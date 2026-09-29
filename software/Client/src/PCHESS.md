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
Claimable draws are automatically accepted.

The AI opponent (`2`) is Stockfish when it is installed on the server
(`sudo apt install stockfish`; the setup script does this). msxpi.ini:

```text
var PCHESSENGINE=        # Stockfish path; empty = find it (PATH, /usr/games)
var PCHESSELO=800        # approximate playing strength
var PCHESSMOVETIME=1     # seconds of thinking per move
```

Stockfish's rating limit starts at about 1320; below that PChess uses its
weakest skill level with a shallow search, so low ratings such as the 800
default are approximate. Without Stockfish, or if it fails, a much weaker
built-in two-ply search plays. Stockfish and python-chess are GPL-3.0; they
run as separate programs on the server and the MSX executable links neither.

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
- `4 ONLINE`: connect to IRC and join #msxpi; `5`: announce availability.
- `6`, nickname, Return: privately invite an opponent; `7`: accept an invite.
- Arrows or joystick port 1 move the cursor. Space, Return or joystick A
  selects source/destination. Cursor promotions choose a queen.
  Direction events are rate-limited to one per eight jiffies (133–160 ms)
  to suppress rapid repeats; the first direction is immediate.
- Type UCI (`e2e4`, `a7a8n`) or SAN (`Nf3`, `O-O`) and press Return.
- Backspace edits notation.
- Escape opens the menu: Up/Down pick a row. On `AI LEVEL`, Left/Right
  choose 1-8 and Return saves it (`pchess level N` sets PCHESSELO in
  msxpi.ini: 600, 800, 1000, 1350, 1600, 1900, 2200, 2500). `EXIT`
  returns to DOS; Escape resumes the game.

IRC settings and the public-discovery/private-game protocol are documented
in `software/docs/PCHESS-IRC.md`. Both servers must use the same IRC network.
Games are in memory; reconnect/resume, clocks and Lichess integration are
not implemented. An IRC connection failure is displayed on the status line.

ROOM mode (`3`) uses a small HTTP relay built into the MSXPi server. Choosing
`3` starts it on `PCHESSLISTEN:PCHESSPORT` (msxpi.ini, default `0.0.0.0:5080`,
reachable from the LAN); choosing any other mode stops it. `PCHESSRELAY`
selects the relay both players share: leave it empty on the hosting MSXPi,
and set it to `http://HOST_IP:5080` on the other one. Both players enter the
same room name; the first to join is white. The relay is plain HTTP for
trusted networks. `python msxpi_pchess.py --listen 0.0.0.0 --port 5080`
still runs a standalone relay on a third machine.

Tests: `test_pchess.py` and `test_pchess_irc.py` under `Server/Python/tests`.
Run `pchess_dual.py --irc` with Windows Python for two OpenMSX instances,
two MSXPi servers on ports 5041/5042 and a local IRC fixture on 5081.
The harness switches each DOS session to C:, sends e4/e5 and checks both
boards. Test logs/screenshots are in a fresh `work/pchess-dual-*` directory.
Only processes created by that harness are terminated during cleanup.
