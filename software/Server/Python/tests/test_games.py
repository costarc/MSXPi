"""Game invitations (msxpi_games) and their use in the chat (msxpi_chat).

The first part drives two Invites objects directly; the second runs two chats against the local IRC
fixture with real msxpi_netplay sessions and checks that the MSX would be told to start the game, and
that the two sessions then find each other.  A second game with transport "none" shows nothing is
soccer-specific.  The games are real GPF files (gpf_fixture.py) in a temporary games folder.
"""
import os
import shutil
import struct
import sys
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from pchess_irc_fixture import Server
import gpf_fixture as fx
import msxpi_chat
import msxpi_games as g
import msxpi_netplay as n

GAMES = fx.games_dir()
SOCCER_HASH = '%08x' % struct.unpack_from('<I', fx.SOCCER, 8)[0]


def tearDownModule():
    shutil.rmtree(GAMES, ignore_errors=True)


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
        self.profile_hash = 0

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

    def __init__(self, games=None, games_b=None, clock=None):
        self.said = {'a': [], 'b': []}
        self.np = {'a': FakeNetplay(), 'b': FakeNetplay()}
        games = games or g.load_registry(GAMES)
        kw = {'clock': clock} if clock else {}
        self.a = g.Invites(games, lambda nick, text: self.b.on_message('alice', text),
                           self.said['a'].append, lambda: self.np['a'], **kw)
        self.b = g.Invites(games_b or games, lambda nick, text: self.a.on_message('bob', text),
                           self.said['b'].append, lambda: self.np['b'], **kw)


