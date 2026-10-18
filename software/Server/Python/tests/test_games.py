"""Game invitations (msxpi_games) and their use in the chat (msxpi_chat).

The first part drives two Invites objects directly; the second runs two chats against the local IRC
fixture with real msxpi_netplay sessions and checks that the MSX would be told to start the game, and
that the two sessions then find each other.  A made-up second game shows nothing is soccer-specific.
"""
import os
import sys
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from pchess_irc_fixture import Server
import msxpi_chat
import msxpi_games as g
import msxpi_netplay as n


def wait(check, seconds=5):
    end = time.time() + seconds
    while time.time() < end:
        if check():
            return True
        time.sleep(0.02)
    return False


class FakeNetplay:
    def __init__(self):
        self.calls = []
        self.version = 1

    def open(self):
        self.calls.append('open')

    def candidates(self):
        return ['10.0.0.%d:5000' % (len(self.calls) + 1)]

    def set_peers(self, peers):
        self.calls.append(('peers', peers))

    def close(self):
        self.calls.append('close')

    def describe(self):
        return 'playing'


class Pair:
    """Two Invites wired together like two chats."""

    def __init__(self, games=None, clock=None):
        self.said = {'a': [], 'b': []}
        self.np = {'a': FakeNetplay(), 'b': FakeNetplay()}
        games = games or g.load_registry()
        kw = {'clock': clock} if clock else {}
        self.a = g.Invites(games, lambda nick, text: self.b.on_message('alice', text),
                           self.said['a'].append, lambda: self.np['a'], **kw)
        self.b = g.Invites(games, lambda nick, text: self.a.on_message('bob', text),
                           self.said['b'].append, lambda: self.np['b'], **kw)


class Registry(unittest.TestCase):
    def test_builtin_and_ini_games(self):
        reg = g.load_registry({'MSXGAME_tanks': 'Tanks|TANKS {role} {peer}|RED,BLUE|netplay|3'})
        self.assertEqual(sorted(reg), ['soccer', 'tanks'])
        self.assertEqual(reg['tanks'].command('BLUE', 'bob', 'abcd1234'), 'TANKS BLUE bob')
        self.assertEqual(reg['tanks'].version, 3)
        self.assertEqual(reg['soccer'].command('H', 'bob', 'x'), 'SOCCERNET H')

    def test_bad_entries_are_ignored(self):
        reg = g.load_registry({'MSXGAME_bad': 'Bad|RUN ; DEL *|A,B|netplay',
                               'MSXGAME_x': 'only|two'})
        self.assertEqual(sorted(reg), ['soccer'])

    def test_command_is_validated(self):
        with self.assertRaises(ValueError):
            g.Game('evil', 'Evil', 'RUN {role}&', ['A', 'B'])
        with self.assertRaises(ValueError):
            g.Game('Caps', 'x', 'RUN', ['A', 'B'])
        with self.assertRaises(ValueError):
            g.Game('one', 'x', 'RUN', ['A'])


