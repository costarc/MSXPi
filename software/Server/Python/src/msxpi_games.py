"""Game invitations for MSX Free Chat: a generic way to start an online game from a chat.

Nothing here knows a particular game.  A game is an entry of a registry:

    id         short name used on the wire and in /play (letters, digits, '-')
    title      what the players are shown
    cmd        MSX-DOS command line that starts it, e.g. "SOCCERNET {role}"
               {role} = the seat's role word, {peer} = the opponent's nick, {token} = session id
    roles      one word per seat; seat 0 is whoever sent the invitation
    transport  "netplay"  the two MSXPi machines are connected by msxpi_netplay (UDP, lockstep games)
               "none"     the game brings its own connection; the chat only starts it
    version    protocol version of the game; players with different versions cannot play each other

Built-in games can be extended or replaced in msxpi.ini:
    var MSXGAME_<id>=Title|COMMAND {role}|role0,role1|transport[|version]

Wire format (private IRC messages between the two chat servers, never shown as text):
    MSXG1 INVITE  <game> <version> <token>
    MSXG1 ACCEPT  <token> <candidates>      candidates = ip:port,ip:port | -
    MSXG1 GO      <token> <candidates>
    MSXG1 DECLINE <token> <reason>
    MSXG1 CANCEL  <token>
The invitee accepts and, for a netplay game, opens its UDP port and sends the addresses it can be reached
at; the inviter answers with its own (GO) and both start; the two session objects then punch through the
NAT by talking to each other's candidates at the same time (msxpi_netplay.set_peers).

The MSX is told through the chat: flags() in the packet header, then the "launch" command returns the
command line, which the MSX program stuffs into the keyboard buffer before it returns to MSX-DOS.
"""
import re
import secrets
import time

PROTOCOL = 'MSXG1'
INVITE_TTL = 120.0          # seconds an invitation stays open
LAUNCH_TTL = 180.0          # seconds the game may wait for the MSX to start it
FLAG_LAUNCH, FLAG_INVITED = 1, 2

DEFAULT_GAMES = {
    'soccer': ("Konami's Soccer", 'SOCCERNET {role}', ['H', 'C'], 'netplay', 1),
}
ID_RE = re.compile(r'[a-z0-9][a-z0-9-]{0,15}')
CMD_OK = re.compile(r'[A-Za-z0-9 ._:\-]{1,37}')     # one more byte (Enter) fits the 40-byte keyboard buffer
TOKEN_RE = re.compile(r'[0-9a-f]{8}')
ENDPOINT_RE = re.compile(r'(\d{1,3}(?:\.\d{1,3}){3}):(\d{1,5})')


class Game:
    def __init__(self, gid, title, cmd, roles, transport='netplay', version=1):
        if not ID_RE.fullmatch(gid):
            raise ValueError('bad game id ' + gid)
        if transport not in ('netplay', 'none'):
            raise ValueError('bad transport ' + transport)
        if len(roles) != 2 or not all(re.fullmatch(r'[A-Za-z0-9]{1,8}', r) for r in roles):
            raise ValueError('a game needs two seat roles')
        self.id, self.title, self.cmd = gid, title, cmd
        self.roles, self.transport, self.version = list(roles), transport, int(version)
        self.command(roles[0], 'peer', '00000000')                  # validates the template

    def command(self, role, peer, token):
        line = self.cmd.replace('{role}', role).replace('{peer}', peer).replace('{token}', token)
        if not CMD_OK.fullmatch(line):
            raise ValueError('bad command line for ' + self.id)
        return line


def load_registry(config=None):
    games = {gid: Game(gid, *spec) for gid, spec in DEFAULT_GAMES.items()}
    for key, value in (config or {}).items():
        if key.startswith('MSXGAME_'):
            gid = key[8:].lower()
            parts = value.split('|')
            if len(parts) < 4:
                continue
            try:
                games[gid] = Game(gid, parts[0], parts[1], parts[2].split(','), parts[3],
                                  parts[4] if len(parts) > 4 else 1)
            except ValueError:
                continue
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
        return 'Games: ' + ', '.join(f'{g.id} ({g.title})' for g in self.games.values())

    def play(self, nick, game_id=None):
        self._expire()
        if self.busy:
            raise ValueError('Already in a game or invitation: /cancel first')
        gid = (game_id or ('soccer' if 'soccer' in self.games else next(iter(self.games)))).lower()
        game = self.games.get(gid)
        if not game:
            raise ValueError('Unknown game; ' + self.list_games())
        self.game, self.peer, self.seat = game, nick, 0
        self.token = secrets.token_hex(4)
        self.phase, self.deadline = 'inviting', self.clock() + INVITE_TTL
        self.say(f'Invited {nick} to play {game.title}; waiting for the answer')
        self.send(nick, f'{PROTOCOL} INVITE {game.id} {game.version} {self.token}')

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
        if self.game.transport != 'netplay':
            return '-'
        np = self._netplay()
        np.open()
        found = np.candidates()
        return ','.join(found) if found else '-'

    def _connect(self, candidates):
        if self.game.transport == 'netplay':
            peers = parse_endpoints(candidates)
            if not peers:
                raise ValueError('The other side sent no address')
            np = self._netplay()
            np.version = self.game.version
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
                self._abort()
                self.say(f'{sender} declined the game')
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

    def _on_invite(self, sender, gid, version, token):
        game = self.games.get(gid)
        if not TOKEN_RE.fullmatch(token):
            return
        if self.busy:
            self.send(sender, f'{PROTOCOL} DECLINE {token} busy')
        elif not game:
            self.send(sender, f'{PROTOCOL} DECLINE {token} unknown-game')
        elif str(game.version) != version:
            self.send(sender, f'{PROTOCOL} DECLINE {token} version')
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

    def resumed(self):
        """The player is back in the chat after a game: report how it went and release the session."""
        if self.phase != 'launched':
            return
        peer, np = self.peer, self._np()
        how = np.describe() if np else 'finished'
        self._abort()
        self.say(f'Game with {peer} ended ({how})')
