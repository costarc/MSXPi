#!/usr/bin/env python3
"""`p netreset` rebuilds the Pi's MSX networking and reopens the TAP.

The command exists for a boot the user cannot otherwise recover from: the Pi
has no default route yet when msxpi-monitor runs msxpi-tcpip-setup.sh in the
background, so there is no uplink to NAT to, and the MSX has no network until
somebody logs into the Pi. These tests pin the behaviour that matters from the
MSX's side - that the reply is short enough to read on a 40-column screen, that
a failure says why rather than printing an exit code, and that a teardown
failure does not stop the rebuild (it exits non-zero exactly when there is no
default route, which is the case the command is for).

No GPIO, no server startup, no root: the setup script is replaced by a stub.
"""
import ast
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from subprocess import PIPE, STDOUT

SRC = Path(__file__).resolve().parents[1] / 'Server/Python/src'
TREE = ast.parse((SRC / 'msxpi-server.py').read_text(encoding='utf-8-sig'))
NAMES = {'netreset', 'tcpip', '_eth_relink', '_eth_release', '_eth_note_link'}
CODE = compile(ast.Module(body=[n for n in TREE.body
                               if isinstance(n, ast.FunctionDef) and n.name in NAMES],
                          type_ignores=[]), 'server-functions', 'exec')

# The script the stub stands in for, and what it prints on a good run.
GOOD = """#!/bin/sh
[ "$1" = down ] && { echo "torn down"; exit 0; }
echo "uplink: wlan0"
echo "created msxpi0 (owner pi)"
echo "msxpi0 up: 192.168.99.1/24 mtu 576"
echo "NAT: msxpi0 -> wlan0"
echo "dns: 192.168.1.254"
echo ""
echo "Now restart msxpi-server.py as pi and check it prints"
echo "    eth: TAP device msxpi0 up"
echo "On the MSX, configure InterNestor Lite ... many more lines ..."
exit 0
"""

NO_ROUTE = """#!/bin/sh
echo "no default route - is the Pi on the network?"
exit 1
"""


class Fake:
    """Stand-ins for the module globals netreset() touches."""

    def __init__(self, script, shuttle=None, tap=None):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, 'msxpi-tcpip-setup.sh')
        with open(self.path, 'w', newline='\n') as fh:
            fh.write(script)
        os.chmod(self.path, os.stat(self.path).st_mode | stat.S_IEXEC)
        self.env = {
            'hostType': 'RaspberryPi', 'os': os, 'subprocess': subprocess,
            'PIPE': PIPE, 'STDOUT': STDOUT, 'print': lambda *a, **k: None,
            'TCPIP_SETUP': self.path, '_eth_mod': tap, '_eth_shuttle': shuttle,
            '_eth_tap_retry_at': 99.0, '_eth_handle': None,
            '_eth_link_is_mock': False,
        }
        # `sudo` is not available (and would prompt); run the stub directly.
        self.env['subprocess'] = _NoSudo(subprocess)
        exec(CODE, self.env)

    def netreset(self, parm=None):
        return self.env['netreset'](parm)


class _NoSudo:
    """subprocess with the leading "sudo" dropped from argv."""

    def __init__(self, real):
        self._real = real

    def run(self, argv, **kw):
        if argv and argv[0] == 'sudo':
            argv = argv[1:]
        return self._real.run(argv, **kw)


class Link:
    def __init__(self):
        self.enabled, self.filters, self.closed = True, 0x06, False

    def close(self):
        self.closed = True


class Shuttle:
    def __init__(self):
        self.link = Link()

    def handle(self, opcode):
        return True


class EthMod:
    """Stands in for msxpi_eth: TapLink either opens or raises."""

    def __init__(self, works=True):
        self.works = works
        self.made = 0

    def TapLink(self, *a, **kw):
        self.made += 1
        if not self.works:
            raise OSError(1, 'Operation not permitted')
        return Link()

    class MockLink(Link):
        pass


