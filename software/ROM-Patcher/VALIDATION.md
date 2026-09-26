# Validation record

## Timeout update

The current payload increases PAYLOAD_WAIT to 18 passes of 65,535 polls,
preserving BC and DE and returning carry on exhaustion. Its executable/state
portion is now 1858 bytes. The asset and profile were rebuilt with sjasmplus
1.24.0, without errors or warnings. The hashes and live emulator results below
describe the previous release, not hardware validation of this timeout change.
The updated build passes all 13 patcher checks, including original-ROM and
server mapper scanner checks. Physical Raspberry Pi validation remains pending.

Build date: 2026-09-25.

Input Goonies ROM (32768 bytes):
`2ba602b1a17e4797da1588afe6e65640331c15746bf5959f4778b404be929dde`

Default output, ASCII16 (65536 bytes):
`208c20cf2876bfc8a81003a625df9f8c8e1279df650ac9b13d0c62593e8fbcdd`

Preassembled resident asset (8192 bytes; executable/state portion 1851 bytes):
`68612d72a71f2651512eb467c6220ba3afd8b121fd1da76d3f672a74eb4e8617`

## Completed checks

- Assembly: sjasmplus 1.24.0, zero errors and warnings.
- Python: 13 checks passed, including original-ROM validation and a regression
  against the actual server mapper scanner. Covered size/hash/expected bytes,
  output preservation, overlapping regions, asset containment/checksums,
  duplicate JSON keys, filename capacity, multiple mappings/modes, native-only
  mappings, double-NUL lists, and scanner-safe filename storage.
- Windows Python 3.11 and Linux Python 3.12 generated identical default ROMs.
- Z80 execution in openMSX, Canon V-25, speed 100: valid PID parsing, play then
  loop, stopping the previous PID before switching, deduplication, grace period,
  sustained-silence stop, and selective native PSG volume filtering.
- Failure execution: actual transport with no MSXPi attached latches fallback
  after the first exchange; subsequent frames do not retry. A reply with a
  numeric prefix followed by invalid text also falls back and discards the
  partial PID. Native music volume and effects remain available.
- Filename regression: `x2ab.mp3` is corrupted by an unprotected server scan;
  the protected list survives the same scanner and the Z80 code emits exactly
  `music play x2ab.mp3` after decoding.
- Live transport: Canon V-25 + MSXPi + ram4mb, Archive option 5, fresh profile ROM
  loaded using the corrected existing msxarch and boot disk at speed 100.
  The real server returned decimal IDs to `music loop`. Ctrl+Shift+F5 sent
  `music stop` for the currently owned ID, consumed its reply, cleared the
  active bootstrap header, and returned to DOS without another game entry.
  `music getids` afterward did not include the stopped test ID.
- Active gameplay was separately confirmed visually in Scene 01-01, with
  native state `5,1`, player flag set, and melodic IDs `9B` on the channels.
  The same external loop PID survived the transition into play and was stopped
  only by the exit shortcut. The test uses two Space presses to leave the
  attract sequence and start the game; F1 is not the start control.

The ROM served from cache, the ROM in gameroms, and the generated output have
the same hash. The existing audited ROM, original ROM, server source, loader,
and boot disk were not changed by this framework implementation.

## Scope and limits

Live tests used the Windows MSXPi server and openMSX; they are not a physical
Raspberry Pi / MSX hardware certification. Audio control was verified through
commands, replies, PID ownership, and native PSG register output.

The initial profile intentionally retains one default MP3 for the recognized
melodic range. Individual song/event naming remains separate analysis work;
the configuration and runtime already support different filenames and modes
for those IDs. There is no simultaneous external playback.

The current loader is a runtime prerequisite. No new loader changes were
needed, so this implementation did not require modifying or retesting the
VAMPIRE mapper cache code. The earlier loader regression test remains separate.

An external emulator close/reset bypasses the exit shortcut. An unreachable
server cannot be told to stop an already-running player; this is distinct
from the verified native-audio fallback behavior.
