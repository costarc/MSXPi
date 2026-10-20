"""Local IRC server for the chat + game rig (the test fixture used by the server tests).

    python irc_fixture_server.py <port>       runs until killed

Every line a client sends is printed as "<connection> <nick> <line>", and each new connection as
"conn <connection>": run_native.sh (SCENARIO=tcp) checks that MCHAT /T is back on the same connection.
"""
import itertools
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'Server/Python/tests'))
from pchess_irc_fixture import Handler, Server

ids = itertools.count(1)


class LoggedHandler(Handler):
    def setup(self):
        super().setup()
        cid, nick, rfile = next(ids), ['?'], self.rfile
        print('conn', cid, flush=True)

        def lines():
            for raw in rfile:
                line = raw.decode(errors='replace').rstrip('\r\n')
                if line.startswith('NICK '):
                    nick[0] = line[5:]
                print(cid, nick[0], line, flush=True)
                yield raw
        self.rfile = lines()


if __name__ == '__main__':
    port = int(sys.argv[1])
    server = Server(('127.0.0.1', port))
    server.RequestHandlerClass = LoggedHandler
    print('irc fixture on', port, flush=True)
    server.serve_forever()
