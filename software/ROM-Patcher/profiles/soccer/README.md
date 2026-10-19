# Konami's Soccer netplay package

Package format `msxpi-rom-patch` version 2 with the `msxpi-netplay-v1` ABI (see `../../FORMAT.md` and
`documents/PLAYNET-PROTOCOLS.md`, section 5, for the analysis behind every patch).

| | |
|---|---|
| Input | `SOCCER.ROM`, Konami's Soccer (RC-732), 32768 bytes, CRC-32 `74BC8295`, SHA-256 `b9536809a1784afb2e49a43d80ba9c6c8c15cd31ecbd6c284e9bf62c6927dcd4` |
| Output | a RAM image for PLAYNET (`output.target = "ram-image"`), never a ROM file |
| Game id, roles | `soccer`; `H` (seat 0, player 1), `C` (seat 1, player 2) |
| Layout for PLAYNET | stub F000h-F23Fh (576 bytes), transport F240h-F2FFh, game RAM E000h-EFFFh and stack F30Ch-F37Fh, interrupt handler 402Eh |

No ROM data is included. The player supplies their own dump.

## Status (implementation step 2)

- The 13 patches are exactly those of `SOCCERNET.COM` (`software/Client/src/soccernet/soccernet.asm`, label `patches`).
  `tests/test_gpf.py` proves that both give the same RAM image, byte for byte.
- The stub asset is still today's `SOCCERNET` stub: the MSXPi transport is inside it, and it shakes hands at frame 0. It is
  729 bytes, more than the 576 the PLAYNET layout reserves. So `patch_rom.py --gpf` refuses this package, by design, until the
  stub is rebuilt from the PLAYNET engine (step 4). At that point the package also gains the patch at 4096h, which sends the game's
  H.KEYI hook to the transport's `XIRQ` entry (specification, section 5).

## Rebuild (developers)

```console
python profiles/soccer/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe
```

This copies the stub template into `src/`, assembles `assets/stub.bin`, and writes `profile.json` with the stub's entry addresses
inside the patches.

## Check against your ROM

```console
set SOCCER_ROM=C:\path\to\SOCCER.ROM
python -m unittest tests.test_gpf
```
