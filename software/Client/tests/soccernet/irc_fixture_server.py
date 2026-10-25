"""Local IRC server for the chat + game rig (the test fixture used by the server tests).

    python irc_fixture_server.py <port> [<ping s> <timeout s>]       runs until killed

Every line a client sends is printed as "<connection> <nick> <line>", and each new connection as
"conn <connection>": run_native.sh (SCENARIO=tcp) checks that MCHAT /T is back on the same connection.
With a ping interval, every client gets "PING :<n>" that often ("ping <connection> <nick>" in the log),
and, as a real server does, one that has sent nothing for the timeout is dropped ("drop ...").

Load for the chat-during-a-game measurements (PLAYNET-TCPIP-IMPLEMENTATION-PLAN D1a), from the environment:
IRC_RATE=n sends n channel lines a second (about 100 bytes each) to every client, IRC_BURST=n sends n lines at once
every IRC_BURST_EVERY seconds (default 10, as when a busy channel catches up).  The load starts when a client sends
MSXG1 GO or ACCEPT, so the set-up screens are not disturbed.  The lines are PRIVMSGs to #msxpi.
"""
import itertools
import os
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'Server/Python/tests'))
from pchess_irc_fixture import Handler, Server

ids = itertools.count(1)
game_on = threading.Event()      # set when a client sends MSXG1 GO or ACCEPT: the load starts with the game
live = set()
out = threading.Lock()


def log(*words):
    with out:
        sys.stdout.write(' '.join(map(str, words)) + chr(10))
        sys.stdout.flush()


class LoggedHandler(Handler):
    def setup(self):
        super().setup()
        self.cid, self.nick, self.heard = next(ids), '?', time.monotonic()
        rfile = self.rfile
        log('conn', self.cid)

        def lines():
            for raw in rfile:
                line = raw.decode(errors='replace').rstrip('\r\n')
                self.heard = time.monotonic()
                if line.startswith('NICK '):
                    self.nick = line[5:]
                if ':MSXG1 GO' in line or ':MSXG1 ACCEPT' in line:
                    game_on.set()
                log(self.cid, self.nick, line)
                yield raw
        self.rfile = lines()
        with self.server.lock:
            live.add(self)

    def finish(self):
        with self.server.lock:
            live.discard(self)
        super().finish()


def pinger(server, every, timeout):
    for n in itertools.count(1):
        time.sleep(every)
        with server.lock:
            for h in list(live):
                if time.monotonic() - h.heard > timeout:
                    log('drop', h.cid, h.nick)
                    live.discard(h)
                    try:
                        h.request.shutdown(2)
                    except OSError:
                        pass
                    continue
                try:
                    h.send(f'PING :{n}')
                    log('ping', h.cid, h.nick)
                except OSError:
                    pass


def chatter(server, rate, burst, every):
    text = 'x' * 70
    seq = itertools.count(1)

    def say(n):
        with server.lock:
            for h in list(live):
                for _ in range(n):
                    try:
                        h.send(':bot!b@h PRIVMSG #msxpi :%06d %s' % (next(seq), text))
                    except OSError:
                        break
    last = 0.0
    game_on.wait()
    last = time.monotonic()
    while True:
        time.sleep(1.0 / rate if rate else 0.1)
        now = time.monotonic()
        if rate:
            say(1)
        if burst and now - last >= every:
            last = now
            say(burst)


if __name__ == '__main__':
    port = int(sys.argv[1])
    server = Server(('127.0.0.1', port))
    server.RequestHandlerClass = LoggedHandler
    if len(sys.argv) > 3:
        threading.Thread(target=pinger, args=(server, float(sys.argv[2]), float(sys.argv[3])), daemon=True).start()
    rate, burst = int(os.environ.get('IRC_RATE', '0')), int(os.environ.get('IRC_BURST', '0'))
    if rate or burst:
        threading.Thread(target=chatter, args=(server, rate, burst, float(os.environ.get('IRC_BURST_EVERY', '10'))), daemon=True).start()
    log('irc fixture on', port)
    server.serve_forever()
