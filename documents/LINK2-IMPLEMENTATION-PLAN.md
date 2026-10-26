# LINK2 - implementation plan

Design: LINK2-DESIGN.md. Tests per phase: LINK2-TEST-PLAN.md.

- **Where**: worktree `C:\Users\roniv\Dev\github\MSXPi-link2`, branch `feature/link2`, off
  `feature/tcpip-games` at 542df0c3.
- **First commit** (7495484d) is the retry investigation: the fault-injection harness, the
  pcopy-upload hang fix in `recvdata2_oneblock` and `SENDRETRIES` = 10 for legacy sends. Both
  legacy changes stay compatible with every existing ROM and client.

**Milestones**: every phase ends with a build (`software/build`, which bumps BuildIds and writes
`target/` and `msxpirfh.bat`), a commit, and a push of `feature/link2`. After that,
`msxpiupd feature/link2` on the MSX brings the server and the MSX files to that milestone. The
EEPROM still has to be flashed by hand (`at28c256` with `msxpi32k.rom`, A15 jumper, full 32 KB).

## Status (2026-10-26)

| Phase | State | Commits on `feature/link2` |
|---|---|---|
| retry investigation | done | 7495484d (fault-injection harness, upload-hang fix, `SENDRETRIES` = 10) |
| design and plans | done, kept current | ee9d3cf3, ec3cb50a, and every phase since |
| 0 - tooling | **done**, with a Z80 interpreter instead of sz80: `tests/z80emu.py` hooks the MSXPi ports, which sz80 cannot. T-state baselines, ROM size report (printed by `software/build`) and the simulated link all exist | 898d20ab, and the phase 2 commit |
| 1 - server dual stack | **done**, audited | 898d20ab, 533a0d7b (overflow, NAK reset), 2ebc8d42 (rename), 2dc875db (slips), 7450e089 (BuildId 20261025.079), and the end-mark commit |
| 2 - MSX core | **done**, audited twice (see "Phase 2 results" and "Audit of phases 2 and 3" below): `link2.asm`, the BIOS half and msxpiext.bin on LINK2, L2TEST.BIN, `l2test` on the server | f0179004, 4f177089 (first audit), the second-audit commit |
| 3 - Ethernet protocol 3 | **done** in code and in the Z80 tests (`test_eth3_z80`), audited; openMSX with a disk and hardware are phase 4 | d9c367cb, the second-audit commit |
| 4 to 7 | not started (phase 4 needs the real MSX) | - |

The branch is pushed. `msxpiupd feature/link2` brings this server to an MSX; the MSX files in
`target/` now carry the LINK2 BIOS half, msxpiext.bin and L2TEST.BIN (the DOS half is unchanged).

### What exists, and where

- **Server**:
  - `software/Server/Python/src/msxpi_link2.py`: the LINK2 framing (`link2_accept`,
    `link2_send_block`, `link2_recv_block`, `link2_send`, `link2_recv`), the CRC, the end mark
    and the ABORT flood
  - `msxpi_blocks.py`: the public `link_*` functions, each choosing legacy or LINK2 from the
    transfer's first byte
  - `msxpi_transport.py`: `spi_burst_send` / `spi_burst_recv` (GO + payload in one READY-held
    run) and the `link_send_byte` / `link_recv_byte` pair
  - constants in `msxpi_const.py`
- **Tests** (`software/Server/Python/tests`):
  - `link2_sim.py`: the lockstep simulated link, the MSX model `Msx`, which is the reference for
    the Z80 code (design section 8), and `LegacyMsx`
  - `test_link2.py`: test plan T1, 14 tests
  - `link2_faults.py`: the flip and slip sweeps
  - `fault_server.py` + `fault_inject_openmsx.py`: the openMSX fault harness (test plan T2/T5)
