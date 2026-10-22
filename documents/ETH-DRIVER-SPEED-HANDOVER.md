# MSXPi Ethernet driver: faster send (OTIR) and a one-transaction receive

Handover, written 2026-10-22 on `feature/eth-tx-otir` (a worktree cut from `master` at `0c4ac631`). Nothing is implemented on this branch yet:
a draft of the OTIR send was tried and does not fit in the ROM (section 4). The branch holds this document only.

| | |
|---|---|
| Why | PLAYNET over TCP/IP (InterNestor Lite on the MSXPi Ethernet driver) is slower than over the MSXPi link. The link and the driver are a large part of it. Context: `documents/PLAYNET-TCPIP-PERFORMANCE.md` on `feature/tcpip-games`, step 4 (5.4) |
| Wanted | (1) `ETH_SEND_FRAME` sends its payload with `OTIR` in wait mode. (2) A new Pi opcode so that `ETH_IN_STATUS` brings the waiting frame in the same transaction, and `ETH_GET_FRAME` copies it locally. Both go in this branch so they can be flashed and tested on a real board before anything else depends on them |
| Decision (user) | **No backward compatibility** for the new opcode: the ROM has barely been released. Change the opcodes in place, raise the probe's protocol version, and update the Pi and the ROM together. The ROM must refuse a version mismatch with a clear message instead of failing silently |
| Main files | `software/UNAPI/src/ethtrans.asm` (transport), `ethops.asm` (the UNAPI routines), `ethrom.asm`, `software/ROM/src/MSX-DOS/msxpi-driver.mac`, `software/asm-common/include/unapi_wrk.inc` (`UNAPI_ORG`), `software/Server/Python/src/msxpi_eth.py` (Pi side) |
| PLAYNET needs nothing | A game works with the old ROM and gets faster with the new one. The OTIR change does not alter the wire (same bytes, same checksum), so it needs no Pi change at all |

---

## 1. What was measured (on `feature/tcpip-games`, the two-emulator rig)

Both players over TCP/IP (InterNestor Lite on this driver), Soccer, 1200 frames, emulated time. One exchange (`XCHG`) costs about 20 ms, against
4 ms on the MSXPi link. The rig samples the PC every 0.5 ms of emulated time while inside `XCHG` (`PERF_PROF=1`, `perf_node.tcl`), by 256-byte block,
slot register and mapper segments. Top blocks, of 47 571 samples:

| Samples | Share | Where (`A8` = slot register) | What |
|---|---|---|---|
| 8082 + 5281 + ~1100 | ~29 % | `7C00`, `7E00`, `7F00`, `7B00`, `A8=58` | the MSXPi ROM: the driver's link code (byte loops, `ETH_WAIT_READY`) |
| 7013 + 1812 | ~19 % | `9800`, `9700`, in the PLAYNET overlay | SDCC's `memcpy` (`___memcpy` at 97D2) and runtime helpers. Not the driver: a separate task, see section 7 |
| 3866 + 1646 + 1156 + more | ~20-25 % | `5300`, `4100`, `5F00`, `4200`, page 1 | InterNestor Lite itself |
| 1204 + ... | ~4 % | `0300`, `0D00` | BIOS |

So the link code is the biggest single block we can change. Per exchange the link carries about 83 bytes per game frame (K = 2): a send of 69 bytes
(`ETH_SEND_FRAME`) and a receive of 71 (`ETH_GET_FRAME`) per two frames, plus the status polls.

What the driver does today (read from the source):
- **Receive** already bursts: `ETH_RX_BLOCK` uses `INIR` at 21 T-states a byte in wait mode (`ETH_WAIT_READY` once before the burst).
- **Send** does not: `ETH_TX_SUM` calls `ETH_WAIT_READY` and sends one byte at a time, roughly 100-120 T-states a byte, 69 bytes per frame. The comment in
  `ethtrans.asm` says why: it was never done because the path "has never carried a real frame".
- **`ETH_IN_STATUS`** is one transaction (1 byte out, 5 back) every time INL's timer runs, frame or not; a waiting frame then costs a second transaction
  (`ETH_GET_FRAME`: 3 out, 3 + frame + 1 back).
