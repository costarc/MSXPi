# Penguin-kun Wars 2 (ASCII) online, versus

Package format `msxpi-rom-patch` version 2 with the `msxpi-netplay-v1` ABI and image host `mapper-ram` (mapper type `ascii16`).
The analysis behind every patch is in `documents/PWARS2-DESIGN.md` (kept locally, not in git).

| | |
|---|---|
| Input | `P-WARS2.ROM`, ASCII's Penguin-kun Wars 2 for the MSX2 (1988), 262144 bytes, ASCII16 MegaROM, CRC-32 `B1B24DA1`, SHA-256 `7815e5ac436521faeec24719d6edaaa820f07b8fb55ddafab4a0a08364cc766e` |
| Output | a RAM image in mapper segments for PLAYNET (`output.target = "ram-image"`), never a ROM file |
| Game id, roles | `pwars2`; `P1` (seat 0, the inviter), `P2` (seat 1) |
| Play | The cartridge is a one-player game: a series of matches against computer opponents. In this package player 1 plays the penguin and **player 2 takes over the computer opponent** of every match: walk left and right, the trigger picks up a ball in reach and throws the ball held. The opponents' own throws (power, curves) are kept. Menus, the character select, the map and the continue screen are player 1's. The pause key (F1) is disabled; MSX-MUSIC is not used (both machines play the PSG music). |
| Layout for PLAYNET | stub A630h-AC7Fh (page 2: the game's own RAM segment; engine, ASCII16 bank engine, glue), transport F100h-F2FFh; game RAM 8000h-A62Fh and AC80h-F0FFh |
| Machine | an MSX2 with a memory mapper of 512 KB (19 free segments: one per 16 KB bank, and page 2). Over an MSXPi (link 0) or a TCP/IP UNAPI (link 1, `PLAYNET /T`: the bridged UNAPI transport, which bounces the packets through the game's page 3 because the stub's buffers are in page 2). Not link 2 (`/H`): its transport area would have to be below MSX-DOS's TPA top, which the game owns. |

No ROM data is included. The player supplies their own dump.

## Files

| File | |
|---|---|
| `src/glue.asm` | the game's side: inputs and TICKs, the interrupt handler as the engine's sound tick, INIT, `ld a,r`, the bank-1 table, versus |
| `src/playnet_engine.asm`, `src/mapper_a16.asm` | copied by `rebuild.py` from `software/Client/src/playnet/engine/` |
| `rebuild.py` | assembles the stub, generates the patches, writes `profile.json`; `--rom` checks them against a dump; `--local-rom` builds a no-network test cartridge (player 2 on joystick 2) |
| `assets/stub.bin`, `profile.json` | generated |

## Rebuild (developers)

```console
python profiles/pwars2/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\path\to\P-WARS2.ROM
```
