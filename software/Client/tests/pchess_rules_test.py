"""Random games: pchess_rules.c (host build, in WSL) against python-chess.

Every ply compares the FEN, the full legal-move list with SAN, the game
outcome with claimable draws, and parsing of SAN and UCI back to moves.
Run with Windows Python (python-chess installed); needs WSL gcc.
    python pchess_rules_test.py [games] [seed]
"""
import random
import subprocess
import sys
from pathlib import Path
import hashlib
import chess

HERE = Path(__file__).resolve().parent
DISTRO = 'Ubuntu-24.04'


def wsl_path(path):
    drive, rest = str(path).split(':', 1)
    return '/mnt/' + drive.lower() + rest.replace('\\', '/')


def build():
    cmd = (f'cd {wsl_path(HERE)} && gcc -O2 -Wall -Wno-unused-function '
           f'-o /tmp/pchess_rules_host pchess_rules_host.c')
    subprocess.run(['wsl.exe', '-d', DISTRO, '--', 'bash', '-lc', cmd], check=True)


class Host:
    def __init__(self):
        self.proc = subprocess.Popen(['wsl.exe', '-d', DISTRO, '--', '/tmp/pchess_rules_host'],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def ask(self, line):
        self.proc.stdin.write(line + '\n')
        self.proc.stdin.flush()
        return self.proc.stdout.readline().strip()


def outcome_code(board):
    o = board.outcome(claim_draw=True)
    if o is None:
        return 0
    return 3 if o.winner is None else 1 if o.winner else 2


def pick(board, rng, shuffle):
    moves = list(board.legal_moves)
    if shuffle:
        quiet = [m for m in moves if board.piece_type_at(m.from_square) in (chess.KNIGHT, chess.KING)
                 and not board.is_capture(m)]
        if quiet and rng.random() < .9:
            return rng.choice(quiet)
    return rng.choice(moves)


def main():
    games = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    rng = random.Random(seed)
    build()
    host = Host()
    endings = {}
    plies = 0
    for game in range(games):
        board = chess.Board()
        assert host.ask('reset') == 'ok'
        shuffle = game % 3 == 0
        while True:
            fen = host.ask('fen')
            assert fen == board.fen(), (game, board.move_stack, fen, board.fen())
            assert host.ask('digest') == hashlib.sha256(fen.encode()).hexdigest()[:16], fen
            got = dict(item.split(':') for item in host.ask('moves').split())
            want = {m.uci(): board.san(m) for m in board.legal_moves}
            assert got == want, (game, board.fen(), set(got.items()) ^ set(want.items()))
            code = int(host.ask('outcome'))
            assert code == outcome_code(board), (game, board.fen(), code, board.outcome(claim_draw=True))
            if code:
                o = board.outcome(claim_draw=True)
                endings[o.termination.name] = endings.get(o.termination.name, 0) + 1
                break
            move = pick(board, rng, shuffle)
            san = board.san(move)
            for text in (san, move.uci()):
                assert host.ask('parse ' + text) == move.uci(), (game, board.fen(), text)
            assert host.ask('play ' + (san if rng.random() < .5 else move.uci())) == 'ok'
            board.push(move)
            plies += 1
    print(f'{games} games, {plies} plies, all matched; endings {endings}')


if __name__ == '__main__':
    main()
