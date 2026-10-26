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
| 4 - real hardware | **functional, READY race and speed done** (results in LINK2-TEST-PLAN.md "Phase 4": 1000 x 512 OTIR sends OK, 21.4 KB/s vs 8.8 KB/s legacy for 8 KB downloads). **soak done** (1 h 40 min, 136 rounds: 136,000 OTIR sends counted on the MSX, 129,240 `L2TEST OK` in the server log, 0 BAD, 0 F); Ethernet and the control run are not done | b64bc860, 166552a5, bf28efa7, d195f996 |
| 5 - optimise | **done** (see "Phase 5 results"): `link2.asm` 1406 -> 1156 bytes with the same wire bytes and faster polled loops, CALL handler rewritten, legacy code out of LINK2 images, a table-less CRC for the DOS half | the phase 5 commit |
| 6 - DOS driver | **done** in openMSX (see "Phase 6 results"): DSKIO and CALL MSXPI on LINK2 with the CRC table, burst writes back; the Ethernet UNAPI driver left the DOS half (question 5); hardware not run | the phase 6 commit |
| 7 - .COM tools and the C library | **done** in openMSX (see "Phase 7 results"): the C library speaks LINK2 through the code of `link2.asm`, every C client is converted, `template.com` too; hardware not run, `playnet`, the asm msxarch and the ROM-Patcher runtimes handled in a follow-up (see "Not done" below) | the phase 7 commit |

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
- `buildClientCommands=yes` no longer touches `target/msxarch.com`: the old asm `msxarch.asm` and its build line were
  deleted (phase 7 follow-up); the C build (`make.bat msxarch`) is the only one.
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

### Phase 5 results

What changed, all with the same bytes on the wire (T3 byte for byte against the model):

| Where | Change | Bytes |
|---|---|---|
| `link2.asm`, frame | `L2_ENTER` is a subroutine; the frame sits below the caller's pushed registers, which are the arguments (no copying in); `L2_START` gone (in modes 0 and 1 `L2_PTR` stays at the buffer); "buffer at 8000h or above" read from the pointer, no flag | |
| `link2.asm`, receive | header and trailer read by one `L2_GET_BYTES`, CRCs compared by `L2_CMP_DE`; one NAK counter (`L2R_NAKS`) and one doubled answer (`L2_ANSWER`); the bad header's ABORT merged into the flood; the mode-2 room check rewritten (same verdicts, `RoomCeiling`) | |
| `link2.asm`, send | attempts counted down; the answer check without reloads; `LINK_COMMAND` with CPIR | |
| `link2.asm`, total | | 1406 -> 1156 |
| `link2.asm`, speed | polled loops count runs of 256 with DJNZ, CTRL+ESC once a run | +11 |
| `msxpi_call.asm` (LINK2) | `_MSXPI`, `PARSE_CALL_PARAMETERS` and mode 2 rewritten: `LINK_RECV` with the mode in A, one header writer for success and failure, the syntax error shares `SYNTAX_ERROR`; `CALL MSXPIVER` shares the receive tail; `ExtractCommand` folded into the parser | 88 in the DOS half |
| legacy code in LINK2 images | `PAYLOAD_RX`, `PAYLOAD_TX`, `PAYLOAD_ADVANCE` (generator), `PAYLOAD_*_BURST`, `MSXPI_GETSTASH`, `LINK_DISCARD` not assembled | 60-90 per image |
| `LINK2_CRC_NOTABLE` | the CRC without its 512-byte table, written for the DOS half (`L2_CRC_BYTE`); no image uses it since the DOS half kept the table (phase 6) | -512 +35 |

Sizes: BIOS half code ends at 0x4A0D (phase 2: 0x4C0D; the CRC table moved down a page), 3,506 bytes free below
the DOS ROM's INIT entry. msxpiext.bin 3,089 bytes (phase 2: 3,345; its table sits on a page boundary, so a few
bytes of code can cost or save 256 of padding). T-states per byte, Z80 work only (`z80bench.py`, MSX M1 wait):

| Loop | Legacy | Phase 2 | Phase 5, table | Phase 5, no table (DOS half) |
|---|---|---|---|---|
| burst CRC / sum pass | 97.0 | 85.1 | 85.1 | 220.1 |
| polled receive | 260.0 | 257.9 | 224.1 | 359.1 |
| polled send | 190.0 | 194.0 | 151.1 | 286.1 |

Not done: the naming pass is limited to the code that moved (the LINK2 branch of the CALL handler,
`link2.asm`); the legacy branch of `msxpi_call.asm` and the legacy routines in `msxpi_bios.asm` keep their
names until the DOS half and the .COM tools move (phases 6 and 7), when they go altogether.

### Phase 6 results

