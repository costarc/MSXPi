# 1942 online, turn based (PLAYNET): analysis and design

Written 2026-10-27. It brings ASCII's 1942 for the MSX to PLAYNET (`documents/PLAYNET-PROTOCOLS.md`) in the game's own
two-player mode, which takes turns. The method is Salamander's (`documents/SALAMANDER-DESIGN.md`): the whole game runs on both
machines in lockstep and only the inputs cross the network, from a 128 KB MegaROM hosted in mapper RAM.

| | |
|---|---|
| Dump | `1942.ROM`, 131072 bytes, CRC-32 `C99E5601`, SHA-256 `d8442d2c08958f0bc9be7d2078e3cf07224e1ec3493ddce3215ed8df2bd37b1f` (the user's copy is `C:\Users\roniv\Dev\MX\gameroms\1942.ROM`, from msxarchive.nl `games/roms/msx2/1942.lzh`; never commit it or anything derived from it, such as a disassembly) |
| Mapper | ASCII8: 16 banks of 8 KB, registers 6000h / 6800h / 7000h / 7800h for the windows at 4000h / 6000h / 8000h / A000h |
| Game id / GPF | `1942` / `1942.GPF` |
| Roles | `P1` (seat 0, the inviter), `P2` (seat 1) |
| Input width | 2 bytes |
| Package | `software/ROM-Patcher/profiles/1942/` (glue, rebuild script, profile). The bank engine is `software/Client/src/playnet/engine/mapper_k8.asm`, unchanged. |

## 1. Summary

- **Turn based comes with the game.** The title offers 1 PLAYER, 2 PLAYERS and CONTINUE. In 2 PLAYERS one ship flies and, when it is
  shot down, the other player gets the next one: the game swaps the two players' blocks (4295h) and flips bit 0 of `EFA0h`. So the
  package needs no game logic: the machine whose player is not active just watches, and the game gets the active player's input.
- **One input routine.** The game polls everything in one routine, 6D09h (joystick/cursors via GTSTCK and GTTRIG, space, a few
  keys via SNSMAT), and the hi-score name entry in 6DAAh. There is no interrupt handler: the BIOS interrupt only paces the
  frame (`ei; halt` at 4871h, 30 frames/s). Each of the 5 + 2 call sites becomes a call to the stub: PN_TICK, then the net input.
- **The hard part is the room, not the game.** The game owns C000h-DD5Fh (the stage map, 7 KB, built at each stage by 71A8h)
  and EA00h-F37Fh, and writes E000h-E016h. Free: DD60h-DFFFh and E017h-E9FFh. The transport (512 bytes) goes at DD60h, the
  stub at E018h-E5FFh (1501 of 1512 bytes used) and the bank engine's pair map at E600h-E9FFh.
- **Memory**: 25 bank switches a frame, so the pair map is needed. 13 pinned segments plus spares: minimum 20, recommended 28.
- **No sound work.** The game plays its music from its main loop; there is no SCC and no per-interrupt driver
  (`G_SOUND_TICK = 0`).
- **MSXPi link only for now.** The UNAPI and hybrid transports must sit in MSX-DOS's page 3 below the TPA top (D406h-D706h);
  1942 leaves no free RAM there.

## 2. What the ROM does

All measured in openMSX with the real cartridge (`-romtype ASCII8`), by disassembly of the code the traces reach, and by
Tcl watchpoints over several minutes of a bot playing.

### 2.1 Start, frame, interrupt

| | |
|---|---|
| Header | `AB`, INIT = 4013h, no STATEMENT/DEVICE/TEXT |
| INIT 4013h | writes the four bank registers (banks 0, 1, 2, 3 into 6000h, 6800h, 7000h, 7800h: 4014h-4022h), clears a few variables, WRTVDP, SP = F380h, then **never returns**: it runs the game's main loop at 4066h (title menu 4443h, new game 40D7h, frame 413Fh). |
| Interrupt | The game installs no hook. The BIOS interrupt runs, and the game waits for it with `ei; halt` at 4871h (inside 4858h, once per frame). It reads neither JIFFY nor the VDP status (only the BIOS does). |
| Frame 413Fh | one pass of 415Dh-41A3h is one game frame: input (6D09h), the game, `halt`. |
| Slots | 5CC0h: RSLREG/WSLREG puts page 2 in the slot of page 1 (the cartridge's). In PLAYNET both are the same RAM slot. |

### 2.2 Banks

- W0 (4000h) and W1 (6000h) never change after INIT: banks 0 and 1 hold all the code and the resident data. The game writes
  only the W2 and W3 registers while it runs: **14 sites** (`ld (7000h),a` x 2, `ld (7800h),a` x 12), plus the four at INIT. No
  indirect writes (`ld hl,7000h` at 4056h and `ld de,6000h` at 46A1h are data and arithmetic).
- W2 is always bank 2 or 5. W3 takes 3-15. Pairs seen over 6743 + 3757 frames: (2,3) (2,4) (2,6) (2,7) (2,8) (2,9) (2,10) (2,11)
  (2,12) (2,13) (2,14) (2,15) (5,3) (5,4) (5,6) (5,7). Traffic: about 12 W2 and 29 W3 writes a frame, almost all of them real
  changes (the sprite and pattern drawing alternates banks).
- Homes: banks 8-15 each need a pair of their own, because W2 is only ever 2 or 5. So 12 pairs are pinned.

### 2.3 Inputs

| Reader | What it does |
|---|---|
| 6D09h | `ED10h` = GTSTCK 0 (cursors), else 1, else 2 (value 0-8); bit 7 = any of GTTRIG 1, 2 (space, trigger A) or space (row 8 bit 0); bit 6 = GTTRIG 3, 4 (trigger B, M/N) or SHIFT; bit 5 = STOP (row 7 bit 4: pause). Then 6D77h: a key combination that sets bit 7 of `EE83h`. |
| 6DAAh | the hi-score name: the key pressed, as an ASCII code, in `ED10h` |
| callers of 6D09h | 4161h (the frame), 43E2h and 43ECh (pause: until the key is released, then until another is pressed), 4468h (the title menu loop, 4608 polls), 4507h (the wait after game over) |
| callers of 6DAAh | 459Eh, 45B7h (name entry) |

No other keyboard, joystick or PSG read exists in the game's own code.

### 2.4 Who is active

`EFA0h`: bit 7 = two players, bit 0 = the first player's turn. The title sets it to 00h (1 PLAYER) or 81h (2 PLAYERS). At the end
of a life (4210h) the swap routine 4295h flips bit 0 and exchanges the two players' blocks (`ED20h`.. with `EFA1h`..). So **the
second player is active exactly when `EFA0h` = 80h**.

### 2.5 Determinism

| Source | Finding | Action |
|---|---|---|
| R register | 10 `ld a,r` in bank 1 (6100h 6127h 63A2h 63AFh 63D1h 63D8h 64F0h 65D5h 6673h 6912h); two more bytes `ED 5F` in banks 13 and 15 are data | each one and the instruction after it -> a call to the same instruction on a xorshift value |
| Interrupt counts, JIFFY, VDP status | not read by the game | - |
| Keys | only through 6D09h/6DAAh, and the combination at 6D77h | the stub reads them (`rdLocal`), 6D77h is patched out |
| RAM at start | a cartridge game starts after the BIOS cleared the RAM; `EFA0h` and other variables are read before they are written | `initGame` clears the game's RAM on both machines |
| ROM writes | `ld (4000h),0` at 5CD5h (the `ldir` after it is already patched out in this dump) writes into the ROM copy | patched out |

### 2.6 RAM

Measured with write watchpoints during 10,000 frames of a bot playing:

| Range | Use |
|---|---|
| C000h-DBFFh | the stage map, written by 71A8h at the start of a stage |
| DC00h-DD5Fh | a copy of F000h-F15Fh (7B21h), restored by 7B24h |
| DD60h-DFFFh | **free** |
| E000h-E016h | variables (`E010h` the most) |
| E017h-E9FFh | **free** (E000h-E7FFh measured, E800h-E9FFh by the code: the first use is the `ldir` at EA00h) |
| EA00h-ECFFh | a work buffer (cleared with `ldir` at 4980h and 41EFh) |
| ED00h-EFFFh | the game's variables, the two players' blocks |
| F000h-F37Fh | sprite attribute copy, hi-score table (F160h), the stack below F380h |

## 3. Design

| Piece | Where | |
|---|---|---|
| Transport | DD60h-DF5Fh | PLAYNET's (MSXPi), unchanged |
| Stub | E018h-E5F0h | the engine, the 8 KB bank engine, the glue |
| Pair map | E600h-E9FFh | the bank engine's 1 KB map |
| Game RAM saved by PLAYNET | C000h-DD5Fh, E000h-E016h, E600h-F37Fh | |

### 3.1 Patches (34, generated by `rebuild.py`)

| Group | Sites | Replacement |
|---|---|---|
| INIT | 4014h-4022h (the four bank writes) | `call initGame` + nops: SP = F380h, clear C000h-DD5Fh, E000h-E017h, EA00h-F2FFh, H.KEYI -> XIRQ |
| INIT | 5CD5h `ld (hl),0` (hl = 4000h) | nop |
| Frame, pause | 4161h, 43E2h, 43ECh | `call inAct` |
| Title menu | 4468h | `call inP1` (the inviter) |
| After game over | 4507h | `call inAny` (either player) |
| Name entry | 459Eh, 45B7h | `call keyAct` |
| Secret keys | 6D73h `call 6D77h` | nops |
| `ld a,r` | the 10 above | `call rAnd7F/rRra/rAnd0C/rAnd3F/rAnd0F` |
| Bank switches | 14 sites | `call MK_W2` / `call MK_W3` |

`inP1`, `inAny`, `inAct` all start with PN_TICK (the exchange), then pick: player 1's byte, the OR of both, or the active player's
(`EFA0h` = 80h: player 2's, else player 1's); the result goes in `ED10h`, where the game expects it. `rdLocal` (called inside
PN_TICK) runs the game's own 6D09h and 6DAAh to read this machine's keys: byte 0 and byte 1 of the input.

The H.KEYI hook is installed only because the TCP/IP transports count interrupts in XIRQ; `irq_handler` is the `ret` at 413Eh.

### 3.2 Why every call is a TICK

The title and pause loops poll 6D09h without waiting for an interrupt. Making each call an exchange keeps both machines on the same
sequence of calls, whatever their speed; the exchange itself (and the `halt` in the frame) is what paces them. The number of
exchanges in a loop therefore depends on the network, not on time: the title's 4608 polls take a few seconds.

### 3.3 Memory

| Segments | |
|---|---|
| 1 | page 1, always (0,1) (the table has a second, unused entry: the loader wants a spare per page) |
| 12 | page 2, pinned: (2,3) (5,4) (5,6) (5,7) (2,8) (2,9) (2,10) (2,11) (2,12) (2,13) (2,14) (2,15) |
| 4 | (2,4) (2,6) (2,7) (5,3), seen in play |
| 7 | spares (the clock replaces among the 12 non-pinned) |

Minimum 20, recommended 28.

## 4. Open points

1. TCP/IP and hybrid transports: no room below the TPA top. Moving the game's stage map out of C000h-DD5Fh would free it
   (it is addressed from many places).
2. The real hardware: never run.
3. A spectator's view of the other player's turn is the same game, with the same frame delay (input delay D).
4. Name entry and the pause key follow the active player; the title menu follows the inviter.
