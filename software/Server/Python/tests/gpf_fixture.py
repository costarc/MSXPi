"""GPF files for the server tests, written by ROM-Patcher's own compiler (software/ROM-Patcher/patch_rom.py),
so the server's reader is tested against the real format rather than a copy of it."""
import importlib.util
import os
from pathlib import Path
import tempfile

_spec = importlib.util.spec_from_file_location(
    'patch_rom', Path(__file__).resolve().parents[3] / 'ROM-Patcher/patch_rom.py')
patch_rom = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(patch_rom)


def make_gpf(game_id, title, roles, transport='lockstep', command='', revision=0):
    """A small, valid GPF.  `revision` changes the package (and so its profile hash), as an update would."""
    netplay = {'abi': 'msxpi-netplay-v1', 'game_id': game_id, 'title': title, 'roles': list(roles),
               'transport': transport}
    if transport == 'none':
        netplay['command'] = command
        profile = {'format': 'msxpi-rom-patch', 'version': 2, 'id': game_id + '-test', 'abi': ['msxpi-netplay-v1'],
                   'source': None, 'output': {'size': 0, 'fill': 0, 'mapper': 'none', 'target': 'ram-image'},
                   'requirements': [], 'assets': {}, 'layout': [], 'patches': [], 'netplay': netplay}
        return patch_rom.gpf_bytes(profile, {})
    netplay.update({'input_bytes': 1, 'image': {'host': 'plain', 'base': 0x4000},
                    'stub': {'asset': 'stub', 'load': 0xF000, 'max': 576},
                    'transport_area': {'address': 0xF240, 'size': 192},
                    'game_ram': [[0xE000, 0xEFFF]], 'irq_handler': 0x4043, 'start': 'header-init'})
    profile = {'format': 'msxpi-rom-patch', 'version': 2, 'id': game_id + '-test', 'abi': ['msxpi-netplay-v1'],
               'source': {'size': 16384, 'sha256': '0' * 64, 'crc32': revision, 'file': 'GAME.ROM'},
               'output': {'size': 16384, 'fill': 0, 'mapper': 'plain', 'target': 'ram-image'},
               'requirements': [], 'assets': {'stub': {'file': 'assets/stub.bin', 'sha256': ''}},
               'layout': [{'source': 'input', 'offset': 0, 'size': 16384, 'destination': 0}],
               'patches': [], 'netplay': netplay}
    return patch_rom.gpf_bytes(profile, {'stub': bytes([1, 0, 0, 0]) + bytes(60)})


SOCCER = make_gpf('soccer', "Konami's Soccer", ['H', 'C'])
SOCCER_OTHER_VERSION = make_gpf('soccer', "Konami's Soccer", ['H', 'C'], revision=1)
TANKS = make_gpf('tanks', 'Tanks', ['RED', 'BLUE'], 'none', 'TANKS /{role} {peer}')


def games_dir(*files):
    """A temporary games folder holding (name, bytes) files; default: soccer and tanks."""
    folder = tempfile.mkdtemp(prefix='msxpi-games-')
    for name, data in files or (('SOCCER.GPF', SOCCER), ('TANKS.GPF', TANKS)):
        with open(os.path.join(folder, name), 'wb') as stream:
            stream.write(data)
    return folder
