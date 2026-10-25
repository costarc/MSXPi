#!/usr/bin/env python3
"""Dependency-free MSXPi ROM patcher. Profiles are data, never executed code.

Package format msxpi-rom-patch, versions 1 and 2 (see FORMAT.md). Version 2 makes the
music ABI optional and adds the msxpi-netplay-v1 ABI: such a package is compiled to a GPF
file for PLAYNET (--gpf) and never to a patched ROM file."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import zlib

ROOT = Path(__file__).resolve().parent
MAX_ROM = 16 * 1024 * 1024

ABI_MUSIC = 'msxpi-music-v1'
ABI_NETPLAY = 'msxpi-netplay-v1'
KNOWN_ABIS = (ABI_MUSIC, ABI_NETPLAY)

# GPF, the compiled netplay package (documents/PLAYNET-PROTOCOLS.md, section 8)
GPF_MAGIC = b'GPF1'
GPF_FORMAT = 1
GPF_HEADER = 128
GPF_MAX = 16384
PLAYNET_VERSION = 3                     # the newest min_playnet this tool understands
SEC_END, SEC_SOURCE, SEC_NETPLAY, SEC_LAYOUT, SEC_PATCH, SEC_ASSET, SEC_MAPPER = range(7)
HOST_PLAIN, HOST_MAPPER = 0, 1          # netplay.image.host, GPF flags bits 1-2
MAPPER_TYPES = {'konami-scc': 1}        # mapper-ram: the cartridge mappers a stub's bank engine emulates
MAPPER_BANK = 8192                      # 8 KB banks, two to a 16 KB mapper segment (PLAYNET-PROTOCOLS 7.3)
MAPPER_MIN_PLAYNET = 3
# What a package may need from the machine or from PLAYNET (never a link: one package serves every link). One bit each in
# GPF header byte 99; a loader that meets a bit it does not know refuses the package ("update PLAYNET").
CAPABILITIES = {'mapper-ram': 0x01}
MAPPER_FIXED = '<BBBH4BBBBBB'           # the MAPPER section before its pairs (14 bytes)
PAGE3_LOW, PAGE3_HIGH = 0xC000, 0xF37F  # RAM below the BIOS work area
# The largest transport plus the UNAPI buffer: the hybrid (384 bytes) and UNAPI (346) transports keep a 128-byte buffer at +384, the
# MSXPi one is 458 bytes (software/Client/src/playnet/build/, checked in tests/test_profiles.py).
TRANSPORT_AREA_MIN = 512
# MSX-DOS's TPA top (the word at 0006h) with the TCP/IP stack loaded, measured with tests/soccernet/tpatop.sh (PLAYNET-PROTOCOLS 10.2).
# The UNAPI and hybrid transports are written into MSX-DOS's page 3 too: transport area + 512 must lie below the top
# (PLAYNET.COM's tcpFootprint refuses otherwise).
TPA_TOPS = {
    'MSX-DOS 1, no drive of its own (Canon V-25) + MSR + INL': 0xD406,
    'MSX-DOS 1, no drive of its own, CTRL held at boot': 0xDA06,      # CTRL at boot leaves out the second drive: +1.5 KB
    'MSX-DOS 1.8, own drive (Panasonic FS-A1WSX) + MSR + INL': 0xC806,
    'MSX-DOS 1.8, own drive, CTRL held at boot': 0xD406,
    'Nextor + RAMHELPR + INL': 0xD706,
}


def tcpip_misfits(v):
    """The measured set-ups where this package's transport area is not TPA, so PLAYNET /T cannot run it there."""
    end = v['transport_area'] + TRANSPORT_AREA_MIN
    return [name for name, top in TPA_TOPS.items() if end > top]
INPUT_ROM = 0xFF                        # layout source "input" in a GPF

GAME_ID_RE = re.compile(r'[a-z0-9-]{1,8}')
ROLE_RE = re.compile(r'[A-Za-z0-9]{1,8}')
COMMAND_RE = re.compile(r'(?:[A-Za-z0-9 ._:/\-]|\{role\}|\{peer\}|\{token\}){1,37}')
FILE83_RE = re.compile(r'[A-Z0-9_\-]{1,8}\.[A-Z0-9_\-]{1,3}')


