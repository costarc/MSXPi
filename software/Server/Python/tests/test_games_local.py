"""Conformance: games_local.c (MCHAT /t's MSXG1 invitations, C) against Invites (the Pi's, Python).

alice is the Pi's Invites, bob is games_local built with gcc (Client/tests/games_local_host.c); each one's
private messages are delivered to the other. Skipped when there is no gcc (on Windows: run it under WSL).
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_games as g


class FakeNetplay:
    """What Invites needs from a session object (as test_games.FakeNetplay; that module needs python-chess)."""

    def __init__(self):
        self.calls = []
        self.profile_hash = 0

    def open(self):
        self.calls.append('open')

    def candidates(self):
        return ['10.0.0.2:5000']

    def set_peers(self, peers):
        self.calls.append(('peers', peers))

    def close(self):
        self.calls.append('close')

    def describe(self):
        return 'playing'

CLIENT = Path(__file__).resolve().parents[3] / 'Client'
HASH = 0x2E4A3A94


class Bob:
    """games_local as a subprocess, one command at a time."""

    def __init__(self, exe, alice):
        self.alice = alice
        self.proc = subprocess.Popen([exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.said, self.sent, self.out = [], [], []

    def cmd(self, line):
        self.proc.stdin.write(line + '\n')
        self.proc.stdin.flush()
        replies = []
        while True:
            r = self.proc.stdout.readline().rstrip('\n')
            if r == 'OK':
                break
            replies.append(r)
        for r in replies:
            kind, _, rest = r.partition(' ')
            if kind == 'SAY':
                self.said.append(rest)
            elif kind == 'SEND':
                nick, _, text = rest.partition(' ')
                self.sent.append((nick, text))
                if nick == 'alice':
                    self.alice.on_message('bob', text)
            else:
                self.out.append(r)
        return replies

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(5)
        self.proc.stdout.close()


@unittest.skipUnless(shutil.which('gcc'), 'needs gcc (run under WSL on Windows)')
class Conformance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.exe = os.path.join(cls.tmp, 'games_local_host')
        subprocess.run(['gcc', '-std=c99', '-Wall', '-I', str(CLIENT / 'src'), '-o', cls.exe,
                        str(CLIENT / 'tests/games_local_host.c'), str(CLIENT / 'src/games_local.c')], check=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def setUp(self, alice_hash=HASH):
        self.np = FakeNetplay()
        self.alice_said = []
        games = {'soccer': g.Game('soccer', "Konami's Soccer", ['H', 'C'], 'lockstep', '', alice_hash)}
        self.alice = g.Invites(games, lambda nick, text: self.bob.cmd('msg alice ' + text),
                               self.alice_said.append, lambda: self.np, clock=lambda: self.t)
        self.t = 1000.0
        self.bob = Bob(self.exe, self.alice)
        self.bob.cmd('game soccer Soccer H C %08x' % HASH)
        self.bob.cmd('open 10.0.2.2:5102')

    def tearDown(self):
        self.bob.close()

    def flags(self):
        self.bob.cmd('flags')
        return int(self.bob.out.pop().split()[1])

    def session(self):
        self.bob.cmd('session')
        return bytes.fromhex(self.bob.out.pop().split()[1])

    def test_link2_hands_the_opponent_to_the_msxpi_and_marks_the_session(self):
        self.bob.cmd('link2')                                               # bob's game port is his MSXPi's
        self.alice.play('bob', 'soccer')
        self.bob.cmd('accept')
        self.assertEqual(self.alice.phase, 'ready')
        peers = [line for line in self.bob.out if line.startswith('PEERS ')]
        self.assertEqual(len(peers), 1)
        _, token, seat, game, cands = peers[0].split()
        self.assertEqual((token, seat, game), (self.alice.token, '1', 'soccer'))
        self.assertTrue(cands)                                              # alice's candidates
        self.bob.cmd('launch')
        rec = self.session()
        self.assertEqual((rec[8], rec[9]), (1, 2))                          # seat 1, link 2
        self.assertEqual(int.from_bytes(rec[10:12], 'little'), 0)           # no UDP port of the MSX's

    def test_alice_invites_bob(self):
        self.alice.play('bob', 'soccer')
        self.assertEqual(self.flags(), 2)                                   # invited
        self.assertIn('alice invites you to play Soccer', self.bob.said)
        self.bob.cmd('accept')
        self.assertEqual(self.alice.phase, 'ready')
        self.assertIn(('peers', [('10.0.2.2', 5102)]), self.np.calls)      # alice will punch towards bob
        self.assertEqual(self.flags(), 1)                                   # launch
        self.bob.cmd('launch')
        self.assertEqual(self.bob.out.pop(), 'LAUNCH PLAYNET /T')
        rec = self.session()
        self.assertEqual(rec[:4], b'PNS1')
        self.assertEqual(rec[4:8].hex(), self.alice.token)
        self.assertEqual((rec[8], rec[9]), (1, 1))                          # seat 1, TCP/IP
        self.assertEqual(int.from_bytes(rec[10:12], 'little'), 5102)
        self.assertEqual(int.from_bytes(rec[12:16], 'little'), HASH)
        self.assertEqual(rec[16:24], b'SOCCER  ')
        self.assertEqual(rec[24:29], b'alice')
        self.assertEqual(rec[40], 1)                                        # alice's candidate
        self.assertEqual(rec[41:47], bytes([10, 0, 0, 2]) + (5000).to_bytes(2, 'little'))

    def test_bob_invites_alice(self):
        self.bob.cmd('play alice soccer')
        self.assertEqual(self.alice.phase, 'invited')
        self.alice.accept()
        self.assertEqual(self.alice.phase, 'ready')
        self.assertEqual(self.flags(), 1)
        self.bob.cmd('launch')
        rec = self.session()
        self.assertEqual(rec[4:8].hex(), self.alice.token)
        self.assertEqual(rec[8], 0)                                         # the inviter is seat 0
        self.assertEqual(self.alice.seat, 1)

    def test_decline(self):
        self.bob.cmd('play alice')
        self.alice.decline()
        self.assertIn('alice declined the game', self.bob.said)
        self.assertEqual(self.flags(), 0)

    def test_different_version(self):
        self.tearDown()
        self.setUp(alice_hash=HASH + 1)
        self.alice.play('bob', 'soccer')
        self.assertEqual(self.alice.phase, 'idle')                          # bob declined: profile
        self.assertTrue(any('different version' in s for s in self.alice_said))

    def test_unknown_game(self):
        self.alice.games['other'] = g.Game('other', 'Other', ['A', 'B'], 'lockstep', '', 7)
        self.alice.play('bob', 'other')
        self.assertEqual(self.alice.phase, 'idle')
        self.assertTrue(any('does not have that game' in s for s in self.alice_said))

    def test_busy(self):
        self.bob.cmd('play carol')                                          # bob is inviting carol
        self.alice.play('bob', 'soccer')
        self.assertEqual(self.alice.phase, 'idle')
        self.assertTrue(any('is busy' in s for s in self.alice_said))

    def test_cancel(self):
        self.bob.cmd('play alice')
        self.bob.cmd('cancel')
        self.assertEqual(self.alice.phase, 'idle')
        self.assertTrue(any('cancelled' in s for s in self.alice_said))

    def test_invitation_expires(self):
        self.bob.cmd('time 100')
        self.bob.cmd('play alice')
        self.bob.cmd('time 221')
        self.assertEqual(self.flags(), 0)
        self.assertIn('Game invitation expired', self.bob.said)

    def test_result_after_the_game(self):
        self.alice.play('bob', 'soccer')
        self.bob.cmd('accept')
        self.bob.cmd('launch')
        self.bob.cmd('resumed 1')
        self.assertEqual(self.bob.said[-1], 'Game with alice ended (you ended it)')


if __name__ == '__main__':
    unittest.main()
