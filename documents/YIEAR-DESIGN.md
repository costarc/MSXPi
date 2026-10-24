# Yie Ar Kung-Fu online (PLAYNET): analysis and design

Written 2026-10-22, updated 2026-10-23 for `feature/tcpip-games` (the branch this one is now rebased on). It brings Konami's Yie Ar
Kung-Fu (MSX, RC-725) to PLAYNET, the online two-player system specified in `documents/PLAYNET-PROTOCOLS.md`, first proven with
Konami's Soccer (`documents/SOCCERNET-NETPLAY.md`, `documents/PLAYNET-DESIGN.md`) and then with Salamander's co-op
(`documents/SALAMANDER-DESIGN.md`, `documents/HANDOVER-salamander.md`). **Updated 2026-10-24: the package is built and published
(`YIEAR.GPF`); section 14 says where the implementation differs from the design below, and wins where they disagree.** The plan is
`documents/YIEAR-IMPLEMENTATION-PLAN.md`, the tests are in `documents/YIEAR-TEST-PLAN.md`, and the state of the work is in
`documents/HANDOVER-yiear.md`.

What `feature/tcpip-games` changed under this design (section 13 has the details):

- **PLAYNET 3** is the current loader: stub ABI 2 (send interval K, service latency S, timed resend; release 2) and image host
  `mapper-ram` (release 3). The 8 KB GPFs this game needs come in the next release (D10), not "release 2".
