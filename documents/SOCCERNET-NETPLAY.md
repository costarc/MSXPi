# Konami's Soccer online play over MSXPi (work in progress)

Design notes and test findings, written as the work went. The disassembly this builds on is the
reference repository `antxiko/KonamisSoccer-disassembly` (read-only for us); the ROM itself is never
distributed: the loader reads the user's own `SOCCER.ROM`, checks it and patches a RAM copy.

Where things live in this repository:

| What | Path |
|---|---|
| Loader `SOCCERNET.COM`, resident lockstep stub, UDPTEST, UNAPI draft | `software/Client/src/soccernet/` (see its README) |
| Server side of the native transport (opcode C9) | `software/Server/Python/src/msxpi_netplay.py`, hooked in `msxpi_ethglue.py` |
| Server unit tests | `software/Server/Python/tests/test_netplay.py` |
| Two-emulator test rig | `software/Client/tests/soccernet/` |

Paths below (`netplay/...`, `tests/...`) are those of the earlier prototype in the disassembly clone;
map them with the table above. The earlier file-mailbox and TAP-adapter rigs were not brought over.

---

# Konami's Soccer netplay (UNAPI TCP/IP) - design

Goal: two players, each on an MSX with any UNAPI TCP/IP interface (GR8NET,
ObsoNET, MSXPi via InterNestor Lite...), play the 2-player match over the
internet. Lobby/matchmaking reuses the PChess IRC rooms; the game traffic does
not go through IRC.

## Findings in the ROM (see src/soccer.asm)

- The whole game runs from the 50/60 Hz interrupt (H.KEYI hook at 0x4070).
- `lee_los_mandos` (0x4896) is called once per frame before anything else. It
  fills (0xE007) held / (0xE006) new for pad 1 and (0xE009) / (0xE008) for pad 2.
  (0xE002) bit 5 = two players.
- Randomness: frame counter (0xE003) (deterministic) and `ld a,r` at 0xB006 and
  0xB028 (NOT deterministic - must be patched to use (0xE003)).
- The ROM has no usable free space (zero runs: 0x54D2 x18, 0x681E x32), so
  the network code cannot live in the cartridge image.

- **The ROM writes to itself (anti-copy).** On a cartridge these writes are
  ignored; in a RAM copy they break the game. The loader NOPs all three:
  `ld (410Ah),hl` at 0x4028, `ld (4116h),hl` at 0x4056, and `res 6,(hl)` at
  0x40C3 (clears display-enable in the R1 template at 0x488A: black screen).
  Verified: after 100 s of emulated play the RAM image differs from the ROM
  in exactly those 8 bytes.

## Milestone 1 status: DONE

`netplay/soccernet.asm` -> SOCCERNET.COM (472 bytes, sjasmplus) boots the game
from RAM under MSX-DOS 1 (openMSX, Panasonic FS-A1WSX, folder disk with
MSXDOS.SYS + COMMAND.COM + SOCCERNET.COM + SOCCER.ROM). Test:
`netplay/tests/boot_ram.tcl` (logs state and RAM-vs-ROM diffs, screenshots);
`netplay/tests/boot_cart.tcl` is the cartridge control run. Not yet tried on
Nextor/DOS2 or an MSX1.

## Milestone 2 status: DONE (determinism proven, no network yet)

`netplay/stub.asm` (resident at FA00h, installed by the loader) replaces the
four pad reads (0x4564, 0x4569, 0x4896, 0x48AC) with scripted pads keyed on
the frame counter, and the two `ld a,r` coin flips (0xB006, 0xB028) with
the frame counter. The loader applies these through a patch table.

Test (`netplay/tests/trace.tcl`, per-frame trace of the ball/zone state, same
inputs, game started 2.7 emulated seconds apart):
- patched RNG: identical over 2800 frames, through scenes 4-6 (a real match);
- original `ld a,r` (`SOCCERNR.COM`): diverges at frame 2245 in the match.
So lockstep with inputs-only exchange is viable for this game. Build:
`sh netplay/build.sh`.

## Milestone 3a-i status: lockstep engine (in progress)

Engine in `netplay/stub.tmpl.asm` (generated into `stub.asm`; resident at F975h,
about 360 bytes): input delay 3 frames, 8-bit frame numbers (live window <=16),
packet = seq, len, F, last 8 local inputs, stall in the wait loop with resend
every 256 polls. Two-node rig: `netplay/tests/run_pair.sh <lag_s> <drop_%> <frames>`
(two openMSX processes, the Tcl script is the "network").

