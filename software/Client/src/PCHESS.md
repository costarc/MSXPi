# PChess

PChess uses SCREEN 5 and Fusion-C on any MSX2 (64 KB VRAM is enough). Pieces are
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

Files A-H are labelled above the board and ranks 1-8 to its left; they
follow the board when it is rotated. The PSG beeps twice when the opponent
offers a draw, plays a rising tune when you win and a falling one when you
lose (in local two-player any win plays the rising tune).

Controls:

- `1`: local two-player; `2`: play white against the server AI.
- `4 ONLINE`: connect to IRC and join #msxpi; `5`: announce availability.
- `6`, nickname, Return: privately invite an opponent; `7`: accept an invite.
- `8 PLAYERS`: list players who seeked or invited you in the last ten
  minutes (up to seven, newest first); Up/Down and Return invite one.
- Once matched (lobby, room or AI), the panel shows your colour (`AS
  WHITE`/`AS BLACK`; PChess1: `YOU ARE WHITE` and `VS <nick>`), and the
  lobby/room status reads e.g. `YOU ARE BLACK - chp1 MOVES`. Black sees
  the board rotated, with its own pieces at the bottom; the cursor moves as
  shown on screen and typed moves (`e7e5`) are unchanged. `ROTATE BOARD`
  in the ESC menu turns the board over at any time, in any mode.
- While online (after `3` ROOM or `4` ONLINE), keys `1`-`4` first ask
  `LEAVE ONLINE GAME? Y/N`: any key but `Y` keeps the current game.
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
- `OFFER DRAW` (ESC menu): in local play the game is drawn at once. The AI
  accepts unless it is ahead by more than half a pawn (Stockfish's
  evaluation, or material without Stockfish), otherwise the status reads
  `AI DECLINES THE DRAW`. Online (room or lobby) you offer on your move;
  the opponent sees `OPPONENT OFFERS DRAW - ESC MENU` and accepts with
  `OFFER DRAW`, or declines by moving. `RESIGN` asks `RESIGN? Y/N`; in
  local play the side to move resigns. Both ask Y/N first.

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

## PChess1 (MSX1)

`pchess1.c` is the MSX1 (TMS9918, 16 KB VRAM) version with the same server
protocol, modes and controls. It uses SCREEN 2 as a tile screen: the same
256 characters are loaded into all three pattern/colour banks, so refreshes
only write name-table bytes. Squares are 16x16 (the pchess pieces scaled to
two thirds) and text uses the BIOS 8x8 font, copied from SCREEN 1 at start.
Because SCREEN 2 allows two colours per 8 pixels, pieces have no outline,
and the cursor (red) and selection (green) are hardware sprites.

Build with `make.bat pchess1`; it produces `target\pchess1.com`.
