# LINK2 - handover: the three tools still on the legacy protocol

Branch `feature/link2` (worktree `C:\Users\roniv\Dev\github\MSXPi-link2`), after phase 7 (f6899eaa).
Read first: `LINK2-IMPLEMENTATION-PLAN.md` ("Phase 7 results"), `LINK2-DESIGN.md` 5.3 and 8, `LINK2-TEST-PLAN.md` T7.

The server speaks both protocols and picks one from the transfer's first byte, so none of the three is broken today.
Converting them lets the legacy code leave the MSX side altogether (the next step, after hardware tests, is a separate
decision: see "Retiring the legacy protocol").

## What a conversion looks like (the pattern phase 7 settled)

- Asm tools: `DEFINE MSXPI_LINK2` before the includes (as `template.com.asm` and `ROM/src/BIOS/l2test.asm` do). Then
  `msxpi_bios.asm` leaves out the legacy routines and `link2.asm` is included at its end. Call
  `LINK_COMMAND` (DE = zero terminated command; C on error), `LINK_SEND` (DE = source, BC = length),
  `LINK_RECV` (A = mode 0 drop / 1 print / 2 buffer, DE = buffer, BC = largest block, A out = the Pi's end code,
  BC out = bytes), `LINK_PRINT` (mode 1 with DE/BC). Run `LINK_RECV` etc. with the buffer at 8000h or above
  when you can: only then may the Pi burst (OTIR/INIR).
- A reply that is one block of type `RC_READY` (more *transfers* follow) cannot use `LINK_RECV`, which waits for
  further blocks. The C side has `link_recv_open` / `link_recv_next` for it (frame in 26 bytes of RAM); the asm
  equivalent is `L2_OPEN` + `L2_RECV_BLOCK` with a frame at IX (see how `l2_recv_open` / `l2_recv_next` in
  `C-common/lib/msxpi-bios.c` set it up: zero 26 bytes, mode 2 at +19, size at +20, pointer at +22).
- Behaviour to remember: LINK2 retries inside the transfer (10 NAKs, then `RC_PROTOERR`); drop the client's own
  retry loops. A binary holds one protocol, so every call in the file moves together.
- Reference for the bytes on the wire: `tests/link2_sim.py`, class `Msx`. If the asm and `Msx` disagree, `Msx` wins.

## 1. `playnet` (`software/Client/src/playnet/`)

Legacy users in `playnet.asm`: `piCommand` (about line 1282: `SendCommandToMSXPi`, `PerformHandshake`,
`RECVDATA_ONEBLOCK` loop into the reply area, sizes from `pcBsz`), and `sendSave` / `sendBlk` (about lines 1090-1200:
a hand-written `playnet save` upload using `PIWRITEBYTE` / `PIREADBYTE`). `c9link.asm`, `transport_msxpi.asm`
and `transport_hybrid.asm` showed no calls to the byte routines; re-check with
`grep -n "PIWRITEBYTE\|PIREADBYTE\|PerformHandshake\|RECVDATA\|SENDDATA\|SendCommandToMSXPi"` over the folder
(the game data path itself goes through opcode C9 / UNAPI, not through these).

Why it was left: `sendSave` sends a 8-byte header (`svHdr`, `SV_HDR`) and the saved memory area as **one transfer of
several blocks** (`RC_READY` on all but the last), which `LINK_SEND` (one contiguous source) cannot express. The
server side takes it as one `link_recv(SAVE_MAX)` (`msxpi_cmd_web.py`, `playnet`, "save").

Plan:
1. **Likely the simple way**: the restore path already uses a contiguous `RBUF` laid out as header + area
   (`RBUF+SV_HDR+SV_MAX <= $C000` is asserted, `cmdRestore` reads `SV_HDR+SV_MAX+1`). Build the same layout for the
   save (header, then `LDIR` the area behind it) and make `sendSave` a single `LINK_SEND` of `SV_HDR+svLen` bytes from
   `RBUF`. Check the memory the saved area itself occupies is not what `RBUF` overlaps; if it is, fall to step 2.
