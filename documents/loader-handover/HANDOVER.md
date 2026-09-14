# Handover: new generic ROM loader (table-driven, client-side patching)

## Goal
Create a NEW MSX megaROM loader. Leave msxarch (software/Client/src/msxarch.c)
untouched - it is the reference implementation, not the thing to modify.

The new loader separates "what to patch" from "which loader runs it":
- A per-game patch TABLE, keyed by ROM SHA-1, with SYMBOLIC records:
    bank 00 +014D  expect 7A 87 87 87 C6 60 67 F3 73  ->  F3 CD <DISPATCH> 00 00 00 00 00
    bank 0F +0081  expect 32 00 60                      ->  CD <WIN1>
  Placeholders (<WIN1>..<WIN4>, <PAGE1>, <PAGE2>, <DISPATCH>, ...) are resolved
  by each loader to the addresses of its own resident code.
- A GENERIC Z80 patch routine (reusable by any loader): verify expected bytes,
  substitute symbols, write replacement. Touches only listed spots - no scanning.
- The server (or an offline tool) GENERATES tables using the existing
  detection/patch rules in mapper_detect.py; hand-written records cover special
  cases. Tables can also be pre-built files next to the ROMs (loader without Pi).
- Server sends the UNMODIFIED ROM + patch list, instead of a patched image.
- Also worth studying first: how SofaRun's ROM loader (SROM) does it (not verified
  in the previous chat).

## Repository / branch
- Repo: C:\Users\roniv\Dev\github\MSXPi  (git remote costarc/MSXPi)
- Current branch: fix/msxarch-1942 (based on release/v1.6). master = v1.5.
  Create a new branch for the loader from release/v1.6 (or from this branch if
  the uncommitted msxarch work below is committed first - ask the user).
- Other worktrees exist (MSXPi-v16 = release/v1.6, MSXPi-cpld, MSXPi-deploy, ...).
- NEVER commit the user's own uncommitted files (msxpi-driver.mac, msxpiext.asm,
  build, openMSX files, ROM/disk images, msxarch.ini, FSA1F files, unrelated
  msxpi-server.py hunks). Commit only files you changed, hunk by hunk if needed.

## State of msxarch at handover (reference material)
Committed on fix/msxarch-1942: ff111fb, 4867c04 (H.STKE start), 07fdd4a
(inc/dec before exact bank registers - PENNANT).
UNCOMMITTED (made in the previous chat, tested by user unless noted):
- msxarch.c: game list size display is server-side; loading screen
  "Loading <name> (NNNK)" + progress bar drawn once via BIOS, cells filled with
  OUT (98h),'#' (no BIOS in transfer loop); 8K window dispatcher copied to FAD8h
  (16 bytes) and sent as 7th handler address in the selection.
- msxpi-server.py: per-source file sizes (local getsize, 00index.txt Size column
  = UNPACKED ROM KB, dir-listing size column, HEAD fallback per page via
  127.0.0.1 + one session); file name sent after ROM header; Ice World fix
  (16KB plain ROM with INIT in 8000-BFFF traced from 8000h and mirrored to 32KB);
  7th handler = dispatcher, passed to patch_indexed_switches; import re.
- mapper_detect.py: patch_indexed_switches() for the ASCII8 computed window
  select pattern 7A 87 87 87 C6 60 67 F3 73 (Hydlide 3 routine at 414Dh).
