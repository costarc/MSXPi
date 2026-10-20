# Online games from the chat, with or without an MSXPi: assessment and design

Written 2026-10-19 as a review of `documents/HANDOVER-games-from-chat.md` (HEAD `df22a0ee` of `worktree-msx-freechat`),
with one new requirement from the user:

> The design must also support TCP/IP UNAPI (GR8NET, ObsoNET, InterNestor Lite...), where there is no host
> (Raspberry Pi or PC) to run the server side code.

Revision 2 (same day) folds in the user's answers to the first draft. They are recorded in section 9. Nothing here is implemented yet.

---

## 1. Summary

The current implementation is good engineering, but every part above the in-game stub assumes a Pi on **both** ends.
The Pi runs four things the MSX would have to do itself without one:

1. the invitation state machine (`msxpi_games.Invites`),
2. the UDP session: STUN, hole punching, HELLO/version check, RTT measurement and input delay, keep-alive and dead-peer detection
   (`msxpi_netplay.Netplay`),
3. game profile storage, validation and encoding (the agreed but unbuilt section 6 of the handover),
4. the session data handed from the chat to the game: the opponent's address and the agreed delay never reach the MSX today.

The proposal keeps everything that works and changes five things:

- **One specification, two implementations.** The IRC invitation messages, the peer-to-peer UDP protocol, the session record and
  the compiled profile become written specifications. The Pi (Python) and the MSX (C/Z80) each implement them. **Mixed matches
  (a Pi player against a UNAPI player) are a requirement from the start**, enforced by conformance tests.
- **Profiles reuse the ROM-Patcher package format** (`msxpi-rom-patch`, `software/ROM-Patcher/FORMAT.md`). It becomes version 2:
  the music section turns into one optional "ABI" section, and a new `msxpi-netplay-v1` ABI section is added beside it. There is no new
  patch format. For the MSX, a package compiles to one binary file, `<ID>.GPF`.
- **The session is set up before the game starts, not inside it.** One generic loader, `PLAYNET.COM`, connects to the opponent in
  the MSX-DOS phase. Only then does it start the game. The resident stub does only the per-frame exchange.
- **On the UNAPI path (a memory mapper is mandatory there), the network code runs in a mapper segment**, loaded from an overlay
  file. A small page-3 shim maps it in for each call, and an interrupt trampoline keeps the game's handler from running while a page is
  switched away.
- **A game ends without a reset, on both paths.** The loader saves the DOS system area before the game starts. The end of a game
  (Ctrl+Shift+F5, the opponent leaving, or a lost connection) restores it and returns to MSX-DOS, which then runs `MCHAT`.

Plain 16/32 KB ROMs come first. Nothing in the format, loader or runtime assumes "plain", so MegaROMs can follow (section 5.9).

---

## 2. What exists, and who does each job without a host

| Job | Today (Pi on both ends) | With no host (UNAPI) | Status |
|---|---|---|---|
| IRC chat | `msxpi_chat.py` on the Pi | `mchat_local.c` in `MCHAT /t` | exists |
| `/play`, `/accept`... and `MSXG1` messages | `msxpi_games.Invites` (Python) | **nothing**: `/play` is "Unknown command", and an incoming `MSXG1 INVITE` is shown as a private message | gap G1 |
| Game list | `DEFAULT_GAMES` + `msxpi.ini` | **nothing** | gap G3 |
| UDP socket, LAN + STUN candidates | `Netplay.open/candidates` | **nothing** (the UNAPI calls are proven in `udptest.asm`) | gap G2 |
| Hole punching, HELLO/version, leader election, RTT, delay, SETUP/ACK | `Netplay._pump/_on_ctl` | **nothing** | gap G2 |
| Keep-alive, dead-peer detection (15 s) | `Netplay` | **nothing** (and `JIFFY` stops advancing while the game runs, see G6) | gap G2, G6 |
| Session hand-off chat -> game | the Pi keeps it; the MSX only gets `SOCCERNET H` (37-character limit) | **nothing**: the MSX program exits, so its state is lost | gap G4 |
| Profile store, validation, encoding | planned on the Pi only | **nothing** | gap G3 |
| Loader: ROM check, patching, stub install | `soccernet.asm`, hard-coded for one game | same program, but with the native transport only | gap G5 |
| Per-frame exchange in the game | stub + opcode C9 (polled I/O ports, page 3 only) | `unapi.tmpl.inc`, a draft that uses the page-1 switching shown to hang | gap G5, G6 |
| End of a game, back to the chat | reset; the chat keeps running on the Pi | reset, which also unloads INL and drops the IRC connection | gap G7 |
| Profile updates | `update.sh` on the Pi (planned) | no TLS on a Z80, so GitHub raw cannot be fetched from the MSX | gap G8 |

---

## 3. Assessment of the current implementation

### What is sound and is kept

- **Lockstep core.** Input-only exchange, redundancy of 8 inputs per packet, stall on missing input, sound ticked once per frame,
  R-register coin flips replaced, desync checksum. This is proven over 3001 frames with lag, jitter and loss. It does not depend on
  the transport.
- **The chat contract.** The packet header flags (byte 22), `mchat launch`, and stuffing the keyboard buffer. Both links share the same
  256-byte packets, so `mchat.c` does not care which link is in use. That pattern is what makes the no-host path cheap.
- **The invitation protocol shape**: tokens, timeouts, one game at a time, candidate exchange in ACCEPT/GO, no relay.
- **The peer UDP protocol** (13-byte game packet, 14-byte control datagram). It is small enough to implement in Z80/C. The
  specification generalises the game packet to 1-4 input bytes per frame, and adds a kind byte to every datagram.
- **The test assets.** `test_netplay.py`, `test_games.py`, the two-emulator rig, and `cmp_pair.py`.
- **ROM-Patcher conventions** (from the music work): file offsets instead of CPU addresses, expected bytes checked under every patch,
  code shipped as hashed assets built from sources in the package, a per-game `rebuild.py`, and Ctrl+Shift+F5 as the exit key.

### Problems that exist even without the new requirement

