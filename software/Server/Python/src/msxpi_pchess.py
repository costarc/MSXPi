"""PChess rules, bounded local AI, and optional shared-room relay.

Install requirements-pchess.txt. Choosing ROOM mode starts a relay inside
this server (msxpi.ini PCHESSLISTEN/PCHESSPORT); any other mode stops it.
PCHESSRELAY names the relay both players share: empty means this server's
own relay, otherwise http://HOST:PORT of the MSXPi hosting the room. The
module can still run standalone with --listen to host a dedicated relay.
PCHESSROOMS=irc makes ROOM a #pchess-<room> IRC channel instead (see
msxpi_pchess_irc.py), which MSX machines on TCP/IP UNAPI can join too.

The AI opponent is Stockfish when it is installed (PCHESSENGINE, PCHESSELO,
PCHESSMOVETIME in msxpi.ini); otherwise a small built-in search plays.
"""
import argparse
import collections
import json
import os
import re
import secrets
import shutil
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen

import chess
import chess.engine

from msxpi_pchess_irc import CHAT_QUEUE, CHAT_ROW, chat_rows, chat_text
from msxpi_pcheckers_irc import CheckersPeer


CHECKERS_ACTIONS = ('cmove', 'cdraw', 'cresign', 'creset', 'cpoll')
# Moves handed over per poll; a client further behind polls again.
CHECKERS_FETCH = 8


