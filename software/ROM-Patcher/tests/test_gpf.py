"""Package format version 2, the netplay ABI and the GPF file (documents/PLAYNET-PROTOCOLS.md 7-8).

The Soccer equivalence tests rebuild SOCCERNET.COM's RAM image from its own patch table
(software/Client/src/soccernet/soccernet.asm) and compare it with the image built from the
package. They run on a synthetic ROM always, and on the real dump when SOCCER_ROM is set.
"""
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import patch_rom as patcher

SOCCER = ROOT / 'profiles/soccer/profile.json'
SOCCERNET = ROOT.parent / 'Client/src/soccernet'


def soccernet_patches(symbols):
    """The patch table of soccernet.asm as (cpu address, bytes), read from the assembly source."""
    lines = (SOCCERNET / 'soccernet.asm').read_text().splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith('patches:'))
    table = []
    for line in lines[start + 1:]:
        line = line.split(';', 1)[0].strip()
        if not line or line.split()[0] in ('IFNDEF', 'IFDEF', 'ENDIF'):
            continue
        items = [item.strip() for item in line.split(':')]
        address = value(items[0].split(None, 1)[1], symbols)
        if address == 0:
            return table
        data = b''
        for item in items[2:]:
            op, args = item.split(None, 1)
            for arg in args.split(','):
                v = value(arg.strip(), symbols)
                data += struct.pack('<H', v) if op == 'defw' else bytes([v])
        length = value(items[1].split(None, 1)[1], symbols)
        assert len(data) == length, line
        table.append((address, data))
    raise AssertionError('no end of the patch table')


def value(text, symbols):
    if text.startswith('$'):
        return int(text[1:], 16)
    if re.fullmatch(r'\d+', text):
        return int(text)
    return symbols[text]


XIRQ_PATCH = (0x4096, struct.pack('<H', 0xC500 + 6))   # PLAYNET's addition: H.KEYI -> the transport's XIRQ
CLEARS = (0x40A5, 0x45A9)      # SOCCERNET's shortened RAM clears, not needed with the stub at C100h


def irq_patches(symbols):
    """PLAYNET's other change: the two per-interrupt sound calls count interrupts (PN_IRQ) instead of
    being removed."""
    irq = struct.pack('<H', symbols['PN_IRQ'])
    return [(0x4032, b'\xcd' + irq), (0x404E, b'\xfc' + irq)]


def old_image(rom, symbols):
    """SOCCERNET.COM's RAM image (its own patch table, today's stub entry addresses) without the shortened
    RAM clears, plus the XIRQ hook and the PN_IRQ calls."""
    image = bytearray(rom)
    for address, data in ([p for p in soccernet_patches(symbols) if p[0] not in CLEARS] + [XIRQ_PATCH]
                          + irq_patches(symbols)):
        image[address - 0x4000:address - 0x4000 + len(data)] = data
    return bytes(image)


def synthetic_rom(profile):
    """Zeros plus the expected bytes of every patch: not game content, cannot run as a game."""
    rom = bytearray(profile['source']['size'])
    for patch in profile['patches']:
        data = bytes.fromhex(patch['expected'])
        rom[patch['offset']:patch['offset'] + len(data)] = data
    return bytes(rom)


def retarget(profile, rom):
    profile['source']['sha256'] = patcher.digest(rom)
    profile['source']['crc32'] = patcher.crc32(rom)


def write_package(directory, profile, assets):
    """A package directory with its assets; the profile's asset hashes are set to match."""
    directory = Path(directory)
    (directory / 'assets').mkdir(exist_ok=True)
    for name, data in assets.items():
        (directory / f'assets/{name}.bin').write_bytes(data)
        profile['assets'][name] = {'file': f'assets/{name}.bin', 'sha256': hashlib.sha256(data).hexdigest()}
    (directory / 'profile.json').write_text(json.dumps(profile))
    return directory / 'profile.json'


