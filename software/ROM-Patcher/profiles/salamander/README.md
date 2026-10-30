# Konami's Salamander online co-op package

Package format `msxpi-rom-patch` version 2 with the `msxpi-netplay-v1` ABI and image host `mapper-ram`. The analysis behind every patch
is in `documents/SALAMANDER-DESIGN.md`.

| | |
|---|---|
| Input | `SALAMAND.ROM`, Konami's Salamander (RC-758), 131072 bytes, Konami SCC MegaROM, CRC-32 `C36F559D`, SHA-256 `edbbba820ac67d6a55b9dc5da9309e45979936d5620c07d09793efaf077e86b9` |
| Output | a RAM image in mapper segments for PLAYNET (`output.target = "ram-image"`), never a ROM file |
| Game id, roles | `salamand`; `P1` (seat 0, the inviter, Vic Viper), `P2` (seat 1, Lord British) |
| Play | the game's DUALPLAY, both players at once; each uses joystick 1 or the cursor keys and space on their own machine |
| Layout for PLAYNET | transport D000h-D1FFh (first: on the TCP/IP path it is also in MSX-DOS's page 3), stub D200h-D8FFh (engine, 8 KB bank engine, glue), the bank engine's pair map DA00h-DDFFh, game RAM C000h-CFFFh and E000h-F0F8h, interrupt handler 4069h |
| Machine | a memory mapper with at least 22 free segments (512 KB recommended) |

No ROM data is included. The player supplies their own dump.

## Status

- Playable over the MSXPi with PLAYNET 3, from MCHAT (`/play NICK salamand`) to the game and back: verified in openMSX (two Canon
  V-25 with a memory mapper, MSX-DOS 1 from the MSXPi), the machines identical frame by frame (a 2 MB and a 512 KB mapper).
  Published as `software/target/games/SALAMAND.GPF`. The stub is 1589 of 1792 bytes; 78 patches, all matching the dump.
- Speed: about 28 frames/s in steady play against the cartridge's 31 (1PLAYER, same scenes); lighter scenes at the cartridge's.
- Over TCP/IP (`PLAYNET /T`, MCHAT /T): loads and connects in openMSX up to the connection, not played to the end yet.

## Frame catch-up: not added

The frame catch-up of Soccer, Yie Ar and Ping Pong (the busy flag's clear at 40BEh -> `isrEnd`, `G_CATCHUP`) is not in
this package yet. It makes the GPF 2920 bytes, and before PLAYNET's fix (its bounce buffer at 3500h, inside the 3 KB GPF
buffer; now at 3600h) the stub's last 13 bytes, the new code, came out as an MSXPi reply and the game stopped after
frame 0. With the fixed PLAYNET it plays (1501 identical frames, the stub intact in RAM); its speed is not measured yet.

## Files

| File | |
|---|---|
| `src/glue.asm` | the game's side: inputs, sound tick, `ld a,r`, the cartridge probe |
| `src/playnet_engine.asm`, `src/mapper_k8.asm` | copied by `rebuild.py` from `software/Client/src/playnet/engine/` |
| `rebuild.py` | assembles the stub, generates the patches, writes `profile.json`; `--rom` checks them against a dump |
| `assets/stub.bin`, `profile.json` | generated |

## Rebuild (developers)

```console
python profiles/salamander/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\path\to\SALAMAND.ROM
```