class Games:
    def __init__(self):
        self.games = {}
        self.lock = threading.RLock()

    def request(self, req):
        with self.lock:
            return self._request(req)

    def _request(self, req):
        action = req.get('action', '')
        if action == 'new':
            mode = req.get('mode', 'local')
            if mode not in ('local', 'ai', 'room'):
                raise ValueError('Unknown game mode')
            now = time.monotonic()
            self.games = {k:v for k,v in self.games.items() if now-v['seen'] < 86400}
            room = req.get('room', '').lower()
            if mode == 'room' and (not room or len(room)>16 or not room.isalnum()):
                raise ValueError('Room: 1-16 letters or digits')
            checkers = req.get('kind') == 'checkers'
            if checkers and mode != 'room':
                raise ValueError('Checkers are played in rooms')
            game_id = ('ckr-' if checkers else 'room-') + room if mode == 'room' else secrets.token_hex(8)
            if game_id not in self.games:
                if len(self.games) >= 128:
                    raise ValueError('Relay full')
                # A checkers room keeps only the moves, as the paths its
                # players typed: the MSX clients hold the rules and check
                # every move they receive.
                self.games[game_id] = dict(board=None if checkers else chess.Board(), mode=mode,
                    players=[], history=[], seen=now, resigned=None,
                    offers=set(), agreed=False, chat={},
                    human_black=mode == 'ai' and bool(req.get('black')),
                    kind='checkers' if checkers else 'chess', moves=[])
            game = self.games[game_id]
            if len(game['players']) >= (2 if mode == 'room' else 1):
                raise ValueError('Room full; choose another')
            token = secrets.token_hex(16)
            game['players'].append(token)
            game['chat'][token] = collections.deque(maxlen=CHAT_QUEUE)
            if game['human_black']:
                # Human plays black: the AI opens as white.
                move = ai_move(game['board'])
                game['history'].append(game['board'].san(move))
                game['board'].push(move)
            result = self.snapshot(game, token)
            result.update(game=game_id, token=token)
            return result
        game = self.games.get(req.get('game'))
        token = req.get('token')
        if game is None or token not in game['players']:
            raise ValueError('Game not found; start new')
        game['seen'] = time.monotonic()
        board = game['board']
        side = game['players'].index(token) == 0 and not game['human_black']
        if (game['kind'] == 'checkers') != (action in CHECKERS_ACTIONS) and action not in ('say', 'chat'):
            raise ValueError('Not a %s game' % game['kind'])
        if action == 'cmove':
            self.checkers_move(game, token, side, req)
        elif action == 'cdraw':
            self.checkers_over_check(game)
            if len(game['players']) < 2:
                raise ValueError('Waiting for opponent')
            if (not side) in game['offers']:
                game['agreed'] = True
            else:
                game['offers'].add(side)
        elif action == 'cresign':
            self.checkers_over_check(game)
            game['resigned'] = side
        elif action == 'creset':
            # The clients end a game by the rules themselves, so only the
            # rematch menu (offered once a game is over) sends this.
            if len(game['players']) < 2:
                raise ValueError('Waiting for opponent')
            game.update(moves=[], resigned=None, agreed=False, offers=set())
        elif action == 'cpoll':
            return self.snapshot(game, token, max(0, int(req.get('ply', 0))))
        elif action == 'move':
            if self.finished(game):
                raise ValueError('Game over')
            if game['mode'] == 'room' and len(game['players']) < 2:
                raise ValueError('Waiting for opponent')
            if game['mode'] != 'local' and board.turn != side:
                raise ValueError('Opponent turn')
            notation = req.get('move', '').strip()
            try:
                move = board.parse_uci(notation.lower().replace('-', ''))
            except ValueError:
                move = board.parse_san(notation)
            game['history'].append(board.san(move))
            board.push(move)
            # Moving declines the opponent's draw offer; one's own stays.
            game['offers'].discard(board.turn)
            if game['mode'] == 'ai' and not self.finished(game):
                move = ai_move(board)
                game['history'].append(board.san(move))
                board.push(move)
        elif action == 'resign':
            if self.finished(game):
                raise ValueError('Game over')
            game['resigned'] = board.turn if game['mode'] == 'local' else side
        elif action == 'draw':
            if self.finished(game):
                raise ValueError('Game over')
            if game['mode'] == 'local':
                game['agreed'] = True
            elif game['mode'] == 'ai':
                if not ai_accepts_draw(board, not side):
                    raise ValueError('AI DECLINES THE DRAW')
                game['agreed'] = True
            else:
                if len(game['players']) < 2:
                    raise ValueError('Waiting for opponent')
                if (not side) in game['offers']:
                    game['agreed'] = True
                elif board.turn != side:
                    raise ValueError('Offer a draw on your move')
                else:
                    game['offers'].add(side)
        elif action == 'say':
            if game['mode'] != 'room' or len(game['players']) < 2:
                raise ValueError('NO ONE TO CHAT WITH')
            text = chat_text(req.get('text', ''))
            if not text:
                raise ValueError('Nothing to say')
            rows = chat_rows('WHITE' if side else 'BLACK', text)
            for other in game['players']:
                if other != token:
                    game['chat'][other].extend((1, row) for row in rows)
        elif action == 'chat':
            queued = game['chat'][token]
            result = self.snapshot(game, token)
            result['chat_rows'] = [queued.popleft() for _ in range(min(5, len(queued)))]
            result['chat_unread'] = len(queued)
            return result
        elif action != 'poll':
            raise ValueError('Unknown action')
        return self.snapshot(game, token)

    @staticmethod
    def checkers_finished(game):
        return game['resigned'] is not None or game['agreed']

    def checkers_over_check(self, game):
        if self.checkers_finished(game):
            raise ValueError('Game over')

    def checkers_move(self, game, token, side, req):
        self.checkers_over_check(game)
        if len(game['players']) < 2:
            raise ValueError('Waiting for opponent')
        moves = game['moves']
        if int(req.get('ply', -1)) != len(moves):
            raise ValueError('Out of sync; poll')
        # White (the first player) moves on even plies.
        if side != (len(moves) % 2 == 0):
            raise ValueError('Opponent turn')
        text = req.get('move', '').lower()
        if not re.fullmatch(r'(?:[a-h][1-8]){2,13}', text):
            raise ValueError('Bad move')
        moves.append(text)
        # Moving declines the opponent's draw offer; one's own stays.
        game['offers'].discard(not side)

    @staticmethod
    def finished(game):
        return (game['resigned'] is not None or game['agreed'] or
                game['board'].is_game_over(claim_draw=True))

    def snapshot_checkers(self, game, token, since):
        side = game['players'].index(token) == 0      # True: white
        matched = len(game['players']) == 2
        moves = game['moves']
        # over: 1 white wins (black resigned), 2 black wins, 3 draw agreed.
        over = (3 if game['agreed'] else 0 if game['resigned'] is None
                else 2 if game['resigned'] else 1)
        # offer: 1 the opponent offered a draw, 2 this player did.
        offer = 1 if (not side) in game['offers'] else 2 if side in game['offers'] else 0
        status = 'WAIT PLAYER' if not matched else 'YOU ARE ' + ('WHITE' if side else 'BLACK')
        since = len(moves) if since is None else min(since, len(moves))
        return dict(kind='checkers', matched=matched, side=int(not side), over=over,
                    status=status, ply=len(moves), moves=moves[since:since + CHECKERS_FETCH],
                    offer=offer, chat_unread=len(game['chat'][token]))

    def snapshot(self, game, token, since=None):
        if game['kind'] == 'checkers':
            return self.snapshot_checkers(game, token, since)
        board = game['board']
        outcome = board.outcome(claim_draw=True)
        status = 'WHITE TURN' if board.turn else 'BLACK TURN'
        if board.is_check():
            status = 'WHITE CHECK' if board.turn else 'BLACK CHECK'
        side = 1 if game['human_black'] else game['players'].index(token)
        matched = game['mode'] == 'ai' or (game['mode'] == 'room' and len(game['players']) == 2)
        if matched and game['mode'] == 'room' and not board.is_check():
            colour = 'BLACK' if side else 'WHITE'
            status = f'YOU ARE {colour} - ' + (
                'YOUR MOVE' if board.turn != bool(side) else 'OPPONENT MOVES')
        if game['mode'] == 'room' and len(game['players']) < 2:
            status = 'WAIT PLAYER'
        if outcome:
            status = ('DRAW' if outcome.winner is None else
                      'WHITE WINS' if outcome.winner else 'BLACK WINS')
        elif game['offers'] and game['mode'] == 'room':
            status = ('DRAW OFFERED' if (not side) in game['offers'] else
                      'OPPONENT OFFERS DRAW - ESC MENU')
        if game['agreed']:
            status = 'DRAW AGREED'
        if game['resigned'] is not None:
            status = ('WHITE RESIGNED - BLACK WINS' if game['resigned'] else
                      'BLACK RESIGNED - WHITE WINS')
        return dict(board=''.join(board.piece_at(chess.square(x,7-y)).symbol()
                    if board.piece_at(chess.square(x,7-y)) else '.'
                    for y in range(8) for x in range(8)),
                    turn=int(board.turn), side=side, matched=matched,
                    opponent='AI' if game['mode'] == 'ai' else '',
                    mode=game['mode'], status=status, over=self.finished(game),
                    ply=len(board.move_stack), history=game['history'][-12:],
                    chat_unread=len(game['chat'][token]))


