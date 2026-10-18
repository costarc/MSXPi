# SOCCERNET - Konami's Soccer over the network (work in progress)

Two MSX play Konami's Soccer (RC-732, 32 KB MSX1 ROM) against each other. Lockstep: both machines run the
whole game and exchange only the two joystick bytes per frame. The ROM is never distributed or modified on
disk: `SOCCERNET.COM` reads the user's own `SOCCER.ROM`, verifies it (Fletcher-16, see `rom_check.py`), copies
it to RAM 4000h-BFFFh, patches the RAM copy and installs a small stub at F000h. Design, findings and test
history: `documents/SOCCERNET-NETPLAY.md`.

| File | Purpose |
|---|---|
| `soccernet.asm` | DOS-phase loader and the patch table (addresses of one exact ROM dump) |
| `stub.tmpl.asm` | resident stub: lockstep engine, MSXPi-native transport (`-DNATIVE`), handshake, desync check |
| `gen_stub.py`, `gen_inc.py` | generate `stub.asm` (scripted-input tables for tests) and the symbol include for the loader |
| `rom_check.py` | prints the ROM hash and the loader's check values |
| `udptest.asm`, `unapi.tmpl.inc` | UNAPI TCP/IP UDP path (second backend, for GR8NET/ObsoNET/...): the test program uses the standard dispatch; `unapi.tmpl.inc` has **not** been ported to it yet |

Transport: one MSXPi opcode (C9) per poll, served by `msxpi_netplay.py` on the Pi/PC, which does the UDP, the
handshake (version, round trip, input delay) and dead-peer detection. See that file's header for the wire format.

Build (needs sjasmplus and Python 3): `SJASMPLUS=/path/to/sjasmplus sh build.sh` -> `build/SOCNAT.COM`
(scripted input, for the test rig) plus the mailbox-transport test variants. The real-joystick production
build has not been made or run yet. The stub must stay below F300h: the game's stack reaches F30Ch.

Test: `software/Server/Python/tests/test_netplay.py` (no emulator) and
`software/Client/tests/soccernet/run_native.sh` (two openMSX, needs your own `SOCCER.ROM`).

Status: scripted-input matches verified in openMSX only; nothing has run on real hardware.
