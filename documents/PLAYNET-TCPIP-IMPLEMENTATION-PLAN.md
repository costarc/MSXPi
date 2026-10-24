# PLAYNET over TCP/IP: implementation plan

Written 2026-10-24 on `feature/tcpip-games` at `36168d25`. It replaces the work plan in "PLAYNET over TCP/IP: audit and work plan"
(Claude Docs, 24 Oct). The evidence behind each choice is in `documents/PLAYNET-TCPIP-PLAN-REVIEW.md`.

| | |
|---|---|
| Goal | The four PLAYNET games (Soccer, Ping Pong, Salamander, Yie Ar Kung-Fu) play on every link (0, 1, 2 and mixed pairs, section 1.1), launched from MCHAT and back to it, on the rig and on real hardware, including GR8NET. One game package serves every link, and a fifth game needs only its profile folder |
| Reads first | `PLAYNET-PROTOCOLS.md` (9 stub, 10 transport vector, 11 MSXNP, 13 session record, 16 versions), `PLAYNET-TCPIP-PERFORMANCE.md` (5.7a numbers, 6 risks), `PLAYNET-TCPIP-PLAN-REVIEW.md` |
| Branch | `feature/tcpip-games` is the authoritative branch. Every task lands there. |
| Done when | Every rig cell of section 3.1 passes, the hardware cells marked "gate" pass, and phase F is released |

## 1. State at the start

### 1.1 The links

| Link | Chat (MCHAT) | Game packets | Who runs the session (MSXNP) | Needs |
|---|---|---|---|---|
| 0, MSXPi | over the MSXPi | the MSXPi link, one opcode-C9 transaction per exchange (`transport_msxpi.asm`) | the Pi, in its own thread (`msxpi_netplay.py`) | an MSXPi |
| 1, TCP/IP | `MCHAT /T` over the TCP/IP UNAPI | UDP through the TCP/IP UNAPI (`transport_unapi.asm`) | the MSX itself (`PLAYNET.OVL`, netcore) | a TCP/IP UNAPI stack and a mapper; no MSXPi |
| 2, hybrid | `MCHAT /T` over the TCP/IP UNAPI | the MSXPi link, as on link 0 (`transport_hybrid.asm`) | the Pi (`playnet open` / `playnet peers`) | both |
| mixed | | one player on link 0 (or 2), the other on link 1 | each side its own | |

In the rig, link 1 is InterNestor Lite on the MSXPi's Ethernet UNAPI driver, so its Ethernet frames still cross the MSXPi link,
and the Pi only forwards them (`msxpi_ethnat.py`). On a GR8NET or DenYoNet, link 1 uses no MSXPi at all.

### 1.2 Measured

On the rig at `36168d25` (review section 4). Soccer, 1200 frames, fps over frames 500-1200, the same `SOCCER.GPF` (profile hash
`015fb9b8`) in every run:

| Link | Result | fps |
|---|---|---|
| native pair (0 / 0) | IDENTICAL | 28.7 |
| both TCP/IP (1 / 1) | IDENTICAL | 22.9 |
| mixed (0 / 1) | IDENTICAL | 18.0 (the MSXPi node stalls in 48 % of its frames) |
| hybrid (2 / 2) | IDENTICAL | 27.6 |

Salamander with P2 on Nextor + RAMHELPR + INL: 1501 frames with identical game state, after removing a forced MSXNP 1 from the rig
script. Ping Pong and Yie Ar: MSXPi link only, never run on links 1 or 2. Real hardware over TCP/IP: never.

## 2. Rules for every task

- **Scope.** `feature/tcpip-games` is authoritative: no task adds compatibility with what is on `master` (older ROMs, servers,
  protocols or file formats). The ROM, the server and the clients of this branch are one set.
- **MCHAT is the one chat.** It is a universal chat that also launches games; no game gets a lobby or chat of its own. Every game is
  started from MCHAT (`/play`, `/accept`) and returns to it.
