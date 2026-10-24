# Handover: Yie Ar Kung-Fu online (PLAYNET)

2026-10-22. Design session: no code yet.
2026-10-23. The branch was rebased (fast-forward: it had no commits of its own) onto `feature/tcpip-games` at `1f802adb` (PLAYNET 3,
with Salamander merged), and the four documents were updated to its protocols and method. Design section 13 lists what changed.
2026-10-23. Implementation session 1: Single, the play-mode screen, Turn and a first Versus (progress log at the end).
2026-10-24. Rebased onto `feature/tcpip-games` `36168d25` (23 newer commits, no conflicts; the old tip is kept as
`backup/yiear-netplay-before-rebase`). Published `YIEAR.GPF` and brought the documents up to date (design section 14: as built).
**When this work is complete, `feature/yiear-netplay` is merged back into `feature/tcpip-games`** (not into `master`).

| | |
|---|---|
| Branch / worktree | `feature/yiear-netplay`, on `feature/tcpip-games` `36168d25`, in `C:\Users\roniv\Dev\github\MSXPi-yiear` (the main checkout is shared with other sessions: do not switch branches there). The rebase is **local**: `origin/feature/yiear-netplay` still has the old commits, so the next push needs `--force-with-lease`. |
| Model to follow | Soccer (`profiles/soccer/`, `run_native.sh`, `SOCCER-QUICKSTART.txt`), and Salamander for the rig scripts (`run_salamander.sh`, `salamander_debug/`) |
| Design | `documents/YIEAR-DESIGN.md` |
| Plan | `documents/YIEAR-IMPLEMENTATION-PLAN.md` (steps 1-10) |
| Tests | `documents/YIEAR-TEST-PLAN.md` (T0-T13) |
| Protocol it builds on | `documents/PLAYNET-PROTOCOLS.md`, `documents/PLAYNET-DESIGN.md`, Soccer's package `software/ROM-Patcher/profiles/soccer/` |
| ROM | `C:\Users\roniv\Dev\MSX\gameroms\kung-fu.rom`, 16384 bytes, CRC-32 `8A12EC4F` (the dump PROTOCOLS 6 names). Never commit it, or anything derived from it, such as the disassembly. |

## State

