# PLAYNET - online two-player games for MSX (MSX side)

Specification and integration guide: `documents/PLAYNET-PROTOCOLS.md`. Design: `documents/PLAYNET-DESIGN.md`.

| File | Purpose |
|---|---|
| `playnet.asm` | `PLAYNET.COM`, the loader (MSXPi path): session and game package from the MSXPi, ROM check (CRC-32), image and patches (every expected byte checked), connect, install, start |
| `engine/playnet_engine.asm` | the shared lockstep engine (stub ABI 1). Each game's package assembles it with its own glue (`software/ROM-Patcher/profiles/<game>/src/glue.asm`) |
| `transport_msxpi.asm` | the MSXPi transport (`XCHG`, `XEND`, `XIRQ` over opcode C9), installed by the loader at the game's `transport_area` |
| `c9link.asm` | polled byte transfer on the MSXPi link, shared by the loader and the transport |
| `build.py` | builds `build/PLAYNET.COM`; assembles the transport at two origins to derive its relocation table (`build/transport_msxpi.inc`) |

```console
python build.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe
```

Usage on the MSX:

```
PLAYNET                  the game MCHAT prepared (MCHAT types this itself)
PLAYNET <game> <role>    without the chat, when the MSXPi's netplay session is set up by other means (test rigs)
```

Status: MSXPi path only. TCP/IP UNAPI (`PLAYNET /T`, the network engine in a mapper segment) is implementation step 7.
The engine supports 1-4 input bytes per frame; only 1 (Konami's Soccer) has run.

Test: `software/Client/tests/soccernet/run_native.sh` (two openMSX, two MSXPi servers; `SCENARIO=chat` through MCHAT;
`RENDERER=SDLGL-PP` to watch, `RECORD=file.wav` to record node H's sound).
