# Handover: Salamander online co-op (PLAYNET 3, image host mapper-ram)

2026-10-23. Session 2 fixed the intermittent start-up crash (section 4). Open: speed, Soccer regression, TCP/IP (section 2).

| | |
|---|---|
| Worktree / branch | `C:\Users\roniv\Dev\github\MSXPi-salamander`, `feature/salamander-netplay` (from `master` at `64049cf8`), not pushed. Keep `salamander_debug/step_hung_example.txt` out of git (disassembled game code). The main checkout is shared with other sessions: do not switch branches there. |
| Design | `documents/SALAMANDER-DESIGN.md` (analysis, decisions D1-D8, plan). Spec: `documents/PLAYNET-PROTOCOLS.md` 7.3 (new), 8.2 (`MAPPER` section). |
| ROM | `C:\Users\roniv\Dev\MSX\gameroms\SALAMAND.ROM`, CRC-32 `C36F559D`. Never commit it or anything derived from it. |
| Tools | sjasmplus `C:\Users\roniv\Dev\bin\sjasmplus.exe`; openMSX `C:\Users\roniv\Dev\MSX\MSXPi\openmsx-MSXPi_v1.6.1\openmsx.exe` |

## 1. What is done and works

- **Package** `software/ROM-Patcher/profiles/salamander/`: `src/glue.asm`, `rebuild.py` (78 patches; `--rom` checks every expected byte
  and that no bank-register write is left; `--syms` writes Tcl symbols; `--test-gpf` scripted build). Stub 1432 of 1536 bytes at D000h,
  transport D600h, `MK_BLOCK` D295h. GPF 2601 bytes. Game id `salamand`, roles `P1`/`P2`, 2 input bytes.
- **Bank engine** `software/Client/src/playnet/engine/mapper_k8.asm` (MK_W0-MK_W3, pair tables with pinned homes, clock eviction).
- **`patch_rom.py`**: image host `mapper-ram`, GPF flags host 1, `MAPPER` section (type 6, 14-byte fixed part + pairs), rules in
  `check_mapper`, `PLAYNET_VERSION` 3. Tests: `tests/test_gpf.py` class `MapperRamTests`; 40 tests pass
  (`SALAMANDER_ROM=... SOCCER_ROM=... python -m unittest tests.test_gpf tests.test_patcher`). The only failure is
  `test_games_folder_is_current` (SALAMAND.GPF not published to `software/target/games` yet: run `build_games.py` when it is ready).
- **PLAYNET 3 loader** `software/Client/src/playnet/mapper_host.asm` (+ hooks in `playnet.asm`): segment detection (mapper routines,
  or MSX-DOS 1 counting like msxarch), ROM into homes in 2 KB chunks, patches into homes, pairs built, `MK_BLOCK` filled in the stub
  image, start pairs mapped by the trampoline, MSX-DOS segments restored in `pnBack`. Mapper-ram over TCP/IP is refused ("not yet").
  Memory map changed: CRC tables 3C00h, bounce buffer 3400h-3BFFh (CHUNK 2 KB), tBuf 3500h, mapper loader 2400h-27FFh (the TCP/IP
  overlay passes over it; only code below `tcpSafeEnd` 21F2h runs on that path). GPF receive gets one block of slack
  (`GPFMAX+BLKSIZE`). `saveDos` also counts the stub and transport areas (`svLow`).
- **Rig** `software/Client/tests/soccernet/run_salamander.sh` + `salamander_node.tcl`: two Canon V-25 + MSXPi + `ram2mb` (P2: `EXT2`),
  manual start, per-frame trace (state, E300h-E4FFh hash, banks, segments), P1 picks DUALPLAY with the keys, then random play.
  `SEED`, `EXTRA_TCL`, `MENU`, `ONLY` supported.

**Verified:** the game boots from mapper RAM and plays DUALPLAY in lockstep: 1501 and 3201 frames IDENTICAL between a 2 MB node (30
page-2 pairs, 0 builds) and a 512 KB node (23 pairs, 1 build); desync detection ends both games cleanly (result 4). ROM load ~16 s.

## 2. Open problems

1. ~~Intermittent start-up crash (about 1 run in 3)~~: **fixed in session 2**, section 4.
2. **A desync at frame 3067** in one 6000-frame run (after game over, second game starting, state 04h), before the INIT-clear patch.
   Not reproduced since. Likely the same cause as 1: in every run before the fix `clrRam` was garbage, so the RAM it should clear
   was not cleared (or cleared differently on the two machines).
3. **Speed**: play runs at ~17 frames/s against the cartridge's ~31 (measured: `salamander_debug/cartridge_fps.tcl`). Not profiled yet
   (`salamander_debug/prof.tcl` is ready: time in the exchange, in the bank engine, number of switches).

## 3. Experimental state to undo or keep

- None left. `clrRam` is back to C000h-CFFFh (the C100h experiment is undone; it was a symptom of section 4).

## 4. The start-up crash: cause and fix (session 2)

