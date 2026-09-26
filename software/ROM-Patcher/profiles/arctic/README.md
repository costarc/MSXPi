# Arctic MSXPi profile

Input is **ARCTIC.ROM**, the 128 KiB MSX2 cartridge, not a DOS COM file.
The accepted SHA-256 is
`3dcb85704006e2a3d95f11e9e2dbf13f1457b55f89727d70940ed7720ea0c78c`.

From the ROM-Patcher directory:

```console
python patch_rom.py --profile profiles/arctic/profile.json --write-config arctic-music.json
python patch_rom.py "C:\Users\roniv\Dev\MSX\gameroms\ARCTIC.ROM" --profile profiles/arctic/profile.json --music arctic-music.json --output "C:\Users\roniv\Dev\MSX\gameroms\ARCTIC_MSXPI.ROM"
```

Edit `arctic-music.json` before building. Defaults are **placeholder filenames**
`ARCTIC_01.mp3` through `ARCTIC_14.mp3`, each in `loop` mode. Supply these
files on the Pi or replace the filenames with your own music. No music files
are included. A missing file or failed first response triggers native-audio
fallback for the remainder of the session. Use `play` for one-shot tracks;
set an individual `sounds` value to `null` to retain that native tune.

Sound keys `01` through `0e` are hexadecimal IDs for the game's 14 melodic
selectors. ID zero stops music. Selector 1 is used on the title screen;
the remaining selectors have not all been assigned gameplay event names.
Default silence tolerance is zero frames. Identical filename/mode mappings
share one external track and do not restart it on each mapped ID change.

## Loading and implementation

The output is a 136 KiB ASCII16 image for **MSX2**, loaded through MSXPi's
writable `msxarch` RAM mapper loader. An MSX1 such as Canon V-25 is not a
suitable test machine. A direct read-only cartridge is unsupported.
Invalidate the server's cached copy when replacing an existing output name.

The original eight 16 KiB banks retain their positions. The added 8 KiB
holds the runtime and configuration as the first half of bank 8; the image is
not padded. msxpi-server rounds the bank count up to 9 and sends only the
136 KiB; msxarch allocates nine segments and receives just what was sent. A gateway in original bank 0 tracks bank selection, captures the
music request at `$7748`, services commands from foreground input polls,
then restores the game bank. No network exchange runs in the timer handler.
Only the melodic volume writer at `$7E6D` is muted after a valid playback ID;
the original sequencer and separate effects engine remain present.

The profile inherits the Goonies runtime's enlarged transfer timeout.
Ctrl+Shift+F5 requests a stop for its owned PID, clears the writable cartridge
header, removes the timer hook, and resets through BIOS. Returning to DOS
depends on the MSXPi boot environment. An unreachable server cannot be
guaranteed to stop an already-running player.

## Developer rebuild

Applying the profile requires only Python's standard library. Rebuilding
assembly assets additionally requires sjasmplus:

```console
python profiles/arctic/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\Users\roniv\Dev\MSX\gameroms\ARCTIC.ROM
```

The rebuild copies the shared runtime sources from the Goonies profile and
relocates their tables into the added bank. It does not modify Goonies.
Original ROM content is not included in the profile assets.