The budget first (2026-10-26, before the decision): with the legacy code removed (about 670 bytes), the CALL
handler rewrite (88) and the table-less CRC, LINK2 (1,154 bytes) still left the DOS half 332 bytes over the
UNAPI driver at 0x7AC9, and the table-less CRC was slower than the legacy sum on every loop. Question 5 below
took the Ethernet UNAPI driver (protocol 2, 1,335 bytes) out of the DOS half instead (design section 6).

What the DOS half is now:

- `msx-dos.mac` defines `MSXPI_LINK2`; the DOS half carries LINK2 with the CRC table (0x7C00-0x7DFF). MSXPi
  code ends at 0x7BF7; **512 bytes free** below 0x8000 (the build prints it).
- DSKIO: reads are one `LINK_RECV` mode 2 a sector, writes one `LINK_SEND` a sector, bursting from 8000h up
  when the Pi and /WAIT allow (**burst writes are back**); the sector info and the commands go through
  `LINK_SEND`/`LINK_COMMAND`. `DSKIO_TXSIZE`, `DSKIO_RXSIZE` and their files are gone.
- DSKIO runs with interrupts off (the caller's state given back) instead of the busy flag, which only the
  ROM's own Ethernet driver read (design section 6). INIENV is a plain RET. MYSIZE 5 bytes (was 181).
- `ETHUNAPI.COM` (the RAM driver) now goes out with the ROM in `target/`, so `msxpiupd` delivers it: it is
  the Ethernet driver for MSX-DOS booted from the DOS half. `ethrom.asm` (protocol 2, ROM) is no longer in
  any image; the build still assembles it because `test_eth3_z80` runs it.
- The DOS ROM's header addresses did not move (INIT 0x57BF, STATEMENT 0x65DB), so the BIOS half is the
  phase 5 one with a new BuildId.

Tests: see LINK2-TEST-PLAN.md "Phase 6".

Not done: T6 on hardware (COPY both ways, the pcopy batch, the COPY that failed with burst writes before);
`msxpiupd` from a LINK2 MSX-DOS (it uses pcopy and p, still legacy, against a dual-stack server, so it is
expected to work); the game quickstarts (SOCCER, YIEAR) say to run INL after the card's driver, which on an
MSXPi DOS half now means ETHUNAPI first.

### Phase 7 results

**The C library.** `C-common/lib/msxpi-bios.c` has no protocol code of its own any more. Its LINK2 is
`asm-common/include/link2.asm`, the very code of the ROM: `asm-common/transport/link2_c.py` (run by
`generate.py`) turns it into SDAS (`C-common/lib/link2_generated.h`: conditional assembly evaluated, macros
expanded, constants as numbers, `#` on immediates), so the Python model `Msx` is the reference for the C clients too.

| Where | Change |
|---|---|
| `link_command(cmd, appendTail)` | was `SendCommandToMSXPi`; one `link_send` of the command string |
| `link_send(src, size)` | one whole transfer to the Pi (was `SENDDATA2`) |
| `link_recv(mode, buffer, maxblock, &received)` | one whole transfer from the Pi, modes 0 (drop), 1 (print each block) and 2 (blocks one after another) (was `PerformHandshake` + `RECVDATA` / the `RECVDATA_ONEBLOCK` loop) |
| `link_recv_open` / `link_recv_next` | the same transfer a block at a time, for a caller that puts each block somewhere of its own (msxarch's ROM banks, showpage, pcopy's one-block replies). The frame is the one `LINK_RECV` keeps on the stack, in 26 bytes of RAM |
| `printstdout` | `link_recv` mode 1 |
| gone | `CHKPIRDY`, `PIREADBYTE`, `PIWRITEBYTE`, `RECVDATA`, `RECVDATA_ONEBLOCK`, `PerformHandshake`, `SENDDATA2`, `payload_rx`/`payload_tx` and their generated header (`payload_generated.h`), the retry loops in the clients (LINK2 retries inside the transfer) |
| the CRC table | 512 bytes on a page boundary, built in RAM at the first transfer (`l2_table_mem`, 768 bytes of BSS) instead of carried in every program; "built already" is told from four table bytes, since the programs are linked with `--no-std-crt0` and BSS is not cleared |
| `PRINT`, `STORE_BYTE` | the two routines `link2.asm` expects of its host: a C `Print` call and `ld (de),a` |
| `RC_PROTOERR` (F0h) | in `msxpi.h`, with a `parseConnError` message |

Clients converted: `p` (and `showpage`, which it includes), `pcopy`, `ssh`, `nitros`, `mchat` (+ `mchat_local`),
`pchess`, `pchess1`, `pcheckers`, `msxarch`, `templatc`, and `template.com` (asm: `MSXPI_LINK2`, `LINK_COMMAND`,
`LINK_PRINT`). Each of the ssh/nitros/mchat/pchess polls is one `link_command` and one `link_recv` of the 256-byte
block. Sizes: a client grows about 600 bytes (the code of `link2.asm` against the two payload loops and the
handshakes) and 768 bytes of BSS; `pchess_memory_test.py` still passes (4,384 bytes free with INL loaded).

**Also**: `SENDDATA2`/`RECVDATA` have no limit question left, since a LINK2 transfer is bounded by `LINK2_RETRIES` and
`LINK2_SENDER_CAP`; **pcopy deletes the partial file when a download is aborted** (`abort_download`: close, then BDOS 13h).
The BSS is not cleared: `l2ctest.c` found its own counters uninitialised.

**The three remaining tools (phase 7 follow-up, 2026-10-26)**:

- `playnet`: converted. `piCommand` is `LINK_COMMAND` + `LINK_RECV` mode 2; `playnet save` sends the 8 byte header and
  the area as **two transfers** (`LINK_SEND`, then `LINK_SEND_SIZE` with blocks of BLKSIZE); the server joins them
  (a first transfer of exactly 8 bytes starting `PNSV`; a legacy client's single transfer is longer and still works).
  The contiguous-buffer idea did not apply: the game image already occupies RBUF when the save runs. Two things the
  conversion found: `LINK2_CRC_NOTABLE` (the 512 byte table does not fit under CRCT; PLAYNET.COM 11,049 bytes) makes a
  CRC pass ~70 us a byte, so an 8 KB burst block timed the Pi out (hence BLKSIZE blocks); and the area is read twice
  (burst, then the CRC pass), so `saveDos` runs with interrupts off or JIFFY & co. change under the CRC.
- `msxarch.asm` (the old asm version): deleted; the C `msxarch.c` is the only one.
- `ROM-Patcher/profiles/*` (arctic, goonies, nemesis, vampire; the others use the playnet path and had no legacy
  call): `runtime.asm` has `DEFINE MSXPI_LINK2` and `exchange` is `LINK_COMMAND` + `LINK_RECV` mode 2 (256 byte block:
  a longer reply ends in RC_PROTOERR, i.e. the link is disabled, where the legacy code treated it as an invalid PID).
  The shared sources in `goonies/src` now carry the current `msxpi_bios.asm`, `include.asm`, `payload_generated.asm`,
  `link2.asm` and `link2_crc_table.asm`; the Goonies bounded `PAYLOAD_WAIT` (about 15 s, so a missing Pi cannot freeze
  the game) is kept, returning RC_CONNERR. Runtime 3,015 bytes, `code_end` CBC7 (limit D000).
- Hardware: no C client was run on the real machine.

## Open questions (defaults used until answered)

1. **.COM tools and the C library** (pcopy, p, mchat, ssh...): move them to LINK2 in this
   project, after the DOS driver (phase 7)? *Answered by default: yes, done in phase 7; `playnet`
   is the exception (see "Phase 7 results"). The server keeps serving the legacy protocol.*
2. **Ethernet frame check**: keep the 8-bit sum, fixing only GO and `RC_OK` (design section 4),
   or also move it to CRC-16? CRC costs about +40 T-states a byte on every frame (about 1.5x the
   per-byte cost of a send) on the INL hot path. *Default: keep the sum; IP, TCP and UDP check
   their own data.*
3. **The real Pi's GPIO engine**: native (`MSXPI_NATIVE_GPIO=1`) or the Python fast path? Both get
   the GO bursts, but the speed baselines must be measured on the engine you actually run.
   *Default: native.*
4. **Branch name** `feature/link2`: in use and pushed.
5. **Phase 6, the DOS half**: LINK2 did not fit. *Answered (2026-10-26): take the Ethernet UNAPI driver out
   of the DOS half and use the CRC table there.* Ethernet stays in the BIOS half and the RAM driver.

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

## Phase 6 - MSX-DOS driver on LINK2 (done: see "Phase 6 results")

1. Assemble the DOS half with `-DMSXPI_LINK2`, using the optimised code. DSKIO keeps its
   structure; `DSKIO_TXSIZE`/`DSKIO_RXSIZE` go (bursts are negotiated in the HELLO2 exchange).
2. **Burst writes come back**: sector writes with OTIR and GO.
3. If the table does not fit, use the fallbacks in design section 6, chosen from the measured
   budget.
4. Test plan T4/T5 with MSX-DOS (COPY both ways, the pcopy batch) and T6 on hardware: the COPY that
   failed with burst writes before.
5. **Update path**: `msxpiupd` from a LINK2 MSX-DOS. The server already speaks both protocols, so
   the order no longer matters, and an old server gives a clean error.

## Phase 7 - .COM tools and the C library (question 1) (done: see "Phase 7 results")

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
