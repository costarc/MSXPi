# Konami's Yie Ar Kung-Fu netplay package

Package format `msxpi-rom-patch` version 2 with the `msxpi-netplay-v1` ABI. Design: `documents/YIEAR-DESIGN.md`; plan:
`documents/YIEAR-IMPLEMENTATION-PLAN.md`. Modelled on the Soccer package (`../soccer/`).

| | |
|---|---|
| Input | `KUNG-FU.ROM`, Konami's Yie Ar Kung-Fu (RC-725), 16384 bytes, CRC-32 `8A12EC4F`, SHA-256 `644c78c7d20bb30802888b513b384cf0ce4f9d8b6fd490f30e6211ac92274848` |
| Output | a RAM image for PLAYNET (`output.target = "ram-image"`), never a ROM file |
| Game id, roles | `yiear`; `P1` (seat 0, the inviter), `P2` (seat 1) |
| Layout for PLAYNET | the ROM at 4000h-7FFFh, stub C100h, transport C500h, game RAM E000h-E4FFh, interrupt handler 4043h |
| Machine | any MSX with 64 KB (no memory mapper needed on the MSXPi path) |

No ROM data is included. The player supplies their own dump.

## Status

Single mode only (step 3 of the plan): the second player watches. The five patches of design section 7 that need no extension:
H.KEYI (4019h), the two sound ticks (4047h, 4062h), the TICK site (4053h) and the second reader (4583h). The play-mode screen,
Turn and Versus (steps 4-7) are not written.

## Rebuild (developers)

```console
python profiles/yiear/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\path\to\kung-fu.rom
```
`--rom` also checks every patch's expected bytes against the dump. `--syms F.tcl` writes the stub's symbols for the rig.
`--test-gpf T.GPF --test-syms T.tcl` builds the scripted-input variant for `run_yiear.sh`.