- **PChess and PCheckers are out of scope.** They are standalone programs, not launched by MCHAT. Revisit them only if a change to a
  shared library (`msxpi-bios.lib`, the fusion build, the UNAPI driver's interface) breaks them.
- **A game package does not depend on the transport.** One GPF serves links 0, 1, 2 and mixed pairs; no profile mentions a link or
  a transport by name (task C1 makes this a checked rule).
- Work in a worktree of `feature/tcpip-games` (other sessions use the main checkout); never switch branches in the main checkout.
- Tools: sjasmplus `C:/Users/roniv/Dev/bin/sjasmplus.exe`; SDCC 4.6.0 `C:/Apps/SDCC`; openMSX Windows build
  `C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe`; WSL openMSX for Nextor images `OPENMSX_WSL=/usr/local/bin/openmsx`
  (the scripts' default `/opt/openMSX/bin/openmsx` is not executable on this PC).
- ROMs from `C:/Users/roniv/Dev/MSX/gameroms` (SOCCER.ROM, PINGPONG.ROM, SALAMAND.ROM, kung-fu.rom); never commit a ROM or a
  disassembly.
- Rig runs: `WORK` in a scratch folder, check progress every few minutes (runs hang), one rig run at a time (fixed ports 8115/8116,
  `kill_nodes.sh`).
- **Regression set**, after every change to the engine, a transport, `playnet.asm`/`playnet_tcp.asm`, netcore, `msxpi_netplay.py`
  or MCHAT's game agent: Soccer native pair, both TCP/IP and hybrid (`run_native.sh`, three runs, about 4 min each), `test_netcore.py`,
  `test_netplay.py`, `test_games.py`, `test_games_local.py`, `test_gpf.py`, `test_patcher.py`, `lockstep_model.py`. A drop of more
  than 5 % fps on any run is a failure.
- After every change to the ROM driver or `msxpi_eth.py`: `test_ethshuttle.py`, `test_ethnat.py`, the UNAPI harness
  (`wsl_ethops.tcl`, `wsl_bench.tcl`, `wsl_waitmode.tcl`), then the regression set.
- The shipped binaries in `software/target/` must equal a clean build from the tree (`playnet.com`, `playnet.ovl`, `mchat.com`, the
  GPFs).

Sizes: S = up to half a day, M = one or two days, L = more.

## 3. Tasks

### Phase A: a rig you can trust (do first; nothing else is measurable without it)

**A1. The rig runs this branch's ROM (S).**
The rig loads `msxpibios.rom` from `Documents/openMSX/share/systemroms/extensions/` through `share/extensions/MSXPi.xml`: whatever
any session installed last. The image openMSX needs is the whole 32 KB EEPROM image `software/target/msxpi32k.rom` (sha1 `50096592`, the first one
in `MSXPi.xml`), installed under the name `msxpibios.rom`; `target/msxpibios.rom` (`f93dc9d5`) is only its 16 KB lower half and fails on the rig. A ROM and server
that disagree on the Ethernet protocol leave INL with no network; that cost the last sessions their TCP/IP testing.
- Files: new `software/Client/tests/soccernet/rig_preflight.sh` (or `.py`), called first by `run_native.sh`, `run_salamander.sh`,
  `run_pingpong.sh`, `run_yiear.sh`, `measure.sh`.
- Change: compare the ROM openMSX will load (the `sha1` in `MSXPi.xml`, then the file) with `software/target/msxpi32k.rom`, and
  check its Ethernet protocol byte (the `cp ETH_PROTO` after the probe's `cp "H"`, as the review's scan did) against `PROTO_VERSION`
  in `msxpi_eth.py`. On a mismatch, stop and print the command that installs the branch's ROM. Print the ROM's sha1 into the run log
  either way.
- Test: one run with the branch's ROM installed (passes), one with any other ROM (stops with the message).

**A2. Fix the Salamander rig for TCP/IP (S).**
- `run_salamander.sh:84`: `MSXPI_NETPLAY_VERSION=1` becomes `${VER:-2}` (as `run_native.sh` does). It made every `TCP=1` run fail
  with "incompatible opponent".
- Its trace compare: the last column (physical segments of two mapper pages) differs by design when P2's mapper also holds Nextor,
  RAMHELPR and INL. Leave it out of the comparison, keep it in the trace.
- `msxpi_netplay.py:43`: the comment says the default version is 1; the code's default is `VERSION = 2`.
- Test: `OPENMSX_WSL=/usr/local/bin/openmsx TCP=1 sh run_salamander.sh 1500` reports IDENTICAL.

**A3. Correct the documents (S).**
- `SDCC46-PORT-HANDOVER.md` 0.1: `playnet.ovl` in `target/` is the SDCC 4.6 stage-1 build, not the 4.0 one.
- `HANDOVER-salamander.md` 4b: the "rig failure" was the ROM/server protocol mismatch (A1) plus the forced MSXNP 1 (A2).
- `PLAYNET-TCPIP-PERFORMANCE.md`: 5.7a gets today's rows; the LDIR `memcpy` note (SDCC 4.6's `memcpy` is as fast); 5.5 says the
  hybrid keeps every 30th call, the code says `KEEP_EVERY` 8.
- `PLAYNET-PROTOCOLS.md` 10: the transport sizes (MSXPi 458, UNAPI 346, hybrid 384 bytes today).

**A4. MCHAT's TCP/IP test on the user-mode NAT link (S).**
`mchat_openmsx.py` with `MCHAT_LINK=tcp` uses the TAP address 192.168.99.1, which times out on this PC. Give it the option (default
on) to start its server with `MSXPI_ETH_LINK=udpnat`, INL configured as in `run_native.sh` (`ip l 10.0.2.15`, gateway and DNS
10.0.2.2), the IRC fixture at 10.0.2.2. Keep TAP as the other option. Test: passes on this PC without TAP, on Canon_V-25 + RAM 4MB.

### Phase B: every game on every link (the matrix)

**B1. Merge Yie Ar into the branch (S).** `feature/yiear-netplay` (`455b1314`) contains `36168d25`, so it merges without
conflict. Rebuild YIEAR.GPF with `build_games.py` and check its hash against `target/games/index.txt`.

**B2. Ping Pong on links 1, 2 and mixed (M).**
- `run_pingpong.sh`: add `SCENARIO=mixed`, `BOTH=1` and `HYBRID=1` by copying `run_native.sh`'s lines (the `nat`/`np` variables,
  the INL start, `PLAYNET /T pingpong <role> <lport> 10.0.2.2:<port>`), and `EXTRA_TCL=perf_node.tcl` support. If B6 is done first,
  use it instead.
