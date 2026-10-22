# MSXPi Ethernet driver, protocol 2: end-to-end test plan

Branch `feature/eth-tx-otir`. Covers the OTIR send, the inline receive in `ETH_IN_STATUS`, the discard without transfer, and the
protocol-version refusal. How to build and run each item: `ETH-DRIVER-SPEED-TEST-HANDOVER.md`. Design: `ETH-DRIVER-SPEED-HANDOVER.md` and
`software/UNAPI/PHASE1_DESIGN.md` 3.5.

The ROM and the Pi server must come from this branch together. An old ROM against this server is not refused (it does not check the
version) and desynchronises on the first small received frame; a new ROM against an old server is refused by design (T5).

Every level runs in **both transport modes** where it can: wait (`Mode: 01`, the OTIR/INIR path) and polled (`ETHMODE P`, `Mode: 00`).

---

## Level 0: build checks (no emulator)

| # | Check | Pass |
|---|---|---|
| B1 | `UNAPI/build.sh --no-copy` | 6 x `Errors: 0`; `ethrom.bin 1314 bytes`, `21 bytes free below 8000h` |
| B2 | DOS ROM half (zmac `msx-dos.mac`) | zmac exit 0; listing shows `ld hl,MYSIZE` = `21 B5 00` (181) |
| B3 | BIOS-only half (sjasmplus `msxpibios.asm`) | `Errors: 0`, `include data: name=ethrom.bin (1314 bytes)`; no `ASSERT` failure |
| B4 | Both halves | the bytes from offset 3AC9h to the end are identical in the DOS half and the BIOS-only half; below 7AC9h only MYSIZE differs from `target/*.rom` on master (DOS 57FA-57FBh and 586Eh, BIOS-only 402Ah) plus any BuildId bump |

## Level 1: Pi side unit tests (no MSX)

