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

## Oval table: feasibility

Whether the table can be the X68000 Poker Tournament's oval instead of the 3x3
grid. The prototype is in `ppoker.c` behind `-DOVAL_TABLE` (`OVAL=1` in
`make.bat ppoker`); the default build and `target/ppoker.com` are untouched, so
players still get the grid. The screenshots from the openMSX table scene are
`documents/PPOKER-OVAL-TABLE-1.png` (seat 1) and `-2.png` (seat 9, whose pod is
the bottom one).

### The model and the third

`code/poker/src/ui_x68k.c` of the X68000 book (branch `thread/poker`) draws a
768x512 screen: table centre (384,236); four ellipses 334x158, 326x150, 306x130
and 300x124; nine pods of 156x44 at

    (384,376) (191,343) (89,260) (124,166) (281,104)
    (487,104) (644,166) (679,260) (577,343)

clockwise from the bottom one, the player's own pod always the bottom one and
the others rotated with it; the pot above the board; the board in a strip at
x 234..535, y 148..230.

256x212 is a third of that screen, so the plan below is those numbers divided by
three and clamped to the edges - a re-design of the same idea, not a port.

### The pixel plan (256x212)

| what | where |
| --- | --- |
| header | y=1, one line, unchanged |
| oval | centre (128,88); rings 112x56 (rail, grey), 110x54 (rim), 106x50 (felt): the table spans x 16..240, y 32..144 |
| nine pods | 52x16, clockwise from the bottom, top left corner x,y: mine (102,132), then (29,120), (0,89), (0,54), (63,31), (141,31), (201,54), (204,89), (175,120) |
| pot | `POT n` at (107,44) |
| board | five 26x36 cards at x 63+28i, y 54, so x 63..201, y 54..90 |
| own cards | two 26x36 cards at x 102+28i, y 96, so x 102..156, y 96..132 |
| my stack, hand name | one line each at (36,96) and (36,106), beside the cards |
| panel | one row at y=9: `SEAT n STK n CALL n MIN n` from x 0, `POT n`, the clock and `OVER` from x 202 |
| actions | y 174, 183, 192, unchanged |
| status | y 205, unchanged |

The rotation is the prototype's: pod `pos` shows seat `(pos + seat - 1) % 9`, so
your pod is always the bottom one, gold framed.

### What a pod can show

- Line 1 is `n NICK`: the seat digit, a space and six letters of nickname -
  seven characters, 46 pixels, the pod is 52 wide and the glyphs are 6. Your own
  pod has a `>` after the digit, so it gets five. Today's seat cell is 58 pixels,
  nine characters ("9 BOT7").
- Line 2 is the stack and then either a bet (`1460+20`) or one letter: `W`
  waiting, `F` folded, `A` all in, `D` disconnected, `OUT` for a stack of zero.
  The grid spells WAIT, FOLD, ALL, DISC in a column.
- The frame carries the state: gold yours, yellow the player on the clock.

### What shrinks or moves, with numbers

- The panel is the big loss: its 62x56 column at x 194..255, y 12..68 is where
  pods 7 and 8 now sit, so eight rows become one 42-column line at y=9. Every
  field stays (seat, stack, call, minimum raise, pot, clock, `OVER`); none gets
  a second line.
- Text on the felt: the glyph tiles are 6x7 with a black background, so every
  string paints a black patch - 46x10 for the pot, 62x20 for stack and hand name,
  252x7 for the panel row. A transparent text mode needs a second 50-glyph set
  (50 x 42 bytes = 2,100 bytes of VRAM) and a VDP copy with the transparent
  logical op; it is not in the prototype.
- Your cards keep their 26x36 tiles but move to the middle of the felt, so the
  stack and the hand name are one line each beside them instead of three lines
  under them; `OVER` moved to the panel row.
- The board keeps its card size. At y=54 the felt has narrowed to about 70
  pixels either side of centre, so the two outer cards overhang the felt onto the
  rim ring - still table, not background.
- Nothing is dropped from today's screen: seat, nick, stack, action, my cards,
  hand name, pot, board, level, hand number, players, actions, clock, status.

### Measured drawing cost

The prototype has a bench behind `-DOVAL_TIMING` (`TIMING=1` in `make.bat`): it
draws a full table ten times and prints two counts on the status line, the oval
alone from scratch and a whole redraw with the oval already there. A jiffy is
20 ms. Canon V-25 profile in openMSX, the machine the other scenes use.

| build | what | 10 draws | one draw |
| --- | --- | --- | --- |
| grid (today) | full redraw | 125 jiffies | 12.5 jiffies = 250 ms |
| oval | the oval alone, from scratch | 1,487 jiffies | 148.7 jiffies = 2.97 s |
| oval | full redraw, oval already on screen | 117 jiffies | 11.7 jiffies = 234 ms |

- The oval is 323 LMMV row fills (113 + 109 + 101 for the three rings), so a row
  costs about 9 ms: one VDP command per row, set up by the Z80 through Fusion-C.
  Any row-wise drawing costs the same, and on the X68000 four ellipses are 1,268
  line calls and 1.1 s on a 10 MHz 68000, so the shape is not what is expensive.
- The per-action redraw is 234 ms against today's 250 ms: it fits in one poll
  period (60 jiffies = 1.2 s) and is as cheap as the grid's. Most of that budget
  is the pods, and only when they change - redrawing all nine every poll was
  442 ms until each pod remembered its two lines.
- The oval has to be drawn once when the table is first shown, not per redraw:
  2.97 s of a table appearing, and again after every popup, because the popup
  overwrites it. It cannot be cached off screen and restored with one HMMM: the
  visible screen is 212 of the 256 lines (27,136 of 32,768 bytes) and the card
  cache and the font live from line 256 on, so the free run is lines 212-255 =
  5,632 bytes, while the oval's bounding box is 224x112 = 12,544 bytes.
- The table scene's checks still look at 3x3 coordinates, so they fail against
  the prototype (seats, panel, hand name); the frames are what it produces, and
  it does produce them. Teaching the scene the oval's coordinates belongs to the
  card that switches the default.

### Recommendation

**Adopt, with the compromises above.** The compromises are real but small: one
line of panel instead of eight, six letters of nickname, one-letter action
flags, and black patches behind the text on the felt. The price is a single 3 s
draw when a table appears, because the per-action redraw is already as cheap as
the grid's (234 ms against 250 ms). That 3 s is the only thing that argues for
keeping the grid. If Roni wants it, the next card makes `-DOVAL_TABLE` the
default, teaches `poker_table_openmsx.py` the oval's coordinates and draws the
oval once per table (which the prototype already does).

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

Two switches build the alternatives: `OVAL=1` adds `-DOVAL_TABLE` (the
oval table of the section above) and `TIMING=1` adds `-DOVAL_TIMING` (the
oval bench, which prints its jiffy counts at y=205 and waits for a key).
Both take effect as `set "OVAL=1"` before `make.bat ppoker`; the default
build is unchanged and still matches the committed `target/ppoker.com`
byte for byte.

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
