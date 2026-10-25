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

Single, the play-mode screen (state 9), Turn and a first Versus are built: 12 patches, stub 804 bytes at C100h, extension 662
bytes at A000h, GPF 1830 bytes (`software/target/games/YIEAR.GPF`). The two-emulator rig (`run_yiear.sh`) keeps both machines identical
in every mode. What is still open (the Versus move set, the chat and TCP/IP scenarios, sound and speed checks) is listed in
`documents/HANDOVER-yiear.md`; where the code differs from the design, `documents/YIEAR-DESIGN.md` section 14 says how.

## Rebuild (developers)

```console
python profiles/yiear/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\path\to\kung-fu.rom
```
`--rom` also checks every patch's expected bytes against the dump. `--syms F.tcl` writes the stub's symbols for the rig.
`--test-gpf T.GPF --test-syms T.tcl` builds the scripted-input variant for `run_yiear.sh`.