- **Test ROMs without touching the install**: build with the zmac + sjasmplus recipe of
  ETH-DRIVER-SPEED-HANDOVER.md section 5 (DOS half first; the BIOS half takes its `DOS_INIT`,
  `DOS_STMT` and `DOS_RET` addresses), concatenate to 32 KB, and run it through the openMSX
  extension `MSXPiTest` (`Documents/openMSX/share/extensions/MSXPiTest.xml`, a copy of MSXPi.xml
  without sha1s whose ROM is `C:/tmp/fi/msxpitest.rom`). `fault_inject_openmsx.py --rom` does
  the copy. An unchanged build reproduces the shipped `msxpi32k.rom` byte for byte (sha1
  50096592).
- **Careful with `software/build`**: a full build copies the disk images into
  `C:\home\pi\msxpi\disks`, which the user's own server serves. Use
  `buildMSXdiskImage=no` while that server runs, or ask first. A server-only release is
  `updateServerVersion=yes buildClientCommands=no buildMSXdiskImage=no ./build` (BuildId only).
  A ROM milestone is `buildBIOS=yes buildClientCommands=no buildMSXdiskImage=no updateServerVersion=yes
  updateRomVersion=yes ./build`: ROM halves, msxpiext.bin, ethrom3.bin and L2TEST.BIN, nothing else.
- **`buildClientCommands=yes` overwrites `target/msxarch.com`** with the old asm version (`msxarch.asm`,
  5,300 bytes) instead of the SDCC 4.6 C build that `feature/tcpip-games` ships (14,181 bytes, `make.bat
  msxarch`). The first phase 2 audit committed exactly that; it was put back in the second. After such a
  build, restore it (`git checkout 542df0c3 -- software/target/msxarch.com`) or rebuild it with make.bat.
- **Every milestone that changes the server bumps its BuildId** (`updateServerVersion=yes`). Phase 3 did not
  (the server changed under 20261025.081); the second audit's build is 20261026.082.

### Phase 2 results

`link2.asm`, `L2TEST.BIN` (`ROM/src/BIOS/l2test.asm`, built to `target/L2TEST.BIN`) and the server's `l2test`
command are in; the BIOS half and msxpiext.bin are assembled with `-DMSXPI_LINK2`. Numbers and what was
not run are in LINK2-TEST-PLAN.md ("Phase 2"); the code as built is in LINK2-DESIGN.md 8.8. Left for later
phases: `PerformHandshake` / `RECVDATA_ONEBLOCK` have no LINK2 twin (the legacy code is assembled only
`IFNDEF`), the DOS half and the .COM tools still speak the legacy protocol, and the hardware test (phase 4)
is the next milestone. `msxpiupd feature/link2` brings the server; the ROM image (`target/msxpi32k.rom`)
and `msxpiext.bin` have to be flashed / copied by hand.

### Audit of phases 2 and 3 (2026-10-26)

A review of the first audit's fixes (4f177089) and of phase 3 (d9c367cb). Fixed; the first three have a
test that fails on the code before the fix, the MSXPIVER and L2TEST changes are covered only by the
openMSX run passing (no test provokes them):

| Where | Problem | Fix |
|---|---|---|
| Ethernet v3, `ETH_GO` | GO was not checked. When the server refuses ETH_SEND_FRAME's length it answers BADLEN in the GO slot; the MSX took it as GO and sent the whole frame with OTIR into the server's opcode hunt, where its bytes are taken as opcodes | GO must be 5Ah, or the transaction fails and is resynchronised (`test_a_refused_length_is_not_sent_into_the_opcode_hunt`). 5 bytes; ethrom3.bin is 1381 bytes, 27 free |
| Ethernet v3, server | The protocol lived in memory only. After a server restart a v3 driver, which probes only when it starts, got protocol 2 replies and failed until the MSX was reset | kept as `ETHPROTO` in msxpi.ini (`test_protocol_3_survives_a_server_restart`, `test_the_protocol_is_kept_across_a_restart`) |
| `link2.asm`, mode 2 room | A block ending exactly at 10000h wraps to 0 and was accepted from any buffer, also one below F380h, so it ran over the system area | judged as "ends past F380h" (`test_ends_exactly_at_10000h_from_below_the_system_area`) |
| `CALL MSXPIVER` | The first audit's "terminator inside the buffer" fix moved the buffer with the size, so the terminator still landed on HIMEM | buffer at HIMEM-128 for 127 bytes (`scf` instead of `or a`: no size change; the DOS half changes by this byte and the BuildId only) |
| L2TEST.BIN | The server's sink now answers a failed receive, but L2TEST skipped its reply read after a failed send, so the answer met the next repetition's command | the reply is read after every send; the repetition counts as failed if either failed |
| `target/msxarch.com` | the first audit's build replaced the C msxarch with the old asm one | restored (see "Careful with `software/build`") |
| documents | `UNAPI_ORG3` is 73 bytes below the v2 origin, not 41; phase 3 had no results in the test plan | corrected; test plan "Phase 3" |

