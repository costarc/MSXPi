# Review: "PLAYNET over TCP/IP: audit and work plan" against the local tree

Written 2026-10-24 on `feature/tcpip-games` at `36168d25` (the plan's head), from the local checkout, with builds and rig runs.
The plan under review was written from PR #183's commit messages only; this pass reads the code, the seven handovers it could not
read, and runs the rig.

## 1. Bottom line

The plan's premise, "not functional", does not hold at the branch head. **Soccer plays on all four links in the rig today**
(native, pure TCP/IP 22.9 fps, mixed 18.0, hybrid 27.6; all 1201 frames identical, each at or above the number recorded before the
SDCC 4.6 port), and **Salamander plays 1501 identical frames with P2 on Nextor + INL** once a rig script stops forcing MSXNP 1. The
two "Critical" findings are wrong (B1) or right for a different reason (B2), and the rig blocker (B4) does not apply to PLAYNET:
the rig already has a link with no TAP and no admin rights.

What actually stopped TCP/IP testing in the last sessions was an Ethernet protocol mismatch in the rig itself: openMSX loads the
MSXPi BIOS from the user data folder, that ROM speaks protocol 2, and any server older than this branch speaks protocol 1, so
the driver refuses every frame and INL sees no network. That is B2, but it hit the developer, not a player.

The reuse half of the plan overstates the problem. The fourth game, Yie Ar Kung-Fu, was added with **no change** to the loader,
engine or transports. The engine is one source, not four copies. The two contracts the plan proposes already exist in
PLAYNET-PROTOCOLS.md 9.3 and 10. Phase 2 as written is a rewrite of working, specified interfaces, and one part of it (injecting the
engine at load time) would break the profile hash's guarantee that both machines run identical code.

Recommendation: drop phase 0.4 and most of phase 2, fix the rig's ROM pinning, fill the test matrix (most cells are one command
each), and spend the effort on what the numbers say: Salamander and Yie Ar on link 1, the GR8NET path the user actually targets, and
K = 3 or hybrid for speed.

## 2. Findings, checked