| # | Problem | Where |
|---|---|---|
| P1 | The handshake runs in the stub at game frame 0, inside the game's interrupt handler. The title screen stays blank while it waits, and the code uses stub bytes that are already at the limit (`ASSERT stubEnd <= $F300`). | `stub.tmpl.asm` `connect` |
| P2 | `HELLO` carries a 1-byte version that a human keeps by hand. Lockstep really needs "same patches, same engine", which a version number does not guarantee. The handover's profile hash fixes this in the chat, but not on the wire: a game started by hand bypasses the check. | `msxpi_netplay.py` CTL, `msxpi_games.py` |
| P3 | The dead-peer timer starts from SETUP/ACK, not from the first game packet. A slow loader (a floppy, a long ROM check) on one side spends part of the 15 s before the game has even started. | `Netplay._pump` |
| P4 | The launch command is limited to 37 characters (the keyboard buffer), so no session data can travel with it. That is fine while the Pi holds the session, and fatal without one. | `CMD_OK` |
| P5 | The trampoline writes `RET` over H.TIMI (`FD9F`) unconditionally. That removes INL's timer hook, so INL stops working. | `soccernet.asm` `trampSrc` |
| P6 | "Profiles are data, not code" is weaker than it sounds: byte patches and assets *are* Z80 code. The real trust boundary is where a profile comes from (the repository, its hash in the index), not the format. Bounds and expected-byte checks protect against a corrupt or mismatched profile, not a malicious one. ROM-Patcher already works this way; the netplay ABI should say so too. | handover 6.4 |
| P7 | Per-game code is not fully declarative. The Soccer patch at `B028h` replaces `ld a,r; and 6` with `call rng2; nop`, and `rng2` contains the game's own `and 6`. ROM-Patcher solves this the right way: the per-game runtime is an asset assembled from shared sources plus game glue. Netplay should do the same. | `stub.tmpl.asm` `rng1/rng2` |
| P8 | Ending a game is a reset (`fatal`). On every path, that throws away MSX-DOS, and on the UNAPI path also the TCP/IP stack and the IRC connection. | `stub.tmpl.asm` `fatal` |

---

## 4. Gaps for the no-host requirement

- **G1. Invitations in `MCHAT /t`.** No `/play`, `/accept`, `/decline`, `/cancel` or `/games`. `MSXG1` private messages are shown as
  text instead of being handled. `mchat.c` `fetch_launch()` returns early when `link_tcp` is set. A Pi player who invites a `/t`
  player sees the invitation expire, and the `/t` player sees a strange private message.
- **G2. No session engine on the MSX.** Nothing on the MSX does UDP_OPEN, STUN, LAN address, punching, leader election, RTT,
  delay, SETUP/ACK, keep-alive or dead detection. All of it lives in `msxpi_netplay.py`.
- **G3. No profiles without a host.** The registry and the planned profiles exist only as Python on the Pi. There is no
  binary format the MSX can read, and nowhere on the MSX to list games from.
- **G4. No session hand-off.** `MCHAT /t` exits before the game starts. The opponent's candidates, the local UDP port (the NAT
  mapping that STUN learned), the token, the role and the profile hash all have to survive that exit.
- **G5. The loader is single-game and native-only.** `SOCCERNET.COM` has the patch table compiled in and only knows opcode C9.
- **G6. Running a UNAPI stack under a game that owns the machine.**
  - Page 1 (and page 2) hold the game. The UNAPI implementation, and our own code if it is larger than page 3 allows, must be
    mapped in for each call. The game's interrupt handler lives in page 1. So an interrupt during a call jumps into whatever
    is mapped there at that moment, unless H.KEYI points to page 3 and checks.
  - The game reads the VDP status in its own H.KEYI handler, so the BIOS never calls H.TIMI. INL does its processing from
    H.TIMI, and `JIFFY` does not advance. Timeouts in INL and in our code both stop.
  - The stub uses the game's stack, which reaches F30Ch, a few bytes from the stub. Calling C code on that stack would overwrite the stub.
  - INL's page-3 code (`DDCFh` on the test rig), the UNAPI RAM helper and the DOS2 mapper routines are in page 3 too. The game
    clears `E000h-EFFFh`, and nobody has measured whether it writes to `C000h-DFFFh`.
- **G7. The end of a game.** See P8. On the UNAPI path the nick also stays taken on the IRC server until it times out (several minutes),
  and the result of the game is lost.
- **G8. Distributing profiles to MSX-only users.** The MSX cannot fetch from GitHub raw (HTTPS only, no TLS on a Z80). MSX-DOS1 has
  no subdirectories.
- **G9. Memory for `MCHAT /t`.** `mchat.com` already ends near `C020h`. With INL loaded, the TPA top can be `C806h`, which leaves
  about 2 KB. The invitations, UDP/STUN and profile listing in C are estimated at about 3 KB. It does not fit as it is (decision 5 in
  section 9: scrollback may drop to 24 rows a room).
- **G10. Mixed matches.** Today the "peer protocol" is whatever `msxpi_netplay.py` happens to do. Two implementations need it written
  down, plus a conformance test between them.
- **G11. The ROM-Patcher format cannot be used as it is.** Version 1 requires the `music`, `sounds` and `defaults` fields, describes its
  output as a new ROM file, and identifies the input by SHA-256 only. Computing SHA-256 over 32 KB takes several seconds on a Z80, and
  much longer over a MegaROM.

---

## 5. Proposed architecture

### 5.1 Roles, independent of where they run

```
             Pi host (MSXPi link)                     MSX host (UNAPI, mapper required)
            ---------------------                    ---------------------------------
CHAT AGENT  msxpi_chat.py + msxpi_games.py           mchat_local.c + games_local.c      <- MSXG over IRC
SESSION     msxpi_netplay.py (Python, Pi socket)     netcore (C, PLAYNET.OVL, segment)  <- MSXNP over UDP
PROFILES    games/*.GPF, served to the MSX           *.GPF on the MSX disk              <- GPF (from msxpi-rom-patch v2)
LOADER      PLAYNET.COM, session from the Pi         PLAYNET.COM /T, session from PLAYNET.SES
IN GAME     game stub + native transport (C9)        game stub + UNAPI transport (shim -> netcore)
GAME END    restore DOS area (segment or Pi)         restore DOS area (segment), INL and IRC survive
```

