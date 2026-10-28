# PLAYNET design: online games from the MSX chat, with or without an MSXPi

PLAYNET lets two MSX players meet in MSX Free Chat (`MCHAT`) and play a two-player game over the Internet. Each MSX runs the whole
game; only the two players' inputs cross the network (lockstep). This document explains the design and why it is the way it is. The byte-level
specification and the guide for game authors are in `PLAYNET-PROTOCOLS.md`, and the TCP/IP link's speed work is in
`PLAYNET-TCPIP-PERFORMANCE.md`. Where this document and the specification differ in a detail, the specification wins.

The design had one hard requirement: **it must work on a plain MSX with a TCP/IP UNAPI card or cartridge (GR8NET, ObsoNET,
InterNestor Lite...), where there is no host (Raspberry Pi or PC) to run the server-side code**, and an MSXPi player and a TCP/IP
player must be able to play each other.

---

## 1. Summary

With an MSXPi, the Raspberry Pi can do everything above the in-game stub: the invitations, the UDP session (STUN, hole punching,
version check, round-trip measurement, keep-alive), the game profiles, and the hand-off from the chat to the game. Without a Pi, the MSX
has to do all of it. The design therefore has these parts:

- **One specification, two implementations.** The IRC invitation messages, the peer-to-peer UDP protocol, the session record and the
  compiled game profile are written specifications. The Pi (Python) and the MSX (C and Z80) each implement them. **Mixed matches (a Pi
  player against a TCP/IP player) are a requirement**, enforced by conformance tests.
- **Game profiles reuse the ROM-Patcher package format** (`msxpi-rom-patch`, `software/ROM-Patcher/FORMAT.md`), version 2: the music
  section becomes one optional "ABI" section, and a `msxpi-netplay-v1` ABI section is added beside it. There is no separate patch
  format. For the MSX, a package compiles to one small binary, `<ID>.GPF`.
- **The session is set up before the game starts, not inside it.** One generic loader, `PLAYNET.COM`, connects to the opponent in the
  MSX-DOS phase, and only then starts the game. The resident stub does only the per-frame exchange.
- **The network code on the TCP/IP path runs in a mapper segment** (`PLAYNET.OVL`). A small page-3 transport maps it in for each call.
  The game runs in a page 3 of its own, so the TCP/IP stack's state in MSX-DOS's page 3 is never touched.
- **A game ends without a reset, on every path.** The end of a game (Ctrl+Shift+F5, the opponent leaving, or a lost connection) returns
  to MSX-DOS and runs `MCHAT` again.

Plain 16 KB and 32 KB ROMs are supported first. Nothing in the format, the loader or the runtime assumes "plain", so MegaROMs can
follow (section 5.9).

---

## 2. Roles, and who does each job with and without a host

| Job | With an MSXPi (Pi host) | Without a host (TCP/IP UNAPI) |
|---|---|---|
| IRC chat | `msxpi_chat.py` on the Pi | `mchat_local.c` in `MCHAT /T` |
| `/play`, `/accept`... and the `MSXG1` messages | `msxpi_games.Invites` (Python) | `games_local.c` in `MCHAT /T` (C) |
| Game list | the `*.GPF` files in the Pi's `games/` directory | the `*.GPF` files in the current directory (`GAMES\` under DOS 2) |
| UDP socket, LAN and STUN candidates | `Netplay.open`, `Netplay.candidates` | netcore, in `PLAYNET.OVL` (C) |
| Hole punching, HELLO and profile check, leader election, round trip, delay, SETUP/ACK | `Netplay` (Python) | netcore |
| Keep-alive, dead-peer detection | `Netplay` | netcore, with the game's frame counter as the clock |
| Session hand-off from the chat to the game | kept by the Pi; the MSX asks for it with `playnet session` | `PLAYNET.SES`, written by `MCHAT /T` just before it exits |
| Profile store, validation, loading | the Pi serves the GPF (`playnet profile`); the loader validates it | the loader reads and validates the GPF from disk |
| Loader | `PLAYNET.COM` | the same program, with `/T` |
| Per-frame exchange in the game | stub and the native transport (opcode C9) | stub and the UNAPI transport (netcore through a page-3 transport) |
| End of a game, back to the chat | restore the DOS area from the Pi; the chat keeps running on the Pi | switch back to MSX-DOS's page 3; `MCHAT /T` reconnects to IRC |
| Profile updates | `update.sh` fetches the listed GPFs | the player copies a file (a Z80 has no TLS to reach GitHub) |

```
             Pi host (MSXPi link)                     MSX host (TCP/IP UNAPI, memory mapper required)
            ---------------------                    ---------------------------------------------
CHAT AGENT  msxpi_chat.py + msxpi_games.py           mchat_local.c + games_local.c      <- MSXG over IRC
SESSION     msxpi_netplay.py (Python, Pi socket)     netcore (C, PLAYNET.OVL, segment)  <- MSXNP over UDP
PROFILES    games/*.GPF, served to the MSX           *.GPF on the MSX disk              <- GPF (from msxpi-rom-patch v2)
LOADER      PLAYNET.COM, session from the Pi         PLAYNET.COM /T, session from PLAYNET.SES
IN GAME     game stub + native transport (C9)        game stub + UNAPI transport (page-3 transport -> netcore)
GAME END    restore the DOS area from the Pi         switch back to MSX-DOS's own page 3
```