Findings that matter for any game, not just this one:
- **Lockstep needs the sound driver ticked once per game frame.** The game
  ticks it per interrupt, plus a second time when a frame overruns, and its
  match set-up waits for the driver to go quiet (`espera_a_que_calle_el_sonido`).
  That leaks timing into game logic: the two nodes diverged at frame 212 until
  both tick calls in `latido` (0x4032, 0x404E) were NOPed and the stub calls
  `tic_del_sonido` (0x4F25) once per frame. Cost: music stretches during a
  network stall instead of racing ahead. Not yet checked against the original
  PSG output.
- Anything the game derives from interrupt count or wall time, not from the
  frame counter, has to be found and tied to the frame. Candidates for the
  next games: sound, timers, R register, VDP status polling.
- Rig lessons: run both emulators in real time (a stalled node otherwise burns
  its emulated clock before the peer boots), truncate the exchange files
  before launching, and ignore mailbox reads while DOS is mid slot-switch.

## UNAPI backend: how a call has to work in this memory layout

Taken from how the repo's `ping.asm` (Konamiman's PING) discovers and calls the
stack (EXTBIO with DE=2222h to count implementations, then B=1 for slot,
segment and entry address):
- An implementation whose entry is below C000h lives in **page 1** (a ROM in
  its slot, or a RAM segment on the mapper) and must be mapped there for the
  call. Page 1 is where this game's code runs.
- So every send/receive poll from the stub (page 3) must: DI; remember the
  game's page-1 slot and mapper segment; ENASLT the implementation's slot into
  page 1 and select its segment (port FDh, or DOS2's mapper routines); call
  the entry with the function number in A; switch the game's slot and segment
  back; then EI. Interrupts cannot stay on during the call: the game's
  interrupt handler is also in page 1.
- An implementation with an entry at C000h or above is already visible and
  needs no switching.
- Cost: two slot/segment switches per call. Fine per frame, but the stall loop
  polls, so the loop should call the stack at most every few ms.
- The loader has to install the stack's mapper support (MSR / RAMHELPR, INL)
  before the game starts, in segments the game's TPA copy does not use.

### Risks to test first on a real stack (not yet verified)

1. **Does the stack get to process the network at all?** InterNestor Lite does
   its work from the timer hook (H.TIMI, FD9Fh). The game's H.KEYI handler reads
   the VDP status itself (RDVDP in `latido`), so the BIOS interrupt routine may
   never reach H.TIMI, and the loader's trampoline also writes RET over FD9Fh to
   get rid of the MSX-DOS disk hook. If INL only works from that hook, the stub
   has to run it itself once per tick (a chained call to the saved H.TIMI), and
   the trampoline must keep INL's hook while still dropping DOS's. TCPIP_WAIT is
   no help: it halts for the next interrupt, which with page 1 switched away
   would run the game's handler in the wrong page.
2. **Resident UDP connection across programs.** The spec has the lifetime flag
   (B=1 on UDP_OPEN); whether INL keeps it alive across a program exit is
   to be confirmed.
3. **Page-1 switching with the mapper segment** (port FDh): the loader must
   record the game's page-1 slot and segment and the stub restore both.

## Status of the UNAPI backend (end of the overnight session)

**Verified**
- Lockstep engine, 2000-3000 frames identical on two emulated nodes, through a
  real match (scenes 0-6), including with 120 ms one-way delay and 20% loss in
  the rig (see Milestone 3a-i). Python model passes the same loss/lag cases.
- Stub at F000-F174 (372 bytes), game's two RAM clears shortened (137Fh -> 0FFFh
  at 40A4h, 119Fh -> 0F1Fh at 45A8h). Measured: the game never writes
  ED30-F2FF except those clears; its stack bottoms out at F322 and stays at
  F32E under netplay. NOTE: an earlier measurement that only covered title and
  demo wrongly suggested F000-F2FF was free because the second clear
  (45A5h) only runs at match set-up; always measure through a full game.
- Two virtual MSXs on two TAP adapters can ping each other through the PC
  (forwarding enabled, ttl 63, ~50 ms) - `netplay/tests/ping_pair.sh`.
