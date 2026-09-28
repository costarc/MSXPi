# PChess

PChess uses SCREEN 8 and Fusion-C on an MSX2 with 128 KB VRAM. Pieces are
graphical silhouettes. The MSXPi server validates all moves using the optional
`chess` Python package; local two-player mode also requires the server.

Pieces and glyphs are cached in off-screen VRAM at startup. Refresh uses
Fusion-C's assembly HMMM VDP blitter; only changed squares and characters
are copied. The board/panel is not cleared during moves or network polls.
A normal-speed Panasonic OpenMSX cursor test measured completion within
34 emulated milliseconds (VRAM polling at 1 ms intervals).

Install `Server/Python/src/requirements-pchess.txt` with the server's Python.
Rules include check, mate, stalemate, castling, en passant and underpromotion.
Claimable draws are automatically accepted. The built-in two-ply AI is a
simple opponent, not Stockfish. The optional Python package is licensed
GPL-3.0-or-later; the MSX executable does not link it.

Build from `software` with:

```bat
make.bat pchess
```

This produces `target\pchess.com` and copies it to the configured FloppyA
directory. Use Panasonic_FS-A1WSX, MSXPi, ram4mb, and mount
`C:/Users/roniv/Dev/MSX/MSXPi/FloppyA` using `diska`. Inside MSX-DOS, switch
to **C:**, then run `PCHESS`.

Controls:

- `1`: local two-player; `2`: play white against the server AI.
- `4`: connect to IRC and join #msxpi; `5`: announce availability.
- `6`, nickname, Return: privately invite an opponent; `7`: accept an invite.
- Arrows or joystick port 1 move the cursor. Space, Return or joystick A
  selects source/destination. Cursor promotions choose a queen.
- Type UCI (`e2e4`, `a7a8n`) or SAN (`Nf3`, `O-O`) and press Return.
- Backspace edits notation; Escape returns to DOS.

IRC settings and the public-discovery/private-game protocol are documented
in `software/docs/PCHESS-IRC.md`. Both servers must use the same IRC network.
Games are in memory; reconnect/resume, clocks and Lichess integration are
not implemented. An IRC connection failure is displayed on the status line.

An alternative dedicated room relay is available using `3`: run
`python msxpi_pchess.py --listen 0.0.0.0 --port 5080`, set
`PCHESS_RELAY_URL=http://HOST:5080` on each MSXPi server, and enter the same
room name on both clients. Use a private LAN or protected tunnel; this
simple HTTP relay is intended for trusted networks. First player is white.

Tests: `test_pchess.py` and `test_pchess_irc.py` under `Server/Python/tests`.
Run `pchess_dual.py --irc` with Windows Python for two OpenMSX instances,
two MSXPi servers on ports 5041/5042 and a local IRC fixture on 5081.
The harness switches each DOS session to C:, sends e4/e5 and checks both
boards. Test logs/screenshots are in a fresh `work/pchess-dual-*` directory.
Only processes created by that harness are terminated during cleanup.
