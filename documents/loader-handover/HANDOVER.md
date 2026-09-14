# Handover: ROMLDR, a table-driven MSX ROM loader in Fusion-C (MSX-DOS1 + DOS2/Nextor)

Read `ROM-LOADER-MODEL.md` in this folder first. It is the reusable contract
(identification, symbols, runtime ABI, patch table formats, generator). This
file covers the concrete work: what to build, where, in what order, and how
to test it.

## 0. Status / what changed since the previous handover
- All msxarch work listed as "uncommitted" before is now committed:
  ff111fb, 4867c04, 07fdd4a, **c130baa** (progress bar, list sizes, Ice World,
  Hydlide 3 / DISPATCH at FAD8h).
- Current branch: `fix/msxarch-extract-cleanup`, with the user's own uncommitted
  files (driver, ext ROM, openMSX files, disks, msxarch.ini, make/build,
  server hunks). Create `feature/romldr` from release/v1.6 (decided).
- SofaRun (SROM) has still not been studied. Do this before finalising the
  DOS2 memory path (step 3); record the findings in section 7.

## 0.1 Decisions (user, 2026-09-14)
- Base branch: **release/v1.6**, so create `feature/romldr` from it.
- DOS1 testing: `software\startOpenMSX_Tests.bat`.
- DOS2/Nextor testing: `software\startOpenMSX_MFRSCCSD.bat` (FS-A1WSX,
  MegaFlashROM SCC+ SD, MSXPi). The user updated its floppy path to match
  make.bat's copy folder.
- **Loading method: generic rules by mapper type are the default for every ROM**,
  as msxarch already does (OUTRUN loads without any per-game data). Model 4.0 / 4.7.
- **Exceptions: one text database, `ROMDB.TXT`**, looked up by name or alias,
  with optional sha1/crc32/size. It lists only games too specific for the
  rules, including plain ROMs with inverted or mirrored banks and similar.
  A ROM with no entry is never refused for that reason.

## 1. Goal and scope
`ROMLDR.COM`, built with Fusion-C/SDCC, runs under **MSX-DOS1** and **MSX-DOS2 /
Nextor**. It loads plain, Konami, Konami-SCC, ASCII8 and ASCII16 ROMs.
- Source A (first milestone): **disk**. `ROMLDR GAME.ROM` detects the type,
  applies the rules on the MSX, then applies any `ROMDB.TXT` entry. It needs no Pi.
- Source B (second milestone): **MSXPi**. It uses the new server command in
  model section 4.6.
- Do not change: `msxarch.c`, `mapper_detect.py` behaviour, or the
  `msxarchive` server command.
- Out of scope: SRAM mappers (ascii8sram*, ascii16sram* load as their base
  type, with no SRAM), SCC sound emulation, Konami5 carts with R-type/SuperLodeRunner mappers.

## 2. Files to create
| File | What |
|------|------|
| `software/Server/Python/src/mrp.py` | Rules to records, ROMDB.TXT parser, CLI `--rules` (model 4.5/4.7). Imports mapper_detect. |
| `software/Server/Python/src/test_mrp.py` | Equivalence test over gameroms (model 4.5). |
| `software/C-common/header/mrprules.h` | Z80 port of detection plus site rules (model 4.7). |
| `software/Client/src/romldr.c` | Main program: args, file I/O, UI, launch. |
| `software/C-common/header/mrp.h` | Record structs, symbol ids, `mrp_apply()` (C with a small asm compare). |
| `software/C-common/header/romrt.h` | Resident handlers (naked asm) *copied* from msxarch.c, plus relocation. |
| `software/C-common/header/memseg.h` | DOS1/DOS2 segment layer (section 3). |
| `software/target/ROMDB.TXT` | Exceptions database (model 4.0), shipped next to romldr.com; the Pi server reads the same file. Seed it with HYDLIDE3 and ICEWORLD. |

