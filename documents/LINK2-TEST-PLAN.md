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
- **Register contracts**: SENDDATA, PerformHandshake, RECVDATA_ONEBLOCK and SendCommandToMSXPi
  preserve and return what their callers expect, checked with a stub link that scripts the Pi's
  bytes.

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
  - buffers in page 2 and page 3 (bursts) and in page 1 (polled, WRSLT)
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

## Reporting

Each milestone commit carries the numbers: T1/T3 pass counts, T3 T-states against the baseline,
the T5 verdict table, T6 KB/s and soak counts. The documents get a results section per phase.
