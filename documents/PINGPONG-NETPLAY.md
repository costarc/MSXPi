# Konami's Ping Pong online (PLAYNET)

Written 2026-10-24. Package: `software/ROM-Patcher/profiles/pingpong/`. Rig: `software/Client/tests/soccernet/run_pingpong.sh`.
The method is Soccer's (`documents/SOCCERNET-NETPLAY.md`, `PLAYNET-PROTOCOLS.md`): both machines run the whole game and only the
pad bytes cross the network, in lockstep. Ping Pong is the easiest game of the family so far, because the ROM already has a
**simultaneous 2 PLAYERS mode**: nothing has to be added to the game, only its input and its clock have to be tied to the network.

| | |
|---|---|
| ROM | `PINGPONG.ROM`, 16384 bytes, CRC-32 `3F200491`, SHA-256 `8e0f57b2c52e85505505c1d4bb4643eb7311213676f0ecfe21dd06571fc0bbd5` (the user's copy: `C:\Users\roniv\Dev\MSX\gameroms\PINGPONG.ROM`). Never commit it, or the disassembly. |
| Game id | `pingpong` (`PINGPONG.GPF`), roles `P1` (the inviter, seat 0) and `P2` |
| PLAYNET | release 2 or later (stub ABI 2), image host `plain`, no mapper |
| Stub | 749 bytes at C100h (limit 1024), transport C500h-C6FFh |

## 1. What the ROM does (static analysis, confirmed in openMSX)

- Header `AB`, INIT 406Ch, no mapper. INIT installs H.KEYI (FD9Ah) pointing to the handler at 4019h, clears E000h-E3FFh, sets SP to E400h
  and idles in `jr $` (409Ah). **The whole game runs from the interrupt**, under a busy flag (E005h bit 0), as in Soccer and Yie Ar.
- Per interrupt: RDVDP, sound driver tick (4019h: `call 5195h`), then, when not already busy: 46ACh, **47E3h (the pad reader)**, 409Fh
  (state dispatch on E000h/E001h, frame counter E003h), and at the end RDVDP again and a catch-up sound tick (404Ah) when another
  interrupt is already pending.
- **Pads** (47E3h, once per frame): player 2 first, 4837h: if E002h bit 5 (two players) is clear the computer plays (5B6Eh), else joystick 2
  (PSG, 4802h with E = CFh) or keys (4852h); then player 1: joystick 1 (4800h) or cursor keys + space (4812h). The result is cached with its
  edge byte at E009h/E008h (player 1) and E049h/E048h (player 2). 46EBh swaps the two (the players change ends).
  The title menu and the level menu read player 1 only, with their own copies of the same two calls (43A7h, 42ABh).
- **Mode**: E002h = 40h for 1 player, 60h for 2 players (bit 6 = a human plays; 0 is the demo), set by the title menu at 43CDh from a
  two byte table at 43EFh, the cursor being E042h. 1 player has a LEVEL menu (E044h), 2 players does not.
- **Randomness**: none outside the game's RAM. There is no `ld a,r` and no JIFFY read; what looks random comes from the frame counter E003h.
  So, unlike Soccer, no RNG patch is needed.
- **Self-writes (anti-copy)**: 4013h `ld (40EEh),a` once at start-up (a RET over a DJNZ) and 4052h `ld (40F8h),hl` (0000h over a JP operand),
  4 times. Ignored by a cartridge, harmful in a RAM image: NOPed. Measured with write watches over 2 x 5 minutes of random play, 1 and 2
  players: **no other write** in 4000h-7FFFh, 8000h-DFFFh or E400h-F37Fh.
- **Footprint**: the game writes only E000h-E3FFh; the stack goes down to E3BAh at the sampled points. Nothing is read from 8000h-DFFFh or
  from E400h up, so no ROM mirror is needed in page 2, and the stub (C100h) and the transport (C500h) have the memory to themselves.
- **Game state for the desync check**: writes concentrate in E000h-E1BFh (scene, pads, ball, paddles, scores); E1C0h-E3FFh is stack and idle.
  The engine checksums E000h-E1FFh every 32 frames.

## 2. The 11 patches (`profiles/pingpong/rebuild.py`)

| CPU | Original | Replacement | Why |
|---|---|---|---|
| 4013h | `ld (40EEh),a` | NOP x3 | anti-copy self-write |
| 4052h | `ld (40F8h),hl` | NOP x3 | anti-copy self-write |
| 401Dh | `call 5195h` | `call PN_IRQ` | sound tick per interrupt: only counted; the stub ticks the driver once per frame |
| 404Ah | `call m,5195h` | `call m,PN_IRQ` | the catch-up tick, same |
| 4033h | `call 47E3h` | `call tickSite` | TICK site: `PN_TICK` (the exchange), then the game's own reader |
| 4075h | `4019h` | XIRQ | H.KEYI hook goes through the transport, which jumps to 4019h |
| 47E6h | `call 4800h; ld d,a; call 4812h; or d` | `call key1`, NOPs | player 1's pad = `PN_P1` |
| 4845h | `call 4802h; ld d,a; call 4852h; or d` | `call key2`, NOPs | player 2's pad = `PN_P2` |
| 42ABh, 43A7h | same as 47E6h | `call key1`, NOPs | the two menus follow player 1's pad |
| 43CDh | `ld (E002h),a` | `call forceTwo` | online both title choices are the 2 player game |

Glue (`src/glue.asm`): `rdLocal` = the hardware read of 47E6h (joystick 1 + cursor keys/space), whichever seat; the engine puts it in `PN_P1` on
the inviter's machine and `PN_P2` on the guest's, and both machines see the same two bytes for every frame.
The inviter is therefore always the player on the pad of player 1, and the guest on the pad of player 2. The menus are the inviter's: the
guest watches the title and presses nothing.

## 3. Tests

Rig: two Canon V-25 + MSXPi, two stock servers relaying over UDP on localhost (`PINGPONG_ROM=<dump> sh run_pingpong.sh <lag_ms> <loss_%> <frames> <jitter_ms>`).
The engine's own scripted pad table is too tame for this game (nobody ever serves, so nobody scores), so the test stub (`rebuild.py --test-gpf`,
glue define `TESTPADS`) feeds each seat a seeded pseudo-random pad held 12 frames; the game then really plays: rallies, points, deuce, game over.
`cmp_pair.py` compares the two traces frame by frame (scene, E002h, both point counters E054h/E057h, a hash of E000h-E1FFh).
`POKEPTS`, `POKEF`, `EXITKEY` are available as in the other rigs.