- The Pi already puts "another frame is queued" in `ETH_GET_FRAME`'s flags (`FLAG_MORE_PENDING`). The MSX does not use it (the TODO in `FN_IN_STATUS`).

Baseline for A/B comparisons (rig, both TCP/IP, 1200 frames, `PERF_PROF=1`), ROM rebuilt from this tree **unchanged**: H node 19.44 fps, C node 19.46 fps,
20 ms in `XCHG` per frame, 91 link bytes per frame. The installed openMSX ROM gave 19.9 fps: the same within noise.

---

## 2. Change 1: send with OTIR

Draft (it assembles; it is the part that makes the ROM too big, section 4). In `ethtrans.asm`, replace the "There is no ETH_TX_BLOCK" comment with:

```asm
; --- ETH_TX_BLOCK: send BC bytes from HL, leaving the 8-bit sum in ETH_SUM.
; Wait mode: summed 256 bytes at a time (26 T-states a byte), then OTIR (21 T-states a byte; the OUT itself
; stalls the Z80 until the byte is taken). Like INIR in ETH_RX_BLOCK it waits for the Pi once, before the burst.
; Polled mode: ETH_TX_SUM, as before. Out: CF=1 on timeout; corrupts AF/BC/DE/HL.
ETH_TX_BLOCK:
            ld      a,(ix+o_ETH_MODE)
            cp      MODE_WAIT
            jp      nz,ETH_TX_SUM
            push    bc                      ; ETH_WAIT_READY corrupts BC
            call    ETH_WAIT_READY
            pop     bc
            ret     c
            ld      e,0                     ; E = the sum
.chunk:     ld      a,b
            or      c
            jr      z,.done
            ld      a,b
            or      a
            jr      z,.last                 ; fewer than 256 left
            push    bc
            ld      b,0                     ; a whole 256-byte chunk (B = 0 means 256)
            call    .sumout
            pop     bc
            dec     b
            jr      .chunk
.last:      ld      b,c
            call    .sumout
.done:      ld      (ix+o_ETH_SUM),e
            or      a
            ret
; B bytes (0 = 256) at HL: add them to E, then send them. HL moves past them.
.sumout:    ld      d,b
            push    hl
            ld      a,e
.sum:       add     a,(hl)
            inc     hl
            djnz    .sum
            ld      e,a
            pop     hl
            ld      b,d
            ld      c,DATA1
            otir
            ret
```

and in `ethops.asm` `FN_SEND_FRAME` call `ETH_TX_BLOCK` where it calls `ETH_TX_SUM`. Expected gain: about 70 T-states a byte x 69 bytes, about 1.4 ms per send.

**Risks to test on the board first**
- The old comment's claim stands: **OTIR in wait mode has never run on hardware.** The CPLD stalls the Z80 on `OUT` in wait mode (`ethtrans.asm`, ETH_TX comment), but it
  only starts a transfer while `SPI_RDY` is high. If the Pi drops RDY between bytes of a received burst, `OTIR` would outrun it and bytes would be lost. The Pi then sees a
  checksum mismatch and answers `ETH_RC_CHKSUM`; the driver reports "excessive collisions" and INL retransmits. That is the failure to look for (`ETHBENCH`, ping loss).
  Check how `msxpi_eth.py` / the Pi's `_read_n` receives bytes (`PHASE1_DESIGN.md` 3.4 describes the Pi holding RDY for a reply burst; the receive direction is not described).
- The 256-byte chunking: a length that is an exact multiple of 256 must not send an extra block (same rule as `ETH_RX_BLOCK`). Test lengths 255, 256, 257, 512, 1514.
- Also try polled mode (`ETHMODE`) to confirm nothing changed there.

---

## 3. Change 2: receive in one transaction (new opcode)

Today a received frame costs two transactions. Proposal (adjust freely, it is yours to design):
- `OP_IN_STATUS` (C5) keeps its 5-byte reply (flag, length, ethertype) and, **when a frame is waiting and it is not larger than N bytes**, the Pi appends the frame and its checksum
  in the same reply; the driver keeps it in its work area; `ETH_GET_FRAME` then copies it locally with no link traffic. Larger frames: the old two-step path.
