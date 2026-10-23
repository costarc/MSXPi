# Handover: Yie Ar Kung-Fu online (PLAYNET)

2026-10-22. Design session: no code yet.
2026-10-23. The branch was rebased (fast-forward: it had no commits of its own) onto `feature/tcpip-games` at `1f802adb` (PLAYNET 3,
with Salamander merged), and the four documents were updated to its protocols and method. Design section 13 lists what changed.

| | |
|---|---|
| Branch / worktree | `feature/yiear-netplay`, now at `feature/tcpip-games` `1f802adb`, in `C:\Users\roniv\Dev\github\MSXPi-yiear` (the main checkout is shared with other sessions: do not switch branches there) |
| Model to follow | Salamander: `documents/SALAMANDER-DESIGN.md`, `documents/HANDOVER-salamander.md`, `profiles/salamander/`, `run_salamander.sh`, `salamander_debug/` |
| Design | `documents/YIEAR-DESIGN.md` |
| Plan | `documents/YIEAR-IMPLEMENTATION-PLAN.md` (steps 1-10) |
| Tests | `documents/YIEAR-TEST-PLAN.md` (T0-T13) |
| Protocol it builds on | `documents/PLAYNET-PROTOCOLS.md`, `documents/PLAYNET-DESIGN.md`, Soccer's package `software/ROM-Patcher/profiles/soccer/` |
| ROM | `C:\Users\roniv\Dev\MSX\gameroms\kung-fu.rom`, 16384 bytes, CRC-32 `8A12EC4F` (the dump PROTOCOLS 6 names). Never commit it, or anything derived from it, such as the disassembly. |

## State

- **Done**: analysis of the ROM (static, from an openMSX disassembly), the design, the implementation plan, the test plan. The user's
  decisions are recorded in design section 2.
- **Not done**: everything in the plan. Nothing has been verified dynamically in the emulator yet: every "to verify" in design section 3 is
  open.
- Nothing is committed. The four documents are new files in the worktree.

## What was found (the short version)

- The MSX game is **one-player only**: one input reader (4522h, joystick 1 or the keyboard), a title with "PUSH SPACE" and no player
  choice, and five opponents run by AI routines (dispatch at 6B42h, table 6B4Bh: 6C90h, 6E79h, 7012h, 7320h, 7758h).
- It is the **same Konami frame structure as Soccer**: H.KEYI installed at INIT (operand 4019h, handler 4043h), busy flag E006h bit 0,
  the sound driver 7C5Ch ticked per interrupt plus a catch-up tick, the frame counter E003h, and the game RAM E000h-E3FFh with SP = E400h.
- **Lockstep looks easy**: no `ld a,r`, no `JIFFY`, randomness from a rotating register in game RAM (6D2Ch) and the frame counter.
- **Versus is possible** because the opponents act through a few shared action routines (7429h, 744Ah-7458h, 73CDh, 74DAh/74E7h,
  74A2h). Only the choice among them is AI.
- **Corrections to the PROTOCOLS 6 sketch**:
  - E002h bit 6 = 1 means a human plays, and 0 means the demo, not the other way round.
  - `G_READ_LOCAL` must not be 4522h, because it writes E009h/E00Ah and applies the demo override; it must be a glue routine that only
    reads the hardware.
  - Also, `G_CHECK_LEN` 400h exceeds the 512 maximum: use E100h/200h.
- **A loader limit**: `PLAYNET.COM` holds a GPF in 3 KB (`GPFBUF` 2900h-34FFh in PLAYNET 3). Yie Ar's GPF with the extension will be
  4.5-5.5 KB, so the loader stages GPFs in page 2 (design section 6, plan step 2), in release 3 or 4 (design D10).

## What the rebase on feature/tcpip-games changed (2026-10-23)

- Release numbers: 2 = stub ABI 2 (K, S, timed resend), 3 = `mapper-ram`. The staging is no longer "release 2" (D10).
- For free: MSXNP 2, DELTA packets on the MSXPi link, link 2 (MCHAT /T through the MSXPi), the lost-interrupt count from `XCHG`.
- Loader map: GPF code in page 1, `GPFBUF` 2900h, page 0 about 670 bytes free; the trampoline's own stack under C100h.
- Method: a rig of the game's own driven by Tcl keys (D11), so the engine change `G_SCRIPT` is dropped and Soccer's stub cannot
  change; `rebuild.py --rom/--syms/--test-gpf`; stub write watches (K8); speed against the cartridge; `build_games.py`.
