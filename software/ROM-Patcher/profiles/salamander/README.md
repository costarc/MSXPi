# Konami's Salamander online co-op package

Package format `msxpi-rom-patch` version 2 with the `msxpi-netplay-v1` ABI and image host `mapper-ram`. The analysis behind every patch
is in `documents/SALAMANDER-DESIGN.md`.

| | |
|---|---|
| Input | `SALAMAND.ROM`, Konami's Salamander (RC-758), 131072 bytes, Konami SCC MegaROM, CRC-32 `C36F559D`, SHA-256 `edbbba820ac67d6a55b9dc5da9309e45979936d5620c07d09793efaf077e86b9` |
| Output | a RAM image in mapper segments for PLAYNET (`output.target = "ram-image"`), never a ROM file |
| Game id, roles | `salamander`; `P1` (seat 0, the inviter, Vic Viper), `P2` (seat 1, Lord British) |
| Play | the game's DUALPLAY, both players at once; each uses joystick 1 or the cursor keys and space on their own machine |
| Layout for PLAYNET | stub D000h-D5FFh (engine, 8 KB bank engine, glue), transport D600h-D7FFh, game RAM C000h-CFFFh and E000h-F0F8h, interrupt handler 4069h |
| Machine | a memory mapper with at least 22 free segments (512 KB recommended) |

No ROM data is included. The player supplies their own dump.

## Status

- Analysis done in openMSX with the real cartridge. The stub assembles (1393 of 1536 bytes), and the 77 patches match the dump.
- **Not runnable yet**: PLAYNET release 3 (the mapper-RAM host, design section 9) and `patch_rom.py` support for `mapper-ram` do not
  exist. Until they do, `rebuild.py` writes `profile.json` and the stub but no GPF.

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
