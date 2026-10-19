# MSX Free Chat: inviting players to a game

MSX Free Chat (`MCHAT.COM`) is a general multi-room chat. From it a player can invite somebody to an online
game. The chat knows nothing about any particular game: a game is a GPF file in the games folder, and the
program that runs it follows a small contract. This page is the chat's side of it. The full specification
(formats, protocols, how to bring a new game) is `documents/PLAYNET-PROTOCOLS.md`.

## What the players do

| Command | Effect |
|---|---|
| `/games` | list the games this chat can start |
| `/play NICK [GAME]` | invite `NICK` (default game: `soccer` when installed) |
| Ctrl-U | pick a player in the user list: Up/Down move the highlight, Enter puts `/play NICK ` on the input line (add a game name, or press Enter again for the default game), Esc goes back to typing |
| `/accept`, `/decline` | answer an invitation (shown as a chat line, and in the status bar) |
| `/cancel` | withdraw an invitation or leave a game that is about to start |

When both agree, `MCHAT` ends by itself and the game starts: the chat types the game's command line at the
MSX-DOS prompt (`PLAYNET` for a lockstep game). The chat keeps running on the MSXPi, so running `MCHAT` again after
the game picks it up where it was, with a line saying how the game ended.

Status: the MSXPi side is implemented. Games from the chat over TCP/IP only (`MCHAT /t`, no MSXPi) are designed
(`documents/PLAYNET-DESIGN.md`, sections 5.6 and 7) but not built yet.

## The games

On the MSXPi the games are the files `MSXPIHOME/games/<GAME-ID>.GPF` (`/home/pi/msxpi/games/`), compiled from
ROM-Patcher packages (`software/ROM-Patcher/profiles/<id>/`, `patch_rom.py --gpf`). The chat reads only their
header:

| Field | Meaning |
|---|---|
| game id | 1-8 characters `a-z 0-9 -`; what players type; in upper case, the file name |
| title | shown to the players |
| roles | one word per seat. Seat 0 is the player who sent the invitation |
| transport | `lockstep`: PLAYNET runs the game, and the two MSXPi servers connect the machines (`msxpi_netplay`, UDP). `none`: the game is its own program and makes its own connection; the chat only types its command line |
| command | for transport `none` only: the MSX-DOS command line, at most 37 characters of `A-Z a-z 0-9 space . _ : / -`; `{role}`, `{peer}` and `{token}` are replaced by the seat's role word, the opponent's nick and the session id |
| profile hash | CRC-32 of the file. Players whose hashes differ cannot play each other: the invitation is declined and both are told to update |

A file with a bad header or checksum, or with the wrong name, is skipped and logged. Adding a game means adding its
file; nothing is configured in `msxpi.ini`.

## What a game program must do

- **Lockstep games** are run by `PLAYNET.COM` and need nothing from the chat. PLAYNET asks the Pi for the session
  (`playnet session`), the package (`playnet profile`), connects (opcode `C9`), runs the game, and reports how it ended
  (`playnet result`). See the specification, sections 10, 13 and 15.
- **Games with transport `none`**:
  1. Be an MSX-DOS program started with the command line above. It must check its own prerequisites and print a clear
     message if something is missing.
  2. End by returning to MSX-DOS (or resetting the machine). It must not expect to return into the chat. After it ends,
     the player types `MCHAT` to go back.

## How an invitation travels

Private IRC messages between the two chat programs, never shown as chat (rooms ignore them). See the specification, section 12.

```
MSXG1 INVITE  <game> <profhash> <token>      profhash: 8 hex digits
MSXG1 ACCEPT  <token> <candidates>           candidates: ip:port,ip:port  or  -
MSXG1 GO      <token> <candidates>
MSXG1 DECLINE <token> <reason>               busy | declined | unknown-game | profile | no-mapper
MSXG1 CANCEL  <token>
```

For a lockstep game the accepting side opens its UDP port and sends the addresses it can be reached at (its LAN address
and, if a STUN server answers, its public one). The inviter answers with its own. Both sides then send to the other's
addresses at the same time, which opens the NAT on both sides (hole punching), and the first address that answers is
kept. There is no relay: behind symmetric or carrier-grade NAT the connection fails and both players are told. An
invitation expires after 120 s, and a ready game that is not started after 180 s.

## MSX side of the chat

The `M` reply (rows) has a flags byte at offset 22: bit 0 = a game is ready to start, bit 1 = an invitation is waiting.
When bit 0 is set, `MCHAT.COM` sends `mchat launch`. The `L` reply carries a flag (offset 6) and the command line
(offset 24, zero-terminated). The client puts the line and Enter into the BIOS keyboard buffer, closes its screen, and
returns to MSX-DOS without telling the server to quit.

## Tests

- `software/Server/Python/tests/test_games.py`: the registry from real GPF files (`gpf_fixture.py`), the invitation flow
  (profile hash, declines, expiry), the session record and results, the `playnet` commands, and two real chats against
  the local IRC fixture.
- `software/Server/Python/tests/test_netplay.py`: the MSXPi side of the session (handshake with profile hash, delay,
  relay of 1-4-byte inputs, start and dead timeouts, BYE).
- `software/Client/tests/soccernet/run_native.sh` with `SCENARIO=chat`: two emulated MSX meet in `MCHAT` and the game
  starts. It still runs the old `SOCCERNET` program and does not match the Pi again until PLAYNET replaces it
  (implementation step 4).
