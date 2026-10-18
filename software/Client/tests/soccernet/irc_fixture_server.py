"""Local IRC server for the chat + game rig (the test fixture used by the server tests).

    python irc_fixture_server.py <port>       runs until killed
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'Server/Python/tests'))
from pchess_irc_fixture import Server

if __name__ == '__main__':
    port = int(sys.argv[1])
    server = Server(('127.0.0.1', port))
    print('irc fixture on', port, flush=True)
    server.serve_forever()
