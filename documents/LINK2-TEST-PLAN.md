# LINK2 - test plan

Design: LINK2-DESIGN.md. Phases: LINK2-IMPLEMENTATION-PLAN.md.

**Pass criteria, for every LINK2 configuration and every fault test:**

- **0 HUNG**: every run reaches its end marker, no CTRL+ESC or reset needed.
- **0 CORRUPT**: no wrong byte ever lands in a file or buffer.
- **FAILED only as reported aborts**, with the error on screen and both ends idle afterwards (the
  next command works).
- **No speed regression**: per byte, no path slower than its phase 0 baseline.

## T0 - baselines (phase 0)

| Item | How | Recorded |
|---|---|---|
| Z80 loop cost, legacy | sz80: PRB_SUM, PAYLOAD_RX, PAYLOAD_TX, ETH_TX_BLOCK sum | T-states/byte |
| ROM budget | listings from `software/build` | free bytes per half, per region |
| Legacy fault matrix | `fault_inject_openmsx.py`, rate 1.5e-4, seeds 1-8, shipped ROM and server | verdicts (reference: BLOCK-RETRIES-FAULT-INJECTION.md) |
| Hardware speed, legacy | Canon V-25 + Pi: CALL MSXPI("2,...") of 32 KB, pcopy 41 KB, COPY 41 KB, timed with JIFFY | KB/s |

## T1 - server protocol unit tests (phase 1, `link2_sim.py`, runs without an MSX)

The real server code against the Python MSX model, over the lockstep simulated link:

1. **Clean transfers** in both directions, sizes 0, 1, 255, 256, 512, 513, 8192 and 8193 bytes;
   multi-block; burst and polled; the flag combinations of 3.2.
2. **One fault at every position**: flip one bit in every byte position of a transfer, one run per
   position (header, header CRC, header ACK, GO, payload, CRC, ACK). Each run must recover with
   identical data, or abort cleanly with both ends idle.
3. **Lost ACK**: corrupt the payload ACK so the sender resends; the receiver must discard the
   duplicate seq and ACK again. Run it for a middle block and for the final block (expected: the
   sender reports an error, no data damage).
4. **Limits**: NAK forever, so the receiver ABORTs after `LINK2_RETRIES`. Receiver gone, so the
   sender stops at `LINK2_SENDER_CAP`.
5. **Mixed traffic**: legacy READY transfers and HELLO2 transfers alternate in one session; both
   still work, with no state leaking from one to the next.
6. **Random faults**: 10,000 random transfers at several fault rates. The undetected-error count
   must be 0, and must stay 0 with multi-bit faults of up to 3 bits per block.
7. **The old server**: the MSX model against the legacy server gets RC_PROTOERR within 16
   exchanges, with no hang.
8. **Slips** (`link2_faults.sweep_slip`): at every MSX transfer of a transfer, one completes on
   the MSX side only (a write lost in the CPLD latch, a stale read), in both directions. The
   server keeps serving afterwards, as the real one does, and the MSX retries the next command up
   to 3 times. Pass: never wrong data, never a hang, and the next command works within the 3
   tries.
9. **Capacity**: an MSX that sends more than the server's buffer is ABORTed in the header slot of
   the block that does not fit, and is never told the transfer succeeded.
10. **End mark**: a block whose CRC is right but whose end mark is wrong is NAKed and resent.
11. **NAK limit per block**: NAKs spent on a duplicate do not count against the next block.

Item 6 runs 300 transfers by default; `LINK2_SLOW=1` runs the full 10,000 (about 15 minutes).

**How to run** (from `software/Server/Python/tests`, Windows Python):

```
python -m unittest test_link2                                    # T1, about 3 minutes
LINK2_SLOW=1 python -m unittest test_link2.Faults.test_random_multibit   # item 6 in full
python link2_faults.py flip                                      # item 2 in full, all sizes
python link2_faults.py slip                                      # item 8 in full, about 5 minutes
```

Lines like `link_recv: block index ... - out of step` during these runs are the legacy framing
reacting to a stray 0xAA while the simulated server hunts. They are expected; the verdicts are
what counts.

## T2 - legacy regression (phase 1 onward, every milestone)

Shipped ROM and tools against the new server, in openMSX:

- `client_smoke_openmsx.py` for p, pcopy and mchat
- `fault_inject_openmsx.py` with the shipped ROM: verdicts identical to the T0 legacy matrix,
  except the pcopy upload, which must now complete
