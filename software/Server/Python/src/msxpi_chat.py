"""MSX Free Chat: a multi-room IRC chat for the MSX, served by the MSXPi.

Reuses the PChess IRC infrastructure (msxpi_pchess_irc.IRC: config, TLS,
SASL, line sending) and joins the same #msxpi channel by default. The MSX
sends "mchat <command>" and always gets one fixed 256-byte reply.

The server keeps all state (rooms, scrollback, users), so a client can quit
and come back, and so the MSX needs very little memory. Text is wrapped here
to the width the client gives in "mchat start", so the same server serves a
40/51-column MSX1 and an 80-column MSX2.

Commands (client -> server)
  start <nick|-> <width>   connect (or resume), nick '-' = configured/random
  get <room> <abs>         rows of a room from absolute row <abs>
  meta <first>             nick, rooms and the user list from user <first>
  room <index>             make a room current (where "say" goes)
  say <text>               text, or a /command (see HELP below)
  quit                     leave and disconnect

Reply 'M' (CHT1): 4 state (0 connecting 1 ready 2 lost 3 error 4 no session),
5 'M', 6 rooms, 7 rows here, 8-9 first, 10-11 next (of the room asked),
12-19 next of each room (4 x u16), 20 meta version, 21 current room,
24.. rows of (kind, nick length, text[width]).
Reply 'U' (CHT1): 5 'U', 6 rooms, 7 current, 8-9 users, 10 users here,
12-23 nick, 24-71 four 12-byte room names, 72.. 15 users of 12 bytes
(prefix @ or + kept).
Row kinds: 0 text, 1 private in, 2 system, 3 own, 4 action, 5 private out.

Games (msxpi_games.py): /play NICK [GAME], /accept, /decline, /cancel, /games.  Header byte 22 of the
'M' reply carries flags: bit 0 a game is ready to start, bit 1 an invitation is waiting.  The command
"launch" answers with an 'L' packet: 4 state, 5 'L', 6 flag (1 = a command follows), 24.. the MSX-DOS
command line, zero-terminated (PLAYNET for a lockstep game).  The client puts it in the keyboard buffer and
returns to MSX-DOS; running "mchat" again resumes the same chat session and says how the game ended.

PLAYNET's own commands ("playnet ...", documents/PLAYNET-PROTOCOLS.md 15) are answered by playnet_command():
session, profile <id>, save, restore, result <code>.
"""
import collections
import os
import re
import secrets
import socket
import textwrap
import threading
import time

from msxpi_pchess_irc import IRC, fold
from msxpi_games import Invites, load_registry, RESULTS

DEFAULT_ROOM = '#msxpi'
MAX_ROOMS = 4
ROWS_KEPT = 400         # scrollback per room, in wrapped rows
HEADER = 24
MAX_WIDTH = 72
MIN_WIDTH = 20
K_TEXT, K_PRIV_IN, K_SYSTEM, K_OWN, K_ACTION, K_PRIV_OUT = range(6)
NICK_RE = re.compile(r'[A-Za-z\[\]\\`_^{|}][A-Za-z0-9\[\]\\`_^{|}-]{0,15}')
HELP = ('/nick N  /msg N TEXT  /join #ROOM  /part  /me TEXT  /who  /topic  '
        '/play N [GAME]  /accept  /decline  /cancel  /games  /help.  Ctrl-U pick a player to invite, ESC quit')


def clean(text):
    return ''.join(c if ' ' <= c <= '~' else '?' for c in text if c >= ' ' or c == '\t')


class Room:
    def __init__(self, name):
        self.name = name
        self.msgs = collections.deque(maxlen=ROWS_KEPT)   # what was said, unwrapped
        self.rows = collections.deque(maxlen=ROWS_KEPT)   # the same, wrapped for the client
        self.first = 0              # absolute index of rows[0]
        self.users = {}             # folded nick -> display nick with prefix
        self.topic = ''
        self.joined = False

    @property
    def next(self):
        return self.first + len(self.rows)

    @staticmethod
    def wrap(kind, nick_part, text, width):
        lines = textwrap.wrap(clean(nick_part + text), width, subsequent_indent=' ',
                              break_long_words=True, replace_whitespace=True) or ['']
        return [(kind, len(nick_part) if i == 0 else 0, line) for i, line in enumerate(lines)]

    def add(self, kind, nick_part, text, width):
        """Wrap "<nick_part><text>"; the first row carries the nick length."""
        self.msgs.append((kind, nick_part, text))
        for row in self.wrap(kind, nick_part, text, width):
            if len(self.rows) == self.rows.maxlen:
                self.first += 1
            self.rows.append(row)

    def rewrap(self, width):
        """New width (the client changed screen mode): wrap the history again.
        Row numbers restart, so the client must start from the header."""
        self.rows.clear()
        self.first = 0
        for kind, nick_part, text in self.msgs:
            for row in self.wrap(kind, nick_part, text, width):
                if len(self.rows) == self.rows.maxlen:
                    self.first += 1
                self.rows.append(row)

    def user_list(self):
        def order(display):
            return ({'@': 0, '%': 1, '+': 2}.get(display[0], 3), display.lstrip('@%+').lower())
        return sorted(self.users.values(), key=order)