class PatchError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise PatchError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def crc32(data):
    return zlib.crc32(data) & 0xFFFFFFFF


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


def abis(profile):
    """The ABIs a package uses. Version 1 packages are music packages."""
    if profile['version'] == 1:
        return [ABI_MUSIC]
    names = profile['abi']
    require(isinstance(names, list) and names and len(set(names)) == len(names)
            and all(name in KNOWN_ABIS for name in names), f'abi must list known ABIs: {", ".join(KNOWN_ABIS)}')
    return names


def load_profile(path):
    path = Path(path).resolve()
    profile = read_json(path)
    require(profile['format'] == 'msxpi-rom-patch' and type(profile['version']) is int and profile['version'] in (1, 2),
            'Unsupported patch profile format/version')
    used = abis(profile)
    if ABI_MUSIC in used:
        require(profile['music']['abi'] == ABI_MUSIC, 'Unsupported music ABI')
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
    if ABI_NETPLAY in used:
        check_netplay(netplay_values(profile), {i: len(data) for i, data in enumerate(assets.values())})
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


def apply_layout_and_patches(original, assets, size, fill, layout, patches):
    """Shared by build() and gpf_image(). layout: (source, offset, size, destination), source None = the ROM;
    patches: (offset, expected, replacement, reason)."""
    output = bytearray([fill]) * size
    used = bytearray(size)
    for source, offset, length, destination in layout:
        data = original if source is None else assets[source]
        src = span(offset, length, len(data), 'layout source')
        dst = span(destination, length, size, 'layout destination')
        require(not any(used[dst]), 'Overlapping layout destinations')
        output[dst] = data[src]
        used[dst] = b'\1' * length
    patched = bytearray(size)
    for offset, expected, replacement, reason in patches:
        require(len(expected) == len(replacement) and expected, 'Patch lengths must match and be nonempty')
        dst = span(offset, len(expected), size, 'patch')
        require(not any(patched[dst]), 'Overlapping patch operations')
        require(output[dst] == expected, f'Expected bytes differ at {offset:#x}: {reason}')
        output[dst] = replacement
        patched[dst] = b'\1' * len(expected)
    return output, patched


def build(original, profile, assets, overrides=None):
    used = abis(profile)
    source = profile['source']
    require(source is not None, 'This package has no ROM to build (netplay transport "none")')
    require(len(original) == source['size'] and digest(original) == source['sha256'],
            'Input ROM is not the supported original (size/SHA-256 mismatch). '
            'Already-patched ROMs are not accepted.')
    if 'crc32' in source:
        require(crc32(original) == source['crc32'], 'Input ROM CRC-32 does not match the profile')
    size = integer(profile['output']['size'], 1, MAX_ROM, 'output size')
    fill = integer(profile['output']['fill'], 0, 255, 'fill byte')
    output, patched = apply_layout_and_patches(
        original, assets, size, fill,
        [(None if item['source'] == 'input' else item['source'], item['offset'], item['size'], item['destination'])
         for item in profile['layout']],
        [(patch['offset'], bytes.fromhex(patch['expected']), bytes.fromhex(patch['replace']), patch['reason'])
         for patch in profile['patches']])
    if ABI_MUSIC not in used:
        require(overrides is None, 'This package has no music configuration')
        manifest = {'format': 'msxpi-rom-build', 'version': 1, 'profile': profile['id'], 'abi': used,
                    'profile_sha256': digest(json.dumps(profile, sort_keys=True).encode()),
                    'source_sha256': digest(original), 'output_sha256': digest(output),
                    'mapper': profile['output']['mapper'], 'size': len(output),
                    'requirements': profile['requirements'], 'symbols': profile.get('symbols', {})}
        return bytes(output), manifest
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


# ---- netplay ABI ---------------------------------------------------------------------------
# One set of rules for both forms of a netplay package: the JSON profile and the compiled GPF.
# Both are first turned into the same flat dictionary, then check_netplay() applies the rules
# of PLAYNET-PROTOCOLS.md 7.2 (the MSX loader applies them again, 8.3).