`make.bat` compiles exactly one `.c` (`Client\src\%1.c`), so the shared parts
are headers with the code in them, not separate .rel files. Build:
```
cmd.exe /d /c "pushd C:\Users\roniv\Dev\github\MSXPi\software && C:\Users\roniv\Dev\github\MSXPi\software\make.bat romldr"
```
Output: `software\target\romldr.com`, also copied to `C:\Users\roniv\Dev\MSX\MSXPi\FloppyA`
(drive C: in the test openMSX). Check the timestamp.
SDCC asm rules: no apostrophes in `__asm` comments; code that gets copied to
page 3 uses relative jumps only (see msxarch's `jp po` note).

## 3. Memory layer: the main DOS1 vs DOS2 difference
Interface (memseg.h):
```
uint8_t ms_init(void);                 // detect DOS, mapper, TPA segments
uint8_t ms_alloc(uint8_t *seg);        // one 16K segment, RC_FAILED when exhausted
void    ms_put(uint8_t page, uint8_t seg);  // page 1 or 2, no BIOS, usable with DI
uint8_t ms_tpa(uint8_t page);          // segment DOS had in page 0-3 at start
void    ms_restore(void);              // put TPA segments back (error exit)
```
**DOS version**: DOS function `_DOSVER` (6Fh). Set B=0 before the call, and
treat B<2 as DOS1. *Verify on DOS1, DOS2.2 and Nextor 2.1 in openMSX*: the
behaviour of an undefined function on DOS1 is the part to confirm.

**DOS1 backend**: exactly msxarch's code (`detectMapperSegments`,
`takeSegment` top-down, TPA segments reserved). Known weakness: it reads TPA
segments with `IN (FCh-FFh)`. That works in openMSX and on most machines,
but some mappers have write-only ports. Keep it, and note it as a limit.

**DOS2/Nextor backend**:
- `HOKVLD` (FB20h) bit 0 must be set, otherwise fall back to DOS1 probing.
- `EXTBIO` (FFCAh) with D=4, E=2 returns HL = mapper support jump table.
  Entries: ALL_SEG +00h, FRE_SEG +03h, PUT_P1 +1Eh, GET_P1 +21h, PUT_P2
  +24h, GET_P2 +27h, GET_P3 +2Dh. *Check the offsets against the DOS2
  Program Interface doc before relying on them.*
- `ALL_SEG` A=0 (user), B=0 (primary mapper). This way DOS2's RAM disk and
  other programs are respected. Free all segments with FRE_SEG only on an
  error exit; a launched game never returns.
- Do not use Fusion-C `AllocateSegment()` on DOS1: it vectors into nothing (see
  msxarch.c comments). On DOS2 it is acceptable, but calling the jump table
  directly keeps one code path under our control.
- Use `GET_Px` for TPA segments, not IN ports.
- The primary mapper must be the one in the TPA slot. The handlers do direct
  `OUT (FDh/FEh)`, which only addresses that mapper, so only allocate from B=0.
- For an 8K game, `ms_put` inside the handlers stays a direct OUT on both
  backends (speed). DOS2's PUT_Px is used only by the loader before launch.

**Capacity**: storage = bank_count (16K) or ceil(bank_count/2) (8K), plus 2 exec,
plus up to 22 pair-cache segments (these may be fewer; msxarch degrades
gracefully). A 1MB ROM needs 64+2 segments, so it does not fit a 1MB mapper
under DOS2 (DOS2 takes some). Report "need N, have M" as msxarch does.

## 4. Load pipeline (disk source)
1. Parse the argument and open `GAME.ROM`. DOS1: FCB (Fusion-C `fcb_*`,
   see msxarch `SetFcbFilename`). DOS2: handles (`Open`/`Read`). Put this
   behind `rf_open/rf_read/rf_close`. Paths and subdirectories only work
   on DOS2.
2. Take the file size and compute the segment count (ceil(size/16K)).
3. Allocate segments (section 3). The bank size is not needed yet.
4. Compute CRC-32 while reading the ROM in 8KB chunks **into a TPA buffer below 8000h** (not in page
   1: the DOS1 disk ROM swaps page 1 during BDOS calls), then DI, `ms_put(2,seg)`,
   LDIR to 8000h/A000h, restore page 2, EI. Chunk c goes to segment c>>1 at offset
   (c&1)*2000h, the same mapping as msxarch `loadBanksIntoStorage`. Progress
   bar: copy msxarch `progressStart/progressDot` (OUT 98h, no BIOS in the loop).
4b. Look up the ROM in `ROMDB.TXT` (crc/sha1, then name or alias). The entry
   may override the mapper type and flags.
4c. With no type from the entry, detect it on the MSX (tallies collected
   during step 4). Run the generic rules and produce records (`mrprules.h`),
   unless `rules-off` is set. An unrecognisable megaROM is refused *as
   undetectable*, not as missing from the database.
5. `mrp_apply()` on rule records plus entry records, in two passes (verify all, then write), with read/write callbacks
   that page the segment into page 2. On a mismatch: print the record offset
   plus the expected and found bytes, then abort.