- Use the "another frame queued" flag already returned by `ETH_GET_FRAME` to cache the next frame's length and ethertype, so `ETH_IN_STATUS` can answer "a frame is
  waiting" with no round trip when the cache says so. Keep the round trip when the cache says "none" (a frame may have arrived since).
- Bump the probe's protocol version (`OP_PROBE` returns `'E','T','H', version`); the ROM compares it and refuses a mismatch with a message. No fallback to the old opcodes (user's decision).

**Open problem: where the frame sits between the two calls.** The driver's work area (`GETWRK`) is small and `MAX_FRAME_LEN` is 1514. A fetch-with-status needs a buffer for a whole frame; a
game packet is 64 bytes. Either limit it to small frames (N around 128: ARP, UDP game packets, ACKs) or skip it. **Expected gain is modest:** one transaction fewer per received frame, about 6 link
bytes and one Pi dispatch out of roughly 140 bytes per exchange. Measure the Pi's per-transaction latency (`MSXPI_PROFILE=1`, v1.6 profiler) before spending ROM bytes on it. The OTIR change
needs no protocol change and is the safer first step.

The Pi's TAP filter (PLAYNET-TCPIP-PERFORMANCE.md 5.4, item 4: pass only frames for the MSX's MAC, broadcast ARP for its IP, and the multicasts INL uses; count what is dropped) is a Pi-only change in
`msxpi_eth.py` and was not started. It matters on a busy LAN, not in the rig (user-mode NAT).

---

## 4. The ROM is full: this is the real work

`UNAPI_ORG` is `07AC9H` (`asm-common/include/unapi_wrk.inc`): the DOS driver code is below it and the UNAPI image is above it, up to 8000H.
`8000H - 07AC9H = 1335` bytes of room; the image `ethrom.bin` is **1329** bytes. **Six bytes are free.** The draft above adds 58 bytes (`ethrom.bin` 1329 -> 1387), and the BIOS-only
ROM then fails `ASSERT $ <= $8000` (`ROM/src/BIOS/msxpibios.asm` line 393). The new opcode needs more (a work-area buffer is RAM, but the code for the
cache, the fetch and the version check is perhaps 80-150 bytes).

The comment on `UNAPI_ORG` says to move it only in response to an assert and to re-measure. To make room there are three ways, combine as needed:
1. **Move `UNAPI_ORG` down** and shrink the DOS driver (`ROM/src/MSX-DOS/msxpi-driver.mac`, zmac) by the same amount. Needs the full DOS ROM rebuild and a look at what in `msxpi-driver.mac` can go
   (the assert at line 651 says `$ LE UNAPI_ORG` for the driver). The DOS ROM half then changes too, and the BIOS-only half reads its header addresses from it.
2. **Shrink `ethrom.bin`.** For instance: let `ETH_TX_BLOCK` replace `ETH_TX_SUM` (one per-byte loop in the polled branch, about 30 bytes saved), look for duplicated code between
   `ETH_RX`, `ETH_TX`, `ETH_RX_BLOCK`, and the four `ETH_OP` callers.
3. **Drop code that wait mode makes dead** only if a board without wait mode is no longer supported (do not assume that: `fix/eth-wait-probe-legacy-boards` exists for legacy boards).

The RAM variant (`ETHUNAPI.COM`, `ethseg.asm`) shares `ethtrans.asm` and `ethops.asm` and has no size limit, but every change must still build there (`UNAPI/build.sh --no-copy`).

---

## 5. How to build and test without touching the installed openMSX

Tools: `C:/Users/roniv/Dev/bin` has `sjasm.exe`, `sjasmplus.exe`, `zmac`, `hex2bin`. SDCC is on PATH.