Checked and left as they are: every shuttle reply path against the driver's GO reads (fast ops, IN_STATUS
with and without an inline frame, GET_FRAME empty, discard, too long and full, SEND_FRAME), wait mode
around `ETH_GO` on every exit, the BIOSENTRY table of msxpiext.bin, the DOS-half alias names, and the
setup and update scripts' file lists. A v2 RAM driver next to the v3 ROM driver switches the server's
protocol; that is recorded in the design (section 4), not worked around.

## Open questions (defaults used until answered)

1. **.COM tools and the C library** (pcopy, p, mchat, ssh...): move them to LINK2 in this
   project, after the DOS driver (phase 7)? *Default: yes, phase 7. Until then they keep using
   the legacy protocol, which the server keeps serving.*
2. **Ethernet frame check**: keep the 8-bit sum, fixing only GO and `RC_OK` (design section 4),
   or also move it to CRC-16? CRC costs about +40 T-states a byte on every frame (about 1.5x the
   per-byte cost of a send) on the INL hot path. *Default: keep the sum; IP, TCP and UDP check
   their own data.*
3. **The real Pi's GPIO engine**: native (`MSXPI_NATIVE_GPIO=1`) or the Python fast path? Both get
   the GO bursts, but the speed baselines must be measured on the engine you actually run.
   *Default: native.*
4. **Branch name** `feature/link2`: in use and pushed.

## Phase 0 - tooling (no behaviour change)

- `software/Server/Python/tests/link2_sim.py`: a lockstep virtual link. Two byte queues stand in
  for the CPLD. The server side uses the real `msxpi_blocks`/`msxpi_link2`, through a test
  transport. The MSX side is a Python model of the MSX LINK2 code. Fault hooks: flip a bit in a
  chosen byte (`Wire.flip`, `Wire.hook`), or slip a chosen MSX transfer (`Wire.slip`). *Done.*
