# Handover: 1942 online, turn based (PLAYNET, image host mapper-ram, ASCII8)

2026-10-27. Status: **package builds and loads, the game starts on both machines, but it does not yet run in lockstep.**

| | |
|---|---|
| Worktree / branch | `C:\Users\roniv\Dev\github\MSXPi-1942`, `feature/1942-netplay`, from `feature/link2` (`1a9f24db`). Not pushed. Other worktrees exist for the same repo: never switch branches in the main checkout. |
| Design | `documents/1942-DESIGN.md` (analysis, patches, memory map) |
| Package | `software/ROM-Patcher/profiles/1942/` (`src/glue.asm`, `rebuild.py`, generated `profile.json`, `assets/stub.bin`, README) |
| ROM | `C:\Users\roniv\Dev\MSX\gameroms\1942.ROM`, CRC-32 `C99E5601`, 128 KB ASCII8. Never commit it or anything derived from it. |
| Tools | sjasmplus `C:\Users\roniv\Dev\bin\sjasmplus.exe`; openMSX `C:\Users\roniv\Dev\MSX\MSXPi\openmsx-MSXPi_v1.6.1\openmsx.exe`; my analysis scratch (Z80 disassembler `z80dis.py`, probes, debug Tcl) is in `work-1942/`, git-excluded (`info/exclude`), game-derived output: keep it out of git. |
| Commits | `407c7178` package, `97cc2034` PLAYNET accepts ASCII8 + rig + design + tests, `7b5ccfe4` initGame return address. **Uncommitted:** `glue.asm`/`profile.json`/`stub.bin` with `rdLocal` restoring ED10h (stub now 1510 of 1512 bytes). Commit them. |

## 1. Idea

1942's own 2 PLAYERS mode alternates turns. Both machines run the whole game; the input fed to it is the active player's: `EFA0h` == 80h means player 2, else player 1. The game reads all input in `6D09h` (names: `6DAAh`); each call becomes `PN_TICK` + the net input (`inAct`, `inP1` for the title menu at 4468h, `inAny` after game over at 4507h, `keyAct` for name entry). 34 patches (see design 3.1). No sound work (no interrupt driver); `ld a,r` x10 replaced by xorshift.

## 2. Memory (why it is tight)

The game owns C000h-DD5Fh (stage map) and EA00h-F37Fh, writes E000h-E016h. Free: DD60h-DFFFh, E017h-E9FFh. Transport DD60h (512), stub E018h-E5FFh (max 1512), pair map E600h-E9FFh. MSXPi link only (TCP/IP transports must sit below the TPA top). Pinned pairs: page 1 (0,1); page 2 twelve pairs (see `rebuild.py`); `MK_P1_MAX` must be 2 (loader wants a spare entry).

## 3. Done and verified

- `rebuild.py --rom` : every expected byte found, no bank-register write left, GPF 2201 bytes. `python -m unittest tests.test_gpf.Game1942Tests` passes (with `P1942_ROM`).
- PLAYNET `mapper_host.asm` accepts mapper type 2. **PLAYNET prints check numbers in hex** (33 = 51).
- Rig `software/Client/tests/soccernet/run_1942.sh` + `p1942_node.tcl` (clone of Salamander's). Run:
  `ALLOW_ROM=1 P1942_ROM=C:/Users/roniv/Dev/MSX/gameroms/1942.ROM WORK=/c/tmp/p1942work EXT2=ram512k TMAX=500 NODETMO=1500 sh run_1942.sh 900` from `software/Client/tests/soccernet`. `ALLOW_ROM=1` because the installed MSXPi ROM speaks Ethernet protocol 3 and the server 2 (irrelevant on the MSXPi path). Boot + load takes ~6 min wall before the game starts. **`ONLY=P1` never starts the game** (it waits for the peer). `EXTRA_TCL` runs for both nodes: write per-role files with `$::env(ROLEARG)`. Old trace files persist between runs: wait on `run*.log` ("compared"), not on the trace.
- Both nodes: GPF accepted, ROM loaded, `initGame` runs, game reaches `4039h` and the title menu (`4066h`), `inP1` ticks are called.

## 4. Open problem

The game does not run in lockstep:
1. Run with the `rdLocal` fix: no frames compared; the screen dump at t=60 shows PC `F66C`, SP `2EE8` (crash, garbage).
2. **Suspect: the game's stack runs into the stub.** At the title menu SP is `E046h` (and `E042h` at the inP1 site, `E040h` inside inP1), i.e. inside the stub (E018h+); the original cartridge never writes E000h-E7FFh below E016h, so its stack stays at F000h-F380h. At an interrupt in a P1 run SP was `EFFEh` with engine return addresses (`E028h`, `E03Ah`) on the stack. Unknown yet: why the game's SP is ~4.9 KB below F380h 14 s after `4039h` (it sets SP=F380h at 4039h and only `ld sp` there). Candidates: a runaway/unbalanced stack in the init the game does between 4039h and 4066h (`5CC0h`, `9B30h`, ...) caused by a patch (check the `ld a,r` call replacements, `MK_W2/W3` register/flag preservation, `initGame`), or the 14 s init itself (the original reaches its first frame ~2 s after start).
   - Last attempt in flight: `work-1942/dbg_stk.tcl` (dump of the stack at the 3rd `inP1`, `C:/tmp/p1942work/dbg_stk_<role>.txt`). Not read yet; `dbg_sp.tcl` shows the first low-SP event (SP=EFFE at `0038h`).
   - Next: single-step/bisect SP between `4039h`, `403Ch`, `403Fh`, `4042h`, `4066h` (breakpoints printing SP), and compare with the cartridge (`-romtype ASCII8`, `probe6.tcl` pattern; the cartridge run needs more than 100 s to reach 4066h).
2. Earlier desync reports were partly false: the engine checksums `ED00h-EEFFh` inside `PN_TICK` while the local readers had left their scratch in `ED10h`. Fixed in `rdLocal` (save/restore), unverified.
3. After a clean start still to check: lockstep over ~3000 frames (the rig's `cmp_pair.py`), a 2 PLAYERS game with a turn swap (`EFA0h` 81h to 80h; verify the bit meaning, the design infers it from 4295h/4487h), 512 KB vs 2 MB nodes, the exit key back to MCHAT, name entry, pause, and the init time (14 s).

## 5. Not done

TCP/IP transports (no room), real hardware, publishing `1942.GPF` (`build_games.py`; `test_games_folder_is_current` will fail until then), MCHAT game list / `target/games/README.md` entries, `test_profiles.py` misfit expectations, `FORMAT.md` mention of ascii8, SDCC/other clients unaffected.

## 6. Pitfalls

- A matching `ld a,r` list: ten in bank 1 only (two `ED 5F` in banks 13/15 are data).
- `zero` in glue clobbers DE/BC/HL; keep return addresses on the stack.
- Watch long runs (check every few minutes); kill leftovers with `kill_nodes.sh`; the script kills listeners on ports 8115/8116.
- Other sessions' rigs share ports and the installed `msxpibios.rom`: check they are idle.
