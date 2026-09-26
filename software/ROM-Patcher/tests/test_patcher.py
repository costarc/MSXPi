import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import patch_rom as patcher


class PatcherTests(unittest.TestCase):
    def setUp(self):
        self.profile, self.assets = patcher.load_profile(ROOT/'profiles/goonies/profile.json')
        # Synthetic ROM reproduces only the small expected-byte sites; it is
        # not copyrighted game content and cannot execute as a game.
        original = bytearray(32768)
        for patch in self.profile['patches']:
            offset = patch['offset']
            if offset >= 0x8000:
                offset -= 0x8000
            elif 0x4000 <= offset < 0x8000:
                pass
            else:
                continue
            data = bytes.fromhex(patch['expected'])
            original[offset:offset+len(data)] = data
        self.original = bytes(original)
        self.profile['source']['sha256'] = patcher.digest(self.original)

    def test_deterministic_conversion_and_double_null(self):
        first, manifest = patcher.build(self.original, self.profile, self.assets)
        second, _ = patcher.build(self.original, self.profile, self.assets)
        self.assertEqual(first, second)
        self.assertEqual(len(first), 65536)
        self.assertEqual(first[:4], b'AB\x10\x40')
        filename = b'The_Goonies_R_Good_Enough.mp3\0'
        self.assertEqual(first[0x1310:0x1310+len(filename)], filename)
        self.assertEqual(first[0x1310+len(filename)], 0)
        self.assertEqual(manifest['output_sha256'], patcher.digest(first))
        self.assertEqual(first[0x1100+0xa4], first[0x1100+0xe4])
        self.assertEqual(first[0x1100+0x8e], 0)  # pause effect not mapped
        self.assertEqual(first[0x1100+0xad], 0)  # silence not mapped

    def test_multiple_tracks_modes_and_fallback_mapping(self):
        config = {'tracks': {'boss': {'filename': 'boss.mp3', 'mode': 'play'}},
                  'sounds': {'24': 'boss', '0f': None}}
        data, manifest = patcher.build(self.original, self.profile, self.assets, config)
        self.assertEqual(data[0x1100+0x8f], 0)
        boss = data[0x1100+0xa4]
        default = data[0x1100+0xa3]
        self.assertNotEqual(boss, default)
        self.assertEqual(data[0x1200+boss], 0)
        self.assertEqual(data[0x1200+default], 1)
        self.assertIn(b'boss.mp3\0\0', data)
        self.assertEqual(len(manifest['track_indices']), 2)

    def test_no_tracks_double_null(self):
        config = {'sounds': {k: None for k in self.profile['sounds']}}
        data, _ = patcher.build(self.original, self.profile, self.assets, config)
        self.assertEqual(data[0x1100:0x1300], bytes(512))
        self.assertEqual(data[0x1310:0x1312], b'\0\0')

    def test_input_and_expected_byte_guards(self):
        with self.assertRaises(patcher.PatchError):
            patcher.build(self.original[:-1], self.profile, self.assets)
        profile = copy.deepcopy(self.profile)
        profile['patches'][-1]['expected'] = '00000000'
        with self.assertRaises(patcher.PatchError):
            patcher.build(self.original, profile, self.assets)

    def test_bad_configuration(self):
        for override in [
            {'tracks': {'default': {'filename': '', 'mode': 'loop'}}},
            {'tracks': {'default': {'filename': 'x'*128, 'mode': 'play'}}},
            {'tracks': {'default': {'filename': 'a\0b', 'mode': 'play'}}},
            {'tracks': {'default': {'filename': 'a\nb', 'mode': 'play'}}},
            {'tracks': {'default': {'filename': 'song.mp3', 'mode': 'pause'}}},
            {'sounds': {'unknown': 'default'}}, {'sounds': {'24': 'missing'}},
            {'gap_frames': -1}, {'gap_frames': True}, {'exit_enabled': 'yes'},
            {'command': 'arbitrary'},
        ]:
            with self.subTest(override=override), self.assertRaises(patcher.PatchError):
                patcher.build(self.original, self.profile, self.assets, override)

    def test_name_capacity(self):
        override = {'tracks': {}, 'sounds': {}}
        for i, key in enumerate(self.profile['sounds']):
            override['tracks'][key] = {'filename': str(i).zfill(3)+'x'*124, 'mode': 'loop'}
            override['sounds'][key] = key
        with self.assertRaisesRegex(patcher.PatchError, 'too large'):
            patcher.build(self.original, self.profile, self.assets, override)

    def test_filename_escape_preserves_delimiters(self):
        data, _ = patcher.build(self.original, self.profile, self.assets,
                               {'tracks': {'default': {'filename': 'x2ab.mp3', 'mode': 'loop'}}})
        self.assertEqual(data[0x1310:0x131a], b'x\x02ab.mp3\0\0')

    @unittest.skipUnless(os.environ.get('MSXPI_MAPPER_SOURCE'), 'optional server scanner compatibility check')
    def test_server_scanner_does_not_change_config(self):
        spec = importlib.util.spec_from_file_location('mapper_test', os.environ['MSXPI_MAPPER_SOURCE'])
        mapper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mapper)
        data, _ = patcher.build(self.original, self.profile, self.assets,
                               {'tracks': {'default': {'filename': 'x2ab.mp3', 'mode': 'loop'}}})
        changed, count = mapper.patch_bank_switches(data, 3, [0xfac0, 0xfad8])
        self.assertEqual(data[0x1100:0x2100], changed[0x1100:0x2100])
        self.assertEqual(count, 3)  # bootstrap page 1/page 2 and exit bank zero

    def test_overlap_guards(self):
        for change in ('layout', 'patches', 'music'):
            profile = copy.deepcopy(self.profile)
            if change == 'music':
                profile['music']['map_offset'] = profile['music']['modes_offset']
            else:
                profile[change].append(copy.deepcopy(profile[change][0]))
            with self.subTest(change=change), self.assertRaises(patcher.PatchError):
                patcher.build(self.original, profile, self.assets)

    def test_assets_hash_and_containment(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profile = copy.deepcopy(self.profile)
            profile['assets']['resident']['file'] = '../outside.bin'
            (root/'profile.json').write_text(json.dumps(profile))
            with self.assertRaisesRegex(patcher.PatchError, 'escapes'):
                patcher.load_profile(root/'profile.json')
            profile['assets']['resident']['file'] = 'bad.bin'
            (root/'bad.bin').write_bytes(b'incorrect')
            (root/'profile.json').write_text(json.dumps(profile))
            with self.assertRaisesRegex(patcher.PatchError, 'checksum'):
                patcher.load_profile(root/'profile.json')

    def test_cli_does_not_overwrite_input_or_existing_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rom = root/'original.rom'
            rom.write_bytes(self.original)
            output = root/'existing.rom'
            output.write_bytes(b'keep this')
            for dest in (rom, output):
                completed = subprocess.run([sys.executable, str(ROOT/'patch_rom.py'),
                                            str(rom), '-o', str(dest)], capture_output=True)
                self.assertEqual(completed.returncode, 2)
            self.assertEqual(rom.read_bytes(), self.original)
            self.assertEqual(output.read_bytes(), b'keep this')

    def test_duplicate_json_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'config.json'
            path.write_text('{"sounds": {}, "sounds": {}}')
            with self.assertRaises(patcher.PatchError):
                patcher.read_json(path)

    @unittest.skipUnless(os.environ.get('MSXPI_TEST_ROM'), 'set MSXPI_TEST_ROM for original-ROM validation')
    def test_original_rom(self):
        profile, assets = patcher.load_profile(ROOT/'profiles/goonies/profile.json')
        data, manifest = patcher.build(Path(os.environ['MSXPI_TEST_ROM']).read_bytes(), profile, assets)
        self.assertEqual(len(data), 65536)
        with self.assertRaises(patcher.PatchError):
            patcher.build(data, profile, assets)


if __name__ == '__main__':
    unittest.main()