The game stub (the lockstep engine plus the game's glue, one asset per game), the loader's ROM, profile and patch code, and the exit
handling are **the same** on both paths. Only the transport behind the stub's vector differs.

A third link, **hybrid** (link 2), combines the two: the chat runs over TCP/IP while the game's packets go through the MSXPi.
It is useful on an MSX that has both a TCP/IP card and an MSXPi.

---

## 3. Design decisions that follow from the problems

### 3.1 What is kept as it is

- **Lockstep core.** Input-only exchange, redundancy of 8 inputs per packet, a stall on a missing input, the sound driver ticked once
  per frame, the R-register coin flips replaced, and a desync checksum. It does not depend on the transport.
- **The chat contract.** The packet header flags (byte 22), `mchat launch`, and stuffing the keyboard buffer. Both links share the same
  256-byte packets, so `mchat.c` does not care which link is in use. That is what makes the no-host path cheap.
- **The invitation protocol shape**: tokens, timeouts, one game at a time, candidate exchange in ACCEPT and GO, no relay server.
- **The peer UDP protocol.** It is small enough to implement in Z80 and C. The specification generalises the game packet to 1-4 input
  bytes per frame and puts a kind byte on every datagram.
- **ROM-Patcher conventions**: file offsets instead of CPU addresses, expected bytes checked under every patch, code shipped as hashed
  assets built from sources in the package, a per-game `rebuild.py`, and Ctrl+Shift+F5 as the exit key.

### 3.2 Problems an early prototype had, and how the design avoids them

| # | Problem | Design answer |
|---|---|---|
| P1 | The handshake ran in the stub at game frame 0, inside the game's interrupt handler. The title screen stayed blank while it waited, and the stub had no room left. | The loader connects in MSX-DOS, before the game starts. The stub only exchanges frames. |
| P2 | `HELLO` carried a 1-byte version that a person keeps by hand. Lockstep needs "same patches, same engine", which a version number does not guarantee. | `HELLO` carries the profile CRC-32, which covers the patches and the stub. A mismatch is "different game data". |
| P3 | The dead-peer timer started at SETUP/ACK, so a slow loader (a floppy, a long ROM check) used up part of the 15 seconds before the game began. | The dead-peer timer starts at the first game packet, with a separate 60 s start timeout from READY. |
| P4 | The launch command is limited to 37 characters (the keyboard buffer), so session data could not travel with it. | A session record: on the Pi, read with `playnet session`; on TCP/IP, `PLAYNET.SES`. |
| P5 | The old trampoline wrote `RET` over H.TIMI, which removed the TCP/IP stack's timer hook. | The hook is preserved; the transport calls it itself, in a controlled way (5.5). |
| P6 | "Profiles are data, not code" is weaker than it sounds: byte patches and assets are Z80 code. | The trust boundary is where a profile comes from (the repository, its hash in the index), not the format. The loader's bounds and expected-byte checks protect against a corrupt or mismatched profile, not a malicious one. The format document says so. |
| P7 | Per-game code was not fully declarative (a patch replaced `ld a,r; and 6` with a call to a routine containing the game's own `and 6`). | The per-game runtime is an asset assembled from shared engine sources plus game glue, as the music runtimes are. |
| P8 | Ending a game was a reset, which threw away MSX-DOS and, on TCP/IP, the stack and the chat connection. | Both paths return to MSX-DOS without a reset (5.8). Reset is only the fallback. |

### 3.3 Requirements the no-host path adds

- **R1. Invitations in `MCHAT /T`.** `/play`, `/accept`, `/decline`, `/cancel` and `/games`, and private `MSXG1` messages handled
  instead of shown as text.
- **R2. A session engine on the MSX.** UDP open, STUN, LAN address, punching, leader election, round trip, delay, SETUP/ACK,
  keep-alive and dead-peer detection, all in C.
- **R3. Profiles without a host.** A binary format the MSX can read and a place to list games from.
- **R4. A session hand-off that survives the exit of `MCHAT`.** The opponent's candidates, the local UDP port (the NAT mapping STUN
  learned), the token, the role and the profile hash must all reach the game.
- **R5. A generic loader.** One program for every game, on both paths.
- **R6. Running a TCP/IP stack under a game that owns the machine.**
  - The game's interrupt handler lives in page 1, which the stack's implementation (and our code, if large) must map in for each call.
    An interrupt during a call jumps into whatever is mapped there, unless the game's H.KEYI hook points to page 3 and checks.
  - The game reads the VDP status in its own H.KEYI handler, so the BIOS never calls H.TIMI. A stack that does its work from H.TIMI
    stops, and `JIFFY` stops advancing. Timeouts in the stack and in our code both stop.
  - The stub uses the game's stack, which reaches F30Ch. Calling C code on that stack would overwrite the stub.
  - The stack keeps its state in MSX-DOS's page 3, inside the RAM a typical game uses.
- **R7. The end of a game.** See P8. On TCP/IP the nick would also stay taken on the IRC server until it times out.
- **R8. Distributing profiles to MSX-only players.** The MSX cannot fetch from GitHub (HTTPS only, no TLS on a Z80), and MSX-DOS 1 has
  no subdirectories.
- **R9. Memory for `MCHAT /T`.** `mchat.com` ends near C020h. With a TCP/IP stack loaded, the TPA top can be C806h, which leaves about
  2 KB. The invitations, UDP and STUN, and the profile listing in C cost more than that (8.7).
- **R10. Mixed matches.** Two implementations need the peer protocol written down, plus a conformance test between them.
- **R11. The ROM-Patcher format has to be extended.** Version 1 requires the `music`, `sounds` and `defaults` fields, describes its
  output as a new ROM file, and identifies the input by SHA-256 only. SHA-256 over 32 KB takes several seconds on a Z80, and much longer
  over a MegaROM.

---

## 4. Specifications

The specification, with the integration guide for game authors, is `PLAYNET-PROTOCOLS.md`. This section keeps the reasoning.

**(a) MSXG, invitations over IRC.**

```
MSXG1 INVITE  <game> <profhash8> <token>
MSXG1 ACCEPT  <token> <candidates>
MSXG1 GO      <token> <candidates>
MSXG1 DECLINE <token> busy|declined|unknown-game|profile|no-mapper
MSXG1 CANCEL  <token>
```

`profhash8` is the CRC-32 of the GPF body (8 hex digits), read from the GPF header; neither implementation computes it at run time.
The candidates are up to three `ip:port` (LAN, public). The MSX side uses the same timeouts as the Pi (120 s and 180 s), counted with
`JIFFY`.

**(b) MSXNP, peer-to-peer UDP.** A 13-byte-header game packet and a 14-byte control datagram, with these properties:
- `HELLO` carries the profile CRC-32 and the PLAYNET protocol version. The profile CRC covers the game stub too, so "same patches, same
  engine" is checked on the wire. A mismatch is status 2, "different game data".
- The dead-peer timer starts at the first game packet received; a separate 60 s "start" timeout runs from READY to the first game packet.
- **BYE** is a control datagram sent a few times when a player presses Ctrl+Shift+F5, so both sides end the game at once instead of
  waiting 15 s for the dead-peer timer.

Times on the wire stay in milliseconds. The MSX measures round trip in jiffies and converts to frames with the same rule on both
implementations (`ceil(rtt/2 / 20 ms) + 2`, clamped to 2..6). The leader's value wins, whatever its implementation.

**(c) Session record** (256 bytes in `PLAYNET.SES`; the first 40 bytes from the Pi), laid out identically on both paths: magic `PNS1`,
token, seat, link, local UDP port, profile CRC-32, game id, opponent's nick, then state and result code, and for TCP/IP the opponent's
candidates, the nick and the rooms.
- Pi path: the chat agent keeps it, and `PLAYNET` asks the Pi for it with `playnet session`. The candidates stay on the Pi, which owns
  the socket.
- TCP/IP path: `MCHAT /T` writes `PLAYNET.SES` in the current directory just before it exits, so the keyboard buffer only needs
  `PLAYNET /T`. The NAT mapping learned by STUN survives because `PLAYNET` opens **the same local UDP port** a few seconds later (home
  routers keep UDP mappings for 30 s or more). The port is chosen at random in 40000-49999 for each session.

**(d) GPF, the compiled profile** (5.3).

---

## 5. Architecture

### 5.1 Components

| Component | Where | Role |
|---|---|---|
| `PLAYNET.COM` | `software/Client/src/playnet/` | The generic loader. Session, profile, ROM check, RAM image, connect, start, and the return to MSX-DOS. |
| `PLAYNET.OVL` | same | Netcore, the TCP/IP session engine, loaded into a mapper segment by `PLAYNET /T`. |
| Stub engine | `software/Client/src/playnet/engine/` | The lockstep engine, shared by every game, copied into each build. |
| Transports | `transport_msxpi.asm`, `transport_unapi.asm`, `transport_hybrid.asm` | The code behind the stub's transport vector. |
| `games_local.c` | with `mchat_local.c` | The C twin of the Pi's invitation logic, in `MCHAT /T`. |
| `msxpi_netplay.py`, `msxpi_games.py` | the Pi server | The Python session engine and invitation logic, and the `playnet` MSXPi command. |
| Game packages | `software/ROM-Patcher/profiles/<id>/` | One `msxpi-rom-patch` package per game, compiled to `software/target/games/<ID>.GPF`. |

### 5.2 The four specifications

See section 4. They are the contract between the Pi and the MSX implementations, and the conformance tests (5.7) check both.

### 5.3 Game profiles: ROM-Patcher packages, compiled to GPF

**Source: an `msxpi-rom-patch` package**, one directory per game under `software/ROM-Patcher/profiles/<id>/`, next to the music
packages. It holds `profile.json`, `src/` (the game glue), `rebuild.py`, and `assets/stub.bin` (built, hashed). The patch list is
written as file offsets with expected bytes.

**Format version 2** (`FORMAT.md`; `patch_rom.py` accepts versions 1 and 2):

| Change | Why |
|---|---|
| `music`, `sounds` and `defaults` move under an optional ABI section. A package declares the ABIs it uses (`"abi": ["msxpi-music-v1"]`, `["msxpi-netplay-v1"]`, or both). Version 1 files are read as "music ABI". | A netplay game has no music configuration (R11) |
| `source.crc32` is added next to `source.sha256` | The MSX checks the ROM with CRC-32 (well under a second). The Pi and the PC tools keep checking SHA-256. Expected bytes under every patch add a second check. |
| `output.target` is `rom-file` (as for msxarch) or `ram-image` (PLAYNET: no patched ROM is ever written to disk) | Netplay builds the image in RAM |
| New ABI section `netplay` | What PLAYNET needs beyond layout and patches |

The `netplay` section declares the title and roles, the image host (`plain`, or `mapper-ram` later), the stub's load address and entry
points, the transport area, the game RAM ranges, the address of the game's H.KEYI handler, and how to start the game. For Soccer the stub
is loaded at C100h, the transport area is C500h-C6FFh, and the game RAM is D500h-D5FFh and E000h-F37Fh (measured, 8.1). The full field list is in
`PLAYNET-PROTOCOLS.md` section 7.2.

Most per-game addresses (frame counter, sound tick, pad readers, check region) are **compiled into the game's stub asset** by its
`rebuild.py`, as the music runtimes are. The ABI section holds only what the loader itself needs. This also settles P7 and removes the
need for a relocatable stub.

**GPF** is the compiled binary form of a v2 package with the netplay ABI: header, ABI block, layout, patches with expected bytes, and the
embedded assets. It is about 1-2 KB for Soccer. `patch_rom.py --gpf` writes it after the same validation as a ROM build.

- The **loader checks every GPF itself**, whether it came from the Pi or from disk: the body CRC, that the source size and CRC match the
  ROM, the layout and patch bounds, the expected bytes, the stub and transport area inside free RAM and outside `game_ram`, and sizes.
- **Names and places.**
  - Pi: `games/*.GPF` plus `index.txt`, under the MSXPi home directory. `update.sh` downloads `index.txt`, then each listed file whose
    SHA-256 changed, checks it and replaces it atomically. It never touches files that are not in the index, so a player's own GPF placed in `games/`
    survives updates. A player who wants to change an official game gives the changed copy another id.
  - MSX: `GAMES\*.GPF` under MSX-DOS 2 or Nextor, and the current directory under MSX-DOS 1 (no subdirectories).
  - The files ship in the release archive and on the disk images. An MSX without a Pi cannot download them (HTTPS), so adding a game
    means copying one file.
- A player on an older profile gets `DECLINE ... profile` and a line telling them to update. That replaces a hand-kept version number.
- `build_games.py` compiles every netplay package into `software/target/games/<ID>.GPF` and writes `index.txt`
  (`<sha256>  <ID>.GPF`). How a player adds a game, and how an author writes a package, is in `software/target/games/README.md` and
  `PLAYNET-PROTOCOLS.md`.
- The Soccer package is verified by building the patched RAM image the old way and the new way and comparing them byte for byte.

### 5.4 `PLAYNET.COM`, the generic loader

```
PLAYNET            session from the Pi (MSXPi link)
PLAYNET /T         session from PLAYNET.SES (TCP/IP; a memory mapper is required, checked first)
PLAYNET /T id role lport ip:port[,ip:port]   manual start (LAN, VPN, forwarded port, tests) - no chat needed
```

It is **one program**. The TCP/IP session engine (netcore) is a separate overlay, `PLAYNET.OVL`, loaded into a mapper segment only with
`/T`, so `PLAYNET.COM` stays small enough for the Pi path on a 64 KB MSX without a mapper. Its code and the bounce buffer stay in page 0
(0100h-3FFFh), and the image goes straight to 4000h-BFFFh.

Phases, all in MSX-DOS with normal interrupts:

1. **Session.** Read the record (from the Pi or the file). Refuse a stale token, or a record older than the launch timeout.
2. **Profile.** Fetch it from the Pi (`playnet profile <id>`) or read `<ID>.GPF`. Check it (5.3), and check that its CRC equals the
   session's profile hash.
3. **Image.** Open the ROM named by the package, check its size and CRC-32, and build the RAM image from the layout and patches,
   checking every expected byte. The image goes through the image host (5.9); for `plain`, pages 1-2.
4. **Footprint check** (TCP/IP). Find the page-3 addresses the stack uses (the hook target read from H.TIMI, the RAM helper address
   from EXTBIO, the mapper routine table) and refuse with a clear message if any of them falls where the game would overwrite it (R6).
5. **Save for the return** (Pi path, 5.8). The DOS system area goes to the Pi. On the TCP/IP path nothing is saved, because the game
   gets a page 3 of its own.
6. **Connect.** The screen shows "Connecting to NICK... RTT 80 ms, delay 4".
   - Pi path: the Pi's session engine, driven by status polls from the loader.
   - TCP/IP path: netcore opens the port, punches, checks the profile with HELLO, measures the round trip and runs SETUP/ACK.

   A failure returns to MSX-DOS with the reason, and records it in the session. Nothing has been overwritten yet.
7. **Start.** Install the stub asset and the transport into `transport_area` and, on the TCP/IP path, switch to the game's page 3.
   Start the game as the profile says.

The image is built and checked **before** connecting, so a slow disk does not use up the opponent's timeouts. Both sides start the game
within about a second of READY, and the lockstep stall absorbs the difference.

### 5.5 In-game runtime

**Game stub (both paths).** Built per game from the shared engine and the game glue: the lockstep engine plus a Ctrl+Shift+F5 check
(two keyboard-matrix reads per frame). It reaches the network only through the **transport vector** at `transport_area`: `XCHG` (send
and receive in one call, so the native path keeps one C9 transaction per poll), `XEND(reason)`, and `XIRQ` (the target of the game's
patched H.KEYI hook). `XEND` starts the return (5.8). The contract is in `PLAYNET-PROTOCOLS.md` section 10.

**Native transport (Pi path).** One opcode-C9 transaction per `XCHG`, 458 bytes. The Pi's session engine does the rest.

**TCP/IP transport (no host, mapper required).**

- The transport is 346 bytes in `transport_area` (512 bytes, which also holds a 128-byte buffer for the UNAPI calls).
- **The game gets a page-3 segment of its own.** The loader copies MSX-DOS's page 3 into a new segment and switches to it, so the game's
  RAM, its stack and its hooks never touch MSX-DOS's. This matters because the TCP/IP stack keeps its state in MSX-DOS's work area inside a
  typical game's RAM (measured, 8.2).
- On each `XCHG` the transport switches page 3 back to MSX-DOS's segment (the transport is installed at the same address in both), maps
  netcore's segment into page 2, runs it with interrupts on, and switches back. Only registers cross a page-3 switch: the packets go
  through netcore's I/O block in page 2.
- netcore's stack is under MSX-DOS's TPA top. A RAM-based implementation maps its own segments into pages 1 and 2 while it runs,
  and the transport records and restores the page-2 segment around the call.
- **The stack's timer.** A stack that works from a timer routine (InterNestor Lite; any implementation in RAM) needs its H.TIMI hook
  called. The game's own H.KEYI handler reads the VDP status, so the BIOS never does it. The transport calls MSX-DOS's H.TIMI hook itself
  with interrupts off, once per interrupt period of the game, and not when an interrupt has already run it during a call. It does not
  chain the hook on every frame, because that costs 38-44 % of a frame (8.4). `/S1` forces the call, `/S0` turns it off.
- **The tick counter.** The transport reads MSX-DOS's `JIFFY` before and after the call and returns the difference, which the engine
  adds to the game's interrupt count. `XIRQ` counts ticks as the engine's clock and **never writes `JIFFY`**, because a game that reads
  `JIFFY` must see what it would see on a cartridge, or the two machines drift. `XIRQ` returns at once while a call is in progress (an
  interrupt arrived with the wrong pages mapped, measured in 8.5), and otherwise jumps to the game's handler. It needs one patch per
  game: the operand where the game installs its H.KEYI hook points to `XIRQ`, and the handler address goes in the ABI. For a Konami
  cartridge that is the standard `ld a,C3h / ld (FD9Ah),a / ld hl,HANDLER / ld (FD9Bh),hl` sequence (Soccer: 4090h, handler 402Eh).
- A ROM-based implementation (GR8NET) is called with CALSLT and needs no timer chaining.
- netcore is **one C module used twice**: `PLAYNET /T` maps the segment and calls it for the connect phase in MSX-DOS, and the transport
  calls it during the game. It uses no DOS calls, only UNAPI, and `JIFFY` or the transport's tick for time.

**Hybrid transport (link 2).** `XCHG` is the MSXPi transaction; every eighth call it also serves the chat connection through the overlay.
It is for an MSX with both an MSXPi and a TCP/IP stack.

### 5.6 `MCHAT /T` as a chat agent

- `games_local.c` is a C port of `Invites`:
  - the commands and private `MSXG1` handling (hidden from the chat, as `PCH1` is),
  - expiry with `JIFFY`,
  - `/games` from the GPF headers,
  - candidates: the stack's LAN address, `GAMEADDR` from `MCHAT.INI`, and one STUN binding request on the session port,
  - `DECLINE ... no-mapper` when the machine has no mapper.
- It sets bit 0 of header byte 22 and answers `mchat launch` with `PLAYNET /T` after writing `PLAYNET.SES`. `mchat.c` itself does not
  change.
- **The IRC connection does not stay open through a game.** Keeping it (resident, with the engine answering `PING`s) works, but
  measured it costs 3-27 % of the frame rate on the TCP/IP link and 12-54 % on the hybrid link, and the open connection alone about 4 ms
  a frame (`PLAYNET-TCPIP-PERFORMANCE.md` 5.6a). `AWAY` and `PART` do not remove the keep-alive `PING`s. So `MCHAT /T` sends `QUIT` before
  handing over, and on return connects again with the same nick and joins the default room. The other rooms are not rejoined and the
  scrollback from before the game is not kept.
- The invitation logic and netcore's protocol state machine are written as **portable C** (no SDCC-only constructs, I/O passed in as
  functions). They compile with gcc on the PC, and the Python tests drive them against `Invites` and `Netplay` over real localhost UDP.
  That is the mixed-match conformance test (R10), and it needs no emulator.
