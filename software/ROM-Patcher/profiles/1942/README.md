# Capcom's 1942 (ASCII) online, turn based

Package format `msxpi-rom-patch` version 2 with the `msxpi-netplay-v1` ABI and image host `mapper-ram` (mapper type `ascii8`).
The analysis behind every patch is in `documents/1942-DESIGN.md`.

| | |
|---|---|
| Input | `1942.ROM`, ASCII's 1942 for the MSX, 131072 bytes, ASCII8 MegaROM, CRC-32 `C99E5601`, SHA-256 `d8442d2c08958f0bc9be7d2078e3cf07224e1ec3493ddce3215ed8df2bd37b1f` |
| Output | a RAM image in mapper segments for PLAYNET (`output.target = "ram-image"`), never a ROM file |
| Game id, roles | `1942`; `P1` (seat 0, the inviter), `P2` (seat 1) |
| Play | the game's own 2 PLAYERS mode, which takes turns: one ship, and when it is shot down the other player takes the next life. Both machines run the game; the input is the active player's. The inviter picks the mode in the title menu. |
| Layout for PLAYNET | transport DD60h-DF5Fh, stub E018h-E5FFh (engine, 8 KB bank engine, glue), the bank engine's pair map E600h-E9FFh; game RAM C000h-DD5Fh, E000h-E016h and EA00h-F37Fh |
| Machine | a memory mapper with at least 20 free segments (512 KB recommended). MSXPi link only: the TCP/IP transports need to sit below the TPA top (D406h-D706h), and 1942 leaves no free RAM there. |

No ROM data is included. The player supplies their own dump.

## Frame catch-up: not added

A frame ends with `ei / halt` at 4871h; skipping the halt when an interrupt went by during the frame's PN_TICK (the
catch-up of Soccer, Yie Ar and Ping Pong) needs about 37 bytes of stub, and the stub has 5 left (1507 of 1512, between the
game's variables and the pair map). The catch-up that the other games use counts only the interrupts MSX-DOS takes inside
the TCP/IP transport, and 1942 plays over the MSXPi only, where that changes nothing.

## Files

| File | |
|---|---|
| `src/glue.asm` | the game's side: input routing by turn, INIT, `ld a,r` |
| `src/playnet_engine.asm`, `src/mapper_k8.asm` | copied by `rebuild.py` from `software/Client/src/playnet/engine/` |
| `rebuild.py` | assembles the stub, generates the patches, writes `profile.json`; `--rom` checks them against a dump |
| `assets/stub.bin`, `profile.json` | generated |

## Rebuild (developers)

```console
python profiles/1942/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\path\to\1942.ROM
```
