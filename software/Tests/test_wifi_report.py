#!/usr/bin/env python3
"""`p wifi` lists every interface, whatever its index.

The display used to be `ip a` filtered through
`grep '^1\\|^2\\|^3\\|^4\\|inet' | grep -v inet6`, which keeps an interface's
header line only when its index is 1 to 4. msxpi0 is recreated every time the
TAP is rebuilt and its index climbs each time, so once it passed 4 the MSX saw
its address with no interface line above it - an address apparently belonging
to the previous interface, which reads as corrupted output.

These tests feed canned `ip -o` output, so they need no network and no root.
"""
import ast
import subprocess
import unittest
from pathlib import Path
from subprocess import PIPE, STDOUT

SRC = Path(__file__).resolve().parents[1] / 'Server/Python/src'
TREE = ast.parse((SRC / 'msxpi-server.py').read_text(encoding='utf-8-sig'))
CODE = compile(ast.Module(body=[n for n in TREE.body
                               if isinstance(n, ast.FunctionDef)
                               and n.name == 'interfaces_report'],
                          type_ignores=[]), 'server-functions', 'exec')

# A Pi that has rebuilt its TAP a few times: msxpi0 is interface 7.
LINKS = (
    '1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN\\\n'
    '2: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast\\\n'
    '3: eth0: <NO-CARRIER,BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN\\\n'
    '7: msxpi0: <BROADCAST,MULTICAST,UP> mtu 576 qdisc fq_codel state UNKNOWN\\\n'
)
ADDRS = (
    '1: lo    inet 127.0.0.1/8 scope host lo\\\n'
    '2: wlan0    inet 192.168.1.239/24 brd 192.168.1.255 scope global wlan0\\\n'
    '7: msxpi0    inet 192.168.99.1/24 brd 192.168.99.255 scope global msxpi0\\\n'
)


class FakeRun:
    """subprocess.run that answers the two `ip -o` calls from canned text."""

    def __init__(self, links=LINKS, addrs=ADDRS, rc=0, boom=None):
        self.links, self.addrs, self.rc, self.boom = links, addrs, rc, boom

    def run(self, argv, **kw):
        if self.boom:
            raise self.boom
        text = self.links if 'link' in argv else self.addrs
        return subprocess.CompletedProcess(argv, self.rc, stdout=text)


def report(**kw):
    ns = {'subprocess': FakeRun(**kw), 'PIPE': PIPE, 'STDOUT': STDOUT,
          'print': lambda *a, **k: None}
    exec(CODE, ns)
    return ns['interfaces_report']()


class WifiReportTest(unittest.TestCase):

    def test_lists_an_interface_whose_index_is_above_four(self):
        """The whole point: msxpi0 at index 7 must still be named."""
        out = report()
        self.assertIn('msxpi0', out)
        line = [l for l in out.splitlines() if l.startswith('msxpi0')]
        self.assertEqual(len(line), 1, out)
        self.assertIn('192.168.99.1/24', line[0])

    def test_every_address_is_attached_to_its_own_interface(self):
        """No address may appear without its interface name on the same line."""
        for line in report().splitlines():
            name, rest = line.split(None, 1)
            self.assertTrue(name and not name[0].isdigit(), line)
            self.assertTrue(rest.strip(), line)

    def test_fits_a_40_column_screen(self):
        for line in report().splitlines():
            self.assertLessEqual(len(line), 40, line)

    def test_reports_interface_state(self):
        out = report()
        self.assertIn('up', [l.split()[1] for l in out.splitlines()
                             if l.startswith('wlan0')])
        self.assertIn('down', [l.split()[1] for l in out.splitlines()
                               if l.startswith('eth0')])

    def test_an_interface_with_no_ipv4_still_appears(self):
        """eth0 is down with no address - it must not vanish from the list."""
        self.assertTrue(any(l.startswith('eth0') for l in report().splitlines()))

    def test_ipv6_is_not_listed(self):
        self.assertNotIn(':', report().replace('msxpi0', '').replace('wlan0', ''))

    def test_failure_to_read_is_reported_not_raised(self):
        self.assertIn('could not read', report(rc=1))
        self.assertIn('could not read', report(boom=OSError('no ip command')))


if __name__ == '__main__':
    unittest.main(verbosity=2)
