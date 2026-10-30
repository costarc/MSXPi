# Konami's Ping Pong netplay package

Package format `msxpi-rom-patch` version 2 with the `msxpi-netplay-v1` ABI. Analysis: `documents/PINGPONG-NETPLAY.md`.
Modelled on the Soccer package (`../soccer/`) and the Yie Ar Kung-Fu one.

| | |
|---|---|
| Input | `PINGPONG.ROM`, Konami's Ping Pong (1985), 16384 bytes, CRC-32 `3F200491`, SHA-256 `8e0f57b2c52e85505505c1d4bb4643eb7311213676f0ecfe21dd06571fc0bbd5` |
| Output | a RAM image for PLAYNET (`output.target = "ram-image"`), never a ROM file |
| Game id, roles | `pingpong`; `P1` (seat 0, the inviter), `P2` (seat 1) |
| Layout for PLAYNET | the ROM at 4000h-7FFFh, stub C100h, transport C500h, game RAM E000h-E4FFh, interrupt handler 4019h |
| Machine | any MSX with 64 KB (no memory mapper needed on the MSXPi path) |

No ROM data is included. The player supplies their own dump.

## What it does

The ROM already has the 2 PLAYERS mode, with both pads read once per interrupt, so nothing is added to the game: the
inviter plays the pad of player 1, the guest the pad of player 2, and the two machines run the whole game in lockstep.
The title menu is read from player 1's pad only, and both menu entries start the 2 player game (there is nobody to play
against but the other person). 12 patches: two anti-copy self-writes, H.KEYI, the two sound ticks, the TICK site, the
four pad reads (player 1, player 2, and the two menu readers), the menu's mode store, and the frame catch-up (below).

## Frame catch-up

Every frame is one run of the H.KEYI handler, and an interrupt that comes while it runs is dropped (the busy flag E005h).
Over TCP/IP, MSX-DOS's own handler takes the interrupts that come inside the transport's XCHG (the engine adds them to
`irqCnt`), so a frame that the network makes longer than an interrupt period costs the game a whole period. With the patch
at 4040h (`isrEnd`), when an interrupt went by inside XCHG the next frame runs as soon as this one ends (one at most:
the engine's `PN_AGAIN`, `G_CATCHUP` 2). Interrupts that the game's own work makes it miss are still dropped, as on the
cartridge. Only the pace changes, never what a frame computes, so the machines stay in lockstep.

The MSXPi transport takes no interrupts (XCHG returns E = 0), so nothing changes on the MSXPi path. Catching up the
interrupts the handler saw during PN_TICK as well (`G_CATCHUP` 1, like Bubble Bobble's own catch-up) gained less over TCP/IP (32.3) and nothing on the MSXPi pair (37.0).

Measured in openMSX (Canon V-25 pairs, 50 ms lag, 8% loss, 20 ms jitter, 3001 frames identical on both machines,
frames 600-2400, frames a second):

| Pair | Before | After |
|---|---|---|
| MSXPi + MSXPi | 37.1 | unchanged (same code path) |
| MSXPi + TCP/IP (`SCENARIO=mixed`) | 30.9 | 34.0 |

## Rebuild (developers)

```console
python profiles/pingpong/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\path\to\PINGPONG.ROM
```
`--rom` also checks every patch's expected bytes against the dump. `--syms F.tcl` writes the stub's symbols for the rig.
`--test-gpf T.GPF --test-syms T.tcl` builds the scripted-input variant for `software/Client/tests/soccernet/run_pingpong.sh`.
