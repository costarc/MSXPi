# Taito's Bubble Bobble online, two players at once

Package format `msxpi-rom-patch` version 2 with the `msxpi-netplay-v1` ABI and image host `mapper-ram` (mapper type `ascii8`).
This file holds the analysis behind every patch.

| | |
|---|---|
| Input | `BUBBLE.ROM`, Taito's Bubble Bobble for the MSX2 (1987), 131072 bytes, ASCII8 MegaROM, CRC-32 `6524D9FC`, SHA-256 `15962fd815c3fd8d28cbb664c8f99d10825979fb5b9bd975b7aac785d35532eb` |
| Output | a RAM image in mapper segments for PLAYNET (`output.target = "ram-image"`), never a ROM file |
| Game id, roles | `bubble`; `P1` (seat 0, the inviter, Bub: the green dragon), `P2` (seat 1, Bob: the blue one) |
| Play | the game's own two-player mode: both dragons at once. In the play select, 2P START starts both; after 1P START the second player joins by pressing a trigger, as on the cartridge. Either player's STOP pauses the game on both machines. |
| Controls | each player on their own machine: joystick port 1 or 2, or either key set of the game (cursors, space, GRAPH; or D, G, CTRL, SHIFT) |
| Layout for PLAYNET | transport C950h-CB4Fh, the bank engine's pair map CC00h-CFFFh, stub E660h-EF7Fh (engine, 8 KB bank engine, glue, the bank-switch site table) |
| Machine | an MSX2 (the game needs one) with a memory mapper of at least 16 free segments (512 KB recommended). The MSXPi link, TCP/IP UNAPI (`PLAYNET /T`) and mixed pairs. |

No ROM data is included. The player supplies their own dump.

## What the ROM does

Measured in openMSX (Canon V-25, `-romtype ASCII8`) with the cartridge: a bot playing two players for ten minutes (seven
rounds, deaths, continues) under write watchpoints, BIOS-call breakpoints and a bank-register log; and a disassembly of
the code those reach.

| | |
|---|---|
| Header, INIT | `AB`, INIT 4054h: `di`, SP = F380h, the slot of page 2 (4184h), H.KEYI = `ret`, banks W1 = 4, W2 = 9, W3 = 5, the RAM clear C000h-F37Dh (6825h), VRAM set-up, then H.KEYI = `jp 42D5h` (4137h-413Fh), `ei`, and the main loop `jp 414Bh`, which never does anything else. |
| The frame | **Everything runs in the H.KEYI handler 42D5h**: a busy flag (D032h) makes a nested interrupt return at once; the sound driver (6066h, 82AEh, with banks 14 and 15 in page 2); a cooperative task scheduler (4231h: tasks 0-8, a timer each at C000h-C00Fh, a stack each at C030h + 256 x n); then 4323h: the sprite table to VRAM and **both players' inputs, once per interrupt**. |
| Inputs | 4353h reads a joystick (E = 8Fh port 1, CFh port 2) through PSG registers 15/14; 4364h player 1's keys (row 8: cursors, space; row 6: GRAPH, CAPS; row 2), 43B3h player 2's (row 3: D, G; row 6: CTRL, SHIFT). One byte each, bits 0-5: up, down, left, right, trigger A, trigger B. Player 1 goes to E150h and DAD6h, player 2 to DB66h. The only other keyboard reads are in bank 13 (B084h): STOP (pause, row 7) and HOME+INS / HOME+DEL (row 8). |
| Banks | ASCII8, registers written at 6FF8h (W1), 77F8h (W2), 7FF8h (W3), each with a shadow copy in E488h-E48Ah. W0 is always bank 0, W1 bank 4 or 11. 167 writes, all of them code (each is next to its shadow store); about 8 a frame. Pairs seen in page 2: (9,5) (9,3) (9,13) (9,15) (14,5) (14,15) (6,5) (6,10) (6,13) (8,5) (9,7) (12,13) (12,5) (9,2) (9,10) (2,1) (2,3) (2,5) (9,1) (0,13). Seventeen more stores into 6000h-7FFFh are data or the tail of IX instructions. |
| Determinism | 17 `ld a,r`, 15 of them code (two in bank 2 are graphics). No JIFFY read, no VDP status read by the game (the BIOS reads it), no H.TIMI, no EXTBIO. RDPSG at 8291h reads the mixer register, which the game wrote. |
| Page 3 after INIT | written: C000h-C94Fh (the task stacks; SP goes down to C115h), D030h-E65Fh, EF80h-F37Fh. **Free: C950h-D02Fh** (no task 9-15 exists: the scheduler's entry table 42B5h ends at task 8) **and E660h-EF7Fh**. Read watchpoints over the same ten minutes: the game's only reads there are EF7Eh-EF7Fh (A7CFh, bank 15 at INIT: a table it never writes, so 0 on the cartridge). |

## Patches

| Where | What | Why |
|---|---|---|
| 405Ah `call 4184h` | `call stubInit` | before the game's first bank switch, the stub turns the 163 bank-register writes into `call MK_W1/MK_W2/MK_W3` in every segment the loader built (below) |
| 4079h `call 6825h` | `call clrGame` | the RAM clear C000h-F37Dh, around the transport, the pair map and the stub, and from the stub's end on (the game reads EF7Eh-EF7Fh: on a Nextor machine MSX-DOS's bytes were there, and the two machines differed) |
| 42DDh, 431Ah | `call busyChk`, `jp isrEnd` | the frame catch-up (below) |
| 413Dh `ld hl,42D5h` | `ld hl,XIRQ` | H.KEYI through the transport; `irq_handler` = 42D5h |
| 42E8h, 42F9h | `call sndMap`, `call gameMap` | the handler's own switches to the sound banks (14,15) and back, each as one page-2 switch (`MK_W23`) instead of two through a passing pair |
| 432Fh | `call inP1` | **the TICK**: PN_TICK, then player 1's byte (seat 0) |
| 4342h | `call inP2` | player 2's byte (seat 1) |
| bank 13: B08Dh, B0BDh | `call stopKey` | the pause: STOP is bit 6 of each player's byte, so a pause happens on both machines on the same frame |
| bank 13: B099h | `ld a,FFh` | HOME+INS, HOME+DEL: local keys, never pressed |
| 15 `ld a,r` | `call rnd...` | a 16-bit LFSR in the stub instead of R, with the instruction that followed |