class Flow(unittest.TestCase):
    def test_invite_accept_launch_both_sides(self):
        p = Pair()
        p.a.play('bob', 'soccer')
        self.assertEqual(p.b.phase, 'invited')
        self.assertEqual(p.b.flags(), g.FLAG_INVITED)
        self.assertIn('invites you', p.said['b'][-1])
        p.b.accept()
        self.assertEqual(p.a.phase, 'ready')
        self.assertEqual(p.b.phase, 'ready')
        self.assertEqual(p.a.flags(), g.FLAG_LAUNCH)
        # the inviter opens and learns bob's address; bob learns alice's from GO
        self.assertIn(('peers', [('10.0.0.2', 5000)]), p.np['a'].calls)
        self.assertTrue(any(c[0] == 'peers' for c in p.np['b'].calls if isinstance(c, tuple)))
        self.assertEqual(p.a.take_launch(), 'SOCCERNET H')        # inviter = seat 0
        self.assertEqual(p.b.take_launch(), 'SOCCERNET C')
        self.assertIsNone(p.a.take_launch())                      # only once
        self.assertEqual(p.a.phase, 'launched')

    def test_other_game_same_machinery(self):
        reg = g.load_registry({'MSXGAME_tanks': 'Tanks|TANKS {role} {peer}|RED,BLUE|none|2'})
        p = Pair(reg)
        p.a.play('bob', 'tanks')
        p.b.accept()
        self.assertEqual(p.a.take_launch(), 'TANKS RED bob')
        self.assertEqual(p.b.take_launch(), 'TANKS BLUE alice')
        self.assertEqual(p.np['a'].calls, [])                      # transport "none": no network set-up

    def test_decline_and_busy(self):
        p = Pair()
        p.a.play('bob')
        p.b.decline()
        self.assertEqual(p.a.phase, 'idle')
        self.assertIn('declined', p.said['a'][-1])
        p.a.play('bob')
        with self.assertRaises(ValueError):
            p.a.play('carol')                                       # one at a time
        p.b.on_message('carol', 'MSXG1 INVITE soccer 1 deadbeef')   # a second inviter while busy
        self.assertEqual(p.b.peer, 'alice')

    def test_cancel_by_either_side(self):
        p = Pair()
        p.a.play('bob')
        p.a.cancel()
        self.assertEqual(p.b.phase, 'idle')
        self.assertIn('cancelled', p.said['b'][-1])
        p.a.play('bob')
        p.b.accept()
        p.b.cancel()
        self.assertEqual(p.a.phase, 'idle')
        self.assertIn('close', p.np['a'].calls)

    def test_version_and_unknown_game_are_declined(self):
        reg_b = g.load_registry({'MSXGAME_soccer': "Konami's Soccer|SOCCERNET {role}|H,C|netplay|2"})
        said_a = []
        a = g.Invites(g.load_registry(), lambda nick, text: b.on_message('alice', text), said_a.append,
                      FakeNetplay)
        b = g.Invites(reg_b, lambda nick, text: a.on_message('bob', text), [].append, FakeNetplay)
        a.play('bob')
        self.assertEqual(a.phase, 'idle')
        self.assertIn('declined', said_a[-1])
        a.games['zzz'] = g.Game('zzz', 'Z', 'Z {role}', ['A', 'B'])
        a.play('bob', 'zzz')
        self.assertEqual(a.phase, 'idle')

    def test_stale_answers_are_ignored(self):
        p = Pair()
        p.a.play('bob')
        p.a.on_message('bob', 'MSXG1 ACCEPT 00000000 1.2.3.4:5')   # wrong token
        self.assertEqual(p.a.phase, 'inviting')
        p.a.on_message('mallory', 'MSXG1 ACCEPT %s 1.2.3.4:5' % p.a.token)   # wrong sender
        self.assertEqual(p.a.phase, 'inviting')

    def test_no_address_fails_the_game(self):
        p = Pair()
        p.a.play('bob')
        p.a.on_message('bob', 'MSXG1 ACCEPT %s -' % p.a.token)
        self.assertEqual(p.a.phase, 'idle')
        self.assertIn('failed', p.said['a'][-1])

    def test_invitation_expires(self):
        now = [0.0]
        p = Pair(clock=lambda: now[0])
        p.a.play('bob')
        now[0] = g.INVITE_TTL + 1
        self.assertEqual(p.b.flags(), 0)
        self.assertEqual(p.b.phase, 'idle')
        self.assertIn('expired', p.said['b'][-1])
        p.a.play('bob')                      # the old one is gone: a new one is possible
        self.assertEqual(p.a.phase, 'inviting')

    def test_ready_game_not_started_in_time(self):
        now = [0.0]
        p = Pair(clock=lambda: now[0])
        p.a.play('bob')
        p.b.accept()
        now[0] = g.LAUNCH_TTL + 1
        self.assertIsNone(p.a.take_launch())
        self.assertEqual(p.a.phase, 'idle')

    def test_resume_reports_and_releases(self):
        p = Pair()
        p.a.play('bob')
        p.b.accept()
        p.a.take_launch()
        p.a.resumed()
        self.assertEqual(p.a.phase, 'idle')
        self.assertIn('ended (playing)', p.said['a'][-1])
        self.assertIn('close', p.np['a'].calls)