| # | Plan says | Found | Verdict | Evidence |
|---|---|---|---|---|
| B1 | PLAYNET.OVL is outside the SDCC 4.6 port; shipped `.ovl` is either an unrebuildable 4.0 binary or a 4.6 build that passes register args to stack-reading asm | Stage 1 (`6491784a`) removed the 4.0-convention `___memcpy` and shipped a 4.6 build. Every asm/C boundary is register-free: the vector entries are `void f(void)` and pass everything through the I/O block (`ovl_crt0.s`, `ovl_main.c:267-332`); the naked helpers take no arguments (`raw_call` works through globals, `r_reg` sets both A and L, `run_timi` none). A clean build from the tree with SDCC 4.6.0 is byte-identical to `target/playnet.ovl` (sha1 `cbd01066`) | **Refuted** | `build.py` in a scratch copy; rig run in 4 |
| B1a | The LDIR memcpy removal is a speed regression | SDCC 4.6's `memcpy` ends in LDIR. Rig at head: 22.9 fps / 13.2 ms in XCHG against 21.79 / 13.9 with the old override | **Refuted** (same host caveat, Q7 of the perf doc) | 4 |
| B2 | ROM/server protocol mismatch makes INL find no network | Confirmed in code (`ethtrans.asm:116-122`, `MODE_REFUSED`; server `PROTO_VERSION = 2` on the branch, `1` on master). And it already happened: the ROM in `Documents/openMSX/share/systemroms/extensions/` (sha1 `50096592`, matching neither master's `b4cfe00c` nor the branch's `f93dc9d5`) has `ETH_PROTO = 2`. Salamander session 3 ran from a master-based branch (protocol 1 server) and saw "no frame at all from INL", also on clean master: HANDOVER-salamander.md 4b blamed "the rig". `msxpirfh.bat` does copy `msxpibios.rom` to the disk, but nothing flashes it | **Confirmed, and it is the rig failure** | `ethtrans.asm`, `msxpi_eth.py:106`, ROM byte scan at 3F06h |
| B3 | C globals start as FFh | True for programs linked with `crt0_msxdos.rel` (make.bat, hex2bin FFh gap), fixed case by case (`f599c183`, `lt_seg`). **Not true for the overlay**: `ovl_crt0.s` `init` zeroes `_DATA` and copies `_INITIALIZER` | **Confirmed for .COM programs only** | `ovl_crt0.s:26-48`, `make.bat:27,65` |
| B4 | The rig cannot run link 1 (TAP times out) | `msxpi_ethnat.py` is a user-mode NAT link (no TAP, no admin), selected with `MSXPI_ETH_LINK=udpnat`, and `run_native.sh SCENARIO=mixed/tcp` already uses it. The 192.168.99.1 timeouts are the TAP-based tests (`pchess_tcpip`, `pcheckers_tcpip`, `MCHAT_LINK=tcp`) | **Refuted for PLAYNET**; task 0.4 already exists | `run_native.sh:23,109`, run in 4 |
| B5 | Salamander stops at the connection because page 3 is full | The handover's failure (no frame from INL, Soccer and master too) is B2. Today it connects and plays 1501 identical frames over TCP/IP once the rig's forced MSXNP version 1 is removed (4). Page 3 fits (transport D000h-D1FFh, stub D200h-D89Eh, `tcpFootprint` passes) | **Refuted**: two rig bugs | 4 |
| B6 | Ping Pong and the fourth game never ran on link 1/2 | Confirmed: `run_pingpong.sh:14` and `run_yiear.sh:14` "Not here yet: the chat, TCP/IP and link-2 scenarios" | **Confirmed** | |
| B7 | Hybrid transport at its 384-byte cap | `transport_hybrid.bin` is exactly 384 bytes; `ASSERT tEnd - tBase <= 384` | **Confirmed** | `transport_hybrid.asm:233` |
| B8 | Shipped binaries drift from the tree | `playnet.com` and `playnet.ovl` rebuild byte for byte. The SDCC handover's "playnet.ovl back to the 4.0 build" (stage 0.1) is not what `6491784a` shipped: it shipped the 4.6 stage-1 build. The doc is wrong, the binary is right | **Refuted at head**; fix the handover text | sha1 compare |
| B9 | ETH_BEGIN READY fix only on the branch; `fix/eth-wait-probe-legacy-boards` edits the same files | The fix is branch-only, but `fix/eth-wait-probe-legacy-boards` (`9863ddbc`) is **already merged into master** | **Half refuted**: no conflict risk left. Check whether `32bdb92d` applies without protocol 2 | `git merge-base` |
| B10 | One "LOBBY CONNECTION TIMED OUT" in PChess TCP/IP | The message is PChess/PCheckers' own lobby (`pchess_tcp.c:684`, `pcheckers_tcp.c:602`, `msxpi_game_irc.py:571`), not PLAYNET. Not run (TAP test) | **Out of scope** for this plan; keep it in the regression list | |

### Open questions the tree already answers

| Q | Answer | Where |
|---|---|---|
| Q1 fourth game | **Yie Ar Kung-Fu**, `feature/yiear-netplay` (`455b1314`), which contains the branch head. YIEAR.GPF, Single/Turn/Versus modes, 7002 frames identical with 50 ms lag, 20 ms jitter, 8 % loss, MSXPi link only | branch log, `documents/HANDOVER-yiear.md` there |
| Q4 NAT on link 1 | Already designed and implemented: STUN from the game socket, candidates in MSXG ACCEPT/GO, simultaneous HELLO to every candidate (hole punching), **no relay**: symmetric/CGNAT fails with a message | PROTOCOLS 11.2, 12 |
| Q5 MSX1 on link 1 | See below: the plan's reason ("INL needs a mapper") is wrong for GR8NET and DenYoNet; the mapper requirement comes from PLAYNET's own design | DESIGN 9 decision 4, `playnet_tcp.asm:7-11, 213-224` |

So the only real open decision under Q4 is whether to add a relay for symmetric NAT. Q2 and Q3 stand.

