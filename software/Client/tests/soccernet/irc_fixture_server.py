"""Local IRC server for the chat + game rig (the test fixture used by the server tests).

    python irc_fixture_server.py <port> [<ping s> <timeout s>]       runs until killed

Every line a client sends is printed as "<connection> <nick> <line>", and each new connection as
"conn <connection>": run_native.sh (SCENARIO=tcp) checks that MCHAT /T is back on the same connection.
With a ping interval, every client gets "PING :<n>" that often ("ping <connection> <nick>" in the log),
and, as a real server does, one that has sent nothing for the timeout is dropped ("drop ...").
"""
import itertools
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'Server/Python/tests'))
from pchess_irc_fixture import Handler, Server

ids = itertools.count(1)
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


if __name__ == '__main__':
    port = int(sys.argv[1])
    server = Server(('127.0.0.1', port))
    server.RequestHandlerClass = LoggedHandler
    if len(sys.argv) > 3:
        threading.Thread(target=pinger, args=(server, float(sys.argv[2]), float(sys.argv[3])), daemon=True).start()
    log('irc fixture on', port)
    server.serve_forever()
