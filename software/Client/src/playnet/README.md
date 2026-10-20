# PLAYNET - online two-player games for MSX (MSX side)

Specification and integration guide: `documents/PLAYNET-PROTOCOLS.md`. Design: `documents/PLAYNET-DESIGN.md`.

| File | Purpose |
|---|---|
| `playnet.asm` | `PLAYNET.COM`, the loader: session and game package (from the MSXPi, or `ID.GPF` with `/T`), ROM check (CRC-32), image and patches (every expected byte checked), connect, install, start, and the way back to MSX-DOS |
| `playnet_tcp.asm` | `PLAYNET /T`: mapper segments, `PLAYNET.OVL`, the connect phase through it, the UNAPI transport's fields |
| `netcore/` | netcore, the MSXNP engine in portable C (`netcore.c`), its MSX side (`ovl_main.c`, `ovl_crt0.s`: `PLAYNET.OVL`) and its PC side for the conformance test (`host/netcore_host.c`) |
| `transport_unapi.asm` | the TCP/IP UNAPI transport: the game's own page 3, the switch back to MSX-DOS's for each call |
| `engine/playnet_engine.asm` | the shared lockstep engine (stub ABI 1). Each game's package assembles it with its own glue (`software/ROM-Patcher/profiles/<game>/src/glue.asm`) |
| `transport_msxpi.asm` | the MSXPi transport (`XCHG`, `XEND`, `XIRQ` over opcode C9), installed by the loader at the game's `transport_area` |
| `c9link.asm` | polled byte transfer on the MSXPi link, shared by the loader and the transport |
| `build.py` | builds `build/PLAYNET.COM` and `build/PLAYNET.OVL` (SDCC); assembles each transport at two origins to derive its relocation table |

```console
python build.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe
```

Usage on the MSX:

```
PLAYNET                  the game MCHAT prepared (MCHAT types this itself)
PLAYNET <game> <role>    without the chat, when the MSXPi's netplay session is set up by other means (test rigs)
PLAYNET /T               the game MCHAT /T prepared (PLAYNET.SES; MCHAT /T types this itself, and PLAYNET types
                         MCHAT /T when the game ends)
PLAYNET /T <game> <role> <port> <ip:port>[,<ip:port>]
                         over TCP/IP UNAPI (InterNestor Lite...) without the chat. Both /T forms need a memory mapper,
                         PLAYNET.OVL and GAME.GPF in the current directory
```

Status: the MSXPi path, and TCP/IP UNAPI from MCHAT /T or started by hand. Both are tested with InterNestor Lite on MSX-DOS 1
with MSR, in openMSX.
The engine supports 1-4 input bytes per frame; only 1 (Konami's Soccer) has run.

Test: `software/Client/tests/soccernet/run_native.sh` (two openMSX, two MSXPi servers; `SCENARIO=chat` through MCHAT;
`RENDERER=SDLGL-PP` to watch, `RECORD=file.wav` to record node H's sound; `SCENARIO=mixed` for an InterNestor Lite node, `BOTH=1`
for two; `EXITKEY=n` for the way back). Conformance of netcore: `Server/Python/tests/test_netcore.py` (gcc, WSL on Windows).
