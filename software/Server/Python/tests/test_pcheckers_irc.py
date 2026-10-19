"""PCheckers on IRC (rooms and lobby) against the pchess IRC fixture: pairing,
moves, shared public chat with PChess players, private chat in the game."""
import os
import sys
import threading
import time
import unittest
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'src'))
sys.path.insert(0, str(HERE))
import msxpi_pchess as p
from msxpi_pchess_irc import IRC
from msxpi_pcheckers_irc import CheckersPeer
from pchess_irc_fixture import Server


class Base(unittest.TestCase):
    def setUp(self):
        self.server = Server(('127.0.0.1', 0))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        os.environ.update(PCHESS_IRC_HOST='127.0.0.1', PCHESS_IRC_PORT=str(self.server.server_address[1]),
                          PCHESS_IRC_TLS='0')

    def client(self, nick, room=None, peer_class=None):
        os.environ['PCHESS_IRC_NICK'] = nick
        irc = IRC(None, room, peer_class)
        self.addCleanup(irc.close)
        return irc

    def pump(self, *clients, until, seconds=5):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            for c in clients:
                c.poll()
            if until():
                return
            time.sleep(.05)
        self.fail('timed out')


class Irc(Base):
    def test_room_pairing_moves_and_chat_shared_with_pchess(self):
        room = '#pchess-dama'
        a = self.client('Alice', room, CheckersPeer)
        self.pump(a, until=lambda: a.ready)
        b = self.client('Bob', room, CheckersPeer)
        c = self.client('Carl', room)                  # a PChess player in the same room
        self.pump(a, b, c, until=lambda: a.peer.phase == 'playing' and b.peer.phase == 'playing')
        self.assertEqual((a.peer.side, b.peer.side), (0, 1))
        a.peer.cmove(0, 'c3d4')
        self.pump(a, b, c, until=lambda: b.peer.moves == ['c3d4'])
        b.peer.cmove(1, 'b6a5')
        self.pump(a, b, c, until=lambda: a.peer.moves == ['c3d4', 'b6a5'])
        with self.assertRaises(ValueError):
            a.peer.cmove(1, 'd4e5')                    # stale
        # Public talk in the room reaches everybody, the PChess player included.
        c.peer.say('ola a todos')
        self.pump(a, b, c, until=lambda: a.peer.chat and b.peer.chat)
        self.assertEqual(a.peer.take_chat()[0], [(0, 'CARL: OLA A TODOS')])
        b.peer.take_chat()
        # The players' own words stay between them once the game started.
        a.peer.say('so para voce')
        self.pump(a, b, c, until=lambda: b.peer.chat)
        self.assertEqual(b.peer.take_chat()[0], [(1, 'ALICE: SO PARA VOCE')])
        # And the checkers lines are never chat to the PChess player.
        self.assertEqual(list(c.peer.chat), [])
        # The PChess player's talk is public, so Alice and Bob get it after the game too.
        a.peer.draw()
        self.pump(a, b, until=lambda: b.peer.draw_offer == 'peer')
        b.peer.draw()
        self.pump(a, b, until=lambda: a.peer.result == 3 and b.peer.result == 3)
        a.peer.reset()
        self.pump(a, b, until=lambda: not b.peer.moves and not b.peer.result)

    def test_lobby_seek_offer_accept_and_resign(self):
        a = self.client('Alice', None, CheckersPeer)
        b = self.client('Bob', None, CheckersPeer)
        self.pump(a, b, until=lambda: a.ready and b.ready)
        a.peer.seek()
        self.pump(a, b, until=lambda: b.peer.recent_players() == ['Alice'])
        self.assertIn('WANTS TO PLAY', b.peer.status)
        b.peer.offer('Alice')
        self.pump(a, b, until=lambda: a.peer.invite == 'Bob')
        a.peer.accept()
        self.pump(a, b, until=lambda: b.peer.phase == 'playing')
        self.assertEqual((a.peer.side, b.peer.side), (1, 0))       # the offerer plays white
        b.peer.cmove(0, 'c3d4')
        self.pump(a, b, until=lambda: a.peer.moves == ['c3d4'])
        a.peer.resign()
        self.pump(a, b, until=lambda: b.peer.result == 1)
        self.assertEqual(a.peer.result, 1)
        self.assertTrue(a.peer.free() and b.peer.free())

    def test_lobby_chat_is_public_to_chess_players(self):
        a = self.client('Alice', None, CheckersPeer)
        c = self.client('Carl')
        self.pump(a, c, until=lambda: a.ready and c.ready)
        c.peer.say('quem joga')
        self.pump(a, c, until=lambda: a.peer.chat)
        self.assertEqual(a.peer.take_chat()[0], [(0, 'CARL: QUEM JOGA')])
        a.peer.seek()                                   # a checkers SEEK is not chat for chess
        a.peer.say('eu')
        self.pump(a, c, until=lambda: c.peer.chat)
        self.assertEqual(c.peer.take_chat()[0], [(0, 'ALICE: EU')])

    def test_busy_room(self):
        room = '#pchess-busy'
        a = self.client('Alice', room, CheckersPeer)
        b = self.client('Bob', room, CheckersPeer)
        self.pump(a, b, until=lambda: a.peer.phase == 'playing')
        c = self.client('Zed', room, CheckersPeer)
        self.pump(a, b, c, until=lambda: 'BUSY' in c.peer.status)


