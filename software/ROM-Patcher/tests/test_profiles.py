"""Netplay profiles stay in step with the shared PLAYNET sources (plan C2).

Every profile that carries a copy of the engine (src/playnet_engine.asm, src/mapper_k8.asm) must carry the one in
software/Client/src/playnet/engine/, and its published assets/stub.bin must be what its rebuild.py makes of it today.
The rebuild test needs sjasmplus (SJASMPLUS=path, or on PATH, or C:/Users/roniv/Dev/bin/sjasmplus.exe) and is skipped
without it. It rebuilds in place and puts the published files back.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
PROFILES = ROOT / 'profiles'
ENGINE_DIR = ROOT.parent / 'Client/src/playnet/engine'
SHARED = ('playnet_engine.asm', 'mapper_k8.asm')


def netplay_profiles():
    """The profiles that carry the engine."""
    return sorted(p for p in PROFILES.iterdir() if (p / 'src/playnet_engine.asm').is_file())


def find_assembler():
    for candidate in (os.environ.get('SJASMPLUS'), shutil.which('sjasmplus'), 'C:/Users/roniv/Dev/bin/sjasmplus.exe'):
        if candidate and Path(candidate).exists() or candidate and shutil.which(candidate):
            return candidate
    return None


class TransportSizes(unittest.TestCase):
    BUILD = ROOT.parent / 'Client/src/playnet/build'
    BUFFER_AT = 384          # the UNAPI and hybrid transports keep their 128-byte buffer at +384

    def test_every_transport_fits_the_minimum_area(self):
        import patch_rom
        bins = sorted(self.BUILD.glob('transport_*.bin'))
        if not bins:
            self.skipTest('PLAYNET is not built (software/Client/src/playnet/build.py)')
        for path in bins:
            if path.stem.endswith(('_0', '_100')):      # build.py's relocation probes
                continue
            with self.subTest(transport=path.name):
                size = len(path.read_bytes())
                self.assertLessEqual(size, patch_rom.TRANSPORT_AREA_MIN)
                if path.stem != 'transport_msxpi':
                    self.assertLessEqual(size, self.BUFFER_AT, 'code would run into the buffer at +384')

    def test_every_profile_area_is_big_enough(self):
        import patch_rom
        for profile in netplay_profiles():
            with self.subTest(profile=profile.name):
                size = json.loads((profile / 'profile.json').read_text())['netplay']['transport_area']['size']
                self.assertGreaterEqual(size, patch_rom.TRANSPORT_AREA_MIN)


class TpaTops(unittest.TestCase):
    """PLAYNET-PROTOCOLS 10.2: where each package's transport area fits (patch_rom.TPA_TOPS, measured)."""

    def misfits(self, game):
        import patch_rom
        profile = json.loads((PROFILES / game / 'profile.json').read_text())
        n = profile['netplay']
        return patch_rom.tcpip_misfits({'transport_area': n['transport_area']['address']})

    def test_soccer_pingpong_yiear_fit_every_measured_setup(self):
        for game in ('soccer', 'pingpong', 'yiear'):
            with self.subTest(game=game):
                self.assertEqual(self.misfits(game), [])

    def test_salamander_does_not_fit_the_drive_of_its_own_machine(self):
        # the known limit (decision D-6): D000h + 512 is above C806h. Update this test when it is lifted.
        self.assertEqual(len(self.misfits('salamander')), 1)
        self.assertIn('Panasonic', self.misfits('salamander')[0])


class EngineCopies(unittest.TestCase):
    def test_there_are_netplay_profiles(self):
        self.assertGreaterEqual(len(netplay_profiles()), 4)

    def test_every_engine_copy_is_the_shared_one(self):
        for profile in netplay_profiles():
            for name in SHARED:
                copy = profile / 'src' / name
                if copy.is_file():
                    with self.subTest(profile=profile.name, file=name):
                        self.assertEqual(copy.read_bytes(), (ENGINE_DIR / name).read_bytes(),
                                         f'{copy} differs from {ENGINE_DIR / name}: run the profile\'s rebuild.py')


class PublishedStubs(unittest.TestCase):
    def test_every_stub_is_what_its_rebuild_makes(self):
        assembler = find_assembler()
        if not assembler:
            self.skipTest('no sjasmplus')
        for profile in netplay_profiles():
            published = [profile / 'assets/stub.bin', profile / 'profile.json']
            before = {p: p.read_bytes() for p in published}
            try:
                subprocess.run([sys.executable, str(profile / 'rebuild.py'), '--assembler', assembler],
                               cwd=profile, check=True, capture_output=True)
                for p in published:
                    with self.subTest(profile=profile.name, file=p.name):
                        self.assertEqual(
                            hashlib.sha256(p.read_bytes()).hexdigest(), hashlib.sha256(before[p]).hexdigest(),
                            f'{p} is not what {profile.name}/rebuild.py makes: rebuild and commit it')
            finally:
                for p, data in before.items():
                    p.write_bytes(data)


if __name__ == '__main__':
    unittest.main()