- `software/tools/z80bench/`: assembles single routines with sjasmplus and runs them in `sz80`
  (SDCC's simulator, already used by netcore_cost.py) to get exact T-states and sizes. This is
  for the CRC loop, the polled loops and the burst checksum pass.
- **ROM size report**: the build prints free bytes per ROM half from the assembler listings, and
  fails when a half overflows. This number decides phase 6.
- **Baseline**: T-states of today's PRB_SUM, PAYLOAD_RX and PAYLOAD_TX loops, and the
  fault-injection matrix on the shipped protocol. These are the numbers LINK2 must beat.

## Phase 1 - server dual stack

1. Constants in `msxpi_const.py`:
   - codes: `HELLO2`, `HELLO2_ACK`, `LINK_ACK`, `LINK_NAK`, `LINK_ABORT`
   - limits: `LINK2_RETRIES` = 10, `LINK2_SENDER_CAP` = 32
   - `RC_PROTOERR` = 0xF0
2. `msxpi_link2.py`:
   - the CRC (`binascii.crc_hqx`)
   - `link2_accept()`: answers HELLO2 with HELLO2_ACK and flags, then reads the MSX's size frame
   - `link2_send()` / `link2_send_block()` and `link2_recv()` / `link2_recv_block()`: header, header ACK,
     payload, CRC, ACK/NAK/ABORT, seq and duplicate handling, the receiver-side limit, the
     sender cap
3. Transport: `spi_burst_send(data)` and `spi_burst_recv(n)`, with GO plus payload in one
   READY-held run:
   - native: `msxpi_gpio_burst()` with both buffers; wrapper changes in `msxpi_gpio_native.py`
     only
   - Python fast GPIO: the same loops, RDY raised once
   - TCP-framed openMSX: `tcp_exchange([GO] + ..., hold=True)`
   - raw TCP: plain stream
4. `msxpi_blocks.py`: the public functions take the paired names of design section 5.3 (`link_recv`,
   `link_send`, `link_send_block`, `link_recv_block`, `link_recv_command`). Each one hunts for
   READY or HELLO2 and runs the legacy or the LINK2 framing. The old names stay as aliases.
5. **Naming, server side**: one mechanical commit converts every command handler from
   `recvdata2` / `sendmultiblock` / `senddata` / `recvdata2_oneblock` / `PerformHandshake` /
   `SPI_ByteTransfer` to the paired names. The commit does nothing else, so it reviews as a pure
   rename. Then the aliases are removed, so a missed call fails loudly. `msxpi_link2.py` names
   its functions `link2_*`: the LINK2 half behind the public `link_*`. *Done: 2ebc8d42.*
6. Unit tests on the simulated link (test plan T1).
7. Regression: the legacy openMSX smoke and fault runs against the new server (test plan T2).

**Done when**: T1 passes, legacy behaviour is unchanged in openMSX, and the build is pushed. The
existing ROM and tools work with this server exactly as before.

## Phase 2 - MSX LINK2 core (BIOS half + msxpiext.bin)

1. `asm-common/include/link2.asm`:
   - `LINK_CRC_TABLE`: 512 bytes, page-aligned, generated by `asm-common/transport/generate.py` so
     the C library can share it later
   - `LINK_CRC`: register-only
   - `LINK_OPEN`: HELLO2 with the bounded wrong-answer counter
   - `LINK_SEND_BLOCK` / `LINK_RECV_BLOCK`, `LINK_SEND` / `LINK_RECV`, `LINK_COMMAND`
   - `LINK_BURST_RECV` / `LINK_BURST_SEND`: polled read of GO, wait mode on, INIR/OTIR, wait mode off,
     CRC pass over the buffer
2. `msxpi_bios.asm`:
   - under `IFDEF MSXPI_LINK2` the public entry points are the paired `LINK_*` names (design
     section 5.3), with the register contracts of the legacy routines they replace
   - the legacy names (`SENDDATA`, `PerformHandshake`, `RECVDATA_ONEBLOCK`, `SendCommandToMSXPi`,
     `PIREADBYTE`, `PIWRITEBYTE`) are defined as aliases (`EQU`) of the new ones, only for code
     not yet converted
   - the legacy code is assembled only `IFNDEF MSXPI_LINK2`
   - **naming, MSX side**: `msxpi_call.asm` and `msxpiext.asm` call the new names. The DOS driver
     (phase 6) and the asm .COM tools (phase 7) are converted when they move to LINK2, then the
     aliases go
   - the polled payload loops (`payload.z80` + `generate.py`) gain a CRC variant that updates the
     CRC with the previous byte while the next transfer runs
3. The BIOS half is assembled with `-DMSXPI_LINK2`, and `msxpiext.asm` too (`-DMSXPI_RAM_STASH
   -DMSXPI_LINK2`). The burst routines move out of `IFDEF MSXPI_DRIVER`, so CALL MSXPI bursts
   into RAM buffers outside page 1.
4. `software/build` assembles the DOS half with the legacy protocol (unchanged) and the BIOS half
   and msxpiext.bin with LINK2. It still writes `msxpi32k.rom` = DOS half + BIOS half.
5. `L2TEST.BIN`: a small test binary built from the same sources. CALL MSXPI downloads it to RAM,
   where it runs as `DEFUSR`, so no floppy is needed. It exercises what CALL MSXPI cannot: bulk
   MSX -> Pi sends with OTIR, receive into page-1 buffers, timing loops. It gets its own server
   test command (`l2test`), which echoes and verifies.
6. Tests: test plan T3 (Z80 bench), T4 (openMSX, BIOS-only boot) and T5 (fault matrix).

**Done when**: CALL MSXPI and L2TEST pass in openMSX, the fault matrix shows 0 hangs and 0
corrupt with LINK2, measured T-states per byte are no worse than the phase 0 baseline, and the
build is pushed for the real-MSX test (phase 4).

## Phase 3 - Ethernet protocol 3

1. `UNAPI/src`: GO before ETH_TX_BLOCK's OTIR and before ETH_RX_BLOCK's INIR; `ETH_RC_OK` = 0x5A;
   `OP_PROBE3` (0xCA); `ETH_PROTO` = 3 under `-DETH_V3`. Built twice: v2 for the DOS half, v3 for
   the BIOS half.
2. `msxpi_eth.py`: protocol 3 next to 2, chosen by the probe opcode.
3. Tests: `test_ethshuttle.py` for both versions; ETHTEST and ETHBENCH in openMSX and on hardware.

## Phase 4 - real hardware (Canon V-25 + Pi, v1.6 CPLD)

`msxpiupd feature/link2`, then flash, then test plan T6:

- the CALL MSXPI suite
- L2TEST sends with OTIR, the case that failed before
- speed against the baseline
- ETHBENCH
- a long soak

## Phase 5 - optimise

- **Size pass on `msxpi_call.asm` and `msxpi_bios.asm`** (user's note: rewrite where it pays):
  - the CALL parser: EVALTXTPARAM, PARSE_CALL_PARAMETERS, the error paths, the three response
    modes
  - shared tails, register-based state instead of stack shuffling, dead code from the legacy
    protocol in LINK2 images
- **Naming pass** on every remaining BIOS routine and the CALL handler: the verb-noun scheme of
  design section 5.3 (`PRINT_PI_STDOUT`, `PARSE_CALL_PARAMETERS`...), no mixed case, one name per
  routine, done together with the rewrite
- **Speed pass**: unroll the CRC and burst checksum loops where measurements show a gain.
- **Report**: bytes saved per routine, and the projected DOS-half budget.

## Phase 6 - MSX-DOS driver on LINK2 (if it fits)

1. Assemble the DOS half with `-DMSXPI_LINK2`, using the optimised code. DSKIO keeps its
   structure; `DSKIO_TXSIZE`/`DSKIO_RXSIZE` go (bursts are negotiated in the HELLO2 exchange).
2. **Burst writes come back**: sector writes with OTIR and GO.
3. If the table does not fit, use the fallbacks in design section 6, chosen from the measured
   budget.
4. Test plan T4/T5 with MSX-DOS (COPY both ways, the pcopy batch) and T6 on hardware: the COPY that
   failed with burst writes before.
5. **Update path**: `msxpiupd` from a LINK2 MSX-DOS. The server already speaks both protocols, so
   the order no longer matters, and an old server gives a clean error.

## Phase 7 - .COM tools and the C library (question 1)

- `msxpi-bios.c`: LINK2 using the shared generated payload/CRC code, under the paired names in
  lower case (`link_send()`, `link_recv_block()`...); the old C names stay as macros until every
  client is converted.
- Rebuild every C client.
- The asm tools (msxarch, playnet, template).
- Also: give `SENDDATA2`/`RECVDATA` a limit, and make pcopy delete its partial file on an abort.
- **Legacy server support stays** for old EEPROMs and tools; dropping it is a separate decision.

## Rules for the whole project

- **Shared checkout**: work only in this worktree. Other sessions run their own openMSX and servers
  (check the ports first; the harness uses 5046).
- **Process hygiene**: every openMSX/server run is bounded by a timeout and watched every 5
  minutes or less; kill hung runs by exact PID.
- **Commits**: one per milestone, with the measured results in the message. Push only
  `feature/link2`.
