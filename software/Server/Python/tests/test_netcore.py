"""Conformance: netcore (the MSX's MSXNP engine, C) against Netplay (the Pi's, Python) over localhost UDP.

The design's mixed-match test (PLAYNET-DESIGN.md 5.6/5.7): the C engine is built with gcc
(Client/src/playnet/netcore/host/netcore_host.c) and plays one side; a Netplay with its MSX side simulated by
opcode C9 transactions (as in test_netplay) plays the other. Skipped when there is no gcc (on Windows, run it
under WSL: python3 -m unittest test_netcore).
"""
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_netplay as n
from test_netplay import free_ports, packet, txn, wait_for

NETCORE = Path(__file__).resolve().parents[3] / 'Client/src/playnet/netcore'
PROFILE = 0x2E4A3A94
LEADER, FOLLOWER = 'FFFFFFFF', '00000001'      # forced first nonce of the C side


class Host:
    """netcore_host as a subprocess; its output lines are collected as they come."""

    def __init__(self, exe, lport, pport, frames, bye_at=0, width=1, version=2, nonce='0', profile=PROFILE, k=1, s=0):
        args = [exe, str(lport), '127.0.0.1', str(pport), '%08x' % profile, str(frames), str(bye_at), str(width),
                str(version), nonce, str(k), str(s)]
        self.proc = subprocess.Popen(args, stdout=subprocess.PIPE, text=True)
        self.lines = []
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            self.lines.append(line.strip())

    def has(self, prefix):
        return any(line.startswith(prefix) for line in self.lines)

    def first(self, prefix):
        return next((line for line in self.lines if line.startswith(prefix)), None)

    def finish(self, seconds=20):
        try:
            self.proc.wait(seconds)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        time.sleep(0.1)
        self.proc.stdout.close()
        return self.lines