class InChat(unittest.TestCase):
    """Two real chats on the IRC fixture and two real netplay sessions."""

    def setUp(self):
        self.server = Server(('127.0.0.1', 0))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        port = self.server.server_address[1]
        self.env = patch.dict(os.environ, {'PCHESS_IRC_HOST': '127.0.0.1', 'PCHESS_IRC_PORT': str(port),
                                           'PCHESS_IRC_TLS': '0', 'MSXPI_NETPLAY_NOSTUN': '1',
                                           'MSXPI_NETPLAY_LAN': '127.0.0.1'})
        self.env.start()
        self.np = {'alice': n.Netplay(None, None, {}, lambda *a: None),
                   'bob': n.Netplay(None, None, {}, lambda *a: None)}
        self.chat = {}
        for nick in ('alice', 'bob'):
            c = msxpi_chat.ChatIRC({'IRCNICK': nick}, '#msxpi', 40, netplay=lambda nick=nick: self.np[nick])
            self.chat[nick] = c
        self.assertTrue(wait(lambda: all(c.ready and c.rooms[0].joined for c in self.chat.values())))

    def tearDown(self):
        for c in self.chat.values():
            c.close()
        for np in self.np.values():
            np.close()
        self.env.stop()
        self.server.shutdown()
        self.server.server_close()

    def texts(self, nick):
        return [r[2] for r in self.chat[nick].rooms[0].rows]

    def test_play_from_invitation_to_connected_sessions(self):
        self.chat['alice'].say('/play bob soccer')
        self.assertTrue(wait(lambda: self.chat['bob'].invites.phase == 'invited'))
        self.assertTrue(any('invites you' in t for t in self.texts('bob')))
        self.assertEqual(msxpi_chat.launch_packet(self.chat['bob'])[6], 0)    # nothing to start yet
        self.assertEqual(self.chat['bob'].rows_packet(0, 0)[22], g.FLAG_INVITED)
        self.chat['bob'].say('/accept')
        self.assertTrue(wait(lambda: self.chat['alice'].invites.phase == 'ready'
                             and self.chat['bob'].invites.phase == 'ready'))
        self.assertEqual(self.chat['alice'].rows_packet(0, 0)[22], g.FLAG_LAUNCH)
        pa, pb = msxpi_chat.launch_packet(self.chat['alice']), msxpi_chat.launch_packet(self.chat['bob'])
        self.assertEqual((pa[5:6], pa[6], pa[24:35]), (b'L', 1, b'SOCCERNET H'))
        self.assertEqual(pb[24:35], b'SOCCERNET C')
        self.assertEqual(msxpi_chat.launch_packet(self.chat['alice'])[6], 0)  # once
        # the MSX programs would now ask the Pi to start the session (flags 0x40): do it here
        self.np['alice'].restart()
        self.np['bob'].restart()
        self.assertTrue(wait(lambda: self.np['alice'].state == n.S_READY and self.np['bob'].state == n.S_READY, 10))
        self.assertEqual(self.np['alice'].delay, self.np['bob'].delay)
        # game traffic is never shown as chat
        self.assertFalse(any('MSXG1' in t for t in self.texts('alice') + self.texts('bob')))

    def test_game_messages_in_a_room_are_ignored(self):
        self.server.clients['bob'].send(':alice!t@h PRIVMSG #msxpi :MSXG1 INVITE soccer 1 deadbeef')
        time.sleep(0.3)
        self.assertEqual(self.chat['bob'].invites.phase, 'idle')
        self.assertFalse(any('MSXG1' in t for t in self.texts('bob')))

    def test_errors_show_up_as_chat_lines(self):
        for line in ('/play', '/play alice', '/accept', '/decline', '/cancel', '/play bob nosuchgame'):
            with self.assertRaises(ValueError):          # handle_command turns these into '! ...' lines
                self.chat['alice'].say(line)
        self.assertEqual(self.chat['alice'].invites.phase, 'idle')


if __name__ == '__main__':
    unittest.main()