**Q5 in detail.** Two separate requirements were mixed up in the plan:

| Network device | TCP/IP stack | Needs INL | Mapper needed by the stack |
|---|---|---|---|
| MSXPi Ethernet driver (this project) | none: Ethernet UNAPI only | yes | yes (INL is a RAM implementation in mapper segments) |
| ObsoNET | none: Ethernet UNAPI only (RTL8019AS) | yes | yes |
| DenYoNet | **hardware** (W5100), TCP/IP UNAPI in its ROM | no | no |
| GR8NET | **hardware** (W5100), TCP/IP UNAPI in its ROM | no | no |

- **PLAYNET itself requires a mapper on the UNAPI path, whatever the stack.** `tcpSetup` refuses with "no mapper" when EXTBIO
  reports no mapper support routines, and allocates two segments: one for `PLAYNET.OVL` (netcore + the UNAPI layer, 5364 bytes
  of code, data up to 98FCh), mapped in page 2 during `XCHG`, and one for the game's private page 3 (G3). G3 exists mainly because INL
  keeps its state in MSX-DOS's page 3; with a ROM stack that reason is weaker, but G3 is also what makes the return to MSX-DOS work
  without a save. MCHAT's agent answers `DECLINE no-mapper` for the same reason.
- **GR8NET can supply the mapper itself.** Its mapper mode 8 is "GR8NET + 512K mapped RAM" (manual 3.11, `CALL NETSETMAP(8,M)`):
  the network and a 512 KB memory mapper at once. So an MSX1 with a GR8NET in mode 8 and MSX-DOS 1 + MSR (or Nextor) should pass
  `tcpSetup` with no other hardware. To verify: that MSR/Nextor take GR8NET's RAM as the primary mapper (the TPA's slot, since G3 is
  switched in page 3 by segment only), and that the manual's warning about the mapper read flag on machines with a second mapper does
  not bite. Mode 7 (1 MB mapped RAM) has no network.
- **DenYoNet has no RAM mapper.** An MSX1 with a DenYoNet and no mapper cartridge is refused by PLAYNET's design, not by its stack.
  Supporting it would need a no-mapper UNAPI path: netcore resident somewhere outside the game's pages 1-2 and without G3. On a 64 KB
  machine running a 32 KB game that room does not exist for about 6 KB of netcore, so this is a design change for the owner to decide,
  not a fix. DenYoNet is also hard to find today.