- Accept: 1200 frames IDENTICAL on each, with the same PINGPONG.GPF as on link 0; one 40 000-frame soak on link 1 with
  `40 5 40000 15` (lag ms, loss %, frames, jitter ms), as was done on the MSXPi link.

**B3. Yie Ar on links 1, 2 and mixed (M).** As B2 with `run_yiear.sh`, Versus and Turn modes (`MODE=2`, `MODE=1`). Accept: 1200
frames IDENTICAL per mode and link, and Versus with `50 8 3000 20`.

**B4. Salamander, the rest of its row (M).**
- Link 2 (`HYBRID=1`): the hybrid transport has never run with mapper-ram. Add the option to `run_salamander.sh`.
- P2 with `EXT2=ram512k` on link 1 (fewer segments).
- Both nodes on TCP/IP (P1 on Nextor too).
- Accept: 3000 frames IDENTICAL on each.

**B5. Launched from MCHAT and back, for every game (M).**
`run_native.sh SCENARIO=tcp EXITKEY=n` does it for Soccer: both nodes in `MCHAT /T`, `/play` and `/accept`, MCHAT writes
`PLAYNET.SES` and starts PLAYNET, the exit key, back in MCHAT on the same IRC connection. Run it with and without `GAMELINK1=1`
(link 1 and link 2), with `PLAININI=1` (a user's MCHAT.INI), and the MSXPi scenario (`SCENARIO=chat`, link 0). Then the same for the
other three games (with B6, one option of the runner).
Accept: frames IDENTICAL, both back in MCHAT, IRC PONGs during the game, no drop.

**B6. One runner for every game (M).** Replaces the four `run_*.sh` and their `*_node.tcl` copies.
- `software/Client/tests/soccernet/run_game.sh PROFILE=<id> LINK=0|1|2|mixed [CHAT=1] [EXITKEY=n] <lag> <loss> [frames] [jitter]`.
- Per-game facts come from a small `rig.json` in each profile folder (ROM name, machine and memory, keys to start a two-player
  game, frame counter and checksum addresses for the trace), so the runner has no per-game code and no per-link code in the profile.
- Output: IDENTICAL or the first differing frame, then the `cmp_perf.py` table.
- Accept: reproduces the results of B2-B5 with the old scripts deleted. Do it after B2-B4 have shown what each game needs.

### Phase C: one package for every link, and room for the next game

The fourth game already went in without touching common code, and one GPF already runs on every link. These tasks make that a rule
and remove what would stop the next, less convenient game.

**C1. The transport rule, written and checked (S).**
Today each profile declares one `netplay.transport_area` (512 bytes: C500h for Soccer, Ping Pong and Yie Ar, D000h for Salamander)
and the loader installs whichever transport the link needs there. The rule is implicit, and Salamander had to move its area for
TCP/IP. Make it explicit:
- `PLAYNET-PROTOCOLS.md` 7.2 and 10: `transport_area` is at least `TRANSPORT_AREA_MIN` (512, the largest transport plus the UNAPI
  buffer) and lies in page 3, outside `game_ram` and the stub, and entirely below the lowest MSX-DOS TPA top PLAYNET supports with a
  TCP/IP stack loaded, because the UNAPI and hybrid transports are written into MSX-DOS's page 3 too (`tcpFootprint` checks it at
  run time today).