The game stub (the lockstep engine plus the game's glue, one asset per game), the loader's ROM/profile/patch code and the end-of-game
restore are **the same** in both columns. Only the transport behind the stub's vector, and where the saved DOS area is kept, differ.

### 5.2 Four specifications (now written: `documents/PLAYNET-PROTOCOLS.md`)

The specification, with the integration guide for game authors, is in its own document. Where it differs from this section in a detail,
the specification wins. This section keeps the reasoning.

**(a) MSXG, invitations over IRC.** This is the current `MSXG1`, with the version replaced by the profile hash. Nothing has shipped
yet, so it changes in place:

```
MSXG1 INVITE  <game> <profhash8> <token>
MSXG1 ACCEPT  <token> <candidates>
MSXG1 GO      <token> <candidates>
MSXG1 DECLINE <token> busy|declined|unknown-game|profile|no-mapper
MSXG1 CANCEL  <token>
```
`profhash8` is the CRC-32 of the GPF body (8 hex digits), read from the GPF header. Both implementations read it and neither
computes it at run time. The candidates are up to 3 `ip:port` (LAN, public). The MSX side uses the same timeouts (120 s / 180 s),
counted with `JIFFY`.

**(b) MSXNP, peer-to-peer UDP.** This is the current wire format, frozen and written down, with these changes:
- `HELLO` carries `a = profile CRC-32` and `b = PLAYNET protocol version`. The profile CRC also covers the game stub (it is an asset
  inside the profile), so "same patches, same engine" is checked on the wire too. A mismatch is status 2, "different game data" (P2).
- The dead-peer timer starts at the first game packet received, with a separate "start" timeout of 60 s from READY to the first game
  packet (P3).
- **BYE**: a control datagram (new type 6) sent a few times when a player presses Ctrl+Shift+F5. Both sides end the game at once
  instead of waiting 15 s for the dead-peer timer.

Times on the wire stay as they are. The MSX measures RTT in jiffies and converts to frames with the same rule
(`ceil(rtt/2 / 20 ms) + 2`, clamped to 2..6). The leader's value wins, whatever its implementation.

**(c) Session record** (32 bytes, the same layout from the Pi and from the file):
```
0  'PNS1'          4  token (4 bytes)       8  seat (0/1)      9  transport (0 native, 1 unapi)
10 local UDP port  12 profile CRC-32        16 game id (8 chars, upper case = GPF file name)
24 peer nick (8, truncated, display only)
-- UNAPI only, appended: n (1), n x (ip 4, port 2); IRC connection number, nick, room names (for the return, 5.8)
-- written back by PLAYNET: result (connect failed / different game data / ended / opponent left / lost / desync)
```
- Pi path: the chat agent keeps it, and `PLAYNET` asks the Pi for it with an MSXPi command (`playnet session`). The candidates stay on
  the Pi, which owns the socket.
- UNAPI path: `MCHAT /t` writes `PLAYNET.SES` in the current directory just before it exits. The keyboard buffer then only needs
  `PLAYNET` or `PLAYNET /T`. This removes the 37-character problem (P4, G4). The NAT mapping learned by STUN survives because
  `PLAYNET` opens **the same local UDP port** a few seconds later. UDP mappings on home routers last 30 s or more. The port is
  chosen at random in 40000-49999 for each session.

**(d) GPF, compiled profile** (section 5.3).

### 5.3 Game profiles: ROM-Patcher packages, compiled to GPF

**Source: an `msxpi-rom-patch` package**, one directory per game under `software/ROM-Patcher/profiles/<id>/`, next to Goonies, Nemesis,
Arctic and Vampire. It holds `profile.json`, `src/` (game glue), `rebuild.py`, and `assets/stub.bin` (built, hashed). The Soccer package
replaces `soccernet.asm`'s patch table and `rom_check.py`. The patch list is the current one, written as file offsets with expected bytes.

**Format version 2** (`FORMAT.md` is updated, and `patch_rom.py` accepts versions 1 and 2):

| Change | Why |
|---|---|
| `music`, `sounds` and `defaults` move under an optional ABI section. A package declares the ABIs it uses (`"abi": ["msxpi-music-v1"]`, `["msxpi-netplay-v1"]`, or both). Version 1 files are read as "music ABI". | G11: a netplay game has no music configuration |
| `source.crc32` is added next to `source.sha256` | The MSX checks the ROM with CRC-32 (well under a second). The Pi and the PC tools keep checking SHA-256. Expected bytes under every patch add a second check on the MSX. |
| `output.target` is `rom-file` (as now, for msxarch) or `ram-image` (PLAYNET: no ROM file is ever written, the image is built in RAM) | Netplay never writes a patched ROM to disk |
| New ABI section `netplay` (below) | What PLAYNET needs beyond layout and patches |

```json
"netplay": {
  "abi": "msxpi-netplay-v1",
  "title": "Konami's Soccer",
  "roles": ["H", "C"],
  "transport": "lockstep",                 // or "none": the game brings its own connection; then "command" is used
  "image_host": "plain",                   // plain (16/32 KB in pages 1-2) | mapper-ram (future, 5.9)
  "stub":      {"asset": "stub", "load": 49408, "entry_init": 49408, "irq": 49411},     // C100h
  "transport_area": {"address": 50432, "size": 256},                                 // C500h-C5FFh
  "game_ram": [[54528, 54783], [57344, 62335]],   // D500h-D5FFh and E000h-F37Fh (stack included), measured
  "irq_handler": 16430,                    // 402Eh: where the game's H.KEYI hook points (installed at 4090h)
  "start": "header-init"                   // start like a cartridge: jump to INIT from the image header
}
```
The `//` comments and the numbers are illustration only: real package files are plain JSON with decimal numbers, and the Soccer values
come from the measurements in section 8. For Soccer, the stub and the transport together must fit C100h-C5FFh (stub at most 1024 bytes, transport 256).

Most per-game addresses (frame counter, sound tick, pad readers, check region) are **compiled into the game's stub asset** by its
`rebuild.py`, as the music runtimes do. The stub engine sources are shared: `software/Client/src/playnet/engine/`, copied into each build.
The ABI section then only holds what the loader itself needs. This also settles P7 (the glue is part of the asset), and removes the need
for a relocatable stub.

**GPF** is the compiled binary form of a v2 package with the netplay ABI: header, ABI block, layout, patches with expected bytes, and the
assets embedded. It is about 1-2 KB for Soccer. `patch_rom.py --gpf OUT.GPF` writes it, after the same validation as a ROM build. If
given the ROM, it also checks the expected bytes against it.

```
header  'GPF1', format=1, body length, body CRC-32 (= profhash), id[8], title[24], roles[2][8],
        transport, image host, command[38] (only for transport 'none')
SOURCE  size, CRC-32
ABI     stub load/entry/irq, transport area, game RAM ranges, IRQ handler, start
LAYOUT  n x (source: input | asset index, file offset, size, destination offset)
PATCH   n x (file offset, length, expected bytes, replacement bytes)
ASSETS  n x (length, bytes)
```

- The **loader checks every GPF itself**, whether it came from the Pi or from the disk. It checks the body CRC, that the source size and
  CRC match the ROM, the layout and patch bounds, the expected bytes, the stub and transport area inside free RAM and outside `game_ram`,
  and sizes. The trust statement (P6) is in the format document.
- **Names and places** (decision 2):
  - Pi: `/home/pi/msxpi/games/*.GPF` plus `index.txt`. `update.sh` downloads `index.txt`, then each listed file whose SHA-256 changed,
    checks it and replaces it atomically. It never touches files that are not in the index, so a user's own GPF placed in `games/` survives
    updates. A user who wants to change an official game gives the changed copy another id.
  - MSX: `GAMES\*.GPF` under MSX-DOS2/Nextor, and the current directory under MSX-DOS1 (no subdirectories).
  - The files ship in the release archive and on the disk images. An MSX without a Pi cannot download them itself (HTTPS). To add a
    game, a user copies one file.
- A player on an older profile gets `DECLINE ... profile` and a line telling them to update. That replaces the version number kept by hand.
- **Before freezing ABI v1**, write the package of a second game on paper and convert Soccer. Prove the conversion by building the patched
  RAM image the old way and the new way and comparing them byte for byte.

### 5.4 `PLAYNET.COM`, the generic loader

```
PLAYNET            session from the Pi (MSXPi link)
PLAYNET /T         session from PLAYNET.SES (UNAPI; a mapper is required, checked first)
PLAYNET /T id role lport ip:port[,ip:port]   manual start (LAN, VPN, forwarded port, tests) - no chat needed
```

**One program** (decision 2). The UNAPI session engine (netcore) is a separate overlay, `PLAYNET.OVL`, loaded into a mapper segment
only with `/T`. `PLAYNET.COM` itself stays small enough for the Pi path on a 64 KB MSX without a mapper. Its code and the bounce
buffer stay in page 0 (0100h-3FFFh), and the image goes straight to 4000h-BFFFh, as today.

Phases, all in MSX-DOS with normal interrupts:

1. **Session.** Read the record (from the Pi or the file). Refuse a stale token, or a record older than the launch timeout.
2. **Profile.** Fetch it from the Pi (`playnet profile <id>`) or read `<ID>.GPF`. Check it (5.3), and check that its CRC equals the
   session's `profhash`.
3. **Image.** Open the ROM named by the package, check its size and CRC-32, and build the RAM image with the layout and patches,
   checking every expected byte. The image goes through the image host (5.9): for `plain`, pages 1-2.
4. **Footprint check.** Collect the page-3 addresses the transport needs:
   - INL's hook target, read from H.TIMI,
   - the RAM helper address, from EXTBIO,
   - the mapper routine table.
   Refuse with a clear message if any of them falls inside `game_ram`, the stub or the transport area (G6).
5. **Save for the return** (5.8): the DOS system area, to a mapper segment, or to the Pi on a machine without a mapper.
6. **Connect.** The screen shows "Connecting to NICK... RTT 80 ms, delay 4".
   - Pi path: today's flag 0x40, then status polls, moved out of the stub.
   - UNAPI path: netcore opens the port, punches, does the HELLO/profile check, RTT and SETUP/ACK.
   A failure returns to DOS cleanly with the reason, and records it in the session (file or Pi). Nothing has been overwritten yet.
7. **Start.** Install the stub asset, the transport (C9 or shim, into `transport_area`) and, on the UNAPI path, the IRQ trampoline. Keep
   INL's H.TIMI hook (P5). Start the game as `start` says.

The image is built and checked **before** connecting, so a slow disk does not use up the opponent's timeouts. Both sides start the game
within about a second of READY. The lockstep stall absorbs the difference.

### 5.5 In-game runtime

**Game stub (both paths).** Built per game from the shared engine and the game glue: the current lockstep engine, minus `connect`
(moved to the loader), plus a Ctrl+Shift+F5 check (two keyboard-matrix reads per frame). It reaches the network only through the
**transport vector** at `transport_area`: `XCHG` (send and/or receive in one call, so the native path keeps one C9 transaction per poll),
`XEND(reason)`, and `XIRQ` (the target of the game's patched H.KEYI hook). `XEND` replaces `fatal` and starts the return (5.8). The exact
contract is in `PLAYNET-PROTOCOLS.md` section 10.

**Native transport (Pi path).** Today's `xchg` over opcode C9, about 150 bytes. It is assembled position-independent, or with a
relocation table, so it can be placed at `transport_area`. The Pi changes only for the HELLO fields, P3, BYE, and serving the session,
profile and saved area.

**UNAPI transport (no host, mapper required).**

```
page 3 (transport_area, ~120 bytes)                  mapper segment N (PLAYNET.OVL), mapped at 8000h during a call
  shim:  DI; netBusy=1; save SP; SP=BFF0h            netcore (C, SDCC, linked at 8000h):
         OUT (FEh),N ; CALL 8000h+entry                 UDP_SEND / UDP_RCV via the standard dispatch
         OUT (FEh),curSeg2 ; restore SP                 (RAM helper CALL_MAP, or CALSLT, or direct)
         netBusy=0; EI                                  peer lock, keep-alive, dead timer (frames), BYE
  irq:   H.KEYI -> here (patched hook site)             IRC keep-alive: answers PING on the resident
         if netBusy: read VDP status, missed++, RET       IRC connection, discards everything else
         ticks++ ; call game handler (irq_handler)      the same code runs the connect phase in DOS
         netBusy=1; call saved H.TIMI (INL); netBusy=0
```

- netcore is **one C module, used twice**. `PLAYNET /T` maps the segment and calls it for the connect phase in DOS, and the stub calls
  it through the shim during the game. It uses no DOS calls: only UNAPI, and `JIFFY` for time.
- **Private stack** in the segment (G6: the game's stack is a few bytes from the stub).
- `curSeg2` is a variable, not a constant. With a plain ROM it never changes. With a MegaROM (5.9) the bank handlers update it, so the shim
  puts back the bank the game has selected at that moment.
- The **IRQ trampoline** (`XIRQ`) fixes three things at once: an interrupt while a page is switched away, INL's timer never being called,
  and netcore having no clock. It keeps its own tick counter and **never writes `JIFFY`**, because a game that reads `JIFFY` must see what
  it would see on a cartridge, or the two machines drift. It needs one patch per game: the `ld hl,HANDLER` operand where the game installs its
  H.KEYI hook points to `XIRQ`, and the handler address goes in the ABI. For a Konami cartridge, that is the standard
  `ld a,C3h / ld (FD9Ah),a / ld hl,HANDLER / ld (FD9Bh),hl` sequence (Soccer: 4090h, handler 402Eh).
- A ROM-based implementation (GR8NET) is called with CALSLT and needs no timer chaining. The trampoline still protects page 1.
- This retires `unapi.tmpl.inc`. `udptest.asm` remains the reference for the dispatch.

### 5.6 `MCHAT /t` becomes a chat agent

- New `games_local.c`, a C port of `Invites`:
  - the commands and private `MSXG1` handling (hidden from the chat, as `PCH1` is),
  - expiry with `JIFFY`,
  - `/games` from the GPF headers (FFIRST/FNEXT on `GAMES\*.GPF` or `*.GPF`),
  - candidates: TCPIP_GET_IPINFO for the LAN address, plus one STUN binding request on the session port (DNS_Q `stun.l.google.com`),
  - `DECLINE ... no-mapper` when the machine has no mapper.
- It sets bit 0 of header byte 22 and answers `mchat launch` with `PLAYNET /T` after writing `PLAYNET.SES`. Before exiting it marks the
  IRC TCP connection resident and does not close it (5.8). `fetch_launch()` loses its `link_tcp` guard. `mchat.c` itself does not
  change otherwise.
- Write the invitation logic and netcore's protocol state machine as **portable C** (no SDCC-only constructs, with I/O passed in as
  functions). They then compile with gcc on the PC, and the Python tests drive them against `Invites` and `Netplay` over real localhost
  UDP. That is the mixed-match conformance test (G10), and it needs no emulator.
- **Memory (G9).** Measure the real end of the image and the TPA top with INL and with GR8NET. Then cut `LROWS` from 32 to 24 (about
  -2 KB of `ltext`) if needed. That is accepted (decision 5). Splitting the program in two stays the fallback.

### 5.7 Mixed matches (required from the start)

No special code, by construction. A Pi chat and a `/t` chat meet in the same channel and exchange `MSXG1`. The Pi's socket and the
MSX's UNAPI socket punch to each other with MSXNP. The leader's delay is used. Every milestone that touches a protocol is accepted only
with a mixed test: the conformance tests (5.6) on the PC, and `SCENARIO=mixed` (one Pi node, one INL node) on the rig. The
specification also states:
- 50 Hz against 60 Hz machines run at the slower rate (lockstep). Music tempo follows the game frame, not wall time.
- LAN candidates let two players behind the same router meet without hairpin NAT.

### 5.8 Ending a game without a reset (both paths)

**What ends a game.** Ctrl+Shift+F5 on either machine (the ROM-Patcher exit key), a BYE from the opponent, the dead-peer timeout, or a
desync (always in release builds, where the stub's desync flag is set; test builds only record the frame). Each ends in `XEND(reason)` on both machines. The Pi or netcore records the reason in the session.

**What the game destroys, and what it does not.**
- The game runs with the BIOS ROM in page 0, so DOS's page-0 RAM is not touched.
- Pages 1-2 held the game image. That was TPA, so nothing has to be put back there (COMMAND.COM reloads its transient part).
- Page 3 from HIMEM to FFFFh is destroyed: the DOS and disk work areas, the hooks, and the BIOS variables. With INL loaded, that is about
  14 KB. This is what gets saved.

**Save (loader, step 5).**
- With a mapper (always on the UNAPI path, often on the Pi path): copy `[HIMEM..FFFFh]` into a segment allocated through the mapper
  routines, together with the slot registers (A8h, sub-slot FFFFh), the TPA mapper segments and SCRMOD.
- Pi path without a mapper: send the same bytes to the Pi (`playnet save`, about 14 KB: under a second on the MSXPi link). The Pi keeps
  them with the session.

**Restore (`XEND`).** A small routine copied into page 2, with its stack there too, because page 3 is about to be overwritten:
1. DI, silence the PSG.
2. Copy the saved area back: from the segment mapped in page 1, or fetched from the Pi with `playnet restore` over the I/O ports.
3. Put back the slot and mapper registers.
4. Re-initialise the screen as SCRMOD says (INITXT/INIT32), with the restored VDP register copies.
5. Put `MCHAT` and Enter in the keyboard buffer, set the page-0 slot back to RAM, and `JP 0000h` (DOS warm start).

The chat then resumes:
- **Pi path:** the chat never stopped on the Pi. `MCHAT` picks it up and shows "Game with X ended (reason)".
- **UNAPI path:** INL, its segments and its page-3 code survived (the footprint check in step 4 made sure of that). The IRC TCP
  connection stayed open, because `MCHAT /t` made it resident and netcore answered the server's PINGs during the game. `MCHAT /t` finds
  the connection number, nick and rooms in `PLAYNET.SES`, re-attaches, asks for NAMES, and reports the result. The scrollback from
  before the game is gone (it was in the TPA).

**Fallback.** If the save is impossible (no mapper and no Pi), or the restore finds a bad checksum on the saved area, it resets as today,
wiping the `AB` header of the image first. On the UNAPI path, `MCHAT /t` then reconnects. If the old nick is still held (`433`), it uses `nick_`
and asks for its nick back once the old connection times out.

### 5.9 Room for MegaROMs (not in the first release)

Decision 3: plain 16/32 KB ROMs first, but nothing should block MegaROMs, since UNAPI users have mappers. What keeps the door open:

- **Format.** `msxpi-rom-patch` already speaks in file offsets, has a `layout` that can move banks and append assets, and records
  `output.mapper` (`ASCII16` and `Konami` packages exist for music). A MegaROM netplay package only adds `image_host: "mapper-ram"`.
- **Image host.** The loader builds the image through an interface (allocate, write at a file offset, map for start), not by writing to
  4000h directly. `plain` is the first implementation. `mapper-ram` puts the image in mapper segments and installs page-3 bank
  handlers, reusing the technique msxarch/EXECROM already use: `mapper_detect.patch_bank_switches` turns `LD (nn),A` bank selects into
  calls to handlers at F9C0h-FB3Fh. In a package, those conversions are ordinary patches with expected bytes, produced once by the author
  with that tool. The MSX never scans the ROM.
- **Runtime.** The shim restores `curSeg2` (and its page-1 counterpart), which the bank handlers keep up to date. The footprint check
  already covers the handler area.
- **Known hard cases**, to be solved then and not now:
  - 8 KB-bank mappers (Konami, ASCII8) on a 16 KB-granular memory mapper (msxarch's handlers show how far that goes),
  - SCC sound,
  - games that need more RAM than pages 1-2 leave free,
  - 128 KB+ images on the 64 KB Pi-path machine (not supported: MegaROM implies a mapper).

---

## 6. Changes by file

| File | Change |
|---|---|
| `documents/PLAYNET-PROTOCOLS.md` | new: MSXG, MSXNP (with BYE), session record, GPF, `msxpi-netplay-v1` ABI |
| `software/ROM-Patcher/FORMAT.md`, `patch_rom.py` | format version 2 (optional ABI sections, `source.crc32`, `output.target`), `--gpf` compiler; version 1 packages still accepted |
| `software/ROM-Patcher/profiles/soccer/` | new package: `profile.json`, `src/` glue, `rebuild.py`, `assets/stub.bin` |
| `software/Client/src/playnet/` (new; replaces `soccernet/`) | `PLAYNET.COM`, shared stub engine, native transport, netcore (`PLAYNET.OVL`), shim, IRQ trampoline, save/restore |
| `software/target/games/*.GPF`, `index.txt` | compiled profiles (release artifacts) |
| `msxpi_games.py` | registry from `games/*.GPF`; drop `DEFAULT_GAMES`/`MSXGAME_*`; profhash in INVITE/DECLINE; session record; the launch line becomes `PLAYNET` |
| `msxpi_netplay.py` | HELLO a/b, start timeout (P3), BYE, result codes; commands `playnet session`, `profile`, `save`, `restore` |
| `msxpi_chat.py` | launch packet from the session; resume reports the result |
| `software/Server/Setup/update.sh` | `index.txt`, changed GPFs only, SHA-256 check, atomic replace, unlisted files untouched |
| `mchat_local.c` + new `games_local.c` | invitations, STUN, GPF listing, `PLAYNET.SES`, resident IRC connection and re-attach, nick-in-use recovery, `LROWS` 24 if needed |
| `mchat.c` | drop the `link_tcp` guard in `fetch_launch` |
| tests | `test_gpf.py` (v2 validation, Soccer byte-for-byte equivalence, v1 packages unchanged), C-vs-Python conformance for invites and netcore, rig scenarios `chat`, `mixed`, `tcp`, and a return-to-chat scenario on both paths |

---

## 7. Implementation order

Each step ends with something that can be shown to work. Mixed play is part of the acceptance from the first protocol step.

1. **Specifications** (`PLAYNET-PROTOCOLS.md`, which also specifies `msxpi-rom-patch` v2; `FORMAT.md` itself is updated in step 2
   together with `patch_rom.py`) and the package of a second game on paper (`PLAYNET-PROTOCOLS.md` section 6: Yie Ar Kung-Fu, from a static
   scan). *Proof:* user review. **Draft written 2026-10-19, awaiting review.**
2. **ROM-Patcher v2 + Soccer package + `--gpf`**, with the equivalence test against today's patched image. Music packages must still
   build bit-identical ROMs. *Proof:* `test_gpf.py` and the existing patcher tests.
   **Done 2026-10-19**:
   - `patch_rom.py` reads versions 1 and 2, has the netplay rules, and writes and reads GPF.
   - `profiles/soccer/` exists, and its image is byte-identical to `SOCCERNET.COM`'s on the real dump.
   - The four music packages build identical ROMs and manifests on their real dumps.
   - 38 tests pass.
   - The Soccer GPF itself is refused until step 4, because today's stub (729 bytes) does not fit the 576 bytes the PLAYNET layout
     reserves. Step 4 also adds the 4096h hook patch.
3. **Server side**: `msxpi_games` from GPFs, profhash in MSXG, HELLO fields, P3, BYE, the session/profile/save/restore commands.
   *Proof:* the existing 98 tests plus new ones.
   **Done 2026-10-19**:
   - The games are the GPF files in `MSXPIHOME/games`; `DEFAULT_GAMES` and `MSXGAME_*` are gone.
   - Invitations carry the profile hash and are declined on a mismatch.
   - `msxpi_netplay` speaks the specified MSXNP: a kind byte on every datagram, 1-4-byte inputs, the profile hash in HELLO,
     120 s connect / 60 s start / 15 s dead timeouts, and BYE.
   - The C9 transaction is length-prefixed.
   - The new MSXPi command `playnet` handles session, profile, save, restore and result.
   - The chat types `PLAYNET` and reports the result when the player is back.
   - 112 server tests pass.
   - Deployment fixed on the way: `msxpi_netplay.py`, `msxpi_chat.py` and `msxpi_games.py` were missing from the server file
     lists (`update.sh`, `msxpi-setup.sh`, `msxpi-windows-setup.ps1`, `SERVER_MODULES`), so a real Pi would never have
     received them.
   - The two-emulator rig (`run_native.sh`) still runs the old `SOCCERNET` stub, so it no longer matches the Pi until step 4
     replaces it.
4. **`PLAYNET.COM`, Pi path**: generic loader, connect phase out of the stub, Soccer stub built from the package. *Proof:* the rig with
   `SCENARIO=chat`, frame-identical traces as today.
   **Done 2026-10-19**: rig (stub at C100h, transport at C500h): plain, chat (`/play` in MCHAT starts the game), and 50 ms lag +
   8 % loss + 20 ms jitter each give 3001 identical frames, no desync, no foreign writes into C100h-C5FFh; a poked ball is
   caught on both nodes; a node that leaves at frame 600 ends the game on both. Sound fixed on the way: ticking the driver once a
   frame played Soccer's music at 20-39 ticks a second instead of 60. The game waits on the driver's state, so ticking it per
   interrupt would desync; the frame record now carries player 1's interrupt count and both machines tick that many times
   (PROTOCOLS 9.2, game packet L = 14 + 8W). Measured: 60 ticks a second, as the original.
5. **Return without a reset, Pi path** (save to a segment, and to the Pi without a mapper). *Proof:* a rig scenario where Ctrl+Shift+F5
   on one node brings both back to `MCHAT`, with the result line.
   **Done 2026-10-19**: on the Pi path the DOS area always goes to the Pi (one code path, any machine; the segment is the TCP/IP path's,
   step 7). `XEND` goes back through `PLAYNET.COM`, still in page 0 (PROTOCOLS 14). Rig `SCENARIO=chat EXITKEY=600`: Ctrl+Shift+F5 on
   bob's machine at frame 600 ends the game on both; both are back in `MCHAT` with nick and room, showing "Game with alice ended (you
   ended it)" and "Game with bob ended (the opponent ended it)". Measured: 8 KB saved (HIMEM = DF6Eh), restored in under a second.
6. **Measurements** (section 8). They decide the details of steps 7 and 8.
   **Done 2026-10-20**: results in 8a. Two changes came out of them: the save start rule (8.2/8.3, for MSX-DOS 2), and netcore must
   not run INL's timer every frame (8.4).
7. **netcore** (portable C) plus the conformance test against `Netplay` on the PC; then `PLAYNET.OVL`, the shim and the IRQ trampoline.
   *Proof:* `SCENARIO=mixed` (Pi node against INL node), then two INL nodes.
   **Done 2026-10-20**: `netcore/netcore.c` passes the conformance test (`test_netcore.py`, gcc under WSL: leadership either way,
   the same delay, packets with W 1 and 4, incompatible profile and version, BYE both ways). On the MSX it is `PLAYNET.OVL` (SDCC,
   a mapper segment at 8000h), and `PLAYNET /T id role lport ip:port[,...]` loads it. The rig gives INL a network without TAP: the
   server's user-mode UDP link (`msxpi_ethnat.py`, `MSXPI_ETH_LINK=udpnat`, INL at 10.0.2.15, the host at 10.0.2.2). Results:
   `SCENARIO=mixed` (MSXPi node against InterNestor Lite node) and `BOTH=1` (two InterNestor Lite nodes): 1501 identical frames,
   no desync; Ctrl+Shift+F5 on one TCP/IP node brings both back to the MSX-DOS prompt without a reset. What changed from 5.5 on the
   way: the TCP/IP stack keeps state in MSX-DOS's work area inside the game's RAM, so the game gets a page-3 segment of its own and
   every call switches back to MSX-DOS's (PROTOCOLS 10); that also removes the save for the return. The stack's timer runs during
   those calls from MSX-DOS's own hooks, not from XIRQ (8.4). SDCC 4.0.0 miscompiles `return a - b` of two `uint16_t` arguments
   (it overwrites L while HL still points at b); netcore avoids the pattern. Not done: the session file and the chat (step 8),
   GR8NET and real hardware (step 9).
8. **`MCHAT /t` agent** (`games_local.c`), after the memory measurement; resident IRC connection and re-attach. *Proof:* the conformance
   test against `Invites`, then `SCENARIO=tcp` from chat to game and back to the chat.
   **Done 2026-10-20**: `games_local.c` (the C twin of `Invites`) passes the conformance test (`test_games_local.py`, gcc under WSL,
   9 cases). `MCHAT /t` answers `/play`, `/accept`, `/decline`, `/cancel` and `/games` (the games are the `*.GPF` in the current
   directory). It sends its LAN address and `GAMEADDR` from `MCHAT.INI` as candidates, writes `PLAYNET.SES`, and leaves with
   `PLAYNET /T` typed. `PLAYNET /T` with no arguments reads the file, writes the result back and types `MCHAT /T`. `MCHAT /T` then
   takes the IRC connection back and says how the game ended (PROTOCOLS 13.1, 14). The memory fix is in 8.7: the scrollback and the
   user lists are kept in a mapper segment. `SCENARIO=tcp` (two InterNestor Lite nodes, `MCHAT /1 /T`, the IRC fixture reached through
   `msxpi_ethnat.py` TCP) passes:
   - INVITE, ACCEPT and GO over IRC;
   - the game started from the chat on both machines;
   - 601 identical frames, no desync;
   - Ctrl+Shift+F5 on one node ends it on both, with results 1 and 2;
   - both machines are back in `MCHAT /T` on the IRC connection they had before the game.

   Not done: answering IRC `PING` during a game.
9. `update.sh` + index, "how to add a game", and the real-hardware run (GR8NET or ObsoNET, a real Pi).
   **Done 2026-10-20, except the real-hardware run.** `software/ROM-Patcher/build_games.py` compiles every netplay package into
   `software/target/games/<ID>.GPF` and writes `index.txt` (`<sha256>  <ID>.GPF`). `--check` runs in `test_gpf.py`, and the
   published `SOCCER.GPF` rebuilds the same image as the package from the real dump. `update.sh` fetches the index, then only the
   listed GPFs whose SHA-256 changed. It checks each one (SHA-256, `GPF1`), moves it into place whole, and leaves unlisted files
   alone (`test_update_games.py`, 7 cases, the real script under `sh`). `msxpi-windows-setup.ps1` fetches the listed games as well.
   "How to add a game" for players and package writers is in `software/target/games/README.md`.

   Still open, and needs the user's hardware:
   - a real Pi and a real MSX with GR8NET or ObsoNET;
   - `MCHAT /T` on a machine whose TPA top is C806h, such as the Canon V-25 with the MSXPi TCP/IP driver: it fits on paper (8.7),
     but has not been run there;
   - IRC `PING` during a game (PROTOCOLS 14).
10. Later: the `mapper-ram` image host and a first MegaROM package (5.9).

---

## 8. Risks to measure first (before writing netcore)

1. **Game RAM footprint in `C000h-DFFFh`** across title, demo, set-up and a full match (a write watch, as was done for ED30-F2FF).
   This decides whether INL's page-3 code and the RAM helper survive the game. It is expected to be free (a cartridge of the 8 KB/16 KB
   RAM era) but has not been measured.
2. **Where INL, RAMHELPR and the DOS2/Nextor mapper routines put their page-3 code**, on DOS1+MSR, DOS2 and Nextor, and **how big
   `[HIMEM..FFFFh]` is** in each case (the size of the save).
3. **Restoring the DOS area after a game**: on DOS1, DOS2 and Nextor, with a floppy and with an SD interface. Check the disk work area,
   the FDC state, and DOS2's own page-3 data.
4. **The cost of INL's timer routine when chained once per frame**, and whether it is safe with the game's VDP state. The earlier rig
   showed INL is slow over the MSXPi Ethernet driver. A hardware stack (GR8NET) is the more relevant target.
5. **Whether UNAPI implementations enable interrupts inside calls** (this decides whether the trampoline guard is ever reached; it is
   kept in any case).
6. **Whether a resident TCP connection survives** from `MCHAT /t` through `PLAYNET` and back, on INL and on GR8NET.
7. **`mchat.com` memory**: the real end of the image and the TPA top with INL loaded and with GR8NET.
8. ~~The Soccer hook-install site~~: found while writing the specification: H.KEYI is installed at 4090h (`ld hl,402Eh`, operand at 4096h).

### 8a. Results (step 6, 2026-10-20, openMSX: Canon V-25)

Tools: `Client/tests/soccernet/measure.sh` (one machine: the prompt, then each install command; `BOOT=nextor` for Nextor 2.10 on a
MegaFlashROM SCC+ SD), and `run_native.sh` with `EXTRA_TCL` for the game (watch scripts). The numbers are emulated.

| | Result | What it decides |
|---|---|---|
| 8.1 Game RAM in C000h-DFFFh | The original cartridge writes **nothing** there in 5 minutes of title and demo. Under PLAYNET, a full 3000-frame match writes there only at INIT: 16 pushes at D55Eh-D5xxh, which are the loader's own stack (SP-relative, so always in the TPA). | C000h-DFFFh is free during the game: a stack's page-3 code there survives. Soccer's `game_ram` D500h-D5FFh range is the loader stack, not game data. |
| 8.2 Where the stacks live, and the save size | **MSX-DOS 1** (MSXPi): HIMEM DF6Eh, TPA top D606h; `MSR I` lowers the TPA top to D406h and keeps HIMEM; `INL I` hooks H.TIMI and EXTBIO to `call DDCFh` (in MSR's area). **Nextor 2.10**: HIMEM E6FEh, TPA top DC06h; `RAMHELPR I` lowers it to DB06h; `INL I` hooks H.TIMI/EXTBIO to `call E675h` (RAMHELPR's area). Between the TPA top and HIMEM: the resident code, and on DOS 2 the system's own page-3 code and data. | The save is HIMEM-FFFEh, **or lower where the game's RAM reaches below HIMEM** (Nextor: Soccer's E000h-F37Fh is below E6FEh). Saved: 8337 bytes on DOS 1, 8191 on Nextor (from E000h). The stacks' code below that start is never written by the game (8.1). |
| 8.3 Restoring the DOS area | Step 5's rig scenario passes on **MSX-DOS 1** (disk on the MSXPi) and on **Nextor 2.10** (hard disk on the MegaFlashROM SD): Ctrl+Shift+F5 on one machine, both back in `MCHAT` with the result line. The first Nextor run hung in DOS 2's page-3 code until the save start rule above. Not covered: a real floppy (FDC) and DOS 2 on other interfaces. | The rule above (PROTOCOLS 14). |
| 8.4 INL's timer per frame | Over the MSXPi Ethernet driver INL's H.TIMI takes a **mean of 6-7 ms per interrupt (38-44 % of a 60 Hz frame), up to 120 ms**, on both DOS 1 and Nextor (without INL, Nextor's own H.TIMI: 0.8 ms). Emulated, with the MSXPi device waiting for a real-time server, so the absolute numbers are pessimistic; the driver's polling is the cost either way. | netcore must **not** chain INL's timer every frame during a game. Step 7: the timer runs only while `XCHG` is in MSX-DOS's page 3 with interrupts on. Measure again on GR8NET (step 9). |
| 8.5 Interrupts inside UNAPI calls | **Yes.** During `INL S`, 121-179 of 300-500 interrupts came while INL's own mapper segments were in pages 1-2. | The IRQ trampoline guard is needed, not only a precaution: `XIRQ` must return at once while a call is in progress (PROTOCOLS 10). |
| 8.6 A resident TCP connection | (step 8) InterNestor Lite keeps a connection opened with the resident flag through `PLAYNET /T` and a whole game: `SCENARIO=tcp` shows both players' `NAMES` after the game on the IRC connection they opened before it (2 connections in all). | Not tested: a server that pings during a longer game (PROTOCOLS 14). |
| 8.7 `mchat.com` memory | The image (data included) ends at C01Ah (48922 bytes). TPA tops with INL: D406h (DOS 1 + MSR, this rig: 5100 bytes for the stack), DB06h (Nextor + RAMHELPR: 6892 bytes), C806h (Canon V-25 with the TCP/IP driver, `pchess_memory_test.py`: **2028 bytes**). | The agent (step 8) must fit in about 2 KB on the smallest of these, or the chat must shrink: a measured constraint for step 8. Step 8: the agent and its glue cost about 8 KB (C code by SDCC), so `MCHAT /t` keeps its scrollback (the rows with their kind and nick length, 7.2 KB) and the user lists (1.1 KB) in a mapper segment of its own (TCP/IP needs a mapper anyway), copied in and out at 4000h with interrupts off. The image ends at C35Ch: it fits all three, C806h with 426 bytes to spare beyond the 768 kept for the stack. |

---

## 9. Decisions (user, 2026-10-19)

| # | Question | Decision | Where it changed the design |
|---|---|---|---|
| 1 | Profile format | Use the ROM-Patcher profile format instead of defining another one | 5.3: `msxpi-rom-patch` v2 with an optional netplay ABI, compiled to GPF for the MSX (G11) |
| 2 | Names | `PLAYNET`, `*.GPF`, `games/` | One program, `PLAYNET.COM` (with `/T`), plus the overlay `PLAYNET.OVL`; no `games.local/` (user files live in `games/` and the updater leaves unlisted files alone); `GAMES\` on the MSX under DOS2 |
| 3 | Scope of the first format | Plain 16/32 KB ROMs first; MegaROMs as a later improvement, and the architecture must allow them | 5.9: image host interface, banked `curSeg2`, bank handlers as ordinary patches |
| 4 | Mapper on the UNAPI path | Mandatory | 5.1, 5.4, 5.5: checked by `PLAYNET /T` and by `MCHAT /t` (`DECLINE no-mapper`) |
| 5 | `MCHAT /t` scrollback | 24 rows a room is acceptable if needed | 5.6 |
| 6 | Mixed matches | A requirement from the start | 5.7, section 7: conformance and `SCENARIO=mixed` are acceptance criteria |
| 7 | Return to the chat without a reset | Desirable on all paths (UNAPI and MSXPi) | 5.8: save/restore of the DOS area (segment, or the Pi), resident IRC connection on UNAPI; reset only as the fallback |
| 8 | Exit key | Ctrl+Shift+F5 for every game, no per-game override | Spec 9.3 and requirement R10 |
| 9 | Inputs wider than one byte | Must be supported | Spec 4.4, 7.2, 11.1: input width 1-4 per game; kind byte on every datagram; length-prefixed C9 packets |
| 10 | Connect timeout | 120 s | Spec 11.3 |
| 11 | Desync in release builds | End the game on both machines and show the frame number; test builds only record it | Spec 9.1 (stub flag bit 0) and Appendix B |

Still open (for the next review):

- Where should the Soccer package live: `software/ROM-Patcher/profiles/soccer/` (next to the music packages, as proposed) or a separate
  `profiles` tree for netplay games?
