#!/usr/bin/env python3
"""Dependency-free MSXPi ROM patcher. Profiles are data, never executed code."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
MAX_ROM = 16 * 1024 * 1024


class PatchError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise PatchError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def integer(value, low, high, label):
    require(type(value) is int and low <= value <= high,
            f'{label} must be an integer in {low}..{high}')
    return value


def span(offset, size, limit, label):
    integer(offset, 0, limit, label + ' offset')
    integer(size, 1, limit, label + ' size')
    require(offset + size <= limit, label + ' exceeds its buffer')
    return slice(offset, offset + size)


def read_json(path):
    def unique_pairs(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f'Duplicate JSON key: {key}')
            result[key] = value
        return result
    value = json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=unique_pairs)
    require(isinstance(value, dict), f'{path}: expected JSON object')
    return value


def load_profile(path):
    path = Path(path).resolve()
    profile = read_json(path)
    require(profile['format'] == 'msxpi-rom-patch' and type(profile['version']) is int and profile['version'] == 1,
            'Unsupported patch profile format/version')
    require(profile['music']['abi'] == 'msxpi-music-v1', 'Unsupported music ABI')
    require(isinstance(profile['id'], str) and profile['id'], 'Missing profile ID')
    assets = {}
    for name, spec in profile['assets'].items():
        require(name != 'input', 'Asset name input is reserved')
        asset = (path.parent / spec['file']).resolve()
        require(asset.is_relative_to(path.parent), 'Asset escapes profile directory')
        require(asset.stat().st_size <= MAX_ROM, 'Asset too large')
        data = asset.read_bytes()
        require(digest(data) == spec['sha256'], f'Asset checksum mismatch: {name}')
        assets[name] = data
    return profile, assets


def music_config(profile, overrides=None):
    result = json.loads(json.dumps(profile['defaults']))
    if overrides is not None:
        require(set(overrides) <= {'tracks', 'sounds', 'exit_enabled', 'gap_frames'},
                'Unknown music configuration field')
        for key, value in overrides.items():
            if key in ('tracks', 'sounds'):
                require(isinstance(value, dict), f'{key} must be an object')
                result[key].update(value)
            else:
                result[key] = value
    require(type(result['exit_enabled']) is bool, 'exit_enabled must be true or false')
    integer(result['gap_frames'], 0, 255, 'gap_frames')
    definitions = profile['sounds']
    require(set(result['sounds']) == set(definitions), 'Unknown or missing sound IDs')
    require(isinstance(result['tracks'], dict), 'tracks must be an object')
    # Validate even unused entries to catch configuration mistakes early.
    for key, track in result['tracks'].items():
        require(isinstance(track, dict) and set(track) == {'filename', 'mode'},
                f'Track {key}: expected filename and mode')
        require(track['mode'] in ('play', 'loop'), f'Track {key}: mode must be play or loop')
        filename = track['filename']
        require(isinstance(filename, str) and filename == filename.strip()
                and 1 <= len(filename) <= 127
                and all(32 <= ord(ch) < 127 for ch in filename),
                f'Track {key}: filename must be 1..127 printable ASCII characters, '
                'without leading/trailing whitespace')
    mapping = bytearray(256)
    modes = bytearray(256)
    names = bytearray()
    indices = {}
    records = []
    claimed = set()
    for sound_key, definition in definitions.items():
        track_key = result['sounds'][sound_key]
        require(track_key is None or isinstance(track_key, str), 'Sound mapping must be track name or null')
        index = 0
        if track_key is not None:
            require(track_key in result['tracks'], f'Sound {sound_key}: unknown track {track_key}')
            track = result['tracks'][track_key]
            identity = (track['filename'], track['mode'])
            if identity not in indices:
                index = len(indices) + 1
                require(index <= 255, 'At most 255 distinct filename/mode pairs are supported')
                indices[identity] = index
                names.extend(track['filename'].encode('ascii') + b'\0')
                modes[index] = int(track['mode'] == 'loop')
                records.append({'index': index, **track})
            index = indices[identity]
        require(definition['raw_ids'], f'Sound {sound_key}: empty raw_ids')
        for raw in definition['raw_ids']:
            integer(raw, 0, 255, 'raw sound ID')
            require(raw not in claimed, f'Duplicate raw sound ID: {raw}')
            claimed.add(raw)
            mapping[raw] = index
    names.extend(b'\0' if names else b'\0\0')
    require(len(names) <= profile['music']['names_capacity'], 'Packed filename list is too large')
    return result, bytes(mapping), bytes(modes), bytes(names), records


def build(original, profile, assets, overrides=None):
    source = profile['source']
    require(len(original) == source['size'] and digest(original) == source['sha256'],
            'Input ROM is not the supported original (size/SHA-256 mismatch). '
            'Already-patched ROMs are not accepted.')
    size = integer(profile['output']['size'], 1, MAX_ROM, 'output size')
    fill = integer(profile['output']['fill'], 0, 255, 'fill byte')
    output = bytearray([fill]) * size
    used = bytearray(size)
    for item in profile['layout']:
        data = original if item['source'] == 'input' else assets[item['source']]
        src = span(item['offset'], item['size'], len(data), 'layout source')
        dst = span(item['destination'], item['size'], size, 'layout destination')
        require(not any(used[dst]), 'Overlapping layout destinations')
        output[dst] = data[src]
        used[dst] = b'\1' * item['size']
    patched = bytearray(size)
    for patch in profile['patches']:
        expected, replacement = bytes.fromhex(patch['expected']), bytes.fromhex(patch['replace'])
        require(len(expected) == len(replacement) and expected, 'Patch lengths must match and be nonempty')
        dst = span(patch['offset'], len(expected), size, 'patch')
        require(not any(patched[dst]), 'Overlapping patch operations')
        require(output[dst] == expected, f'Expected bytes differ at {patch["offset"]:#x}: {patch["reason"]}')
        output[dst] = replacement
        patched[dst] = b'\1' * len(expected)
    effective, mapping, modes, names, records = music_config(profile, overrides)
    music = profile['music']
    span(music['names_offset'], music['names_capacity'], size, 'filename storage')
    encoding = music.get('names_encoding', 'ascii')
    require(encoding in ('ascii', 'escape-32'), 'Unsupported filename storage encoding')
    if encoding == 'escape-32':
        # ASCII 2 is also Z80 LD (nn),A. Prevent the server's instruction
        # scanner from interpreting filenames as bank-switch instructions.
        # NUL delimiters survive; the adapter restores 02 -> 32 in RAM.
        names = names.replace(b'2', b'\x02')
    config_spans = bytearray(size)
    fields = [(music['map_offset'], mapping), (music['modes_offset'], modes),
              (music['names_offset'], names.ljust(music['names_capacity'], b'\0')),
              (music['options_offset'], bytes([int(effective['exit_enabled']), effective['gap_frames']]))]
    for offset, data in fields:
        dst = span(offset, len(data), size, 'configuration')
        require(not any(config_spans[dst]) and not any(patched[dst]), 'Overlapping configuration/patch regions')
        require(not any(output[dst]), 'Configuration region is not zero-filled')
        config_spans[dst] = b'\1' * len(data)
        output[dst] = data
    manifest = {'format': 'msxpi-rom-build', 'version': 1, 'profile': profile['id'],
                'profile_sha256': digest(json.dumps(profile, sort_keys=True).encode()),
                'source_sha256': digest(original), 'output_sha256': digest(output),
                'mapper': profile['output']['mapper'], 'size': len(output),
                'music': effective, 'track_indices': records,
                'requirements': profile['requirements'], 'symbols': profile.get('symbols', {})}
    return bytes(output), manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rom', nargs='?', type=Path, help='supported ORIGINAL ROM')
    parser.add_argument('--profile', type=Path, default=ROOT / 'profiles/goonies/profile.json')
    parser.add_argument('--music', type=Path, help='JSON configuration overrides')
    parser.add_argument('--output', '-o', type=Path, help='new ROM path (must not exist)')
    parser.add_argument('--write-config', type=Path, help='write editable defaults and exit')
    args = parser.parse_args(argv)
    try:
        profile, assets = load_profile(args.profile)
        if args.write_config:
            with args.write_config.open('x', encoding='utf-8') as stream:
                json.dump(profile['defaults'], stream, indent=2)
                stream.write('\n')
            print(f'Configuration: {args.write_config}')
            return 0
        require(args.rom is not None and args.output is not None, 'ROM and --output are required')
        require(args.rom.resolve() != args.output.resolve(), 'Output must differ from the original ROM')
        manifest_path = args.output.with_suffix(args.output.suffix + '.json')
        require(not args.output.exists() and not manifest_path.exists(), 'Output ROM or manifest already exists')
        require(args.rom.stat().st_size <= MAX_ROM, 'Input ROM too large')
        overrides = read_json(args.music) if args.music else None
        data, manifest = build(args.rom.read_bytes(), profile, assets, overrides)
        with args.output.open('xb') as stream:
            stream.write(data)
        try:
            with manifest_path.open('x', encoding='utf-8') as stream:
                json.dump(manifest, stream, indent=2)
                stream.write('\n')
        except OSError:
            args.output.unlink()  # only the file exclusively created above
            raise
        print(f'Created {args.output} ({len(data)} bytes, {manifest["mapper"]})')
        print(f'SHA-256: {manifest["output_sha256"]}')
        print(f'Manifest: {manifest_path}')
        return 0
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f'Patch error: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
