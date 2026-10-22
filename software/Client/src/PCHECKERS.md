# PCheckers (DAMAS)

Brazilian draughts on the 8x8 board for the MSX2 and later, built from the
PChess client (`pchess.c`). The rules and the AI run on the MSX itself, so
local and AI games need no server. Online play, the lobby and chat work like
PChess's, on the MSXPi link and on the TCP/IP link, and PChess and PCheckers
players share the same IRC lobby and rooms.

Build: `software\make.bat pcheckers` (from `software`), then run `PCHECKERS`
in MSX-DOS. It needs an MSX2 (SCREEN 5, 64 KB VRAM is enough). Memory is
tight like PChess's: the program ends at 0xC05E, and the TCP/IP link refuses
to start with less than 768 bytes below the TPA top (`LOW MEMORY: TPA xxxx
END yyyy`; 0xC806 on a Canon V-25 once `INL I` is loaded).

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
| `c3d4` + Return | Typed move (`c3-d4`, `c3xe5`); a capture with several routes needs every landing square (`c3e5g7`) |
| 1 | Local two-player game |
| 2 / 3 | Game against the AI, you as white / black |
| 4 | ROOM: type a room name, Return |
| 5 | ONLINE: join the lobby (`#msxpi`) |
| 6 SEEK | Announce that you want to play (lobby) |
| 7 ASK | Type a nick, Return: invite that player (you play white) |
| 8 ACCEPT | Accept the invitation shown in the status line |
| 9 PLAYER | List players who sought or invited you in ten minutes; Return invites |
| TAB | Chat window (online games) |
| ESC | Menu |

Green dots show where the selected piece can go. A capture with several
routes is entered one landing square at a time (`CONTINUE THE CAPTURE`); when
only one legal move still fits, it is played. While online, keys 1-5 first ask
`LEAVE ONLINE GAME? Y/N`. Once matched the panel shows `AS WHITE`/`AS BLACK`
and black sees the board rotated.

ESC menu: `AI LEVEL` (1-6, searching level+1 plies; about 2-7 s a move at the
default 2 on a 3.58 MHz Z80, minutes at 5-6), `ROOMS` (RELAY or IRC, saved in
msxpi.ini by `pchess rooms`; always IRC on the TCP/IP link), `LINK`
(MSXPI or TCPIP, applied with Return or ESC), `OFFER DRAW`, `RESIGN` (both ask
Y/N), `ROTATE BOARD`, `CHAT`, `REMATCH` (online, after a game), `CREDITS`,
`EXIT`. With no MSXPi interface the status line reads
`NO MSXPI - ESC MENU LINK TCPIP` and MSXPi-only actions fail at once instead
of waiting; the ESC menu still opens.
The AI accepts a draw when it is not ahead. Online, the opponent sees
`OPPONENT OFFERS DRAW - ESC MENU` and accepts by offering too, or declines by
moving.

## Online play and chat

* **Rooms (`4`)**: on the MSXPi link a room is either a relay room (the
  small HTTP relay of the MSXPi server, `PCHESSRELAY`, `PCHESSPORT`; the first
  to join plays white) or, with `ROOMS: IRC`, the IRC channel
  `#pchess-<room>` (the lower nick plays white). On the TCP/IP link rooms are
  always IRC.
* **Lobby (`5`)**: the IRC channel `#msxpi`; seek, ask, accept and the player
  list work as in PChess. The player who asks plays white.
* **Chat**: the same window as PChess (TAB or the menu, 20 rows, private
  rows yellow). In the lobby and in IRC rooms it goes to the channel, which
  PChess players read too, and what they say reaches PCheckers; once a game
  has started it goes to the opponent alone. Relay rooms have no public
  channel (as in PChess): chat there reaches only the opponent.
* The checkers game lines are `PCH1 CK ...` messages (documented in
  `Server/Python/src/msxpi_pcheckers_irc.py`). PChess ignores them, so they
  never show as chat there, and an MSX on the MSXPi link and one on the TCP/IP
  link can play each other. The server relays and orders moves but does not
  know the rules: each client checks every move it receives.

The AI level is local to the MSX and is not saved; PChess's saved level
belongs to the server's Stockfish.

## Files

* `pcheckers.c` - screen, input, menus, chat window (from `pchess.c`).
* `pcheckers_rules.c` - rules, move generation and AI; plain C, no MSX code.
* `pcheckers_tcp.c` - the TCP/IP link: UNAPI, IRC and the PCH1 CK peer (the
  transport is a copy of `pchess_tcp.c`'s; a change there is worth mirroring).
* `Server/Python/src/msxpi_pcheckers_irc.py`, and `msxpi_pchess.py`
  (`cjoin`, `circ`, `cseek`, `coffer`, `caccept`, `cplayers`, `cmove`,
  `cpoll`, `cdraw`, `cresign`, `creset`, `cleave`).

## Tests

* `Client/tests/pcheckers_rules_test.py` - builds `pcheckers_rules_host.c`
  with sdcc for the Z80 and runs it in the `sz80` simulator: opening perft
  7/49/302/1469, majority capture, flying king, backward capture, crowning.
* `Server/Python/tests/test_pcheckers.py` (relay rooms) and
  `test_pcheckers_irc.py` (IRC rooms, lobby, chat shared with a PChess
  peer, server commands) against the pchess IRC fixture.
* openMSX, `Client/tests`: `pcheckers_chat_openmsx.py` (two MSXs on the relay
  with chat), `pcheckers_irc_openmsx.py room|lobby` (one MSX against IRC
  players) and `pcheckers_tcpip_openmsx.py` (TCP/IP link, needs the Windows
  TAP free and set up, like `pchess_tcpip_openmsx.py`).
