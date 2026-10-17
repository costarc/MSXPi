# PCheckers (DAMAS)

Brazilian draughts on the 8x8 board for the MSX2 and later, built from the
PChess client (`pchess.c`). The chess engine is replaced by a checkers engine
that runs on the MSX itself, so the game needs no MSXPi server or network.

Build: `software\make.bat pcheckers` (from `software`), then run `PCHECKERS`
in MSX-DOS. It needs an MSX2 (SCREEN 5, 64 KB VRAM is enough).

## Rules (Brazilian draughts)

* 12 pieces each on the dark squares; white (bottom) moves first.
* Men move one square diagonally forward and capture forward or backward.
* Kings ("damas") move and capture any distance along a diagonal.
* Capturing is mandatory and the capture taking the most pieces must be
  played. Captured pieces are removed after the whole move and cannot be
  jumped twice. A man passing through the last row while capturing stays a
  man; one that ends its move there is crowned.
* A side with no legal move loses. 20 moves by each side with only king
  moves and no capture is a draw.

## Controls

| Key | Action |
|-----|--------|
| Arrows / joystick | Move the cursor |
| Space / Return / fire | Select a piece, then a destination |
| 1 | New two-player game |
| 2 / 3 | New game against the AI, you as white / black |
| ESC | Menu: AI level, offer draw, resign, rotate board, credits, exit |

Green dots show where the selected piece can go. A capture that has several
routes is entered one landing square at a time (the status line says
CONTINUE THE CAPTURE); when only one legal move still fits, it is played.

The AI searches level+1 plies (levels 1-6, default 2). Thinking time on a
3.58 MHz Z80 grows quickly with the level: about 2-7 s at level 2, roughly
8 s on average (more in busy middlegames) at level 3, and minutes at 5-6.
The AI accepts a draw offer when it is not ahead.

## Files

* `pcheckers.c` - screen, input, menu (from `pchess.c`).
* `pcheckers_rules.c` - rules, move generation and AI; plain C, no MSX code.
* `../tests/pcheckers_rules_test.py` - builds `pcheckers_rules_host.c` with
  sdcc for the Z80 and runs it in the `sz80` simulator: opening perft
  7/49/302/1469, majority capture, flying king, backward capture, crowning.

Not carried over from PChess: online/room play, IRC, the TCP/IP link and
typed move entry.
