"""msxpi_eth.WinTapLink.pick_adapter: the TAP holding the gateway address wins, not the registry order."""
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_eth as eth

A = ('{A}', 'Local Area Connection')      # registry-first, 192.168.98.1
B = ('{B}', 'Local Area Connection 2')    # the one the setup script configured
IPS = {'{A}': ['192.168.98.1'], '{B}': ['192.168.99.1', '169.254.9.245']}


class PickAdapter(unittest.TestCase):
    def pick(self, **kw):
        with mock.patch.object(eth.WinTapLink, 'adapter_ips', side_effect=lambda g: IPS[g]):
            return eth.WinTapLink.pick_adapter([A, B], **kw)

    def test_address_beats_registry_order(self):
        self.assertEqual(self.pick(tap_ip='192.168.99.1'), B)

    def test_configurable_address(self):
        self.assertEqual(self.pick(tap_ip='192.168.98.1'), A)

    def test_explicit_name_wins(self):
        self.assertEqual(self.pick(ifname='Local Area Connection', tap_ip='192.168.99.1'), A)

    def test_no_match_falls_back_to_first(self):
        self.assertEqual(self.pick(tap_ip='10.9.9.1'), A)
        self.assertEqual(self.pick(), A)

    def test_default_is_the_setup_script_address(self):
        self.assertEqual(eth.DEFAULT_TAP_IP, '192.168.99.1')


@unittest.skipUnless(sys.platform == 'win32', 'registry')
class Registry(unittest.TestCase):
    def test_real_adapters_resolve(self):
        for guid, _ in eth.WinTapLink.find_adapters():
            self.assertIsInstance(eth.WinTapLink.adapter_ips(guid), list)


if __name__ == '__main__':
    unittest.main()