- boot from MSXPi (MSX-DOS), then `msxpiupd feature/link2` against a scratch MSXPI_HOME
- **after each rename commit** (server handlers, then each MSX image): the whole T2 set, plus
  - a search showing no old name is left outside the alias definitions; once the aliases are
    removed, no old name at all
  - an import of every server module, and every ROM image and .COM still assembling
  - byte-identical binaries where only names changed: a pure rename must not move a single byte

## T3 - Z80 routine tests (phase 2 and 5, sz80)

- **CRC correctness**: `LINK_CRC` and the table against `binascii.crc_hqx` for 1,000 random
  buffers, lengths 0-8192.
- **Cost**: T-states per byte of the CRC pass, the polled RX/TX loops with CRC and the burst
  checksum pass. Each must be no worse than its T0 legacy counterpart.
- **Register contracts**: `LINK_SEND`, `LINK_OPEN`, `LINK_RECV_BLOCK` and `LINK_COMMAND` (and
  their legacy aliases) preserve and return what their callers expect.
- **Byte-for-byte against the reference**: assemble `link2.asm` with `-DLINK2_TEST`, which turns
  `LINK_SEND_BYTE` / `LINK_RECV_BYTE` (and the burst entries) into reads and writes of two RAM
  queues, so no port I/O is needed in sz80. A Python driver fills the Pi-side queue with what the
  server would send (generated by running `msxpi_link2` against `link2_sim`), runs the routine,
  and compares the bytes it wrote with what `link2_sim.Msx` writes for the same input. That
  covers every case of design section 8, including NAK/ABORT answers, duplicates, the final
  block's doubled answers, the end mark and the ABORT flood.

## T4 - openMSX functional tests (phase 2 onward)

- **Machines**:
  - Canon_V-25 (MSX2, no floppy) with `set msxpirom_bank BANK1` (BIOS-only half)
  - a machine with a drive (e.g. Panasonic_FS-A1WSX) for msxpiext.bin, MSXPi ROM switched off
    (`set msxpirom_sltsl OFF`), then `BLOAD "MSXPIEXT.BIN",R`
- **ROM under test**: through the MSXPiTest extension (`C:/tmp/fi/msxpitest.rom`). The server runs
  from the worktree, with MSXPI_HOME a scratch copy.
- **CALL MSXPI suite** (BASIC program LINK2T.BAS):
  - `CALL MSXPIVER`
  - all three response modes ("0,...", "1,...", "2,addr,...")
  - responses of 0, 1, 512, 8 KB and 32 KB bytes
  - buffers in page 2 and page 3 (page 1 is ROM under BASIC)
  - every result compared with what the server sent (the server's `l2test` command returns a
    seeded pattern, and its CRC is printed on both sides)
- **L2TEST.BIN** (downloaded by CALL MSXPI, run through `DEFUSR`):
  - bulk MSX -> Pi sends of 512 bytes to 32 KB, burst and polled; the server verifies and reports
  - timing loops, which print T-state-derived throughput
- **Old server**: the LINK2 ROM against a legacy server (the `--server-src` copy) prints the
  "server does not speak LINK2" error and returns to BASIC.
- **Jumper**: both halves from one `msxpi32k.rom`. With BANK2 the DOS half boots legacy, with
  BANK1 the BIOS half speaks LINK2, against the same running server.

## T5 - fault-injection matrix (phase 2 and 6)

- **Harness**: `fault_inject_openmsx.py`, extended with a BASIC workload mode for the BIOS-only
  half: the LINK2T.BAS suite plus L2TEST sends, results checked by the harness.
- **Runs**: rates 1.5e-4 and 5e-4, seeds 1-16, directions both/rx/tx.
- **Slips in openMSX** (to build): `fault_server.py` gains `FAULT_SLIP_RATE`. On a slip it answers
  one MSX transfer from the TCP link without counting it - the Pi offers the same byte again for
  the next transfer - which is what a stale read or a lost write does to the real link. Same
  pass criteria, and the slip sweep of T1 is the reference for what to expect.
- **Pass**: 0 HUNG, 0 CORRUPT. At 1.5e-4, aborts well below the legacy matrix: with 10 retries
  and receiver-side decisions, an 8 KB block should almost never exhaust its attempts.
- **Phase 6**: the same matrix with the MSX-DOS workload (pcopy down and up, COPY both ways).

## T6 - real hardware (phase 4 onward; Canon V-25, v1.6 CPLD, Pi on the engine from question 3)

