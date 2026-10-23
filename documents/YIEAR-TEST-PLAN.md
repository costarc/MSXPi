# Yie Ar Kung-Fu online: test plan

Written 2026-10-22, updated 2026-10-23 for PLAYNET 3 (`feature/tcpip-games`), for `documents/YIEAR-DESIGN.md` and
`documents/YIEAR-IMPLEMENTATION-PLAN.md`. T0-T13 are Yie Ar's; Salamander's tests continue at T20 (SALAMANDER-DESIGN 13). The steps that run each test are in
the plan's overview. A package is accepted under the same rule as every PLAYNET game (PROTOCOLS 4.9): the scripted pair stays identical
over at least 3000 frames, through a full fight, with 50 ms lag, 20 ms jitter and 8 % loss, and no desync is reported. For Yie Ar that
rule applies **to each of the three modes**.

## Set-up

| | |
|---|---|
| ROM | `YIEAR_ROM=C:\Users\roniv\Dev\MSX\gameroms\kung-fu.rom` (CRC-32 `8A12EC4F`). Never committed. |
| Soccer, Salamander (regression) | `SOCCER_ROM=C:\Users\roniv\Dev\MSX\gameroms\SOCCER.ROM`, `SALAMANDER_ROM=C:\Users\roniv\Dev\MSX\gameroms\SALAMAND.ROM` |
| Emulator | the Windows openMSX build with the MSXPi device (`OPENMSX=`), throttle on. `RENDERER=SDLGL-PP` for screenshots. |
| Assembler | `SJASMPLUS=C:/Users/roniv/Dev/bin/sjasmplus.exe` |
| Rig | `software/Client/tests/soccernet/run_yiear.sh` + `yiear_node.tcl` (implementation plan, step 3), driven by Tcl key presses (design D11). Results in `$WORK/np/{P1,P2}.trace`, `.screen`; `cmp_pair.py` compares them at the end. Debug scripts: `salamander_debug/` and `yiear_debug/`, passed with `EXTRA_TCL`. |
| Ports | the rig's own (8115/8116, 5101/5102). Check that port 5000 is free and that no other session's openMSX is using the rig's ports. |
| Disks | on the MSXPi path, A:/B: are the server's images: tests that write to them run with `MSXPI_HOME` pointing at a scratch copy |

Each test's result is written into `documents/HANDOVER-yiear.md` with the date and the command used.

---

## T0. Package and GPF (no emulator)

Command: `YIEAR_ROM=... python -m unittest tests.test_gpf` (in `software/ROM-Patcher`), plus `python build_games.py --check`.

