# MSXPi ROM patch package, versions 1 and 2

This is the handoff contract between game analysis and the patching application.
Version 1 describes music packages. Version 2 (section "Version 2" below) makes
the music part one optional ABI and adds the netplay ABI used by PLAYNET.
`patch_rom.py` reads both versions.
The producer supplies a directory containing `profile.json` and referenced
binary assets. Assembly sources and evidence/tests should accompany it.
JSON numbers are decimal integers; binary strings are hexadecimal without `0x`.
Offsets always refer to **file bytes**, never CPU addresses, unless explicitly
identified as runtime symbols. Duplicate JSON keys are invalid.

## Processing order

1. Validate format/version, input size/hash, and asset hashes.
2. Allocate `output.size` bytes initialized to `output.fill`.
3. Copy the non-overlapping `layout` ranges into the output.
4. Apply non-overlapping `patches`, verifying every expected byte.
5. Music ABI only: merge music overrides into defaults, validate
   IDs/names/modes/capacity, and populate the declared zero-filled music
   configuration regions.
6. Write a new ROM and deterministic build manifest. Never modify the input.
   A package whose `output.target` is `ram-image` (netplay) never produces a
   ROM file: it is compiled to a GPF file instead (`--gpf`), and PLAYNET
   repeats steps 2-4 in RAM on the MSX.

File size limit: 16 MiB. Asset paths resolve inside the profile directory;
paths escaping it are rejected, including symlinks resolving outside it.
No shell commands, Python code, assembler invocation, expression evaluation,
or arbitrary callbacks are part of the consumer format.

## Required fields

| Field | Meaning |
|---|---|
| `format` | Exact string `msxpi-rom-patch` |
| `version` | Integer `1`; incompatible future versions must be rejected |
| `id` | Nonempty, versioned package identity |
| `source.size`, `source.sha256` | Exact original ROM size and SHA-256 |
| `output.size`, `output.fill`, `output.mapper` | Output allocation, fill byte, mapper description |
| `requirements` | Human-readable runtime prerequisites |
| `assets` | Object of asset names mapped to `{file, sha256}` |
| `layout` | Array of `{source, offset, size, destination}` copies |
| `patches` | Array of `{offset, expected, replace, reason}` operations |
| `music` | Configuration ABI and output offsets, described below |
| `sounds` | Game IDs keyed by stable strings, mapped to `{raw_ids, description}` |
| `defaults` | Complete default music configuration |
| `symbols` | Optional diagnostic object: label to runtime CPU address |

`layout.source` is `input` or an asset name. The name `input` is reserved.
Source/destination ranges must fit their buffers. Unassigned output areas keep
the fill byte. Patches use equal, nonempty byte lengths, so ROM layout cannot
shift accidentally. Put insertions and bank rearrangements in the layout.

Original ROM version differences are expressed as separate profiles in v1.
Do not use fuzzy matching or silently apply a nearby game's patch locations.

## Version 2

Everything above applies, with these changes:

| Field | Version 2 rule |
|---|---|
| `version` | Integer `2` |
| `abi` | Required. Nonempty array of the ABIs the package uses, no duplicates: `msxpi-music-v1`, `msxpi-netplay-v1`. A version 1 package is read as `["msxpi-music-v1"]`. |
| `music`, `sounds`, `defaults` | Required only with `msxpi-music-v1` (described below, unchanged) |
| `netplay` | Required with `msxpi-netplay-v1` |
| `source.crc32` | Required with the netplay ABI: CRC-32 (zlib) of the original ROM, as an integer. The MSX identifies the dump with it. `patch_rom.py` checks it whenever it is present. |
| `source.file` | Required with the netplay ABI: the upper-case 8.3 name PLAYNET opens by default, e.g. `SOCCER.ROM` |
| `output.target` | Optional. `rom-file` (default) writes a new ROM as in version 1. `ram-image` never writes a ROM: the package compiles to GPF. A netplay `lockstep` package must use `ram-image`. |
| `source` | May be `null` for a netplay game with transport `none` (the game is its own program); then `layout`, `patches` and `assets` are empty |

The `netplay` section, its validation rules, the GPF binary layout and what
PLAYNET checks when it loads one are specified in
`documents/PLAYNET-PROTOCOLS.md`, sections 7 and 8. In short:

```json
"netplay": {
  "abi": "msxpi-netplay-v1", "game_id": "soccer", "title": "Konami's Soccer",
  "roles": ["H", "C"], "transport": "lockstep", "input_bytes": 1,
  "image": {"host": "plain", "base": 16384},
  "stub": {"asset": "stub", "load": 61440, "max": 576},
  "transport_area": {"address": 62016, "size": 192},
  "game_ram": [[57344, 61439], [62220, 62335]],
  "irq_handler": 16430, "start": "header-init", "min_playnet": 1
}
```

Commands:

```console
python patch_rom.py --profile profiles/soccer/profile.json --gpf SOCCER.GPF [SOCCER.ROM]
```

With the ROM, the package is first built and checked against it (hash,
CRC-32, every expected byte), and the GPF is read back and must rebuild the
same image. The GPF is written only if it does not exist. The netplay rules
are checked twice, once on the JSON and again on the GPF, so a damaged or
hand-edited GPF is refused the same way the MSX refuses it.

The trust boundary is unchanged: patches and assets are Z80 code. Validation
catches corrupt or mismatched packages, not malicious ones.

