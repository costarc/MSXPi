"""Every server module msxpi-server.py needs is in every install and update list.

msxpi-server.py imports some modules only inside a function (msxpi_cmd_web.poker() does
"from msxpi_poker import ..." when the MSX first asks for a table), so a module can be
missing from an installer and nothing fails until a user runs that command on a fresh
MSXPi.  This test follows the imports (top level and lazy) from msxpi-server.py through
the modules in Python/src and checks the four file lists that put the server on a Pi or a
Windows PC:

  - Setup/msxpi-setup.sh          install_msxpi(): the files it checks update.sh fetched
  - Setup/msxpi-windows-setup.ps1 the "Keep in sync with Python/src" download list
  - Setup/update.sh               the download loop and the chown list

Run from software/Server/Python:
    python -m unittest tests.test_install_lists -v
"""
import ast
import re
import unittest
import warnings
from pathlib import Path

SERVER = Path(__file__).resolve().parents[1]
SRC = SERVER / 'src'
SETUP = SERVER.parent / 'Setup'

# Imported by the server's modules but deliberately not installed.
NOT_SHIPPED = {
    # msxpi_eth.make_link() imports it only when MSXPI_ETH_LINK=udpnat: the user-mode
    # network of the openMSX test rigs, never a real MSXPi.
    'msxpi_ethnat',
}


def imported_names(path):
    """Top-level module names a file imports, anywhere in it (functions included)."""
    names = set()
    with warnings.catch_warnings():
        # Old modules have docstrings with stray escapes; that is not this test's business.
        warnings.simplefilter('ignore', SyntaxWarning)
        tree = ast.parse(path.read_text(encoding='utf-8'), str(path))
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(a.name.split('.')[0] for a in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module and not node.level:
            names.add(node.module.split('.')[0])
    return names


def server_modules():
    """Every module in Python/src reachable from msxpi-server.py by imports."""
    seen, todo = set(), [SRC / 'msxpi-server.py']
    while todo:
        for name in imported_names(todo.pop()):
            path = SRC / f'{name}.py'
            if name not in seen and path.is_file():
                seen.add(name)
                todo.append(path)
    return seen


def py_names(text):
    return set(re.findall(r'[\w.-]+\.py\b', text))


def setup_sh_list():
    text = (SETUP / 'msxpi-setup.sh').read_text(encoding='utf-8')
    body = text[text.index('install_msxpi() {'):]
    m = re.search(r'^\s*for f in (msxpi-server\.py[^;]*);', body, re.M)
    return py_names(m.group(1))


def windows_setup_list():
    text = (SETUP / 'msxpi-windows-setup.ps1').read_text(encoding='utf-8')
    start = text.index('Keep in sync with Python/src')
    m = re.compile(r'foreach \(\$f in @\((.*?)\)\) \{', re.S).search(text, start)
    return py_names(m.group(1))


def update_sh_lists():
    text = (SETUP / 'update.sh').read_text(encoding='utf-8').replace('\\\n', ' ')
    download = re.search(r'^for f in (msxpi-server\.py[^;]*);', text, re.M)
    chown = re.search(r'chown "\$owner" (msxpi-server\.py[^\n]*)', text)
    return py_names(download.group(1)), py_names(chown.group(1))


def install_lists():
    download, chown = update_sh_lists()
    return {
        'Setup/msxpi-setup.sh (install_msxpi)': setup_sh_list(),
        'Setup/msxpi-windows-setup.ps1': windows_setup_list(),
        'Setup/update.sh (download loop)': download,
        'Setup/update.sh (chown list)': chown,
    }


class InstallListTests(unittest.TestCase):
    def test_the_lazy_poker_import_is_followed(self):
        # The module this test was written for: imported only inside msxpi_cmd_web.poker().
        mods = server_modules()
        self.assertIn('msxpi_poker', mods)
        self.assertIn('msxpi_cmd_web', mods)

    def test_every_server_module_is_in_every_list(self):
        needed = {f'{m}.py' for m in server_modules() if m.startswith('msxpi_')} - {
            f'{m}.py' for m in NOT_SHIPPED}
        for where, listed in install_lists().items():
            with self.subTest(list=where):
                self.assertIn('msxpi-server.py', listed)
                self.assertEqual(sorted(needed - listed), [], f'missing from {where}')

    def test_every_listed_module_exists(self):
        for where, listed in install_lists().items():
            with self.subTest(list=where):
                self.assertEqual(sorted(f for f in listed if not (SRC / f).is_file()), [],
                                 f'{where} names a file that is not in Python/src')

    def test_not_shipped_modules_are_still_real(self):
        # A stale exclusion would hide a module that does need installing.
        self.assertLessEqual(NOT_SHIPPED, server_modules())


if __name__ == '__main__':
    unittest.main()