- **Memory (R9).** The agent and its glue cost about 8 KB. `MCHAT /T` keeps its scrollback (7.2 KB) and its user lists (1.1 KB) in a
  mapper segment of its own (TCP/IP needs a mapper anyway), copied in and out at 4000h with interrupts off. The image ends at C35Ch,
  which fits all three measured TPA tops, C806h with 426 bytes to spare beyond the 768 kept for the stack (8.7).

### 5.7 Mixed matches

A Pi chat and a `/T` chat meet in the same channel and exchange `MSXG1`. The Pi's socket and the MSX's UNAPI socket punch to each other
with MSXNP, and the leader's delay is used. No special code is needed. Every change that touches a protocol is accepted only with a
mixed test: the conformance tests (5.6) on the PC, and `SCENARIO=mixed` (one Pi node, one TCP/IP node) on the two-emulator rig. The
specification also states:
- 50 Hz and 60 Hz machines run at the slower rate (lockstep). Music tempo follows the game frame, not wall time.
- LAN candidates let two players behind the same router meet without hairpin NAT.

### 5.8 Ending a game without a reset

**What ends a game.** Ctrl+Shift+F5 on either machine, a BYE from the opponent, the dead-peer timeout, or a desync (in release builds the
stub ends the game; test builds only record the frame). Each ends in `XEND(reason)` on both machines, and the reason is recorded in the
session.