| # | Check | Expected |
|---|---|---|
| T0.1 | `patch_rom.py --profile profiles/yiear/profile.json --gpf YIEAR.GPF` with the ROM | accepted. Every expected byte matches the dump. |
| T0.2 | The same with another ROM (Soccer's, or one changed byte) | refused: size or CRC, then the expected bytes |
| T0.3 | GPF size | at most 8192 bytes, asserted by `rebuild.py` |
| T0.4 | Netplay rules | stub C100h-C4FFh and transport C500h-C6FFh in page 3, apart from `game_ram` and from each other. The extension destination (A000h) does not overlap the staged GPF. |
| T0.5 | Rebuild twice | identical `stub.bin`, `ext.bin`, `profile.json`, GPF: the profile hash is stable |
| T0.6 | The image from the GPF equals the image from the package | byte for byte, as Soccer's equivalence test |
| T0.7 | Staging vectors (step 2) | a 6 KB GPF with a free page 2 is accepted; a 6 KB GPF whose layout writes 8000h is refused; a 4 KB GPF for a 32 KB image is refused; a 4 KB `mapper-ram` GPF is refused; Soccer's and Salamander's GPFs are accepted |
| T0.8 | `min_playnet` | `YIEAR.GPF` says the staging release (design D10: 3 or 4). An older build refuses it with "This game needs a newer PLAYNET", a PLAYNET 3 built before the change with "too big". |
| T0.9 | Soccer and Salamander unchanged | `SOCCER.GPF`, `SALAMAND.GPF` and both `stub.bin` are byte-identical after the loader and `patch_rom.py` changes |
| T0.10 | `test_games_folder_is_current` | `software/target/games` is what the packages compile to (`build_games.py`) |
| T0.11 | `rebuild.py --rom` | every expected byte matches the dump, patches do not overlap; `--syms` writes the symbols the rig needs |

## T1. Hook sites (step 1, cartridge)

openMSX, `-carta`, breakpoints that count hits per frame.

| # | Check | Expected |
|---|---|---|
| T1.1 | 4053h (the reader call) | once per frame, while the busy flag is clear |
| T1.2 | 7C5Ch | once per interrupt, plus one when a frame overran |
| T1.3 | 4583h | every frame while E002h bit 6 = 0 (title and demo), except in state 3, and from state 7 (4213h). Never while a human plays. |
| T1.4 | 6B42h | every second frame during a fight, never in a bonus stage |
| T1.5 | Writes to 4000h-7FFFh, with the image in RAM | none during 10 minutes covering every state |

## T2. RAM footprint

Write watches. The BIOS work area (F380h and up) and VRAM do not count.

| # | Run | Expected |
|---|---|---|
| T2.1 | Cartridge: 5 minutes of title and demo, then a full unaided loop of the five opponents and the bonus stages | writes only inside E000h-E401h, plus what step 1 finds. This is `game_ram`. |
| T2.2 | The same, watching 8000h-BFFFh and E402h-E4FFh | **no writes** (else the extension and its RAM move: design D5, D9) |
| T2.3 | Under PLAYNET (the rig), each mode | no write into C100h-C6FFh except by the stub and the transport (`foreign_writes=0`), and the stub equal to `stub.bin` at the first `PN_TICK` (`wwatch.tcl`, design K8); no write into 8000h-9FFFh, none into A000h-BFFFh except by the extension; the lowest stack write is inside `game_ram` |
| T2.4 | Reads before writes in C000h-DFFFh and E402h+ (cartridge) | none, or the glue clears that RAM at the start (design 3.6) |

## T3. Lockstep pair (each mode)

Tcl key presses in `yiear_node.tcl` against the release GPF: P1 presses space on the title, picks `MODE` on the mode screen, then both
nodes play seeded random keys (`SEED`). P2 plays as player 2 (Turn, Versus), or presses keys that must be ignored (Single).

```
MODE=single YIEAR_ROM=... sh run_yiear.sh 3001
MODE=single YIEAR_ROM=... sh run_yiear.sh 3001 50 8
```
The same with `MODE=turn` and `MODE=versus`, and with `SEED=1..8` for coverage.

| # | Check | Expected |
|---|---|---|
| T3.1 | Frame traces of H and C (`cmp_pair.py`) | **identical**, every frame |
| T3.2 | Desync | `desync=0` on both |
| T3.3 | Coverage (from the traces' E000h state and E054h) | title, the mode screen, at least two opponents' fights. Turn: at least three player changes. Versus: at least two opponents. |
| T3.4 | With lag, jitter and loss | identical. The server counters show dropped packets and no bad checksums. |
| T3.5 | Forced delay `FORCE_DELAY=2` and `=7` (the ABI 2 maximum) | identical |
| T3.6 | Speed (`prof.tcl`, `busy.tcl`), the same key script on the rig and on the cartridge | frames a second in a fight within 10 % of the cartridge's; time in `XCHG` and `rdLocal` recorded in the handover |
| T3.7 | DELTA on the MSXPi link | the servers' `deltas_in`/`deltas_out` counters grow; a full packet is 22 bytes, a DELTA 6 |

## T4. Sound

| # | Check | Expected |
|---|---|---|
| T4.1 | 7C5Ch calls a second on node H | 60 on a 60 Hz machine (50 on 50 Hz), as the cartridge (T1.2) |
| T4.2 | `RECORD=yiear.wav` on the title jingle and a fight, against the cartridge | same tempo and pitch by ear. The jingle's length is within 2 % of the cartridge's. |
| T4.3 | A network stall (`ONLY=H` for a few seconds) | the music pauses, then goes on. It does not race ahead. |

## T5. Desync detection

| # | Check | Expected |
|---|---|---|
| T5.1 | Test build (`rebuild.py --test-gpf`), `POKEF=800` (a byte of E100h-E2FFh changed on P1) | both nodes record the desync within 32 frames, at the same frame |
| T5.2 | Release build, the same poke | both machines end the game with result 4 and show the frame |

## T6. End of a game

| # | Check | Expected |
|---|---|---|
| T6.1 | `CHAT=1 EXITKEY=600` (Ctrl+Shift+F5 on P2) | both machines back in `MCHAT` with "Game with X ended (you ended it / the opponent ended it)"; each Pi logged "playnet restore", then "mchat start" |
| T6.2 | `EXITF=300` (node P2 killed) | P1 ends with "connection lost" about 15 s later, and is back at the prompt or in `MCHAT` |
| T6.3 | Ctrl+Shift+F5 on the mode screen and during a Turn change | same as T6.1 (no state where the exit key is ignored) |

## T7. The play-mode screen

| # | Check | Expected |
|---|---|---|
| T7.1 | Screenshots of both nodes on the screen | identical: "SELECT MODE", the three modes, "PLAYER 1 SELECTS", the blinking choice |
| T7.2 | Seat 1's up, down and trigger | ignored |
| T7.3 | Seat 0's up, down and trigger | the cursor moves (it wraps or stops at the ends, as the design says) and each mode can be chosen |
| T7.4 | After a game over | back to the title, and the next start shows the screen again |
| T7.5 | The demo | still runs from the title after the usual wait. A key during the demo returns to the title, not to the mode screen. |
| T7.6 | Offline ROM (T12) | the cursor starts on SINGLE and "PLAYER 1 SELECTS" is not shown |

## T8. Turn

| # | Check | Expected |
|---|---|---|
| T8.1 | At each change of player (a breakpoint in `lifeLost`) | the saved block equals the live block at the moment the life is lost. The loaded block is the other player's last saved one. |
| T8.2 | Scores | each player's score only grows during their own turns. The high score is shared. |
| T8.3 | One player out | "PLAYER n GAME OVER". The other player continues alone. The game ends when both are out. |
| T8.4 | Inputs | during player 2's turns, seat 0's input has no effect on Oolong, and the other way round |
| T8.5 | Equivalence | player 1's first life in Turn is frame-identical to the first life of a Single game with the same inputs |

## T9. Versus

| # | Check | Expected |
|---|---|---|
| T9.1 | For each opponent and each move table entry: a scripted P2 input that makes it, with breakpoints on the action routines | the routine is called with the table's parameters |
| T9.2 | Countdowns | the shortest gap between two attacks by P2 equals the AI's (E129h, E132h, E169h are honoured) |
| T9.3 | P2 idle | the opponent stands still and never attacks by itself |
| T9.4 | Bonus stages | never entered in Versus. Still entered in Single and Turn. |
| T9.5 | P1 beats the fifth opponent | "PLAYER 1 WINS", then the title |
| T9.6 | P1 runs out of REST | "PLAYER 2 WINS", then the title |
| T9.7 | Opponent 2's throw | P2 can throw, and the projectile hits and misses as the AI's does |
| T9.8 | Human play test, each opponent, both sides | a checklist in the handover: responsiveness, fairness, no stuck states, the animations right |

## T10. Regression

| # | Check | Expected |
|---|---|---|
| T10.1 | Soccer with the new loader: `run_native.sh 0 0 1501`, `50 8 3001 20`, `SCENARIO=chat EXITKEY=700`, `SCENARIO=mixed` (and `HYBRID=1`), `BOTH=1`, `SCENARIO=tcp EXITKEY=...` | the results recorded in PLAYNET-DESIGN 7 (identical frames, both back in the chat). The TCP/IP scenarios wait for the rig fix (design K9). |
| T10.1a | Salamander with the new loader: `run_salamander.sh 1500` (`EXT2=ram512k`), `CHAT=1 EXITKEY=...` | identical, scenes 0-6, both back in MCHAT (HANDOVER-salamander 4c) |
| T10.2 | ROM-Patcher | `python -m unittest discover tests`: the four music packages still build bit-identical ROMs |
| T10.3 | Server | `test_games.py`, `test_netplay.py`, `test_games_local.py`, `test_update_games.py` pass. `msxpi_games` lists both games from `games/`. |
| T10.4 | `update.sh` (`test_update_games.py`) | fetches `YIEAR.GPF` from the index, and leaves unlisted files alone |

## T11. Paths and machines

| # | Check | Expected |
|---|---|---|
| T11.1 | `CHAT=1` with `/games` and `/play bob yiear` | the game is listed with its title, and starts on both machines |
| T11.2 | An invitation between two different `YIEAR.GPF` | declined with `profile`, with the line telling one player to update |
| T11.3 | `TCP=1` (P2 over the TCP/IP UNAPI, K = 2) | T3.1 and T3.2 hold; the music keeps its tempo (lost interrupts returned by `XCHG`) |
| T11.3a | `TCP=1 HYBRID=1` (link 2: `PLAYNET /T /H`) | T3.1 and T3.2 hold |
| T11.4 | `TCP=1 CHAT=1 EXITKEY=...` | as for Soccer: back in `MCHAT /T` on the same IRC connection |
| T11.5 | `BOOT=nextor` (MSX-DOS 2) | T3 and T6 hold. The DOS area is saved from the right start (PROTOCOLS 14). |
| T11.6 | A 64 KB MSX without a mapper on the MSXPi path (the rig's Canon V-25, an MSX2; and a Canon V-20 for MSX1) | starts and returns |
| T11.7 | One node on a 50 Hz machine and one on a 60 Hz machine | identical traces, and the game runs at 50 frames a second on both |
| T11.8 | No ROM, wrong dump, ROM under another name | result 8 with the message that names `KUNG-FU.ROM` and the CRC |

## T12. Offline two-player ROM (later phase)

| # | Check | Expected |
|---|---|---|
| T12.1 | The 32 KB ROM in openMSX as a cartridge, MSX1 (Canon V-20) and MSX2 (Canon V-25) | boots, with page 2 enabled at INIT |
| T12.2 | Two joysticks (openMSX `plug joyporta/b`, or key mappings) | each mode works as in T7-T9 |
| T12.3 | Sound | the original's (no lockstep patches) |
| T12.4 | The ROM file through msxarch / EXECROM | runs |

## T13. Real hardware

| # | Check | Expected |
|---|---|---|
| T13.1 | Two real MSX with MSXPi, over the Internet | a match in each mode, back to the chat |
| T13.2 | A real MSX with GR8NET or ObsoNET against an MSXPi | the same |
| T13.3 | 50 Hz against 60 Hz | the same |
| T13.4 | Per-frame cost | the C9 transaction time on the MSXPi path (an oscilloscope or the frame-overrun count) leaves the game at full speed |
| T13.5 | A real MSX with GR8NET and Nextor, MCHAT /T, against an MSXPi (the user's set-up, HANDOVER-salamander 4b) | a match in each mode, back to the chat |
