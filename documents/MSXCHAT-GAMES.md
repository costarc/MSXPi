# MSX Free Chat: inviting players to a game

MSX Free Chat (`MCHAT.COM`) is a general multi-room chat. From it a player can invite somebody to an online
game. The mechanism knows nothing about any particular game: a game is an entry in a registry, and the
program that runs it follows a small contract. This page describes both, so that another game (or another
program, such as a chess or checkers client) can be added without touching the chat.

## What the players do

| Command | Effect |
|---|---|
| `/games` | list the games this chat can start |
| `/play NICK [GAME]` | invite `NICK` (default game: `soccer`) |
| `/accept`, `/decline` | answer an invitation (shown as a chat line, and in the status bar) |
| `/cancel` | withdraw an invitation or leave a game that is about to start |

When both agree, `MCHAT` ends by itself and the game starts: the chat types the game's command line at the
MSX-DOS prompt. The chat keeps running on the MSXPi, so running `MCHAT` again after the game picks it up where
it was, with a line saying how the game ended. The chat over TCP/IP only (`MCHAT /t`, no MSXPi) cannot start
games: the game transports need the MSXPi.

## The game registry

A game has an id (lower case letters, digits, `-`) and:

| Field | Meaning |
|---|---|
| title | shown to the players |
| command | MSX-DOS command line, at most 37 characters, letters, digits, space and `. _ : -` only. `{role}`, `{peer}` and `{token}` are replaced: the seat's role word, the opponent's nick, the session id |
| roles | one word per seat. Seat 0 is the player who sent the invitation |
| transport | `netplay`: the two MSXPi servers are connected by `msxpi_netplay` (UDP, for lockstep games). `none`: the game makes its own connection; the chat only starts it |
| version | protocol version of the game; players with different versions cannot play each other (the invitation is declined) |

Built in: `soccer` = Konami's Soccer, `SOCCERNET {role}`, roles `H`,`C`, transport `netplay`.
More games, or a replacement, go in `msxpi.ini`:

```
var MSXGAME_<id>=Title|COMMAND {role}|role0,role1|transport[|version]
```

## What a game program must do

1. Be an MSX-DOS program started with the command line above. It must check its own prerequisites and print a
   clear message if something is missing (the chat cannot know, for instance, whether a ROM is on the disk).
2. For `netplay` games: use the MSXPi opcode `C9` (see `msxpi_netplay.py`) and begin with the session start flag
   (`0x40` then status polls with `0x80`); it receives the agreed input delay and the connection state. The
   opponent's address never reaches the MSX: the Pi already holds it.
3. End by returning to MSX-DOS (or resetting the machine). It must not expect to return into the chat.
4. Never rely on the chat for anything else: after the program ends the player types `MCHAT` to go back.

## How an invitation travels

Private IRC messages between the two chat servers, never shown as chat (rooms ignore them):

```
MSXG1 INVITE  <game> <version> <token>
MSXG1 ACCEPT  <token> <candidates>        candidates: ip:port,ip:port  or  -
MSXG1 GO      <token> <candidates>
MSXG1 DECLINE <token> <reason>            busy | declined | unknown-game | version
MSXG1 CANCEL  <token>
```

For a `netplay` game the accepting side opens its UDP port and sends the addresses it can be reached at (its
LAN address and, if a STUN server answers, its public one); the inviter answers with its own. Both servers then
send to the other's addresses at the same time, which opens the NAT on both sides (hole punching), and the
first address that answers is kept. There is no relay: behind symmetric or carrier-grade NAT the connection
fails and both players are told. An invitation expires after 120 s, a ready game that is not started after 180 s.

## MSX side of the chat

The `M` reply (rows) has a flags byte at offset 22: bit 0 = a game is ready to start, bit 1 = an invitation is
waiting. When bit 0 is set `MCHAT.COM` sends `mchat launch`; the `L` reply carries a flag (offset 6) and the
command line (offset 24, zero-terminated). The client puts the line and Enter into the BIOS keyboard buffer,
closes its screen and returns to MSX-DOS, without telling the server to quit.

## Tests

- `software/Server/Python/tests/test_games.py`: the invitation flow, two real chats against the local IRC fixture,
  and a made-up second game.
- `software/Client/tests/soccernet/run_native.sh` with `SCENARIO=chat`: two emulated MSX meet in `MCHAT`, one
  invites the other, the chat starts Konami's Soccer, and the two machines are compared frame by frame.
