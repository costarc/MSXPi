"""PPOKER relay robustness: bad requests and nine concurrent players.

The relay must always answer - with a table packet or an error - and keep
serving afterwards.  Each test starts the relay on a free localhost port.

Run from software/Server/Python:
    python -m unittest tests.test_poker_relay -v
"""
import http.client
import json
import socket
import sys
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_poker as p

CONFIG = {'POKERSTACK': '1000', 'POKERACTIONSECS': '30', 'POKERLEVELSECS': '300',
          'POKERDROP': '20', 'POKERGRACE': '600', 'POKERHANDDELAY': '1', 'POKERLATE': '4'}
TIMEOUT = 10


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


class RelayCase(unittest.TestCase):
    def setUp(self):
        p.stop_relay()
        self.port = free_port()
        p.start_relay(dict(CONFIG, POKERLISTEN='127.0.0.1', POKERPORT=str(self.port)))
        self.assertIsNotNone(p._relay, 'relay did not start on %d' % self.port)

    def tearDown(self):
        p.stop_relay()

    def request(self, method='POST', body=b'', path='/poker', headers=None):
        """Send one raw request; return (status, decoded JSON reply)."""
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=TIMEOUT)
        try:
            conn.request(method, path, body=body, headers=headers or {})
            response = conn.getresponse()
            data = response.read()
        finally:
            conn.close()
        return response.status, json.loads(data)

    def post(self, payload):
        return self.request(body=json.dumps(payload).encode(),
                            headers={'Content-Type': 'application/json'})

    def packet(self, reply):
        """A relay reply as a checked 256-byte packet."""
        self.assertIn('packet', reply, reply)
        data = bytes.fromhex(reply['packet'])
        self.assertEqual(len(data), p.PACKET)
        self.assertEqual(data[0:4], b'POKR')
        self.assertEqual(data[255], sum(data[0:255]) & 0xFF)
        return data

    def assert_error(self, reply):
        """The reply is {"error": ...} or a valid error packet."""
        if 'error' in reply:
            self.assertTrue(reply['error'])
            return
        data = self.packet(reply)
        self.assertEqual(data[5], ord('E'), 'expected an error packet, got kind %r' % data[5])

    def assert_still_serving(self, room='robust'):
        status, reply = self.post({'cmd': 'join %s' % room, 'nick': 'CHECK', 'room': room})
        self.assertEqual(status, 200)
        data = self.packet(reply)
        self.assertNotEqual(data[5], ord('E'), data[208:248])
        self.assertNotEqual(data[12], 0xFF)


class BadRequests(RelayCase):
    def check_bad(self, *args, **kwargs):
        status, reply = self.request(*args, **kwargs)
        self.assertLess(status, 500)
        self.assert_error(reply)
        self.assert_still_serving()

    def test_body_not_json(self):
        self.check_bad(body=b'join robust please')

    def test_json_not_an_object(self):
        self.check_bad(body=b'[1, 2, 3]')

    def test_json_without_cmd(self):
        self.check_bad(body=json.dumps({'nick': 'BOB', 'room': 'robust'}).encode())

    def test_unknown_command(self):
        self.check_bad(body=json.dumps({'cmd': 'dance', 'nick': 'BOB', 'room': 'robust'}).encode())

    def test_room_too_long(self):
        room = 'A' * 17
        self.check_bad(body=json.dumps({'cmd': 'join ' + room, 'nick': 'BOB',
                                        'room': room}).encode())
        self.assertNotIn(room.lower(), p._rooms.rooms)

    def test_room_with_punctuation(self):
        for room in ('bad!', 'a b', '../x', 'r%00'):
            self.check_bad(body=json.dumps({'cmd': 'poll', 'nick': 'BOB', 'room': room}).encode())
            self.assertNotIn(room.lower(), p._rooms.rooms)

    def test_body_over_64k(self):
        big = json.dumps({'cmd': 'join robust', 'nick': 'BOB', 'room': 'robust',
                          'text': 'X' * (65 * 1024)}).encode()
        self.check_bad(body=big)

    def test_get_instead_of_post(self):
        self.check_bad(method='GET')

    def test_empty_body(self):
        self.check_bad(body=b'')

    def test_wrong_path(self):
        self.check_bad(body=b'{"cmd": "poll"}', path='/other')


class NinePlayers(RelayCase):
    ROUNDS = 100

    def test_nine_concurrent_clients(self):
        room = 'nine'
        nicks = ['PLAYER%d' % i for i in range(9)]
        for nick in nicks:
            status, reply = self.post({'cmd': 'join ' + room, 'nick': nick, 'room': room})
            self.assertEqual(status, 200)
            self.assertNotEqual(self.packet(reply)[5], ord('E'))
        time.sleep(2.5)        # the first hand is dealt two seconds after a join
        failures = []
        replies = [0] * len(nicks)

        def player(index, nick):
            commands = ('poll', 'call', 'check', 'poll', 'raise 60', 'fold', 'poll', 'say hi',
                        'chat', 'bet 40', 'allin')
            try:
                for n in range(self.ROUNDS):
                    command = commands[(n * 7 + index) % len(commands)]
                    status, reply = self.post({'cmd': command, 'nick': nick, 'room': room})
                    if status != 200:
                        failures.append('%s %s: HTTP %d' % (nick, command, status))
                        return
                    data = bytes.fromhex(reply['packet'])
                    if len(data) != p.PACKET or data[0:4] != b'POKR' or \
                            data[255] != sum(data[0:255]) & 0xFF:
                        failures.append('%s %s: bad packet' % (nick, command))
                        return
                    replies[index] += 1
            except Exception as exc:                        # timeouts included
                failures.append('%s: %r' % (nick, exc))

        threads = [threading.Thread(target=player, args=(i, nick)) for i, nick in enumerate(nicks)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(120)
        self.assertFalse(any(t.is_alive() for t in threads), 'a client thread hung')
        self.assertEqual(failures, [])
        self.assertEqual(replies, [self.ROUNDS] * len(nicks))
        tournament = p._rooms.get(room, {}, create=False)
        with tournament.lock:
            chips = sum(s.stack for s in tournament.seats) + tournament.pot()
            self.assertEqual(chips, 9 * int(CONFIG['POKERSTACK']))
            self.assertGreater(tournament.hand_no, 0)
        self.assert_still_serving()


if __name__ == '__main__':
    unittest.main()