**Pi path.**
- The game runs with the BIOS ROM in page 0, so MSX-DOS's page-0 RAM is untouched, and `PLAYNET.COM` is still there.
- Pages 1 and 2 held the game image; that was the TPA, so nothing has to be put back.
- Page 3 from `HIMEM` to FFFFh is destroyed: the DOS and disk work areas, the hooks and the BIOS variables. The loader saves it to the
  Pi before the game starts. The save starts at `HIMEM`, or lower where the game's RAM reaches below `HIMEM` (MSX-DOS 2 keeps code and data
  between the TPA top and `HIMEM`, measured in 8.2). At most 16 KB are saved.
- `XEND` puts back MSX-DOS's slot registers and jumps to `PLAYNET.COM`'s return routine, which restores the area from the Pi, re-initialises the
  screen (`INITXT` or `INIT32`), types `MCHAT` and Enter into the keyboard buffer, and warm-starts MSX-DOS. The chat never stopped on the
  Pi, so `MCHAT` shows "Game with X ended (reason)".

**TCP/IP path.** The game ran in a page 3 of its own, so MSX-DOS's was never touched. `XEND` switches back to it, gives the two
segments back, and types `MCHAT /T`. `MCHAT /T` reads the result from `PLAYNET.SES`, reconnects to IRC (5.6) and reports how the game ended.