## Music ABI `msxpi-music-v1`

`music` has these fields:

| Field | Region written by the patcher |
|---|---|
| `abi` | Exact string `msxpi-music-v1` |
| `map_offset` | 256 bytes: raw game sound ID to track index |
| `modes_offset` | 256 bytes: index 0 unused; 0 = play, 1 = loop |
| `options_offset` | Two bytes: exit enabled (0/1), silence grace frames (0..255) |
| `names_offset` | Packed ASCII filename list |
| `names_capacity` | Reserved list size; unused bytes zero-filled |
| `names_encoding` | Optional `ascii` (default) or `escape-32` |

These regions must be disjoint, zero-filled after layout/patch application,
and must not overlap byte patches. They can lie in a payload asset. The profile
producer ensures the bootstrap copies them to the RAM addresses expected by
the payload; the generic patcher does not infer runtime memory mapping.

Track indices are one-based, at most 255. Zero means retain original audio.
The Nth filename is track N. Each filename ends in NUL and an extra NUL marks
the end of the list. With no tracks, the list is exactly two NULs before padding.
Filenames cannot be empty, exceed 127 ASCII bytes, contain nonprintable bytes,
or have surrounding whitespace.

`escape-32` stores filename byte `32` hex (ASCII `2`) as `02` hex. The producer's
adapter must restore it before using the list. NUL/double-NUL delimiters do not
change. This prevents the current server's bank-switch scanner from rewriting
filenames such as `x2ab.mp3` as Z80 instructions. It is unambiguous because byte
`02` is forbidden in input filenames. ID/mode tables are not encoded; profiles
with many track indices must separately validate their scanner compatibility.
The supplied Goonies profile has at most 30 indices, none equal to opcode `32`.

`sounds` keys represent the analysis task's stable identifiers; they need not
be numeric. Each record lists unique `raw_ids` in 0..255. An adapter for a game
with wider or structured identifiers must normalize them to this byte-sized
event space. Every raw ID must belong to at most one record.

`defaults` and user configuration contain:

```json
{
  "tracks": {"theme": {"filename": "theme.mp3", "mode": "loop"}},
  "sounds": {"stage": "theme", "victory": null},
  "exit_enabled": true,
  "gap_frames": 120
}
```

The keys of the effective `sounds` object must exactly match the profile's
sound definitions. A value names a defined track or is `null` for native audio.
User files may be partial: tracks and sound mappings merge by key, while exit
and grace settings replace their defaults. A track entry replaces that entire
entry and must include both `filename` and `mode`.

Indices are allocated in profile sound-definition order, deduplicating equal
`(filename, mode)` pairs. Unreferenced tracks are validated but not stored.
Different modes for the same file are distinct tracks. Reordering JSON object
members may change binary track indices, but not the configured behavior.

## Supplied Z80 runtime calling contract

`profiles/goonies/src/runtime.asm` is the reusable single-player implementation.
`game.asm` supplies its adapter and executes `service` with interrupts disabled
from a safe foreground point, not from an interrupt handler. The adapter owns
register preservation and native-game state compatibility at its hooks.

- `desired_music`: return A = track index, or zero for silence/native audio.
- `music_id`: map raw ID in A through the 256-byte table; A = result, carry set
  for a nonzero result. Preserves HL. This runtime uses page-aligned tables.
- `service`: manage single current/desired track, one owned decimal PID, the
  silence grace, and bounded command/reply transport. May clobber main registers;
  the supplied transport can use shadow registers, hence foreground DI context.
- `stop_music`: stop only the saved PID and consume the reply. The caller must
  ensure the PID is nonempty. A valid reply is `Ok` with optional line ending.
- `link_failed`: terminal native-audio fallback flag for this session. Do not
  mute native channels or attempt routine service commands when set.
- `pid`: 11-byte buffer, at most 10 decimal digits plus NUL. Muting is allowed
  only after successful parsing and when `link_failed` is zero.

The adapter must leave original sequencing intact for fallback. The Goonies
adapter hooks channel-volume output to mute mapped melodies only after external
playback succeeds, retaining sound effects and original state progression.
It examines channel IDs in A/B/C order; this priority is game-specific.

Exit is also adapter-specific. Goonies polls Ctrl+Shift+F5, stops its PID,
clears the original lower-bank and bootstrap `AB` headers in mapper RAM,
removes the timer hook, and jumps to BIOS reset. This is not a generic reset
algorithm for every mapper or cartridge.

## Analysis-package acceptance checklist

- Original hash and expected bytes verified against the actual input revision.
- Mapper conversion, bank visibility, RAM/stack reservations, and hook side
  effects reviewed against the game and supported loader.
- Sound IDs, aliases, effects, silence, and event priority documented with
  evidence. Unidentified IDs must not be given invented event names.
- Playback, sustained silence, transitions, failure fallback, effects, and exit
  checked in an emulator at normal speed; live MSXPi transport checked separately.
- No original ROM or MP3 included in the distributable package.
- Asset built from accompanying sources; profile hashes updated with it.

The build manifest records input/output hashes, profile identity/fingerprint,
effective music settings, assigned track indices, symbols, and requirements.
It is written to `builds/<output name>.json` beside the profile, never next to
the ROM. It contains no timestamp, so identical input/profile/configuration gives
identical ROM bytes and manifest content.
