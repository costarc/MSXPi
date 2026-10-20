"""update.sh's games part (MSXPI_UPDATE_ONLY=games): fetch index.txt, then only the listed GPFs whose
SHA-256 changed; check each one and move it into place whole; never touch a file the index does not list.
Runs the real script with sh (Git's on Windows); skipped when sh or sha256sum is missing."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

UPDATE = Path(__file__).resolve().parents[2] / 'Setup/update.sh'
SH = shutil.which('sh')


def gpf(tag):
    return b'GPF1' + tag.encode() * 10


@unittest.skipUnless(SH and shutil.which('sha256sum'), 'needs sh and sha256sum')
class UpdateGamesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.src, self.home = self.tmp / 'src', self.tmp / 'home'
        self.src.mkdir(); self.home.mkdir()
        shutil.copy(UPDATE, self.home / 'update.sh')
        self.games = self.home / 'games'

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def publish(self, files, index=None):
        lines = []
        for name, data in files.items():
            (self.src / name).write_bytes(data)
            lines.append(f'{hashlib.sha256(data).hexdigest()}  {name}\n')
        (self.src / 'index.txt').write_text(index if index is not None else ''.join(lines), newline='\n')

    def run_update(self):
        env = dict(os.environ, MSXPI_UPDATE_ONLY='games', MSXPI_UPDATE_GAMES_BASE=self.src.as_posix())
        done = subprocess.run([SH, 'update.sh'], cwd=self.home, env=env, capture_output=True, text=True)
        return done.returncode, done.stdout

    def test_fresh_install_and_nothing_to_do(self):
        self.publish({'SOCCER.GPF': gpf('a'), 'YIEAR.GPF': gpf('b')})
        rc, out = self.run_update()
        self.assertEqual(rc, 0, out)
        self.assertEqual((self.games / 'SOCCER.GPF').read_bytes(), gpf('a'))
        self.assertEqual((self.games / 'YIEAR.GPF').read_bytes(), gpf('b'))
        self.assertTrue((self.games / 'index.txt').is_file())
        rc, out = self.run_update()
        self.assertEqual((rc, out), (0, ''))                           # unchanged: nothing fetched

    def test_only_changed_files_are_replaced(self):
        self.publish({'SOCCER.GPF': gpf('a'), 'YIEAR.GPF': gpf('b')})
        self.run_update()
        self.publish({'SOCCER.GPF': gpf('c'), 'YIEAR.GPF': gpf('b')})
        rc, out = self.run_update()
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.split(), ['ok', 'games/SOCCER.GPF'])
        self.assertEqual((self.games / 'SOCCER.GPF').read_bytes(), gpf('c'))

    def test_unlisted_files_survive(self):
        self.games.mkdir()
        (self.games / 'MINE.GPF').write_bytes(gpf('m'))
        self.publish({'SOCCER.GPF': gpf('a')})
        rc, out = self.run_update()
        self.assertEqual(rc, 0, out)
        self.assertEqual((self.games / 'MINE.GPF').read_bytes(), gpf('m'))

    def test_bad_download_keeps_the_old_file(self):
        self.publish({'SOCCER.GPF': gpf('a')})
        self.run_update()
        self.publish({'SOCCER.GPF': gpf('c')})
        (self.src / 'SOCCER.GPF').write_bytes(gpf('x'))                # not what the index says
        rc, out = self.run_update()
        self.assertEqual(rc, 1)
        self.assertIn('FAIL games/SOCCER.GPF', out)
        self.assertEqual((self.games / 'SOCCER.GPF').read_bytes(), gpf('a'))
        self.assertEqual(list(self.home.glob('*.new')), [])

    def test_not_a_gpf_is_refused(self):
        self.publish({'SOCCER.GPF': b'<html>not found</html>'})
        rc, out = self.run_update()
        self.assertEqual(rc, 1)
        self.assertFalse((self.games / 'SOCCER.GPF').exists())

    def test_bad_names_are_skipped(self):
        bad = hashlib.sha256(b'x').hexdigest()
        self.publish({}, index=f'{bad}  ../evil.GPF\n{bad}  TOOLONGNAME.GPF\n# comment\n\n{bad}  update.sh\n')
        rc, out = self.run_update()
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.count('skip bad index line'), 3)
        self.assertEqual(sorted(p.name for p in self.games.iterdir()), ['index.txt'])

    def test_missing_index_keeps_everything(self):
        self.games.mkdir()
        (self.games / 'SOCCER.GPF').write_bytes(gpf('a'))
        rc, out = self.run_update()
        self.assertEqual(rc, 1)
        self.assertIn('FAIL games index', out)
        self.assertEqual((self.games / 'SOCCER.GPF').read_bytes(), gpf('a'))


if __name__ == '__main__':
    unittest.main()