(2026-10-24; the step-by-step state is the "State" column of the plan's overview)

- **Built**: Single, the play-mode screen (state 9), Turn and a first Versus. 12 patches, stub 804 bytes, extension 662 bytes, **GPF
  1830 bytes**: it fits `PLAYNET.COM`'s 3 KB buffer, so the planned loader change (plan step 2, design D6/D10) is dropped.
- **Published**: `software/target/games/YIEAR.GPF` (profile hash `73c47d8c`), its `index.txt` line, the games README row, the
  `msxpirfh.bat` line, `documents/YIEAR-QUICKSTART.txt`, and `PLAYNET-PROTOCOLS.md` section 6 (the package as built).
- **Tests**: `test_gpf.py` has `YieArPackageTests` (the profile, the GPF under 3 KB, the extension at A000h, the extension built with
  the published stub, and with `YIEAR_ROM` the real dump: only the 12 patches differ). All ROM-Patcher and server tests pass.
- **Rig results so far** (two emulators, MSXPi path, scripted input): Single 3001 identical frames with and without 50 ms lag, 20 ms
  jitter and 8 % loss; menu 3001; Turn 4001; Versus 4501, both match ends seen. No desync, no foreign writes into the stub.
- **Not run yet**: chat, link 2, mixed and TCP/IP scenarios; speed against the cartridge; sound tempo; desync detection; the exit key
  back to the chat; 50 Hz against 60 Hz; real hardware.

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

Built as proposed, still to be confirmed by the user: D5 (the extension at A000h), D7 (`KUNG-FU.ROM`), D8 (how a Versus match
ends). Settled by the build: D6 and D10 (no staging needed), D9 (the state is in the stub). Still open: D11 (the rig's inputs), whether
player 2 gets a REST of its own in Versus, and whether the mode should travel with the invitation (design section 12).

## Next step

(2026-10-24) What is pending, grouped as reviewed with the user:

1. ~~Housekeeping and publishing~~: done 2026-10-24 (above).
2. **Versus**: which of actions 4/5/6 is high, middle and low (the up/down mapping is a guess); opponent 2's automatic throw (4638h);
   the special states of opponents 3 and 4 (E1C0h, E1D0h); a jump for player 2; the per-opponent move tables (plan step 6); a human
   play test for balance.
3. **Turn and the mode screen**: "PLAYER n GAME OVER"; T8 (Turn's first life against a Single game); a real screenshot; "PLAYER 1
   SELECTS"; where the cursor starts (built: SINGLE; design: VERSUS online).
4. **Tests not run**: chat, link 2, mixed and TCP/IP scenarios (the rig's TCP/IP path is broken for every game, K9); speed against the
   cartridge; sound tempo; desync detection; the exit key back to the chat; 50 Hz against 60 Hz. Also D11: the rig still uses the
   engine's SCRIPTED tables, not Tcl keys.
5. **Later**: the offline two-player ROM (plan step 9) and real hardware (step 10).

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

## 2026-10-24, later: the user's answers and where this stopped

Decisions are in design section 15 (U1-U9, I1-I5). In short: P2 jumps, throws with button B, and has **lives of their own** in Versus
(the match ends when either player has none; D8 and the fifth-opponent rule are replaced); the menu cursor stays on SINGLE, no "PLAYER 1
SELECTS"; the rig moves to Tcl key presses; TCP/IP scenarios, 50/60 Hz and real hardware are out of scope. In Turn, "PLAYER n GAME OVER"
is shown when a player is out but **both machines keep running in lockstep and keep showing the other player's game** (the user's
instruction): no screen is frozen.

Not started in code: the key-press rig, the new Versus (move set, jump, throw, P2 lives, end of match), the Turn game-over text, and
the rig runs. Started: `yiear_debug/moves.tcl` (starts each opponent's actions 0-8 at the shared decision point and logs the pose
codes). Findings so far: the action tables are at 6E5Bh, 6FFEh, 7302h, 772Ch and 79A3h (one per opponent, entries point at short pose
scripts; poses 04/06/08/0A/0C are the attack poses, 7740h-7754h are shared); `screenshot` gives black images in these headless runs,
so read poses from RAM (E184h) or dump VRAM as `menushot.tcl` does. The first run reached opponent 1 only (action 8 needs checking).

## 2026-10-24, later still: the key-press rig and the new Versus (done)

- **Rig (U8)**: `yiear_node.tcl` plays by Tcl key presses chosen from the game's own state (title taps, the menu choice `MODE` = 0 Single,
  1 Turn, 2 Versus, random fights from `KEYSEED`); `run_yiear.sh` builds the release stub (`rebuild.py --keys --test-gpf`), so the
  published code is what runs and a desync ends the game. `versus_test.tcl` and `turn_deaths.tcl` force wins and deaths at the same
  ticks on both nodes.
- **Versus (U1, U2, I1-I3)**: player 2 has its own lives (`tLives2`, 3), the match ends when either side has none; the second button
  or UP alone is the jump attack; the fifth-opponent rule is gone. Design 15.1 has the details.
- **Turn (U5)**: "PLAYER n GAME OVER" while a player is out, and the other player's fight goes on.
- **Results** (two emulators on the MSXPi path, delay 6, 50 ms lag, 20 ms jitter, 8 % loss unless noted; frames compared are
  identical in every run, no desync, 0 foreign writes into the stub): Single 3002 frames (no lag); Versus 5002 (random play) and 7002
  (three forced wins: player 1 won with `tLives2` = 0; then forced deaths: player 2 won at REST = 0, three matches); Turn 6002 (out flags
  11, the game over and the restart through the title and the menu).
- **GPF** 1996 bytes, republished (`build_games.py`); ROM-Patcher tests pass.
- **Not verified**: the new strings ("PLAYER n GAME OVER", "P2 REST n") on a real screen (screenshots are black in these runs: dump
  VRAM as `menushot.tcl` does); which of the attacks 4/5/6 is high, middle or low (a human test); the balance; the chat, link 2, sound,
  speed and exit-key scenarios (I4); opponent 2's weapon only through the jump attack.

## 2026-10-24, last: the chat and link 2 in the rig (done), and a safer rig

- `run_yiear.sh` has `SCENARIO=chat` (alice invites bob with `/play bob yiear`, bob accepts, the chat starts the game) and
  `SCENARIO=tcp` (the chat over TCP/IP, MSR/INL, `MCHAT /1 /T`; with an MSXPi on each machine the game runs over the MSXPi: **link 2**).
  `EXITKEY=n` presses Ctrl+Shift+F5 on P2 and checks the return.
- **Chat** (Versus, `EXITKEY=900`): 901 identical frames, results 2 and 1, both servers saw `playnet restore` then `mchat start`;
  MCHAT shows "Game with bob ended (the opponent ended it)" and "Game with alice ended (you ended it)".
- **Link 2** (`SCENARIO=tcp`, same key): 900 identical frames, both back in `MCHAT /T` on the same IRC connection (2 connections,
  none dropped); MCHAT's line there says "(finished)" for both, not who ended it.
- **Other sessions' emulators and servers**: the old rig killed every openMSX running a `*node.tcl` script and every listener on
  8115/8116/6671, which Soccer's, Ping Pong's and Salamander's rigs use too. `run_yiear.sh` now has its own ports (servers 8137/8138, UDP
  5137/5138, IRC 6637; override with `P1PORT`, `P2PORT`, `UDP1`, `UDP2`, `IRC_PORT`), stops only an openMSX running `yiear_node.tcl`,
  stops a listener on its ports only if it is an `msxpi-server` or the IRC fixture, and otherwise stops with a message. It does not use
  `kill_nodes.sh`. The other rigs still use the shared ports and patterns.
- Still not run: sound tempo and speed against the cartridge, desync detection (`POKEF`), the mixed and `BOTH=1` TCP/IP game
  scenarios, the new strings on a real screen, a human play test.

## 2026-10-24, the sound tempo and speed check (done)

`yiear_debug/tempo.tcl` counts the sound driver (7C5Ch) and the frame counter (407Eh) per emulated second during 20 s of a fight (it
starts 4 s after the fight begins). The same script runs on the bare cartridge (`TEMPO_CART=1`, a tap on space on the title) and as
`EXTRA_TCL` of the rig. Canon V-25 (MSX2, 60 Hz), Single mode:

| | Sound driver calls | Frames |
|---|---|---|
| Cartridge | 59.95 / s | 59.95 / s |
| PLAYNET, no lag (delay 3) | 59.90 and 59.95 / s (the two nodes) | 59.70 and 59.75 / s |
| PLAYNET, 50 ms lag, 20 ms jitter, 8 % loss (delay 6) | 59.95 and 59.90 / s | 58.35 and 58.30 / s |

The pair stayed identical (3201 frames each run). So the music keeps the original's tempo whatever the network does (the engine ticks the
driver as many times as player 1's machine counted interrupts, PROTOCOLS 9.2), and the game itself loses 0.4 % of its speed with no lag
and 2.7 % with the worst network tried, because a frame waits for the opponent's input. Emulated seconds, throttle on (the MSXPi device
needs real time); another session's emulators were running on the host, which does not change emulated time. Not measured: the sound
by ear or a recording (`RECORD=file.wav`), and a real machine's cost per frame.