- **Sockets.** Both W5100 cards have 4 sockets. GR8NET shares 3 with its BASIC network I/O (manual 12.4). DenYoNet's BIOS is reported
  to keep one for DHCP/DNS, leaving 3. PLAYNET needs 2 (the IRC TCP connection `MCHAT /T` keeps open, and the game's UDP port).
- The rig has neither card (it runs INL on the MSXPi driver only), so these stay hardware cells of the matrix.

Proposed decision for Q5: keep "mapper required", state it as PLAYNET's requirement rather than INL's, and document GR8NET mode 8
as the MSX1 route. Treat a no-mapper path for DenYoNet as out of scope unless an owner of one asks.

## 3. The reuse section, checked

| Plan's coupling | Found | Verdict |
|---|---|---|
| 1. Engine copied per game, four edits per fix | One source. `rebuild.py` copies `engine/playnet_engine.asm` (and `mapper_k8.asm` for Salamander) into `src/` on every build; all three copies are byte-identical to the engine. A fix is one edit plus a rebuild of each GPF. The copies are tracked in git, so a check that they match is worth adding | **Overstated** |
| 2. Fixed addresses in common code for one game | True: the trampoline keeps C100h-C5FFh for Soccer's stub, PLAYNET.COM's buffers moved for Salamander | **Confirmed** |
| 3. Fixed-size slots | True (B7; Salamander's stub 1695/1792) | **Confirmed** |
| 4. Link choice in four places | True. PLAYNET.SES is the binary PNS1 record (PROTOCOLS 13), not key=value | **Confirmed** |
| 5. One version for unrelated capabilities | Partly: PROTOCOLS 16 already versions GPF, stub ABI, bank engine, MSXNP, MSXG and PNS separately; only `min_playnet` lumps them | **Partly** |
| 6. Rig per game | True, and Yie Ar added a fourth copy (`run_yiear.sh`, `yiear_node.tcl`) | **Confirmed** |

The plan's test of done ("a new game changes nothing outside its profile") is **already met by Yie Ar**: `git diff 36168d25
feature/yiear-netplay` outside the profile, its documents and `target/games` touches only its rig scripts, `test_gpf.py` and
`msxpirfh.bat`. The couplings bite only for games with unusual memory needs (Salamander's mapper-ram and page 3).

Problems with the proposed target design:

- **Contracts 1 and 2 exist.** The engine interface (`PN_TICK`, `PN_P1/P2`, `PN_END`, `G_READ_LOCAL`, `G_SOUND_TICK`...) is
  PROTOCOLS 9.3; the transport vector (`XCHG`, `XEND`, `XIRQ`, with registers in and out, `E` = lost ticks) is PROTOCOLS 10. Version
  and extend them; do not replace them with `ENG_*` / `L_*`.
- **Injecting the engine at load time breaks the profile hash.** Today the engine is inside the stub, so equal profile hashes
  mean both machines run the same engine (DESIGN 9, PROTOCOLS 16). If PLAYNET.COM injects its own engine, two players with different
  PLAYNET.COM versions pass the hash check and can desync. Task 2.2 would need the engine's hash in HELLO; the gain (no GPF rebuild
  after an engine fix) is small with four games and one `build_games.py`.
- **`.TRN` files in mapper segments** solve only B7. The hybrid transport already maps the overlay every 30th call; moving its
  rarely-run IRC/keep path into the overlay frees the cap without a new file format, loader or allocator.
- **PLAYNET.SES v2** changes MCHAT, the loader and the server for a format that works. Worth doing only with the next transport.

## 4. Rig runs at the branch head

Soccer, 1200 frames, no lag or loss, `perf_node.tcl` on both nodes, frames 500-1200 for the perf columns. Same host, same session;
compare rows with each other only (perf doc Q7).

| Run (`run_native.sh 0 0 1200`) | Link | Frames | fps H / C | ms XCHG/frame H / C | link bytes/frame H / C | Recorded before (commit msgs) |
|---|---|---|---|---|---|---|
| native pair | 0 / 0 | 1201 IDENTICAL | 28.73 / 28.81 | 1.8 / 1.7 | 18 / 18 | 27.9 |
| `SCENARIO=mixed` | 0 / 1 | 1201 IDENTICAL | 18.04 / 17.98 | 15.4 / 20.1 | 185 / 109 | 16.4 |
| `SCENARIO=mixed BOTH=1` | 1 / 1 | 1201 IDENTICAL | 22.88 / 22.90 | 13.2 / 13.4 | 71 / 71 | 21.79 |
| `SCENARIO=mixed BOTH=1 HYBRID=1` | 2 / 2 | 1201 IDENTICAL | 27.60 / 27.61 | 4.4 / 4.4 | 51 / 51 | 27.49 |

Every Soccer cell of the plan's matrix except "chat, game, chat" and "real hardware" passes at the head, and every number is at
or above the one recorded before the SDCC port. Against this run's native pair: link 1 is 80 %, mixed 63 %, hybrid 96 %.

The weakest cell is **mixed**: the MSXPi node polls 27.6 times a frame and stalls in 48 % of its frames, waiting for the TCP/IP
node. That is the case the plan's 23 fps target is about, and it is where speed work pays most.

**Salamander, P1 on the MSXPi, P2 on Nextor + RAMHELPR + INL (`run_salamander.sh TCP=1`, 1500 frames, ram2mb):**

- As committed it fails with "incompatible opponent (MSXNP 2 ...; ours 1)": `run_salamander.sh:84` forces
  `MSXPI_NETPLAY_VERSION=1` on both Pis, which predates MSXNP 2. With both nodes on Pis that matches; against P2's netcore (MSXNP 2)
  it does not. The connection itself works: P2's HELLO reaches P1's Pi.
- With version 2 (a temporary copy of the script): connected, leader, K 2, S 1, delay 7; **1501 frames, game state identical**
  (frame, E200h, E202h, 512-byte checksum, bank pages), engine desync count 0 on both. P2 ran frames 600-1200 at about 19 fps of
  emulated time.
- `cmp_pair.py` still reports "1501 DIFFER, first at 0": the trace's last column is the physical segment of two mapper pages
  (`0409` on P1, `060B` on P2), which differ by design when P2's mapper also holds Nextor, RAMHELPR and INL. The compare must drop
  that column in TCP mode.

So B5's cause is two rig bugs, not page 3. Ping Pong and Yie Ar on links 1 and 2 remain the empty cells.

## 5. Recommended plan instead

Phase 0, one or two days:
1. **Pin the rig's ROM.** `run_native.sh`, `run_salamander.sh` and the others build `msxpibios.rom` from the tree (or take
   `target/`) and point openMSX at a private user-data folder (`OPENMSX_USER_DATA`), checking the sha1 openMSX reports. This is the fix
   for the failure the last three sessions hit.
2. **B2 for players** (plan 1.3, kept): `p ver` prints both protocol numbers; the server logs a refused probe once; `msxpiupd` says
   when the ROM must be reflashed. Keep "no backward compatibility" (Q2) only if 1.3 lands in the same release.
3. **Fix the two Salamander rig bugs**: `MSXPI_NETPLAY_VERSION=1` in `run_salamander.sh:84` (use `${VER:-2}` as `run_native.sh`
   does), and the segment column in its trace compare for `TCP=1`. Also the stale "default 1" in `msxpi_netplay.py:43` (the code's
   default is `VERSION = 2`).
4. **Correct the documents**: SDCC46-PORT-HANDOVER 0.1 (playnet.ovl is the 4.6 build), HANDOVER-salamander 4b (the rig failure was
   the protocol mismatch), the perf doc's "LDIR memcpy" line.
5. **Fill the matrix** with the existing scripts: Soccer and Salamander are done here; add `TCP=1`/`HYBRID=1` to
   `run_pingpong.sh` and `run_yiear.sh` by copying `run_native.sh`'s lines (or start the single runner of plan 0.5 here, since it is
   the same work).

Phase 1, make every game work on every link (plan 1.5-1.8, kept): Ping Pong and Yie Ar on links 1, 2 and mixed; Salamander on
link 2 and with a 512 KB mapper; the chat-game-chat run (`SCENARIO=tcp`) for each. Plan 1.1 is done; 1.2 shrinks to a zeroing `crt0` for the
`.COM` programs (the overlay already zeroes).

Phase 2, reuse, reduced to: a test that the profile copies of the engine match `engine/`; a profile-driven runner replacing the four
`run_*.sh`; the hybrid's cold path moved into the overlay (B7); capability names in the GPF next to `min_playnet` (Q3). Drop the
engine injection, `.TRN` files and PLAYNET.SES v2 until a game or transport needs them.

Phase 3, speed, reordered by measured gain:
- **K = 3 as an option** (24.1 fps measured, at delay 7) and **hybrid by default for MSXPi owners** (27.5 fps): both exist.
- **The GR8NET path.** HANDOVER-salamander 4b names the user's target set-up as Canon V-25 + GR8NET + Nextor, no MSXPi. Protocol 2,
  the TAP filter and hybrid give it nothing; it has never run. Q9 of the perf doc (UNAPI calls from inside H.KEYI) is the first risk.
  This deserves a real-hardware slot before any driver work, on an MSX2 first and then on an MSX1 with GR8NET in mapper mode 8 (Q5).
- DELTA on link 1 (plan 3.2): on INL it saves about 15 of 64 bytes per Ethernet frame; on GR8NET bytes are nearly free. Low.
- Driver OTIR on hardware (3.5) and TAP filter (3.6): keep, they are cheap and independent.

Phase 4 as in the plan.