class NetresetTest(unittest.TestCase):

    def test_reports_only_what_fits_on_screen(self):
        """The script prints pages of advice; the MSX gets four lines."""
        fake = Fake(GOOD)
        out = fake.netreset()
        lines = out.split('\r\n')
        self.assertIn('uplink: wlan0', lines)
        self.assertIn('NAT: msxpi0 -> wlan0', lines)
        self.assertIn('created msxpi0 (owner pi)', lines)
        # The Pi's resolver: the MSX keeps its own in INL.CFG, and when the Pi
        # changes network the two silently stop agreeing.
        self.assertTrue(any(l.startswith('dns: 192.168.1.254') for l in lines),
                        lines)
        self.assertNotIn('', [l for l in lines if l == ''])
        for line in lines:
            self.assertLessEqual(len(line), 40, f'too wide for the screen: {line}')
        # The help text the script echoes must not be mistaken for status.
        self.assertNotIn('eth: TAP device msxpi0 up', out)

    def test_reattaches_the_tap_after_the_device_is_recreated(self):
        """The old fd points at a deleted device: it must be reopened."""
        shuttle, mod = Shuttle(), EthMod(works=True)
        old = shuttle.link
        out = Fake(GOOD, shuttle=shuttle, tap=mod).netreset()
        self.assertEqual(mod.made, 1)
        self.assertIsNot(shuttle.link, old)
        self.assertTrue(old.closed, 'the stale link must be closed')
        self.assertIn('TAP reattached', out)

    def test_carries_the_msx_visible_link_state_across_the_swap(self):
        shuttle, mod = Shuttle(), EthMod(works=True)
        shuttle.link.enabled, shuttle.link.filters = False, 0x14
        Fake(GOOD, shuttle=shuttle, tap=mod).netreset()
        self.assertIs(shuttle.link.enabled, False)
        self.assertEqual(shuttle.link.filters, 0x14)

    def test_says_so_when_the_tap_still_cannot_be_opened(self):
        shuttle, mod = Shuttle(), EthMod(works=False)
        fake = Fake(GOOD, shuttle=shuttle, tap=mod)
        out = fake.netreset()
        self.assertIn('TAP unavailable', out)
        self.assertEqual(fake.env['_eth_tap_retry_at'], 0.0,
                         'the opcode path must be left free to retry')

    def test_nothing_attached_yet_is_not_an_error(self):
        out = Fake(GOOD, shuttle=None, tap=EthMod()).netreset()
        self.assertIn('idle', out)

    def test_no_default_route_explains_itself(self):
        out = Fake(NO_ROUTE).netreset()
        self.assertIn('no default route', out)
        self.assertTrue(out.startswith('Pi:'), out)

    def test_teardown_failure_does_not_stop_the_rebuild(self):
        """`down` exits non-zero with no default route - the case this is for."""
        script = ("#!/bin/sh\n"
                  "[ \"$1\" = down ] && { echo 'cannot tear down'; exit 1; }\n"
                  "echo 'uplink: wlan0'\necho 'NAT: msxpi0 -> wlan0'\nexit 0\n")
        out = Fake(script).netreset()
        self.assertIn('NAT: msxpi0 -> wlan0', out)
        self.assertNotIn('cannot tear down', out)

    def test_wait_is_passed_to_the_script_and_bounded(self):
        script = ("#!/bin/sh\n[ \"$1\" = down ] && exit 0\n"
                  "echo \"uplink: $WAIT_SECS\"\nexit 0\n")
        self.assertIn('uplink: 30', Fake(script).netreset('30'))
        self.assertIn('uplink: 60', Fake(script).netreset('600'))  # clamped
        self.assertIn('uplink: 1', Fake(script).netreset('0'))     # clamped
        self.assertIn('uplink: 15', Fake(script).netreset('abc'))  # default
        self.assertIn('uplink: 15', Fake(script).netreset())

    def test_missing_script_is_reported_not_raised(self):
        fake = Fake(GOOD)
        fake.env['TCPIP_SETUP'] = os.path.join(fake.dir, 'gone.sh')
        self.assertIn('missing', fake.netreset())

    def test_refused_off_the_pi(self):
        fake = Fake(GOOD)
        fake.env['hostType'] = 'Linux'
        self.assertIn('not supported', fake.netreset())

    def test_releases_the_device_before_the_script_runs(self):
        """`ip tuntap del` cannot remove a device the server still holds open.

        It only clears the persist flag; the device survives with its original
        owner until the descriptor closes. So the link must be dropped BEFORE
        the script tries to delete it, not after - otherwise the rebuild
        reconfigures the very device the server cannot open, which is exactly
        what the Pi showed: the owner check fired, "created ..." never
        appeared, and the reply ended "TAP unavailable".
        """
        shuttle, mod = Shuttle(), EthMod(works=True)
        first = shuttle.link
        # The stub records whether the old link was already closed when it ran.
        script = ("#!/bin/sh\n[ \"$1\" = down ] && exit 0\n"
                  "echo 'uplink: wlan0'\necho 'NAT: msxpi0 -> wlan0'\nexit 0\n")
        fake = Fake(script, shuttle=shuttle, tap=mod)
        real_run = fake.env['subprocess'].run
        seen = []

        def watching_run(argv, **kw):
            seen.append(first.closed)
            return real_run(argv, **kw)

        fake.env['subprocess'].run = watching_run
        fake.netreset()
        self.assertTrue(seen and all(seen),
                        'the TAP was still open while the script ran')

    def test_a_device_that_could_not_be_deleted_is_reported(self):
        script = ("#!/bin/sh\n[ \"$1\" = down ] && exit 0\n"
                  "echo 'uplink: wlan0'\n"
                  "echo 'WARN msxpi0 still present after delete - another "
                  "process holds it'\necho 'NAT: msxpi0 -> wlan0'\nexit 0\n")
        out = Fake(script).netreset()
        self.assertIn('WARN', out)

    def test_tcpip_is_an_alias(self):
        fake = Fake(GOOD)
        self.assertEqual(fake.env['tcpip'](), fake.netreset())


if __name__ == '__main__':
    unittest.main(verbosity=2)