| # | Test | Pass |
|---|---|---|
| U1 | `python -m unittest test_ethshuttle -v` in `software/Server/Python/tests` | all pass: probe says version 2; IN_STATUS empty is 5 zeros; a 67-byte frame comes inline with checksum and leaves the queue; 128 inline, 129 announced only (flag 1, stays queued); short frames padded to 64 before the length is reported; GET_FRAME unchanged for 600 bytes; maxlen 0 returns only the header and drops the frame; SEND_FRAME at 16/64/255/256/257/512/1514 reads payload+checksum in ONE `read_burst(n+1)`; bad checksum gives RC 03 and nothing is transmitted; without a burst reader the send still works byte by byte |
| U2 | `python -m unittest test_ethnat test_netplay test_netcore` | unchanged (regression: the shuttle's callers) |

## Level 2: openMSX harness (MockLink, one emulator)

Run with the rebuilt ROM pair installed in the openMSX share the harness uses (see the handover: sha1 in `MSXPi.xml`), and the
rebuilt `.COM` tools on the served `msxpiboot.dsk`.

| # | Test | Mode | Pass |
|---|---|---|---|
| H1 | `wsl_probe`, `unapi_discovery`, `unapi_install` | wait | driver found; `ETHTEST` prints `Mode:  01` and no "protocol version" message |
| H2 | `wsl_ethops` (ETHTEST: GETINFO, HWADD, NETSTAT, IN_STATUS, GET_FRAME, ETHTEST T send) | wait, then `ETHMODE P` | all routines answer; `Snd: 00`; `P57` shows wait mode off after |
| H3 | `wsl_bench` (ETHBENCH, 2048 x NETSTAT / HWADD) | both | every `ok=0800`; jiffies within 10 % of master's run on the same machine |
| H4 | **`ETHBENCH S`** (new: ETH_SEND_FRAME, 32 frames at 16, 64, 255, 256, 257, 512, 513, 1514) | wait then polled, in one run | all 16 lines `ok=0020`; server log has no `send checksum mismatch` and no `SPI_BurstIn` / `payload read failed` lines; MockLink's sent count +256 |
| H5 | `wsl_waitmode` | wait | unchanged pass |
| H6 | `wsl_linkclaim`, `wsl_pcopy`, `dos_dir`, `big_copy` | wait | disk traffic with the driver resident: no stray `0xC5`, no "Insert a DOS disk", PCOPY data identical |
| H7 | `wsl_inl` / `win_inl_ping` / `win_inl_dns` (INL over MockLink or the NAT link) | both | ping replies, DNS resolves; INL installs with its usual messages |
| H8 | Inline boundary (needs a frame of 128 and of 129 bytes to reach the MSX): ping the MSX with ICMP payloads of 86 and 87 bytes (Ethernet frame 128 / 129) | both | both answered; with `MSXPI_PROFILE`/server log, 128 arrives in one C5 transaction, 129 in C5 + C6 |
| H9 | Discard path (ETH_GET_FRAME with HL=0): a harness Tcl that injects a frame larger than 128 bytes and calls routine 8 with HL=0 through the debugger, or any client known to discard | wait | A=0, BC = the frame length; the server log shows a `C6` with maxlen 0 and only 3 reply bytes; the next IN_STATUS reports the following frame, not leftovers |

## Level 3: version refusal

| # | Test | Pass |
|---|---|---|
| T5 | New ROM, server from `master` (PROTO_VERSION 1) | `ETHTEST` prints `Mode:  02` and the three-line "speaks another Ethernet protocol version" message; every routine that crosses the wire fails cleanly (NETSTAT 00, IN_STATUS none); `ETHMODE` prints `refused - Pi protocol mismatch`; `ETHBENCH` stops with the message; INL reports no network instead of hanging; the disk keeps working (DIR, PCOPY) |
| T6 | Same session, switch the server to this branch's, then run `ETHTEST` again (it calls ETH_RESET first) | `Mode:  01` again, everything works - no MSX reboot |
| T7 | Old ROM (master's `target/msxpibios.rom`), this branch's server: document only | expect desync on the first received frame of 128 bytes or less. Not a supported combination; record what is seen so the release notes can say it |

## Level 4: two-emulator rig, A/B performance (`feature/tcpip-games`)

Same rig, same scenario as the baseline in `ETH-DRIVER-SPEED-HANDOVER.md` section 1: both players over TCP/IP, Soccer, 1200 frames,
`PERF_PROF=1`, `SCENARIO=mixed BOTH=1`, on a merge of this branch into `feature/tcpip-games` (the touched files are identical on both).

| # | Measure | Baseline (unchanged ROM) | Pass |
|---|---|---|---|
| R1 | Game frames | - | `cmp_pair.py` prints IDENTICAL; no IRC drop, no desync |
| R2 | fps per node | H 19.44, C 19.46 | higher; record the figure |
| R3 | ms in `XCHG` per frame | 20 | lower; record |
| R4 | link bytes per frame | 91 | lower (one C5 transaction fewer per received frame) |
| R5 | profile samples in `7C00`/`7E00`/`7F00`/`7B00` (driver link code) | 8082 + 5281 + ~1100 | lower share of the 47 571 |
| R6 | Repeat R1-R5 with the driver forced polled on both nodes (`ETHMODE P` in each before PLAYNET, if the rig allows) | - | R1 holds; numbers recorded for reference |

The expected gain is about 1.4 ms per send from OTIR and one Pi dispatch per received frame from the inline receive. If R3 does not move,
the next suspect is the Pi's per-transaction latency (`MSXPI_PROFILE=1`), not the driver.

## Level 5: real board (the decisive level - OTIR in wait mode has never run on hardware)

Pi on this branch's server, MSX on the rebuilt ROM. Watch the server console throughout.

| # | Test | Pass |
|---|---|---|
| P1 | `ETHTEST` | `Mode:  01`, MAC 02:4D:53:58:50:69, `Net: 01`, no mismatch message |
| P2 | `ETHTEST T` (one 42-byte ARP send) | `Snd: 00` |
| P3 | **`ETHBENCH S`** | all lines `ok=0020` under W and P. Any shortfall on a W line but not the P line of the same length = OTIR outrunning the Pi: capture the server log (`send checksum mismatch`, `SPI_BurstIn: CS was already low before READY`, native GPIO `transfer failed`) |
| P4 | `ETHBENCH` (no argument) | every `ok=0800`; jiffies vs master's ROM within noise (receive path barely changed) |
| P5 | Ping the MSX from the Pi: `ping -c 200 <msx ip>`, then `-s 86` (frame 128, inline) and `-s 1000` (two-step + 1042-byte OTIR reply) | 0 % loss in each; RTT recorded against the old 40-60 ms |
| P6 | `HGET` of a file of a few hundred KB | completes, file identical (compare checksum on the Pi) |
| P7 | Telnet session, typing for a minute | no lost keystrokes, no hang |
| P8 | PLAYNET over TCP/IP (`PLAYNET /T soccer C ...` or via the chat), a full match | no desync; subjectively at least as smooth as before; record fps if the build shows it |
| P9 | P3 and P5 again after `ETHMODE P` | all pass (polled path through `SPI_BurstIn`) |
| P10 | Disk while networking: INL resident, run `PCOPY` and `DIR` of the Pi drive | no corruption, no "Insert a DOS disk" |
| P11 | Memory: `PRINT FRE(0)` / HIMEM in BASIC, and the MSX-DOS TPA, with the new ROM vs master's | about 268 bytes less (2 x 134, MYSIZE is allocated twice); nothing that used to fit stops fitting |
| P12 | T5/T6 on hardware (old server, then new) | as T5/T6 |
| P13 | `ETHBENCH S` timing, before (master ROM: not possible - no send pass) / after | record the W and P jiffies per length as the new baseline |

## Exit criteria

- L0, L1 and L2 all pass, T5/T6 pass.
- Rig: R1 identical, R3 and R4 lower than baseline.
- Board: P1-P10 pass, P3 and P9 with zero send failures, ping loss 0 %.
- Anything that fails only in wait mode on the board blocks the merge: fix (for example a RDY settle wait in the driver before OTIR, or
  pacing on the Pi) before release.
