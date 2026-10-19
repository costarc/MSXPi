"""Game invitations for MSX Free Chat: a generic way to start an online game from a chat.

Specification: documents/PLAYNET-PROTOCOLS.md (MSXG in section 12, the session record in 13, GPF in 8).

Nothing here knows a particular game.  The games are the GPF files in the games folder
(MSXPIHOME/games, one <GAME-ID>.GPF per game, compiled from a ROM-Patcher package).  This module
only reads their 128-byte header:

    game id    what players type (/play NICK soccer) and, in upper case, the file name
    title      what the players are shown
    roles      one word per seat; seat 0 is whoever sent the invitation
    transport  "lockstep": PLAYNET runs the game (the chat types PLAYNET), msxpi_netplay connects the machines
               "none":     the game is its own program; the chat types its command line
    hash       the profile hash (CRC-32 of the file): both players must have the same one

Wire format (private IRC messages between the two chat programs, never shown as text):
    MSXG1 INVITE  <game> <profhash8> <token>
    MSXG1 ACCEPT  <token> <candidates>      candidates = ip:port,ip:port | -
    MSXG1 GO      <token> <candidates>
    MSXG1 DECLINE <token> <reason>          busy | declined | unknown-game | profile | no-mapper
    MSXG1 CANCEL  <token>
The invitee accepts and, for a lockstep game, opens its UDP port and sends the addresses it can be reached
at; the inviter answers with its own (GO) and both start; the two session objects then punch through the
NAT by talking to each other's candidates at the same time (msxpi_netplay.set_peers).

The MSX is told through the chat: flags() in the packet header, then the "launch" command returns the
command line, which the MSX program stuffs into the keyboard buffer before it returns to MSX-DOS.  PLAYNET
then asks for the session record ("playnet session") and reports how the game ended ("playnet result").
"""
import os
import re
import secrets
import struct
import time
import zlib

PROTOCOL = 'MSXG1'
INVITE_TTL = 120.0          # seconds an invitation stays open
LAUNCH_TTL = 180.0          # seconds the game may wait for the MSX to start it
FLAG_LAUNCH, FLAG_INVITED = 1, 2
LAUNCHER = 'PLAYNET'        # what the chat types for a lockstep game (MSXPi link)

GPF_MAGIC = b'GPF1'
GPF_HEADER = 128
GPF_MAX = 16384
ID_RE = re.compile(r'[a-z0-9-]{1,8}')
ROLE_RE = re.compile(r'[A-Za-z0-9]{1,8}')
CMD_OK = re.compile(r'[A-Za-z0-9 ._:/\-]{1,37}')    # one more byte (Enter) fits the 40-byte keyboard buffer
TOKEN_RE = re.compile(r'[0-9a-f]{8}')
HASH_RE = re.compile(r'[0-9a-f]{8}')
ENDPOINT_RE = re.compile(r'(\d{1,3}(?:\.\d{1,3}){3}):(\d{1,5})')

# Result codes (PLAYNET-PROTOCOLS.md 13.2) and how the chat says them
RESULTS = {
    0: 'finished', 1: 'you ended it', 2: 'the opponent ended it', 3: 'connection lost',
    4: 'the machines lost sync', 5: 'could not connect', 6: 'different game versions: update the game',
    7: 'cancelled before the start', 8: 'ROM missing or not the expected dump',
    9: 'not possible on this machine'}
DECLINES = {'busy': 'is busy', 'declined': 'declined the game', 'unknown-game': 'does not have that game',
            'profile': 'has a different version of the game: one of you must update it',
            'no-mapper': 'cannot play it (TCP/IP needs a memory mapper)'}
SESSION_SIZE = 40


