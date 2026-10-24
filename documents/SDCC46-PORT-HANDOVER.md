# Handover: port all MSXPi C code to SDCC 4.6 (native calling convention)

Branch: `feature/sdcc46-port` (off `feature/tcpip-games` at e59728e0).
Goal: every C program builds with SDCC 4.6.0 in its default calling convention (`sdcccall(1)`), links only
SDCC 4.6's own runtime and code built from source in this repo, and no build mixes conventions.

## 1. Why: the MCHAT hang

Commit e59728e0 rebuilt the C clients with SDCC 4.6 and added `--sdcccall 0` to make.bat, because
fusion.lib and the naked asm routines expect stack arguments. But SDCC 4.6's `z80.lib` is built for
`sdcccall(1)`: `__divuint`, `__moduint`, `__divsint`, `strlen`, `memset`, `memcpy`, `memmove`, `strcmp`,
`strstr`... take their arguments in HL/DE. Code compiled with `--sdcccall 0` pushes them on the stack, so every
call into the runtime reads garbage. The prebuilt fusion.lib has the same problem: its C modules (`printnumber`,
`print`...) were compiled by the old SDCC with stack arguments.

Seen on Canon_V-25 + MSXPi + RAM 4MB: MCHAT shows a black screen and never sends its first command. The PC
loops in `__divuint`, called from the games' clock (`gsec += d / 60u`, mchat_local.c:625). The SDCC 4.0
binary passes every check of `mchat_openmsx.py` on the same machine.

Both tools already warn about it on every build:
- `warning 296: non-default sdcccall specified, but default stdlib or crt0`
- `?ASlink-Warning-Conflicting sdcc options: "-mz80 sdcccall(0)" in module "mchat" and "-mz80 sdcccall(1)" in module "divunsigned"`

Also affected:
- **The other programs rebuilt in e59728e0** (pchess, pchess1, pcheckers, nitros) have the same fault.
- **msxpi-bios.lib**: `u16_to_ascii` divides, and the library calls fusion's `Print`, `InPort`, `OutPort`,
  `PrintNumber`, `PrintChar`.
- **PLAYNET.OVL** is built with the default convention, but its own `___memcpy` (netcore/ovl_crt0.s) reads
  all three arguments from the stack and does not pop the count. Under 4.6 the arguments arrive as HL = dst,
  DE = src, count on the stack, and the callee must pop the count. The only call is `peer = from;`
  (netcore.c:344, when the first peer answers): it writes 6 bytes to the wrong place and leaves the stack
  unbalanced. Seen in the generated code; not run yet.
- **make.sh** links an "ABI-0 runtime" from `/mnt/c/Apps/SDCC/lib/z80/z80.lib`, which is the 4.6 one now.
- **Not affected**: the ROM BIOS, MSX-DOS driver, loadrom, msxarch.asm, PLAYNET.COM and soccernet, all
  assembled with sjasmplus.

