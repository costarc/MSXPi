# MSXPi Ethernet driver, protocol 2: handover for testing

Written 2026-10-22 on `feature/eth-tx-otir` (worktree `.claude/worktrees/eth-tx-otir`, cut from `master` at `0c4ac631`). The
implementation is on this branch; **nothing has been run yet** beyond assembling it. The test plan is
`ETH-DRIVER-SPEED-TESTPLAN.md`; this document is what you need to carry it out. Background and the original measurements:
`ETH-DRIVER-SPEED-HANDOVER.md`.

---

## 1. What changed

| Area | Change |
|---|---|
| Send (`ethtrans.asm` `ETH_TX_BLOCK`) | Sums the frame in one pass (`ADD A,(HL)` + `CPI`, 33 T/byte), then in wait mode sends it with `OTIR` (odd bytes first, then whole 256-byte runs), then the checksum byte. Polled mode sends the same bytes one at a time. Replaces `ETH_TX_SUM` |
| Receive (`ETH_RX_BLOCK`) | Same run structure with `INIR`; polled loop uses `CPI`. Now corrupts DE |
| Pi side of the send (`msxpi_eth.py`, `msxpi_ethglue.py`) | **The handover said the OTIR change needs no Pi change. It does.** The Pi read the payload byte by byte with `SPI_ByteTransfer`, which drops READY between bytes, and an OTIR write landing in that gap is lost. The payload and checksum are now read in one `SPI_BurstIn(len+1)` (READY held), injected as `read_burst` |
| Inline receive (`FN_IN_STATUS`, `ETH_OPX`) | The C5 reply is `[flag][len][ethertype]`; flag 2 means the frame (at most `RX_INLINE_MAX` = 128 bytes) and its checksum follow. The Pi dequeues it as it sends; the driver keeps it in the work area (`o_RXC`) and `ETH_IN_STATUS` answers from it with no round trip until `ETH_GET_FRAME` copies it out with no link traffic. A garbage length (0, or over 128) fails the transaction instead of writing past the work area |
| Discard (`FN_GET_FRAME` with HL=0) | Sends maxlen 0; the Pi drops the frame and replies with the 3-byte header only (was: the whole frame pulled over and thrown away, `ETH_RX_SINK`, now gone) |
| Version | Probe reports 2 (`PROTO_VERSION` / `ETH_PROTO`). A mismatch sets `MODE_REFUSED` (2): `ETH_LOCK` refuses every transaction, `ETH_RESET` probes again. ETHTEST, ETHMODE and ETHBENCH print the reason. No fallback (user's decision) |
| Work area (`unapi_wrk.inc`) | `o_RXC` (5) + `o_RXC_FRAME` (129). `UNAPI_WRKEND` = `MYSIZE` 47 -> 181. Allocated twice below HIMEM by a disk ROM: about 268 bytes less free memory |
| ROM size | `ethrom.bin` 1329 -> **1316** bytes, 19 free below 8000h (was 6). `UNAPI_ORG` did not move, the DOS driver is untouched apart from MYSIZE. Paid for by keeping `ETH_OP`'s parameters in registers, `ETH_OP1` for the four one-byte fast ops, `ETH_TX3` for opcode+word, merging `ETH_WAIT_DATA` into `ETH_WAIT_READY`, dropping `ETH_RX_SINK` |
| Tools | `ETHBENCH S`: new send pass, 32 x `ETH_SEND_FRAME` at 16, 64, 255, 256, 257, 512, 513, 1514 bytes, wait then polled, `ok=0020` per line. ETHTEST/ETHBENCH `CALL_UNAPI` no longer clobbers HL for a RAM implementation (the send address). ETHMODE knows mode 2 |
| Tests | `software/Server/Python/tests/test_ethshuttle.py` (new, **not run**) |
| Docs | `software/UNAPI/PHASE1_DESIGN.md` 3.5 |

Not done, on purpose:
- The handover's second idea - cache "another frame queued" from `ETH_GET_FRAME` so `ETH_IN_STATUS` answers locally. With inline
  frames, the round trip that cache would save is the one that delivers the next frame, so it would only help back-to-back frames over
  128 bytes. Not worth ROM bytes now.
- No message from inside the ROM (`GETINFO` text, printing): the refusal is reported by the tools and by everything failing cleanly.
- `target/msxpibios.rom` / `msxpibas.rom` are **not** rebuilt on this branch: the release build (`software/build`) bumps BuildIds and
  that is the user's call. On this branch they are still protocol-1 ROMs - do not test them against this branch's server (that is T7).
- The Pi TAP filter and PLAYNET's `memcpy` (handover sections 3 and 7).

## 2. Known risks - what to look for

1. **OTIR on hardware, the reason the board level exists.** The CPLD stalls `OUT` only while `SPI_RDY` is high. The driver waits for
   ready once before the burst (`ETH_WAIT_READY`), the Pi holds READY for the whole of `SPI_BurstIn`. If the Pi still lets READY drop
   inside the burst, or the wait passes in the instant between the length byte's transfer and the Pi dropping READY, bytes are lost.
   Symptoms: `ETHBENCH S` W lines short of `0020` while the P lines of the same length are fine; server log
   `eth: send checksum mismatch`, `SPI_BurstIn: CS was already low before READY - the MSX started early`,
   `native GPIO transfer failed`. The same race exists for INIR today and has not shown up, which is why it is expected to hold.
2. **Lengths at run boundaries**: 255/256/257, 512/513 - covered by `ETHBENCH S`.
3. **Old ROM + new server desynchronises** (an old ROM reads 5 bytes and leaves an inline frame on the wire). Flash and update together.
4. **A held frame can be lost** if a foreground `ETH_IN_STATUS` is interrupted by INL's ISR `ETH_IN_STATUS` in a window of a few
   instructions; the foreground one then overwrites the held frame. Needs a foreground program polling while INL is resident (ETHTEST
   with INL loaded). One lost frame, which TCP/INL recover from.
5. **Inline frames' checksum is not verified on the MSX**, same as `ETH_GET_FRAME` never did. A corrupted small frame reaches INL, whose
   own IP/UDP/TCP checksums catch it.
6. **Memory**: 268 bytes less below HIMEM. Check a machine with a built-in disk drive (P11).
7. Sends now need a burst-capable Pi transport (native or fast GPIO) - already true for every reply the driver reads, so no new
   requirement in practice.

## 3. Building - without touching the shipped ROMs or the installed openMSX

Tools: `C:/Users/roniv/Dev/bin` (`sjasm.exe`, `sjasmplus`, `hex2bin.exe`), zmac at `C:/Users/roniv/Dev/zmac/zmac.exe`.

**UNAPI tools and both driver variants** (writes the tracked `.COM`s in `UNAPI/src`, already rebuilt on this branch):
```
cd software/UNAPI && sh build.sh --no-copy
```
Expect 6 x `Errors: 0`, `ethrom.bin 1316 bytes`, `19 bytes free below 8000h`.

**The 32 KB ROM pair**, in a scratch copy (MYSIZE changed, so the DOS half must be rebuilt too, not only the BIOS-only half). This is
what was run to check the asserts; it does not bump BuildIds:
```
W=/c/Users/roniv/AppData/Local/Temp/claude/rombuild; rm -rf $W; mkdir -p $W/target $W/UNAPI
cd <worktree>/software && cp -r ROM asm-common $W/ && cp -r UNAPI/src $W/UNAPI/
cd $W && B=C:/Users/roniv/Dev/bin
( cd UNAPI/src && $B/sjasm.exe ethrom.asm ../../ROM/src/MSX-DOS/ethrom.bin ethrom.lst )
C:/Users/roniv/Dev/zmac/zmac.exe -I ./asm-common/include -I ./ROM/src/MSX-DOS ./ROM/src/MSX-DOS/msx-dos.mac
$B/hex2bin.exe -s 4000 zout/msx-dos.hex && cp zout/msx-dos.bin target/msxpibios.rom
rw() { od -An -tx1 -j "$2" -N2 "$1" | awk '{print $2 $1}'; }; DOS=target/msxpibios.rom
$B/sjasmplus -DMSXPI_ROM_STASH --inc=./asm-common/include --inc=./ROM/src/MSX-DOS \
  -DDOS_INIT=0x$(rw $DOS 2) -DDOS_STMT=0x$(rw $DOS 4) -DDOS_RET=0x$(rw $DOS 32) \
  -DOUTFILE="\"target/msxpibas.rom\"" ./ROM/src/BIOS/msxpibios.asm
cat target/msxpibios.rom target/msxpibas.rom > target/rom32.rom
```
(This run gave DOS INIT 57BF, STATEMENT 65DB, RET 75C6.) The release alternative is `software/build`, which does the same and bumps the
BuildIds and regenerates disks and `MSXPi.xml` - read it first (lines 236-345).

**Pi server**: run `software/Server/Python/src/msxpi-server.py` from this worktree (the changed files are `msxpi_eth.py`,
`msxpi_ethglue.py`). On the real Pi, copy those two files over the installed ones and restart the server.

## 4. Running

**Unit tests** (level 1): `cd software/Server/Python/tests && python -m unittest test_ethshuttle -v`.

**Harness** (level 2, `software/UNAPI/harness`, `./run.sh <test>`): openMSX identifies the MSXPi ROM by sha1, and `run.sh` uses
`Documents/openMSX/share`. Work on a copy or restore afterwards: put the rebuilt `msxpibios.rom` (the DOS half, or `rom32.rom` if the
machine config maps 32 KB - check `MSXPi.xml`) into the share and update the sha1 in `MSXPi.xml`. `run-wsl.sh` has its own copies
(harness README, "After changing the ROM"). Put the rebuilt `ETHTEST/ETHBENCH/ETHMODE/ETHUNAPI.COM` on the served
`C:/home/pi/msxpi/disks/msxpiboot.dsk` with `software/dsktool.py` while no server is running (`UNAPI/build.sh` without `--no-copy` does
it). For T5, run the server from a `master` checkout instead.

`ETHBENCH S` is the new check that matters most; run it in every environment.

**Rig** (level 4): the rig is on `feature/tcpip-games`. The files this branch touches are identical there, so make a scratch branch from
`feature/tcpip-games`, merge `feature/eth-tx-otir`, and run the rig from that worktree with the rebuilt `rom32.rom` in a **copy** of the
openMSX install, exactly as `ETH-DRIVER-SPEED-HANDOVER.md` section 5 describes (`cp -rL ... /tmp/omx-b`, `OPENMSX=...`, `run_native.sh 0 0
1200`, `cmp_perf.py`, `cmp_pair.py`). Kill stale `openmsx.exe` / `python.exe` / `sh.exe` from earlier runs first. Compare with the
baseline: H 19.44 fps, C 19.46 fps, 20 ms in `XCHG` per frame, 91 link bytes per frame.

**Board** (level 5): flash the 32 KB ROM (both halves) the usual way, update the Pi's two Python files, then the P-table in the plan.
Keep master's ROM image at hand to flash back.

## 5. Where to look when something fails

| Symptom | Look at |
|---|---|
| `ETHBENCH S` W lines short, P lines fine | risk 1: Pi log for `SPI_BurstIn` lines; try `MSXPI_GPIO_CS_SETUP_NS`; consider a short settle before OTIR in `ETH_TX_BLOCK` (19 bytes of ROM free) |
| Both W and P short at one length only | the run split in `ETH_TX_BLOCK` (odd bytes first, then `D` runs of 256) |
| `Mode: 02` with the right server | the probe's 5th byte: `PROTO_VERSION` in the server actually running, and `ETH_PROTO` in `ethops.asm` |
| Received frames lost or garbled after the change, sends fine | `FN_IN_STATUS` / `ETH_OPX .inline` / `FN_GET_FRAME .held`; the Pi's `_op_in_status`; check `RX_INLINE_MAX` is 128 on both sides |
| Disk errors with INL resident | unchanged locking (`ETH_LOCK`, `o_LINK_BUSY`), but check `ETH_RESYNC`'s drain (it no longer saves BC around `ETH_RX`, which preserves it) |
| Build: `ASSERT $ <= $8000` | the image grew past 1335 bytes: something was added; see the size notes in `unapi_wrk.inc` |

## 6. First test run: wait-mode sends lost, fixed

`ETHBENCH S` in the WSL harness lost 1-4 of 32 frames per length in wait mode and none in polled mode, on master's driver too. Breakpoints
on the ROM driver's failure exits (openMSX Tcl) put every loss at one place: `ETH_BEGIN` found port 56h = 01 and gave up, before the
opcode was sent. It looked at READY **once**. After answering a transaction the Pi drops READY and only raises it again once Python is
back in `recvdata2`; a caller that starts the next transaction at once lands in that gap. Polled mode has no such check, which is why it
never lost anything. (Why the NETSTAT bench does not show it was not investigated.)

The fix: `ETH_BEGIN` waits with the bounded `ETH_WAIT_READY` (the same polled spin every byte uses, before wait mode is switched on, so
it can time out but never hang). +2 bytes: `ethrom.bin` 1316, 19 free. After it, `ETHBENCH S` gave `ok=0020` on all 16 lines and no
failure exit was hit. The same gap should exist on the board (the Pi's Python turnaround against the next `ETH_BEGIN`), so this most
likely fixes a pre-existing loss there too, each one costing INL a retransmission - to confirm with `ETHBENCH S` on the board (P3).

The earlier experiment "a bounded wait in ETH_BEGIN did not help" was made on the RAM driver. The WSL openMSX was loading an older ROM
at the time (its own ROM driver resident too), so `ETHBENCH` was most likely talking to that ROM driver, not the patched one - not
verified, but the patched ROM driver shows the fix working.
