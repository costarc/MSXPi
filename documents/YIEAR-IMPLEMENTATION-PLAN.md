# Yie Ar Kung-Fu online: implementation plan

Written 2026-10-22, updated 2026-10-23 after the rebase on `feature/tcpip-games` (PLAYNET 3, design section 13), for the design in
`documents/YIEAR-DESIGN.md` (referred to as "design" below). The tests named T0-T13 are in `documents/YIEAR-TEST-PLAN.md`
(Salamander's plan continues at T20). As in `PLAYNET-DESIGN.md` section 7, each step ends with something that can be shown to work,
and a step is done only when its proof has passed. Salamander's package (`profiles/salamander/`, `run_salamander.sh`,
`HANDOVER-salamander.md`) is the model for the package, the rig and the debugging scripts.

Conventions for every step:
- Work on a branch of its own (this design is on `feature/yiear-netplay`, rebased on `feature/tcpip-games`), in a separate git
  worktree. Other sessions use the main checkout.
- The ROM is never committed. Tools and tests take it from `YIEAR_ROM` (the user's copy: `C:\Users\roniv\Dev\MSX\gameroms\kung-fu.rom`).
- Assembler: `C:\Users\roniv\Dev\bin\sjasmplus.exe`. Emulator: the Windows openMSX build with the MSXPi device
  (`C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe`). Keep throttle on for MSXPi runs.
- Long emulator runs go in the background and are checked at least every 5 minutes: they can hang. Before trusting a result, check
  that only one rig loop is running (a stopped loop's `sh` can survive).
- After any change to the loader, the engine or `patch_rom.py`: Soccer's and Salamander's `stub.bin` and GPFs stay byte-identical,
  and `software/target/playnet.com` and `software/target/games` are rebuilt (`build.py`, `build_games.py`).

## Overview

| Step | What | Depends on | Proof | State (2026-10-24) |
|---|---|---|---|---|
| 1 | Dynamic analysis and footprint (the cartridge in openMSX) | - | T1, T2: the "to verify" items of design section 3 answered, written into the design | Partly: footprint and hook sites measured (15 min, fights shortened by pokes). Open: a full unaided loop, self-writes with the image in RAM |
| 2 | PLAYNET 3 (or 4, design D10): GPFs up to 8 KB, staged in page 2 | - | T0 vectors, T10 Soccer and Salamander regression | **Dropped**: the GPF is 1830 bytes and fits the 3 KB buffer (design 14) |
| 3 | Yie Ar's rig (`run_yiear.sh`), and the package with Single only (no extension) | 1 | T3-T6 in Single: 3000 identical frames with lag and loss | Done on the rig (scripted, 3001 frames, lag and loss). Open: chat, link 2, TCP/IP scenarios, speed, sound |
| 4 | The extension and the play-mode screen | 2, 3 | T3 through the menu, T7 the screen | Done (state 9). Open: "PLAYER 1 SELECTS", the start choice, a real screenshot |
| 5 | Turn | 4 | T3 Turn, T8 | Done (4001 frames). "PLAYER n GAME OVER" done (6002 frames). Open: T8 against Single |
| 6 | Versus analysis: the five opponents' move tables | 1 | the tables, reviewed | Not done: one generic mapping replaced it for now (design 14) |
| 7 | Versus | 4, 6 | T3 Versus, T9 | First version (4501 frames, both ends seen). Redone 2026-10-24: P2 lives, jump, key-press rig (7002 frames). Open: attack mapping, balance |
| 8 | Publish: GPF, index, documents, chat and TCP/IP scenarios | 5, 7 | T0, T11, T10 | Partly (2026-10-24): `YIEAR.GPF`, `index.txt`, games README, `msxpirfh.bat`, `YIEAR-QUICKSTART.txt`, PROTOCOLS 6. Open: chat, mixed, TCP/IP scenarios |
| 9 | Offline two-player ROM (later phase) | 7 | T12 | Not started |
| 10 | Real hardware | 8 | T13 | Not started |

Steps 1 and 2 are independent and can run in parallel. Step 6 is analysis only, and can run as soon as step 1 is done.

---

## Step 1: dynamic analysis and footprint

Goal: replace every **to verify** in design section 3 with a measurement.

1. **Disassembly**: regenerate it with the Tcl script in the handover (`debug disasm`, the game running so page 1 is the cartridge). Keep it
   out of the repository, because it is derived from the ROM.
2. **Footprint** (T2): openMSX, cartridge in slot 1 (`-carta`), MSX1 machine (Canon V-20) and MSX2 (Canon V-25). Write watches on
   `8000h-BFFFh`, `C000h-DFFFh` and `E402h-F37Fh`, and the lowest stack address. Run 5 minutes of title and demo, then a scripted game
   (`keymatrixdown` on row 8) through the five opponents and a bonus stage. To get there in reasonable time, debug pokes may shorten the
   fights (opponent energy, or E054h), but **one** run must be a full unaided loop. Record the result in the design (section 3.4), and set
   `game_ram`.
3. **Variables** (for Turn and Versus): watch writes to E049h-E05Fh and E00Bh/E053h through two games (game over, then a game in which an
   opponent is beaten). List which bytes are per-player progress and which are global (the high score, timers). Confirm the state numbers
   and the sites of the life lost (41D7h path), the REST decrement, the new-game copy (42A3h), the opponent-beaten path (423Eh) and the
   game-over path (41F3h).
4. **Hook sites**: breakpoints on 4053h (once per frame?), 4583h (in which states?), 409Ch, 6B42h (every second frame in a fight?),
   7C5Ch (how many times per frame?).
5. **Self-writes**: with the image in RAM (step 3's rig, or a write watch on 4000h-7FFFh with the cartridge), confirm that the game
   never writes its own code area.
6. **Reads before writes** in C000h-DFFFh and E402h+ (design 3.6): if the game reads RAM INIT does not clear, the glue clears it at
   the start, as Salamander's `clrRam` does.
7. **Stack** with nested calls at the TICK site (design 3.6).

Files: `documents/YIEAR-DESIGN.md` (section 3.6 closed item by item, results in 3.4), and the Tcl scripts under
`software/Client/tests/soccernet/yiear_debug/` (no ROM data; output paths through an environment variable, not a session's
scratchpad). Reuse `salamander_debug/` where it fits: `wwatch.tcl` (write watch + stub compare), `hang.tcl`, `prof.tcl`, `busy.tcl`,
`ramdump.tcl` (per-frame RAM keyed by `nf`).

## Step 2: GPF staging (PLAYNET 3 or 4, design D10)

Design section 6. Settle D10 with the user first: it decides `PLAYNET_VERSION` and `min_playnet`.

1. `playnet.asm`: `GPFSTAGE EQU 8000h`, `GPFSTAGE_MAX EQU 2000h`, and a page-0 variable `gpfBase`. `getProfile` (in
   `playnet_gpf.asm`, page 1) and `tcpGpf` (`playnet_tcp.asm`) receive into GPFSTAGE; the MSXPi receive comes in 512-byte blocks and
   needs room for a whole block, so it must not run past A000h (`GPFSTAGE_MAX` minus a block, or stop the receive at the limit).
   `gpfCheck` works on the staged copy. Then, if the layout puts the ROM (or anything) over [8000h, 8000h + length), or the image host
   is `mapper-ram`, move the GPF down to `GPFBUF` if it fits 3 KB, else refuse it with a new message.
   Every `GPFBUF+n` reference (about 23, in `playnet.asm`, `playnet_gpf.asm`, `playnet_tcp.asm`) reads `gpfBase` instead: the header
   fields (title, roles), `assetAt`, `copyAssets`, `patchImage` and `install`. Page 0 has about 670 bytes left: keep the new code in
   page 1 where it only runs before the image is loaded.
2. Check in `mapper_host.asm` that nothing maps a segment into page 2 before `parseGpf` is done (else the staged copy is lost).
3. `PLAYNET_VERSION` per D10. The banner says it.
4. `patch_rom.py`: in the netplay rules, for a GPF longer than 3072 bytes, no layout destination may intersect the first GPF-length bytes
   from 8000h, and the host must be `plain`. Accept the new `min_playnet`.
5. `PLAYNET-PROTOCOLS.md`: 8.1 (a loader accepts at least 8 KB, and stages it in page 2), 7.2 (the rule), 17 (the vector), 16 (the
   release table). Update the memory map comment at the top of `playnet.asm`.
6. Tests: `test_gpf.py`, a synthetic 6 KB GPF that is accepted, and one whose layout overlaps the staging area, which is refused. Rebuild
   `software/target/playnet.com` with `build.py`, then T10 (Soccer and Salamander, both MSXPi and chat).

## Step 3: Yie Ar's rig, and Single without the extension

The engine does not change (design D11): no scripted tables, so Soccer's and Salamander's stubs stay byte-identical by construction.

1. **Package skeleton** `software/ROM-Patcher/profiles/yiear/`, modelled on Salamander's:
   - `src/yiear.inc` (game addresses), `src/glue.asm`: `rdLocal`, `tick` (`call PN_TICK; ld a,(PN_P1); jp 452Bh`), `key1`
     (`ld a,(PN_P1)`), a RAM clear if step 1 found one is needed, and `ORG C100h`.
   - `rebuild.py`: the patches of design 7 that need no extension (4019h, 4047h, 4062h, 4053h, 4583h), layout = the ROM only (output
     16384), `min_playnet` 2 (this GPF is under 3 KB and needs no staging yet). `--rom` (every expected byte), `--syms` (Tcl symbols for
     the rig: `nf`, `PN_TICK`, `PN_P1`, `PN_P2`, `desync`, `pnDelay`, the glue entries), `--test-gpf` (flags bit 0 = 0).
   - `README.md` in Salamander's form (input, output, game id and roles, layout, machine, status).
2. **Rig** `software/Client/tests/soccernet/run_yiear.sh` and `yiear_node.tcl`, from `run_salamander.sh` and `salamander_node.tcl`:
   two Canon V-25 + MSXPi (no memory mapper needed), MSX-DOS from the MSXPi, `PLAYNET yiear P1|P2`, two stock `msxpi-server.py`
   relaying over UDP on localhost. Inputs by Tcl key presses: P1 presses space on the title (and, from step 4, picks `MODE`), then both
   play seeded random keys (`SEED`). One trace line per frame (frame, E000h, E002h, E054h, a hash of E000h-E4FFh), `cmp_pair.py` at the
   end. Options as Salamander's: `ONLY`, `CHAT=1` (`/play bob yiear`), `EXITKEY=n`, `TCP=1`, `HYBRID=1`, `EXTRA_TCL`, `TMAX`/`NODETMO`, `RENDERER`,
   lag and loss arguments. Gate breakpoints on the stub being in place (`[peek 0xC100] == 2`, the ABI byte), and key per-frame dumps by
   `nf`.
3. Run T3-T6 in Single. **Proof**: 3000 identical frames through a real fight, with and without 50 ms lag, 20 ms jitter and 8 % loss; no
   desync; sound at the original tempo; 0 foreign writes to C100h-C6FFh after the trampoline's jump (K8); `CHAT=1 EXITKEY=600` returns
   both machines to `MCHAT` (each Pi logs "playnet restore", then "mchat start"); speed near the cartridge's in a fight (`prof.tcl`,
   `busy.tcl`).

At the end of step 3, Yie Ar Kung-Fu is already playable online in Single (one player plays, the other watches): the whole PLAYNET path
works for this game before any game logic is added.

## Step 4: the extension and the play-mode screen

1. `src/ext.asm`, `ORG A000h`, includes `yiear.inc` and the stub's exported symbols (`rebuild.py` assembles the stub first and writes
   `stub_syms.inc`). Entries: `dispatch`, `menu`, `menuState`. Extension RAM at E480h (mode at E480h, menu cursor, P1's edge byte).
2. Patches 409Ch (dispatch) and 45A7h (menu). `key1` returns 0 in state 9.
3. Strings in the game's encoding: a small Python helper in `rebuild.py` turns `"SELECT MODE"` into bytes, with the VRAM addresses picked
   on the title screen (read the name table address from VDP R2 in the emulator).
4. Layout: output 32768, the ROM at 0, asset `ext` at 6000h. `min_playnet` = the staging release (D10) as soon as the GPF is over
   3 KB. Until step 2 is merged, keep the GPF under 3 KB and `min_playnet` 2.
5. All three entries lead to Single for now. **Proof**: T7 (the screen on both machines, P2's input ignored), and T3 through the menu.

## Step 5: Turn

1. Fix the per-player block from step 1's measurement (design 5.2). Patches at the new-game site and the life-lost site, and "PLAYER n"
   before "PLAY START".
2. `tick` picks `PN_P1` or `PN_P2` from the current player (E481h).
3. "PLAYER n GAME OVER" when one player is out and the other goes on.
4. **Proof**: T3 in Turn (identical over 3000 frames with at least three player changes), and T8 (each player's block and score are
   right).

## Step 6: Versus analysis

For each of the five AI routines (6C90h, 6E79h, 7012h, 7320h, 7758h) and opponent 2's throw code (7162h, 718Dh):
1. Read the routine, and run the fight in openMSX with breakpoints on every shared action routine (design 3.5). Log the caller, A, C,
   E184h, E168h-E16Bh and the distance to Oolong (E161h against E181h).
2. Write the opponent's **move table**: every distinct action (walk, turn, each attack, jump, special), how it is started (routine and
   registers), its countdown, and the conditions the AI checks first (distance, Oolong's state).
3. Propose the joystick mapping for that opponent (design 5.3), with one rule for all five wherever possible.

Deliverable: a section "5.3a Move tables" in the design, for the user's review **before** step 7.

## Step 7: Versus

1. `vsAI` (design 5.3), with one table per opponent in the extension, P2's edge state at E4E0h, and a fallback to the original AI for an
   opponent whose table is not done (a build flag per opponent).
2. The bonus stage skip (4248h). The end of the match and "PLAYER n WINS" (4280h, 41F3h).
3. `tick` gives the game `PN_P1` in Versus (Oolong). `vsAI` reads `PN_P2`.
4. **Proof**: T3 in Versus (a scripted P2 that fights each opponent), T9 (every move in every table can be made, and both ends of the match
   happen), and a human play test of each opponent.

## Step 8: publish

1. `build_games.py` writes `software/target/games/YIEAR.GPF` and its `index.txt` line. Then `test_games_folder_is_current` in
   `test_gpf.py` passes.
2. `software/target/games/README.md` (the table row), `documents/YIEAR-QUICKSTART.txt` (as Soccer's: install, modes, controls, the ROM
   name and CRC), and `README.md`'s online games line if it lists games.
3. `PLAYNET-PROTOCOLS.md` section 6: replace the sketch with the real package (the patch table, the findings, the extension).
4. Rig scenarios on Yie Ar (`run_yiear.sh`): `CHAT=1` (`/play bob yiear`), `TCP=1`, and `TCP=1 HYBRID=1` (link 2: `PLAYNET /T /H`, as
   `run_native.sh` does for Soccer), each with `EXITKEY`. `TCP=1` waits for the rig's TCP/IP link to be fixed (design K9). Then T10 on Soccer and Salamander again.
5. `msxpirfh.bat` and the Windows installer already copy `target/games/*.GPF`. Check that the new file is included.

## Step 9: offline two-player ROM (later phase)

Design section 9: `profiles/yiear-2p/`, `rom-file`, `-DLOCAL2P`, the page-2 enable at INIT, joystick port 2. Proof: T12.

## Step 10: real hardware

A real Pi and a real MSX on the MSXPi path; GR8NET or ObsoNET on the TCP/IP path; one 50 Hz and one 60 Hz machine. Proof: T13.

---

## Estimates and order of risk

| Step | Size | Risk |
|---|---|---|
| 1 | 1 session | low |
| 2 | 1 session | medium (the loader's memory map, now shared with the mapper-ram loader; regressions on the TCP/IP path) |
| 3 | 1 session | low (Soccer's layout, Salamander's rig as the template) |
| 4 | 1 session | low |
| 5 | 1 session | medium (finding the whole per-player block) |
| 6 | 1-2 sessions | **high** (five AI routines) |
| 7 | 2 sessions | **high** (playability, balance) |
| 8 | 1 session | low |
| 9 | 1 session | medium (32 KB cartridge start) |

The first playable result (online Single) comes at step 3. The first one that is new to the players (Versus) comes at step 7.