def netplay_values(profile):
    """The netplay section of a JSON profile as the flat dictionary check_netplay() takes."""
    require(profile['version'] == 2, 'The netplay ABI needs package format version 2')
    n = profile['netplay']
    require(isinstance(n, dict) and n.get('abi') == ABI_NETPLAY, 'netplay.abi must be ' + ABI_NETPLAY)
    names = list(profile['assets'])
    v = {'game_id': n.get('game_id'), 'title': n.get('title'), 'roles': n.get('roles'),
         'transport': n.get('transport'), 'command': n.get('command', ''),
         'min_playnet': n.get('min_playnet', 1), 'requires': n.get('requires', [])}
    if v['transport'] == 'none':
        require(profile['source'] is None and not profile['layout'] and not profile['patches'] and not profile['assets'],
                'A game with transport "none" has no ROM, layout, patches or assets')
        return v
    require(v['transport'] == 'lockstep', 'netplay.transport must be "lockstep" or "none"')
    require(profile['output'].get('target') == 'ram-image', 'A lockstep package needs output.target "ram-image"')
    source = profile['source']
    require(isinstance(source, dict), 'A lockstep package needs its source ROM')
    image, stub, area = n.get('image', {}), n.get('stub', {}), n.get('transport_area', {})
    require(image.get('host') in ('plain', 'mapper-ram'), 'netplay.image.host must be "plain" or "mapper-ram"')
    require(stub.get('asset') in names, 'netplay.stub.asset must name an asset')
    start = n.get('start')
    if image['host'] == 'mapper-ram':
        layout = profile['layout']
        require(len(layout) == 1 and layout[0]['source'] == 'input' and layout[0]['offset'] == 0
                and layout[0]['destination'] == 0 and layout[0]['size'] == source['size'] == profile['output']['size'],
                'A mapper-ram image is the ROM itself: one layout entry, the whole input at 0')
        require(image.get('mapper') in MAPPER_TYPES, 'netplay.image.mapper must be one of ' + ', '.join(MAPPER_TYPES))
        require(image.get('bank_size') == MAPPER_BANK, f'netplay.image.bank_size must be {MAPPER_BANK}')
        pinned = image.get('pinned')
        require(isinstance(pinned, list) and len(pinned) == 2, 'netplay.image.pinned is [page 1, page 2]')
        v['mapper'] = {'type': MAPPER_TYPES[image['mapper']], 'banks': image.get('banks'), 'block': image.get('block'),
                       'start': image.get('start_banks'), 'pinned': pinned, 'min_segments': image.get('min_segments'),
                       'pairs': [image.get('page1_pairs'), image.get('page2_pairs')]}
        v['patch_spans'] = [(patch['offset'], len(patch['expected']) // 2) for patch in profile['patches']]
    v.update({
        'input_bytes': n.get('input_bytes', 1), 'image_base': image.get('base', 0x4000),
        'output_size': profile['output']['size'], 'stub_asset': names.index(stub['asset']),
        'stub_load': stub.get('load'), 'stub_max': stub.get('max'),
        'transport_area': area.get('address'), 'transport_size': area.get('size'),
        'irq_handler': n.get('irq_handler'), 'start': 0 if start == 'header-init' else start,
        'game_ram': n.get('game_ram'),
        'source_size': source['size'], 'source_crc32': source.get('crc32'), 'source_file': source.get('file')})
    return v


def _overlap(a_low, a_high, b_low, b_high):
    return a_low <= b_high and b_low <= a_high


def check_netplay(v, asset_sizes):
    """Structural rules of a netplay package. asset_sizes: {index: length}."""
    require(isinstance(v['game_id'], str) and GAME_ID_RE.fullmatch(v['game_id']),
            'netplay.game_id must be 1-8 characters a-z 0-9 -')
    title = v['title']
    require(isinstance(title, str) and 1 <= len(title) <= 24 and all(32 <= ord(ch) < 127 for ch in title),
            'netplay.title must be 1-24 printable ASCII characters')
    roles = v['roles']
    require(isinstance(roles, list) and len(roles) == 2 and all(isinstance(r, str) and ROLE_RE.fullmatch(r) for r in roles),
            'netplay.roles must be two words of 1-8 letters or digits')
    integer(v['min_playnet'], 1, 255, 'netplay.min_playnet')
    req = v.get('requires', [])
    require(isinstance(req, list) and len(set(req)) == len(req) and all(r in CAPABILITIES for r in req),
            'netplay.requires must list each of ' + ', '.join(CAPABILITIES) + ' at most once')
    if v['transport'] == 'none':
        command = v['command']
        require(isinstance(command, str) and COMMAND_RE.fullmatch(command),
                'netplay.command must be at most 37 characters of A-Z a-z 0-9 space . _ : / - and {role} {peer} {token}')
        return
    integer(v['input_bytes'], 1, 4, 'netplay.input_bytes')
    if v.get('mapper'):
        check_mapper(v)
        image_low, image_high = 0x4000, 0xBFFF
    else:
        require(v['image_base'] in (0x4000, 0x8000), 'netplay.image.base must be 16384 (4000h) or 32768 (8000h)')
        require(v['output_size'] in (16384, 32768), 'A plain image is 16384 or 32768 bytes')
        image_low, image_high = v['image_base'], v['image_base'] + v['output_size'] - 1
    require(image_high <= 0xBFFF, 'The image must end at or below BFFFh')
    integer(v['source_size'], 1, MAX_ROM, 'source.size')
    integer(v['source_crc32'], 0, 0xFFFFFFFF, 'source.crc32')
    require(isinstance(v['source_file'], str) and FILE83_RE.fullmatch(v['source_file']),
            'source.file must be an upper-case 8.3 file name')
    require(v['stub_asset'] in asset_sizes, 'netplay.stub.asset must name an asset')
    stub_low = integer(v['stub_load'], PAGE3_LOW, PAGE3_HIGH, 'netplay.stub.load')
    stub_high = stub_low + integer(v['stub_max'], 1, PAGE3_HIGH - PAGE3_LOW + 1, 'netplay.stub.max') - 1
    require(stub_high <= PAGE3_HIGH, 'The stub area must lie in page 3 (C000h-F37Fh)')
    area_low = integer(v['transport_area'], PAGE3_LOW, PAGE3_HIGH, 'netplay.transport_area.address')
    area_high = area_low + integer(v['transport_size'], TRANSPORT_AREA_MIN, PAGE3_HIGH - PAGE3_LOW + 1,
                                   'netplay.transport_area.size') - 1
    require(area_high <= PAGE3_HIGH, 'The transport area must lie in page 3 (C000h-F37Fh)')
    require(not _overlap(stub_low, stub_high, area_low, area_high), 'The stub and the transport area overlap')
    ranges = v['game_ram']
    require(isinstance(ranges, list) and 1 <= len(ranges) <= 16, 'netplay.game_ram must list 1-16 ranges')
    for item in ranges:
        require(isinstance(item, (list, tuple)) and len(item) == 2, 'A game_ram range is [low, high]')
        low, high = integer(item[0], 0, 0xFFFF, 'game_ram low'), integer(item[1], 0, 0xFFFF, 'game_ram high')
        require(low <= high, 'A game_ram range must have low <= high')
        require(not _overlap(low, high, stub_low, stub_high), f'game_ram {low:04X}-{high:04X} overlaps the stub area')
        require(not _overlap(low, high, area_low, area_high),
                f'game_ram {low:04X}-{high:04X} overlaps the transport area')
    if v.get('mapper'):
        block = v['mapper']['block']
        require(stub_low <= block and block + mapper_block_size(v['mapper']) - 1 <= stub_high,
                'netplay.image.block must lie inside the stub area')
    irq = integer(v['irq_handler'], 0, 0xFFFF, 'netplay.irq_handler')
    require(image_low <= irq <= image_high, 'netplay.irq_handler must be inside the image')
    start = v['start']
    require(start == 0 or (type(start) is int and image_low <= start <= image_high),
            'netplay.start must be "header-init" or an address inside the image')


def mapper_block_size(m):
    """MK_BLOCK (mapper_k8.asm) up to its tables: 10 bytes, 2 a bank, 2 x 3 page records. The tables follow, as
    many entries as the stub reserves (bytes 2 and 3 of the block); the loader checks them against the pairs."""
    return 10 + 2 * m['banks'] + 6


def mapper_homes(m):
    """bank -> (page 0/1, entry, half): the first pinned entry holding each bank, page 1's first."""
    homes = {}
    for page in (0, 1):
        for entry, pair in enumerate(m['pairs'][page][:m['pinned'][page]]):
            for half, bank in enumerate(pair):
                homes.setdefault(bank, (page, entry, half))
    return homes


def check_mapper(v):
    """The mapper-ram rules (PLAYNET-PROTOCOLS 7.3)."""
    m = v['mapper']
    require(v['min_playnet'] >= MAPPER_MIN_PLAYNET, f'A mapper-ram package needs min_playnet {MAPPER_MIN_PLAYNET}')
    require('mapper-ram' in v['requires'], 'A mapper-ram package must list "mapper-ram" in netplay.requires')
    banks = integer(m['banks'], 2, 64, 'netplay.image.banks')
    require(banks & (banks - 1) == 0, 'netplay.image.banks must be a power of two')
    require(v['output_size'] == banks * MAPPER_BANK, 'The ROM must be banks x bank_size bytes')
    start = m['start']
    require(isinstance(start, list) and len(start) == 4 and all(type(b) is int and 0 <= b < banks for b in start),
            'netplay.image.start_banks lists the banks of the four windows')
    for page in (0, 1):
        pairs = m['pairs'][page]
        require(isinstance(pairs, list) and 1 <= len(pairs) <= 60, 'A page lists 1 to 60 pairs')
        require(all(isinstance(p, list) and len(p) == 2 and all(type(b) is int and 0 <= b < banks for b in p)
                    for p in pairs), 'A pair is [low bank, high bank]')
        require(len({tuple(p) for p in pairs}) == len(pairs), 'A pair is listed twice')
        integer(m['pinned'][page], 1, len(pairs), 'netplay.image.pinned')
    require(list(start[:2]) in m['pairs'][0][:m['pinned'][0]] and list(start[2:]) in m['pairs'][1][:m['pinned'][1]],
            'The start pairs must be pinned')
    require(set(mapper_homes(m)) == set(range(banks)), 'Every bank needs a home in a pinned pair')
    integer(m['min_segments'], m['pinned'][0] + m['pinned'][1] + 2, 255, 'netplay.image.min_segments')
    integer(m['block'], 0, 0xFFFF, 'netplay.image.block')
    for offset, length in v.get('patch_spans', ()):
        require(offset // MAPPER_BANK == (offset + length - 1) // MAPPER_BANK, f'The patch at {offset:#x} crosses a bank')


def check_stub_size(v, asset_sizes):
    """The built stub must fit the room its package reserves. Checked when a GPF is written or loaded."""
    if v['transport'] == 'lockstep':
        size = asset_sizes[v['stub_asset']]
        require(size <= v['stub_max'],
                f'The stub asset is {size} bytes but netplay.stub.max is {v["stub_max"]}: '
                'rebuild the stub with the PLAYNET engine, or reserve more room')


# ---- GPF writer and reader -----------------------------------------------------------------

def _text(value, size):
    data = value.encode('ascii')
    require(len(data) <= size, f'"{value}" is longer than {size} bytes')
    return data.ljust(size, b'\0')


def _section(kind, payload):
    require(len(payload) <= 0xFFFF, 'GPF section too large')
    return struct.pack('<BH', kind, len(payload)) + payload


def gpf_bytes(profile, assets):
    """Compile a version 2 netplay package to a GPF file (PLAYNET-PROTOCOLS.md 8.2)."""
    require(ABI_NETPLAY in abis(profile), 'Only packages with the netplay ABI compile to a GPF')
    v = netplay_values(profile)
    names, blobs = list(assets), list(assets.values())
    sizes = {i: len(data) for i, data in enumerate(blobs)}
    check_netplay(v, sizes)
    check_stub_size(v, sizes)
    lockstep = v['transport'] == 'lockstep'
    body = b''
    if lockstep:
        source = profile['source']
        body += _section(SEC_SOURCE, struct.pack('<II', source['size'], source['crc32']) + _text(source['file'], 12))
        ranges = v['game_ram']
        body += _section(SEC_NETPLAY, struct.pack(
            '<HBBHHHHHHB', v['image_base'], v['input_bytes'], v['stub_asset'], v['stub_load'], v['stub_max'],
            v['transport_area'], v['transport_size'], v['irq_handler'], v['start'], len(ranges))
            + b''.join(struct.pack('<HH', low, high) for low, high in ranges))
        layout = profile['layout']
        require(len(layout) <= 255, 'At most 255 layout entries')
        body += _section(SEC_LAYOUT, struct.pack('<IBB', profile['output']['size'], profile['output']['fill'], len(layout))
                         + b''.join(struct.pack('<BIII', INPUT_ROM if item['source'] == 'input' else names.index(item['source']),
                                                item['offset'], item['size'], item['destination']) for item in layout))
        patches = b''
        for patch in profile['patches']:
            expected, replacement = bytes.fromhex(patch['expected']), bytes.fromhex(patch['replace'])
            require(len(expected) == len(replacement) and 1 <= len(expected) <= 255, 'A patch is 1-255 bytes')
            patches += struct.pack('<IB', patch['offset'], len(expected)) + expected + replacement
        body += _section(SEC_PATCH, struct.pack('<H', len(profile['patches'])) + patches)
        for data in blobs:
            body += _section(SEC_ASSET, data)
        m = v.get('mapper')
        if m:
            body += _section(SEC_MAPPER, struct.pack(MAPPER_FIXED, m['type'], MAPPER_BANK >> 10, m['banks'], m['block'],
                                                     *m['start'], m['pinned'][0], m['pinned'][1], m['min_segments'],
                                                     len(m['pairs'][0]), len(m['pairs'][1]))
                             + bytes(b for page in m['pairs'] for pair in page for b in pair))
    body += _section(SEC_END, b'')
    flags = (1 if lockstep else 0) | ((HOST_MAPPER if v.get('mapper') else HOST_PLAIN) << 1)
    header = bytearray(GPF_HEADER)
    header[0:4] = GPF_MAGIC
    header[4] = GPF_FORMAT
    header[5] = flags
    require(len(body) <= 0xFFFF and GPF_HEADER + len(body) <= GPF_MAX, f'A GPF file is at most {GPF_MAX} bytes')
    header[6:8] = struct.pack('<H', len(body))
    header[12:20] = _text(v['game_id'], 8)
    header[20:44] = _text(v['title'], 24)
    header[44:52] = _text(v['roles'][0], 8)
    header[52:60] = _text(v['roles'][1], 8)
    header[60:98] = _text(v['command'] if not lockstep else '', 38)
    header[98] = v['min_playnet']
    header[99] = sum(CAPABILITIES[r] for r in v['requires'])
    data = bytearray(header + body)
    data[8:12] = struct.pack('<I', crc32(data))
    return bytes(data)


def _unpad(raw):
    return raw.split(b'\0', 1)[0].decode('ascii')


def read_gpf(data):
    """Parse and check a GPF file the way PLAYNET does (PLAYNET-PROTOCOLS.md 8.3, step 1).
    Returns the flat netplay dictionary plus 'hash', 'layout', 'patches', 'assets'."""
    require(len(data) >= GPF_HEADER and data[:4] == GPF_MAGIC, 'Not a GPF file')
    require(data[4] == GPF_FORMAT, f'GPF format {data[4]} is newer than this PLAYNET understands: update PLAYNET')
    require(len(data) <= GPF_MAX, f'A GPF file is at most {GPF_MAX} bytes')
    body_length = struct.unpack_from('<H', data, 6)[0]
    require(GPF_HEADER + body_length == len(data), 'GPF length does not match its header')
    stored = struct.unpack_from('<I', data, 8)[0]
    require(crc32(data[:8] + b'\0\0\0\0' + data[12:]) == stored, 'GPF checksum mismatch: the file is damaged')
    require(data[98] <= PLAYNET_VERSION, 'This game package needs a newer PLAYNET: update PLAYNET')
    require(data[99] & ~sum(CAPABILITIES.values()) == 0, 'This game package needs something this PLAYNET does not have: update PLAYNET')
    lockstep = bool(data[5] & 1)
    host = (data[5] >> 1) & 3
    require(host in (HOST_PLAIN, HOST_MAPPER), 'This game package needs an image host this PLAYNET does not have')
    v = {'hash': stored, 'game_id': _unpad(data[12:20]), 'title': _unpad(data[20:44]),
         'roles': [_unpad(data[44:52]), _unpad(data[52:60])], 'command': _unpad(data[60:98]),
         'min_playnet': data[98], 'requires': [n for n, bit in CAPABILITIES.items() if data[99] & bit], 'transport': 'lockstep' if lockstep else 'none',
         'layout': [], 'patches': [], 'assets': []}
    sections, pos = {}, GPF_HEADER
    while True:
        require(pos + 3 <= len(data), 'GPF ends inside a section header')
        kind, length = struct.unpack_from('<BH', data, pos)
        payload = data[pos + 3:pos + 3 + length]
        require(len(payload) == length, 'GPF section runs past the end of the file')
        pos += 3 + length
        if kind == SEC_END:
            break
        if kind == SEC_ASSET:
            v['assets'].append(bytes(payload))
        elif kind in (SEC_SOURCE, SEC_NETPLAY, SEC_LAYOUT, SEC_PATCH, SEC_MAPPER):
            require(kind not in sections, 'GPF section repeated')
            sections[kind] = payload
        # unknown section types are skipped
    require(pos == len(data), 'Data after the GPF end marker')
    if lockstep:
        require(all(k in sections for k in (SEC_SOURCE, SEC_NETPLAY, SEC_LAYOUT, SEC_PATCH)),
                'GPF lacks a required section')
        p = sections[SEC_SOURCE]
        require(len(p) == 20, 'Bad GPF SOURCE section')
        v['source_size'], v['source_crc32'] = struct.unpack_from('<II', p)
        v['source_file'] = _unpad(p[8:20])
        p = sections[SEC_NETPLAY]
        fixed = struct.calcsize('<HBBHHHHHHB')                   # 17 bytes, then the RAM ranges
        require(len(p) >= fixed, 'Bad GPF NETPLAY section')
        (v['image_base'], v['input_bytes'], v['stub_asset'], v['stub_load'], v['stub_max'], v['transport_area'],
         v['transport_size'], v['irq_handler'], v['start'], count) = struct.unpack_from('<HBBHHHHHHB', p)
        require(len(p) == fixed + 4 * count, 'Bad GPF NETPLAY section')
        v['game_ram'] = [list(struct.unpack_from('<HH', p, fixed + 4 * i)) for i in range(count)]
        p = sections[SEC_LAYOUT]
        require(len(p) >= 6, 'Bad GPF LAYOUT section')
        v['output_size'], v['fill'], count = struct.unpack_from('<IBB', p)
        require(len(p) == 6 + 13 * count, 'Bad GPF LAYOUT section')
        for i in range(count):
            source, offset, size, destination = struct.unpack_from('<BIII', p, 6 + 13 * i)
            require(source == INPUT_ROM or source < len(v['assets']), 'GPF layout names a missing asset')
            v['layout'].append((None if source == INPUT_ROM else source, offset, size, destination))
        p = sections[SEC_PATCH]
        require(len(p) >= 2, 'Bad GPF PATCH section')
        count, at = struct.unpack_from('<H', p)[0], 2
        for _ in range(count):
            require(at + 5 <= len(p), 'Bad GPF PATCH section')
            offset, length = struct.unpack_from('<IB', p, at)
            at += 5
            require(length and at + 2 * length <= len(p), 'Bad GPF PATCH section')
            v['patches'].append((offset, bytes(p[at:at + length]), bytes(p[at + length:at + 2 * length]),
                                 f'GPF patch at {offset:#x}'))
            at += 2 * length
        require(at == len(p), 'Bad GPF PATCH section')
        if host == HOST_MAPPER:
            require(SEC_MAPPER in sections, 'GPF lacks its MAPPER section')
            p = sections[SEC_MAPPER]
            fixed = struct.calcsize(MAPPER_FIXED)
            require(len(p) >= fixed, 'Bad GPF MAPPER section')
            kind, kb, banks, block, s0, s1, s2, s3, pin1, pin2, min_seg, n1, n2 = struct.unpack_from(MAPPER_FIXED, p)
            require(kind in MAPPER_TYPES.values() and kb << 10 == MAPPER_BANK, 'Bad GPF MAPPER section')
            require(len(p) == fixed + 2 * (n1 + n2), 'Bad GPF MAPPER section')
            flat = [list(p[fixed + 2 * i:fixed + 2 * i + 2]) for i in range(n1 + n2)]
            v['mapper'] = {'type': kind, 'banks': banks, 'block': block, 'start': [s0, s1, s2, s3],
                           'pinned': [pin1, pin2], 'min_segments': min_seg, 'pairs': [flat[:n1], flat[n1:]]}
            v['patch_spans'] = [(o, len(e)) for o, e, _, _ in v['patches']]
            require(v['layout'] == [(None, 0, v['output_size'], 0)], 'A mapper-ram image is the ROM itself')
    sizes = {i: len(asset) for i, asset in enumerate(v['assets'])}
    check_netplay(v, sizes)
    check_stub_size(v, sizes)
    return v


def gpf_image(gpf, rom):
    """What PLAYNET does with a checked GPF and the player's ROM (8.3 steps 2-3): the RAM image and the stub."""
    require(gpf['transport'] == 'lockstep', 'This game is its own program: there is no image to build')
    require(len(rom) == gpf['source_size'] and crc32(rom) == gpf['source_crc32'],
            f'{gpf["source_file"]} is not the dump this game package was made for')
    image, _ = apply_layout_and_patches(rom, gpf['assets'], gpf['output_size'], gpf['fill'],
                                        gpf['layout'], gpf['patches'])
    return bytes(image), gpf['assets'][gpf['stub_asset']]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rom', nargs='?', type=Path, help='supported ORIGINAL ROM')
    parser.add_argument('--profile', type=Path, default=ROOT / 'profiles/goonies/profile.json')
    parser.add_argument('--music', type=Path, help='JSON configuration overrides')
    parser.add_argument('--output', '-o', type=Path, help='new ROM path (must not exist)')
    parser.add_argument('--write-config', type=Path, help='write editable defaults and exit')
    parser.add_argument('--gpf', type=Path, help='compile a netplay package to this GPF file (must not exist); '
                                                  'with a ROM, check the package against it first')
    args = parser.parse_args(argv)
    try:
        profile, assets = load_profile(args.profile)
        if args.gpf:
            require(args.output is None and args.music is None, '--gpf takes no --output or --music')
            require(not args.gpf.exists(), 'Output GPF already exists')
            data = gpf_bytes(profile, assets)
            if args.rom:
                image, _ = build(args.rom.read_bytes(), profile, assets)
                require(gpf_image(read_gpf(data), args.rom.read_bytes())[0] == image,
                        'Internal error: the GPF does not rebuild the same image')
            else:
                read_gpf(data)
            with args.gpf.open('xb') as stream:
                stream.write(data)
            print(f'Created {args.gpf} ({len(data)} bytes, profile hash {struct.unpack_from("<I", data, 8)[0]:08x})'
                  + ('' if args.rom else '; not checked against a ROM'))
            return 0
        if args.write_config:
            require(ABI_MUSIC in abis(profile), 'This package has no music configuration')
            with args.write_config.open('x', encoding='utf-8') as stream:
                json.dump(profile['defaults'], stream, indent=2)
                stream.write('\n')
            print(f'Configuration: {args.write_config}')
            return 0
        require(profile['output'].get('target', 'rom-file') == 'rom-file',
                'This package builds a RAM image for PLAYNET and never a ROM file: use --gpf')
        require(args.rom is not None and args.output is not None, 'ROM and --output are required')
        require(args.rom.resolve() != args.output.resolve(), 'Output must differ from the original ROM')
        # Kept with the profile, not beside the ROM: a ROM folder served to
        # msxarch listed every manifest as a game. It records the latest build
        # of that output name, so a rebuild replaces it.
        manifest_path = args.profile.resolve().parent / 'builds' / (args.output.name + '.json')
        require(not args.output.exists(), 'Output ROM already exists')
        require(args.rom.stat().st_size <= MAX_ROM, 'Input ROM too large')
        overrides = read_json(args.music) if args.music else None
        data, manifest = build(args.rom.read_bytes(), profile, assets, overrides)
        with args.output.open('xb') as stream:
            stream.write(data)
        try:
            manifest_path.parent.mkdir(exist_ok=True)
            with manifest_path.open('w', encoding='utf-8') as stream:
                json.dump(manifest, stream, indent=2)
                stream.write('\n')
        except OSError:
            args.output.unlink()  # only the file exclusively created above
            raise
        print(f'Created {args.output} ({len(data)} bytes, {manifest["mapper"]})')
        print(f'SHA-256: {manifest["output_sha256"]}')
        print(f'Manifest: {manifest_path}')
        return 0
    except (OSError, ValueError, KeyError, TypeError, struct.error) as exc:
        print(f'Patch error: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