`C:\Apps\SDCC-4.0.0` is not 4.0.0: it is a second copy of 4.6.0 (its z80.lib is byte-identical to
`C:\Apps\SDCC`'s). The real 4.0.0 is at `C:\Users\roniv\Dev\sdcc-4.0.0`, with the runtime sources in
`share\sdcc\lib\src`. Use it only to compare behaviour; nothing in the final build may depend on it.

## 2. How the order keeps regression testing small

1. **Ship the last known-good binaries until a program is ported.** Stage 0 puts the SDCC 4.0 builds back, so
   the unported programs keep working and are never rebuilt while the port is under way.
2. **Make every hand-written ABI dependency explicit before switching anything.** `__sdcccall(0)` on a
   declaration means the same thing under both conventions, so these edits leave today's `--sdcccall 0` builds
   byte-identical. A byte comparison is the whole regression test for those stages.
3. **Keep shared code apart from the programs.** msxpi-bios.lib is compiled on every make.bat call with that
   call's flags, and the new fusion library will be too, so switching one program changes nothing in another.
4. **Switch one program at a time and test only that program.** Its own harness or smoke test is enough.
5. **One full regression run, at the end.**

| Stage | Changes shipped binaries? | Regression needed |
|---|---|---|
| 0 Known-good binaries, guards, harness | yes, back to the SDCC 4.0 builds | one MCHAT smoke run (known good) |
| 1 PLAYNET.OVL memcpy | PLAYNET.OVL only | netplay tests only |
| 2 Explicit `__sdcccall(0)` | no (byte-identical) | byte comparison only |
| 3 Fusion functions built from source in the repo | no (new build path only) | build/link check only |
| 4 Switch programs one by one | one program at a time | that program only |
| 5 Remove the legacy path | no | full run, once |

## 3. Stages

### Stage 0: safety net and tooling (do first)

0.1 **Put the last known-good binaries back.** Take `mchat.com`, `pchess.com`, `pchess1.com`, `pcheckers.com`,
`nitros.com` and `playnet.ovl` from e59728e0~1 into `software/target/`. Inject the `.com` files into
`target/disks/msxpiboot.dsk` and `tools.dsk` with `dsktool.py copy` (run from the disks folder, back the images
up first). Do not restore the whole images: e59728e0 also updated other files on them. Check which images held
which file before that commit.
Test: `mchat_openmsx.py` on Canon_V-25 + RAM 4MB (see 0.5). It passed with this binary on 2026-10-24.

0.2 **Guards in make.bat and make.sh:**
- Fail when `sdcc --version` is not 4.6.0.
- Fail when the link prints `Conflicting sdcc options`, unless `SDCC_ALLOW_ABI_MIX=1`. That variable is only
  for the byte-identical builds of stage 2.

0.3 **A per-program switch in make.bat/make.sh**, e.g. `ABI1_PROGRAMS=` (empty at first).
- Listed programs: no `--sdcccall 0`, SDCC's own stdlib, msxpi-bios built the same way, the repo's fusion
  library (stage 3).
- Unlisted programs: exactly today's command line, and the 0.2 guard stops them building.
  That is intended: they stay at their stage-0 binaries.

0.4 **A byte-compare helper**, e.g. `software/tools/abi_bytecmp.py <prog>...`. It builds each program at a
given commit and at the working tree with `SDCC_ALLOW_ABI_MIX=1 KEEPMAP=1`, then compares `.com` and `.map`.
make.bat also copies to `..\..\..\MSX\MSXPi\FloppyA`, which is shared: build into a scratch dir instead.

0.5 **Harness (`Client/tests/mchat_openmsx.py`, in the first commit of this branch):**
- `MCHAT_MACHINE=msx2 MCHAT_MSX2_MACHINE=Canon_V-25` runs MSX2 MCHAT from A: (msxpiboot.dsk) on
  Canon_V-25 + MSXPi + RAM 4MB, as on the real machine.
- `MCHAT_SHOTS=24,32` adds screenshots (needs `MCHAT_SHOW=1`: with `set renderer none` there are none).
- `MCHAT_EXTRA_TCL=file.tcl` appends a Tcl file (a PC sampler found the `__divuint` loop).
- **To do: the Panasonic_FS-A1WSX run.** It fails before MCHAT starts, even with the SDCC 4.0 binary: with
  the floppy drive and RAM 4MB, MSX-DOS says "Program too big to fit in memory". Find a layout that boots with
  room for a ~48 KB .COM (e.g. MSXPi drive only, or DOS2) before relying on it. The user wants every MCHAT
  change tested on both Canon_V-25 and Panasonic_FS-A1WSX.

0.6 **Baseline.** Run every harness once against the stage-0 binaries and keep the results in this document.
A later failure can then be pinned on the stage that caused it.

Commit: binaries + disk images, guards, switch, helper. One test run.

### Stage 1: PLAYNET.OVL `___memcpy` (independent)

The overlay already builds in the default convention with 4.6's runtime (build.py: no `--sdcccall`, no
fusion). Only its `___memcpy` override is wrong.
- Preferred: delete the override. 4.6's `memcpy` already uses LDIR, and the override existed only to replace
  4.0's byte loop.
- If the override stays: HL = dst, DE = src, count on the stack, popped by the callee, dst returned in DE.
- Check the comment about interrupts in ovl_crt0.s still holds (4.6 pops the count into BC before LDIR).
- `r_reg` (ovl_main.c) sets both A and L, so it is fine in either convention.

Rebuild with `playnet/build.py`, check the overlay still fits, ship `playnet.ovl`.
Test only netplay: `pchess_tcpip_openmsx.py`, `pcheckers_tcpip_openmsx.py`, the hybrid (`/T /H`) path,
`netcore_cost.py`.