@unittest.skipUnless(shutil.which('gcc'), 'needs gcc (run under WSL on Windows)')
class Conformance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.exe = os.path.join(cls.tmp, 'netcore_host')
        subprocess.run(['gcc', '-O2', '-Wall', '-std=c99', '-D_POSIX_C_SOURCE=200809L', '-I', str(NETCORE),
                        '-o', cls.exe, str(NETCORE / 'host/netcore_host.c'), str(NETCORE / 'netcore.c')], check=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def start(self, py_nonce=0x80000000, profile=PROFILE, py_k=1, py_s=0, **host):
        self.cport, self.pport = free_ports(2)
        env = {'MSXPI_NETPLAY': '%d:127.0.0.1:%d' % (self.pport, self.cport), 'MSXPI_NETPLAY_PROFILE': '%08x' % profile,
               'MSXPI_NETPLAY_K': str(py_k), 'MSXPI_NETPLAY_S': str(py_s)}
        self.py = n.Netplay(None, None, env, lambda *a: None)
        with self.py.lock:                      # no HELLO goes out with the random nonce in between
            self.py.restart()
            self.py.nonce = py_nonce
        self.host = Host(self.exe, self.cport, self.pport, **host)

    def tearDown(self):
        if getattr(self, 'host', None):
            self.host.finish(1)
        if getattr(self, 'py', None) and self.py.sock:
            self.py.sock.close()

    def play(self, frames, width=1):
        """The Pi side's MSX: one transaction per 20 ms frame, sending a game packet; returns packets received."""
        got = []
        for seq in range(frames):
            out = txn(self.py, 3, packet(seq & 0xFF, width))
            if len(out) > 2:
                got.append(out[1:-1])
            time.sleep(0.02)
        for _ in range(50):                     # what is still in flight
            out = txn(self.py, 2)
            if len(out) > 2:
                got.append(out[1:-1])
            time.sleep(0.02)
        return got

    def ready_pair(self, nonce):
        self.start(nonce=nonce, frames=100)
        self.assertTrue(wait_for(lambda: self.py.state == n.S_READY and self.host.has('STATUS 1'), 15),
                        self.host.lines)
        ready = self.host.first('STATUS 1').split()
        self.assertEqual(int(ready[3]), self.py.delay)               # the same input delay on both sides
        self.assertEqual(ready[5], '1' if nonce == LEADER else '0')  # the higher nonce leads
        self.assertEqual(self.py.leader, nonce == FOLLOWER)

    def exchange(self, width=1):
        got = self.play(100, width)
        lines = self.host.finish()
        self.assertGreaterEqual(len(got), 95)                         # netcore -> Netplay
        self.assertTrue(all(n.game_packet_ok(bytes(p)) and p[3] == width for p in got))
        rx = int(lines[-1].split('=')[1])
        self.assertGreaterEqual(rx, 95, lines[-3:])                   # Netplay -> netcore

    def test_netcore_follows(self):
        self.ready_pair(FOLLOWER)
        self.exchange()

    def test_netcore_leads(self):
        self.ready_pair(LEADER)
        self.exchange()

    def test_k_and_s_are_agreed_with_the_leader_on_either_side(self):
        for nonce in (LEADER, FOLLOWER):                # netcore announces K 2, S 1; Netplay K 1, S 0
            self.start(nonce=nonce, frames=100, k=2, s=1)
            self.assertTrue(wait_for(lambda: self.py.state == n.S_READY and self.host.has('STATUS 1'), 15),
                            self.host.lines)
            ready = self.host.first('STATUS 1').split()
            self.assertEqual(self.py.k, 2)
            self.assertEqual(int(ready[7]), 2)                       # netcore's K
            self.assertEqual(int(ready[3]), self.py.delay)           # the delay includes K - 1 and S
            self.assertIn(self.py.delay, (4, 5))                     # 2 or 3 (netcore's clock has 10 ms steps) + (K - 1) + S
            self.host.finish(1)
            self.py.sock.close()

    def test_four_input_bytes_per_frame(self):
        self.start(nonce=LEADER, frames=100, width=4)
        self.assertTrue(wait_for(lambda: self.py.state == n.S_READY and self.host.has('STATUS 1'), 15))
        self.exchange(width=4)

    def test_different_profile_is_incompatible_on_both_sides(self):
        self.start(nonce=LEADER, frames=10, profile=PROFILE + 1)
        self.assertTrue(wait_for(lambda: self.py.state == n.S_INCOMPATIBLE and self.host.has('STATUS 2'), 15),
                        (self.py.state, self.host.lines))
        self.assertEqual(txn(self.py, 0x80)[0], 0xA0 + n.ST_INCOMPATIBLE)

    def test_different_version_is_incompatible_on_both_sides(self):
        self.start(nonce=FOLLOWER, frames=10, version=3)
        self.assertTrue(wait_for(lambda: self.py.state == n.S_INCOMPATIBLE and self.host.has('STATUS 2'), 15))

    def test_bye_from_netcore(self):
        self.start(nonce=FOLLOWER, frames=200, bye_at=30)
        self.assertTrue(wait_for(lambda: self.py.state == n.S_READY, 15))
        for seq in range(120):
            out = txn(self.py, 3, packet(seq))
            if out[:1] == b'\xfe':
                break
            time.sleep(0.02)
        self.assertEqual(out, b'\xfe\x01')                            # the opponent left, result 1 (its exit key)
        self.host.finish()

    def test_bye_from_netplay(self):
        self.start(nonce=LEADER, frames=300)
        self.assertTrue(wait_for(lambda: self.py.state == n.S_READY and self.host.has('STATUS 1'), 15))
        self.play(20)
        txn(self.py, 0x20, b'\x01')                                   # this side's exit key: BYE, result 1
        self.assertTrue(wait_for(lambda: self.host.has('LEFT'), 5), self.host.lines[-3:])
        self.assertIn('LEFT 1', self.host.lines)


if __name__ == '__main__':
    unittest.main()