**Fallback.** If nothing was saved, or the restore fails (link error, wrong header or length), the machine goes back to the game's slots,
wipes the `AB` header of the RAM image and resets. A game started without the chat has no session on the Pi, so its save is refused and
it always ends this way.

### 5.9 Room for MegaROMs (not in the first release)

Plain 16 KB and 32 KB ROMs come first, but nothing should block MegaROMs, since TCP/IP players have mappers. What keeps the door open:

- **Format.** `msxpi-rom-patch` already speaks in file offsets, has a `layout` that can move banks and append assets, and records
  `output.mapper` (`ASCII16` and `Konami` packages exist for music). A MegaROM package only adds `image_host: "mapper-ram"`.
- **Image host.** The loader builds the image through an interface (allocate, write at a file offset, map for start), not by writing to
  4000h directly. `plain` is the first implementation. `mapper-ram` puts the image in mapper segments and installs page-3 bank
  handlers, reusing the technique msxarch and EXECROM use: `mapper_detect.patch_bank_switches` turns `LD (nn),A` bank selects into calls
  to handlers in page 3. In a package those conversions are ordinary patches with expected bytes, produced once by the author with that
  tool. The MSX never scans the ROM.
- **Runtime.** The transport restores the page-2 segment the game has selected, which the bank handlers keep up to date. The footprint
  check already covers the handler area.
