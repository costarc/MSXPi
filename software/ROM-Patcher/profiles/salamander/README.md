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
  Published as `software/target/games/SALAMAND.GPF`. The stub is 1731 of 1792 bytes; 79 patches, all matching the dump.
- Speed: about 28 frames/s in steady play against the cartridge's 31 (1PLAYER, same scenes); lighter scenes at the cartridge's.
- Over TCP/IP (`PLAYNET /T`): 3001 identical frames in openMSX, P1 over the MSXPi and P2 over TCP/IP on Nextor (`run_salamander.sh`
  with `TCP=1`). The chat route (MCHAT /T) is not played to the end yet.

## Frame catch-up

Every frame is one run of the H.KEYI handler, and an interrupt that comes while it runs is dropped (the busy flag E205h).
Over TCP/IP, MSX-DOS's own handler takes the interrupts that come inside the transport's XCHG (the engine adds them to
`irqCnt`), so a frame that the network makes longer than an interrupt period costs the game a whole period. With the patch
at 40BEh in bank 0 (`isrEnd`), when an interrupt went by inside XCHG the next frame runs as soon as this one ends (one at
most: the engine's `PN_AGAIN`, `G_CATCHUP` 2). Interrupts that the game's own work makes it miss are still dropped, as on
the cartridge. Only the pace changes, never what a frame computes, so the machines stay in lockstep. The MSXPi transport
takes no interrupts (XCHG returns E = 0), so nothing changes on the MSXPi path.

The GPF is 2917 bytes with it: it needs the PLAYNET that keeps its bounce buffer after the 3 KB GPF buffer (3600h). With
the older one (bounce buffer at 3500h) the stub's last bytes, this code, are overwritten and the game stops after frame 0.

Measured in openMSX (`run_salamander.sh` with `TCP=1`: P1 over the MSXPi, P2 over TCP/IP on Nextor; 50 ms lag, 8% loss,
20 ms jitter, 3001 frames identical on both machines, frames 600-2400, two runs each):

| Pair | Before | After |
|---|---|---|
| MSXPi + MSXPi | | unchanged (same code path) |
| MSXPi + TCP/IP | 17.5, 17.6 | 18.3, 18.4 |

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