2. If a copy is impossible: add a block-level send to the library (asm `L2_OPEN`-style open for sending, then
   `L2_SEND_BLOCK` once for the header with type `RC_READY` and once for the area with `RC_SUCCESS`, `L2_SEQ`
   incremented between). `LINK_SEND` shows the loop to copy (`L2SEND_*`). Expose it in `link2.asm` as e.g.
   `LINK_SEND_OPEN` / `LINK_SEND_BLOCK`, mirrored in `link2_sim.py`'s `Msx` first, with a T1/T3 test, then in the
   C library if wanted.
3. `piCommand`: `LINK_COMMAND`, optional `sendSave`, then `LINK_RECV` mode 2 into the reply area with
   `BC = min(room, BLKSIZE)`; it returns the Pi's code in A and the byte count in BC, which is what the callers
   expect (`cp RC_SUCCESS`, the zero terminator is written at DE by hand: mode 2 leaves DE at the end of data).
   `piCommand` checks that a block fits (`msgTooBig`); with LINK2 the receiver enforces the block size itself
   (`RC_PROTOERR` / the Pi's abort), and in mode 2 the room check is against F380h only: keep `pcLim` bounding the
   block size you announce.
4. Add `DEFINE MSXPI_LINK2` to `playnet.asm`; `build.py` already passes `-DMSXPI_RAM_STASH`. Size: `link2.asm`
   is about 1.2 KB plus the 512 byte CRC table (page aligned; `playnet.asm` has a memory map to check, and
   `LINK2_CRC_NOTABLE` drops the table at the cost of speed). PLAYNET.COM is 10,765 bytes and has an overlay.
5. Tests: `Client/tests/soccernet/run_native.sh` (needs your own `SOCCER_ROM`, never commit it), scenarios `chat`
   and the save/restore path (look for `playnet save` / `restore` in `PLAYNET-PROTOCOLS.md` 15 and the scripts
   there), plus `test_games.py` / `test_netplay.py` on the server. Check that the game itself (the C9 data path) still
   runs while the MSXPi link carries LINK2 command traffic.
6. Document in the plan ("Phase 7 results" -> remove from "Not done") and the test plan.

## 2. `Client/src/msxarch.asm` (the old asm msxarch)

The C `msxarch.c` replaced it and is converted. The asm file is still built by `software/build` (`buildClientCommands=yes`,
`sjasmplus -DMSXPI_RAM_STASH ... --raw=./target/msxarch.com`) and **overwrites `target/msxarch.com` with the old
5.3 KB asm version** every time (a known trap, see the plan's "Careful with `software/build`").

Decision first (ask the user): **delete the asm version** and its build lines, or convert it. Deleting is the
recommendation: it is obsolete, the C version is the shipped one, and the build line is the only thing keeping it
alive. If deleted: remove `msxarch.asm` and the `msxarch.com did not assemble` block in `build` (lines ~228-230),
check `grep -rn "msxarch.asm"` in `documents/`, `make.sh`, `msxpirfh.bat` generation, and that
`target/msxarch.com` stays the C build.

If it is converted instead: the legacy calls are `SendCommandToMSXPi` (7 places), `PerformHandshake` +
`RECVDATA_ONEBLOCK` (lines ~474, ~578, ~936-1005) and a `RecvAll` helper (about line 472: a whole multi-block
transfer into one buffer = `LINK_RECV` mode 2). The ROM loader needs one block at a time into a mapped bank
(the C code in `msxarch.c`, `loadrom`, `loadMapperRom`, `drainMappedRomBody`, now uses open/next): the asm needs the
`L2_OPEN` / `L2_RECV_BLOCK` frame described above.

## 3. `ROM-Patcher/profiles/*` (game ROM runtimes)

Profiles with their own copy of `msxpi_bios.asm`, `include.asm`, `payload_generated.asm` and `runtime.asm`:
`arctic`, `goonies`, `nemesis`, `vampire`. (`pingpong`, `salamander`, `soccer`, `yiear` use the playnet path and
UNAPI; check them with the same grep.) Each profile's `rebuild.py` copies the files from `goonies/src` over the
others (`for name in ('msxpi_bios.asm', 'include.asm', 'payload_generated.asm', 'runtime.asm')`) and assembles
`runtime.asm` with `-DMSXPI_RAM_STASH` into the patched ROM's free bank.

The runtime's `exchange` routine (runtime.asm about line 182) does: `resetMSXPI`, `SendCommandToMSXPi`,
`PerformHandshake` with BC = 256, then a `RECVDATA_ONEBLOCK` loop that reads the header type from
`MSXPI_STASH_BUF+5` (a legacy internal) to follow `RC_READY` multipart replies (up to 16 parts), and treats a
multipart reply as an invalid PID.

Plan:
1. Work on `goonies/src` first (the shared source), then let `rebuild.py` of the others copy it. Add
   `DEFINE MSXPI_LINK2` to `runtime.asm` (or pass `-DMSXPI_LINK2` in each `rebuild.py`), refresh the copied
   `msxpi_bios.asm` and add `link2.asm` + `link2_crc_table.asm` to the copied list.
2. Rewrite `exchange`: `LINK_COMMAND`, then `LINK_RECV` mode 2 into `response` with `BC = 256`; the end code comes
   back in A (no `MSXPI_STASH_BUF+5`). The 16-part loop goes: a reply longer than one block ends in
   `RC_PROTOERR`, which is the "not a valid PID" case. Keep "disable further wire attempts on failure".
3. **Space**: the runtime lives in a free 8 KB ROM bank and is asserted `code_end <= 0xD000`, `len == 0x2000`
   (`rebuild.py`). `link2.asm` (about 1.2 KB with the table, which must be page aligned) has to fit; the CRC table
   can go in the bank's padding. Measure before editing the rest.
4. **The shared link**: the runtime runs from page 3 RAM with interrupts and a music routine; LINK2's
   `PAYLOAD_WAIT` / `PAYLOAD_ESCAPE` keep the same behaviour (CTRL+ESC aborts), and `link2.asm` uses the shadow
   registers for the CRC (the BIOS interrupt routine saves them; a game's own interrupt handler must as well:
   check `runtime.asm`'s ISR for `EXX` use).
5. Tests: `software/ROM-Patcher/tests/` (`test_patcher.py`, `test_profiles.py`, `test_arctic.py`,
   `emulator_runtime.py`, `emulator_live.py`; some need the original ROMs, which are never committed: see
   `VALIDATION.md`). The `*.bin` assets are rebuilt by `rebuild.py --rom <original>`; commit the rebuilt assets only
   with the user's go-ahead.
6. Update `ROM-Patcher/README.md` / `FORMAT.md` where they name the legacy routines.

## Retiring the legacy protocol (not part of these three)

After all three are converted **and** the C clients and DOS half have run on the Canon V-25: the MSX side has no
legacy caller left except old EEPROMs. Dropping the server's legacy path (`msxpi_blocks.py`, the READY/READY_ACK
handshake, `senddata`/`recvdata2` framing) and the `IFNDEF MSXPI_LINK2` code of `msxpi_bios.asm` is a **separate
decision**: older installs would stop working. Ask before doing it.

## Housekeeping

- Work only in the worktree; other sessions use the same repository. openMSX harnesses use ports 5044 (smoke) and
  5046 (fault injection): check them first. Bound and watch every run (<= 5 minutes between checks).
- Build C clients with `make.bat <name>` (SDCC 4.6.0) and `MAKE_OUTDIR=<dir>` so nothing goes to the user's
  `FloppyA`; asm tools with `C:\Users\roniv\Dev\bin\sjasmplus.exe --inc=./asm-common/include`.
- `generate.py --check` must pass (it covers `link2_generated.h`).
- One commit per conversion with the measured results; push only `feature/link2`.