def reseal(data):
    """Recompute the profile hash after tampering, so only the tampered rule is tested."""
    data = bytearray(data)
    data[8:12] = b'\0\0\0\0'
    data[8:12] = struct.pack('<I', patcher.crc32(data))
    return bytes(data)


class SoccerPackageTests(unittest.TestCase):
    def setUp(self):
        self.profile, self.assets = patcher.load_profile(SOCCER)

    def test_profile_is_valid_version_2_netplay(self):
        self.assertEqual(self.profile['version'], 2)
        self.assertEqual(patcher.abis(self.profile), ['msxpi-netplay-v1'])
        values = patcher.netplay_values(self.profile)
        self.assertEqual((values['game_id'], values['roles'], values['irq_handler']), ('soccer', ['H', 'C'], 0x402E))

    def test_same_image_as_soccernet_on_a_synthetic_rom(self):
        profile = copy.deepcopy(self.profile)
        rom = synthetic_rom(profile)
        retarget(profile, rom)
        image, _ = patcher.build(rom, profile, self.assets)
        self.assertEqual(image, old_image(rom, self.profile['symbols']))

    @unittest.skipUnless(os.environ.get('SOCCER_ROM'), 'set SOCCER_ROM to check against the real dump')
    def test_same_image_as_soccernet_on_the_real_rom(self):
        rom = Path(os.environ['SOCCER_ROM']).read_bytes()
        image, manifest = patcher.build(rom, self.profile, self.assets)     # also checks SHA-256, CRC-32, expected bytes
        self.assertEqual(image, old_image(rom, self.profile['symbols']))
        patched = set()
        for patch in self.profile['patches']:
            patched.update(range(patch['offset'], patch['offset'] + len(patch['expected']) // 2))
        changed = {i for i, (a, b) in enumerate(zip(image, rom)) if a != b}
        self.assertTrue(changed and changed <= patched)                    # nothing outside the 12 patches
        self.assertEqual(manifest['abi'], ['msxpi-netplay-v1'])
        gpf = patcher.read_gpf(patcher.gpf_bytes(self.profile, self.assets))
        self.assertEqual(patcher.gpf_image(gpf, rom), (image, self.assets['stub']))

    def test_the_gpf_compiles_and_the_stub_fits(self):
        data = patcher.gpf_bytes(self.profile, self.assets)
        gpf = patcher.read_gpf(data)
        self.assertLessEqual(len(self.assets['stub']), gpf['stub_max'])
        self.assertEqual(self.assets['stub'][0], 1)                         # stub ABI 1
        self.assertEqual(gpf['stub_load'] + gpf['stub_max'], gpf['transport_area'])
        self.assertEqual(gpf['transport_area'] + gpf['transport_size'], 0xC700)   # 512: the TCP/IP transport
        rom = synthetic_rom(self.profile)
        profile = copy.deepcopy(self.profile)
        retarget(profile, rom)
        self.assertEqual(patcher.gpf_image(patcher.read_gpf(patcher.gpf_bytes(profile, self.assets)), rom)[0],
                         patcher.build(rom, profile, self.assets)[0])

    def test_no_rom_file_from_a_ram_image_package(self):
        with tempfile.TemporaryDirectory() as directory:
            rom = Path(directory) / 'soccer.rom'
            rom.write_bytes(bytes(32768))
            done = subprocess.run([sys.executable, str(ROOT / 'patch_rom.py'), '--profile', str(SOCCER), str(rom),
                                   '-o', str(Path(directory) / 'out.rom')], capture_output=True, text=True)
            self.assertEqual(done.returncode, 2)
            self.assertIn('use --gpf', done.stderr)
            self.assertFalse((Path(directory) / 'out.rom').exists())


class GpfTests(unittest.TestCase):
    """A package shaped like Soccer's with a small stub, so it compiles."""

    def setUp(self):
        profile, _ = patcher.load_profile(SOCCER)
        self.rom = synthetic_rom(profile)
        retarget(profile, self.rom)
        self.stub = bytes([1, 0, 0, 0]) + bytes(range(96))
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = write_package(self.directory.name, profile, {'stub': self.stub})
        self.profile, self.assets = patcher.load_profile(self.path)
        self.data = patcher.gpf_bytes(self.profile, self.assets)

    def test_round_trip_rebuilds_the_same_image_and_stub(self):
        image, _ = patcher.build(self.rom, self.profile, self.assets)
        gpf = patcher.read_gpf(self.data)
        self.assertEqual(patcher.gpf_image(gpf, self.rom), (image, self.stub))
        self.assertEqual((gpf['game_id'], gpf['title'], gpf['roles']), ('soccer', "Konami's Soccer", ['H', 'C']))
        self.assertEqual((gpf['stub_load'], gpf['transport_area'], gpf['game_ram']),
                         (0xC100, 0xC500, [[0xD500, 0xD5FF], [0xE000, 0xF37F]]))

    def test_header_layout_and_hash(self):
        data = self.data
        self.assertEqual((data[:4], data[4], data[5], data[98]), (b'GPF1', 1, 1, 1))
        self.assertEqual(struct.unpack_from('<H', data, 6)[0], len(data) - 128)
        self.assertEqual(data[12:20], b'soccer\0\0')
        stored = struct.unpack_from('<I', data, 8)[0]
        self.assertEqual(stored, patcher.crc32(data[:8] + bytes(4) + data[12:]))
        self.assertEqual(data, patcher.gpf_bytes(self.profile, self.assets))      # deterministic
        self.assertEqual(data[-3:], b'\0\0\0')                                     # END section

    def test_hash_changes_with_any_patch_or_the_stub(self):
        profile = copy.deepcopy(self.profile)
        profile['patches'][0]['replace'] = '000001'
        self.assertNotEqual(patcher.gpf_bytes(profile, self.assets)[8:12], self.data[8:12])
        assets = dict(self.assets, stub=self.stub[:-1] + b'\xff')
        self.assertNotEqual(patcher.gpf_bytes(self.profile, assets)[8:12], self.data[8:12])

    # ---- the loader's refusals (PLAYNET-PROTOCOLS.md 17, "Loader (GPF)") -------------------

    def test_damaged_file(self):
        data = bytearray(self.data)
        data[200] ^= 1
        with self.assertRaisesRegex(patcher.PatchError, 'damaged'):
            patcher.read_gpf(bytes(data))
        with self.assertRaisesRegex(patcher.PatchError, 'length'):
            patcher.read_gpf(self.data[:-1])
        with self.assertRaisesRegex(patcher.PatchError, 'Not a GPF'):
            patcher.read_gpf(b'GPF2' + self.data[4:])

    def test_wrong_rom(self):
        gpf = patcher.read_gpf(self.data)
        other = bytearray(self.rom)
        other[0x100] ^= 1
        with self.assertRaisesRegex(patcher.PatchError, 'not the dump'):
            patcher.gpf_image(gpf, bytes(other))

    def test_expected_byte_differs(self):
        profile = copy.deepcopy(self.profile)
        profile['patches'][0]['expected'] = 'ffffff'          # the ROM has 22 0A 41 there
        gpf = patcher.read_gpf(patcher.gpf_bytes(profile, self.assets))
        with self.assertRaisesRegex(patcher.PatchError, 'Expected bytes differ at 0x28'):
            patcher.gpf_image(gpf, self.rom)

    def tampered_netplay(self, offset_in_section, value):
        data = bytearray(self.data)
        at = 128
        while data[at] != patcher.SEC_NETPLAY:
            at += 3 + struct.unpack_from('<H', data, at + 1)[0]
        struct.pack_into('<H', data, at + 3 + offset_in_section, value)
        return reseal(data)

    def test_ranges_checked_again_when_loading(self):
        # NETPLAY payload: base 0, input bytes 2, stub asset 3, stub load 4, stub max 6, transport 8, ...
        with self.assertRaisesRegex(patcher.PatchError, 'overlaps the stub'):
            patcher.read_gpf(self.tampered_netplay(4, 0xEF00))          # stub over game RAM E000-EFFF
        with self.assertRaisesRegex(patcher.PatchError, 'stub.load'):
            patcher.read_gpf(self.tampered_netplay(4, 0xB000))          # stub outside page 3
        with self.assertRaisesRegex(patcher.PatchError, 'transport_area.size'):
            patcher.read_gpf(self.tampered_netplay(10, 64))             # transport area too small
        with self.assertRaisesRegex(patcher.PatchError, 'stub asset is 100 bytes'):
            patcher.read_gpf(self.tampered_netplay(6, 64))              # stub bigger than its room

    def test_newer_versions_are_refused(self):
        data = bytearray(self.data)
        data[98] = patcher.PLAYNET_VERSION + 1
        with self.assertRaisesRegex(patcher.PatchError, 'newer PLAYNET'):
            patcher.read_gpf(reseal(data))
        data = bytearray(self.data)
        data[4] = 2
        with self.assertRaisesRegex(patcher.PatchError, 'format 2'):
            patcher.read_gpf(reseal(data))
        data = bytearray(self.data)
        data[5] |= 4                                                     # image host 2: not defined
        with self.assertRaisesRegex(patcher.PatchError, 'image host'):
            patcher.read_gpf(reseal(data))
        data = bytearray(self.data)
        data[5] |= 2                                                     # mapper-ram, without its section
        with self.assertRaisesRegex(patcher.PatchError, 'MAPPER section'):
            patcher.read_gpf(reseal(data))

    def test_unknown_sections_are_skipped(self):
        data = bytearray(self.data)
        extra = struct.pack('<BH', 0x7F, 2) + b'xy'
        data[128:128] = extra
        struct.pack_into('<H', data, 6, len(data) - 128)
        gpf = patcher.read_gpf(reseal(data))
        self.assertEqual(patcher.gpf_image(gpf, self.rom)[1], self.stub)

    def test_cli_writes_once_and_checks_the_rom(self):
        rom = Path(self.directory.name) / 'soccer.rom'
        rom.write_bytes(self.rom)
        out = Path(self.directory.name) / 'SOCCER.GPF'
        command = [sys.executable, str(ROOT / 'patch_rom.py'), '--profile', str(self.path), '--gpf', str(out), str(rom)]
        done = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(out.read_bytes(), self.data)
        again = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(again.returncode, 2)
        self.assertIn('already exists', again.stderr)


class NetplayValidationTests(unittest.TestCase):
    def setUp(self):
        self.profile, _ = patcher.load_profile(SOCCER)
        self.sizes = {0: 100}

    def check(self, change, message):
        profile = copy.deepcopy(self.profile)
        change(profile, profile['netplay'])
        with self.assertRaisesRegex(patcher.PatchError, message):
            patcher.check_netplay(patcher.netplay_values(profile), self.sizes)

    def test_rules(self):
        cases = [
            (lambda p, n: n.update(game_id='Soccer'), 'game_id'),
            (lambda p, n: n.update(game_id='soccernet'), 'game_id'),
            (lambda p, n: n.update(roles=['H']), 'roles'),
            (lambda p, n: n.update(roles=['H', 'C!']), 'roles'),
            (lambda p, n: n.update(title='x' * 25), 'title'),
            (lambda p, n: n.update(input_bytes=5), 'input_bytes'),
            (lambda p, n: n['image'].update(base=0), 'image.base'),
            (lambda p, n: n['image'].update(host='banked'), 'image.host'),
            (lambda p, n: n['image'].update(host='mapper-ram'), 'image.mapper'),
            (lambda p, n: n['stub'].update(load=0xF300, max=256), 'page 3'),
            (lambda p, n: n['transport_area'].update(size=100), 'transport_area.size'),
            (lambda p, n: n['transport_area'].update(address=0xC200), 'overlap'),
            (lambda p, n: n.update(game_ram=[[0xC000, 0xC200]]), 'overlaps the stub'),
            (lambda p, n: n.update(game_ram=[[0xC5F0, 0xC5F0]]), 'overlaps the transport'),
            (lambda p, n: n.update(irq_handler=0xC000), 'irq_handler'),
            (lambda p, n: n.update(start=0x2000), 'start'),
            (lambda p, n: n.update(transport='relay'), 'transport'),
            (lambda p, n: p['source'].update(file='soccer.rom'), '8.3'),
            (lambda p, n: p['output'].update(target='rom-file'), 'ram-image'),
            (lambda p, n: p['output'].update(size=49152), '16384 or 32768'),
        ]
        for change, message in cases:
            with self.subTest(message=message):
                self.check(change, message)

    def test_abi_list(self):
        profile = copy.deepcopy(self.profile)
        profile['abi'] = ['msxpi-netplay-v2']
        with self.assertRaisesRegex(patcher.PatchError, 'known ABIs'):
            patcher.abis(profile)

    def test_game_without_rom(self):
        profile = {'format': 'msxpi-rom-patch', 'version': 2, 'id': 'pchess-v1', 'abi': ['msxpi-netplay-v1'],
                   'source': None, 'output': {'size': 0, 'fill': 0, 'mapper': 'none', 'target': 'ram-image'},
                   'requirements': [], 'assets': {}, 'layout': [], 'patches': [],
                   'netplay': {'abi': 'msxpi-netplay-v1', 'game_id': 'pchess', 'title': 'PChess',
                               'roles': ['W', 'B'], 'transport': 'none', 'command': 'PCHESS /{role} {peer}'}}
        gpf = patcher.read_gpf(patcher.gpf_bytes(profile, {}))
        self.assertEqual((gpf['transport'], gpf['command'], gpf['roles']), ('none', 'PCHESS /{role} {peer}', ['W', 'B']))
        with self.assertRaisesRegex(patcher.PatchError, 'own program'):
            patcher.gpf_image(gpf, b'')
        profile['netplay']['command'] = 'PCHESS & RUN'
        with self.assertRaisesRegex(patcher.PatchError, 'command'):
            patcher.gpf_bytes(profile, {})


SALAMANDER = ROOT / 'profiles/salamander/profile.json'


class MapperRamTests(unittest.TestCase):
    """Salamander's package: image host mapper-ram (PLAYNET-PROTOCOLS 7.3). The real dump when SALAMANDER_ROM is set."""

    def setUp(self):
        self.profile, self.assets = patcher.load_profile(SALAMANDER)
        self.data = patcher.gpf_bytes(self.profile, self.assets)

    def test_round_trip(self):
        gpf = patcher.read_gpf(self.data)
        self.assertEqual(self.data[5], 3)                                # lockstep, image host 1
        image = self.profile['netplay']['image']
        self.assertEqual(gpf['mapper']['pairs'], [image['page1_pairs'], image['page2_pairs']])
        self.assertEqual(gpf['mapper']['pinned'], image['pinned'])
        self.assertEqual(gpf['mapper']['block'], image['block'])
        self.assertEqual(gpf['assets'][0], self.assets['stub'])
        self.assertLessEqual(len(self.data), 3072, "PLAYNET.COM's GPF buffer is 3 KB")

    def test_image_is_the_patched_rom(self):
        rom = synthetic_rom(self.profile)
        profile = copy.deepcopy(self.profile)
        retarget(profile, rom)
        gpf = patcher.read_gpf(patcher.gpf_bytes(profile, self.assets))
        self.assertEqual(patcher.gpf_image(gpf, rom)[0], patcher.build(rom, profile, self.assets)[0])

    @unittest.skipUnless(os.environ.get('SALAMANDER_ROM'), 'set SALAMANDER_ROM to check against the real dump')
    def test_real_rom(self):
        rom = Path(os.environ['SALAMANDER_ROM']).read_bytes()
        image, _ = patcher.gpf_image(patcher.read_gpf(self.data), rom)
        self.assertEqual(len(image), 131072)
        for patch in self.profile['patches']:
            data = bytes.fromhex(patch['replace'])
            self.assertEqual(image[patch['offset']:patch['offset'] + len(data)], data)

    def test_rules(self):
        cases = [
            (lambda i: i.update(mapper='ascii16'), 'image.mapper'),
            (lambda i: i.update(bank_size=16384), 'bank_size'),
            (lambda i: i.update(banks=12), 'power of two'),
            (lambda i: i.update(pinned=[4, 5]), 'home'),
            (lambda i: i.update(start_banks=[0, 1, 2, 9]), 'start pairs'),
            (lambda i: i.update(page2_pairs=i['page2_pairs'] + [[2, 3]]), 'twice'),
            (lambda i: i.update(min_segments=11), 'min_segments'),
            (lambda i: i.update(block=0xDA00), 'block'),           # past the stub (D200h-D8FFh)
        ]
        for change, message in cases:
            with self.subTest(message=message):
                profile = copy.deepcopy(self.profile)
                change(profile['netplay']['image'])
                with self.assertRaisesRegex(patcher.PatchError, message):
                    patcher.check_netplay(patcher.netplay_values(profile), {0: 1395})

    def test_needs_playnet_3(self):
        profile = copy.deepcopy(self.profile)
        profile['netplay']['min_playnet'] = 2
        with self.assertRaisesRegex(patcher.PatchError, 'min_playnet 3'):
            patcher.check_netplay(patcher.netplay_values(profile), {0: 1395})

    def test_a_patch_may_not_cross_a_bank(self):
        profile = copy.deepcopy(self.profile)
        profile['patches'].append({'offset': 0x1FFF, 'expected': '0000', 'replace': '0000', 'reason': 'x'})
        with self.assertRaisesRegex(patcher.PatchError, 'crosses a bank'):
            patcher.check_netplay(patcher.netplay_values(profile), {0: 1395})


class MusicVersion2Tests(unittest.TestCase):
    def test_version_2_music_package_builds_the_same_rom(self):
        v1, assets = patcher.load_profile(ROOT / 'profiles/goonies/profile.json')
        rom = bytearray(32768)
        for patch in v1['patches']:
            offset = patch['offset'] - 0x8000 if patch['offset'] >= 0x8000 else patch['offset']
            if 0x4000 <= patch['offset'] < 0x8000 or patch['offset'] >= 0x8000:
                data = bytes.fromhex(patch['expected'])
                rom[offset:offset + len(data)] = data
        rom = bytes(rom)
        v1['source']['sha256'] = patcher.digest(rom)
        v2 = copy.deepcopy(v1)
        v2.update(version=2, abi=['msxpi-music-v1'])
        self.assertEqual(patcher.build(rom, v1, assets)[0], patcher.build(rom, v2, assets)[0])
        with self.assertRaisesRegex(patcher.PatchError, 'Only packages with the netplay ABI'):
            patcher.gpf_bytes(v2, assets)


class PublishedGamesTests(unittest.TestCase):
    """software/target/games is what the packages compile to (build_games.py), and its index lists each file."""

    def test_games_folder_is_current(self):
        done = subprocess.run([sys.executable, str(ROOT / 'build_games.py'), '--check'], capture_output=True, text=True)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr + 'run build_games.py')

    def test_index_matches_files(self):
        games = ROOT.parent / 'target/games'
        for line in (games / 'index.txt').read_text().splitlines():
            digest, name = line.split()
            self.assertRegex(name, r'^[A-Z0-9_-]{1,8}\.GPF$')
            data = (games / name).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), digest)
            self.assertEqual(patcher.read_gpf(data)['game_id'].upper() + '.GPF', name)


if __name__ == '__main__':
    unittest.main()
