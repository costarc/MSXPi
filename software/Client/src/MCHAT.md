# MCHAT - MSX Free Chat

An IRC chat for the MSX through the MSXPi, in the same `#msxpi` channel as
the PChess lobby (PChess game traffic is hidden). `MCHAT.COM` is the MSX1
build: SCREEN 2, 51 columns. It is about 15 KB, so it leaves most of the TPA
free.

    mchat [nick]

Without a nick the server uses `IRCNICK` from `msxpi.ini`, else `msxNNNN`.
`IRCADDR`, `PCHESSIRCPORT`, `IRCTLS`, `IRCACCOUNT` and `IRCPASSWORD` are the
PChess IRC settings; `MCHATROOM` changes the first room (default `#msxpi`).

## Using it

| Key | Action |
|---|---|
| text, RETURN | say it in the current room, or run a `/command` |
| TAB, RIGHT / LEFT | next / previous room (tabs on the top row) |
| UP / DOWN | read older / newer messages (the server keeps 400 rows a room) |
| HOME | back to the latest message |
| ESC, `/quit` | leave and disconnect |

Commands: `/nick N`, `/msg N TEXT` (private), `/join #room`, `/part`,
`/me TEXT`, `/who`, `/topic`, `/help`. Up to four rooms are open at once; a
room tab turns magenta when it has unread messages. Private messages arrive
in the room you are looking at, in yellow. The left panel lists the users of
the current room (`@` operators, `+` voiced).

## How it is built

- **Server** `Server/Python/src/msxpi_chat.py`, command `mchat`: a subclass
  of the PChess `IRC` class (connection, TLS, SASL), with a multi-room chat
  reader. It keeps rooms, scrollback and user lists, and wraps lines to the
  width the client announces, so the MSX stores almost nothing. Packet
  layouts are in the module docstring. Tests: `Server/Python/tests/test_chat.py`.
- **Client logic** `mchat.c` draws only through `mchat_ui.h`, in character
  cells. It never touches the VDP.
- **Display backend** `mchat_ui_s2.c`: SCREEN 2 as a bitmap with a software
  4x8 font on a 5 pixel pitch (`mchat_font4x8.h`, generated from
  `Client/tools/gen_mchat_font.py`). Colours are per 8-pixel tile, so styles
  only change at multiples of 8 columns; `ui_side` (8) is where the user list
  ends. A backend for MSX2 (80 columns in SCREEN 7, or SCREEN 0 text) or
  another MSX1 mode only has to provide the functions in `mchat_ui.h`; it can
  be swapped at run time with `ui_close()` / `ui_open()` and a redraw.
- Like the other clients it has no C runtime start-up: uninitialised globals
  are not zeroed, so `main()` clears them.

## Build and test

`make mchat` from `software\` (about 10 seconds). End-to-end test in openMSX
(Canon V-25, MSX-DOS 1) against the IRC fixture:

    python Client\tests\mchat_openmsx.py [path\to\mchat.com]

It checks public and private rows, the user list, a second room, TAB and
scrollback by decoding VRAM with the program's own font.

## Not yet

TCP/IP UNAPI link (as PChess), MSX2 backend, an MSX2 version of the layout,
nick/last-room saved in a file, `/whois`, message time stamps.
