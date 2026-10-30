# Konami's Yie Ar Kung-Fu netplay package

Package format `msxpi-rom-patch` version 2 with the `msxpi-netplay-v1` ABI. Design: `documents/YIEAR-DESIGN.md`; plan:
`documents/YIEAR-IMPLEMENTATION-PLAN.md`. Modelled on the Soccer package (`../soccer/`).

| | |
|---|---|
| Input | `KUNGFU.ROM`, Konami's Yie Ar Kung-Fu (RC-725), 16384 bytes, CRC-32 `8A12EC4F`, SHA-256 `644c78c7d20bb30802888b513b384cf0ce4f9d8b6fd490f30e6211ac92274848` |
| Output | a RAM image for PLAYNET (`output.target = "ram-image"`), never a ROM file |
| Game id, roles | `yiear`; `P1` (seat 0, the inviter), `P2` (seat 1) |
| Layout for PLAYNET | the ROM at 4000h-7FFFh, the extension at A000h, stub C100h, transport C500h, game RAM E000h-E4FFh, interrupt handler 4043h |
| Machine | any MSX with 64 KB (no memory mapper needed on the MSXPi path) |

No ROM data is included. The player supplies their own dump.

## Status

Single, the play-mode screen (state 9), Turn and a first Versus are built: 13 patches, stub 842 bytes at C100h, extension 662
bytes at A000h, GPF 2106 bytes (`software/target/games/YIEAR.GPF`). The two-emulator rig (`run_yiear.sh`) keeps both machines identical
in every mode. What is still open (the Versus move set, the chat and TCP/IP scenarios, sound and speed checks) is listed in
`documents/HANDOVER-yiear.md`; where the code differs from the design, `documents/YIEAR-DESIGN.md` section 14 says how.

## Frame catch-up

Every frame is one run of the H.KEYI handler, and an interrupt that comes while it runs is dropped (the busy flag E006h).
Over TCP/IP, MSX-DOS's own handler takes the interrupts that come inside the transport's XCHG (the engine adds them to
`irqCnt`), so a frame that the network makes longer than an interrupt period costs the game a whole period. With the patch
at 4059h (`isrEnd`), when an interrupt went by inside XCHG the next frame runs as soon as this one ends (one at most:
the engine's `PN_AGAIN`, `G_CATCHUP` 2). Interrupts that the game's own work makes it miss are still dropped, as on the
cartridge. Only the pace changes, never what a frame computes, so the machines stay in lockstep.

The MSXPi transport takes no interrupts (XCHG returns E = 0), so nothing changes on the MSXPi path. Catching up the
interrupts the handler saw during PN_TICK as well (`G_CATCHUP` 1, like Bubble Bobble's own catch-up) gained less over TCP/IP (35.1) and nothing on the MSXPi pair (58.1).

Measured in openMSX (Canon V-25 pairs, 50 ms lag, 8% loss, 20 ms jitter, 3001 frames identical on both machines,
frames 600-2400, frames a second):

| Pair | Before | After |
|---|---|---|
| MSXPi + MSXPi | 58.3 | unchanged (same code path) |
| MSXPi + TCP/IP (`SCENARIO=mixed`) | 30.8 | 36.5 |

## Rebuild (developers)

```console
python profiles/yiear/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\path\to\kung-fu.rom
```
`--rom` also checks every patch's expected bytes against the dump. `--syms F.tcl` writes the stub's symbols for the rig.
`--test-gpf T.GPF --test-syms T.tcl` builds the scripted-input variant for `run_yiear.sh`.