class Registry(unittest.TestCase):
    def test_games_come_from_the_gpf_files(self):
        reg = g.load_registry(GAMES)
        self.assertEqual(sorted(reg), ['soccer', 'tanks'])
        soccer, tanks = reg['soccer'], reg['tanks']
        self.assertEqual((soccer.title, soccer.roles, soccer.transport), ("Konami's Soccer", ['H', 'C'], 'lockstep'))
        self.assertEqual(soccer.hash_text, SOCCER_HASH)
        self.assertEqual(soccer.gpf, fx.SOCCER)
        self.assertEqual(soccer.command('C', 'bob', 'x'), 'PLAYNET')               # lockstep: always PLAYNET
        self.assertEqual(tanks.command('BLUE', 'bob', 'abcd1234'), 'TANKS /BLUE bob')

    def test_bad_files_are_ignored(self):
        damaged = bytearray(fx.SOCCER)
        damaged[200] ^= 1
        logged = []
        folder = fx.games_dir(('SOCCER.GPF', bytes(damaged)), ('OTHER.GPF', fx.TANKS),     # wrong file name
                              ('JUNK.GPF', b'not a gpf'), ('README.TXT', b'x'), ('TANKS.GPF', fx.TANKS))
        try:
            self.assertEqual(sorted(g.load_registry(folder, logged.append)), ['tanks'])
            self.assertEqual(len(logged), 3)
        finally:
            shutil.rmtree(folder)

    def test_missing_folder_means_no_games(self):
        self.assertEqual(g.load_registry(os.path.join(GAMES, 'nowhere')), {})
        p = Pair()
        p.a.games = {}
        with self.assertRaisesRegex(ValueError, 'No games installed'):
            p.a.play('bob')

    def test_command_is_validated(self):
        with self.assertRaises(ValueError):
            g.Game('evil', 'Evil', ['A', 'B'], 'none', 'RUN {role}&')
        with self.assertRaises(ValueError):
            g.Game('Caps', 'x', ['A', 'B'])
        with self.assertRaises(ValueError):
            g.Game('one', 'x', ['A'])


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
        self.assertEqual(p.np['a'].profile_hash, int(SOCCER_HASH, 16))         # the handshake checks it again
        self.assertEqual(p.a.take_launch(), 'PLAYNET')
        self.assertEqual(p.b.take_launch(), 'PLAYNET')
        self.assertIsNone(p.a.take_launch())                      # only once
        self.assertEqual(p.a.phase, 'launched')

    def test_invitation_carries_the_profile_hash(self):
        sent = []
        a = g.Invites(g.load_registry(GAMES), lambda nick, text: sent.append(text), [].append, FakeNetplay)
        a.play('bob')
        self.assertEqual(sent[0], 'MSXG1 INVITE soccer %s %s' % (SOCCER_HASH, a.token))

    def test_other_game_same_machinery(self):
        p = Pair()
        p.a.play('bob', 'tanks')
        p.b.accept()
        self.assertEqual(p.a.take_launch(), 'TANKS /RED bob')
        self.assertEqual(p.b.take_launch(), 'TANKS /BLUE alice')
        self.assertEqual(p.np['a'].calls, [])                      # transport "none": no network set-up
        self.assertIsNone(p.a.session_record())                    # and nothing for PLAYNET

    def test_decline_and_busy(self):
        p = Pair()
        p.a.play('bob')
        p.b.decline()
        self.assertEqual(p.a.phase, 'idle')
        self.assertIn('declined', p.said['a'][-1])
        p.a.play('bob')
        with self.assertRaises(ValueError):
            p.a.play('carol')                                       # one at a time
        p.b.on_message('carol', 'MSXG1 INVITE soccer %s deadbeef' % SOCCER_HASH)   # a second inviter while busy
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

    def test_different_versions_are_declined(self):
        folder = fx.games_dir(('SOCCER.GPF', fx.SOCCER_OTHER_VERSION))
        try:
            p = Pair(games_b=g.load_registry(folder))
            p.a.play('bob')
            self.assertEqual(p.a.phase, 'idle')
            self.assertIn('different version', p.said['a'][-1])
            self.assertIn('versions differ', p.said['b'][-1])
        finally:
            shutil.rmtree(folder)

    def test_unknown_game_is_declined(self):
        folder = fx.games_dir(('SOCCER.GPF', fx.SOCCER))
        self.addCleanup(shutil.rmtree, folder)
        p = Pair(games_b=g.load_registry(folder))
        p.a.play('bob', 'tanks')
        self.assertEqual(p.a.phase, 'idle')
        self.assertIn('does not have that game', p.said['a'][-1])
        self.assertIn('not installed', p.said['b'][-1])

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

    def launched(self):
        p = Pair()
        p.a.play('bob')
        p.b.accept()
        p.a.take_launch()
        p.b.take_launch()
        return p

    def test_session_record(self):
        p = self.launched()
        self.assertIsNone(Pair().a.session_record())               # nothing launched
        rec = p.b.session_record()
        self.assertEqual(len(rec), 40)
        self.assertEqual(rec[0:4], b'PNS1')
        self.assertEqual(rec[4:8].hex(), p.b.token)
        self.assertEqual((rec[8], rec[9], struct.unpack_from('<H', rec, 10)[0]), (1, 0, 0))   # seat 1, MSXPi
        self.assertEqual('%08x' % struct.unpack_from('<I', rec, 12)[0], SOCCER_HASH)
        self.assertEqual(rec[16:24], b'SOCCER  ')
        self.assertEqual(rec[24:32], b'alice\0\0\0')
        self.assertEqual((rec[32], rec[33]), (1, 0))                 # started, no result yet
        self.assertEqual(p.a.session_record()[8], 0)                 # the inviter is seat 0

    def test_result_is_reported_on_resume(self):
        p = self.launched()
        p.a.session_record()
        p.a.report(2)
        self.assertEqual(p.a.session_record()[32:34], b'\x02\x02')   # finished, ended by the opponent
        with self.assertRaises(ValueError):
            p.a.report(99)
        p.a.resumed()
        self.assertEqual(p.a.phase, 'idle')
        self.assertIn('ended (the opponent ended it)', p.said['a'][-1])
        self.assertIn('close', p.np['a'].calls)

    def test_resume_without_a_result(self):
        p = self.launched()
        p.a.resumed()                                               # PLAYNET never asked for the session
        self.assertIn('ended (not started)', p.said['a'][-1])
        p.b.session_record()
        p.b.resumed()
        self.assertIn('ended (playing)', p.said['b'][-1])           # what the session object says

    def test_resume_after_playnet_ended_the_game(self):
        p = self.launched()
        p.b.session_record()
        p.np['b'].local_result = 1                                  # PLAYNET's XEND: the exit key here
        p.b.resumed()
        self.assertIn('ended (you ended it)', p.said['b'][-1])