**Reproducing the shipped BIOS-only ROM** (this gives byte-identical `target/msxpibas.rom`, 0 differences, which proves the setup):
```
cd software
( cd UNAPI/src && sjasm.exe ethrom.asm /tmp/romb/ethrom.bin /tmp/romb/ethrom.lst )
rw() { od -An -tx1 -j "$2" -N2 "$1" | awk '{print $2 $1}'; }
DOS=target/msxpibios.rom
sjasmplus -DMSXPI_ROM_STASH --inc=/tmp/romb --inc=./asm-common/include --inc=./ROM/src/MSX-DOS \
  -DDOS_INIT=0x$(rw $DOS 2) -DDOS_STMT=0x$(rw $DOS 4) -DDOS_RET=0x$(rw $DOS 32) \
  -DOUTFILE="\"/tmp/romb/bas.rom\"" ./ROM/src/BIOS/msxpibios.asm
cat $DOS /tmp/romb/bas.rom > /tmp/romb/rom32.rom      # DOS half + BIOS-only half, 32 KB
```
(`--inc=/tmp/romb` first, so `INCBIN "ethrom.bin"` finds the new image.) If you move `UNAPI_ORG` the DOS half must be rebuilt too: `software/build` does it all but also bumps BuildIds and regenerates the
disks, so read it first (lines 236-345 build the ROMs).

**Rig** (the two-emulator rig is on `feature/tcpip-games`, `software/Client/tests/soccernet/`, with `perf_node.tcl`, `cmp_perf.py`, `run_native.sh`):
- The rig's openMSX loads `msxpibios.rom` from its install folder; rig runs use `BANK2` (the upper, BIOS-only half). Work on a **copy**:
  `cp -rL /c/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1 /tmp/omx-b` (`-L`: the install has symlinks) and put `rom32.rom` at `/tmp/omx-b/share/systemroms/extensions/msxpibios.rom`.
- Run from the `feature/tcpip-games` worktree, with `OPENMSX=C:/Users/roniv/AppData/Local/Temp/omx-b/openmsx.exe`:
  `SOCCER_ROM=C:/Users/roniv/Dev/MSX/gameroms/SOCCER.ROM SJASMPLUS=C:/Users/roniv/Dev/bin/sjasmplus.exe EXTRA_TCL=<abs path>/perf_node.tcl EXTRA_TCL_C=<same> PERF_PROF=1 SCENARIO=mixed BOTH=1 WORK=/tmp/x sh run_native.sh 0 0 1200`
  then `python cmp_perf.py /tmp/x/np/H.trace.perf /tmp/x/np/C.trace.perf` and `sort -rn /tmp/x/np/H.trace.prof | head`. Compare against the baseline in section 1: ms in `XCHG` per frame, link bytes per frame, and the `7C00`/`7E00` samples.
- Frames must stay identical (`cmp_pair.py` prints IDENTICAL) and no node may drop IRC or desync.
- Before a run, check that no `openmsx.exe` or `python.exe` from an earlier run is alive (stale server loops disturb ports); the rig's cleanup is `sh kill_nodes.sh` plus killing stale `sh.exe` loops.
- Also run the harness tests in `software/UNAPI/harness/tests` (`wsl_ethops.tcl`, `wsl_bench.tcl`, `wsl_waitmode.tcl`) and `ETHBENCH`/`ETHTEST`.

**On the real board** (before anything else): `ETHTEST` (`Mode: 01`), `ETHBENCH` (the `ok=0800` lines, sends of 16/64/512/1514 bytes), a ping from the Pi to the MSX (was 40-60 ms), `HGET`, telnet, and a PLAYNET game over
TCP/IP (`PLAYNET /T soccer C ...`, or the chat). Time `ETHBENCH` before and after.

---

## 6. Conflicts and context

- `fix/eth-wait-probe-legacy-boards` (worktree `MSXPi-eth-wait-probe`) works on the wait-mode probe in the same files. Check it before editing `ethtrans.asm` / `ethcore.asm`, and rebase.
- `feature/tcpip-games` has the PLAYNET side (steps 0-3 done, 5a642cc9). Nothing in it depends on this branch.
- The driver files are identical between `master` and `feature/tcpip-games`, so this branch can merge to either.

## 7. Related, not part of this branch

The profile also shows about 19 % of an exchange in the PLAYNET overlay's SDCC `memcpy` (`PLAYNET.OVL`, `netcore/ovl_main.c`, `netcore.c`), which copies packets byte by byte. An `LDIR`-based `memcpy` (a naked
`_memcpy` in `ovl_main.c`, SDCC 4.0.0 stack calling convention: `d`, `s`, `n` at 2, 4, 6 above the return address; return `d` in HL) should save a good part of it. It belongs to the tcpip-games
branch and was not done.