class Commands(Base):
    def test_cjoin_irc_room_through_handle_command(self):
        os.environ['PCHESS_IRC_NICK'] = 'MsxOne'
        config = {'PCHESSROOMS': 'irc'}
        data = p.handle_command('cjoin dama', room_config=config)
        self.addCleanup(lambda: p._irc and p._irc.close())
        self.assertEqual((data[:4], data[4]), (b'PCH1', 1))
        other = self.client('Zoe', '#pchess-dama', CheckersPeer)
        for _ in range(100):
            other.poll()
            data = p.handle_command('cpoll 0', room_config=config)
            if data[5]:
                break
            time.sleep(.05)
        self.assertEqual((data[5], data[6]), (1, 0))   # matched; MsxOne sorts first: white
        p.handle_command('cmove 0 c3d4', room_config=config)
        self.pump(other, until=lambda: other.peer.moves == ['c3d4'])
        other.peer.cmove(1, 'b6a5')
        for _ in range(100):
            data = p.handle_command('cpoll 1', room_config=config)
            if data[240]:
                break
            time.sleep(.05)
        # B6 = row 2 col 1 = 17, A5 = row 3 col 0 = 24
        self.assertEqual((data[240], data[241], tuple(data[120:123])), (1, 2, (2, 17, 24)))
        other.peer.say('ola msx')
        for _ in range(100):
            data = p.handle_command('cpoll 2', room_config=config)
            if data[255]:
                break
            time.sleep(.05)
        rows = p.handle_command('chat', room_config=config)
        self.assertEqual(bytes(rows[8:20]), b'ZOE: OLA MSX')
        self.assertIn(b'Not a chess game', bytes(p.handle_command('move e2e4', room_config=config)[72:]))

    def test_circ_lobby_players(self):
        os.environ['PCHESS_IRC_NICK'] = 'MsxOne'
        data = p.handle_command('circ', room_config={})
        self.addCleanup(lambda: p._irc and p._irc.close())
        self.assertEqual(data[4], 1)
        other = self.client('Zoe', None, CheckersPeer)
        for _ in range(100):
            if other.poll() and other.ready:
                break
            time.sleep(.05)
        other.peer.seek()
        for _ in range(100):
            data = p.handle_command('cplayers', room_config={})
            if data[240]:
                break
            time.sleep(.05)
        self.assertEqual((data[5], data[240], bytes(data[120:123])), (ord('P'), 1, b'Zoe'))
        p.handle_command('coffer Zoe', room_config={})
        for _ in range(100):
            other.poll()
            if other.peer.invite == 'MsxOne':
                break
            time.sleep(.05)
        other.peer.accept()
        for _ in range(100):
            data = p.handle_command('cpoll 0', room_config={})
            if data[5]:
                break
            time.sleep(.05)
        self.assertEqual((data[5], data[6]), (1, 0))   # the offerer plays white


