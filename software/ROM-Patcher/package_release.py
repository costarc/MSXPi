#!/usr/bin/env python3
"""Create a source/payload ZIP, excluding ROMs, caches, and assembly listings."""
import argparse
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    allowed = {'.py', '.md', '.json', '.asm', '.bin'}
    with zipfile.ZipFile(args.output, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(ROOT.rglob('*')):
            if not path.is_file() or '__pycache__' in path.parts:
                continue
            if path.suffix not in allowed and path.name not in ('LICENSE', '.gitignore'):
                continue
            name = 'msxpi-rom-patcher/' + path.relative_to(ROOT).as_posix()
            entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, path.read_bytes())
    print(f'Created {args.output}')


if __name__ == '__main__':
    main()