### Stage 1 note: the removed LDIR `___memcpy` (re-apply if needed)

`netcore/ovl_crt0.s` had its own `___memcpy` that copies with LDIR, in place of SDCC 4.0's byte loop (a
performance change). Stage 1 removed it, because it assumed the SDCC 4.0 stack convention. SDCC 4.6's `memcpy`
(z80.lib, `___memcpy` is an alias) also ends in LDIR, so no speed is expected to be lost, but this was not
measured: re-check with `netcore_cost.py` and re-apply the override if it matters. The override in the 4.6
convention (HL = dst, DE = src, count pushed by the caller and popped by the callee, dst returned in DE;
untested):

```
___memcpy::
        pop     af                  ; return address
        pop     bc                  ; BC = count (the callee pops it)
        push    af
        push    hl                  ; dst, for the return value
        ld      a,b
        or      c
        jr      z,1$
        ex      de,hl               ; HL = src, DE = dst
        ldir
1$:     pop     de                  ; DE = dst
        ret
```
(The old SDCC 4.0 version is in git:
`git show e59728e0:software/Client/src/playnet/netcore/ovl_crt0.s`.)

### Stage 2: make the hand-written ABI dependencies explicit (byte-identical)

Add `__sdcccall(0)` to the declaration and the definition of every routine whose asm assumes stack arguments
or an L/HL return. The list below comes from a scan of all naked functions and of asm that calls C:

| File | Routine | Why |
|---|---|---|
| `asm-common/transport/generate.py` -> `C-common/lib/payload_generated.h` | `payload_rx`, `payload_tx` | read 3 stack arguments; change the generator, then regenerate (`generate.py --check` runs in make.bat) |
| `C-common/lib/msxpi-bios.c`, `C-common/header/msxpi.h` | `get_sp` | returns in HL (sdcccall(1) returns 16 bits in DE) |
| `C-common/lib/msxpi-bios.c` | `ctrl_esc_pressed` | sets A and L, so it is already neutral; add a comment |
| `Client/src/nitros.c`, `Client/src/ssh.c` | `put(uint8_t)` | reads its argument at 4(ix) |
| `Client/src/nitros.c`, `Client/src/ssh.c` | `key()` | returns in L/HL; ssh's calls `_Inkey` from asm (fusion, stack convention) |
| `Client/src/p.c` | `SetTimeFromMSXPi(hour, min, sec)` | reads 3 stack arguments, returns int |
| `Client/src/mchat_local.c` | `lt_copy_code` and the `lt_copy` function-pointer cast | the copy in `seg_code` reads 3 stack arguments; put `__sdcccall(0)` on the pointer type |

Not affected (checked): the other 24 naked routines take no arguments, return nothing and work through
globals (kern6, hmmm, write_palette, the msxarch mapper handlers, the `raw_call` UNAPI trampolines, the
msxpi-bios link claim/release...). IX-indexed asm in `mchat_ui_s6.c` and `pchess_sha.c` indexes globals.
Re-run the scan before starting: every `__naked` definition with arguments or a return value, and every `__asm` block that uses `add hl,sp` / `add ix,sp` or calls a C function (`call _Name`).

Verification: `abi_bytecmp.py` over all 10 programs at e59728e0 against the working tree, with
`SDCC_ALLOW_ABI_MIX=1`. All `.com` files identical, so no runtime test. Nothing is shipped.

### Stage 3: the fusion functions built from source in the repo (new build path only)

The programs use 31 Fusion-C functions:

| Kind | Functions (source file in fusion-c/source/lib) |
|---|---|
| asm, stack arguments: declare `__sdcccall(0)` | CopyRamToVram/CopyVramToRam (vram.s), FillVram (fillvram.s), HideDisplay (hideshowdisplay.s), InPort (inport.s), OutPort (outport.s), Inkey (inkey.s), InputChar (inputchar.s), IsDigit (ctype.s), JoystickRead (joystickbios.s), Locate (locate.s), PrintChar (printchar.s), PutCharHex (printhex.s), ReadMSXtype (readmsxtype.s), ReadSP (readsp.s), Screen (screen.s), SetDate (setdate.s), StrCompare (strcompare.s), StrCopy (strcopy.s), VDPwrite (check which file: the scan matched _old_vdp_graph2.s), fcb_open/close/create (fcb_open.s), fcb_read/write (fcb_read.s), fcb_find_first/next (fcb_find.s) |
| C: compiled in the program's convention, no annotation | Print (print.c), PrintNumber (printnumber.c), Width (width.c), ReadTPA (readtpa.c) |