- **MSXNP 2**, **DELTA packets** on the MSXPi link and **link 2** (MCHAT /T with the game's packets through the MSXPi) work for any
  game. Yie Ar gets them for free.
- **The loader's memory map** moved (GPF at 2900h, the GPF code runs in page 1), and the trampoline has its own stack under C100h.
- **The method**: a rig of the game's own (`run_<game>.sh`, `<game>_node.tcl`) driven by Tcl key presses, `rebuild.py --rom` and
  `--syms`, write watches on the stub, speed against the cartridge, and `build_games.py` to publish. That replaces the scripted-table
  engine change this design had planned.

| | |
|---|---|
| Dump | 16384 bytes, CRC-32 `8A12EC4F`, SHA-256 `644c78c7d20bb30802888b513b384cf0ce4f9d8b6fd490f30e6211ac92274848` (the dump PROTOCOLS section 6 names; the user's copy is `C:\Users\roniv\Dev\MSX\gameroms\kung-fu.rom`) |
| Game id / GPF | `yiear` / `YIEAR.GPF` |
| ROM file name | `KUNG-FU.ROM` (`source.file`; what the dump is usually called; decision D7) |
| Roles | `P1` (seat 0, the inviter), `P2` (seat 1) |
| Input width | 1 byte |
| Modes | Single, Turn, Versus, chosen on a new play-mode screen (decisions D1-D3) |
| Package | `software/ROM-Patcher/profiles/yiear/` (glue, extension, rebuild script, profile) |
| Rig | `software/Client/tests/soccernet/run_yiear.sh` + `yiear_node.tcl`, scripts in `yiear_debug/` |
| State | Built: Single, the play-mode screen, Turn and a first Versus, identical on the two-emulator rig; `YIEAR.GPF` published (1830 bytes). Open work: `documents/HANDOVER-yiear.md`. |

---

## 1. Summary

The MSX Yie Ar Kung-Fu is a **one-player game**: one input reader (joystick port 1 or the keyboard), no 1P/2P choice, and five opponents
run by AI routines. PROTOCOLS section 6 already sketched a package from a static scan and left this question open. The scan done for this
design (an openMSX disassembly of the dump, section 3) settles it. The title screen has only "PLAY START" and "PUSH SPACE", and no player
text exists in the ROM.

So the package does more than network the game. It adds **two-player modes** to it:

- **Single**: the original game. On line, the second player watches.
- **Turn**: arcade-style alternating play. Each player has their own score, REST and stage, and the players change at each lost life.
- **Versus**: player 2 controls the CPU opponent of each stage. Player 2's joystick replaces the AI's decisions and goes through the game's
  own action routines, so every opponent keeps its moves, timing and animations.

A new **play-mode screen** after "PUSH SPACE" offers the three modes. In an online game only player 1 (the inviter) chooses.

Everything PLAYNET already does is reused unchanged: the chat and invitations, MSXNP, the transports, the lockstep engine, the return to
the chat. Two things are new:

1. **An extension asset** in page 2 (A000h-BFFFh). A 16 KB cartridge leaves page 2 free in the RAM image, and the package format can
   already place an asset there through `layout`. The menu, Turn and Versus are Z80 code in that asset. Only the small entries that the
   lockstep engine must reach stay in the page-3 stub.
2. ~~One PLAYNET loader change: a GPF of up to 8 KB.~~ **Not needed** (section 14): the built GPF is 1830 bytes and fits
   `PLAYNET.COM`'s 3 KB buffer, so the package runs on today's PLAYNET (`min_playnet` 2). Section 6 is kept for a future game that
   needs more.

Unlike Salamander, this is a **plain 16 KB ROM**: no bank engine, no mapper segments, and it runs on a 64 KB MSX without a mapper.

A later phase reuses the same extension for an **offline two-player ROM**: a ROM-Patcher `rom-file` package in which the second player
uses joystick port 2 (D4).

---

## 2. Decisions

| # | Question | Decision (user, 2026-10-22) |
|---|---|---|
| D1 | Which two-player modes | All three: **Single, Turn, Versus**, on a new play-mode screen |
| D2 | Who chooses the mode online | **The inviter only** (seat 0, player 1). Player 2 sees the same screen. |
| D3 | How Versus is organised | **Game order**: player 1 is Oolong, player 2 plays the opponents in the game's order, the game's REST and energy rules decide, and the bonus stages are skipped |
| D4 | An offline two-player ROM | **Yes, in a later phase**, with the same extension and joystick port 2 |

Decided in this design, open for review (section 12):

| # | Point | Proposal |
|---|---|---|
| D5 | Where the extension lives | A000h-BFFFh (output offset 6000h), at most 8 KB |
| D6 | Large GPF support | **Not needed for this game (section 14).** Every GPF goes to 8000h first. A GPF whose image covers 8000h (Soccer's 32 KB layout) is then moved down to `GPFBUF` (2900h) and must still be 3 KB or less (Soccer 1080 bytes, Salamander 2868). |
| D7 | ROM file name | `KUNG-FU.ROM` |
| D8 | How a Versus match ends | Player 1 wins by beating the fifth opponent. Player 2 wins when player 1 has no REST left. Both end on "PLAYER n WINS", then the title. |
| D9 | Extension RAM | E480h-E4FFh, in page 3, so the offline ROM can use the same addresses (to be confirmed free, T2). **As built**: measured free; only E481h-E482h (the menu's cursor and edge byte) are used; the mode, the current player and Turn's blocks are in the stub (section 14). |
| D10 | PLAYNET release for the 8 KB GPFs | **Not needed for this game (section 14).** Fold into release 3** while `feature/tcpip-games` is not on `master` (no PLAYNET 3 is in players' hands): `min_playnet` 3. If release 3 ships first, it becomes release 4 and `min_playnet` 4. A PLAYNET 3 built before the change refuses the GPF cleanly ("too big"). This also answers SALAMANDER-DESIGN 12.2, point 3. |
| D11 | How the rig drives the game | **Tcl key presses** in `yiear_node.tcl` (`keymatrixdown`/`keymatrixup`, seeded random play after a fixed menu sequence), as `salamander_node.tcl` does, against the release stub and GPF. No scripted tables in the engine (the old `G_SCRIPT` plan is dropped), so the engine and Soccer's stub do not change. `--test-gpf` is kept only for the desync tests (flags bit 0 = 0). **As built, not followed**: the rig runs the `--test-gpf` build with the engine's SCRIPTED tables (section 14); open for the user. |

---

## 3. What the ROM does

Taken from an openMSX disassembly (`debug disasm`, the script is in the handover) and from reading the code. **To verify** means that the
emulator has not confirmed it yet. The implementation plan's step 1 does that the way Salamander's analysis did (SALAMANDER-DESIGN 3):
the cartridge in openMSX (`-carta`, Canon V-25 and Canon V-20), Tcl watchpoints over 5-10 minute runs that record every writing PC,
breakpoints that count hits per frame, and the results written back here (section 3.6 lists what is open).

### 3.1 Start, frame and interrupt

| | |
|---|---|
| Header | `AB`, INIT = 4010h. Page 2 is not used: the image is 16 KB at 4000h. |
| INIT 4010h | `di; im 1`. H.KEYI = `JP 4043h` (`ld a,C3h; ld (FD9Ah),a; ld hl,4043h; ld (FD9Bh),hl`: **operand at 4019h**). SP = E400h. Clears E000h-E3FFh, sets up the VDP (44DEh), then `ei; jr $` at 4041h. |
| Handler 4043h | `call RDVDP; di; call 7C5Ch` (sound) / busy flag **E006h bit 0** / `ei; call 4522h` (input: **TICK site, the call at 4053h**) / `call 407Bh` (frame) / clear busy / `call RDVDP; or a; di; call m,7C5Ch` (catch-up sound tick, operand at 4063h) / `ei; ret`. The same Konami structure as Soccer. |
| Frame counter | E003h (`inc (hl)` at 407Eh); E005h = E003h AND 7. 42E9h also decrements E003h (a pause). |
| Game state | E000h = state, E001h = sub-state, dispatched at 409Ch through `call 4071h` (a table follows the call): 0 40B1h start, 1 40F4h title, 2 40FCh demo, 3 411Fh "PLAY START" and new game (42A3h), 4 414Dh stage set-up, 5 41BEh fight, 6 41D7h life lost / game over, 7 4213h game-over screen, 8 423Eh opponent beaten (next opponent, bonus stage, level) |
| Attract flag | E002h bit 6 = 1 while a human plays (set to 40h at 45A7h). While it is 0, the reader takes its input from the demo table at 55DEh (4564h). PROTOCOLS section 6 has this the wrong way round. |

### 3.2 Inputs

| | |
|---|---|
| Reader 4522h | `call 4510h` (joystick port 1: `WRTPSG` R15 = 8Fh, `RDPSG` R14, complemented, AND 3Fh) OR `call 453Fh` (keyboard: `SNSMAT` rows 7 and 8, folded into the same bits). Then the demo override (452Bh), then the edge logic: E00Ah = held, E009h = newly pressed. Returns A = held. |
| Input byte | bit 0 up, 1 down, 2 left, 3 right, 4 trigger A / space, 5 trigger B / row 7 bit 6. The fight code uses bits 0-4 (`and 1Fh` at 4F57h). |
| Second reader 4583h | Used by the title, the demo and the game-over screen. It reads the hardware again (4583h-458Ah: `call 4510h; ld d,a; call 453Fh; or d`) with its own edge state at E040h/E041h. On the title (E000h = 1), a new trigger or space press starts the game (45A3h-45B1h). In any other attract state, a key returns to the title. |
| Readers of the result | Only the player's code (E00Ah at 4DBCh, 4E5Eh, 4E7Ch, 4F54h). The opponents never read the input. |
| Ctrl+Shift+F5 | Not used: row 6 is never read, and F5 is row 7 bit 1, which the reader masks out. The PLAYNET exit key works (R10). |

### 3.3 Determinism

| Source | Finding |
|---|---|
| R register | No `ld a,r` |
| JIFFY / INTCNT | Not read |
| Randomness | 6D2Ch rotates an 80-bit register at E135h-E13Eh by two bits and returns (E135h) AND 3. The opponents also use the frame counter (for example 6CAEh: `ld a,(E003h); and 3Eh`). Both are game RAM, so they are deterministic under lockstep. |
| Sound | The driver at 7C5Ch is ticked per interrupt plus once when a frame overran: the same pattern as Soccer. Both calls are patched to `PN_IRQ`, and the engine ticks the driver T times a frame (PROTOCOLS 9.2). |
| VDP status | Read only for the interrupt and the catch-up tick. Sprite collisions are not tested (**to verify**: watch the status bits in the two-node test). |
| Writes into the ROM area | None found statically (two hits are inside text and font data). **To verify** with the RAM-against-ROM diff (PROTOCOLS 4.2). |

### 3.4 RAM

| Range | Use |
|---|---|
| E000h-E3FFh | Cleared at INIT. Game variables and the object tables. The stack grows down from E400h. |
| E400h-E401h | Written at 53C5h (`ld (E400h),bc`) |
| C000h-DFFFh, E402h-F37Fh | No static reference. **To verify** with write watches over a full loop of the five opponents, as for Soccer (PROTOCOLS 4.6). |
| 8000h-BFFFh | Not used by a 16 KB cartridge. **To verify** the same way. Under PLAYNET it is RAM, and it holds the extension. |

Game variables the modes need (**all to verify** with watches during a full game):

| Address | Meaning (from the code) |
|---|---|
| E049h-E04Bh | Score, BCD (added at 4319h) |
| E050h | REST (lives): 3 at a new game (42A3h), +1 for each opponent beaten (423Eh) |
| E051h | Stage number, BCD |
| E053h | 1 while the player is alive in the fight (set at 418Fh). 0 = the player lost (41D0h). |
| E00Bh | Non-zero = the opponent is beaten (41C1h) |
| E054h | Opponent index 0-4. After 4 comes 0, and the level goes up. |
| E056h | Level, 0-3: the opponents' timing tables are indexed by it |
| E057h, E059h | Round counters |
| E058h | 1 = bonus stage. It is set after opponents 1 and 4 (4248h-4255h). |
| E150h-E16Fh | Oolong (E160h y, E161h x, E162h facing, E165h attack) |
| E168h-E16Bh, E129h, E132h-E133h, E180h-E185h | The opponent: action, timers, animation code (E184h), facing (E185h) |

### 3.5 The opponents' AI

- `6B05h` runs every second frame during a fight. It first serves two countdowns: E129h (keep walking) and E132h (keep doing an attack).
  Then it dispatches on E054h through the table at **6B4Bh**: **6C90h, 6E79h, 7012h, 7320h, 7758h**, one routine per opponent. The bonus
  stage goes to 79B7h instead.
- Each routine is a small state machine. It uses 6D2Ch for its random choices and gives its decisions to **shared action routines**:
  - 7429h: start action A, with its duration taken from a per-level table into E16Bh;
  - 744Ah, 7450h, 7454h, 7458h: set E129h, or start action 4, 5 or 6;
  - 73CDh: E132h = 9;
  - 74DAh / 74E7h: walk one step; C = direction, E184h = the walking animation;
  - 74A2h: turn round.
- Opponent 2 also throws: 463Ah calls 7162h/718Dh while E184h is 2, 3, 10h or 11h.

This is what makes Versus possible without rewriting the game. **The opponents already act through a small vocabulary of routines, and
only the decision of which routine to call is AI.** Versus replaces the decision and keeps the vocabulary (section 5.3).

### 3.6 Still to verify (implementation step 1)

- The RAM footprint through a full unaided loop of the five opponents and the bonus stages, every writing PC recorded (3.4). This
  sets `game_ram`, and confirms that 8000h-BFFFh, C100h-C6FFh and E402h-E4FFh are free (D5, D9).
- The stack: the lowest address with `PN_TICK`, the sound ticks and an extension call nested at the TICK site (budget: down from
  E400h, above the variables). The game starts on MSX-DOS's stack (the trampoline only uses its own, under C100h, until the jump),
  and INIT writes H.KEYI before it sets SP = E400h: check that nothing is pushed in between, or that it lands in `game_ram`
  (D500h-D5FFh, as for Soccer).
- The hook sites per frame (T1): 4053h, 7C5Ch, 4583h, 409Ch, 6B42h.
- The per-player block for Turn (5.2) and the life-lost, new-game, opponent-beaten and game-over sites (7).
- No write into 4000h-7FFFh (the RAM-against-ROM diff, PROTOCOLS 4.2) and no use of the VDP status collision bits.
- Whether the game reads C000h-DFFFh or E402h+ before writing it. INIT clears only E000h-E3FFh; anything else read first must be
  cleared by the glue at the start (Salamander's `clrRam`), or the two machines start from different RAM.
- A checksum region that changes every frame in a fight and holds no machine-dependent byte (E100h, 200h bytes proposed).

---

## 4. Architecture

```
                     page 1 (4000h-7FFFh)          page 2 (8000h-BFFFh)                 page 3
 MSXPi/TCP/IP  ->    the game (RAM image,          8000h-9FFFh: the GPF while            C000h trampoline + its stack (PLAYNET)
 (PLAYNET)           patched)                      loading (section 6)                   C100h stub: engine + glue
                       | patched calls  ------->   A000h-BFFFh: EXTENSION               C500h transport (512)
                       |                           menu, Turn, Versus, strings           E000h-E401h game RAM, stack
                       +--- TICK (4053h) ---------------------------------------------> stub: PN_TICK, input select
                                                                                         E480h-E4FFh extension RAM
```

### 4.1 Rules for the pieces

| Piece | Lives | Contains | Rule |
|---|---|---|---|
| Trampoline | C000h-C0FFh, only until the game starts | PLAYNET's start-up code and its own stack (`TRAMP_SP` = C100h) | PLAYNET's. It is why nothing of the package may start below C100h. |
| Stub (engine + glue) | C100h, at most 1024 bytes | PLAYNET's engine (stub ABI 2), and the glue entries `rdLocal`, `tick` and `key1` | Everything `PN_TICK` and the interrupt reach. Never calls the extension. Soccer's ABI 2 stub is 746 bytes, so this one should be about 800. |
| Transport | C500h, 512 bytes | PLAYNET's: MSXPi (432 bytes, with DELTA), UNAPI, or link 2 (`transport_hybrid`, at most 384) | Unchanged. In MSX-DOS's page 3 below its TPA top, as the TCP/IP path requires (`tcpFootprint`): C500h-C6FFh is, as for Soccer. |
| Extension | A000h-BFFFh, at most 8 KB | the state-9 menu, Turn, Versus, strings, tables | Runs only from the game's frame logic, after `TICK` (from the state dispatch and the AI dispatch). Never from `PN_TICK`, `XIRQ` or the busy path of the handler. On the TCP/IP path (links 1 and 2) the transport maps the network engine into page 2 inside `XCHG`, then puts back the game's pages 1 and 2 from `tSegs` (the TPA's segments for a plain game). That is safe only because no extension code is on the stack then. |
| Extension RAM | E480h-E4FFh | mode, the current player, Turn's two saved blocks, Versus' P2 edge state | Inside `game_ram`. Initialised by the extension, because INIT only clears E000h-E3FFh. |

The extension is assembled after the stub and imports `PN_P1`/`PN_P2` from the stub's symbols. In the offline build (phase 7) the same
symbols name two RAM bytes that the local glue fills from joystick ports 1 and 2. The extension never knows which build it is in.

### 4.2 Package layout

```
software/ROM-Patcher/profiles/yiear/
  profile.json         written by rebuild.py
  rebuild.py           assembles the stub, then the extension, then writes profile.json. --rom checks every expected byte
                       against the dump, --syms writes the stub's and extension's symbols for the rig's Tcl, --test-gpf
                       builds the desync-test variant (flags bit 0 = 0)
  README.md
  src/glue.asm         the stub's glue (page 3)
  src/ext.asm          the extension (page 2)
  src/yiear.inc        game addresses and the extension RAM map, shared by both
  src/playnet_engine.asm   copied by rebuild.py
  assets/stub.bin, assets/ext.bin
```

`layout`, with an output size of 32768:

| Source | Offset | Size | Destination | Result |
|---|---|---|---|---|
| input | 0 | 16384 | 0 | the ROM at 4000h-7FFFh |
| asset `ext` | 0 | its length | 6000h | the extension at A000h |

Output offsets 4000h-5FFFh (8000h-9FFFh) stay filled with 00h. The loader stages the GPF there (section 6).

---

## 5. The three modes

### 5.1 The play-mode screen

- The title's start (45A7h: `E002h = 40h; E000h/E001h = 3/0`) is patched to enter a **new state 9** instead.
- The dispatcher's `call 4071h` at 409Ch is patched to the extension's `dispatch`. That runs state 9 itself and passes states 0-8 to 4071h
  unchanged, with the table that follows the call.
- State 9 clears the play area and prints, with the game's own print routine (449Eh) and font, so no new glyphs are needed:

  ```
        SELECT MODE
          SINGLE
          TURN
          VERSUS
      PLAYER 1 SELECTS          (online only)
  ```
  The current choice blinks, the way "PLAY START" blinks (449Eh draws it, 44B5h erases it). Up and down move the cursor, and trigger or
  space confirms. The cursor starts on VERSUS online and on SINGLE offline. Confirming stores the mode at E480h and then does what 45A7h did.
- Strings use the game's encoding: a VRAM address, the characters (A-Z = 21h-3Ah, digits 10h-19h, space 00h), FEh plus an address to go
  on elsewhere, and FFh to end.
- **Input**: the menu reads only `PN_P1` (decision D2), directly and with its own edge byte. It does not use E009h/E00Ah: the title is an
  attract state (E002h bit 6 = 0), so the reader's demo override fills those. The second reader 4583h is patched to return `PN_P1` too
  (3.2). While in state 9 it returns 0, because the reader's "any key goes back to the title" branch would otherwise leave the menu.
- **Dispatch**: at 409Ch A = the state, and the return address is the table at 409Fh. For state 9, `dispatch` drops that address and runs
  the menu, which returns where a state routine would. For any other state it jumps to 4071h with the stack untouched.

### 5.2 Turn

- **Per-player block**: the progress variables of 3.4 (E049h-E05Fh, **to verify** which bytes belong to a player and which do not: the high
  score does not). The extension keeps two copies at E4A0h and E4C0h.
- **New game** (the end of 42A3h): copy the fresh block into both copies, current player = 1.
- **A life is lost** (state 6, 41D7h): save the block to the current player's copy. Then, if the other player still has REST, switch
  players, load their copy and go to state 4 (stage set-up) instead of the normal path. If neither has REST, go to the normal game over.
- **A player's last life**: "PLAYER n GAME OVER" is shown, and the other player continues alone until they are out too.
- **The player's input**: `tick` gives the game `PN_P1` while player 1 is current and `PN_P2` while player 2 is.
- **Display**: the "PLAY START" blink (4129h, string 558Ah) is preceded by "PLAYER 1" or "PLAYER 2". The score on the screen is the
  current player's, because the game reads E049h.

### 5.3 Versus

- **Oolong** is player 1 (`PN_P1`). **The opponent** is player 2 (`PN_P2`).
- **The AI dispatch** at 6B42h (`ld a,(E054h); ld hl,6B4Bh; call 4071h`, 9 bytes) is patched to `jp vsAI`. In the other modes `vsAI` does
  those three instructions itself (pushing 6B4Bh for 4071h's `pop hl`), so the original AI runs.
- **`vsAI`** keeps player 2's held and new bits (E4E0h-E4E1h), because the game's edge logic only serves Oolong. It then looks up the current
  opponent's **move table**: input pattern -> (action routine, parameter). The table entries are the calls that opponent's AI makes, found
  by the Versus analysis (implementation plan, step 6).

  | Player 2's input | Becomes |
  |---|---|
  | nothing | stand (the AI's idle path) |
  | left / right | walk (74E7h, C from the wanted direction and E185h), or turn (74A2h) |
  | trigger + up / none / down | that opponent's high / middle / low attack (7429h, 744Ah-7458h, 73CDh with its codes) |
  | trigger B | the special (opponent 2's throw; others: the attack the AI uses least, to be chosen per opponent) |

- **Fairness**: the AI's own countdowns (E129h, E132h, E169h) are kept, and 6B05h still serves them before the dispatch. So player 2 can
  never act faster than the AI could, and the animations stay the game's.
- **Bonus stages** are skipped: at 4248h, in Versus, E054h is not compared, so E058h is never set.
- **End of the match** (D8): when E054h would go from 4 back to 0 (4280h), player 1 wins. When state 6 finds no REST (41F3h), player 2
  wins. Both show "PLAYER n WINS" (new strings), then the game-over and title states.
- **Level**: E056h stays 0 for the whole match, because it only increases after the fifth opponent.

### 5.4 Single

The original game. `tick` always gives the game `PN_P1`, and the AI dispatch runs unchanged. Online, player 2's machine shows the same
game, and player 2 can still end it with Ctrl+Shift+F5.

---

## 6. PLAYNET change: GPFs up to 8 KB (release 3 or 4, D10)

**Problem.** `PLAYNET.COM` (release 3) receives the GPF into `GPFBUF` (2900h-34FFh, `GPFMAX` 0C00h = 3 KB, plus one 512-byte block of
slack that runs into the bounce buffer), from the Pi (`playnet profile`) or from the disk (`tcpGpf`). PROTOCOLS 8.1 allows 16 KB, and
`msxpi_games.py` and `patch_rom.py` allow 16 KB too, so only the MSX loader is short. This package's GPF is estimated at 4.5-5.5 KB:
a 128-byte header, the stub (about 800 bytes), the extension (3-4 KB) and about 25 patches.

Where the code is now (release 3, after the Salamander merge): `getProfile`, `gpfCheck` and `parseGpf` are in `playnet_gpf.asm`,
assembled for **page 1** (4000h, `DISP`) and copied there at the start; a plain game's image lands over them later, after they have
run. `assetAt`, `loadRom`, `copyAssets`, `patchImage` and `install` are in page 0 and read the GPF at `GPFBUF` (about 23 references in
`playnet.asm`, `playnet_gpf.asm`, `playnet_tcp.asm`). Page 0 has about 670 bytes left (program to 2265h, CRC tables at 2500h).

**Change (D6).**
1. Receive every GPF into **8000h-9FFFh** (at most 8 KB, plus the block of slack: the receive must stop at A000h, or the block
   size must divide 8 KB). Page 2 is free until the ROM is loaded, for every game: the page-1 loader code is at 4000h-48xxh, and a
   `mapper-ram` game maps no segment into page 2 before `parseGpf` (to check in `mapper_host.asm`). Then check it there (magic,
   format, length, hash, `min_playnet`), as now.
2. If the image covers the staged GPF (an output of 32 KB with the ROM there, like Soccer; or any `mapper-ram` game, whose banks are
   built through page 2), copy the GPF down to `GPFBUF` before parsing. It must then be 3 KB or less, or the loader refuses it ("the
   package is too big for this game's layout"). Soccer (1080 bytes) and Salamander (2868) still fit.
3. Otherwise, parse it where it is. Every `GPFBUF` reference becomes a read of `gpfBase` (a page-0 variable). **Rule** (loader and
   `patch_rom.py`): no layout destination may overlap the staged GPF, `[8000h, 8000h + GPF length)`. The image's 8000h-9FFFh is left as
   fill. The extension at A000h is copied by `copyAssets` after the ROM, and `install` reads the stub from the staged GPF after the
   connect phase, as now.
4. The TCP/IP path is the same. Page 2 is the TPA segment whenever the loader touches the GPF: `PLAYNET.OVL` is only mapped there
   inside netcore calls, and the transports put the game's pages back from `tSegs`.
5. `PLAYNET_VERSION` stays 3 (D10, folded) or becomes 4, and the package says the same in `min_playnet`. Older loaders refuse it with
   "This game needs a newer PLAYNET" (or, a PLAYNET 3 built before the change, with "too big"). Soccer keeps `min_playnet: 2`,
   Salamander 3.
6. `saveDos`/`svLow` need no change: the stub and transport are below every TPA top (C806h is the smallest), and the extension RAM is
   in `game_ram` (E000h+), which is saved as Soccer's is.

PROTOCOLS 8.1 gets "a loader must accept at least 8 KB", and 7.2 gets the staging rule. A conformance vector for a staged GPF is added (PROTOCOLS 17).

Rejected alternatives:
- **Make `GPFMAX` 4 KB** by shrinking the bounce buffer: page 0 has no room (CRC tables at 2500h, the bounce buffer at 3500h with
  2.75 KB chunks, the transport relocated to 3D00h, and the overlay passes through 2500h-3FFFh). It would also not hold the Versus
  tables.
- **Put the GPF buffer in page 1** next to the page-1 loader code: the ROM is loaded into page 1 before `install` reads the stub
  from the GPF.
- **Ship the extension as a second file**: the profile hash would no longer cover all the code, and players would have two files to keep
  in step.
- **Put everything in the stub**: page 3 below the smallest TPA top (C806h) is already taken. The trampoline, the stub (1 KB) and the
  transport (512 bytes) leave about 260 bytes.

---

## 7. Patch table (draft; offsets = CPU - 4000h)

`S.x` = a stub entry, `X.x` = an extension entry, `T` = C500h (the transport vector).

| CPU | Offset | Expected | Replacement | Reason |
|---|---|---|---|---|
| 4019h | 0019h | `43 40` | `T+6` | H.KEYI -> `XIRQ`, which jumps to 4043h |
| 4047h | 0047h | `CD 5C 7C` | `CD S.PN_IRQ` | sound tick per interrupt -> count it |
| 4062h | 0062h | `FC 5C 7C` | `FC S.PN_IRQ` | catch-up sound tick -> count it |
| 4053h | 0053h | `CD 22 45` | `CD S.tick` | **TICK site**: `PN_TICK`, pick the byte for Oolong (5.2-5.4), then `jp 452Bh` (the reader's demo override and edge logic) |
| 4583h | 0583h | `CD 10 45 57 CD 3F 45 B2` | `CD S.key1 00 00 00 00 00` | the second reader: `PN_P1`, or 0 in state 9 |
| 409Ch | 009Ch | `CD 71 40` | `CD X.dispatch` | state 9, the play-mode screen |
| 45A7h | 05A7h | `3E 40 32 02 E0` | `C3 X.menu 00 00` | the title's start goes to state 9 |
| 6B42h | 2B42h | `3A 54 E0 21 4B 6B CD 71 40` | `C3 X.vsAI 00 00 00 00 00 00` | the opponent's decision |
| 4248h | 0248h | `3A 54 E0` | `CD X.bonus` | no bonus stage in Versus |
| 41D7h-ish | | | `CD X.lifeLost` | Turn: change players. The exact site is fixed in step 5. |
| 42A3h-ish | | | `CD X.newGame` | Turn: copy the fresh block. The exact site is fixed in step 5. |
| 4280h, 41F3h | | | `CD X.vsEnd` | Versus: the winner. The exact sites are fixed in step 7. |

Not needed, unlike Soccer: no `ld a,r` patches, no anti-copy patches (to confirm by the diff), no RAM clear to shorten.

`netplay` section:

```json
"netplay": {
  "abi": "msxpi-netplay-v1", "game_id": "yiear", "title": "Yie Ar Kung-Fu", "roles": ["P1", "P2"],
  "transport": "lockstep", "input_bytes": 1,
  "image": {"host": "plain", "base": 16384},
  "stub": {"asset": "stub", "load": 49408, "max": 1024},
  "transport_area": {"address": 50432, "size": 512},
  "game_ram": [[54528, 54783], [57344, 58623]],
  "irq_handler": 16451, "start": "header-init", "min_playnet": 3
}
```
`min_playnet` is 3 if D10 folds the staging into release 3, else 4. The stub and transport places are Soccer's (C100h/1024,
C500h/512), so everything PLAYNET checks for Soccer's layout (the trampoline under C100h, `tcpFootprint`, `saveDos`) holds unchanged.
`game_ram` = D500h-D5FFh (the loader's stack at INIT, as measured for Soccer; **to measure again**) and E000h-E4FFh (game RAM, stack and
extension RAM; **to measure**). `irq_handler` = 4043h.

Glue symbols: `G_INPUT_BYTES = 1`, `G_READ_LOCAL = rdLocal` (the first half of 4522h: `call 4510h; push af; call 453Fh; pop hl; or h`.
It is **not** 4522h itself, as the PROTOCOLS sketch had it, because 4522h also writes E009h/E00Ah and applies the demo override. Running
it on the local machine only would make the two machines' RAM differ), `G_SOUND_TICK = 7C5Ch`, `G_CHECK_ADDR = E100h`, `G_CHECK_LEN = 200h`
(the objects; at most 512, so the sketch's E000h/400h is not allowed). These are the stub ABI 2 engine's only glue symbols
(`playnet_engine.asm` header), the same set Soccer and Salamander define.

`rebuild.py --rom KUNG-FU.ROM` checks every expected byte against the dump, that the patches do not overlap, and that no jump in the
ROM lands inside a patched span (run on the disassembly, as for Salamander, and kept out of the repository).

---

## 8. Lockstep details

- **One TICK a frame.** 4522h is called once per frame, from the handler, under the busy flag. 4583h is a second reader in the same frame.
  It gets the cached value and never reads the hardware (PROTOCOLS 4.4).
- **Both seats read their own port 1 and keyboard** (`rdLocal`). The engine puts seat 0's byte in `PN_P1` and seat 1's in `PN_P2`. The
  game never sees which machine it runs on: the mode, the current player and the menu choice are all derived from `PN_P1`/`PN_P2`, so they
  are the same on both machines.
- **The demo** (E002h bit 6 = 0) overrides the input in 452Bh. That runs after `tick`, on both machines, with the same table: deterministic.
- **Checksum**: E100h-E2FFh (Oolong, the opponent and the projectiles). The extension RAM is not covered. A Turn or Versus bug that left it
  different would show up within a few frames as different objects anyway.
- **50 Hz against 60 Hz**: as for Soccer, the game runs at the slower machine's pace, and the music follows player 1's interrupt count.
- **What stub ABI 2 and MSXNP 2 bring**, with no work in the package:
  - **K and S**: a packet every K frames (1 on the MSXPi link, 2 with a software TCP/IP stack), and an input delay of
    `ceil(rtt / 2 / 20) + 2 + (K - 1) + S`, clamped to 2..7. Agreed in HELLO/SETUP.
  - **Timed resend**: a waiting machine resends after 3 interrupts (about 50 ms), not after a count of polls.
  - **Interrupts lost in `XCHG`** (MSX-DOS's handler took them on the TCP/IP path) come back in E and are added to the count, so
    the music keeps its tempo over TCP/IP too.
  - **DELTA packets** on the MSXPi link: with W = 1 a full packet is 22 bytes, a DELTA 6 (K = 1) or 8 (K = 2). Salamander's
    exchange went from 5.6 ms to about 2 ms a frame with them.
  - **Link 2**: an MCHAT /T player whose machine also has an MSXPi sends the game's packets through the MSXPi.
- **Speed**: measured against the cartridge with Salamander's tools (`prof.tcl`: ticks, time in the exchange, PC histogram per
  10 s; `busy.tcl`: per-frame time from the interrupt to the idle loop, which also runs on the cartridge). Target: the cartridge's
  frame rate in a fight. A 16 KB game with no bank switches and one SNSMAT-light reader (`rdLocal`: one PSG read, two SNSMAT)
  should get there; the per-frame costs to watch are the exchange and `rdLocal`.

---

## 9. Offline two-player ROM (later phase, D4)

- A second package, `profiles/yiear-2p/`, `output.target = "rom-file"`, 32 KB plain: the original 16 KB plus the extension at A000h in the
  same build, and **no** PLAYNET stub.
- A small local glue (in the extension's build, `-DLOCAL2P`) replaces `tick`: it reads port 1 (and the keyboard) into `IN_P1` and port 2
  (`WRTPSG` R15 = CFh) into `IN_P2`, at the two RAM bytes the extension uses as `PN_P1`/`PN_P2`.
- A 32 KB cartridge needs page 2 selected by its own INIT. A patch at 4010h calls a routine that enables the cartridge's slot in page 2
  (RSLREG/ENASLT, as other 32 KB Konami ROMs do), then goes on with the original INIT.
- The sound and interrupt patches are not applied (no lockstep), so the music runs exactly as on the original cartridge.
- It doubles as a **deterministic test bed for Versus**: openMSX with two joysticks (or scripted key presses), with no network at all.

---

## 10. Risks

| # | Risk | Mitigation |
|---|---|---|
| K1 | Versus needs the five opponents' move vocabularies, read from five AI routines (about 3 KB of code). The work is uncertain. | Step 6 is analysis only and produces a table per opponent. Versus can ship with the opponents that are done, the others falling back to the AI, behind a build flag. |
| K2 | Some opponent behaviour is not in the vocabulary (for example a move started inside the routine itself) | Such a move becomes one more table entry: "call this address in that routine". Patches into the AI routines are allowed if needed. |
| K3 | The Turn block is wrong (a variable missed) | Write watches through two full games, one per player (T2), and a Turn test that compares each player's block with a Single game played the same way (T8) |
| K4 | The game writes page 2 or E402h-E4FFh after all | Footprint measurement first (step 1, T2). The extension moves if needed (D5/D9). |
| K5 | The staging breaks Soccer, Salamander or the TCP/IP path | The Soccer rig scenarios (plain, chat, mixed, tcp) and Salamander's `run_salamander.sh` (plain, `CHAT=1 EXITKEY`) are rerun as a regression (T10). Both GPFs stay byte-identical. |
| K6 | Balance: player 2's opponent is too strong or too weak | The AI's countdowns are kept. Human play tests (T9) can tune the move tables without touching the engine. |
| K7 | The GPF grows past 8 KB | Very unlikely (estimated 4.5-5.5 KB). `rebuild.py` asserts the size. |
| K8 | Something overwrites the stub or the transport between the trampoline's jump and the first frame (Salamander's start-up crash: MSX-DOS's stack inside its stub) | Soccer's layout is the one the fix was proven with. The rig adds a write watch on C100h-C6FFh from the jump to the first `PN_TICK`, and compares the stub with `stub.bin` there (`salamander_debug/wwatch.tcl`): 0 foreign writes (T2.3). |
| K9 | The TCP/IP path of the rig is broken (HANDOVER-salamander 4b: no frame from INL reaches the server's NAT link, for Soccer and master too) | Yie Ar's TCP/IP tests (T11.4) wait for that fix; the MSXPi and link-2 paths do not depend on it. |

---

## 11. What changes, by file

| File | Change |
|---|---|
| `software/ROM-Patcher/profiles/yiear/` (new) | the package (4.2) |
| `software/Client/src/playnet/playnet_gpf.asm`, `playnet.asm`, `playnet_tcp.asm` | GPF staging at 8000h, `gpfBase` for every `GPFBUF` reference, the memory-map comment, `PLAYNET_VERSION` (section 6, D10) |
| `software/ROM-Patcher/patch_rom.py` | the staging rule; `min_playnet` up to the new release accepted |
| `software/ROM-Patcher/tests/test_gpf.py` | Yie Ar tests (`YIEAR_ROM`), the staged GPF vector |
| `software/Client/tests/soccernet/run_yiear.sh`, `yiear_node.tcl` (new) | the rig (D11): two Canon V-25 + MSXPi, `MODE=single\|turn\|versus`, `SEED`, `CHAT=1`, `EXITKEY=n`, `TCP=1`, `ONLY`, `EXTRA_TCL`; one trace line per frame (frame, E000h, E002h, E054h, a hash of E000h-E4FFh), compared by `cmp_pair.py` |
| `software/target/games/YIEAR.GPF`, `index.txt`, `README.md` | the published game (`build_games.py`; `test_games_folder_is_current`) |
| `documents/PLAYNET-PROTOCOLS.md` | section 6 replaced by the verified package, 8.1/7.2 staging, 17 the new vector |
| `documents/YIEAR-QUICKSTART.txt` (new) | as `SOCCER-QUICKSTART.txt`, with the modes and the controls |

The chat, the Pi server, the lockstep engine (`playnet_engine.asm`) and the transports do not change: a new game is a new GPF.

---

## 12. Open points for review

1. D5-D11 above. D10 is shared with Salamander (SALAMANDER-DESIGN 12.2, point 3).
2. Should Versus give player 2 a REST of its own (for example the fight is lost when player 2's opponent is beaten twice), or is "player
   1 against the five opponents" enough? The proposal (D8) keeps the game's rules.
3. Should the mode be part of the invitation (`/play NICK yiear versus`)? Not proposed: it needs a session field. The in-game screen works
   for every path, including a manual start.
4. Turn online: while player 2 plays, player 1's machine shows the same game. That is expected, but it should be said in the quick start.

---

## 13. What changed with the rebase on `feature/tcpip-games` (2026-10-23)

| Area | Before (design of 2026-10-22, on `master`) | Now |
|---|---|---|
| PLAYNET release | release 2 = GPF staging | release 2 = stub ABI 2, release 3 = `mapper-ram`; the staging is folded into 3 or becomes 4 (D10) |
| Stub header / ABI | 4 bytes, ABI 1, delay 2-6 | 5 bytes, ABI 2 (byte 4 = K), delay 2-7 |
| Peer protocol | MSXNP 1 | MSXNP 2 (K and S in HELLO/SETUP/ACK) |
| MSXPi link | full packets only, 204-byte transport | DELTA packets, 432-byte transport (fits the 512 reserved) |
| Links | 0 MSXPi, 1 TCP/IP | plus 2: TCP/IP chat, game through the MSXPi (`transport_hybrid`) |
| `XCHG` | | returns in E the interrupts MSX-DOS took; the TCP/IP transports put back pages 1 and 2 from `tSegs` |
| Loader memory | GPF 2800h-33FFh, transport at 3C00h | CRC tables 2500h, GPF 2900h-34FFh, bounce 3500h (2.75 KB chunks), transport 3D00h; GPF code in page 1 |
| Trampoline | used MSX-DOS's stack | its own stack under C100h (`TRAMP_SP`): nothing of a package below C100h |
| Soccer | `min_playnet` 1, stub 640 bytes | `min_playnet` 2, stub 746 bytes, GPF 1080 bytes |
| Rig and method | generalise `run_native.sh`, scripted tables in the engine (`G_SCRIPT`) | a rig of the game's own driven by Tcl keys (D11); `rebuild.py --rom/--syms`; stub write watches; speed against the cartridge; publish with `build_games.py` |

The game analysis (sections 3 and 5) and the user's decisions D1-D4 are unaffected.

---

## 14. As built (2026-10-24)

The implementation (commits "Single-mode package" to "Versus mode" on `feature/yiear-netplay`) follows sections 3-5 with these
differences. Where this section and the sections above disagree, this one is right.

| Area | Design | As built |
|---|---|---|
| GPF size, loader | 4.5-5.5 KB, needs GPFs up to 8 KB (section 6, D6, D10) | **1830 bytes** (stub 804, extension 662, 12 patches): fits `GPFBUF`, no loader change, `min_playnet` 2. `test_gpf.py` asserts it stays under 3 KB. |
| State both machines read | E480h-E4FFh (D9) | in the **stub** (`tMode`, `tCur`, `tOut`, `tWin`, `tBlk`): the loader copies its bytes, so they start equal on both machines; INIT does not clear E480h. The extension keeps in RAM only the menu's cursor (E481h) and edge byte (E482h), written before they are read. |
| Menu | cursor starts on VERSUS online; "PLAYER 1 SELECTS" | cursor starts on **SINGLE**; no "PLAYER 1 SELECTS" line yet |
| Title start | patch 45A7h (`jp X.menu`) | patch **45ADh** `03` -> `09`: the title's own start sets state 9 |
| Turn hooks | sites to be found | **4132h** (`call 42A3h` -> `newGame`) and **41DCh** (`ld a,(E050h)` -> `lifeLost`); block E049h-E05Fh (23 bytes); hi-score E043h-E045h stays global. "PLAYER n" over PLAY START and on row 2 during fights. |
| Versus | patch the AI dispatch 6B42h, a move table per opponent | the five AI routines share **one decision point, 7335h**; patch **7338h** -> `vsDecide`. One mapping for all opponents: trigger = action 4 (7454h), trigger+up = 5 (7458h), trigger+down = 6 (7450h), left/right = a step (74E7h) every 8 frames, nothing = stand (5522h). No per-opponent tables, no specials, no jump yet. |
| Versus end | 4280h, 41F3h | **4284h** -> `vsWin` (player 1 wins: REST = 0, state 6, the game's own game over); `lifeLost` sets `tWin` = 2; "PLAYER n WINS" printed over state 7 by `dispatch` |
| Rig input (D11) | Tcl key presses | the `--test-gpf` build with the engine's **SCRIPTED** tables (Soccer's table: bit 4 starts the game); Turn and Versus tests add Tcl pokes and inputs in `yiear_debug/` |
| Test builds | must not touch committed files | fixed 2026-10-24: `--test-gpf` writes its generated includes in a temporary folder, and `test_gpf.py` checks that `src/stub_syms.inc` names the published stub's addresses |

---

## 15. Decisions of 2026-10-24 (user), and the choices left to the implementer

| # | Point | Decision |
|---|---|---|
| U1 | A jump for player 2 (Versus) | **Yes** |
| U2 | Player 2's lives (Versus) | **Lives of their own.** Replaces D8 (below). |
| U3 | Where the menu cursor starts | **SINGLE** (as built) |
| U4 | "PLAYER 1 SELECTS" on the menu | **No** |
| U5 | "PLAYER n GAME OVER" in Turn | Shown when a player is out, but the game does not stop: **both machines stay in lockstep and keep showing the other player's game** until they are out too |
| U6 | TCP/IP rig scenarios | **Skipped** (the rig's TCP/IP path is broken for every game, K9) |
| U7 | A 50 Hz against 60 Hz run | **No** (not done for this game) |
| U8 | How the rig drives the game (D11) | **Tcl key presses** instead of the engine's SCRIPTED tables |
| U9 | Real hardware (plan step 10) | **Not part of this work** |

Left to the implementer, "with criteria from similar games":

| # | Point | Choice |
|---|---|---|
| I1 | Player 2's move set | Read from each opponent's own action table (6E5Bh, 6FFEh, 7302h, 772Ch, 79A3h: 4-pose animations per action) and the emulator (`yiear_debug/moves.tcl`). Mapped the way the one-button fighting games of the time do it, and the way Oolong is played: the button with a direction picks the attack (up = high, nothing = middle, down = low), up alone jumps where the opponent has a jump. |
| I2 | Opponent 2's throw | **Player 2 throws**, with the second button (input bit 5: joystick button B, or the keyboard key the game reads there), instead of the throw firing by itself |
| I3 | Lives in Versus (U2) | Each player has the game's starting lives: 3. P1's are the game's own REST (E050h: decremented at every stage start, 41B4h, and given back when P1 wins a fight, 423Eh, so a win costs P1 nothing). P2's are a counter in the stub: P2 loses one each time P1 beats the opponent. A lost fight costs the loser one life; the next fight is the next opponent (P1 won) or the same one again (P2 won), in the game's order, cycling after the fifth. **The match ends when either player has no lives left**: "PLAYER n WINS", then the game-over screen and the title. The "beat the fifth opponent" rule (4284h) is dropped; the level (E056h) stays 0 for the whole match so the opponents' timings do not change. P2's lives are shown during fights. |
| I4 | Tests left open | Run on the MSXPi path: the three modes with lag and loss, the chat with the exit key, link 2, the sound tempo against the cartridge, the speed, desync detection |
| I5 | `KUNG-FU.ROM` (D7), the extension at A000h (D5) | Kept |

### 15.1 As built for I1-I3 (2026-10-24)

- **Moves** (`vsDecide` at 7338h, all five opponents): LEFT/RIGHT walk a step every 8 frames; the button with UP / nothing / DOWN starts the
  opponent's own actions 5 / 4 / 6 (7458h, 7454h, 7450h); **the second button, or UP alone, is the jump attack**: action `JUMPS[opponent]` =
  3, 3, 4, 4, 0, the one pose script of each opponent with the airborne flag (10h) in its action table (6E5Bh, 6FFEh, 7302h, 772Ch, 79A3h),
  started through 7429h. Nothing pressed: the opponent stands.
- **The throw (I2)**: opponent 2's weapon (7162h/718Dh) is not a separate action: the game runs it by itself while the opponent is in
  certain poses (E184h = 2, 3, 10h, 11h, 463Ah). So it is player 2's jump attack, not a button of its own. The first version of
  Versus has no other throw.
- **Which of 4/5/6 is high, middle or low** was not established (screenshots are black in the headless runs; the poses are only
  numbers in RAM). The up / nothing / down mapping above is a convention; a human test decides. `yiear_debug/moves.tcl` logs the poses.
- **Lives (I3, U2)**: player 1's are the game's REST; player 2's are `tLives2` in the stub (3 at the start of a Versus game, shown as
  "P2 REST n" on row 2 every 16 frames). The patch at **423Eh** (`vsBeaten`) takes one from player 2 each time an opponent is beaten and
  sends the game's REST + 1 to a dummy byte (E483h) so player 1 does not get it back. When player 2 has none, player 1 wins through the
  game's own game-over path. When REST is 0, player 2 wins (`lifeLost`, as before). The 4284h patch (fifth opponent) is gone: the
  opponents cycle and the level rises as in the game.
- **Turn game over (U5)**: while a player is out, "PLAYER n GAME OVER" is shown on row 3 every 16 frames and the other player's fight
  goes on (the screen is never frozen; both machines stay in lockstep).