`rdLocal` (the local input, read inside PN_TICK) ORs both joysticks and both key sets, and adds STOP as bit 6.

**Why the bank switches are patched by the stub.** As GPF patches the 163 sites would cost 11 bytes each: the GPF would be
3.9 KB, more than PLAYNET's 3 KB buffer. The stub carries them as a table (`src/sites.asm`, 2 bytes a site, generated by
`rebuild.py`) and patches them at INIT: the loader has already checked the ROM's CRC-32, so the offsets are right, and the stub
patches a site only when it holds `ld (xxF8h),a`. Segments built later are copied from the homes, which are patched by then.
`rebuild.py --rom` checks every site against the dump. The GPF is 2.7 KB.

**The frame catch-up.** Every frame is one run of the H.KEYI handler, and an interrupt that comes while it runs is dropped (the
busy flag D032h). So a frame that the network exchange makes longer than an interrupt period costs a whole period. With the two
patches at 42DDh and 431Ah, an interrupt that comes during PN_TICK is kept: the next frame runs as soon as this one ends (one at
most). That covers an interrupt in the game's page 3, and one that MSX-DOS's handler took inside XCHG on TCP/IP (the engine counts
those in `irqCnt`). Interrupts that the game's own work makes it miss are still dropped, as on the cartridge. Only the pace
changes, never what a frame computes, so the machines stay in lockstep. Measured (emulated, frames 600-2400): the MSXPi pair from
about 46 to 53 frames a second, the mixed pair from about 35 to 40.

## Memory

| Segments | |
|---|---|
| 2 | page 1: (0,4), (0,11), plus a spare entry |
| 12 | page 2, pinned: the homes of banks 1-3, 5-10, 12-15 |
| 8 | the other pairs seen in play; the clock replaces among them |

Minimum 16 segments, recommended 22.

## Files

| File | |
|---|---|
| `src/glue.asm` | the game's side: inputs, INIT, the bank-switch patcher, `ld a,r` |
| `src/sites.asm` | generated by `rebuild.py`: the bank-switch sites, per bank |
| `src/playnet_engine.asm`, `src/mapper_k8.asm` | copied by `rebuild.py` from `software/Client/src/playnet/engine/` |
| `rebuild.py` | assembles the stub, generates the patches, writes `profile.json`; `--rom` checks them against a dump |
| `assets/stub.bin`, `profile.json` | generated |

## Rebuild and test (developers)

```console
python profiles/bubble/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\path\to\BUBBLE.ROM
```

Two emulators: `software/Client/tests/soccernet/run_bubble.sh` (`BUBBLE_ROM=...`; its own ports 8125/8126, UDP 5131/5132, IRC
6681, so it can run beside the other rigs). `TCP=1` puts the second node on TCP/IP (Nextor + InterNestor Lite), `BOTH=1` both,
`CHAT=1` the chat flow, `EXITKEY=n` the exit key.

| Run (emulated, Canon V-25) | Result |
|---|---|
| MSXPi pair, 3000 frames, 50 ms lag, 8 % loss, 20 ms jitter | identical, no desync, about 53 fps |
| MSXPi pair through MCHAT (`/play bob bubble`), Ctrl+Shift+F5 at frame 1500 | identical; both back in MCHAT |
| mixed pair (P2 on TCP/IP), 3000 frames | identical, no desync, about 36-40 fps |

## Open points

- The free RAM and the reads were measured over ten minutes and seven rounds, not over all 100 rounds and the ending.
- Real hardware: never run.
