"""PChess rules, bounded local AI, and optional shared-room relay.

Install requirements-pchess.txt. Choosing ROOM mode starts a relay inside
this server (msxpi.ini PCHESSLISTEN/PCHESSPORT); any other mode stops it.
PCHESSRELAY names the relay both players share: empty means this server's
own relay, otherwise http://HOST:PORT of the MSXPi hosting the room. The
module can still run standalone with --listen to host a dedicated relay.

The AI opponent is Stockfish when it is installed (PCHESSENGINE, PCHESSELO,
PCHESSMOVETIME in msxpi.ini); otherwise a small built-in search plays.
"""
import argparse
import json
import os
import secrets
import shutil
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen

import chess
import chess.engine


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
            game_id = 'room-' + room if mode == 'room' else secrets.token_hex(8)
            if game_id not in self.games:
                if len(self.games) >= 128:
                    raise ValueError('Relay full')
                self.games[game_id] = dict(board=chess.Board(), mode=mode,
                    players=[], history=[], seen=now, resigned=None,
                    offers=set(), agreed=False)
            game = self.games[game_id]
            if len(game['players']) >= (2 if mode == 'room' else 1):
                raise ValueError('Room full; choose another')
            token = secrets.token_hex(16)
            game['players'].append(token)
            result = self.snapshot(game, token)
            result.update(game=game_id, token=token)
            return result
        game = self.games.get(req.get('game'))
        token = req.get('token')
        if game is None or token not in game['players']:
            raise ValueError('Game not found; start new')
        game['seen'] = time.monotonic()
        board = game['board']
        side = game['players'].index(token) == 0
        if action == 'move':
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
        elif action != 'poll':
            raise ValueError('Unknown action')
        return self.snapshot(game, token)

    @staticmethod
    def finished(game):
        return (game['resigned'] is not None or game['agreed'] or
                game['board'].is_game_over(claim_draw=True))

    def snapshot(self, game, token):
        board = game['board']
        outcome = board.outcome(claim_draw=True)
        status = 'WHITE TURN' if board.turn else 'BLACK TURN'
        if board.is_check():
            status = 'WHITE CHECK' if board.turn else 'BLACK CHECK'
        side = game['players'].index(token)
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
                    ply=len(board.move_stack), history=game['history'][-12:])


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


def handle_command(command, irc_config=None, room_config=None, engine_config=None):
    """Return a fixed 256-byte state packet, including user-visible failures."""
    global _session, _remote, _irc, _use_irc, _engine_config
    room_config = room_config or {}
    _engine_config = engine_config or {}
    try:
        args = command.split()
        if not args:
            raise ValueError('new local / new ai / join ROOM')
        if args[0] in ('irc','new'):
            stop_relay()
        if args[0] in ('irc','join') or (args[0]=='new' and args[1:]!=['ai']):
            stop_engine()
        # Not an elif: 'join' also matches the line above, which left this
        # unreachable and the relay never started (connection refused).
        if args[0] == 'join':
            start_relay(room_config)
        if args[0]=='irc':
            from msxpi_pchess_irc import IRC
            if _irc: _irc.close()
            _irc=IRC(irc_config)
            _use_irc=True
            return packet(_irc.poll())
        if args[0]=='players' and not _use_irc:
            raise ValueError('Go online first (4)')
        if _use_irc and args[0] in ('seek','offer','accept','poll','move','players','draw','resign'):
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
            return packet(_irc.poll())
        if args[0] == 'new' and len(args) == 2:
            req = dict(action='new',mode=args[1])
            remote = False
        elif args[0] == 'join' and len(args) == 2:
            req = dict(action='new',mode='room',room=args[1])
            remote = True
        else:
            if _session is None:
                raise ValueError('Start a game first')
            req = dict(action=args[0], game=_session['game'],token=_session['token'])
            remote = _remote
            if args[0] == 'move' and len(args) == 2:
                req['move'] = args[1]
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


def level_packet(elo):
    """Status-only packet (board flag 0 keeps the client board); byte 242 = level."""
    level = elo_level(elo)
    data = bytearray(256)
    data[:4] = b'PCH1'
    message = ('AI LEVEL %d ELO %d' % (level, LEVEL_ELO[level-1])).encode('ascii')
    data[72:72+len(message)] = message
    data[242] = level
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