- **Known hard cases**, to be solved then:
  - 8 KB-bank mappers (Konami, ASCII8) on a 16 KB-granular memory mapper,
  - SCC sound,
  - games that need more RAM than pages 1-2 leave free,
  - 128 KB and larger images on a 64 KB Pi-path machine (not supported: a MegaROM implies a mapper).

---

## 6. Where things are

| Area | Files |
|---|---|
| Specification and author's guide | `documents/PLAYNET-PROTOCOLS.md` |
| Package format | `software/ROM-Patcher/FORMAT.md`, `patch_rom.py` (version 2, `--gpf`; version 1 packages still build) |
| Game packages and GPFs | `software/ROM-Patcher/profiles/<id>/`, `build_games.py`, `software/target/games/*.GPF`, `index.txt`, `README.md` |
| Loader, engine, transports, netcore | `software/Client/src/playnet/` |
| Chat agent on the MSX | `mchat_local.c`, `games_local.c` |
| Pi server | `msxpi_games.py`, `msxpi_netplay.py`, `msxpi_chat.py` and the `playnet` MSXPi command |
| Updates | `software/Server/Setup/update.sh`, `msxpi-setup.sh`, `msxpi-windows-setup.ps1` |
| Tests | `test_gpf.py` (v2 validation, Soccer byte-for-byte equivalence, v1 packages unchanged), `test_netcore.py` and `test_games_local.py` (C against Python conformance), `test_update_games.py`, and the rig scenarios `chat`, `mixed`, `tcp` and the return-to-chat scenarios on both paths |

