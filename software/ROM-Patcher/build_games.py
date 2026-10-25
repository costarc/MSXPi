#!/usr/bin/env python3
"""Compile every netplay package under profiles/ to software/target/games/<ID>.GPF and write index.txt.

    python build_games.py            (re)write the GPFs that changed, and the index
    python build_games.py --check    exit 1 when software/target/games is not what the packages compile to

index.txt lists each GPF as "<sha256>  <ID>.GPF" (the sha256sum format). The Pi's update.sh fetches it,
then only the listed files whose SHA-256 changed (documents/PLAYNET-DESIGN.md 5.3). No ROM data goes in:
a GPF holds the patches and the stub, and PLAYNET checks the player's own dump against it.
"""
import argparse
import hashlib
from pathlib import Path
import sys

import patch_rom

ROOT = Path(__file__).resolve().parent
GAMES = ROOT.parent / 'target/games'
NOTES = []


def compile_all():
    """{file name: GPF bytes} for every package that uses the netplay ABI."""
    out = {}
    for path in sorted(ROOT.glob('profiles/*/profile.json')):
        profile, assets = patch_rom.load_profile(path)
        if patch_rom.ABI_NETPLAY not in patch_rom.abis(profile):
            continue
        data = patch_rom.gpf_bytes(profile, assets)
        gpf = patch_rom.read_gpf(data)
        name = gpf['game_id'].upper() + '.GPF'
        if gpf['transport'] == 'lockstep':
            for setup in patch_rom.tcpip_misfits(gpf):
                NOTES.append(f'note: {name} cannot use the TCP/IP transports on {setup} (transport area above its TPA top; PLAYNET tells the player to hold CTRL at boot or use Nextor)')
        if name in out:
            raise SystemExit(f'two packages compile to {name}')
        out[name] = data
    return out


def index_text(files):
    return ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name, data in sorted(files.items()))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    files = compile_all()
    files_and_index = dict(files, **{'index.txt': index_text(files).encode()})
    stale = [name for name, data in files_and_index.items()
             if not (GAMES / name).is_file() or (GAMES / name).read_bytes() != data]
    extra = sorted(p.name for p in GAMES.glob('*.GPF') if p.name not in files) if GAMES.is_dir() else []
    if args.check:
        for name in stale:
            print(f'stale: {name}')
        for name in extra:
            print(f'not built from a package: {name}')
        return 1 if stale or extra else 0
    GAMES.mkdir(parents=True, exist_ok=True)
    for name in stale:
        (GAMES / name).write_bytes(files_and_index[name])
        print(f'wrote {name}')
    for name in extra:
        print(f'warning: {name} is not built from a package (left alone)')
    for note in NOTES:
        print(note)
    print(f'{len(files)} game(s) in {GAMES}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