class Reconnect(Base):
    """A dropped IRC link is redialled with the same nick; SYNC repairs lost moves."""
    def start(self):
        room = '#pchess-dama'
        a = self.client('Alice', room, CheckersPeer)
        self.pump(a, until=lambda: a.ready)
        b = self.client('Bob', room, CheckersPeer)
        self.pump(a, b, until=lambda: a.peer.phase == 'playing' and b.peer.phase == 'playing')
        a.peer.cmove(0, 'c3d4')
        self.pump(a, b, until=lambda: b.peer.moves == ['c3d4'])
        return a, b

    def drop(self, nick):
        self.server.clients[nick].connection.shutdown(2)

    def test_game_continues_after_the_link_drops(self):
        self.server.ghost_delay = 3
        a, b = self.start()
        self.drop('Bob')
        self.pump(a, b, until=lambda: b.reconnecting)
        self.assertEqual(b.peer.snapshot()['status'], 'IRC LINK LOST - RECONNECTING')
        with self.assertRaisesRegex(ValueError, 'RECONNECTING'):
            b.peer.cmove(1, 'b6a5')
        self.pump(a, b, until=lambda: b.ready and not b.reconnecting, seconds=15)
        self.assertEqual(b.nick, 'Bob')
        b.peer.cmove(1, 'b6a5')
        self.pump(a, b, until=lambda: a.peer.moves == ['c3d4', 'b6a5'])
        a.peer.cmove(2, 'd4e5')
        self.pump(a, b, until=lambda: b.peer.moves == ['c3d4', 'b6a5', 'd4e5'])

    def test_sync_resends_a_move_made_while_he_was_away(self):
        self.server.ghost_delay = 3
        a, b = self.start()
        b.peer.cmove(1, 'b6a5')
        self.pump(a, b, until=lambda: a.peer.moves == ['c3d4', 'b6a5'])
        self.drop('Bob')
        self.pump(a, b, until=lambda: b.reconnecting)
        a.peer.cmove(2, 'd4e5')        # Bob is offline: the server drops that line
        self.pump(a, b, until=lambda: b.ready and not b.reconnecting, seconds=15)
        self.pump(a, b, until=lambda: b.peer.moves == ['c3d4', 'b6a5', 'd4e5'])

    def test_sync_asks_for_a_move_lost_in_the_dead_socket(self):
        self.server.ghost_delay = 3
        a, b = self.start()
        self.drop('Bob')
        self.pump(a, b, until=lambda: b.reconnecting)
        b.peer.moves.append('b6a5')    # as if Bob's move had gone into the dead socket
        self.pump(a, b, until=lambda: b.ready and not b.reconnecting, seconds=15)
        self.pump(a, b, until=lambda: a.peer.moves == ['c3d4', 'b6a5'])

    def test_both_links_drop_and_the_resent_move_arrives_twice(self):
        self.server.ghost_delay = 3
        a, b = self.start()
        b.peer.cmove(1, 'b6a5')
        self.pump(a, b, until=lambda: a.peer.moves == ['c3d4', 'b6a5'])
        self.drop('Alice')
        self.drop('Bob')
        self.pump(a, b, until=lambda: a.reconnecting and b.reconnecting)
        a.peer.moves.append('d4e5')    # as if Alice's move had gone into her dead socket
        self.pump(a, b, until=lambda: not a.reconnecting and not b.reconnecting, seconds=20)
        self.pump(a, b, until=lambda: sum(text == 'PCH1 CK MOVE 2 d4e5'
                                          for _, _, text in self.server.transcript) == 2)
        self.pump(a, b, until=lambda: b.peer.moves == ['c3d4', 'b6a5', 'd4e5'])
        b.peer.cmove(3, 'a5b4')
        self.pump(a, b, until=lambda: a.peer.moves == ['c3d4', 'b6a5', 'd4e5', 'a5b4'])
        self.assertNotIn('OUT OF SYNC', b.peer.status)


if __name__ == '__main__':
    unittest.main()