class Game:
    def __init__(self, gid, title, roles, transport='lockstep', command='', profhash=0, gpf=b''):
        if not ID_RE.fullmatch(gid):
            raise ValueError('bad game id ' + gid)
        if transport not in ('lockstep', 'none'):
            raise ValueError('bad transport ' + transport)
        if len(roles) != 2 or not all(ROLE_RE.fullmatch(r) for r in roles):
            raise ValueError('a game needs two seat roles')
        self.id, self.title, self.roles, self.transport = gid, title, list(roles), transport
        self.command_template, self.profhash, self.gpf = command, profhash, gpf
        self.command(roles[0], 'peer', '00000000')                  # validates the template

    @property
    def hash_text(self):
        return '%08x' % self.profhash

    def command(self, role, peer, token):
        if self.transport == 'lockstep':
            return LAUNCHER
        line = self.command_template.replace('{role}', role).replace('{peer}', peer).replace('{token}', token)
        if not CMD_OK.fullmatch(line):
            raise ValueError('bad command line for ' + self.id)
        return line


def _text(raw):
    return raw.split(b'\0', 1)[0].decode('ascii')


def read_gpf_header(data):
    """A Game from a GPF file's header.  Checks the magic, the length and the profile hash; the MSX checks
    the rest when it loads the file (PLAYNET-PROTOCOLS.md 8.3)."""
    if len(data) < GPF_HEADER or len(data) > GPF_MAX or data[:4] != GPF_MAGIC or data[4] != 1:
        raise ValueError('not a GPF format 1 file')
    if GPF_HEADER + struct.unpack_from('<H', data, 6)[0] != len(data):
        raise ValueError('GPF length does not match its header')
    stored = struct.unpack_from('<I', data, 8)[0]
    if zlib.crc32(data[:8] + b'\0\0\0\0' + data[12:]) & 0xFFFFFFFF != stored:
        raise ValueError('GPF checksum mismatch')
    return Game(_text(data[12:20]), _text(data[20:44]), [_text(data[44:52]), _text(data[52:60])],
                'lockstep' if data[5] & 1 else 'none', _text(data[60:98]), stored, bytes(data))


def default_games_dir():
    return os.environ.get('MSXPI_GAMES_DIR') or os.path.join(os.environ.get('MSXPI_HOME', '/home/pi/msxpi'), 'games')


def load_registry(folder=None, log=print):
    """Every valid <GAME-ID>.GPF in the folder, keyed by game id."""
    folder = folder or default_games_dir()
    games = {}
    try:
        names = sorted(os.listdir(folder))
    except OSError:
        return games
    for name in names:
        if not name.upper().endswith('.GPF'):
            continue
        try:
            with open(os.path.join(folder, name), 'rb') as stream:
                game = read_gpf_header(stream.read(GPF_MAX + 1))
            if name.upper() != game.id.upper() + '.GPF':
                raise ValueError('the file name must be %s.GPF' % game.id.upper())
            games[game.id] = game
        except (OSError, ValueError) as exc:
            log('games: %s ignored: %s' % (name, exc))
    return games


def parse_endpoints(text):
    found = []
    for item in text.split(','):
        m = ENDPOINT_RE.fullmatch(item.strip())
        if m and 0 < int(m.group(2)) < 65536:
            found.append((m.group(1), int(m.group(2))))
    return found