Steps:
1. **Check the Fusion-C licence** before copying sources into this repo. The tree has no licence file. If
   copying is not allowed, make.bat/make.sh compile the same files from the external fusion-c tree at build
   time instead; only our header lives in the repo.
2. Put the sources in `software/C-common/fusion/` and a header with only these prototypes, e.g.
   `software/C-common/header/fusion.h`. Asm functions get `__sdcccall(0)`, C ones nothing. Keep return types
   exactly as the asm returns them (L / HL).
3. The asm sources may call other fusion helpers or SDCC runtime routines. Check each `.s` for `call _...`
   and bring along whatever it needs.
4. Build them into a library on each make.bat call (like msxpi-bios), used only by the `ABI1_PROGRAMS` path.
   The programs keep including `msx_fusion.h` until each is switched in stage 4.

Verification: build `templatc` through the ABI1 path into a scratch dir. It must link with no `Conflicting sdcc
options` and no `warning 296`, and the map must show only 4.6's z80.lib plus repo modules. Nothing is shipped.

### Stage 4: switch the programs one at a time

For each program:
1. Add it to `ABI1_PROGRAMS`.
2. Point its includes from `../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h` to the
   repo header.
3. Build with `KEEPMAP=1`. Check the map and the `.com` size against the program's memory limit.
4. Run that program's test, then commit the source and the binary, and inject the binary into the disk image(s).

Order: small first to prove the path, then the urgent one, then by shared code.

| # | Program | Test |
|---|---|---|
| 4.1 | templatc (pilot: msxpi-bios + Print only) | run it in openMSX against a local server |
| 4.2 | **mchat** (the reported hang) | `mchat_openmsx.py`: MSX1 (`/1`, Canon), MSX2 on Canon_V-25 + RAM 4MB, MSX2 on FS-A1WSX (once 0.5 works), `MCHAT_LINK=tcp` (`/t`, INL); game launch from chat (`pchess_chat_openmsx.py` covers the launch path) |
| 4.3 | pcopy | copy to and from A:/B: with `MSXPI_HOME` pointing at a scratch msxpi.ini and copies of the images (never the real msxpiboot.dsk) |
| 4.4 | p | a few `p` commands against a local server, and the time set (`SetTimeFromMSXPi`) |
| 4.5 | nitros | start, typing (put/key), exit |
| 4.6 | ssh | connect to a local test sshd through the server, typing, exit |
| 4.7 | msxarch | listing and extraction of a test archive; mapper handlers (ascii8/16) with a ROM image from `C:\tmp\msxpi` (delete the cached ROM after regenerating) |
| 4.8 | pchess | `pchess_memory_test.py` (TPA top 0xC806 on a Canon V-25 with INL), `pchess_chat_openmsx.py`, `pchess_tcpip_openmsx.py`, `pchess_nopi_openmsx.py`, `pchess_reconnect_openmsx.py`, `pchess_rules_test.py` |
| 4.9 | pchess1 | `pchess1_chat_openmsx.py` + the same memory check |
| 4.10 | pcheckers | `pcheckers_chat_openmsx.py`, `pcheckers_irc_openmsx.py`, `pcheckers_tcpip_openmsx.py`, `pcheckers_rules_test.py` |

Notes for 4.8 to 4.10:
- Apply every change to PCHESS, PCHESS1 and PCHECKERS, testing in PCHESS first.
- Re-measure pchess's `--max-allocs-per-node 100000`: sdcccall(1) usually makes code smaller, so the slow
  build may no longer be needed.
- pcheckers has a wrapper around `new_game(0,0)` because SDCC 4.6 emitted an invalid `ld hl, a` with
  `--sdcccall 0`. Try without it under sdcccall(1). If the bug remains, keep the wrapper and report it to SDCC
  with a minimal case.

### Stage 5: remove the legacy path, final regression

- Remove `--sdcccall 0`, the switch, `SDCC_ALLOW_ABI_MIX`, make.sh's `SDCC_ABI0_LIB`/`--nostdlib`, and every
  reference to the external fusion-c tree. Keep the 0.2 guards as permanent checks.
