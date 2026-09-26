# MSXPi ROM music patcher

A standalone Python 3.9+ tool that applies a game-analysis package to an
original ROM. No Python dependencies, assembler, MSXPi source checkout, or
original game data are bundled or required beyond your own input ROM.
The resulting cartridges require MSXPi and the compatible `msxarch` loader.
Music tunes are replaced by music played via MSXPi music command. 
In addition, the patched ROM also has a GAME clean exit added, to exit the game via CTRL+SHIFT+F5.

The bundled runtime now allows approximately 15–17 seconds per pending
MSXPi transfer on a standard 3.58 MHz MSX, to accommodate cold music-player
startup. The limit is 18 passes of 65,535 polls in
`profiles/goonies/src/payload_generated.asm` (`PAYLOAD_WAIT`). Accelerated
CPUs shorten this CPU-based timeout. An unavailable Pi therefore takes longer
to trigger native-music fallback. Apply the patch again to the original ROM
to obtain this change; existing patched ROMs are not updated automatically.

## Patch Goonies

From this directory in Windows:

```console
python patch_rom.py --write-config my-music.json
python patch_rom.py "C:\Users\roniv\Dev\MSX\gameroms\GOONIES.ROM" --music my-music.json --output "C:\Users\roniv\Dev\MSX\gameroms\GOONIES_REMIX.ROM"
```

Python on Linux/macOS uses the same command with local paths (`python3` where
appropriate). The default profile is `profiles/goonies/profile.json`.
An explicit `--profile path/to/profile.json` selects another analysis package.
The output and its `.ROM.json` build manifest must not already exist. The
original ROM is never modified. Only the identified 32 KiB Goonies revision
is accepted (SHA-256 is recorded in the profile).

The default plays `music loop The_Goonies_R_Good_Enough.mp3` and uses the same
song for all melodic IDs recognized by the working Goonies patch. Put the
music on the MSXPi server as usual. Filename matching follows the server's
filesystem and music-path handling.

Load the new ROM through `msxarch` using the corrected RAM mapper loader from
the Goonies work. The framework requires no further loader or server changes.
If replacing a ROM under the same name, remove that ROM's cached copy from
`C:\tmp\msxpi\` before loading; the server may otherwise reuse an older image.
A fresh filename avoids that cache collision.

## Configure music

The generated configuration lists every supported normalized Goonies music
ID. Change individual `sounds` entries to refer to named entries in `tracks`.
This smaller override file is also valid; unspecified settings retain defaults:

```json
{
  "tracks": {
    "intro": {"filename": "intro.mp3", "mode": "play"},
    "long_phase": {"filename": "stage_music.mp3", "mode": "loop"}
  },
  "sounds": {
    "24": "intro",
    "25": "long_phase",
    "0f": null
  },
  "exit_enabled": true,
  "gap_frames": 120
}
```

These are configuration examples, **not identified names for Goonies events**.
ID `24` was observed as raw `A4` in the previous working game's music state;
descriptive event names and the other IDs still require the separate analysis
task. The profile preserves the prior melodic range `0F..2C` and its raw ID
aliases; it does not claim that all those IDs occur during gameplay.

- `play` plays once. `loop` repeats until a track change, sustained silence, or exit.
- `null` uses the original audio for that sound ID.
- The same filename **and** mode share one runtime track, so shared mappings
  do not restart the song at every sound-ID change.
- Only one external track plays at a time. A change stops its captured PID
  before starting the next track. Effects do not launch external players.
- `gap_frames` tolerates brief gaps in the native channel states. Default 120
  is about two seconds at 60 Hz (2.4 seconds at 50 Hz). Zero stops immediately.
- Filenames are 1..127 printable ASCII bytes; spaces inside a filename are
  allowed. No leading/trailing spaces or control characters. The packed list
  has 3568 bytes available in this profile.

Filenames are packed as `name\0name\0\0`; an empty list is `\0\0`. There are
separate ID and mode tables, so names can change length without reassembly.
The patcher checks all limits before creating output.
For compatibility with the server's mapper scanner, ASCII `2` is stored as
byte `02` in ROM filenames and restored before use in RAM. The NUL delimiters
are unchanged. Configure filenames through JSON rather than editing ROM bytes.

## Fallback and exit

Until a valid decimal playback ID arrives, the native Goonies music runs
normally. Once playback succeeds, only mapped melodic channel volumes are
suppressed; the sequencer and sound effects keep running. A missing server,
transport failure, or invalid playback reply latches native-audio fallback
for the rest of the session, avoiding repeated communication stalls.

Press **Ctrl+Shift+F5** to exit. The runtime stops its own music PID, clears
both relevant `AB` headers in the RAM-loaded cartridge, removes the game timer
hook, and resets through the BIOS. MSXPi boots back into DOS. Set
`exit_enabled` to false to disable the shortcut.

This exit mechanism is specifically for `msxarch` RAM loading. A physical or
emulated read-only cartridge cannot erase its own header. Closing the emulator
or pressing its external reset button bypasses the exit hook. If the server
connection has failed after starting music, the game can restore native audio
and exit, but it cannot guarantee that the unreachable server stopped its player.

## Create another game's analysis package

The contract is documented in [FORMAT.md](FORMAT.md). Supply:

1. Exact original-ROM size and SHA-256.
2. An output layout with input ranges and small preassembled payload assets.
3. Offset/expected-bytes/replacement patch operations with reasons.
4. Detected game sound IDs and their raw aliases.
5. Configuration table locations and editable music defaults.
6. A game-specific adapter that detects music, preserves effects/fallback,
   reserves safe memory, and implements any mapper/exit requirements.

`patch_rom.py` contains no Goonies address logic. A compatible package requires
no change to the application. The supplied runtime is reusable for adapters
that implement its calling contract; a game with different memory or audio
architecture may need its own payload while retaining the same package format.
Profiles are declarative data; the app never imports or executes profile scripts.

## Rebuild and test (developers only)

Users do **not** need these steps. Assembly sources and bounded MSXPi transport
snapshots are included so the asset is reviewable and reproducible:

```console
python profiles/goonies/rebuild.py --assembler "C:\Users\roniv\Dev\bin\sjasmplus.exe"
python -m unittest discover -s tests -v
```

The developer rebuild regenerates the asset, profile, symbol map/listing, and
example configuration. Edit a separate `my-music.json` for personal settings.
Set `MSXPI_TEST_ROM` to your original ROM to also run original-image checks.

`tests/emulator_runtime.py` executes the real Z80 code in openMSX with a command
test double and with no MSXPi attached. It covers play/loop transitions, PID
ownership, deduplication, silence handling, music muting, effects, malformed
replies, and offline fallback. `tests/emulator_live.py` loads a staged ROM through
Archive and checks music, keyboard exit, DOS return, and player cleanup.
Both scripts provide `--help`; all emulator tests use speed 100 with throttling.

The Goonies-specific ROM-write neutralizations are explicit checked patches.
There is no dependency on importing the server's mapper scanner or on a
hard-coded development-machine path when applying a patch.