class Invites:
    """One invitation / game at a time.

    send(nick, text)  deliver a private message;  say(text)  show a line in the chat;
    netplay()         returns the object that connects the machines (msxpi_netplay.Netplay)."""

    def __init__(self, games, send, say, netplay=None, clock=time.monotonic):
        self.games, self.send, self.say, self._netplay, self.clock = games, send, say, netplay, clock
        self.clear()

    # ---- state ---------------------------------------------------------------------
    def clear(self):
        self.phase = 'idle'     # idle | inviting | invited | accepted | ready | launched
        self.game = self.peer = self.token = None
        self.seat = 0
        self.deadline = 0.0
        self.started = False    # PLAYNET has fetched the session record
        self.result = None      # result code PLAYNET reported (13.2)

    @property
    def busy(self):
        return self.phase != 'idle'

    def _expire(self):
        if self.busy and self.phase != 'launched' and self.clock() > self.deadline:
            was = self.phase
            self._abort()
            self.say('Game invitation expired' if was != 'ready' else 'The game was not started in time')

    def _abort(self, notify=None):
        if notify and self.peer:
            self.send(self.peer, f'{PROTOCOL} CANCEL {self.token}')
        np = self._np()
        if np:
            np.close()
        self.clear()

    def _np(self):
        return self._netplay() if self._netplay else None

    def flags(self):
        self._expire()
        return (FLAG_LAUNCH if self.phase == 'ready' else 0) | (FLAG_INVITED if self.phase == 'invited' else 0)

    def status_line(self):
        if self.phase == 'idle':
            return ''
        return f'{self.game.title} with {self.peer}: {self.phase}'

    # ---- what the user types ------------------------------------------------------------
    def list_games(self):
        if not self.games:
            return 'No games installed (the games folder of the MSXPi is empty)'
        return 'Games: ' + ', '.join(f'{g.id} ({g.title})' for g in self.games.values())

    def play(self, nick, game_id=None):
        self._expire()
        if self.busy:
            raise ValueError('Already in a game or invitation: /cancel first')
        if not self.games:
            raise ValueError(self.list_games())
        gid = (game_id or ('soccer' if 'soccer' in self.games else next(iter(self.games)))).lower()
        game = self.games.get(gid)
        if not game:
            raise ValueError('Unknown game; ' + self.list_games())
        self.game, self.peer, self.seat = game, nick, 0
        self.token = secrets.token_hex(4)
        self.phase, self.deadline = 'inviting', self.clock() + INVITE_TTL
        self.say(f'Invited {nick} to play {game.title}; waiting for the answer')
        self.send(nick, f'{PROTOCOL} INVITE {game.id} {game.hash_text} {self.token}')

    def accept(self):
        self._expire()
        if self.phase != 'invited':
            raise ValueError('No invitation to accept')
        mine = self._open()
        self.phase, self.deadline = 'accepted', self.clock() + INVITE_TTL
        self.say(f'Accepted; connecting to {self.peer}...')
        self.send(self.peer, f'{PROTOCOL} ACCEPT {self.token} {mine}')

    def decline(self):
        self._expire()
        if self.phase != 'invited':
            raise ValueError('No invitation to decline')
        self.send(self.peer, f'{PROTOCOL} DECLINE {self.token} declined')
        self.clear()
        self.say('Invitation declined')

    def cancel(self):
        if not self.busy:
            raise ValueError('Nothing to cancel')
        self._abort(notify=True)
        self.say('Game cancelled')

    def _open(self):
        """Prepare this machine's end of the connection; returns the candidates text for the peer."""
        if self.game.transport != 'lockstep':
            return '-'
        np = self._netplay()
        np.open()
        found = np.candidates()
        return ','.join(found) if found else '-'

    def _connect(self, candidates):
        if self.game.transport == 'lockstep':
            peers = parse_endpoints(candidates)
            if not peers:
                raise ValueError('The other side sent no address')
            np = self._netplay()
            np.profile_hash = self.game.profhash
            np.set_peers(peers)

    # ---- what arrives ---------------------------------------------------------------------
    def on_message(self, sender, text):
        """Handle a private "MSXG1 ..." message.  Returns True (it is never shown as chat)."""
        self._expire()
        parts = text.split(' ')
        verb = parts[1] if len(parts) > 1 else ''
        try:
            if verb == 'INVITE' and len(parts) >= 5:
                self._on_invite(sender, parts[2], parts[3], parts[4])
            elif verb in ('ACCEPT', 'GO') and len(parts) >= 4 and self._mine(sender, parts[2]):
                self._on_candidates(verb, parts[3])
            elif verb == 'DECLINE' and len(parts) >= 3 and self._mine(sender, parts[2]):
                reason = parts[3] if len(parts) > 3 else 'declined'
                self._abort()
                self.say(f'{sender} {DECLINES.get(reason, "declined the game")}')
            elif verb == 'CANCEL' and len(parts) >= 3 and self._mine(sender, parts[2]):
                self._abort()
                self.say(f'{sender} cancelled the game')
        except ValueError as exc:
            if self.busy:
                self._abort(notify=True)
            self.say('Game failed: ' + str(exc))
        return True

    def _mine(self, sender, token):
        return self.busy and sender.lower() == self.peer.lower() and token == self.token

    def _on_invite(self, sender, gid, profhash, token):
        game = self.games.get(gid)
        if not TOKEN_RE.fullmatch(token):
            return
        if self.busy:
            self.send(sender, f'{PROTOCOL} DECLINE {token} busy')
        elif not game:
            self.send(sender, f'{PROTOCOL} DECLINE {token} unknown-game')
            self.say(f'{sender} invited you to {gid}, which is not installed here')
        elif not HASH_RE.fullmatch(profhash) or profhash != game.hash_text:
            self.send(sender, f'{PROTOCOL} DECLINE {token} profile')
            self.say(f'{sender} invited you to {game.title}, but your versions differ: one of you must update it')
        else:
            self.game, self.peer, self.token, self.seat = game, sender, token, 1
            self.phase, self.deadline = 'invited', self.clock() + INVITE_TTL
            self.say(f'{sender} invites you to play {game.title}: /accept or /decline')

    def _on_candidates(self, verb, candidates):
        if verb == 'ACCEPT' and self.phase == 'inviting':
            mine = self._open()
            self._connect(candidates)
            self.send(self.peer, f'{PROTOCOL} GO {self.token} {mine}')
        elif verb == 'GO' and self.phase == 'accepted':
            self._connect(candidates)
        else:
            return
        self.phase, self.deadline = 'ready', self.clock() + LAUNCH_TTL
        self.say(f'{self.peer} is ready: the game starts when this program returns to MSX-DOS')

    # ---- hand-over to the MSX -----------------------------------------------------------------
    def take_launch(self):
        """The command line to run, once; None if no game is waiting."""
        self._expire()
        if self.phase != 'ready':
            return None
        line = self.game.command(self.game.roles[self.seat], self.peer, self.token)
        self.phase = 'launched'
        return line

    def session_record(self):
        """The 40-byte session record PLAYNET reads with "playnet session" (13.1); marks the game started.
        None when no game was handed to the MSX."""
        if self.phase != 'launched' or self.game.transport != 'lockstep':
            return None
        self.started = True
        record = bytearray(SESSION_SIZE)
        record[0:4] = b'PNS1'
        record[4:8] = bytes.fromhex(self.token)
        record[8] = self.seat
        record[9] = 0                                    # link: MSXPi
        struct.pack_into('<HI', record, 10, 0, self.game.profhash)
        record[16:24] = self.game.id.upper().encode('ascii').ljust(8, b' ')
        record[24:32] = self.peer[:8].encode('ascii', 'replace').ljust(8, b'\0')
        record[32] = 2 if self.result is not None else 1
        record[33] = self.result or 0
        return bytes(record)

    def report(self, code):
        """PLAYNET's "playnet result <code>"."""
        if self.phase != 'launched':
            raise ValueError('No game in progress')
        if code not in RESULTS:
            raise ValueError('Unknown result code')
        self.result = code

    def resumed(self):
        """The player is back in the chat after a game: report how it went and release the session."""
        if self.phase != 'launched':
            return
        peer, np = self.peer, self._np()
        if self.result is not None:
            how = RESULTS[self.result]
        elif not self.started and self.game.transport == 'lockstep':
            how = 'not started'
        else:
            how = np.describe() if np else 'finished'
        self._abort()
        self.say(f'Game with {peer} ended ({how})')