- make.sh: require SDCC 4.6 (the distro's 4.2 differs). Allow a path such as `SDCC_BIN` for WSL.
- Update comments that name SDCC 4.0/4.2 (`build`, make.bat, make.sh, MCHAT.md, PCHESS.md, netcore notes).
- Run every harness and host test once and compare with the 0.6 baseline. This is the only full run.
- Rebuild the release artefacts the usual way (`build`), bump BuildIds per the project's rules (one ID per
  board/firmware variant), and update the disk images.

## 4. Rules that apply throughout

- Build only through make.bat/make.sh with the program name; check `target\<name>.com`'s timestamp.
- Other sessions use the main checkout: work in this worktree (`C:\Users\roniv\Dev\github\MSXPi-mchat-sdcc46`),
  never switch branches there. make.bat writes to the shared FloppyA.
- openMSX: use the Windows build (`openmsx-MSXPi_v1.6.1`). Keep throttle on for MSXPi runs, and check ports
  5044 and 6668 are free.
- Check long runs every few minutes; they hang.
- Never commit ROM dumps or disassemblies.

## 5. State at handover (2026-10-24)

- **On the branch:** the harness changes (0.5) and this document. No build-script or binary changes yet.
- **SDCC 4.6.0** is at `C:\Apps\SDCC` (`C:\Apps\SDCC-4.0.0` is the same 4.6.0). The real 4.0.0, for
  comparisons only, is at `C:\Users\roniv\Dev\sdcc-4.0.0`.
- **Known-good SDCC 4.0 MCHAT:** `git show e59728e0~1:software/target/mchat.com` passes all 12 checks of
  `MCHAT_MACHINE=msx2 MCHAT_MSX2_MACHINE=Canon_V-25 python mchat_openmsx.py <com>`. The e59728e0 binary fails
  all 12.

## 6. Progress log (stage 4 findings)

- **Stage 0 baseline:** SDCC 4.0 `mchat.com` passes 12/12 on Canon_V-25 + RAM 4MB (MSX2 build).
- **FS-A1WSX "Program too big":** TPA top is 0xC906 with a drive (max .COM about 51.4 KB), and the SDCC 4.0
  mchat is 51,727 bytes. Holding CTRL during boot (drive 2 not initialised) raises it to 0xD606; tested with
  `client_smoke_openmsx.py --hold-ctrl 12`: the 51,727-byte SDCC 4.0 mchat then loads and runs (SCRMOD 6).
  Without CTRL it still fails. The SDCC 4.6 mchat is 46.7 KB and loads without CTRL.
- **Fusion-C licence:** msx.wiki lists CC BY-SA 4.0 (secondary source; the tree has no licence file). Its files
  are not copied here: `tools/build_fusion46.py` assembles them from the external tree at build time. Stage 5
  must decide: copy them (and mark them CC BY-SA), or keep the external tree for the `.s` files and
  `crt0_msxdos.rel`.
- **SDCC 4.6 internal error in ssh.c** (`validateLink failed in DCL_PTR_OPTIONAL`, SDCCicode.c:2501) on
  `memmove(cells[vy]+vx, ...)` with a 2-D array; the SDCC 4.0-era tree never rebuilt ssh with 4.6. Worked
  around with a row pointer. Worth a minimal case for the SDCC tracker.
- **msxarch under sdcccall(1):** inline `push af` / `pop af` inside C functions (`mapperCopyBank`,
  `prewarmKonami16PairCache`) shift SP-relative locals, which sdcccall(1) code uses. A mapped ROM then
  never started (idle loop of the launch trampoline). Replaced with `irq_save()` / `irq_restore()` naked
  helpers (`__sdcccall(1)`). Scan for the pattern in the games before porting them.
- **Not testable here:** `MCHAT_LINK=tcp` and the TCP/IP games tests (link to 192.168.99.1 times out for the
  SDCC 4.0 binaries too), nitros sessions (need xroar), `netcore_cost.py` (needs `sz80`; SDCC 4.6 ships
  `ucsim_z80` with another command line; the real 4.0.0 in Dev\sdcc-4.0.0 is a macOS build).
- **Disk/test helpers:** `Client/tests/client_smoke_openmsx.py` (one client, real server, `--floppy`,
  `--hold-ctrl`, `--wsl-server --fake-ssh`, `--shots`, `--probe`).
