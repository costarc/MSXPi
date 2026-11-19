# Poker Tournament (PPOKER)

A nine-seat no-limit Texas Hold'em tournament for MSXPi: one Pi hosts the table,
every other Pi forwards its player's commands to it, and each MSX draws the
table it is dealt. The rules, the cards and every chip move live on the host Pi;
a client cannot deal itself a card or bet chips it does not have.

## Why not PLAYNET

PLAYNET's link is a two-player lockstep channel: both sides run the same code and
exchange inputs so they see identical states. A nine-seat tournament is
server-authoritative - the dealer must keep hidden cards hidden, decide side pots
and expel a player who stops answering - which lockstep cannot express. PPOKER
therefore uses PLAYNET's *transport*, the MSXPi LINK2/C9 link the client already
speaks (`link_command`/`link_recv`, the same code as `transport_msxpi.asm` and
`c9link.asm`), and puts the shared state in one authoritative tournament on the
host Pi instead of in every MSX.

## Where things live

| File | What |
| --- | --- |
| `software/Client/src/ppoker.c` | MSX client (PChess-derived UI, SCREEN 5, Fusion-C) |
| `software/Server/Python/src/msxpi_poker.py` | tournament rules, packet snapshot, HTTP relay |
| `software/Server/Python/src/msxpi_cmd_web.py` | `poker` MSXPi command |
| `software/Server/Python/tests/test_poker.py` | rules, packet, join/drop and relay tests |
| `software/tools/make_poker_cards.py` | regenerates the card tiles from the vector deck |

## Running a table

On the host Pi, put these in `msxpi.ini`:

```text
var POKERNICK=ALICE      # your name at the table (1-12 characters, uppercased)
var POKERROOM=attic      # the room you join by default
var POKERSTACK=1500      # starting stack, in chips
var POKERLEVELSECS=300   # seconds per blind level
var POKERLATE=4          # late registration stays open for this many levels
var POKERACTIONSECS=45   # seconds to act before an automatic check/fold
var POKERDROP=20         # seconds of silence before a seat is auto-checked/folded
var POKERGRACE=600       # seconds a dropped seat is held for its player to return
var POKERHANDDELAY=6     # seconds between hands
var POKERLISTEN=0.0.0.0  # where the host's relay listens
var POKERPORT=5090
```

The host runs `PPOKER`, presses `H` and types a room; its Pi starts the relay.
Every other player sets only

```text
var POKERNICK=BOB
var POKERRELAY=http://HOST:5090
var POKERROOM=attic
```

and presses `J`. The room name is 1-16 letters or digits. `POKERRELAY` may also
be set in the environment as `POKER_RELAY_URL`, and `POKERNICK` as `POKER_NICK`.

Without any `POKERRELAY`, a single Pi can host and play; the first `join` creates
the tournament on that Pi. `poker new ROOM` restarts a room, `poker leave`
gives up a seat, `poker rooms` lists what the host knows.

## Command set

The MSX sends one plain-text command per poll: `join ROOM`, `host ROOM`,
`new ROOM`, `poll`, `peek`, `fold`, `check`, `call`, `bet N`, `raise N`,
`allin`, `say TEXT`, `chat`, `leave`, `nick NAME`, `rooms`.

`poll` is the heartbeat: it refreshes the table, marks the player connected and
returns the 256-byte snapshot. A player who stops polling is auto-checked or
folded after `POKERDROP` seconds (their seat still shows, marked `-`), and after
`POKERGRACE` the seat is released. Polling again with the same nickname before
then restores the seat, its stack and its cards.

## The relay

`POST /poker` with `{"cmd": "join attic", "nick": "BOB", "room": "attic"}` and
the reply `{"packet": "<512 hex digits>"}`; `{"error": "..."}` on failure (the
client reports the text in its status line). `say` may pass its text as
`"text"` instead of in the command. The relay keeps one tournament per room for
a day, so a table survives a client that forgets its room. Any error inside the
handler is returned as an error packet rather than a broken connection, so an
MSX never hangs on a poll.

## The packet: one fixed 256-byte reply

