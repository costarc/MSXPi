# msxarch.com Assembly Port — Status

Source: `software/Client/src/msxarch.c` (1695 lines, SDCC + Fusion-C).
Target: hand-written Z80 asm, assembled with z80asm (`C:\Users\roniv\Dev\z80asm-1.8`),
reusing `software/asm-common/include/*.asm` for the MSXPi wire protocol.

## Dependency audit

- `software/asm-common/include/msxpi_bios.asm` already implements the low-level
  protocol routines msxarch.c calls through `msxpi.h`: `CHKPIRDY`, `PIREADBYTE`,
  `PIWRITEBYTE`, `resetMSXPI`, `SENDDATA`, `PerformHandshake`,
  `RECVDATA_ONEBLOCK`, `SendCommandToMSXPi`, `PRINTPISTDOUT`, `CLEARBUF`. This
  is the same source of truth `template.com.asm` and the ROM-Patcher profiles
  build on — no duplication needed for the protocol layer.
- **Gap**: `msxpi.h`'s `RECVDATA` (multi-block, used by the archive-list
  receive in `main()`) and `SENDDATA2` are NOT in asm-common as separate
  labels — only single-block `RECVDATA_ONEBLOCK` and `SENDDATA`. Need a thin
  multi-block wrapper loop in the new asm (loop calling `RECVDATA_ONEBLOCK`
  until a non-`RC_READY` code, same pattern `loadrom()` already uses inline).
- **Gap**: Fusion-C screen/keyboard/string/FCB calls used throughout
  msxarch.c have no asm-common equivalent and must be written fresh against
  MSX BIOS calls: `Screen`, `Width`, `Cls`, `Locate`, `Print`, `FastPrint`,
  `PrintChar`, `PrintNumber`, `WaitForKey`, `InputChar`, `IsDigit`,
  `StrCopy`, `StrCompare`, `OutPort`/`InPort` (trivial, `OUT`/`IN`), and
  `FCB`-based file open/read/close for `MSXARCH.INI` (BDOS F_OPEN/F_READ or
  direct FCB + BDOS calls 0Fh/14h).

## Phased plan

1. **Stage 1 — menu, input, INI parsing** (`stage1_menu.asm` — this
   worktree): `GetValidInput`, `showMenu`, `LoadRepositoryList` +
   `iniSetting`/`iniYes`, `SetFcbFilename`, `StartsWith`/`IsArchiveError`/
   `ShowArchiveError`, the small string/print BIOS shims listed above, and a
   `main` skeleton that loads the repo list and shows the menu (no network
   yet). Buildable and testable standalone in openMSX (menu navigation,
   INI parsing) before any MSXPi traffic is involved.
2. **Stage 2 — plain ROM load + progress bar**: `progressStart/Dot/End`,
   `loadrom`, the multi-block `RECVDATA` wrapper, `readRomHeader`,
   `buildSelection` (address table only — mapper handlers land in stage 3),
   wire into the stage-1 main loop against a real MSXPi server serving a
   plain ROM.
3. **Stage 3 — mapper-aware loader**: segment allocation
   (`detectMapperSegments`, `usableMapperSegments`, `allocateMapperSegments`,
   `takeSegment`/`freeMapperSegments`), `mapperCopyBank`, `patchWindow`,
   the resident handlers (`ascii16Page1Handler`/`Page2Handler`/`Page2Select`/
   `Page2Ram`/`Page2Cart`, `ascii8Dispatch`, `ascii8Handlers`) — these are
   already hand-written Z80 in the C source and port close to 1:1 — plus
   `relocateResidentHandlers16K/8K`, `prewarmKonami16PairCache`,
   `konamiInitialSetup`/`ascii8InitialSetup`, `loadMappedRom`. Test each
   mapper type (Konami, ASCII8, ASCII16) against real ROMs in openMSX.
4. **Stage 4 — integration**: `launchGame` (already inline asm, ports
   directly), full `main()` loop (page next/previous, rejection/reopen
   flow), final assembly into `msxarch.com`, side-by-side regression pass
   against the existing C build's `.dsk` test set.

Each stage is its own commit on `feature/msxarch-asm-port`, buildable and
independently testable before moving to the next.
