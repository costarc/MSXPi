# Online games (PLAYNET)

Each `<ID>.GPF` here is one game that two MSX computers can play against each other from the chat (`MCHAT`). A GPF holds no ROM
data, only the patches that make the game networked. Every player needs their own dump of the game's ROM, under the name the table gives, and
`PLAYNET` checks that dump before it starts. `index.txt` lists each file with its SHA-256.

| File | Game | ROM needed |
|---|---|---|
| `SOCCER.GPF` | Konami's Soccer (two players) | `SOCCER.ROM`: Konami's Soccer (RC-732), 32768 bytes, CRC-32 `74BC8295` |
| `SALAMAND.GPF` | Konami's Salamander (co-op, both ships at once; a memory mapper with 22 free segments, 512 KB or more) | `SALAMAND.ROM`: Konami's Salamander (RC-758), 131072 bytes, CRC-32 `C36F559D` |
| `PINGPONG.GPF` | Konami's Ping Pong (two players, one on each machine; the inviter plays the first pad) | `PINGPONG.ROM`: Konami's Ping Pong (1985), 16384 bytes, CRC-32 `3F200491` |
| `YIEAR.GPF` | Konami's Yie Ar Kung-Fu (Single, Turn or Versus, chosen by the inviter on a play-mode screen; in Versus the second player controls the opponent) | `KUNGFU.ROM`: Konami's Yie Ar Kung-Fu (RC-725), 16384 bytes, CRC-32 `8A12EC4F` |
| `PWARS2.GPF` | ASCII's Penguin-kun Wars 2 (versus: the second player controls the computer opponent; MSX2, a memory mapper of 512 KB, over an MSXPi only) | `P-WARS2.ROM`: ASCII's Penguin-kun Wars 2 (MSX2, 1988), 262144 bytes, CRC-32 `B1B24DA1` |

## Installing a game

**With an MSXPi.** Nothing to do. `update.sh` (MSXPi updater, and `msxpi-setup.sh`) fetches the listed games into the Pi's
`games/` folder next to the server, and later only the ones that changed. Put the ROM in the folder where you start `MCHAT`:
`PLAYNET` runs there and opens it from the current directory. In `MCHAT`, `/games` lists the games, and `/play NICK [GAME]` invites someone.

**Without an MSXPi** (`MCHAT /T`, TCP/IP UNAPI with InterNestor Lite, GR8NET, ...). An MSX cannot download these files itself:
GitHub needs HTTPS. Copy them on a PC, all into the folder where you start `MCHAT /T`:

- `MCHAT.COM` and `MCHAT.INI`;
- `PLAYNET.COM` and `PLAYNET.OVL`;
- `<ID>.GPF` and your ROM.

Under MSX-DOS 1 that is the disk's only folder. A memory mapper is required (MSX-DOS 2 or Nextor, or `MSR` on MSX-DOS 1). The other
player must have the same GPF. A different version is refused at the invitation, with a line telling one of you to update.

## Adding a game of your own

1. Write the package: `software/ROM-Patcher/profiles/<id>/`. The guide is `documents/PLAYNET-PROTOCOLS.md` Part I. It covers
   finding the frame, the inputs and the RAM footprint, then writing the glue and `profile.json`. Soccer is the worked example.
2. Compile it: `python software/ROM-Patcher/patch_rom.py --profile profiles/<id>/profile.json --gpf <ID>.GPF <your ROM>`. Given the
   ROM, it also checks that the GPF rebuilds the same image as the package.
3. Test it locally: copy `<ID>.GPF` into the Pi's `games/` folder, or next to `PLAYNET.COM` for TCP/IP. `update.sh` never touches a
   file that `index.txt` does not list, so your own GPF stays. To change an official game, give your copy another id.
4. Publish it: a pull request with `profiles/<id>/` and the output of `python software/ROM-Patcher/build_games.py`, which writes the
   GPF here and its line in `index.txt`. The tests (`ROM-Patcher/tests/test_gpf.py`) fail when this folder is not what the packages
   compile to.
