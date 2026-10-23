# Handover: Salamander online co-op (PLAYNET 3, image host mapper-ram)

2026-10-23. Paused mid-debugging, at a clean point: an intermittent start-up crash has been narrowed to one precise symptom
(section 4), and nothing else is half-done.

| | |
|---|---|
| Worktree / branch | `C:\Users\roniv\Dev\github\MSXPi-salamander`, `feature/salamander-netplay` (from `master` at `64049cf8`). **Nothing is committed.** The main checkout is shared with other sessions: do not switch branches there. |
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

1. **Intermittent start-up crash (about 1 run in 3), section 4.** Must be fixed first.
2. **A desync at frame 3067** in one 6000-frame run (after game over, second game starting, state 04h), before the INIT-clear patch.
   Not reproduced since. May share the cause of 1 (corrupted stub/RAM), or come from uninitialised RAM (the reason for `clrRam`).
3. **Speed**: play runs at ~17 frames/s against the cartridge's ~31 (measured: `salamander_debug/cartridge_fps.tcl`). Not profiled yet
   (`salamander_debug/prof.tcl` is ready: time in the exchange, in the bank engine, number of switches).

## 3. Experimental state to undo or keep

- `src/glue.asm` `clrRam` currently clears **C100h**-CFFFh (experiment; the intent is C000h-CFFFh) plus F000h-F0DFh and F0F7h. It is
  patched over `ld hl,E000h` at 410Bh (INIT). Decide after section 4 is understood.

## 4. The start-up crash: what is known

- Symptom: in INIT, right after `call clrRam` (410Bh), the CPU runs garbage: either a crash ending in a BIOS loop at 2900h (SP F0E6h,
  `nf` = FFh, no frame ever), or game frames running during INIT, then a desync.
- Decisive evidence (`salamander_debug/step_hung_example.txt`, single-stepped from the `clrRam` breakpoint on both nodes of a hung
  run): the instruction after D520h is **`D521 jp nz,7C54h`**, but the assembled stub has `21 00 C1` (`ld hl,C100h`) at D520h. So **the
  stub in RAM at D520h is not the built stub** in the failing runs: something overwrote the glue (at least D520h-D523h) before INIT
  reached it. Interrupts were off (IFF=0); execution then wandered into the sound driver (7C54h...).
- Same build and inputs pass in other runs, so the overwrite is timing-dependent.
- Not the cause (checked): the clear itself (C000h-C0FFh excluded, still hangs); the game writing 4000h-BFFFh (none, `wr.tcl`); VDP
  status/STATFL/NEWKEY reads (none in the ROM); keyboard paths (all SNSMAT reads handled).
- **Next step:** watch writes to D000h-D5FFh (and D600h-D7FFh) from the moment the trampoline copied the stub
  (`debug set_watchpoint write_mem {0xD000 0xD7FF}`, log PC, address, value, and the slot/segment state), excluding the stub's own
  variable writes (engine rings, `MK_BLOCK`, `rndS`). Suspects, in order: the loader writing the block/tables past `MK_BLOCK`
  (check `mFill` against the table room: tables end exactly at MK_W0 D355h, glue starts after the engine); the trampoline's stub copy
  (`vStubLen`) racing an interrupt with H.KEYI already pointing at the transport; the transport/`XCHG` receive buffer length (L = 14 + 8W
  = 30 for W = 2) against `rxbuf`; the bank engine's `mkCopy` with a wrong home pointing page 1/2 at page 3 segment 0. Compare the
  stub image in GPFBUF before the trampoline with D000h after it.

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
- Soccer must stay byte-identical (stub and GPF): not re-checked since the loader changes; run `run_native.sh` as a regression
  (its GPF is unaffected, but PLAYNET.COM's memory map changed).