- `netplay/udptest.asm`: stack discovery via EXTBIO (INL found at slot 1,
  segment 7Eh, entry 4138h; the program's own page 1 is slot 1, segment 82h),
  page-1 switching around calls, UDP_OPEN, NET_STATE (2 = open) and UDP_STATE
  all work. INL's H.TIMI hook (FD9Fh) is `call DDCF` (a page-3 helper).

**Not working yet on this rig**
- UDP_SEND and TCPIP_WAIT never return (INL spins in its page-3 helper and page-1
  code; the CPU is not frozen). Tried: interrupts off during the call, on during
  the call, INL left mapped in page 1 like ping.asm (worse: starves the
  program), TCPIP_WAIT before sending. Suspects: INL's interrupt work is slow
  over the MSXPi Ethernet link (every Ethernet operation is a server round
  trip), and/or INL's interrupt routine is not safe to run while the program
  has switched page 1 itself. This is a property of the INL + MSXPi-Ethernet
  test rig, not necessarily of GR8NET/ObsoNET-class cards.

**Options for the next session**
1. Test the same UDP calls on real hardware with a hardware stack (GR8NET etc.),
   where the stack does not depend on a Z80 interrupt routine.
2. Build the MSXPi-native backend (3b) and run the whole game online end to end
   in openMSX, which this rig can do today.
3. Instrument INL further (the sources are not in this repo; only the
   RAM-implementation patch is).

Test scripts (all under `netplay/tests/`): `run_pair.sh` / `run_matrix.sh`
(lockstep pair, lag, loss), `cmp_ticks.py`, `model.py`, `ping_pair.sh`,
`udp_pair.sh` / `udp_single.sh`, `start_servers.sh` (two supervised MSXPi
servers on the two TAP adapters), `fat12_add.py` (put files on a test disk),
`msxpi_server_tap.py` (run the stock server on a named adapter).

## ROM check (done)

The loader runs a Fletcher-16 over the 32K before patching and refuses any
other dump (clean return to DOS). `netplay/rom_check.py` confirms the check
values against the full SHA-256. Patches never touch a file: they are applied
to the RAM copy only, so no patched ROM is ever distributed.

## Scope: two transports, one stub

The core (loader, patches, stub, lockstep) is standalone and needs no MSXPi.
It talks to the network through two calls only: `send input(frame)` and
`get remote input(frame)`. Two backends:

1. **UNAPI TCP/IP / UDP (primary, any network interface).** For GR8NET,
   ObsoNET, DenYoNet, SM-X, MSXPi's Ethernet driver and so on. Assumes a
   **memory mapper**: RAM-based UNAPI stacks (InterNestor Lite) need one
   anyway. This removes the 64K squeeze: INL and its RAM helper live in mapper
   segments, not in the game's 64K map, so the 26K for INL is not a problem.
   The game sits in the normal TPA segments of pages 1-2; INL must be
   installed first (`RAMHELPR I`, `INL I`) in other segments.
2. **MSXPi native (optional extra, no mapper needed).** Same two calls over
   the MSXPi link to a session service on the Pi, so an MSXPi owner with a
   plain 64K MSX can play online. This is an advantage of owning an MSXPi,
   not a requirement; nothing in the core depends on it.

Test rig for backend 1 in openMSX: MSXPi's Ethernet driver (openMSX has no
other UNAPI NIC wired up here); it is not part of the shipped design.

Constraints found while designing the UNAPI backend:
- A RAM-based UNAPI call maps the implementation segment into page 1 for the
  duration of the call. The game's own code runs in page 1, so the call must
  run with interrupts disabled, and the stub must live in page 3 (it does).
- That also means network I/O belongs in the frame wait, not in H.KEYI timing
  paths that must not lose a frame (sound ticks with DI, the frame logic with EI).

## Optional: delivery through msxarch (later, not required)

Only a convenience for MSXPi owners who want to fetch it from the internet.

msxarch gets ROMs from the MSXPi server, which already identifies them (SHA-1
ROM DB) and patches them in Python (`patch_for_msx`, `mapper_detect.py`). So
the server, not the MSX, decides:
1. A "game profile" registry on the server keyed by SHA-256/SHA-1 (Konami's
   Soccer = patch table + stub, the same data as `patches:` and `stub.bin`).
2. The ROM header the server sends gains a "variants" flag. For a profiled
   ROM msxarch asks once: `1 Original   2 Online (2P)`; plain ROMs never ask.
3. Original -> server sends the untouched image. Online -> server applies the
   profile and also ships the stub, and msxarch's launcher jumps in as usual.
Alternative with no UI change: list both as separate archive entries
(`SOCCER.ROM`, `SOCCER (online).ROM`) generated by the server.
Caveat: the game still needs a UNAPI stack resident while it runs, with the
RAM that costs (INL is ~26K), so the msxarch path must not be the only way to
run it.

## Architecture