6. Relocate the residents (`romrt.h`), fill the 64-entry table and the pair caches,
   and set the initial banks. Resolve symbols: WIN1..4 = F9C0/C5/CA/CF,
   PAGE1=FAC0, PAGE2=FAD8, DISPATCH8=FAD8 (8K only). These are msxarch's
   addresses; keeping them makes the equivalence test trivial.
   **Note**: symbols must be resolved *before* step 5, so relocation data
   comes first, but the copy into page 3 happens after all DOS calls (DOS2
   keeps its own code and data in page 3; copy as late as possible).
7. Plain ROMs: the image goes into RAM segments in pages 1/2 (`base`, mirror flags),
   then patches. Under DOS2 the TPA page 1/2 segments may be used directly.
8. Launch contract (model 3.5). This is a copy of msxarch `launchGame`.

The Pi source replaces steps 1–4 with: server command, header, table, image
blocks (`PerformHandshake` + `RECVDATA_ONEBLOCK` straight into page 2
segments, as msxarch does).

## 5. Work order (each step ends testable)
1. `mrp.py` plus `test_mrp.py`: rules produce records equal to `patch_for_msx()`
   for all 51 gameroms, plus HYDLIDE3 (`C:\tmp\msxpi\hydlide3.lzh`) and ICEWORLD.
   Also the ROMDB.TXT parser and seed entries.
2. `romldr` DOS1, 16K only (ALESTE, XEVIOUS), with the Z80 rules for
   ASCII16. This proves file I/O, segments, rules, mrp_apply and launch. Diff
   the records against `mrp.py --rules`, and measure the time.
3. 8K rules and handlers plus pair cache (NEMESIS, METAL GEAR, PENNANT scc,
   OUTRUN, HYDLIDE3).
4. Plain ROMs with mirrors (FROGGER, ICEWORLD, GALAGA). Self-writes: first
   as ROMDB.TXT entries (GOONIES, VALLEY), then the Z80 tracer if it is worth it.
5. DOS2 backend, tested with `startOpenMSX_MFRSCCSD.bat` (Nextor).
6. MSXPi source: the new server command (model 4.6) and a romldr menu.
7. Regression sweep: every gameroms title on DOS1 and DOS2, recording a result
   table (title / mapper / DOS1 / DOS2 / note) in `documents/`.

## 6. Test environment (unchanged tools, still valid)
- **Ask before launching openMSX** (standing rule).
- DOS1: `software\startOpenMSX_Tests.bat` (emul_start_config_tests.txt:
  FS-A1WSX, MSXPi ext, ram4mb, diska = FloppyA). For automation, add
  `-script ...\loader-handover\poll.tcl` to the openmsx command line.
  After the host folder changes: `diska eject; diska C:/Users/roniv/Dev/MSX/MSXPi/FloppyA; reset`.
- DOS2/Nextor: `software\startOpenMSX_MFRSCCSD.bat` (emul_start_config_MFRSCCSD.txt:
  FS-A1WSX, MegaFlashROM SCC+ SD, MSXPi). Adding poll.tcl there also needs a
  script argument; ask the user before editing their launcher.
- Automation: `om.py "<tcl>"` → `poll.tcl` → `res.txt`. `source helpers.tcl`
  gives `scr` and `sendkeys`. End commands with `set r ok`, not `return`.
  Useful: `reg pc`, `peek`, `debug read_block memory a n`, `debug read ioports 0xFE`,
  `disasm`, `screenshot -raw f.png`, `set throttle off`.
- Server (Pi source only): `cd software\Server\Python\src && python -u msxpi-server.py`
  (port 5000, restart after changes). ROM HTTP: `simple_http_server_nosizes.py`, port 8000.
- ROMs: `C:\Users\roniv\Dev\MSX\gameroms`; cache `C:\tmp\msxpi`.
- ROM DB: local `C:\Users\roniv\Dev\github\openMSX\openMSX\share\softwaredb.xml`.

## 7. Open questions (ask the user or investigate)
- SofaRun SROM: how it allocates segments on DOS1 (it also uses F975h as a
  resident, per msxarch notes), and how it handles DOS2 and Nextor.
- Disk loader without the Pi: softwaredb.xml (1.4MB) is too big for the MSX,
  so types come from detection. Should ROMDB.TXT also hold `mapper` lines for
  ROMs whose detection is known to be wrong or ambiguous? (Model 4.0 allows it.)

## 8. Rules (unchanged)
- Speed first on the MSX: no BIOS calls in loops, direct VDP OUT for progress.
- Keep msxarch untouched.
- Commit only your own files, hunk by hunk. Never commit the user's own
  uncommitted files (driver, ext ROM, openMSX share, disk/ROM images,
  msxarch.ini, build/make, unrelated server hunks, `tatus`, emul_*.txt).