class PlaynetCommands(unittest.TestCase):
    """playnet_command(), what the MSXPi command "playnet ..." runs."""

    def setUp(self):
        self.p = Pair()

        class Chat:
            invites = self.p.a
        self.saved = (msxpi_chat._chat, msxpi_chat._saved)
        msxpi_chat._chat = Chat()

    def tearDown(self):
        msxpi_chat._chat, msxpi_chat._saved = self.saved

    def run_command(self, text, upload=None):
        return msxpi_chat.playnet_command(text, upload, GAMES)

    def test_no_game_waiting(self):
        self.assertEqual(self.run_command('session'), (False, 'No game is waiting: start it from MCHAT'))
        self.assertFalse(self.run_command('save', b'x')[0])
        self.assertFalse(self.run_command('result 1')[0])

    def test_profile_is_served_by_id(self):
        self.assertEqual(self.run_command('profile soccer'), (True, fx.SOCCER))
        self.assertEqual(self.run_command('profile SOCCER'), (True, fx.SOCCER))
        self.assertFalse(self.run_command('profile tanks')[0])     # its own program: no GPF to load
        self.assertFalse(self.run_command('profile nope')[0])
        msxpi_chat._chat = None                                   # works before the chat started too
        self.assertEqual(self.run_command('profile soccer'), (True, fx.SOCCER))

    def test_session_save_restore_result(self):
        self.p.a.play('bob')
        self.p.b.accept()
        self.p.a.take_launch()
        ok, record = self.run_command('session')
        self.assertTrue(ok)
        self.assertEqual(record[:4], b'PNS1')
        self.assertEqual(self.run_command('save', b'D' * 14000), (True, b'OK'))
        self.assertFalse(self.run_command('save', b'D' * (msxpi_chat.SAVE_MAX + 1))[0])
        self.assertEqual(self.run_command('restore'), (True, b'D' * 14000))
        self.assertFalse(self.run_command('restore')[0])           # once
        self.assertEqual(self.run_command('result 1'), (True, b'OK'))
        self.assertEqual(self.p.a.result, 1)
        self.assertFalse(self.run_command('result x')[0])
        self.assertFalse(self.run_command('dance')[0])


class InChat(unittest.TestCase):
    """Two real chats on the IRC fixture and two real netplay sessions."""

    def setUp(self):
        self.server = Server(('127.0.0.1', 0))
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        port = self.server.server_address[1]
        self.env = patch.dict(os.environ, {'PCHESS_IRC_HOST': '127.0.0.1', 'PCHESS_IRC_PORT': str(port),
                                           'PCHESS_IRC_TLS': '0', 'MSXPI_NETPLAY_NOSTUN': '1',
                                           'MSXPI_NETPLAY_LAN': '127.0.0.1', 'MSXPI_GAMES_DIR': GAMES})
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
        self.assertEqual((pa[5:6], pa[6], pa[24:32]), (b'L', 1, b'PLAYNET\0'))
        self.assertEqual(pb[24:32], b'PLAYNET\0')
        self.assertEqual(msxpi_chat.launch_packet(self.chat['alice'])[6], 0)  # once
        # PLAYNET on each MSX would now start the session (flags 0x40): do it here
        self.np['alice'].restart()
        self.np['bob'].restart()
        self.assertTrue(wait(lambda: self.np['alice'].state == n.S_READY and self.np['bob'].state == n.S_READY, 10))
        self.assertEqual(self.np['alice'].delay, self.np['bob'].delay)
        self.assertEqual(self.np['alice'].profile_hash, int(SOCCER_HASH, 16))
        # game traffic is never shown as chat
        self.assertFalse(any('MSXG1' in t for t in self.texts('alice') + self.texts('bob')))

    def test_game_messages_in_a_room_are_ignored(self):
        self.server.clients['bob'].send(':alice!t@h PRIVMSG #msxpi :MSXG1 INVITE soccer %s deadbeef' % SOCCER_HASH)
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
