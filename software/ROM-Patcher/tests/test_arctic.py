"""Arctic profile invariants; optional private-ROM/server-scanner integration."""
import copy
import importlib.util
import os
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import patch_rom


class ArcticTests(unittest.TestCase):
    def setUp(self):
        self.profile, self.assets = patch_rom.load_profile(ROOT/'profiles/arctic/profile.json')
        original = bytearray(self.profile['source']['size'])
        for patch in self.profile['patches']:
            data = bytes.fromhex(patch['expected'])
            original[patch['offset']:patch['offset']+len(data)] = data
        self.original = bytes(original)
        self.profile['source']['sha256'] = patch_rom.digest(self.original)

    def test_layout_and_maps(self):
        rom, manifest = patch_rom.build(self.original, self.profile, self.assets)
        self.assertEqual(len(rom), 0x22000)
        self.assertEqual(rom[0x21000], 0)  # native silence is not a song
        self.assertEqual(len(set(rom[0x21001:0x2100f])), 14)
        self.assertNotIn(0, rom[0x21001:0x2100f])
        self.assertEqual(rom[0x2100f:0x21100], bytes(241))
        self.assertIn(b'ARCTIC_14.mp3\0\0', rom[0x21210:0x22000])
        self.assertEqual(rom[0x3ffc:0x4000], bytes((1, 0, 0, 0)))
        self.assertEqual(manifest['output_sha256'], patch_rom.digest(rom))

    def test_configurable_native_and_play(self):
        config = {'sounds': {'01': None},
                  'tracks': {'track_02': {'filename': 'stage.mp3', 'mode': 'play'}}}
        rom, _ = patch_rom.build(self.original, self.profile, self.assets, config)
        self.assertEqual(rom[0x21001], 0)
        self.assertEqual(rom[0x21100+rom[0x21002]], 0)
        self.assertIn(b'stage.mp3\0', rom)

    def test_foreground_hooks_not_interrupt_handler(self):
        polls = [p for p in self.profile['patches'] if 'foreground input' in p['reason']]
        self.assertGreater(len(polls), 5)
        for patch in polls:
            self.assertIn(patch['expected'], ('3a54c0', '3a55c0'))
            self.assertFalse(0xa4e <= patch['offset'] < 0xaff)

    @unittest.skipUnless(os.environ.get('MSXPI_MAPPER_SOURCE'), 'needs server scanner')
    def test_mapper_rewrites_only_three_gateway_stores(self):
        spec = importlib.util.spec_from_file_location('arctic_mapper', os.environ['MSXPI_MAPPER_SOURCE'])
        mapper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mapper)
        rom, _ = patch_rom.build(self.original, self.profile, self.assets)
        rewritten, count = mapper.patch_bank_switches(rom, 3, [0xfac0, 0xfad8])
        self.assertEqual(count, 3)
        changes = [i for i, (a, b) in enumerate(zip(rom, rewritten)) if a != b]
        self.assertTrue(all(0x3e80 <= i < 0x3ffc for i in changes))

    @unittest.skipUnless(os.environ.get('MSXPI_ARCTIC_ROM'), 'needs private original ROM')
    def test_original_revision_and_determinism(self):
        profile, assets = patch_rom.load_profile(ROOT/'profiles/arctic/profile.json')
        original = Path(os.environ['MSXPI_ARCTIC_ROM']).read_bytes()
        first, _ = patch_rom.build(original, profile, assets)
        second, _ = patch_rom.build(original, profile, assets)
        self.assertEqual(first, second)
        damaged = bytearray(original)
        damaged[-1] ^= 1
        with self.assertRaises(patch_rom.PatchError):
            patch_rom.build(bytes(damaged), profile, assets)


if __name__ == '__main__':
    unittest.main()
