"""PCH1 CK IRC protocol for PCheckers: the checkers twin of msxpi_pchess_irc.Peer.

It runs on the same IRC class (connection, lobby/room channels, chat queue),
so PCheckers on the MSXPi link gets IRC rooms, the lobby and chat exactly as
PChess does, and plays against PCheckers on the TCP/IP link, which speaks the
same lines (pcheckers_tcp.c). The channels are PChess's own: the lobby
#msxpi and a room #pchess-<room>, so chess and checkers players read the
same public talk and only the game is private. Game lines start with
"PCH1 CK": PChess ignores them (its unknown-op rule), so they never show up
as chat there. They go to one nick except HELLO and SEEK:

  #pchess-<room>   PCH1 CK HELLO            I joined. Answered with HERE (or BUSY).
  nick             PCH1 CK HERE / BUSY      The answer. Both sides pair; the lower
                                         folded nick plays white.
  #msxpi           PCH1 CK SEEK             I am looking for a game.
  nick             PCH1 CK OFFER            An invitation: the sender plays white.
  nick             PCH1 CK ACCEPT           The invitation is taken: I play black.
  nick             PCH1 CK MOVE <n> <path>  Move number n (from 0), e.g. c3e5g7.
  nick             PCH1 CK DRAW / RESIGN    As the menu entries.
  nick             PCH1 CK RESET            A rematch: both clear the game.
  nick             PCH1 CK SYNC <n>         After a reconnect: I hold n moves. The one
                                         with more resends the missing MOVE lines;
                                         the one with fewer answers with its own SYNC.

The rules are the MSX clients' business: moves are only checked for form and
order here. IRC is reliable while connected, so there are no acknowledgements;
a dropped IRC link is repaired by SYNC."""
import collections
import re
import textwrap
import time

from msxpi_pchess_irc import CHAT_QUEUE, PLAYER_TTL, chat_rows, chat_text, fold

PATH = re.compile(r'(?:[a-h][1-8]){2,13}')
NICK = re.compile(r'[A-Za-z][A-Za-z0-9_-]{0,15}')
# Moves handed to the MSX per poll (the packet has room for eight).
FETCH = 8


