# Playing PLAYNET games over TCP/IP

*English. Português do Brasil: [PLAYNET-TCPIP-GUIDE.pt-BR.md](PLAYNET-TCPIP-GUIDE.pt-BR.md)*

> **Alpha.** Online play is still being tested. So far it has only been tried between emulators. It has not been tried on a
> GR8NET or on real hardware over TCP/IP. Expect rough edges.

Two people, each with an MSX, chat and then play a game against each other over the Internet. This guide is for MSX computers
that reach the network through a **TCP/IP card** (not through the MSXPi link).

## Which kind of card do you have?

| Your card | Examples | Install InterNestor Lite (INL)? |
|---|---|---|
| **Ethernet card** | the MSXPi's Ethernet, ObsoNET | **Yes** (Step 2A) |
| **Card with TCP/IP built in** | GR8NET, DenYoNet | **No** (Step 2B) |

Everything else is the same for both.

## Step 1 - Get the files

Both players need these files together **on one disk or in one folder**. Copy them from a PC (the MSX cannot download them).

**For everyone**

| File | What it is | Where to get it |
|---|---|---|
| `MCHAT.COM` | the chat | `software/target/` |
| `PLAYNET.COM` | starts the game | `software/target/` |
| `PLAYNET.OVL` | goes with `PLAYNET.COM` | `software/target/` |
| `SOCCER.GPF` (or another game's `.GPF`) | the game package | `software/target/games/` |
| `SOCCER.ROM` (or the game's ROM) | **your own copy of the game** | you (not supplied) |
| `MCHAT.INI` | your settings (optional, see Step 4) | you write it |

**Only for Ethernet cards (Step 2A)**

| File | Where to get it |
|---|---|
| `INL.COM` and `INL.CFG` | `software/UNAPI/bin/` and `software/target/` |
| `MSR.COM` (only if you use MSX-DOS 1) | `software/UNAPI/bin/` |
| `RAMHELPR.COM` (only if you use Nextor or MSX-DOS 2) | `software/UNAPI/bin/` |
| the card's own driver (ObsoNET and others; not needed for the MSXPi) | comes with the card |

**The games and their ROM files**

| Game | Game file | Your ROM must be named | Size |
|---|---|---|---|
| Konami's Soccer | `SOCCER.GPF` | `SOCCER.ROM` | 32768 bytes |
| Konami's Ping Pong | `PINGPONG.GPF` | `PINGPONG.ROM` | 16384 bytes |
| Konami's Yie Ar Kung-Fu | `YIEAR.GPF` | `KUNGFU.ROM` | 16384 bytes |
| Konami's Salamander | `SALAMAND.GPF` | `SALAMAND.ROM` | 131072 bytes (see "Salamander" at the end) |

Both players must use the **same `.GPF` file**. If the game says the other player has a different version, copy the same file to both.

> **MSXPi owners:** run the updater `msxpiupd`. It already puts `MCHAT.COM`, `PLAYNET.COM`, `PLAYNET.OVL`, `INL.CFG` and the
> `.GPF` files on your disk. You only add your ROMs, `MSR.COM` and `INL.COM`.

## Step 2A - Ethernet card: start the network (needs INL)

Do this **every time you turn the MSX on**. Type the two lines for your system:

| MSX-DOS 1 | Nextor or MSX-DOS 2 |
|---|---|
| `MSR I` | `RAMHELPR I` |
| `INL I` | `INL I` |

Notes:
- With an **MSXPi**, never type `RAMHELPR I` on MSX-DOS 1. It breaks `MSR`.
- `INL.CFG` holds the network addresses. The supplied one is for the MSXPi. On another network, edit it (or delete it to use
  automatic DHCP addresses).
- With a card other than the MSXPi, install the card's own driver first, then the two lines above.

Check that it works: type `INL S` (shows your address). If you have `HOST.COM`, `HOST msx.org` should show an address.

## Step 2B - GR8NET / DenYoNet: nothing to install

The card has its own TCP/IP. Set up its network with its own tools (see its manual) and make sure it is online.

The game also needs a **memory mapper** (extra RAM the MSX can switch):
- MSX2 and later: you normally have one. On MSX-DOS 1, type `MSR I`.
- MSX1 with a GR8NET: the GR8NET can provide the mapper (`CALL NETSETMAP(8,M)` in BASIC, see its manual), then type `MSR I`.
  *This has not been tested yet.*
- MSX1 with a DenYoNet and no mapper: it cannot play. Add a mapper cartridge.

Nothing else should be using the card's network connections while you play.

## Step 3 - Let the other player reach you

- **Same home or network, or a VPN:** nothing to do.
- **Over the Internet:** you must do two things, and so must the other player:
  1. In your router, **forward UDP port 5000 to your MSX**.
  2. Write a file `MCHAT.INI` (Step 4) with your port and your public IP address:
     ```
     GAMEPORT=5000
     GAMEADDR=203.0.113.25
     ```
     (Replace `203.0.113.25` with your own public IP. Search "what is my IP" on a PC.)

Some connections cannot be used (mobile data and some providers share one IP among many customers). If that is your case, use a VPN.

## Step 4 - `MCHAT.INI` (optional)

A small text file, one setting per line:

| Line | Meaning |
|---|---|
| `IRCNICK=myname` | your nickname |
| `GAMEPORT=5000` | the game's port (use the same number you forwarded) |
| `GAMEADDR=203.0.113.25` | your public IP address (needed over the Internet) |
| `MCHATROOM=#msxpi` | the chat room (both players must be in the same room) |
| `GAMELINK=1` | only for MSXPi owners: also send the game over TCP/IP |

You can leave the file out when you play on the same network.

## Step 5 - Play

Go to the disk or folder with your files and type:

```
MCHAT /T MYNAME
```

(`MYNAME` is your nickname. On a machine **without** an MSXPi, `/T` is optional; **with** an MSXPi it is required.)

Then:

| | Player 1 (invites) | Player 2 |
|---|---|---|
| 1 | `/WHO` shows who is in the room, `/GAMES` shows your games | |
| 2 | `/PLAY NICK2 SOCCER` (NICK2 = the other player's nickname) | the invitation appears |
| 3 | | type `/ACCEPT` (or `/DECLINE`) |

The screens clear, the game starts on both MSX in a few seconds. **The player who invited is player 1.** Use the cursor keys or
joystick 1, and SPACE or the button.

To **stop the game**, press **Ctrl+Shift+F5**, or finish the match. You return to the chat.

`/CANCEL` withdraws an invitation. `ESC` leaves the chat.

## If something goes wrong

| What you see | What to do |
|---|---|
| `No TCP/IP UNAPI: run INL I first` | do Step 2A (or set up your card, Step 2B) |
| `Not enough memory for TCP/IP` | restart the MSX; on a machine with its own disk drive hold **CTRL** while it starts |
| stuck on `Connecting...` | the network is down: test with `INL S` / `HOST msx.org`; make sure nobody else already uses your nickname |
| "cannot play it (needs a memory mapper)" | that player must type `MSR I` (MSX-DOS 1) or use Nextor |
| "does not have that game" / "different version" | both players must have the same `.GPF` file |
| ROM not found or wrong | the ROM must be in the same folder, with the exact name in the table of Step 1, and be the right dump |
| the game never connects | both players must start at about the same time; check the router port forwarding and `MCHAT.INI`; try a VPN |
| the game pauses | the Internet connection is slow or losing packets; both MSX wait for each other |

**Salamander:** it needs a lot of memory. Use a memory mapper of **1 MB** with Nextor (512 KB is enough on MSX-DOS 1). On a machine
with its own disk drive running MSX-DOS 1, restart holding **CTRL** or use Nextor. Soccer, Ping Pong and Yie Ar Kung-Fu work everywhere.

## Playing without the chat (advanced, optional)

If you already agreed on addresses by phone, skip the chat. Each player types (adapt the addresses; `H` is player 1, `C` is player 2):

```
Player 1:  PLAYNET /T SOCCER H 5000 192.168.1.60:5000
Player 2:  PLAYNET /T SOCCER C 5000 192.168.1.50:5000
```

The address after the port is the **other** player's address. Start both within a few seconds of each other.

## More information

`documents/MSXCHAT-GAMES.md`, `software/target/games/README.md`, `software/Client/src/MCHAT.md`.
