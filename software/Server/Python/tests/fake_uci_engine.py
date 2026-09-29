"""Minimal UCI engine for tests: records setoptions, always answers e7e5."""
import sys
log = open(sys.argv[1], 'a') if len(sys.argv) > 1 else None
for line in sys.stdin:
    cmd = line.strip()
    if log: log.write(cmd + '\n'); log.flush()
    if cmd == 'uci':
        print('id name FakeFish')
        print('option name Threads type spin default 2 min 1 max 1024')
        print('option name Hash type spin default 64 min 1 max 33554432')
        print('option name Skill Level type spin default 20 min 0 max 20')
        print('option name UCI_LimitStrength type check default false')
        print('option name UCI_Elo type spin default 1320 min 1320 max 3190')
        print('uciok')
    elif cmd == 'isready':
        print('readyok')
    elif cmd.startswith('go'):
        print('bestmove e7e5')
    elif cmd == 'quit':
        break
    sys.stdout.flush()