- The rig's TCP/IP path is broken for every game (HANDOVER-salamander 4b): Yie Ar's TCP/IP tests wait for it (K9).

## User decisions (2026-10-22)

1. Modes: **Single, Turn, Versus**, on a new play-mode screen.
2. Online, **only the inviter** (player 1) chooses the mode.
3. Versus: **the game's order** (player 2 plays the opponents in turn, the game's REST and energy rules, no bonus stages).
4. An **offline two-player ROM** with the same extension, in a later phase.

Still open for the user (design section 12): D5-D11 (where the extension and its RAM live, the staging rule, `KUNG-FU.ROM`, how a
Versus match ends, which PLAYNET release takes the staging, the rig's key-driven inputs), whether player 2 gets a REST of its own in
Versus, and whether the mode should travel with the invitation.

## Next step

Plan **step 1** (dynamic analysis and footprint) and **step 2** (GPF staging) are independent. Step 1 first is recommended,
because its measurements can move the extension (D5, D9) and fix the Turn block. Then step 3 gives online Single play with the
existing machinery (`min_playnet` 2, no staging needed yet), before any game logic is written.

## How the disassembly was made

The game must be running, so that page 1 is the cartridge. `debug disasm` returns `{mnemonic} b1 b2 ...`, with the bytes as hex strings.
Output in the session's scratchpad; keep it out of the repository.

```tcl
# openmsx.exe -machine Canon_V-20 -carta kung-fu.rom -script dis.tcl
set ::out "C:/path/to/scratch"
proc dumpDis {} {
  set f [open "$::out/dis.txt" w]
  set a 0x4000
  while {$a < 0x8000} {
    set r [debug disasm $a]
    puts $f [format "%04X  %-12s %s" $a [join [lrange $r 1 end] " "] [string trim [lindex $r 0]]]
    incr a [expr {[llength $r] - 1}]
  }
  close $f
  exit
}
set throttle off
after time 8 dumpDis
```

Text in the ROM uses the game's own encoding (A-Z = 21h-3Ah, digits = 10h-19h, space = 00h). Its strings are at 5567h-55DDh: "HI SCORE",
"STAGE", "SCORE", "REST", "PLAY START", "PUSH SPACE", "KONAMI", "GAME OVER", "VIDEO CARTRIDGE". A screenshot taken during that 8-second
run was black, so look at the title in a real-time run before planning the screen layout.

## Pitfalls to remember (from the Soccer work)

- Measure the RAM footprint through a **full** game, not the title and demo only (it has been wrong before).
- Tcl in the rig: never name a proc `step` or `arm`. `debug set_condition` runs on every instruction. Breakpoints are address-only, so
  gate them. Keep throttle on with the MSXPi device.
- The 8-bit frame counters wrap every 256 frames: "first frame" logic needs its own state.
- Regenerate the music packages' ROMs after touching `patch_rom.py`, and check that they are bit-identical (T10.2).
- After any loader or `patch_rom.py` change, Soccer's and Salamander's `stub.bin` and GPFs must stay byte-identical (T0.9), or their
  profile hashes change for every player.

## Pitfalls to remember (from the Salamander work, HANDOVER-salamander 6)

- Address-only breakpoints also fire in the disk ROM at boot: gate them on the stub being in place (`[peek 0xC100] == 2`).
- Key per-frame dumps by the engine's `nf`, not a script counter, or the two nodes' dumps misalign.
- MSX-DOS's stack can sit inside a page-3 area the package uses: watch C100h-C6FFh from the trampoline's jump to the first frame.
- `EXTBIO` handlers and MSX-DOS calls do not keep IX.
- The Pi sends GPFs in 512-byte blocks: a receive buffer needs room for a whole block.
- Killing a rig by command-line match also kills the shell that runs it; check for two loops before trusting a result.