class CheckersPeer:
    PREFIX = 'PCH1 '
    LOBBY = '#msxpi'

    def __init__(self, nick, send, room=None):
        self.nick = nick
        self.send = send
        self.room = room            # '#pdamas-<room>' in a room, else None
        self.peer = None
        self.phase = 'lobby'        # lobby, offered, playing, error
        self.side = 0               # 0 white, 1 black
        self.status = 'LOBBY'
        self.invite = None
        self.players = {}
        self.last_seek = -1000
        self.chat = collections.deque(maxlen=CHAT_QUEUE)
        self.offline = False        # our IRC link is down and being re-established
        self.new_game()

    # -- state ------------------------------------------------------------
    def new_game(self):
        self.moves = []
        self.draw_offer = None      # 'me' or 'peer'
        self.result = 0             # 1 white wins, 2 black wins, 3 draw

    def channel(self):
        return self.room or self.LOBBY

    def free(self):
        return self.phase in ('lobby', 'error') or (self.phase == 'playing' and self.result != 0)

    def pair(self, nick, side):
        self.peer, self.phase, self.side = nick, 'playing', side
        self.new_game()
        self.status = 'YOU ARE ' + ('BLACK' if side else 'WHITE')

    def pair_by_name(self, nick):
        # The lower nick plays white, so both ends agree without a message.
        self.pair(nick, 0 if fold(self.nick) < fold(nick) else 1)

    def seen(self, nick):
        for name in list(self.players):
            if fold(name) == fold(nick):
                del self.players[name]
        if len(self.players) >= 64:
            self.players.pop(next(iter(self.players)))
        self.players[nick] = time.monotonic()

    def recent_players(self, max_age=PLAYER_TTL):
        now = time.monotonic()
        return [n for n, when in reversed(self.players.items())
                if now - when < max_age and fold(n) != fold(self.nick)]

    # -- commands from the MSX -------------------------------------------
    def announce_room(self):
        if not self.free() and self.phase != 'playing':
            raise ValueError('Already in a match')
        self.send(self.room, 'PCH1 CK HELLO')
        self.status = ('ROOM ' + self.room[len('#pchess-'):] + ' - WAITING').upper()[:47]

    def seek(self):
        if self.room:
            raise ValueError('In a room; no lobby')
        if not self.free():
            raise ValueError('Already in a match')
        if time.monotonic() - self.last_seek < 60:
            raise ValueError('Wait before announcing again')
        self.send(self.LOBBY, 'PCH1 CK SEEK')
        self.last_seek = time.monotonic()
        self.status = 'SEEK SENT'

    def offer(self, nick):
        if not NICK.fullmatch(nick):
            raise ValueError('Invalid nickname')
        if not self.free() or fold(nick) == fold(self.nick):
            raise ValueError('Cannot challenge now')
        self.peer, self.phase = nick, 'offered'
        self.new_game()
        self.send(nick, 'PCH1 CK OFFER')
        self.status = 'INVITE SENT'

    def accept(self):
        if not self.free() or not self.invite:
            raise ValueError('No invitation')
        nick, self.invite = self.invite, None
        self.pair(nick, 1)
        self.send(nick, 'PCH1 CK ACCEPT')

    def playing(self):
        if self.phase != 'playing':
            raise ValueError('Waiting for opponent')
        if self.result:
            raise ValueError('Game over')

    def cmove(self, ply, path):
        self.playing()
        path = path.lower()
        if not PATH.fullmatch(path):
            raise ValueError('Bad move')
        if ply != len(self.moves):
            raise ValueError('Out of sync; poll')
        if len(self.moves) % 2 != self.side:
            raise ValueError('Opponent turn')
        self.send(self.peer, f'PCH1 CK MOVE {ply} {path}')
        self.moves.append(path)
        if self.draw_offer == 'peer':
            self.draw_offer = None

    def draw(self):
        self.playing()
        self.send(self.peer, 'PCH1 CK DRAW')
        if self.draw_offer == 'peer':
            self.result = 3
        else:
            self.draw_offer = 'me'

    def resign(self):
        self.playing()
        self.send(self.peer, 'PCH1 CK RESIGN')
        self.result = 1 if self.side else 2

    def reset(self):
        if self.phase != 'playing':
            raise ValueError('Waiting for opponent')
        self.send(self.peer, 'PCH1 CK RESET')
        self.new_game()

    def say(self, text):
        text = chat_text(text)
        if not text:
            raise ValueError('Nothing to say')
        # A chat line must never be mistaken for a game message.
        if text.startswith('PCH1'):
            text = ' ' + text
        self.send(self.peer if self.peer and self.phase == 'playing' else self.channel(), text)

    def take_chat(self, count=5):
        rows = [self.chat.popleft() for _ in range(min(count, len(self.chat)))]
        return rows, len(self.chat)

    def tick(self):
        pass

    def link_restored(self):
        """The IRC link is back: lines may have been lost in either direction."""
        if self.peer and self.phase == 'playing':
            self.send(self.peer, f'PCH1 CK SYNC {len(self.moves)}')

    def no_such_nick(self, nick):
        if self.peer and fold(nick) == fold(self.peer) and self.phase == 'offered':
            self.peer, self.phase = None, 'lobby'
        self.status = (nick + ': No such nick')[:47]
        for name in list(self.players):
            if fold(name) == fold(nick):
                del self.players[name]

    # -- lines from IRC ---------------------------------------------------
    def chat_in(self, sender, target, text):
        if fold(sender) == fold(self.nick):
            return
        private = fold(target) == fold(self.nick) and self.peer and fold(sender) == fold(self.peer)
        if not private and fold(target) != fold(self.channel()):
            return
        text = chat_text(text)
        if text:
            self.chat.extend((int(bool(private)), row) for row in chat_rows(sender, text))

    def receive(self, sender, target, text):
        fields = text.split()
        if len(fields) < 3 or fields[:2] != ['PCH1', 'CK'] or fold(sender) == fold(self.nick):
            return
        fields = fields[1:]         # [CK, op, ...]: the indexes below count from CK
        op = fields[1]
        same_peer = self.peer is not None and fold(sender) == fold(self.peer)
        if self.room and fold(target) == fold(self.room):
            if op == 'HELLO' and len(fields) == 2:
                if not self.peer or same_peer or self.free():
                    self.send(sender, 'PCH1 CK HERE')
                    self.pair_by_name(sender)
                else:
                    self.send(sender, 'PCH1 CK BUSY')
            return
        if fold(target) == fold(self.LOBBY):
            if not self.room and op == 'SEEK' and len(fields) == 2 and self.free():
                self.seen(sender)
                self.status = 'PLAYER ' + sender + ' WANTS TO PLAY'
            return
        if fold(target) != fold(self.nick):
            return
        if op == 'OFFER' and len(fields) == 2 and not self.room:
            self.seen(sender)
            if self.free() or same_peer:
                self.invite = sender
                self.status = 'INVITE ' + sender + ' PRESS 8'
        elif op == 'ACCEPT' and len(fields) == 2:
            if self.phase == 'offered' and same_peer:
                self.pair(sender, 0)
        elif op == 'HERE' and len(fields) == 2 and self.room:
            if not self.peer or same_peer or self.free():
                self.pair_by_name(sender)
        elif op == 'BUSY' and len(fields) == 2 and self.room:
            if self.phase != 'playing':
                self.status = 'ROOM BUSY - GAME IN PROGRESS'
        elif same_peer and self.phase == 'playing':
            self.game_line(op, fields)

    def game_line(self, op, fields):
        if op == 'MOVE' and len(fields) == 4 and not self.result:
            ply, path = fields[2], fields[3]
            if (not ply.isdigit() or int(ply) != len(self.moves) or not PATH.fullmatch(path)
                    or len(self.moves) % 2 == self.side):
                self.status = 'OUT OF SYNC - REJOIN THE ROOM'
                return
            self.moves.append(path)
            if self.draw_offer == 'me':
                self.draw_offer = None
        elif op == 'DRAW' and len(fields) == 2 and not self.result:
            if self.draw_offer == 'me':
                self.result = 3
            else:
                self.draw_offer = 'peer'
        elif op == 'RESIGN' and len(fields) == 2 and not self.result:
            self.result = 2 if self.side else 1     # the peer is the other colour
        elif op == 'RESET' and len(fields) == 2:
            self.new_game()
        elif op == 'SYNC' and len(fields) == 3 and fields[2].isdigit():
            theirs = int(fields[2])
            if theirs < len(self.moves):
                for ply in range(theirs, len(self.moves)):
                    self.send(self.peer, f'PCH1 CK MOVE {ply} {self.moves[ply]}')
            elif theirs > len(self.moves):
                self.send(self.peer, f'PCH1 CK SYNC {len(self.moves)}')

    # -- state for the MSX --------------------------------------------------
    def snapshot(self, since=None):
        matched = self.phase == 'playing'
        since = len(self.moves) if since is None else min(since, len(self.moves))
        status = self.status
        if matched and not self.result:
            status = 'YOU ARE ' + ('BLACK' if self.side else 'WHITE')
        if self.offline:
            status = 'IRC LINK LOST - RECONNECTING'
        return dict(kind='checkers', matched=matched, side=self.side, over=self.result,
                    status=status[:47], ply=len(self.moves),
                    moves=self.moves[since:since + FETCH],
                    offer=1 if self.draw_offer == 'peer' else 2 if self.draw_offer == 'me' else 0,
                    chat_unread=len(self.chat))