---

## 7. Implementation status

The design is implemented and tested on the emulator rig, except the real-hardware run.

| Step | What | Result |
|---|---|---|
| 1 | Specifications, and the package of a second game on paper (Yie Ar Kung-Fu) | written |
| 2 | ROM-Patcher v2, the Soccer package, the GPF compiler | The Soccer image is byte-identical to the old loader's. The four music packages build identical ROMs. |
| 3 | Pi side: GPF registry, profile hash in MSXG, HELLO fields, P3, BYE, the `playnet` command | server tests pass |
| 4 | `PLAYNET.COM`, Pi path | 3001 identical frames, with and without 50 ms lag, 8 % loss and 20 ms jitter; no desync; a node leaving at frame 600 ends the game on both |
| 5 | Return without a reset, Pi path | Ctrl+Shift+F5 on one node brings both back to `MCHAT` with the result line; 8 KB saved and restored in under a second |
| 6 | Measurements (section 8) | results in 8a |
| 7 | netcore and `PLAYNET.OVL` | `SCENARIO=mixed` (MSXPi node against InterNestor Lite node) and two InterNestor Lite nodes: identical frames, no desync, and a return to MSX-DOS without a reset |
| 8 | `MCHAT /T` agent | invitation, game, and return to the chat on two InterNestor Lite nodes, with identical frames and no desync |
| 9 | `update.sh`, the index, "how to add a game" | done |

Sound needed a fix on the way: ticking the sound driver once a frame played Soccer's music at 20-39 ticks a second instead of 60. The
game waits on the driver's state, so ticking it per interrupt would desync; the frame record carries player 1's interrupt count and both
machines tick that many times, which measures 60 ticks a second.

**Still open:**
- A real Pi with a real MSX that has a GR8NET or ObsoNET card.
- `MCHAT /T` on a machine whose TPA top is C806h (such as the Canon V-25 with the MSXPi TCP/IP driver). It fits on paper (8.7) but has not
  been run there.
- The `mapper-ram` image host and a first MegaROM package (5.9).

---

## 8. Measurements

These decided details of the TCP/IP path. They were taken on openMSX (Canon V-25) with `Client/tests/soccernet/measure.sh` (one machine:
the prompt, then each install command; `BOOT=nextor` for Nextor 2.10 on a MegaFlashROM SCC+ SD) and `run_native.sh` with `EXTRA_TCL` for
the game (watch scripts). The numbers are emulated.

### 8a. Results