Every reply is 256 bytes, the size the MSXPi link already carries for PChess, so
the transport never has to frame anything. Integers are little-endian 16-bit
where marked `w`. Byte 255 is the low byte of the sum of bytes 0-254, and a bad
checksum drops the frame (the next poll brings a fresh one).

| Offset | Size | Meaning |
| --- | --- | --- |
| 0-3 | 4 | `POKR` magic |
| 4 | 1 | 1 for a table packet, 0 for chat and error packets |
| 5 | 1 | 1 for a table packet, `C` chat, `E` error |
| 6 | 1 | stage 0 wait, 1 preflop, 2 flop, 3 turn, 4 river, 5 showdown, 6 hand over, 7 tournament over |
| 7 | 1 | yours: 1 your turn, 2 in this hand, 4 folded, 8 all in, 16 out of chips, 32 button, 64 waiting, 128 disconnected |
| 8 | w | hand number |
| 10 | w | pot |
| 12 | 1 | your seat number, `0xFF` not seated |
| 13 | 1 | action sequence (bumped for every action) |
| 14 | w | chips you must put in to call |
| 16 | w | minimum raise, or the bet when there is none |
| 18 | w | your stack |
| 20 | w | your bet this street |
| 22 | 1 | seconds left on your action clock |
| 23 | 1 | players left in the tournament |
| 24 | 1 | blind level, 1-based |
| 25 | 1 | seats in use |
| 26 | w | small blind |
| 28 | w | big blind |
| 30 | 1 | flags2: 1 registration open, 2 tournament over, 4 showdown |
| 32-36 | 5 | board, card or `0xFF` |
| 37-38 | 2 | your hole cards |
| 39 | 1 | players left (same as 23, kept for the client's layout) |
| 41 | 1 | seconds until the next hand |
| 42 | 1 | drop grace, in seconds |
| 44-53 | 10 | your hand in capitals (`FULL HOUSE`), empty before the flop |
| 64+16i | 16 | seat *i*, see below |
| 208-247 | 40 | status line, ASCII, zero padded |
| 248 | 1 | unread chat rows |
| 249 | 1 | 1 when the tournament is over |
| 251 | 1 | seconds left in this blind level |
| 252 | 1 | seats at a table (9) |
| 253 | 1 | packet layout version (1) |
| 255 | 1 | checksum |

A card is one byte, `(rank-2)*4 + suit`, rank 0-12 for 2-A and suit 0-3 for
clubs, diamonds, hearts, spades; `0xFF` is no card. A card is only filled in
for your own seat and for players whose cards are face up at showdown.

A seat record is 16 bytes: byte 0 flags (1 occupied, 2 in the hand, 4 folded,
8 all in, 16 out of chips, 32 button, 64 acting, 128 disconnected), byte 1 the
last action (0 none, 1 fold, 2 check, 3 call, 4 bet, 5 raise, 6 all in),
`+2` w stack, `+4` w bet, `+6` two cards, `+8` 6 bytes of nickname, `+14` w the
amount of that action.

A chat packet (`4` = 0, `5` = `C`) carries up to five rows of 44 bytes from
offset 8: 42 characters of text and, at `+43`, 1 for a private message. Byte 240
is the row count and 241 the rows still queued; the client asks again while 241
is set. An error packet (`5` = `E`) puts its text at offset 208 like a status
line. The client reads a hand name from the packet rather than evaluating seven
cards on a Z80.

## Tournament rules

Blinds start at 10/20 with a 1500 stack and rise on the level clock; the button
moves each hand (heads-up posts the small blind on the button). A betting round
ends when everyone still in has matched the bet, the big blind gets their option
preflop, and a short all-in raise does not reopen the betting (the caller sees
`BET NOT REOPENED`). All-ins build side pots, split pots divide odd chips to the
earliest seat left of the button, and a player with no chips after a hand is out.
Late registration and rejoining between hands are allowed for `POKERLATE`
levels; after that the table is closed to new seats. The last player standing
wins, and every client's status line says so.

## Tests

```text
cd software/Server/Python && python -m unittest tests.test_poker
```

Covering the evaluator, blinds and the button, minimum raises and short
all-ins, side pots and split pots, the action clock and auto check/fold,
dropping and rejoining, late registration, the packet fields and checksum, every
command, and two players meeting over a real relay on localhost.
