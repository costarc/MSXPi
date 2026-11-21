# PPoker

PPoker is a nine-seat no-limit Texas Hold'em tournament on SCREEN 5, built with
Fusion-C for any MSX2 (64 KB VRAM is enough). It is PChess's sibling: the same
MSXPi link code, the same VRAM tile cache and blitter, the same header/panel
look. The rules are not in here at all - the Pi deals every card, and this
program draws what its Pi sends back. `documents/POKER-TOURNAMENT.md` has the
protocol and the server side.

```text
PPOKER             play, using POKERNICK / POKERROOM / POKERRELAY from msxpi.ini
```

The first screen offers `J` join a table, `H` host a table and `N` set a
nickname; a host starts the relay its table answers on, and everyone else only
needs their Pi pointed at it with `POKERRELAY`.

## Keys

| Screen | Keys |
| --- | --- |
| Lobby | `J` join, `H` host, `N` nickname, `TAB` chat, `ESC` menu |
| Table | `F` fold, `C` check/call, `A` all in, `B` bet, `R` raise, `TAB` chat, `ESC` menu |
| Action menu | arrows move, `ENTER`/`SPACE` choose, or the letter above |
| Chat | `ENTER` sends (text is uppercased to what the font can draw), `ESC` closes |
| Nickname/amount prompts | type, `BACKSPACE` corrects, `ENTER` accepts, `ESC` cancels |

The table itself can be driven with `UP`/`DOWN` and `ENTER` on the action menu,
so the game is playable without remembering a key.

## The screen

```text
y=1    room, level, blinds, hand number, players left
y=10   nine seats in a 3x3 grid, each: nickname, stack, last action, bet, cards
y=85   pot
y=92   the board (five shared cards) and the dealer's message
y=132  your hole cards and hand name
x=194  panel: seat, stack, to call, minimum raise, action clock
y=174  the five actions, the selected one highlighted
y=205  the status line
```

Seats light their frame when they act, show `FOLD`, `ALLIN`, `-` for a
disconnected player and dim a stack of zero. Cards are drawn from 26x36 2bpp
tiles kept off screen: `software/tools/make_poker_cards.py` regenerates
`ppoker_cards.h` from David Bellot's vector deck (LGPL-2.1), building the suit
pips out of each ace and a 3x5 doubled rank font for the corners. The build uses
the committed header, so the deck is only needed to change the art.

Startup caches the 53 card tiles (13,356 bytes) and the 50-glyph font at VRAM
page 1 lines 256-496, then never reloads them; a refresh copies only the cells
whose card or character changed, exactly as PChess does with its board.

## Building

`make.bat ppoker` on the normal tree (Fusion-C at
`Dev/MSX/MSX-C/WorkingFolder/fusion-c`). By hand, from `software/`:

```text
python tools/build_fusion46.py C-common/lib --fusion-c <fusion-c>
sdcc -mz80 -c C-common/lib/msxpi-bios.c
sdar -rc C-common/lib/msxpi-bios.lib msxpi-bios.rel
sdcc --code-loc 0x106 --data-loc 0x0 --disable-warning 196 -mz80 --no-std-crt0 \
     --opt-code-size fusion46.lib C-common/lib/msxpi-bios.lib -L C-common/lib \
     <fusion-c>/include/crt0_msxdos.rel Client/src/ppoker.c
hex2bin -e com ppoker.ihx
```

The result is about 34 KB, ending below `0x8900`, well inside the TPA of every
disk in `software/Client/tests/pchess_memory_test.py` (`PPOKER.COM` is checked
there too).

## Tests

* `Server/Python/tests/test_poker.py` - the tournament rules, the packet and
  the relay (`python -m unittest tests.test_poker` from `Server/Python`).
* `Client/tests/poker_smoke_openmsx.py` - runs PPOKER.COM on an emulated Canon
  V-25 with no MSXPi: the lobby must draw, the join must fail with
  `NO MSXPI - CHECK THE INTERFACE` instead of hanging, and `ESC`/`EXIT TO DOS`
  must return to the prompt. It writes a PNG of every VRAM dump it takes.
* `Client/tests/poker_table_openmsx.py` - two emulated MSXPis on two servers:
  one hosts a room, the relay fills seats 2-8, the second joins as the ninth
  seat in the middle of a hand, and both act with `C`. It checks the drawn
  table (names, stacks, hole cards, board, hand name) and keeps the frames in
  their own folder under `work/ppoker-art/` (or `--art DIR`). `--ports A,B
  --relay-port N` (or `POKER_TEST_PORTS` / `POKER_TEST_RELAY_PORT`) replace
  the default ports 5071,5072 and 5090, so two runs can share one PC.
* `Client/tests/poker_champion_openmsx.py` - the same two MSXPis play a
  heads-up tournament to a champion (stack 60, fast blinds, both always all
  in) and check the end on the relay and as both MSXes draw it: the winner
  on the status line, `OVER` in the panel, the loser's seat `OUT`. Ports
  5075,5076 and relay 5092 by default, so it runs next to the table scene;
  the same `--ports`/`--relay-port`/`--art` options.