- That lowest TPA top must be measured first, per supported set-up (MSX-DOS 1 + MSR + INL, Nextor + RAMHELPR + INL, Nextor +
  GR8NET, with and without a floppy drive): the records disagree. HANDOVER-salamander 4b gives D406h under MSX-DOS 1 + MSR and D706h
  under Nextor + RAMHELPR + INL; the PChess memory test measured C806h on a Canon V-25 with INL. At C806h Salamander's area
  (D000h-D1FFh) would not fit, which would make Salamander the one package that depends on the set-up. If so, see C1a.

**C1a. Placement data in the GPF, one generic loader step (M, only if C1's measurement shows a game that does not fit).**
The choice depends on the machine at run time (its TPA top with the stack loaded), so a static patch list cannot make it. But the
loader needs to learn only one generic operation, once; everything game-specific stays in the GPF:
- `netplay.transport_area` may list several candidate windows in order of preference, each 512 bytes, each free of `game_ram` and
  the stub (C1's build check applies to every one).
- The stub reaches the transport through one address, `PN_TRANSPORT` in the glue (`XCHG` = +0, `XEND` = +3). `rebuild.py` assembles the
  stub twice with different `PN_TRANSPORT` values and diffs the output, as `build.py` already does for the transports, and the GPF
  carries the resulting fixup list.
- PLAYNET.COM takes the first candidate below the TPA top it measures, relocates the transport there (it already relocates
  transports) and applies the stub's fixups. A one-window GPF behaves as today.
- If no candidate fits, the refusal names the TPA top and the window needed.

If a game has no free 512-byte window below the TPA top at all (Salamander uses C000h-CFFFh, so at C806h it has none), no GPF data
can help: the UNAPI transport's need for the same address in both page-3 segments would have to shrink to a small switching thunk,
with the rest of the transport in the game's page 3 only. That is a transport redesign; decide it on C1's numbers.
- `patch_rom.py` / `build_games.py --check`: refuse a profile that breaks the rule, so a package that builds is valid on every link.
  `build.py` exports the largest transport size so the check follows the code.
- `test_gpf.py`: one failing vector per rule.
- Accept: the four profiles pass unchanged.

**C2. Engine copies checked (S).** `test_gpf.py` (or a new `test_profiles.py`): for every profile with `src/playnet_engine.asm` or
`src/mapper_k8.asm`, the file equals the one in `software/Client/src/playnet/engine/`, and the published `assets/stub.bin` equals a
fresh `rebuild.py` build. Fails the build on drift.

**C3. Room for the hybrid transport within the same 512 bytes (M).** `transport_hybrid.bin` is 384 of 384 bytes (`ASSERT` at
`transport_hybrid.asm:233`). `transport_area` is 512 bytes: code up to +384 and `tBuf` (the 128-byte UNAPI buffer) at +384. `tBuf`
is used only while MSX-DOS's page 3 (D3) is mapped.
- Investigate: whether `tBuf` can live at a D3-only address (for example just below `tStack`, MSX-DOS's TPA top, which the loader
  already computes) for both the UNAPI and the hybrid transport (`build.py` asserts their field offsets match).
- If yes: transport code may grow to 512 bytes with no change to any game's `transport_area` (C1's rule stays 512). Raise the
  `ASSERT` and put back the bytes shaved for room.
- Accept: the regression set, plus Salamander on link 2 (B4).

**C4. Capabilities next to `min_playnet` (S, decision D-3).** `profile.json` gets `"requires": ["mapper-ram", ...]` (game needs only,
never a link), the GPF carries it, and PLAYNET.COM refuses with the name of the missing capability. Only four packages exist, all
rebuilt here, so no GPF 1 compatibility is kept.

**C5. "How to add a game" covers every link (S).** `PLAYNET-PROTOCOLS.md` Part I (4.6 RAM footprint, 4.9 Test, 4.10 Publish): C1's
rule for `transport_area`, the B6 runs on links 0, 1, 2 and mixed and through MCHAT, and `requires` (C4).

**C6. A sample profile as the isolation guard (M).** A minimal two-player test program (no commercial ROM, so it can be committed)
packaged as a profile, run by `run_game.sh` on every link in the regression set. A check fails if building it changes any file
outside its profile folder and `target/games/`.

### Phase D: speed

Targets on the rig (Soccer, 1200 frames, percent of the same run's native pair): link 1 at least 85 %, mixed at least 80 %, hybrid
at least 95 % (today 80 %, 63 %, 96 %). Measure every step with `perf_node.tcl` / `cmp_perf.py`; each step must keep frames identical
and must not change any game package.

**D1. Profile the mixed pair (S).** The weakest case: the MSXPi node polls 27.6 times a frame and the TCP/IP node spends 20 ms in
`XCHG` against 13 ms when both are on TCP/IP. Run `SCENARIO=mixed` with `PERF_PROF=1` and the Q2/Q3 scripts (`q23_node.tcl`,
`q23_analyze.py`). Deliverable: where the TCP/IP node's extra 7 ms goes, in the perf doc 5.7a.

**D1a. What the chat connection costs during a game (M).**
On links 1 and 2, `MCHAT /T`'s IRC TCP connection stays open through the game: `PLAYNET.OVL`'s `irc_keep` reads it twice a second
(at most 4 x 56 bytes, the rest stays queued), drops what it reads and answers each `PING` (PROTOCOLS 14; on link 2 every 8th
exchange, `KEEP_EVERY`). On link 0 the Pi holds the IRC connection and the MSX pays nothing. Every IRC line on links 1 and 2 is a TCP
segment INL must fetch and acknowledge over the same link as the game packets (perf doc C6). All rig runs so far used a quiet
fixture, so the cost is unmeasured.
- `irc_fixture_server.py`: an option to send N channel lines a second (about 100 bytes each) to every client, and a burst mode
  (50 lines at once, as when a busy channel catches up).
- Runs: Soccer, `run_native.sh SCENARIO=tcp` (link 1) and with link 2, at 0, 1, 5 and 20 lines a second and with the burst;
  baseline without IRC = the manual start (`SCENARIO=mixed BOTH=1`). Record fps, ms in `XCHG`, stalled frames, and whether the
  connection survives: `irc_keep` drains about 450 bytes a second at most, so at 20 lines a second the queue grows (TCP window, then
  the server's send queue, and a real server drops the client).
- Deliverable: a table in the perf doc 5.6 and a recommendation for decision D-5.
- If dropping wins, the options, cheapest first: `AWAY` plus reading every 2 s (no traffic saved, fewer reads); `PART` of the
  channels before the game and `JOIN` after (others see it; private messages and `PING` still arrive); `QUIT` before the game and
  reconnect after (most saved, frees a socket, which matters on GR8NET's 3; costs the reconnect time and risks losing the nick).
  PLAYNET already treats a lost connection as recoverable: `ovl_main.c:245` marks it gone and MCHAT /T connects again on return. Test
  that path on its own in B5 (`EXITKEY` after a dropped connection) whatever D-5 decides.

**D2. Let INL take more than one frame per service (M).** Q3 measured one received frame per timer run. In `ovl_main.c`
`service()`: after `UDP_RCV` returns data, run the timer again while the driver reports a frame waiting, at most twice per `XCHG`.
Then try skipping the status poll when the driver's last reply said none is pending (perf doc 5.4 point 2). Keep whichever measures
better.

**D3. K = 3 for slow stacks (S, decision D-2).** Measured: K = 3 gives 24.1 fps on link 1 at delay 7 (K = 2: 21.8 at delay 6). Options:
make it the default for INL, or keep K = 2 and let MCHAT.INI set it. Either way the `/K` switch exists.

**D4. Delay from the measured RTT during play (M).** Perf doc 5.3: D is fixed at SETUP. Re-measure RTT from game packets and lower
D when the link allows, within 2..7, agreed by both sides at a frame boundary. Needs an MSXNP 3 rule; do it only if hardware (E1, E2)
shows the fixed delay is a problem.

**D5. TAP filter on the Pi (S).** `msxpi_eth.py`: pass only frames for the MSX's MAC, ARP for its IP and INL's multicasts; count
what is dropped. Matters on a real LAN, not in the rig.

**D6. DELTA between peers (L, low priority).** On INL it saves about 15 of 64 bytes per Ethernet frame; on GR8NET bytes are nearly
free. Only if D1-D3 leave link 1 under its target.

### Phase E: real hardware

Each run: a 3000-frame match timed against the same match on the MSXPi link (Soccer's frame counter at E003h), `ETHBENCH`, ping
from the Pi. Every run starts from MCHAT.

| # | Set-up | What it settles | Gate for release |
|---|---|---|---|
| E1 | Canon V-25 + MSXPi + INL against an MSXPi peer (mixed), then link 2 | real link cost, INL's timer called outside an interrupt (perf doc Q1) | yes |
| E2 | two such machines on one LAN, then two homes through STUN | NAT traversal (PROTOCOLS 11.2), decision D-1 | LAN yes, internet no |
| E3 | MSX2 + GR8NET (hardware TCP/IP, no INL) against an MSXPi peer | UNAPI calls from inside H.KEYI (perf doc Q9), K and S for a hardware stack, the 3-socket limit | yes |
| E4 | MSX1 + GR8NET in mapper mode 8 (`CALL NETSETMAP(8,M)`), MSX-DOS 1 + MSR | that MSR takes GR8NET's RAM as the primary mapper and `tcpSetup` passes (review, Q5) | no |
| E5 | Panasonic FS-A1WSX, and the Canon V-25 TPA with INL loaded | PLAYNET.COM, the overlay and MCHAT fit (TPA C806h with INL) | yes |
| E6 | OTIR send in wait mode on a real board (`ETHBENCH S`, 16 to 1514 bytes) | Ethernet protocol 2 on hardware | yes |

If E3 fails on Q9, the fix must stay out of the game packages: the engine, not the glue, moves the exchange out of the interrupt
handler (the handler sets a flag, `PN_TICK` runs at the next frame hook). If no such engine-only fix exists, record it as a known
GR8NET limit rather than patching each game.

### Phase F: release

- Users' guide: a section on online play from MCHAT (links 0, 1 and 2 in a player's words, the device families, the mapper
  requirement and GR8NET mode 8, what "incompatible" means).
- README: the alpha notice; "Updating": the ROM, the server and the clients come from the same build, so a server update means
  flashing `msxpibios.rom` too.
- One set from `feature/tcpip-games`: ROM, server, `playnet.com`, `playnet.ovl`, `mchat.com`, the four GPFs; release notes list the
  protocol versions (PROTOCOLS 16 table plus the Ethernet protocol). BuildIds per the project's rules.

### 3.1 The matrix

Rig cells gate a release; hardware cells marked "gate" in phase E too. Fill each with fps and IDENTICAL, or the first differing
frame. One GPF per game across the row.

| Game | Frames | Link 0 | Link 1 | Link 2 | Mixed | From MCHAT and back (0 / 1 / 2) | Hardware |
|---|---|---|---|---|---|---|---|
| Soccer | 1200 | 28.7 IDENTICAL | 22.9 IDENTICAL | 27.6 IDENTICAL | 18.0 IDENTICAL | B5 | E1-E3 |
| Ping Pong | 1200, + 40 000 soak on link 1 | passed | B2 | B2 | B2 | B5 | E1 |
| Salamander | 3000, ram2mb and 512 KB | passed | B4 | B4 | 1500 IDENTICAL (with A2's fix; 3000 in B4) | B5 | E1, E3 |
| Yie Ar | 1200 per mode | passed | B3 | B3 | B3 | B5 | E1 |
| Sample profile | 600 | C6 | C6 | C6 | C6 | C6 | |

## 4. Decisions for the owner

| # | Question | Options | Needed by |
|---|---|---|---|
| D-1 | Relay for symmetric or carrier-grade NAT | None (today: those players are told it failed), or `msxpi_netplay.py` run as a public relay | E2 |
| D-2 | Send interval on INL | K = 2 (delay 6) or K = 3 (delay 7, +10 % fps) as the default | D3 |
| D-3 | Capabilities in GPF | Add `requires` (C4) now while only four packages exist, or keep `min_playnet` only | C4 |
| D-4 | MSX1 with DenYoNet and no mapper | Out of scope (proposed), or a no-mapper UNAPI path (a redesign) | none |
| D-5 | The chat connection during a game (links 1 and 2) | Keep it (today), `AWAY` + slower reads, `PART`/`JOIN`, or `QUIT` and reconnect | D1a's numbers |
| D-6 | A game with no common page-3 window on some set-up | Candidate windows in the GPF (C1a), a smaller shared transport part (redesign), or that game needs Nextor | C1's measurement |

## 5. Order and parallel work

```
A1 ─┬─ A2 ── B4 ─┐
    ├─ A4 ── B5  ├─ B6 ── C6
    ├─ B1 ── B3 ─┤
    └─ B2 ───────┘
A3 (any time)
C1, C2, C4, C5          (after A1; C1 before B6 so the runner relies on it)
C3                      (before B4's link-2 run if it changes the hybrid)
C1 ── C1a               (C1a only if C1's measurement needs it)
D1 ── D2 ── D3 ── D4    (after A1; compare against A1's numbers)
D1a                     (after A4 and B5, which give the TCP/IP chat scenario)
E1, E5, E6 after B5; E3, E4 after E1; E2 after E1
F after the matrix and the gated hardware cells
```

Rig runs cannot overlap (fixed ports), so B2, B3 and B4 can be written in parallel but must be run one at a time.

## 6. Status (updated as tasks land; newest facts first)

| Task | State | Evidence |
|---|---|---|
| A1 | Done | `rig_preflight.py`. **The rig ROM is `software/target/msxpi32k.rom`** (32 KB, sha1 `50096592`) installed as `msxpibios.rom`; `target/msxpibios.rom` is only its 16 KB lower half and breaks every TCP/IP run |
| A2 | Done | `TCP=1 run_salamander.sh 1500`: 1501 frames IDENTICAL |
| A3 | Done | documents corrected; the 4b note says only what was reproduced |
| A4 | Done | `MCHAT_LINK=tcp MCHAT_FORCE1=1 python mchat_openmsx.py`: 10/10 checks on the NAT link, no TAP |
| B1 | Done | Yie Ar merged; `build_games.py --check` clean |
| B2 | Done | Ping Pong 1200 frames IDENTICAL: mixed, link 1, link 2, mixed hybrid; soak on link 1 (`40 5 40000 15`): 40001 frames IDENTICAL, desync 0 |
| B3 | Partly | the Yie Ar branch's own rig covers `SCENARIO=both`/`tcp`/`chat`; mixed and hybrid cells to run |
| B4 | Done | 3000 frames IDENTICAL: P2 on Nextor (link 1), link 2 (`HYBRID=1`), both on TCP/IP, both on link 2, P2 with a 1 MB mapper. With `EXT2=ram512k` PLAYNET refuses cleanly ("Not enough memory: this game needs a memory mapper of 512 KB"): Nextor, RAMHELPR and INL leave too few segments, so Salamander on Nextor needs a 1 MB mapper |
| C1 | Done | measured TPA tops (PROTOCOLS 10.2): D406h MSX-DOS 1, C806h own-drive MSX-DOS 1.8, D706h Nextor. Soccer, Ping Pong, Yie Ar fit all; **Salamander does not fit the own-drive machine: decision D-6 is open** |
| C1a | Not needed | a window cannot help Salamander (its game RAM is all of C000h-CFFFh); see D-6 |
| C2 | Done | `tests/test_profiles.py` |
| C3 | Investigated, deferred | the transports never use `tBuf`; the loader sets the overlay's buffer to area+384 (`playnet_tcp.asm`). Moving it to D3 under the stack is a loader-only change but needs the stack depth under the TPA top measured; nothing needs the 128 bytes yet |
| C4 | Done | `netplay.requires` / GPF header byte 99; only SALAMAND.GPF changed |
| C5 | Done | PROTOCOLS 4.6, 4.8, 4.9, 4.10 |
| D5 | Done | LAN filter in `msxpi_eth.py`, `tests/test_ethfilter.py` |