| | Result | What it decides |
|---|---|---|
| 8.1 Game RAM in C000h-DFFFh | The original cartridge writes **nothing** there in 5 minutes of title and demo. Under PLAYNET, a full 3000-frame match writes there only at INIT: 16 pushes at D55Eh-D5xxh, which are the loader's own stack (SP-relative, so always in the TPA). | C000h-DFFFh is free during the game. Soccer's `game_ram` D500h-D5FFh range is the loader stack, not game data. |
| 8.2 Where the stacks live, and the save size | **MSX-DOS 1** (MSXPi): HIMEM DF6Eh, TPA top D606h; `MSR I` lowers the TPA top to D406h and keeps HIMEM; `INL I` hooks H.TIMI and EXTBIO to `call DDCFh` (in MSR's area). **Nextor 2.10**: HIMEM E6FEh, TPA top DC06h; `RAMHELPR I` lowers it to DB06h; `INL I` hooks H.TIMI and EXTBIO to `call E675h` (RAMHELPR's area). Between the TPA top and HIMEM: the resident code, and on DOS 2 the system's own page-3 code and data. | The Pi path's save is `HIMEM`-FFFEh, **or lower where the game's RAM reaches below `HIMEM`** (Nextor: Soccer's E000h-F37Fh is below E6FEh). Saved: 8337 bytes on DOS 1, 8191 on Nextor (from E000h). On the TCP/IP path the stack's state sits in MSX-DOS's page 3 inside the game's RAM, so the game gets a page 3 of its own and nothing is saved. |
| 8.3 Restoring the DOS area | The Pi-path return passes on **MSX-DOS 1** (disk on the MSXPi) and on **Nextor 2.10** (hard disk on the MegaFlashROM SD): Ctrl+Shift+F5 on one machine, both back in `MCHAT` with the result line. The first Nextor run hung in DOS 2's page-3 code until the save start rule above. Not covered: a real floppy (FDC) and DOS 2 on other interfaces. | The save start rule (`PLAYNET-PROTOCOLS.md` 14). |
| 8.4 The stack's timer per frame | Over the MSXPi Ethernet driver, InterNestor Lite's H.TIMI takes a **mean of 6-7 ms per interrupt (38-44 % of a 60 Hz frame), up to 120 ms**, on both DOS 1 and Nextor (without InterNestor Lite, Nextor's own H.TIMI: 0.8 ms). The MSXPi device was waiting for a real-time server, so the absolute numbers are pessimistic; the driver's polling is the cost either way. | The transport must **not** chain the stack's timer every frame during a game. It runs only while `XCHG` is in MSX-DOS's page 3 with interrupts on, once per game interrupt period. Measure again on GR8NET. |
| 8.5 Interrupts inside UNAPI calls | **Yes.** During `INL S`, 121-179 of 300-500 interrupts came while the stack's own mapper segments were in pages 1 and 2. | The `XIRQ` guard is needed, not only a precaution: it must return at once while a call is in progress. |
| 8.6 A resident TCP connection | InterNestor Lite keeps a connection opened with the resident flag through `PLAYNET /T` and a whole game, and the engine can answer the server's `PING`s during it (a 30-second game with the server pinging every 3 s and dropping after 60 s of silence: 1801 identical frames, no drop). But an open connection costs frame rate (5.6). | Not used: `MCHAT /T` quits IRC before the game and reconnects on return. The engine's keep-alive stays for a session record that carries a connection number. |
| 8.7 `mchat.com` memory | The image (data included) ends at C01Ah (48922 bytes). TPA tops with InterNestor Lite: D406h (DOS 1 + MSR: 5100 bytes for the stack), DB06h (Nextor + RAMHELPR: 6892 bytes), C806h (Canon V-25 with the TCP/IP driver: **2028 bytes**). | The agent and its glue cost about 8 KB, so the scrollback and the user lists live in a mapper segment of their own (5.6). The image ends at C35Ch and fits all three. |

### 8b. What was measured but is not fixed

- **Hardware stacks.** The interrupt and timer behaviour of GR8NET and ObsoNET is expected to be better than a software stack's (no
  timer routine to chain) but has not been measured.
- **Floppy and other DOS 2 interfaces.** The return was tested on the MSXPi disk and on Nextor over SD.

---

## 9. Decisions

| # | Question | Decision | Where it shows |
|---|---|---|---|
| 1 | Profile format | Reuse the ROM-Patcher format instead of defining another one | 5.3: `msxpi-rom-patch` v2 with an optional netplay ABI, compiled to GPF for the MSX (R11) |
| 2 | Names | `PLAYNET`, `*.GPF`, `games/` | One program, `PLAYNET.COM` (with `/T`), plus the overlay `PLAYNET.OVL`; no separate directory for local files (player files live in `games/` and the updater leaves unlisted files alone); `GAMES\` on the MSX under DOS 2 |
| 3 | Scope of the first format | Plain 16 KB and 32 KB ROMs first; MegaROMs later, and the architecture must allow them | 5.9 |
| 4 | Mapper on the TCP/IP path | Mandatory | 5.4 and 5.5: checked by `PLAYNET /T` and by `MCHAT /T` (`DECLINE no-mapper`) |
| 5 | `MCHAT /T` scrollback | The scrollback may shrink if needed; in the end it lives in a mapper segment | 5.6 |
| 6 | Mixed matches | A requirement from the start | 5.7, section 7: conformance and `SCENARIO=mixed` are acceptance criteria |
| 7 | Return to the chat without a reset | Required on all paths | 5.8: the Pi path saves and restores the DOS area; the TCP/IP path gives the game a page 3 of its own; reset is only the fallback |
| 8 | Exit key | Ctrl+Shift+F5 for every game, no per-game override | Specification 9.3 |
| 9 | Inputs wider than one byte | Supported: 1-4 input bytes per frame per game | Specification 4.4, 7.2, 11.1: a kind byte on every datagram; length-prefixed C9 packets |
| 10 | Connect timeout | 120 s | Specification 11.3 |
| 11 | Desync in release builds | End the game on both machines and show the frame number; test builds only record it | Specification 9.1 (stub flag bit 0) |
| 12 | Where the Soccer package lives | `software/ROM-Patcher/profiles/soccer/`, next to the music packages | 5.3 |
| 13 | The chat connection during a game | Close it before the game and reconnect on return, to protect the frame rate | 5.6, 8.6 |
