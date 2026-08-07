# LOADROM MSXPi network-loading patch

Binary patches for the third-party MSX utility **LOADROM.COM** that add
loading ROM images over the MSXPi network interface, as an alternative
source to local disk. No source is available for LOADROM.COM itself, so
this works by binary-patching the original `.COM` file: a handful of
`CALL` instructions are redirected to appended code, and the original
file's own MegaROM mapper/bank-switch/relocation logic is left completely
untouched, byte-for-byte, in both files this project targets.

## Credits

- **LOADROM.COM** itself: (c) Victor Martinez & Trunks, 1998-2015.
  Not affiliated with this project - see `loadrom1.97-readme.txt` for
  their own original readme and version history. This project only
  binary-patches their published `.COM` file; none of their code is
  reproduced here in source form (no source was ever published for it).
- **MSXPi network-loading patch**: costarc / the MSXPi project
  (github.com/MSXPi), 2026.

## What this adds

A new load source - the MSXPi network interface - alongside LOADROM's
existing local-disk loading, for both plain (<=32KB) ROMs and MegaROMs
(Konami/Konami SCC, ASCII8, ASCII16 - the same three mapper families
LOADROM itself supports; this patch doesn't add mapper coverage LOADROM
didn't already have). Invoke with `/N` on the command line, e.g.:

```
LOADROM USAS.ROM /N
```

Without `/N`, the patched binary behaves exactly like the unmodified
original - local disk loading is untouched.

Design principle throughout, in both patch generations: **this patch never
decides plain-vs-mapped, bank count, bank size, or anything else about the
ROM itself** - it only resolves a filename and delivers sequential blocks
on demand to msxpi-server.py's `ploadr` command. Everything downstream of
that - mapper detection, bank-switch-opcode patching, relocation, the
actual game handoff - is entirely LOADROM's own unmodified logic, exactly
as it already works for a local file.

## Two patch generations

| | LDRPATCH.MAC | LDRPATCH197.MAC |
|---|---|---|
| Targets | LOADROM.COM v1.0 (1998, 5023 bytes) | LOADROM.COM v1.97 (2015, 6016 bytes) |
| Patcher | `patch_loadrom.py` | `patch_loadrom197.py` |
| Output | `LOADRPI.COM` | `LOADROM.COM` (rebranded banner: "loadrom 2.0P") |

The v1.97 patch's *output* filename is deliberately the same `LOADROM.COM`
as the unpatched original it's built *from* - don't confuse the two: the
unpatched original is an input to `patch_loadrom197.py` (supplied
separately, not part of this repo - see Building, below), while
`Client/src/loadrom/LOADROM.COM` in this repo is always the patched
result. On the deployed disk images, the patched `LOADROM.COM` replaces
the unpatched original entirely - there's no unpatched copy kept
alongside it there.

v1.97 was targeted as a second generation after v1.0-based testing turned
up a hard-to-pin-down "loads cleanly, then crashes to DOS on handoff" bug
on some MSX-DOS/hardware configurations. v1.97's own changelog (17 years
of fixes over v1.0, see `loadrom1.97-readme.txt`) includes several fixes
in exactly this territory - EI/interrupt-mode handling around bank
switches, per-hardware BIOS-variant detection, MegaROM type
auto-detection reliability - on the theory that some of that bug was
already fixed upstream rather than something this patch introduced.
Testing on real hardware bore this out: MSXPIDOS+RAM2MB, previously
failing on every mapped ROM tested, now loads the large majority of
tested MegaROMs (Konami/SCC, ASCII8, ASCII16 alike) successfully via the
v1.97-based patch. Both generations are kept - `LOADRPI.COM` isn't
obsolete, since some hardware/DOS configurations may still behave
differently between the two upstream versions.

v1.97's internals turned out to be a real evolution from v1.0, not just
relocated code, so the two `.MAC` files are not just address tables -
notably: v1.97 has no surviving command-line option scanner (removed
once type auto-detection matured upstream), so `/N` detection moved to a
raw command-tail scan instead of hooking an option loop; v1.97 tries
MSX-DOS2 `FFIRST`/`FNEXT` for its menu display before falling back to the
same old CP/M-style `F_SFIRST`/`F_SNEXT` v1.0 used as the *authoritative*
search either way, so only that fallback pair needed patching; and
v1.97's search-result buffer is a runtime-computed address (read via a
stable pointer variable) rather than v1.0's fixed compile-time address.
See each `.MAC` file's own top-of-file comment for the full patch-site
table and reasoning - kept there rather than duplicated here so it can't
drift out of sync with the actual code.

## Building

Requires [zmac](http://48k.ca/zmac.html) and
[hex2bin](https://github.com/jhlagado/hex2bin) on `PATH` (or invoke by
full path), plus a genuine, unmodified LOADROM.COM of the matching
version (not included in this repo - not this project's to redistribute).

```bash
# v1.0 -> LOADRPI.COM
zmac -I . -I ../../../asm-common/include LDRPATCH.MAC
hex2bin -s 1900 zout/LDRPATCH.hex
python patch_loadrom.py <original LOADROM.COM v1.0> zout/LDRPATCH.bin LOADRPI.COM zout/LDRPATCH.lst

# v1.97 -> LOADROM.COM
zmac -I . -I ../../../asm-common/include LDRPATCH197.MAC
hex2bin -s 1900 zout/LDRPATCH197.hex
python patch_loadrom197.py <original LOADROM.COM v1.97> zout/LDRPATCH197.bin LOADROM.COM zout/LDRPATCH197.lst
```

Of the three files each `.MAC` includes, two (`include.asm`, `msxpi_bios.asm`
- shared MSXPi protocol constants and BIOS glue, not specific to either
LOADROM version) are the project's own canonical copies in
`asm-common/include/`, resolved via the second `-I` above rather than
duplicated here. The third, `msxpi_putchar.asm`, is kept as a local copy
in this directory rather than referencing `asm-common/include/putchar-
msxdos.asm`: the two aren't equivalent - this patch's copy calls the
BDOS console-output function directly (`CALL 5`, matching how every BDOS
call elsewhere in these `.MAC` files and in LOADROM itself works, since
this is a plain `.COM` program under MSX-DOS, not a device driver or ROM
context), where `putchar-msxdos.asm` calls `$A2` instead - not a BDOS
entry point (that's always `CALL 5`); it looks like the MSX BIOS `CHPUT`
vector, which needs a different calling context than this patch has.

Both patcher scripts verify the source file's exact length and the exact
original bytes at every patch site before writing anything, and refuse to
patch (rather than silently producing a broken binary) if either check
fails - almost always meaning the source `.COM` isn't the exact version
this patch was built against.

Deploy the resulting `.COM` file to `msxpiboot.dsk` (or wherever else it's
served from) via `dsktool.py copy <file> <image.dsk>:<NAME.EXT>` - see the
project's own build workflow notes for the full disk-image conventions.