- Cause: **MSX-DOS's stack was inside the stub.** Under MSX-DOS 1 on the V-25 the TPA stack is at about D53Fh, and the stub
  occupies D000h-D597h. The trampoline copied the stub there and then kept using that stack: `call ENASLT`, `call INIT32` and the
  interrupts INIT32 lets through (BIOS at 0Cxxh, 2992h, 1036h...) pushed over D50Bh-D541h, which is the whole of `clrRam`. This
  happened in **every** run: `salamander_debug/wwatch.tcl` (write watch on D000h-D7FFh + mapper ports, stub compared with
  `stub.bin` at `clrRam`) found 84 bytes differing on both nodes of a run that "passed". Whether a run crashed only depended on what
  the junk at D520h did; the `D521 jp nz,7C54h` of the old step trace was such pushed data.
- Fix (`playnet.asm`): the trampoline saves MSX-DOS's SP (`vDosSp`) and runs on its own stack ending at `TRAMP_SP` = C100h
  (it cannot be higher: Soccer's stub starts at C100h; `overTramp` covers C000h-C0FFh). That stack goes 88 bytes deep with Soccer
  (C0A8h: ENASLT, INIT32 and an interrupt; `salamander_debug/trstack.tcl` measures it), more than the room after the trampoline, so
  the trampoline is laid out in two parts: `trLate` (hook loop, INIT32, the jump; C00Ah-C050h, with `vStart`, `vBase`, `vDosSp`)
  first, and `trEarly` (the copies and slots, run first) last, where the deep stack may overwrite it once done. The start address
  is pushed before INIT32. The game then starts on MSX-DOS's stack, as before the fix (Salamander sets its own before any push:
  no write to D000h-D7FFh between the jump and `clrRam`). Two `ASSERT`s keep 128 bytes under C100h above `trLateEnd` and 32 above
  the copy part.
  A first try with a 68-byte stack after the old layout broke Soccer: the stack ran over `vStart` and node H jumped to garbage.
- Verified (first, 128-byte version): 8 runs of 300 frames (seeds 1-8, 2 MB + 512 KB nodes), all IDENTICAL, stub intact at
  `clrRam` on all 16 nodes (0 diffs), and one 6000-frame run IDENTICAL (the 512 KB node did 1 build), so the frame-3067 desync
  (2. above) did not recur. Final layout: Soccer `run_native.sh 0 0 1500` IDENTICAL (scenes 0-6, foreign writes 0) and 4
  Salamander runs of 300 frames IDENTICAL, 0 stub diffs and 0 writes to D000h-D7FFh before `clrRam` on all 8 nodes.
- **Not run yet:** the trampoline's TCP/IP path (the page-3 copy into G3 now happens on the new stack, which is in page 3 and
  copied with it): run Soccer's `SCENARIO=mixed` (and `tcp`) before merging.

## 5. How to run

```bash
cd /c/Users/roniv/Dev/github/MSXPi-salamander/software/ROM-Patcher
python profiles/salamander/rebuild.py --assembler C:/Users/roniv/Dev/bin/sjasmplus.exe --rom C:/Users/roniv/Dev/MSX/gameroms/SALAMAND.ROM
```

```bash
cd /c/Users/roniv/Dev/github/MSXPi-salamander/software/Client/tests/soccernet && WORK=/c/tmp/salwork SALAMANDER_ROM=C:/Users/roniv/Dev/MSX/gameroms/SALAMAND.ROM EXT2=ram512k TMAX=600 NODETMO=1500 sh run_salamander.sh 3000
```

Results in `$WORK/np/P1.trace`, `P2.trace` (compared by `cmp_pair.py` at the end), `.screen` dumps, server logs in `$WORK`.
A run takes about 4 minutes for 1500 frames (boot ~35 s, load ~16 s). Check progress every few minutes; runs can hang.

`software/Client/tests/soccernet/salamander_debug/` holds the debug scripts used (`hang.tcl` dump on a stall, `stepclr.tcl`
single-step from `clrRam`, `init.tcl` INIT breakpoints with IFF, `ramdump.tcl` per-frame RAM keyed by `nf`, `wr.tcl` writes into the
bank windows, `prof.tcl` timing, `loop2.sh` repeat until a hang). **Their output paths point at the old session's scratchpad: edit
them.** Pass one with `EXTRA_TCL` (several: a file that `source`s each).

## 6. Pitfalls met

- The rig's own breakpoints: an address-only breakpoint also fires in the disk ROM at boot; gate on the stub being in place
  (`[peek 0xD000] == 1 && [peek MK_BLOCK] == 1`). Dumps keyed by a script counter misalign between nodes: key them by `nf`.
- `EXTBIO` handlers and MSX-DOS calls do not keep IX: the loader reloads it (`mSetup`) and `mTab2` no longer uses it.
- The Pi sends GPFs in 512-byte blocks; `piCommand` needs room for a whole block.
- openMSX `screenshot` needs a renderer (`RENDERER=SDLGL-PP`).
- Soccer must stay byte-identical (stub and GPF; unchanged against master). Its `run_native.sh` regression passes with the
  session-2 PLAYNET.COM (MSXPi path only). Anything placed after the trampoline must leave C100h-C5FFh to Soccer's stub.
- A kill by command-line match (`Stop-Process` on `run_native`...) also kills the shell that runs it; and a stopped loop's
  `sh` may survive TaskStop: check for two loops (two `run_salamander.sh` parents) before trusting results.