1. **Install**: `msxpiupd feature/link2` from MSX-DOS, flash `msxpi32k.rom`, set the jumper to the
   BIOS half.
2. **Functional**: the T4 CALL MSXPI suite.
3. **READY race**: L2TEST sends 1,000 bursts of 512 bytes with OTIR. All verified by the server,
   0 failures. This is the case that failed on this machine before (a sector shifted by 10 bytes).
   As a control, rerun the legacy-style burst (no GO byte) to confirm the race reproduces on
   this unit.
4. **Speed**: KB/s against the T0 hardware baseline, for CALL MSXPI 32 KB and L2TEST sends.
   Expected: CALL MSXPI no slower (bursts are new in the BIOS half), sends much faster than
   polled.
5. **Ethernet (phase 3)**: ETHTEST, then ETHBENCH S/R in wait and polled mode, then an INL session
   (ping, telnet, an mchat game) for 30 minutes.
6. **Soak**: CALL MSXPI loads and L2TEST sends in a loop for 2 hours. Count errors and retries;
   expect 0 aborts.
7. **Phase 6**: boot MSX-DOS from LINK2, COPY 41 KB to and from MSXPi drives 50 times
   (byte-identical, checked with the server's copy), pcopy, then `msxpiupd feature/link2` itself.

## Results so far

**Phase 1 (server dual stack), 2026-10-25:**

| Test | Result |
|---|---|
| T1 unit tests (`test_link2`) | 14/14 pass |
| T1.2 single-bit flip at every position (burst and polled, both ways) | 0 failures |
| T1.6 random 1-3 bit faults, rates 1e-3..1e-2, 10,000 transfers | 0 corrupt, 0 hung |
| T1.8 slips at 2,384 positions (512 and 600 bytes, both ways) | 0 corrupt, 0 hung, 0 stuck; next command works within 3 tries |
| T2 openMSX, shipped ROM against the new server | fault-free PASS; with faults (rate 1.5e-4, seeds 1-4) the same verdicts as the shipped server, every upload completes |
| T0 Z80 baselines, T3, T4, T5, T6 | see phase 2 below (T6, hardware, not run) |

What the tests changed in the design is recorded in LINK2-DESIGN.md: section 3.7 for the five
single-flip desyncs, the two slip failures and the CRC coincidence that led to the end mark, and
section 3.3 (capacity) for the block that used to be ACKed before it was found not to fit.

**Phase 2 (MSX core), 2026-10-25** - the assembled `link2.asm`, BuildIds ROM 20261025.079, server 20261025.081:

| Test | Result |
|---|---|
| T3 byte for byte against `link2_sim.Msx` (`test_link2_z80`: clean both ways and all flag combinations, small blocks, single flips, slips, header and answer damage) | pass |
| T1 on the Z80 code (`LINK2_MSX=z80 python -m unittest test_link2`): clean, limits, mixed, flip sweep, slip sweep, no-wait, random 1-3 bit faults | all pass |
| T3 cost, T-states per byte (`z80bench.py`; the Z80's own work, every port answering at once) | burst CRC pass 72.1 against the legacy sum pass 86.0; polled receive 224.8 against 231.5; polled send 167.9 against 168.9 (the CRC included in both). Polled receive stores through a stub here; the real `STORE_BYTE` adds about 20, which the wait for the Pi hides |
| ROM budget (`software/build` prints it) | BIOS half: code ends at 0x4C0D (legacy 0x4612), 2,994 bytes free below the first fixed entry (0x57BF); msxpiext.bin 3,345 bytes |
| T4 openMSX, Canon_V-25, BIOS half, clean (`link2_openmsx.py`) | `CALL MSXPIVER`, `CALL MSXPI` modes 0/1/2, responses of 1 to 16,384 bytes into pages 2 and 3, L2TEST.BIN downloaded and run: 11 sends of 1 to 12,000 bytes and 50 x 512 (all with OTIR when the size allows), all verified by the server: 32 of 32 pass |
| T5 openMSX fault matrix, rates 1.5e-4 (seeds 1-8) and 5e-4 (seeds 1-8), both directions, 32 steps a run | 0 HUNG, 0 CORRUPT. 1.5e-4: 252 pass, 4 reported aborts. 5e-4: 201 pass, 55 reported aborts. Every abort left the link idle (the next step worked) |
| T4 old server, jumper, T5 slips in openMSX, T6 hardware | not run |

Two test-harness mistakes cost time and are worth knowing: a test buffer at 8000h sits on BASIC's program
area (the next BASIC line then runs garbage), and the BASIC screen is 29 columns wide, so a result line must
be short enough not to wrap. The Z80 run found one real bug in the first draft (a damaged flags byte made
the MSX abort a burst that the model reads polled); it is fixed and recorded in the design, section 8.8.

**Phase 3 (Ethernet protocol 3) and the audit of phases 2 and 3, 2026-10-26** - BuildIds ROM 20261026.080, server
20261026.082 (the audit's fixes are listed in LINK2-IMPLEMENTATION-PLAN.md, "Audit of phases 2 and 3"):

| Test | Result |
|---|---|
| `test_ethshuttle` (shuttle, protocols 2 and 3, the version kept across a restart, a store that fails) | 18/18 pass |
| `test_eth3_z80`: the assembled driver, v2 and v3, /WAIT and polled, against the shuttle (probe, in_status, get_frame, send_frame 16..1514, bad checksum, GO placement, a refused length, a server restart) | 8/8 pass; the refused-length test fails on the phase 3 driver (it sent the frame into the opcode hunt) |
| T3 `test_link2_z80`, with the new case: a block that ends exactly at 10000h from below F380h | 9/9 pass; the new case fails on the phase 2 code |
| T1 `test_link2` | 14/14 pass |
| T1 on the Z80 code (`LINK2_MSX=z80`) | 14/14 pass |
| T4 openMSX, Canon_V-25, BIOS half, clean | 32/32 pass |
| T5 openMSX, rate 5e-4, seeds 1-4, 32 steps a run | 0 HUNG, 0 CORRUPT: 99 pass, 29 reported aborts, all on blocks of 8 KB or more (phase 2: 201 pass, 55 aborts over 8 seeds). The step after every abort worked |
| ETHTEST/ETHBENCH in openMSX with a disk system, T6 hardware | not run: the BIOS half's driver installs only with a disk system, and Canon_V-25 has none |

**Phase 4 (real hardware), 2026-10-26.** MSX booted from MFRSCC+SD with the MSXPi cartridge in slot 2 and the
A14 jumper set, so the DOS half is off and CALL MSXPI is the BIOS half (LINK2). ROM 20261026.080, server
20261026.083. (A first round booted MSX-DOS1 from the MSXPi EEPROM: that exercised the legacy half against
the new server and `L2TEST.BIN`, which carries its own LINK2 code, so only the L2TEST bursts counted.)

| Test | Result |
|---|---|
| T6.2 `CALL MSXPIVER`, three response modes, `l2test pat 512 7` (RC 0, size 512, 0 byte errors) | pass |
| T6.3 L2TEST sends of 512 bytes with OTIR from D000h, 1000 repetitions | **pass**: `OK=03E8 F=0000 T=08EC`; 38.7 s by stopwatch = 12.9 KB/s (T = 2284 jiffies = 38.1 s at 60 Hz, so JIFFY agrees for short transfers). Smoke run 10 x 512 gave OK=000A F=0000 six times |
| T6.4 `l2test pat 8192`, 100 downloads into D000h, all 8192 bytes | BAD=0; 37.3 s by stopwatch = 21.4 KB/s |
| JIFFY/TIME as a timer | unusable for long transfers: interrupts are off during transfers and frames are lost (a run of 20 x 8 KB read 29 jiffies). Time with a stopwatch or the server log |
| T0 hardware baseline: the same 100 x 8 KB loop on the DOS half (legacy protocol, same build 20261026.080, DOS1 boot) | BAD=0; 90.9 s = 8.8 KB/s, one run. LINK2 (37.3 s, 21.4 KB/s) is 2.4x faster |
| T6.6 soak, BIOS half, 1 h 40 min: 1000 x 512 OTIR sends plus 20 x 8 KB downloads per round, in a loop | server log: 128,433 `L2TEST OK`, 0 `L2TEST BAD` (about 128 rounds, 64 MB of sends and 20 MB of downloads). Screen at the end: ROUND 136, BAD=0, L2T OK=03E8 F=0000 (136,000 sends on the MSX side; the log read 128,433 and later 129,240 while the soak was still running, still about 6.8k below 136,000, cause not found, so the log count is a floor). Retry and abort counts were not reported. A first soak program broke after round 1 because the 8 KB download at D000h overwrote L2TEST's parameters at E000h (a test-program bug, not LINK2); the fixed program rewrites them each round |
| Control (legacy burst without GO), soak, ETHTEST/ETHBENCH, MSX-DOS half | not run |

The baseline was taken on the same EEPROM, DOS half against BIOS half, no reflash.

**Phase 5 (optimise), 2026-10-26.** The BIOS half from the current sources next to the shipped DOS half
(20261026.080), server 20261026.083:

| Test | Result |
|---|---|
| T3 `test_link2_z80` (with the new `Crc` test: both CRC variants against `binascii.crc_hqx`, check value 0x29B1), `test_eth3_z80`, T1 `test_link2` | 32/32 pass |
| T3 `test_link2_z80` with the table-less CRC (`LINK2_CRC_NOTABLE=1`) | 10/10 pass |
| T1 on the Z80 code (`LINK2_MSX=z80`), table / table-less | 14/14 and 14/14 pass (clean, limits, mixed, flip and slip sweeps, no-wait, random 1-3 bit faults) |
| T3 cost (`z80bench.py`), table | burst CRC pass 85.1 (legacy 97.0), polled receive 224.1 (260.0), polled send 151.1 (190.0); phase 2 was 85.1 / 257.9 / 194.0 |
| T3 cost, table-less (DOS half) | 220.1 / 359.1 / 286.1: slower than legacy on every loop |
| T4 openMSX, Canon_V-25, BIOS half, clean | 32/32 pass (a first run found the CALL handler writing mode-2 data past the command: `LINK_COMMAND` returns DE moved, as `LINK_SEND` does; fixed before this run) |
| T5 openMSX, rate 5e-4, seeds 1-4, 32 steps a run | 0 HUNG, 0 CORRUPT: 99 pass, 29 reported aborts, all on blocks of 8 KB or more: the same as phase 3 |
| Legacy DOS half from the current sources | byte for byte the shipped one (the shared files leave it alone) |
| T6 hardware | not run |

**Phase 6 (MSX-DOS driver on LINK2), 2026-10-26.** The DOS half with LINK2 and the CRC table, no Ethernet
driver (LINK2-IMPLEMENTATION-PLAN.md, "Phase 6 results"); `fault_inject_openmsx.py` (MSX-DOS booted from the
DOS half: pcopy of three files into A:, which is sector reads and burst sector writes, MCHAT.COM uploaded
back, `p date`):

| Test | Result |
|---|---|
| clean run | PASS: all files identical, 0 retry prompts. The server saw 198 Pi -> MSX bursts of GO + 512 (sector reads) and 328 MSX -> Pi bursts of 512 (**sector writes with OTIR**, off since before LINK2) |
| rate 1.5e-4, seeds 1-4 | 0 "Abort, Retry" prompts and 0 sector checksum mismatches (the legacy DOS half on the same seeds: 4 prompts, 30 mismatches). pcopy, still legacy (phase 7), aborted a file in all four runs (legacy DOS half: three), always detected ("Transfer aborted by server", the partial file left behind) |
| the one silent corruption (seed 3) | in pcopy's legacy **upload**: two flips of bit 3 in opposite directions in one 8 KB block (FAULT #103 and #104, rx), which the 8-bit sum cannot see. The LINK2 sector reads around it took six faults and recovered. This is design section 2's first row, and phase 7's job |
| T4 BIOS half, T3, T1 | unchanged since phase 5 (`link2.asm` is the same code); T4 run again on the built ROM: 32/32 pass |
| clean run on the built ROM (BuildId ROM 20261026.082) | PASS |
| T6 hardware (COPY both ways, the pcopy batch, the COPY that failed with burst writes) | not run |

Note on the harness: `--seed` takes several values after one flag (`--seed 1 2 3 4`); repeating the flag keeps
only the last.

## Reporting

Each milestone commit carries the numbers: T1/T3 pass counts, T3 T-states against the baseline,
the T5 verdict table, T6 KB/s and soak counts. The documents get a results section per phase.

## How to run the MSX-side tests

```
python -m unittest test_link2_z80                      # T3, byte for byte against the model, about 2 minutes
LINK2_MSX=z80 python -m unittest test_link2            # T1 on the Z80 code, about 10 minutes
python z80bench.py                                     # T-states per byte
python link2_openmsx.py                                # T4: ver, pat, bin (from tests/, after ./build)
python link2_openmsx.py --rate 0.00015 --seed 1 2 3 4 --port 5051    # T5
```