_engine = None
_engine_path = None
_engine_config = {}


def find_engine(config):
    path = config.get('PCHESSENGINE') or ''
    if path:
        return path if os.path.isfile(path) else None
    # Debian/Raspberry Pi OS install it in /usr/games, often not on PATH;
    # winget on Windows unpacks it under WinGet\Packages.
    found = (shutil.which('stockfish') or
             next((p for p in ('/usr/games/stockfish','/usr/local/bin/stockfish')
                   if os.path.isfile(p)), None))
    if not found and os.name == 'nt':
        import glob
        for root in (os.environ.get('ProgramFiles',''), os.environ.get('LOCALAPPDATA','')+'/Microsoft'):
            hits = glob.glob(root+'/WinGet/Packages/Stockfish.Stockfish*/**/stockfish*.exe',
                             recursive=True)
            if hits:
                return hits[0]
    return found


def engine_limits(engine, elo):
    """Configure strength; return the per-move search limit extras."""
    option = engine.options.get('UCI_Elo')
    if option and elo >= option.min:
        engine.configure({'UCI_LimitStrength': True,
                          'UCI_Elo': min(elo, option.max)})
        return {}
    # Below Stockfish's rating floor (about 1320): weakest skill level and a
    # shallow search. Approximate, not a calibrated rating.
    if 'Skill Level' in engine.options:
        engine.configure({'Skill Level': 0})
    return {'depth': max(1, min(5, (elo - 600) // 200))}


def stop_engine():
    global _engine
    if _engine:
        try:
            _engine.quit()
        except Exception:
            pass
        _engine = None
        print('pchess: engine stopped')


def open_engine(path):
    global _engine, _engine_path
    if _engine is None or path != _engine_path:
        if _engine:
            _engine.quit()
        _engine, _engine_path = chess.engine.SimpleEngine.popen_uci(path), path
        # Pin resources so a newer Stockfish cannot take more of the Pi.
        _engine.configure({k: v for k, v in (('Threads', 1), ('Hash', 16))
                           if k in _engine.options})
    return _engine


def engine_failed(path, exc):
    global _engine
    print(f'pchess: engine {path} failed, using built-in AI: {exc}')
    try:
        if _engine: _engine.quit()
    except Exception:
        pass
    _engine = None


# The AI takes a draw unless it thinks it is ahead by more than this (centipawns).
DRAW_MARGIN = 50


def ai_accepts_draw(board, ai_side):
    """Accept when the AI is not clearly better (Stockfish eval, else material)."""
    path = find_engine(_engine_config)
    if path:
        try:
            info = open_engine(path).analyse(board, chess.engine.Limit(time=0.3))
            return info['score'].pov(ai_side).score(mate_score=100000) <= DRAW_MARGIN
        except Exception as exc:
            engine_failed(path, exc)
    values = (0,100,320,330,500,900,0)
    material = sum(values[p.piece_type]*(1 if p.color==ai_side else -1)
                   for p in board.piece_map().values())
    return material <= DRAW_MARGIN


def ai_move(board):
    """Stockfish move at the configured strength, else the built-in search."""
    config = _engine_config
    path = find_engine(config)
    if path:
        try:
            open_engine(path)
            elo = int(config.get('PCHESSELO') or 800)
            movetime = float(config.get('PCHESSMOVETIME') or 1)
            extra = engine_limits(_engine, elo)
            result = _engine.play(board, chess.engine.Limit(time=movetime, **extra))
            if result.move:
                return result.move
        except Exception as exc:
            engine_failed(path, exc)
    return choose_move(board)


def choose_move(board):
    """Two-ply alpha-beta with a node ceiling; deliberately modest MSX opponent."""
    values = (0,100,320,330,500,900,0)
    nodes = [0]
    def score(depth, alpha, beta):
        nodes[0] += 1
        if board.is_checkmate():
            return -100000-depth
        if board.is_game_over(claim_draw=True):
            return 0
        if depth == 0 or nodes[0] > 4000:
            total = sum(values[p.piece_type]*(1 if p.color==board.turn else -1)
                        for p in board.piece_map().values())
            return total
        for move in sorted(board.legal_moves, key=board.is_capture, reverse=True):
            board.push(move)
            value = -score(depth-1,-beta,-alpha)
            board.pop()
            alpha = max(alpha,value)
            if alpha >= beta:
                break
        return alpha
    best = None
    best_score = -1000000
    for move in list(board.legal_moves):
        board.push(move)
        value = -score(1,-1000000,1000000)
        board.pop()
        if value > best_score:
            best_score, best = value, move
    return best


_games = Games()
_session = None
_remote = False
_irc = None
_use_irc = False
_relay = None


def start_relay(config):
    """Serve the room relay in a background thread; keep it if already up."""
    global _relay
    if _relay:
        return
    listen = config.get('PCHESSLISTEN') or '0.0.0.0'
    port = int(config.get('PCHESSPORT') or 5080)
    try:
        _relay = RelayServer((listen, port), RelayHandler)
    except OSError as exc:
        # Another relay (e.g. a second server on this host) may own the port.
        print(f'pchess: relay not started on {listen}:{port}: {exc}')
        return
    _relay.daemon_threads = True
    threading.Thread(target=_relay.serve_forever, daemon=True).start()
    print(f'pchess: relay listening on {listen}:{port}')


def stop_relay():
    global _relay
    if _relay:
        _relay.shutdown()
        _relay.server_close()
        _relay = None
        print('pchess: relay stopped')


def relay_url(config):
    url = os.environ.get('PCHESS_RELAY_URL') or config.get('PCHESSRELAY') or ''
    if not url:
        url = 'http://127.0.0.1:%d' % int(config.get('PCHESSPORT') or 5080)
    return url.rstrip('/')


def room_channel(room):
    room = room.lower()
    if not room or len(room) > 16 or not room.isalnum():
        raise ValueError('Room: 1-16 letters or digits')
    return '#pchess-' + room


def rooms_mode(config):
    mode = (os.environ.get('PCHESS_ROOMS') or config.get('PCHESSROOMS') or 'relay').lower()
    return 'irc' if mode == 'irc' else 'relay'


CHECKERS_IRC_COMMANDS = ('cpoll','cmove','cdraw','cresign','creset','cseek','coffer','caccept',
                         'cplayers','say','chat')
CHESS_IRC_COMMANDS = ('seek','offer','accept','poll','move','players','draw','resign')


def handle_command(command, irc_config=None, room_config=None, engine_config=None):
    """Return a fixed 256-byte state packet, including user-visible failures."""
    global _session, _remote, _irc, _use_irc, _engine_config
    room_config = room_config or {}
    _engine_config = engine_config or {}
    try:
        args = command.split()
        if not args:
            raise ValueError('new local / new ai / join ROOM')
        say_text = command.partition(' ')[2].strip() if args[0] == 'say' else ''
        irc_room = args[0] == 'join' and len(args) == 2 and rooms_mode(room_config) == 'irc'
        # PCheckers: cjoin ROOM is a relay room or, with PCHESSROOMS=irc, the
        # same #pchess-<room> channel PChess uses; circ is the shared lobby.
        ck_irc_room = args[0] == 'cjoin' and len(args) == 2 and rooms_mode(room_config) == 'irc'
        ck_lobby = args[0] == 'circ'
        if args[0] in ('irc','new','circ') or irc_room or ck_irc_room:
            stop_relay()
        if args[0] in ('irc','join','cjoin','circ') or (args[0]=='new' and args[1:2]!=['ai']):
            stop_engine()
        # Not an elif: 'join' also matches the line above, which left this
        # unreachable and the relay never started (connection refused).
        if (args[0] == 'join' and not irc_room) or (args[0] == 'cjoin' and not ck_irc_room):
            start_relay(room_config)
        if ck_irc_room or ck_lobby:
            channel = room_channel(args[1]) if ck_irc_room else None
            if (_use_irc and _irc and isinstance(_irc.peer, CheckersPeer) and _irc.peer.room == channel
                    and _irc.ready and not _irc.error):
                # The same room again (a rematch) just says HELLO again.
                _irc.poll()
                if channel: _irc.peer.announce_room()
                _irc.poll()
                return checkers_packet(_irc.peer.snapshot())
            from msxpi_pchess_irc import IRC
            if _irc: _irc.close()
            _irc = IRC(irc_config, channel, CheckersPeer)
            _use_irc = True
            _irc.poll()
            return checkers_packet(_irc.peer.snapshot())
        if args[0] == 'cleave':
            # PCheckers leaves its room or the lobby: drop the IRC connection
            # and the relay session. The reply carries no status.
            if _irc: _irc.close()
            _irc, _use_irc, _session = None, False, None
            return b'PCH1' + bytes(252)
        ck_peer = _irc.peer if _use_irc and _irc and isinstance(_irc.peer, CheckersPeer) else None
        if ck_peer and args[0] in CHESS_IRC_COMMANDS:
            raise ValueError('Not a chess game')
        if ck_peer and args[0] in CHECKERS_IRC_COMMANDS:
            _irc.poll()
            if args[0] != 'cpoll' and not _irc.ready:
                raise ValueError('Lobby not ready; wait')
            if args[0] == 'cplayers':
                if ck_peer.room: raise ValueError('In a room; no lobby')
                return players_packet(ck_peer.recent_players())
            if args[0] == 'chat':
                return chat_packet(*ck_peer.take_chat(CHAT_FETCH))
            since = None
            if args[0] == 'cseek': ck_peer.seek()
            elif args[0] == 'coffer': ck_peer.offer(args[1])
            elif args[0] == 'caccept': ck_peer.accept()
            elif args[0] == 'cmove' and len(args) == 3: ck_peer.cmove(int(args[1]), args[2])
            elif args[0] == 'cdraw': ck_peer.draw()
            elif args[0] == 'cresign': ck_peer.resign()
            elif args[0] == 'creset': ck_peer.reset()
            elif args[0] == 'say': ck_peer.say(say_text)
            elif args[0] == 'cpoll': since = int(args[1]) if len(args) > 1 else None
            _irc.poll()
            return checkers_packet(ck_peer.snapshot(since))
        if _use_irc and _irc and not ck_peer and args[0] in CHECKERS_IRC_COMMANDS and args[0] not in ('say', 'chat'):
            raise ValueError('Not a checkers game')
        if irc_room:
            channel = room_channel(args[1])
            # Joining the same room again (a rematch) just says HELLO again.
            if _use_irc and _irc and _irc.peer.room == channel and _irc.ready and not _irc.error:
                _irc.poll()
                _irc.peer.announce_room()
                return packet(_irc.poll())
            from msxpi_pchess_irc import IRC
            if _irc: _irc.close()
            _irc = IRC(irc_config, channel)
            _use_irc = True
            return packet(_irc.poll())
        if args[0]=='irc':
            from msxpi_pchess_irc import IRC
            if _irc: _irc.close()
            _irc=IRC(irc_config)
            _use_irc=True
            return packet(_irc.poll())
        # Lobby commands before 5 ONLINE: say so, not "Start a game first".
        if args[0] in ('players','seek','offer','accept') and not _use_irc:
            raise ValueError('Go online first (4)')
        if args[0]=='players' and _irc.peer.room:
            raise ValueError('In a room; no lobby')
        if _use_irc and args[0] in ('seek','offer','accept','poll','move','players','draw','resign','say','chat'):
            _irc.poll()
            if args[0]!='poll' and not _irc.ready:
                raise ValueError('Lobby not ready; wait')
            if args[0]=='players': return players_packet(_irc.peer.recent_players())
            if args[0]=='seek': _irc.peer.seek()
            elif args[0]=='offer': _irc.peer.offer(args[1])
            elif args[0]=='accept': _irc.peer.accept()
            elif args[0]=='move': _irc.peer.move(args[1])
            elif args[0]=='draw': _irc.peer.draw()
            elif args[0]=='resign': _irc.peer.resign()
            elif args[0]=='say': _irc.peer.say(say_text)
            elif args[0]=='chat':
                _irc.poll()
                return chat_packet(*_irc.peer.take_chat(CHAT_FETCH))
            return packet(_irc.poll())
        if args[0] == 'new' and (len(args) == 2 or args[1:] == ['ai','black']):
            req = dict(action='new',mode=args[1],black=len(args) == 3)
            remote = False
        elif args[0] == 'join' and len(args) == 2:
            req = dict(action='new',mode='room',room=args[1])
            remote = True
        elif args[0] == 'cjoin' and len(args) == 2:
            # PCheckers rooms always use the relay: the IRC peer plays chess.
            req = dict(action='new',mode='room',room=args[1],kind='checkers')
            remote = True
        else:
            if _session is None:
                raise ValueError('Start a game first')
            req = dict(action=args[0], game=_session['game'],token=_session['token'])
            remote = _remote
            if args[0] == 'move' and len(args) == 2:
                req['move'] = args[1]
            if args[0] in ('cmove','cpoll') and len(args) >= 2:
                req['ply'] = int(args[1])
                if args[0] == 'cmove' and len(args) == 3:
                    req['move'] = args[2]
            if args[0] == 'say':
                req['text'] = say_text
        if remote:
            request = Request(relay_url(room_config)+'/game', json.dumps(req).encode(),
                              {'Content-Type':'application/json'})
            with urlopen(request,timeout=5) as response:
                result = json.loads(response.read(8192))
            if 'error' in result:
                raise ValueError(result['error'])
        else:
            result = _games.request(req)
        if req['action']=='new':
            _session, _remote = result, remote
            _use_irc=False
            if _irc:
                _irc.close()
                _irc=None
        if args[0] == 'chat':
            return chat_packet(result['chat_rows'], result['chat_unread'])
        if result.get('kind') == 'checkers':
            return checkers_packet(result)
        return packet(result)
    except Exception as exc:
        data = bytearray(256)
        data[:4] = b'PCH1'
        message = str(exc).replace('\n',' ')[:47].encode('ascii','replace')
        data[72:72+len(message)] = message
        return bytes(data)


# Menu AI levels 1-8 map to PCHESSELO; the level is derived back from it.
LEVEL_ELO = (600, 800, 1000, 1350, 1600, 1900, 2200, 2500)


def elo_level(elo):
    try:
        elo = int(elo or 800)
    except ValueError:
        elo = 800
    return 1 + min(range(8), key=lambda i: abs(LEVEL_ELO[i]-elo))


def level_packet(elo, rooms='relay'):
    """Status-only packet (board flag 0 keeps the client board); byte 242 =
    level, byte 243 = 1 when rooms are IRC channels (PCHESSROOMS=irc)."""
    level = elo_level(elo)
    data = bytearray(256)
    data[:4] = b'PCH1'
    message = ('AI LEVEL %d ELO %d' % (level, LEVEL_ELO[level-1])).encode('ascii')
    data[72:72+len(message)] = message
    data[242] = level
    data[243] = int(rooms == 'irc')
    # The only pchess reply built in microseconds. On the v0.8.2 board a quick
    # reply here intermittently fails: the MSX drops out after the block
    # header and the payload times out (rc=1, completed=0/256). 20 ms failed and
    # 100 ms was clean on hardware; 200 ms keeps a 2x margin. Not reproducible in openMSX.
    time.sleep(0.2)
    return bytes(data)


def packet(state):
    data = bytearray(256)
    data[:4] = b'PCH1'
    data[4:8] = bytes((1,state['turn'],state['side'],int(state['over'])))
    data[8:72] = state['board'].encode('ascii')
    status = state['status'].encode('ascii')
    data[72:72+len(status)] = status
    for i,move in enumerate(state['history']):
        text=move[:9].encode('ascii')
        data[120+i*10:120+i*10+len(text)] = text
    data[240]=len(state['history'])
    data[241]=min(state['ply'],255)
    # 242: 1 once the player's colour is settled (AI, room or lobby match);
    # 243-255: opponent name, NUL-terminated (lobby nick, 'AI', or empty).
    data[242]=int(bool(state.get('matched')))
    opponent=state.get('opponent','')[:12].encode('ascii','replace')
    data[243:243+len(opponent)]=opponent
    # 255: unread chat rows waiting for 'pchess chat' (0-255).
    data[255]=min(state.get('chat_unread',0),255)
    return bytes(data)


# The PCheckers state: byte 4 is 1, 5 matched (two players), 6 this player's
# side (0 white), 7 how the game ended (0 playing, 1 white wins by
# resignation, 2 black wins, 3 draw agreed), status from byte 72, moves from
# byte 120 in 14-byte slots (length, then the board squares row*8+col with
# row 0 at the top), moves in this block in 240, total moves in 241 (low) and 238 (high), draw
# offer in 242 (1 the opponent offered, 2 this player did) and unread chat
# rows in 255. The server does not know the rules: the MSX clients check
# every move they receive.
def checkers_packet(state):
    data = bytearray(256)
    data[:4] = b'PCH1'
    data[4:8] = bytes((1,int(state['matched']),state['side'],state['over']))
    status = state['status'].encode('ascii')
    data[72:72+len(status)] = status
    for i,move in enumerate(state['moves'][:CHECKERS_FETCH]):
        squares = [(8-int(move[j+1]))*8+ord(move[j])-97 for j in range(0,len(move),2)]
        data[120+i*14] = len(squares)
        data[121+i*14:121+i*14+len(squares)] = bytes(squares)
    data[240] = len(state['moves'][:CHECKERS_FETCH])
    data[241] = state['ply'] & 255
    data[238] = min(state['ply'] >> 8,255)
    data[242] = state['offer']
    data[255] = min(state.get('chat_unread',0),255)
    return bytes(data)


# The chat fetch: byte 4 is 0 (no board) and byte 5 is 'C'. Up to five rows
# of 42 characters in 44-byte slots from byte 8 (so byte 72 is chat text, not
# a status; byte 43 of a slot is 1 for a private row), row count in byte 240
# and rows still unread in byte 241. Rows are (private, text).
CHAT_FETCH=5
def chat_packet(rows,unread):
    data = bytearray(256)
    data[:4] = b'PCH1'
    data[5] = ord('C')
    for i,(private,row) in enumerate(rows[:CHAT_FETCH]):
        text = row[:CHAT_ROW].encode('ascii','replace')
        data[8+i*44:8+i*44+len(text)] = text
        data[8+i*44+43] = 1 if private else 0
    data[240] = min(len(rows),CHAT_FETCH)
    data[241] = min(unread,255)
    return bytes(data)


# The lobby player list: byte 4 is 0 (no board) and byte 5 is 'P'. Up to
# seven nicks in 16-byte slots from byte 120, count in byte 240.
PLAYER_SLOTS=7
def players_packet(names):
    data = bytearray(256)
    data[:4] = b'PCH1'
    data[5] = ord('P')
    status = (f'{len(names)} PLAYER' + ('' if len(names)==1 else 'S') if names
              else 'NO PLAYERS - ASK THEM TO SEEK (5)').encode('ascii')
    data[72:72+len(status)] = status
    names = names[:PLAYER_SLOTS]
    for i,name in enumerate(names):
        text = name[:16].encode('ascii','replace')
        data[120+i*16:120+i*16+len(text)] = text
    data[240] = len(names)
    return bytes(data)


class RelayServer(ThreadingHTTPServer):
    # On Windows SO_REUSEADDR lets a second relay share a busy port.
    allow_reuse_address = os.name != 'nt'


class RelayHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            if self.path != '/game':
                raise ValueError('Unknown endpoint')
            size=int(self.headers.get('Content-Length','0'))
            if not 0<size<=2048:
                raise ValueError('Invalid request size')
            result=_games.request(json.loads(self.rfile.read(size)))
        except Exception as exc:
            result={'error':str(exc)}
        body=json.dumps(result).encode()
        self.send_response(200)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--listen',default='127.0.0.1')
    parser.add_argument('--port',type=int,default=5080)
    args=parser.parse_args()
    ThreadingHTTPServer((args.listen,args.port),RelayHandler).serve_forever()
