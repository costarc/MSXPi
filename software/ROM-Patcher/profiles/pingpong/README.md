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
against but the other person). 11 patches: two anti-copy self-writes, H.KEYI, the two sound ticks, the TICK site, the
four pad reads (player 1, player 2, and the two menu readers), and the menu's mode store.

## Rebuild (developers)

```console
python profiles/pingpong/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\path\to\PINGPONG.ROM
```
`--rom` also checks every patch's expected bytes against the dump. `--syms F.tcl` writes the stub's symbols for the rig.
`--test-gpf T.GPF --test-syms T.tcl` builds the scripted-input variant for `software/Client/tests/soccernet/run_pingpong.sh`.
