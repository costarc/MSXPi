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

- The patches are those of `SOCCERNET.COM`, plus the frame catch-up at 4044h (below) (`software/Client/src/soccernet/soccernet.asm`, label `patches`).
  `tests/test_gpf.py` proves that both give the same RAM image, byte for byte.
- The stub asset is still today's `SOCCERNET` stub: the MSXPi transport is inside it, and it shakes hands at frame 0. It is
  729 bytes, more than the 576 the PLAYNET layout reserves. So `patch_rom.py --gpf` refuses this package, by design, until the
  stub is rebuilt from the PLAYNET engine (step 4). At that point the package also gains the patch at 4096h, which sends the game's
  H.KEYI hook to the transport's `XIRQ` entry (specification, section 5).

## Frame catch-up

Every frame is one run of the H.KEYI handler, and an interrupt that comes while it runs is dropped (the busy flag E005h).
Over TCP/IP, MSX-DOS's own handler takes the interrupts that come inside the transport's XCHG (the engine adds them to
`irqCnt`), so a frame that the network makes longer than an interrupt period costs the game a whole period. With the patch
at 4044h (`isrEnd`), when an interrupt went by inside XCHG the next frame runs as soon as this one ends (one at most:
the engine's `PN_AGAIN`, `G_CATCHUP` 2). Interrupts that the game's own work makes it miss are still dropped, as on the
cartridge. Only the pace changes, never what a frame computes, so the machines stay in lockstep.

The MSXPi transport takes no interrupts (XCHG returns E = 0), so nothing changes on the MSXPi path. Catching up the
interrupts the handler saw during PN_TICK as well (`G_CATCHUP` 1, like Bubble Bobble's own catch-up) made the MSXPi pair slower (30.0 to 29.1, 29.0 to 27.3) for the same TCP/IP gain (23.9).

Measured in openMSX (Canon V-25 pairs, 50 ms lag, 8% loss, 20 ms jitter, 3001 frames identical on both machines,
frames 600-2400, frames a second):

| Pair | Before | After |
|---|---|---|
| MSXPi + MSXPi | 30.0, 29.0 (two runs) | unchanged (same code path) |
| MSXPi + TCP/IP (`SCENARIO=mixed`) | 19.9 | 23.5 |

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
