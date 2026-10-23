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

## Progress, 2026-10-23 (implementation session 1)

- **Step 1 (partly)**: `software/Client/tests/soccernet/yiear_debug/footprint.tcl` ran the cartridge 15 emulated minutes (Canon V-25)
  through all five opponents, four levels and the bonus stages (fights shortened by poking E00Bh every 25 s, REST kept at 9: **no
  full unaided loop yet**). Written outside E000h-E3FFh: only E400h-E401h (53C6h). Nothing in 8000h-DFFFh, E402h-F37Fh or the ROM
  area. Stack: lowest SP sampled E3B8h. Hook sites per frame: 4053h, 409Ch once; 4047h, 4062h, 7C5Ch once per interrupt; 6B42h
  every second fight frame; 4583h only on title/demo/game-over frames. Still open: per-player block (Turn), self-writes with the
  image in RAM, reads-before-writes.
- **Step 3 (Single, SCRIPTED rig)**: `profiles/yiear/` (glue, `rebuild.py --rom/--syms/--test-gpf`, 5 patches, `min_playnet` 2,
  stub 743 bytes, GPF 1018) and `run_yiear.sh` + `yiear_node.tcl` (from Soccer's `run_native.sh`/`native_node.tcl`, engine
  SCRIPTED tables: bit 4 = trigger starts the game from the title). Results: 3001 identical frames (scenes 0,1,3,4,5), no desync,
  0 foreign writes to C100h-C5FFh, with no lag (delay 3) and with 50 ms lag, 20 ms jitter, 8 % loss (delay 6).
- Not done in step 3: chat/TCP/link-2 scenarios in the rig, speed against the cartridge, sound check, the profile published
  (`build_games.py`, `YIEAR.GPF`), real-hardware. The ROM is read through `YIEAR_ROM` only.
- Steps 2 and 4-10 are untouched.

- **Step 4 (menu, Single only)**: `src/ext.asm` (219 bytes at A000h; state 9 "SELECT MODE": SINGLE / TURN / VERSUS, blinking choice,
  player 1's input only), patches 409Ch (dispatch) and 45ADh (title start -> state 9), layout output 32768 with asset `ext` at 6000h,
  GPF 1271 bytes, `min_playnet` 2. Rig: 3001 identical frames, scenes 0,1,3,4,5,9 (state 9 lasts frames 84-115 in the scripted
  run). VRAM dump (`yiear_debug/menushot.tcl`) shows the menu below the logo, "PUSH SPACE KEY" erased. All three entries play
  Single; the mode is stored at E480h. Not yet seen on a real screenshot, nor with "PLAYER 1 SELECTS".

- **Step 5 (Turn)**: per-player block = E049h-E05Fh (23 bytes: score, E050 REST, E051 stage, E052 extra-life threshold, E054 opponent,
  E056 level, E057-E059 counters); the hi-score E043h-E045h is global (write watch, `vars.tcl` idea: new-game clear 42A3h, 4324/432A
  score, 4367 hi-score). Hooks: 4132h `newGame`, 41DCh `lifeLost` (state 6 repeats it each frame at game over: it is idempotent).
  Mode, current player, out flags and the two saved blocks live in the stub (`tMode`, `tCur`, `tOut`, `tBlk`: loader-initialised),
  not in E480h (uninitialised RAM differs between machines and `tickSite` reads `tCur`). "PLAYER n" above PLAY START and on row 2 in
  fights. Rig: `yiear_debug/turn_deaths.tcl` kills Oolong every 300 ticks; 4001 identical frames, REST/stage per player right, the turn
  alternates, both out -> game over -> title -> menu -> new game. Not done: "PLAYER n GAME OVER" text, T8 against a Single game.

- **Steps 6-7 (Versus)**: all five AI routines (6C90h, 6E79h, 7012h, 7320h, 7758h) run the current action while E16Bh is not zero
  (their own animation scripts, 54D5h) and jump to the one shared decision point 7335h when it is. Skipping the AI altogether leaves
  the opponent frozen (the executors are inside the routines), so the single patch is at 7338h (`ld a,(E181h)` -> `jp vsDecide`,
  after 5476h has set the facing). Player 2 (`PN_P2`): trigger = attack, +up 7458h (action 5), +down 7450h (6), else 7454h (4);
  left/right = 74E7h (C = 1 / 0) every 8 frames (a step is 8 pixels; Oolong walks 1 px/frame); nothing = stand (E184h = 2 or 3,
  5522h). 4248h `bonus` (no bonus stage), 4284h `vsWin` (fifth opponent beaten: `tWin` = 1, REST = 0, state 6: the game's own
  game-over path), `lifeLost` sets `tWin` = 2 when REST is 0; "PLAYER n WINS" over state 7. Rig: `yiear_debug/versus_test.tcl`,
  4501 identical frames; the opponent walks and attacks on P2's scripted input, both match ends seen (win=1, win=2).
  **Open**: which of actions 4/5/6 is high/middle/low (the up/down mapping is a guess), opponent 2's automatic throw (4638h) and
  opponents 3/4 special states (E1C0h, E1D0h) in Versus, play balance (a human test), a P2 jump, the move table per opponent.