| Run | Result |
|---|---|
| 50 ms lag, 20 ms jitter, 8 % loss, 5000 frames (scripted table, title and serve only) | IDENTICAL, delay 6, no desync |
| 26000 frames (scripted table), 30 ms lag, 5 % loss | IDENTICAL, delay 4, no desync |
| **random pads, 40 ms lag, 15 ms jitter, 5 % loss, 40000 frames (11 min of play)** | **IDENTICAL**, delay 5, no desync, 0 foreign writes to C100h-C5FFh; scenes 0, 1, 3, 4, 5, 6, 7 (a game played to its end, game over, back to the title); about 1500 packets dropped per server, 0 bad checksums |

Footprint and read tests (cartridge in openMSX): `software/Client/tests/soccernet/pingpong_debug/` (`footprint.tcl`, `ramblocks.tcl`, `reads.tcl`).

## 4. Status and what is not done

- Done: analysis, package (`profile.json`, stub, 11 patches), rig, determinism with lag and loss through the title, the match and the scene
  changes up to and including game over.
- Not verified: real hardware (the cost of the two polled transactions per frame is unmeasured, as for every game); the sound against the
  cartridge's by ear (the stub ticks the driver once per frame, so the music stretches during a network stall); the TCP/IP (UNAPI) path.
- Open questions for the user: the cursor of the title menu still starts on `1 PLAYER` (both choices play the 2 player game); changing it
  to start on `2 PLAYERS` is one more patch.