- Hydlide 3 (msxarchive msx1 #96) verified in openMSX: title, Set Up menu,
  Name List. Ice World (#97) tested by user.
- Design doc: C:\Users\roniv\Dev\github\MSXPi\Documents\msxarch-design.html
  (identification, patch engine, per-ROM cases, limits, path to all games).

Key msxarch facts a new loader will reuse:
- Server: software/Server/Python/src/msxpi-server.py (msxarchive command),
  mapper_detect.py (romdb lookup on openMSX softwaredb.xml by SHA-1, detection
  fallback, patch_bank_switches with plausibility rules, neutralise_rom_writes
  for plain ROMs, patch_indexed_switches).
- ROM DB: https://raw.githubusercontent.com/costarc/openMSX/master/share/softwaredb.xml
  (local copy C:\Users\roniv\Dev\github\openMSX\openMSX\share\softwaredb.xml).
- ROM header 16 bytes: 'R', version, mapper (0 plain,1 Konami,2 ASCII8,3 ASCII16,
  FF rejected), bank KB, bank count (u16), total size (u32); text after it =
  reject reason or game name. Konami SCC is server-internal type 4, sent as 1.
- Transfer: 8KB blocks (MAXBUFSIZE); PerformHandshake then RECVDATA_ONEBLOCK.
- MSX side (MSX-DOS 1, not mapper-aware): detect mapper segments itself; resident
  handlers F975-FAF4: table F975, cur F9B5, page records F9B9/F9BC, 8K handler
  entries F9C0/C5/CA/CF (push hl/ld l,n/jr - 5 bytes apart), pair caches
  FA90/FAB4 (12 entries), 16K handlers FAC0/FAD8, dispatcher FAD8 (8K games).
  MSX2 sysvars start FAF5.
- Launch trampoline at C000h: RST30 hooks not in BIOS/SUB-ROM slot -> RET,
  INIT32, push return, jp (4002h); if INIT returns, start via H.STKE (FEDAh).

## Build
- Client (any program in software/Client/src): pass the program NAME, run by
  full path from the software folder:
      cmd.exe /d /c "pushd C:\Users\roniv\Dev\github\MSXPi\software && C:\Users\roniv\Dev\github\MSXPi\software\make.bat msxarch"
  (plain `cmd /c make.bat` from the shell tools did NOT find the batch file).
  Without a name it only rebuilds msxpi-bios.lib. Output: software\target\<name>.com,
  also copied to C:\Users\roniv\Dev\MSX\MSXPi\FloppyA - which the openMSX test
  instance sees as drive C: (MSXPi drive). Run new builds from C:, not A:.
  Check target\<name>.com timestamp to confirm it rebuilt.
- SDCC asm: no apostrophes in comments inside __asm blocks; copied resident code
  must use relative jumps only.

## Run the server (Windows)
    cd C:\Users\roniv\Dev\github\MSXPi\software\Server\Python\src
    python -u msxpi-server.py
Listens on 0.0.0.0:5000. Restart it after every server-side change.
Local HTTP ROM server (user usually runs it): simple_http_server_nosizes.py in
the same folder, port 8000, serving C:\Users\roniv\Dev\MSX\gameroms.
Downloaded/extracted archives are cached in C:\tmp\msxpi (00index.txt caches too).

## Run openMSX (test configuration, with automation poller)
Ask the user before launching openMSX (standing rule), then:
    cd C:\Users\roniv\Dev\github\MSXPi\software
    ..\..\..\MSX\MSXPi\openmsx-MSXPi_v1.6\openmsx.exe -script emul_start_config_tests.txt -script C:\Users\roniv\Dev\github\MSXPi\Documents\loader-handover\poll.tcl
emul_start_config_tests.txt: Panasonic_FS-A1WSX (MSX2+), ext MSXPi, ext ram4mb
(256 mapper segments), diska = C:\Users\roniv\Dev\MSX\MSXPi\FloppyA.
User's own launchers: software\startOpenMSX_Tests.bat, startOpenMSX.bat
(emul_start_config_MSXPi.txt), startOpenMSX_MFRSCCSD.bat.
After a host-folder change, the disk is only re-read on reinsert:
    diska eject; diska C:/Users/roniv/Dev/MSX/MSXPi/FloppyA; reset

## Automation tools (C:\Users\roniv\Dev\github\MSXPi\Documents\loader-handover)
- poll.tcl: loaded by openMSX; every 0.2s runs cmd.tcl from this folder and
  writes the result to res.txt.
- om.py: send one Tcl command and print the result:
      python om.py "<tcl>"          (OM_TIMEOUT env, default 30s)
  Do not end commands with `return` (shows as ERROR); end with `set r ok`.
- helpers.tcl: `source` it first; procs `scr` (screen text, text modes only)
  and `sendkeys "text\r"` (type_via_keybuf).
- sitediff.py: offline compare of patched sites between two mapper_detect
  versions over all ROMs (edit paths inside).
Useful Tcl: reg pc / reg sp; peek addr; debug read_block memory addr size
(use `binary scan ... H* v`); debug read ioports 0xA8; vdpreg n;
disasm addr n; screenshot -raw <file.png> (then view the PNG);
keymatrixdown 8 0x01 / keymatrixup 8 0x01 (space); set throttle off (fast boot).
Typical session: boot -> `sendkeys "c:\r"` -> `sendkeys "msxarch\r"` ->
"1\r" (msxarchive msx1) -> game number -> wait -> screenshot / sample registers.

## Test ROMs
- C:\Users\roniv\Dev\MSX\gameroms (51 ROMs: Nemesis, 1942, METAL, MGEAR, USAS,
  VAMPIRE, CONTRA, VALLEY2, KV2 Gold, MANBOW, BILLIARD, BUBBLE, OUTRUN, TETRIS,
  PENGUIN, ARCTIC, XEVIOUS, ISHTAR, SRAMBO, ALESTE, ANDROGYN, FANZONE2, PENNANT,
  GOONIES, GALAGA, CASTLE, AVALANCH, FROGGER, ... SUPERLOA unsupported).
- msxarch.ini menu: msxarchive msx1 / msx2, http://localhost:8000, local paths.
- Hydlide 3: C:\tmp\msxpi\hydlide3.lzh (ASCII8, 512KB, computed window select).

## User preferences
- Speed is the priority on the MSX side: avoid BIOS calls in loops; use direct
  VDP (OUT 98h) where possible.
- Keep msxarch untouched in this work.
- Ask before launching openMSX; commit only your own changes.