class ChatIRC(IRC):
    """The IRC transport of PChess, with a chat reader instead of the game's."""

    def __init__(self, config, room, width, netplay=None):
        self.invites = Invites(load_registry(config.get('GAMESDIR')), self.send_game, self.say_system, netplay)
        self.width = max(MIN_WIDTH, min(MAX_WIDTH, width))
        self.rooms = [Room(room)]
        self.cur = 0
        self.meta = 0
        self.state_lock = threading.RLock()
        self.registered = False
        self.lost = False
        super().__init__(config)

    # -------------------------------------------------------------- state
    def find(self, name):
        key = fold(name)
        for room in self.rooms:
            if fold(room.name) == key: return room
        return None

    def set_width(self, width):
        width = max(MIN_WIDTH, min(MAX_WIDTH, width))
        with self.state_lock:
            if width != self.width:
                self.width = width
                for room in self.rooms: room.rewrap(width)
                self.meta = (self.meta + 1) & 255

    def say_system(self, text, room=None):
        with self.state_lock:
            (room or self.rooms[self.cur]).add(K_SYSTEM, '', text, self.width)

    def post(self, room, kind, nick_part, text):
        with self.state_lock:
            room.add(kind, nick_part, text, self.width)

    def send_game(self, nick, text):
        """Private game-control message to another chat (never shown as chat)."""
        self.message(nick, text)

    def set_user(self, room, nick, prefix=''):
        room.users[fold(nick)] = prefix + nick
        self.meta = (self.meta + 1) & 255

    def drop_user(self, room, nick):
        if room.users.pop(fold(nick), None) is not None:
            self.meta = (self.meta + 1) & 255

    # ------------------------------------------------------------- reader
    def reader(self):
        buffer = b''
        try:
            while True:
                try: data = self.sock.recv(4096)
                except socket.timeout: continue
                if not data: raise ConnectionError('Disconnected from the server')
                buffer += data
                if len(buffer) > 16384: raise ValueError('Server message too large')
                while b'\n' in buffer:
                    raw, buffer = buffer.split(b'\n', 1)
                    line = raw.decode('utf-8', 'replace').rstrip('\r')
                    if line.startswith('@'): line = line.split(' ', 1)[1]
                    if line.startswith('PING '): self.line('PONG ' + line[5:]); continue
                    parts = line.split(' ', 3)
                    if self.authenticate(line, parts): continue
                    if line.startswith('ERROR '): raise ConnectionError(line[:150])
                    with self.state_lock: self.dispatch(line, parts)
        except Exception as exc:
            if not self.closed:
                self.error = str(exc) or exc.__class__.__name__
                self.lost = True
                self.say_system('Connection lost: ' + self.error)
        finally:
            self.password = ''
            try: self.sock.close()
            except OSError: pass

    def dispatch(self, line, parts):
        if len(parts) < 2: return
        sender = parts[0][1:].split('!', 1)[0] if parts[0].startswith(':') else ''
        cmd = parts[1]
        rest = parts[2] if len(parts) > 2 else ''
        tail = parts[3] if len(parts) > 3 else ''
        if cmd == '001':
            self.nick = rest
            self.registered = True
            self.ready = True
            self.meta += 1
            for room in self.rooms: self.line('JOIN ' + room.name)
        elif cmd == '433' and not self.registered:
            self.nick = (self.nick + '_')[:16]
            self.line('NICK ' + self.nick)
        elif cmd == '433':
            self.say_system('Nick already in use')
        elif cmd == 'NICK':
            new = rest.lstrip(':')
            for room in self.rooms:
                old = room.users.pop(fold(sender), None)
                if old is not None:
                    self.set_user(room, new, old[:len(old) - len(sender)])
                    self.post(room, K_SYSTEM, '', f'{sender} is now {new}')
            if fold(sender) == fold(self.nick):
                self.nick = new
                self.meta += 1
        elif cmd == 'JOIN':
            room = self.find(rest.lstrip(':'))
            if not room: return
            if fold(sender) == fold(self.nick):
                room.joined = True
                room.users.clear()
                self.post(room, K_SYSTEM, '', 'Joined ' + room.name)
            else:
                self.set_user(room, sender)
                self.post(room, K_SYSTEM, '', sender + ' joined')
        elif cmd in ('PART', 'KICK'):
            room = self.find(rest)
            if not room: return
            gone = sender if cmd == 'PART' else tail.split(' ', 1)[0]
            self.drop_user(room, gone)
            if cmd == 'KICK':
                self.post(room, K_SYSTEM, '', f'{gone} was kicked by {sender}')
            elif fold(sender) != fold(self.nick):
                self.post(room, K_SYSTEM, '', sender + ' left')
        elif cmd == 'QUIT':
            for room in self.rooms:
                if fold(sender) in room.users:
                    self.drop_user(room, sender)
                    self.post(room, K_SYSTEM, '', sender + ' quit')
        elif cmd == '353':       # :srv 353 me = #chan :@op +v nick
            params, _, names = tail.partition(' :')
            room = self.find(params.split()[-1]) if params.split() else None
            if room:
                for name in names.split():
                    prefix = ''
                    while name and name[0] in '@%+~&': prefix = prefix or ('@' if name[0] in '~&@' else name[0]); name = name[1:]
                    if name: self.set_user(room, name, prefix)
        elif cmd == '332':
            params, _, topic = tail.partition(' :')
            room = self.find(params.strip())
            if room:
                room.topic = topic
                self.post(room, K_SYSTEM, '', 'Topic: ' + topic)
        elif cmd in ('PRIVMSG', 'NOTICE'):
            text = tail[1:] if tail.startswith(':') else tail
            if text.startswith('PCH1 '): return        # PChess game traffic
            if text.startswith('MSXG1 '):               # game invitations (msxpi_games)
                if not rest.startswith('#'): self.invites.on_message(sender, text)
                return
            kind, body = K_TEXT, text
            if text.startswith('\x01ACTION ') and text.endswith('\x01'):
                kind, body = K_ACTION, text[8:-1]
            elif text.startswith('\x01'):
                return                                  # other CTCP: ignore
            if rest.startswith('#') or rest.startswith('&'):
                room = self.find(rest)
                if not room: return
                if kind == K_ACTION: self.post(room, kind, f'* {sender} ', body)
                else: self.post(room, kind, f'{sender}: ' if cmd == 'PRIVMSG' else f'-{sender}- ', body)
            elif '.' in sender or not sender:
                if self.registered: self.say_system(text)   # server notice
            else:
                label = f'*{sender}* ' if kind != K_ACTION else f'* {sender} '
                self.post(self.rooms[self.cur], K_PRIV_IN, label, body)
        elif cmd.isdigit() and int(cmd) >= 400 and cmd != '433':
            self.say_system(clean(tail.split(' :', 1)[-1] or cmd))
        elif cmd == 'KILL' or cmd == 'ERROR':
            raise ConnectionError(clean(tail or cmd))

    # ----------------------------------------------------------- commands
    def send_room(self, room, text, action=False):
        if not self.ready: raise ValueError('Not connected yet; wait')
        self.message(room, '\x01ACTION ' + text + '\x01' if action else text)

    def say(self, text):
        text = clean(text).strip()
        if not text: return
        if not text.startswith('/'):
            room = self.rooms[self.cur]
            self.send_room(room.name, text)
            self.post(room, K_OWN, f'{self.nick}: ', text)
            return
        cmd, _, arg = text[1:].partition(' ')
        cmd, arg = cmd.lower(), arg.strip()
        room = self.rooms[self.cur]
        if cmd in ('msg', 'm', 'query', 'q'):
            target, _, body = arg.partition(' ')
            if not target or not body.strip(): raise ValueError('Use /msg NICK TEXT')
            self.send_room(target, body.strip())
            self.post(room, K_PRIV_OUT, f'->{target}: ', body.strip())
        elif cmd == 'me':
            if not arg: raise ValueError('Use /me TEXT')
            self.send_room(room.name, arg, action=True)
            self.post(room, K_ACTION, f'* {self.nick} ', arg)
        elif cmd == 'nick':
            if not NICK_RE.fullmatch(arg): raise ValueError('Invalid nick')
            self.line('NICK ' + arg)
        elif cmd in ('join', 'j'):
            name = arg.split()[0] if arg else ''
            if not name: raise ValueError('Use /join #ROOM')
            if not name.startswith('#'): name = '#' + name
            if not re.fullmatch(r'#[A-Za-z0-9_.\-]{1,30}', name): raise ValueError('Invalid room name')
            existing = self.find(name)
            if existing:
                self.cur = self.rooms.index(existing)
            else:
                if len(self.rooms) >= MAX_ROOMS: raise ValueError(f'At most {MAX_ROOMS} rooms; /part one first')
                self.rooms.append(Room(name))
                self.cur = len(self.rooms) - 1
                if self.ready: self.line('JOIN ' + name)
            self.meta += 1
        elif cmd in ('part', 'leave'):
            if len(self.rooms) < 2: raise ValueError('Cannot leave the only room')
            self.line('PART ' + room.name)
            del self.rooms[self.cur]
            self.cur = max(0, self.cur - 1)
            self.meta += 1
        elif cmd == 'who':
            names = [u for u in room.user_list()]
            self.say_system(f'{len(names)} in {room.name}: ' + ' '.join(names))
        elif cmd == 'topic':
            self.say_system('Topic: ' + (room.topic or '(none)'))
        elif cmd == 'play':
            nick, _, game = arg.partition(' ')
            if not nick: raise ValueError('Use /play NICK [GAME]; ' + self.invites.list_games())
            if fold(nick) == fold(self.nick): raise ValueError('Pick somebody else')
            self.invites.play(nick, game.strip() or None)
        elif cmd == 'accept':
            self.invites.accept()
        elif cmd == 'decline':
            self.invites.decline()
        elif cmd == 'cancel':
            self.invites.cancel()
        elif cmd == 'games':
            self.say_system(self.invites.list_games())
        elif cmd in ('help', '?'):
            self.say_system(HELP)
        else:
            raise ValueError('Unknown command; /help')

    # ------------------------------------------------------------ packets
    def state_byte(self):
        if self.lost: return 2
        return 1 if self.ready else 0

    def rows_packet(self, index, start):
        with self.state_lock:
            data = bytearray(256)
            data[:4] = b'CHT1'
            data[4] = self.state_byte()
            data[5] = ord('M')
            data[6] = len(self.rooms)
            room = self.rooms[index if 0 <= index < len(self.rooms) else self.cur]
            slot = 2 + self.width
            start = max(start, room.first)
            count = min(max(room.next - start, 0), (256 - HEADER) // slot)
            data[7] = count
            data[8:10] = room.first.to_bytes(2, 'little')
            data[10:12] = (room.next & 0xFFFF).to_bytes(2, 'little')
            for i, r in enumerate(self.rooms):
                data[12 + i * 2:14 + i * 2] = (r.next & 0xFFFF).to_bytes(2, 'little')
            data[20] = self.meta & 255
            data[21] = self.cur
            data[22] = self.invites.flags()
            for i in range(count):
                kind, nicklen, text = room.rows[start - room.first + i]
                at = HEADER + i * slot
                data[at] = kind
                data[at + 1] = nicklen
                data[at + 2:at + 2 + len(text)] = text.encode('ascii', 'replace')
            return bytes(data)

    def meta_packet(self, first):
        with self.state_lock:
            data = bytearray(256)
            data[:4] = b'CHT1'
            data[4] = self.state_byte()
            data[5] = ord('U')
            data[6] = len(self.rooms)
            data[7] = self.cur
            users = self.rooms[self.cur].user_list()
            data[8:10] = len(users).to_bytes(2, 'little')
            here = users[first:first + 15]
            data[10] = len(here)
            data[12:12 + 11] = self.nick[:11].encode('ascii', 'replace').ljust(11, bytes(1))
            for i, room in enumerate(self.rooms):
                data[24 + i * 12:24 + i * 12 + 11] = room.name[:11].encode('ascii', 'replace').ljust(11, bytes(1))
            for i, name in enumerate(here):
                data[72 + i * 12:72 + i * 12 + 11] = name[:11].encode('ascii', 'replace').ljust(11, bytes(1))
            return bytes(data)


_chat = None


def default_netplay():
    """The session object the MSX transaction (opcode C9) talks to."""
    import msxpi_netplay
    return msxpi_netplay.instance()


def no_session(message='Not started'):
    data = bytearray(256)
    data[:4] = b'CHT1'
    data[4] = 4
    data[5] = ord('M')
    data[HEADER + 2:HEADER + 2 + len(message)] = message.encode('ascii')
    return bytes(data)


def launch_packet(chat):
    """'L' reply: the command line of a game that is ready, once."""
    data = bytearray(256)
    data[:4] = b'CHT1'
    data[4] = chat.state_byte()
    data[5] = ord('L')
    line = chat.invites.take_launch()
    if line:
        data[6] = 1
        data[HEADER:HEADER + len(line)] = line.encode('ascii')
    return bytes(data)


SAVE_MAX = 16384 + 256      # the saved DOS area (HIMEM-FFFFh, at most 16 KB) plus PLAYNET's own header
_saved = None               # (token, bytes) kept by "playnet save" for "playnet restore"


def playnet_command(command, upload=None, games_dir=None):
    """One "playnet ..." command from PLAYNET (PLAYNET-PROTOCOLS.md 15).  Returns (ok, payload): payload is
    the reply on success, or the message to show on failure.  upload: the bytes the MSX sent ("save")."""
    global _saved
    args = command.split()
    op = args[0] if args else ''
    invites = _chat.invites if _chat else None
    token = invites.token if invites and invites.phase == 'launched' else None
    if op == 'session':
        record = invites.session_record() if invites else None
        if not record:
            return False, 'No game is waiting: start it from MCHAT'
        return True, record
    if op == 'profile' and len(args) == 2:
        games = invites.games if invites else load_registry(games_dir)
        game = games.get(args[1].lower())
        if not game or game.transport != 'lockstep':
            return False, 'Game %s is not installed on the MSXPi' % args[1]
        return True, game.gpf
    if op == 'save':
        if not token:
            return False, 'No game in progress'
        if not upload or len(upload) > SAVE_MAX:
            return False, 'Nothing to save, or more than %d bytes' % SAVE_MAX
        _saved = (token, bytes(upload))
        return True, b'OK'
    if op == 'restore':
        if not _saved:
            return False, 'Nothing saved'
        data, _saved = _saved[1], None
        return True, data
    if op == 'result' and len(args) == 2:
        try:
            code = int(args[1])
            if not invites:
                raise ValueError('No game in progress')
            invites.report(code)
        except ValueError as exc:
            return False, str(exc)
        return True, b'OK'
    return False, 'Use playnet session|profile ID|save|restore|result CODE'


def error_packet(message):
    """A session-less error: state 3, text at the first row."""
    data = bytearray(no_session())
    data[4] = 3
    text = clean(message)[:60].encode('ascii', 'replace')
    data[HEADER + 2:HEADER + 2 + 60] = bytes(60)
    data[HEADER + 2:HEADER + 2 + len(text)] = text
    return bytes(data)


def handle_command(command, irc_config=None):
    """Return the 256-byte reply for one "mchat" command."""
    global _chat
    try:
        args = command.split()
        if not args: raise ValueError('mchat start|get|meta|room|say|quit')
        op = args[0]
        if op == 'start':
            nick = args[1] if len(args) > 1 else '-'
            width = int(args[2]) if len(args) > 2 else 40
            if _chat and not _chat.error and not _chat.closed:
                _chat.set_width(width)
                _chat.invites.resumed()
                return _chat.rows_packet(_chat.cur, 1 << 30)
            config = dict(irc_config or {})
            if nick != '-': config['IRCNICK'] = nick
            elif not config.get('IRCNICK') and not os.environ.get('PCHESS_IRC_NICK'):
                config['IRCNICK'] = 'msx' + secrets.token_hex(2)
            if _chat: _chat.close()
            _chat = ChatIRC(config, config.get('MCHATROOM') or DEFAULT_ROOM, width, netplay=default_netplay)
            _chat.say_system('Connecting...')
            return _chat.rows_packet(0, 1 << 30)
        if op == 'quit':
            if _chat: _chat.close()
            _chat = None
            return no_session('Closed')
        if _chat is None: return no_session()
        chat = _chat
        if op == 'launch':
            return launch_packet(chat)
        if op == 'get':
            return chat.rows_packet(int(args[1]), int(args[2]))
        if op == 'meta':
            return chat.meta_packet(int(args[1]) if len(args) > 1 else 0)
        if op == 'room':
            index = int(args[1])
            if 0 <= index < len(chat.rooms):
                chat.cur = index
                chat.meta += 1
            return chat.rows_packet(chat.cur, 1 << 30)
        if op == 'say':
            if chat.error and not chat.ready: raise ValueError(chat.error)
            try: chat.say(command.partition(' ')[2])
            except ValueError as exc: chat.say_system('! ' + str(exc))
            except OSError as exc: chat.say_system('! Send failed: ' + str(exc))
            return chat.rows_packet(chat.cur, 1 << 30)
        raise ValueError('Unknown mchat command')
    except Exception as exc:
        return error_packet(str(exc))