1. **SOCCERNET.COM** (MSX-DOS / Nextor loader):
   - reads soccer.rom, copies it into RAM at 0x4000-0xBFFF, switches page 0 to
     the BIOS ROM and jumps to the game's init;
   - applies the patches below to the RAM copy;
   - installs the net stub in free page-3 RAM (below the game's 0xE000 area is
     NOT free: pick an address after checking the game's RAM map);
   - uses the UNAPI TCP/IP spec: UDP open, send, receive via EXTBIO.
2. **Patches**
   - `lee_el_mando_2` (0x48F2) -> call the net stub: send local pad (from
     pad 1), receive remote pad for the same frame, return it as pad 2.
   - `ld a,r` at 0xB006 / 0xB028 -> read (0xE003) instead.
   - force (0xE002) bit 5 (two players) and the same RNG seed/frame counter on
     both sides at kick-off.
3. **Lockstep protocol (UDP)**: packet = match id, frame number, last 4 frames
   of local input. Input delay N frames (default 3), so frame F uses inputs
   sent for F-N. If the remote input for F is missing, the game waits (halts
   the frame logic, not the interrupt/music). Checksum of ball + player
   positions every 60 frames to detect desync.
4. **Meeting point = IRC, then direct (no relay, no server of ours).**
   - Lobby: the PChess IRC rooms (the TCP/IP client code in the MSXPi repo,
     `pchess_tcp.c` / `pcheckers_tcp.c`, already speaks IRC over UNAPI TCP).
   - Each MSX learns its own public `ip:port` for the game UDP socket by
     sending a STUN binding request (20 bytes) from that same socket to a free
     public STUN server (no server of ours), then posts it in the IRC room.
   - When the match is agreed, both MSXs send UDP to each other's address at
     the same moment (hole punching) and keep it open with keepalives; from
     then on all game traffic is peer to peer. IRC carries nothing in-game.
   - Works with the usual home routers (cone NAT) and with a manually
     forwarded UDP port. Fails with symmetric NAT / carrier-grade NAT: the
     game reports "cannot connect directly" instead of silently relaying.
   - Typed `ip:port` stays as a manual fallback (LAN, VPN, forwarded port).

## Milestones

1. Boot the ROM from a RAM copy via a DOS loader in openMSX (no network).
2. Replace pad 2 with a scripted input stream; patch the RNG; verify two
   openMSX instances stay identical for N minutes.
3. UDP transport over UNAPI in openMSX between two instances with a typed
   `ip:port` (direct, no relay); add input delay, desync checksum.
3b. STUN + IRC meeting + hole punching on top of it.
4. Lobby handoff from IRC (match ticket).
5. Real hardware: GR8NET / ObsoNET / MSXPi, measure per-frame cost.

## Open risks

- The game calls the BIOS from the interrupt; UNAPI calls from inside the
  interrupt handler must not reenter slot switching. The stub may need to run
  from the main loop (the game idles in `jr $`) or save/restore slot state.
- RAM budget in page 3 with INL resident on non-GR8NET setups.
- Machines without RAM in pages 1-2 under DOS cannot use the loader approach.

## Update 2026-10-18: UNAPI hang resolved (architecture review step 1)

`UDPTEST` now uses the standard UNAPI dispatch (RAM helper `CALL_MAP` for a mapper
segment, `CALSLT` for ROM below C000h, direct call otherwise; `ei` after each call) and
keeps all buffers in page 2 (9000h) instead of page 1. Result on the INL rig:
single node `UDP_SEND` returns ("sent HELLO"); pair run passes both ways
(HELLO -> WORLD between 192.168.99.2 and 192.168.98.2). The old hang was the program's
own ENASLT/`OUT (FDh)` page-1 switching plus buffers living in page 1, not INL or the
MSXPi Ethernet driver. `netplay/unapi.tmpl.inc` still has the old switching and must be
ported the same way before the stub uses it.

## Update 2026-10-18: MSXPi-native transport (architecture review step 2)

Built and verified with two openMSX (Canon V-25 + MSXPi) and two msxpi-servers relaying over
UDP on localhost; no TAP adapters, no mapper, no UNAPI.

- **Wire protocol** (opcode 0xC9, same dispatch point as the Ethernet UNAPI opcodes):
  `MSX -> C9, flags, 11 packet bytes, sum`; `Pi -> n (0|11), n bytes, sum`. Flags: 1 = forward to
  peer, 2 = return oldest delivered packet. Checksum failure = lost packet.
- **MSX side**: `xchg` in `stub.tmpl.asm` (`-DNATIVE`), polled ports 56h/5Ah with bounded spins,
  interrupts off during a transaction, 557 bytes total (budget 640). The wait loop is one
  transaction per poll; every 16th poll also resends. Build: `sh netplay/build.sh` makes
  `SOCNAT.COM` (scripted input).
- **Pi side**: `netplay/server/msxpi_netplay.py` (UDP socket, receive thread, delay queue).
  Session and impairments from the environment: `MSXPI_NETPLAY=local:peer_host:peer_port`,
  `MSXPI_NETPLAY_LAG_MS`, `_JITTER_MS`, `_LOSS_PCT`, `_SEED`. `tests/msxpi_server_np.py` runs the
  stock server with the hook; nothing in the MSXPi tree is changed. To ship it, add the module to
  the server and a branch for opcode 0xC9 in `msxpi_ethglue.eth_handle_opcode`.
- **Rig**: `sh netplay/tests/run_native.sh <lag_ms> <loss_pct> [frames] [jitter_ms]` (ports 8115/8116;
  other sessions use 8015). Env `ONLY=H` runs one node, `PROG=SOCNAT`.
- **Results**: lag 0, 1501 frames: IDENTICAL (scenes 0,1,3,4,5,6). Lag 50 ms + 20 ms jitter + 10 %
  loss, 3001 frames, real match: IDENTICAL; server counters tx 3732/3521, dropped 360/398, badsum 0.
  This closes the "lag + loss through a match" gap for the scripted build.
- **Not done**: production stub with real joystick; negotiated delay/handshake/timeouts/desync
  check; STUN/lobby; real hardware (polled-mode transaction cost per frame is unmeasured there);
  UNAPI backend port (`unapi.tmpl.inc`) still has the old page-1 switching.
- Rig pitfalls found: file names must be 8.3 (SOCCERNAT hung DOS); a Tcl `type "...\r"` needs a real
  backslash-r; another session's openMSX was retrying port 8015 and stole the connection.

## Update 2026-10-18 (later): architecture review step 3 - handshake, negotiated delay, timeouts, desync check

All on the MSXPi-native path; verified on the two-openMSX rig.

- **Handshake and version** (Pi side, `msxpi_netplay.py`): peers exchange HELLO (version, random nonce). A
  version mismatch ends the connect on both sides (a side that already failed answers late HELLOs, so a
  peer that starts later learns it too). The MSX asks for the result with status polls (flags 0xC0 then 0x80).
- **Negotiated delay**: the higher nonce is the leader. It sends 8 pings, takes the 90th-percentile round
  trip and sets `DELAY = ceil(rtt/2 / 20 ms) + 2`, clamped to 2..6, then repeats SETUP until the ACK (a
  game packet from the follower counts as an ACK). With 50 ms lag + 20 ms jitter each way it chose 6; on
  localhost 3. The stub takes the value from the status reply and primes its ring tags (`connect`).
  `MSXPI_NETPLAY_DELAY` forces a value for experiments.
- **Timeouts**: connect gives up after 300 s (status 3); in a match, 15 s with nothing from the opponent
  marks the session dead and the next poll returns FFh. The stub then wipes the `AB` header of its RAM copy
  (otherwise the BIOS boots the copy as a cartridge) and resets: the MSX lands at the DOS prompt.
- **Desync check**: every 32nd frame each side checksums E100-E2FF (players and ball), sends tag+value in the
  packet (13 bytes now) and compares with the opponent's for the same frame. Result in `desync` / `desyncF`
  (first frame). Production would define `DESYNC_ABORT` to reset; the tests only flag it.
- **Stub size**: 752 bytes in production (768 with the scripted tables). The game's stack reaches F30Ch, so the
  stub must end below that: kept at <= F300 in the test build (assert). More features need to move code out
  or shrink; there is no free ROM space for it.
- **Results**: lag 50 ms + 20 ms jitter + 8 % loss, 3001 frames, scenes 0-6: IDENTICAL, no desync flagged
  (server counters: 213 and 238 packets dropped, 0 bad checksums). Version mismatch (VER2=2): both servers and
  the MSX stop at once. Ball poked on one node at frame 800: desync flagged on both. Node C killed at frame 300:
  H's server declares the session dead after 15 s and H returns to DOS.
- **Bugs found on the way** (worth remembering): a `ld bc,16` where B was needed overwrote the stub; the 8-bit
  frame counter wraps to 0 every 256 frames, so "frame 0" actions must be guarded by state, not by the counter.
- **Still open**: production stub with the real joystick; lobby/STUN; real hardware (cost of two ~15-byte
  polled transactions per frame unmeasured); UNAPI backend (`unapi.tmpl.inc`) port; connect-time UI (the
  title screen is blank while waiting); the 4000h wipe depends on the RAM copy being the cartridge in page 1.
