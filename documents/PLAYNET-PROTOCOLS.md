# PLAYNET: specification and integration guide

Online two-player games for the MSX. Players meet in MSX Free Chat, and each MSX then runs the whole game in lockstep: only the two
players' input bytes cross the network. It works over an MSXPi (the Raspberry Pi does the networking) and over TCP/IP UNAPI cards with
no Pi at all, and a player on one can play a player on the other.

| | |
|---|---|
| Status | **Draft 1** (2026-10-19), for review. Nothing is frozen until the first release. |
| Design rationale | `documents/PLAYNET-DESIGN.md` (why things are the way they are) |
| Reference implementations | Python: `msxpi_netplay.py`, `msxpi_games.py` (Pi). MSX: `PLAYNET.COM`, `PLAYNET.OVL`, `MCHAT.COM` (planned, see the design) |
| Package format it extends | `software/ROM-Patcher/FORMAT.md` (`msxpi-rom-patch`) |

This document has two parts:
- **Part I, the integration guide**, is for someone who wants to bring their own game to PLAYNET. It explains what a game needs, how to
  analyse it, and how to write its package. Two worked examples follow it.
- **Part II, the reference**, specifies every format and protocol byte by byte. It is what a second implementation must follow.

The key words **must**, **must not**, **should** and **may** are used in their usual specification sense.

---

# Part I: Integration guide

## 1. How PLAYNET runs a game

```
 MSX A                                   network                                   MSX B
 MCHAT  /play B soccer  ---------- MSXG over IRC (private messages) ---------->  MCHAT  /accept
        <------------------------- candidates (ip:port), GO --------------------
 MCHAT exits, types PLAYNET                                                      MCHAT exits, types PLAYNET
 PLAYNET: session, package, ROM -> RAM image, patches, save DOS area
          connect  <-------------- MSXNP over UDP: HELLO, PING, SETUP ------------> connect
          start the game
 game frames: TICK  <------------- MSXNP game packets, one or more a frame -------> TICK
 Ctrl+Shift+F5 / BYE / lost -> restore DOS area -> MCHAT again  (both machines)
```

- Both machines start the game from the same reset state. Every frame, each one reads its own player's input, sends it, and waits for
  the other player's input for that frame. Both then run the same frame with the same two inputs. If the game is deterministic, the two
  machines stay identical forever, without exchanging any game state.
- Inputs are sent a few frames ahead (the **input delay**, 2 to 6 frames, chosen from the measured round trip), so network latency
  becomes a constant small input lag instead of a stall.
- Menus work the same way: both players' inputs go through the same readers, so a choice made by either player happens on both machines.
- **Your game is never modified on disk and never distributed.** The player supplies their own ROM file. PLAYNET checks that it is
  exactly the dump your package was written for, copies it to RAM, and applies your patches to the RAM copy.

What you supply as an integrator is a **package**: a `profile.json`, the source of a small piece of Z80 glue, and the built glue binary.
Everything else (chat, invitations, NAT traversal, transport, lockstep engine, loader, return to the chat) is PLAYNET's.

## 2. Is my game suitable?

A game is a good candidate if all of these hold. Section 4 shows how to check each one.

| # | Requirement | Why |
|---|---|---|
| R1 | A plain 16 KB or 32 KB cartridge ROM, or (PLAYNET 3) a MegaROM of 8 KB banks with a mapper the stub can emulate (7.3; Konami SCC today) | The RAM copy sits in pages 1-2, or in memory mapper segments |
| R2 | It runs from RAM once its writes to its own ROM area are neutralised. | A cartridge ignores those writes; RAM does not |
| R3 | Two players, playing at the same time or taking turns. Each player's input fits in **1 to 4 bytes a frame** (the game's input width: a joystick is 1, two paddles or a mouse with buttons 2-3). | Those bytes are all that crosses the network |
| R4 | There is one point in each game frame, before the game uses the inputs, where you can call PLAYNET's `TICK`. | The lockstep exchange happens there |
| R5 | It is **deterministic**: given the same inputs from reset, it does the same thing. See the checklist in 4.5. | Otherwise the machines drift apart |
| R6 | Its interrupt handler tolerates being entered while a frame is still running (most Konami games have a busy flag). | `TICK` waits with interrupts enabled |
| R7 | About **1 KB of RAM in page 3** that the game never writes, for the stub and the transport. | They live beside the game |
| R8 | For TCP/IP UNAPI players, the game should not write `C000h-DFFFh`. If it does, the package is still valid, but PLAYNET refuses to start when the TCP/IP stack's page-3 code sits in that range. | InterNestor Lite and the UNAPI RAM helper live in page 3 |
| R9 | The game does not need the disk, the clock chip or other hardware that differs between the two machines while it runs. | Both machines must see the same world |
| R10 | The game does not use Ctrl+Shift+F5 itself. | That combination ends a PLAYNET game on both machines, for every game |

50 Hz and 60 Hz machines can play each other. The game runs at the pace of the slower one.

## 3. What you write

| Piece | What it is | Who runs it |
|---|---|---|
| `profile.json` | ROM identification, layout, byte patches with expected bytes, and the `netplay` section (Part II, 7) | PLAYNET's tools and loader |
| `src/glue.asm` | Your game's side of the stub: which routine reads the local input, where the sound driver ticks, which RAM to checksum, and the small entry points your patches call. It is assembled together with PLAYNET's shared lockstep engine. | The MSX, during the game |
| `rebuild.py` | Builds `assets/stub.bin` from the engine and your glue, and writes its SHA-256 into `profile.json` (as the ROM-Patcher music packages do) | You, at build time |
| `README.md` | Which dump, what was patched and why, what was tested | Reviewers |

The package directory is `software/ROM-Patcher/profiles/<game-id>/`. Compiling it gives `<GAME-ID>.GPF`, the file players install.

## 4. Analysing a game, step by step

Use a disassembly and openMSX's debugger (breakpoints, memory watches). Both worked examples (sections 5 and 6) follow these steps.

### 4.1 Identify the dump

Record the size, CRC-32 and SHA-256 of the ROM file, and the name players usually give it (8.3, for example `SOCCER.ROM`). A package
accepts exactly one dump. Another revision of the same game needs its own package.

### 4.2 Make it run from RAM

Look for writes into `4000h-BFFFh`: anti-copy checks and mapper-style writes. On a cartridge they hit ROM and do nothing; in RAM they change
the program. Patch each one into NOPs (expected bytes = the original instruction). **Test:** copy the image to RAM, run it for several minutes
through a full game, and compare the RAM image with the ROM. Only your patched bytes may differ.

### 4.3 Find the frame

Most cartridges of this era install their interrupt handler during INIT:

```
ld a,0C3h / ld (0FD9Ah),a / ld hl,HANDLER / ld (0FD9Bh),hl      ; H.KEYI = JP HANDLER
```

Record:
- the address of the `ld hl,HANDLER` operand (your package patches it so PLAYNET's interrupt entry runs first; PLAYNET then jumps to `HANDLER`),
- `HANDLER` itself (`netplay.irq_handler`),
- the busy flag that stops the handler from re-entering while a frame is running (R6).

### 4.4 Find the inputs and the TICK site

Find every routine that reads the joystick or keyboard (BIOS `GTSTCK`/`GTTRIG`/`SNSMAT`/`RDPSG`, or `PSG` registers 14/15 directly):
- **The TICK site** is the first input read of each frame, before the game logic. Patch that call to your glue's `tick` entry. It must run
  exactly once per game frame on both machines.
- **Every other read in the same frame** is patched to return the cached value for that player (`PN_P1`/`PN_P2`), never to read the hardware again.
- Decide which player is "local" for each seat. Seat 0 (the player who sent the invitation) plays as player 1, and seat 1 as player 2,
  unless your glue maps them differently.
- **Games where players take turns** with shared controls: the glue returns the byte of the player whose turn it is, using the game's own
  "current player" variable.

**Choose the input width** (`netplay.input_bytes`, 1-4): the number of bytes that fully describe one player's input for one frame.
- A joystick or the cursor keys with one or two buttons fit in 1 byte.
- A game that reads separate values gets one byte each, for example:
  - a paddle position (`GTPDL`) plus its button: 2 bytes,
  - a mouse or trackball (dx, dy, buttons): 3 bytes,
  - a joystick plus a keyboard row used for extra commands: 2 bytes.
- Choose the smallest width that works: each extra byte adds 8 bytes to every packet (11.1).
- Analogue readings such as `GTPDL` are timing loops: read them once, in `G_READ_LOCAL`, never again in the same frame.

The input bytes are whatever your game's readers return, as long as the game derives everything from them. If the reader also stores edge
bits ("newly pressed") in RAM, call the game's own reader for the local player and patch the derived state for the remote player too, or
keep the derived state in the cached readers.

### 4.5 Make it deterministic

Go through this checklist. Each item found becomes a patch or a piece of glue.

| Source of drift | What to look for | Usual fix |
|---|---|---|
| The R register | `ld a,r` (`ED 5F`) | Call a glue entry that derives the value from the game's frame counter or from `PN_FRAME` |
| Sound ticked per interrupt | The sound driver called from the handler, and called again when an interrupt is pending after the frame (`call m,...`) | Patch both calls to `PN_IRQ` (keep the `call m,`), which only counts interrupts, and name the driver in `G_SOUND_TICK`. The engine ticks the driver after the exchange as many times as player 1's machine counted interrupts in its last frame (9.2), so the music keeps the original's tempo and both machines tick it the same number of times. Do not tick it per interrupt: games read the driver's state (Soccer waits for a jingle to end), so that would desync. |
| Interrupt counters | Reads of `JIFFY` (`FC9Eh`), `INTCNT`, or the game's own interrupt counter used for anything but timing the display | Use the frame counter instead |
| VDP status timing | Loops that poll the VDP status and count iterations, or sprite collision/5th-sprite flags used in game logic | Usually deterministic (same VRAM, same frame), but check them in the two-node test |
| Uninitialised RAM | Reads of RAM the game never clears | Clear it in a patch or in the glue's init |
| Hardware that differs | The clock chip, `MSX-MUSIC` detection, machine type, keyboard layout | Patch to a fixed answer |
| Self-modifying code | Writes into the code area | Same on both machines once in RAM. Only a problem if they hit your patches. |

**Choose a checksum region:** a few hundred bytes that summarise the game state (player and ball positions, score). Every 32 frames
both machines compare their checksums, so a drift is reported within a second of happening (`G_CHECK_ADDR`, `G_CHECK_LEN`).

### 4.6 Measure the RAM footprint

Set write watches on all of `C000h-F37Fh` and play through the title, the demo, the set-up screens and **a full match**. Measurements over
only part of the game have been wrong before. Record:
- every range the game writes (`netplay.game_ram`), including its RAM clears,
- the lowest address its stack reaches (the stack is game RAM too),
- the free ranges. The stub and the transport area go in one of them.

The **transport area** is 512 bytes (`TRANSPORT_AREA_MIN`) in page 3, outside `game_ram` and the stub, and its end must lie below MSX-DOS's
TPA top with a TCP/IP stack loaded: C806h on a machine with a drive of its own, D406h on MSX-DOS 1 over the MSXPi, D706h on Nextor (10.2).
One area serves every link: the profile never names a link or a transport. `build_games.py` prints a note for each measured set-up
where the area does not fit; Soccer, Ping Pong and Yie Ar (C500h) fit them all.

If a RAM clear covers the only free space, shorten it with a patch (the Soccer package does this) and measure again.

### 4.7 Write the glue

Your glue is assembled with PLAYNET's engine (`software/Client/src/playnet/engine/`, Part II, 9.3). It defines a few symbols and the
entry points your patches call:

```
G_INPUT_BYTES:  EQU  1          ; = netplay.input_bytes
G_READ_LOCAL:   EQU  48B9h      ; routine: A = the local player's input byte (1-byte games, see 9.3)
G_SOUND_TICK:   EQU  4F25h      ; the sound driver: the engine ticks it T times a frame (0 = none)
G_CHECK_ADDR:   EQU  0E100h     ; desync checksum region
G_CHECK_LEN:    EQU  0200h
        INCLUDE "playnet_engine.asm"   ; ORG = netplay.stub.load, TRANSPORT = netplay.transport_area.address
; entries the patches call
pad1t:  call PN_TICK : ld a,(PN_P1) : ret      ; at the TICK site
pad1c:  ld a,(PN_P1) : ret
pad2c:  ld a,(PN_P2) : ret
rng1:   ld a,(FRAME) : rra : ret               ; replaces "ld a,r : rra"
```

With more than one input byte, `G_READ_LOCAL` fills a buffer instead of returning A, and the entries read the cached arrays:

```
G_INPUT_BYTES:  EQU  2          ; paddle position + button
G_READ_LOCAL:   EQU  readPad    ; routine: fill (HL) with G_INPUT_BYTES bytes
readPad: push hl : ld a,1 : call GTPDL : pop hl : ld (hl),a : inc hl : push hl : ld a,1 : call GTTRIG : pop hl : ld (hl),a : ret
paddle2: ld a,(PN_P2+0) : ret                  ; patched over the game's own GTPDL call for player 2
button2: ld a,(PN_P2+1) : ret
```

The engine owns the lockstep exchange, the stall, the input delay and the desync check. Your glue must not call the transport directly.

### 4.8 Write `profile.json`

Patches are written as **file offsets** with the **expected original bytes** (for a ROM at 4000h, file offset = CPU address - 4000h).
The `netplay` section says where the stub goes and what PLAYNET needs. See Part II, 7, and the complete example in section 5.
`netplay.requires` lists what the game needs from the machine (today `mapper-ram`), never a link.

### 4.9 Test

1. `python patch_rom.py --profile profiles/<id>/profile.json --gpf <ID>.GPF ROM` validates the package against your ROM, checks every
   expected byte and writes the GPF.
2. **Install the rig's ROM**: openMSX must load the branch's 32 KB `software/target/msxpi32k.rom`, installed as
   `Documents/openMSX/share/systemroms/extensions/msxpibios.rom` (not `target/msxpibios.rom`, its 16 KB lower half). Every runner starts
   with `rig_preflight.py`, which stops with the install command when it is not.
3. **Scripted pair on every link** (`software/Client/tests/soccernet/run_native.sh`, `run_pingpong.sh`, `run_yiear.sh`,
   `run_salamander.sh`): build the stub with scripted inputs (`-DSCRIPTED`) and run two openMSX instances. Compare the two machines frame
   by frame, with the same GPF on each link: link 0 (both on the MSXPi), link 1 (`SCENARIO=mixed BOTH=1`, both over TCP/IP), link 2
   (`BOTH=1 HYBRID=1`, the game's packets through the MSXPi) and a mixed pair (`SCENARIO=mixed`, one on the MSXPi, one over TCP/IP).
   Then repeat with lag, jitter and packet loss.
4. **Through the chat**: invite, play, Ctrl+Shift+F5, and check that both machines return to the chat, on the MSXPi (`SCENARIO=chat`) and
   over TCP/IP (`SCENARIO=tcp`, with and without `GAMELINK1=1`).
5. **Real hardware**, when you can.

A package is accepted when the scripted pair stays identical over at least 3000 frames (through a full match), with 50 ms lag, 20 ms
jitter and 8 % loss, and no desync is reported.

### 4.10 Publish

Open a pull request that adds `profiles/<id>/` (no ROM data in it), the compiled GPF under `software/target/games/`, and its line in
`index.txt`. `python software/ROM-Patcher/build_games.py` writes both, and `--check` (run by `tests/test_gpf.py`) fails when the
folder is out of date. `tests/test_profiles.py` fails when the profile's engine copy differs from `software/Client/src/playnet/engine/` or
its published `stub.bin` is not what `rebuild.py` makes. On a Pi, `update.sh` fetches `index.txt` and then only the listed GPFs whose SHA-256 changed. It checks each
file and replaces it whole, and never touches unlisted files, so a player's own `<ID>.GPF` in `games/` survives. The player-facing
instructions are in `software/target/games/README.md`. Any change to the package changes its CRC. Players on the old version are then told to update instead of being allowed
into a game that would drift.

---

## 5. Worked example: Konami's Soccer (complete)

| | |
|---|---|
| Dump | `SOCCER.ROM`, 32768 bytes, CRC-32 `74BC8295`, SHA-256 `b9536809a1784afb2e49a43d80ba9c6c8c15cd31ecbd6c284e9bf62c6927dcd4` |
| Game id / roles | `soccer` / `H` (seat 0, player 1), `C` (seat 1, player 2) |
| Image | plain, base 4000h, 32 KB |
| Frame | INIT 4070h installs H.KEYI at 4090h: `ld hl,402Eh` (operand at 4096h). Handler 402Eh. Busy flag E005h bit 0. |
| Inputs | `lee_los_mandos` 4896h calls player 1 (48B9h) and player 2 (48F2h) readers once per frame; held/new bytes at E006h-E009h. Two more reads at 4564h/4569h. |
| Frame counter | E003h (incremented once per frame) |
| Game RAM | E000h-F37Fh cleared at INIT and from E0E0h at each match; stack from F380h down to F200h (measured over a full match). D500h-D5FFh is written at start-up. |
| Stub and transport | C100h-C5FFh, which the game never writes (measured across title, demo, set-up and a full match; the area C000h-D50Ah stays untouched): stub from C100h (at most 1024 bytes), MSXPi transport at C500h (256 bytes). PLAYNET's trampoline lives at C000h. No game RAM is cleared or shortened. |
| Checksum region | E100h-E2FFh (players and ball) |

Patch table (file offset = CPU - 4000h; `T` = address of the transport vector, C500h; `S.x` = glue entry `x`):

| CPU | Offset | Expected | Replacement | Reason |
|---|---|---|---|---|
| 4028h | 0028h | `22 0A 41` | `00 00 00` | anti-copy write `ld (410Ah),hl` |
| 4056h | 0056h | `22 16 41` | `00 00 00` | anti-copy write `ld (4116h),hl` |
| 40C3h | 00C3h | `CB B6` | `00 00` | `res 6,(hl)` on the VDP R1 template (black screen in RAM) |
| 4032h | 0032h | `CD 25 4F` | `CD S.PN_IRQ` | sound tick per interrupt -> count the interrupt |
| 404Eh | 004Eh | `FC 25 4F` | `FC S.PN_IRQ` | catch-up sound tick -> count it |
| 4096h | 0096h | `2E 40` | `T+6` | H.KEYI -> PLAYNET's interrupt entry (`XIRQ`), which jumps to 402Eh |
| 4565h | 0565h | `B9 48` | `S.pad1c` | cached player 1 |
| 456Ah | 056Ah | `F2 48` | `S.pad2c` | cached player 2 |
| 4897h | 0897h | `B9 48` | `S.pad1t` | **TICK site**: exchange, then player 1 |
| 48ADh | 08ADh | `F2 48` | `S.pad2c` | cached player 2 |
| B006h | 7006h | `ED 5F 1F` | `CD S.rng1` | `ld a,r : rra` -> frame counter |
| B028h | 7028h | `ED 5F E6 06` | `CD S.rng2 00` | `ld a,r : and 6` -> frame counter |

Glue: `G_READ_LOCAL = 48B9h` (the player-1 reader, which also reads the cursor keys and space), `G_SOUND_TICK = 4F25h`, `G_CHECK_ADDR = E100h`,
`G_CHECK_LEN = 200h`, and the five entries above. Measured results: see `documents/SOCCERNET-NETPLAY.md`.

## 6. Worked example: Yie Ar Kung-Fu (a one-player game made two-player)

The second worked example shows what a package can do beyond networking a game: the MSX Yie Ar Kung-Fu is a **one-player** game, and
its package adds a play-mode screen with three modes. The design and the measurements are in `documents/YIEAR-DESIGN.md`, the state of
the work in `documents/HANDOVER-yiear.md`; the package is `software/ROM-Patcher/profiles/yiear/`.

| | |
|---|---|
| Dump | `KUNGFU.ROM` (Konami, RC-725), 16384 bytes, CRC-32 `8A12EC4F`, SHA-256 `644c78c7d20bb30802888b513b384cf0ce4f9d8b6fd490f30e6211ac92274848` |
| Game id / roles | `yiear` / `P1` (seat 0, player 1), `P2` (seat 1, player 2) |
| Image | plain, base 4000h, output 32 KB: the ROM at 4000h-7FFFh, the **extension** asset at A000h (layout destination 6000h), 8000h-9FFFh fill |
| Frame | INIT 4010h installs H.KEYI: `ld hl,4043h` (operand at 4019h). Handler 4043h: `call RDVDP / di / call 7C5Ch` (sound) / busy flag E006h bit 0 / `ei / call 4522h` (input) / `call 407Bh` (frame) / `call RDVDP / di / call m,7C5Ch / ei`: the same Konami structure as Soccer |
| Frame counter | E003h (`inc (hl)` at 407Eh) |
| Inputs | **One** reader, 4522h: joystick port 1 or-ed with keyboard rows 7 and 8, then (452Bh) the demo override while E002h bit 6 = 0 and the edge logic (E00Ah held, E009h new). A second reader, 4583h, reads the hardware again on the title, demo and game-over screens. No port-2 read exists. |
| Determinism | no `ld a,r`, no `JIFFY`; randomness from a rotating register in game RAM (6D2Ch) and the frame counter |
| Game RAM | E000h-E401h (INIT clears E000h-E3FFh, SP = E400h, 53C5h writes E400h-E401h). Measured over 15 emulated minutes through all five opponents, four levels and the bonus stages: nothing else in C000h-F37Fh, nothing in 8000h-BFFFh, no write into the ROM area. `game_ram` = D500h-D5FFh (as Soccer) and E000h-E4FFh (room for the extension's two RAM bytes at E481h). |
| Stub and transport | as Soccer: stub C100h (at most 1024 bytes; 804 used), transport C500h (512) |
| Checksum region | E100h-E2FFh (Oolong, the opponent, the projectiles) |

Patch table (`T` = C500h; `S.x` = a stub entry, `X.x` = an extension entry):

| CPU | Offset | Expected | Replacement | Reason |
|---|---|---|---|---|
| 4019h | 0019h | `43 40` | `T+6` | H.KEYI -> `XIRQ`, which jumps to 4043h |
| 4047h | 0047h | `CD 5C 7C` | `CD S.PN_IRQ` | sound tick per interrupt -> count the interrupt |
| 4053h | 0053h | `CD 22 45` | `CD S.tickSite` | **TICK site**: `PN_TICK`, then 452Bh (the reader's second half) on the byte of the player who plays now |
| 4062h | 0062h | `FC 5C 7C` | `FC S.PN_IRQ` | catch-up sound tick -> count it |
| 409Ch | 009Ch | `CD 71 40` | `CD X.dispatch` | the state dispatch: the new state 9 (play-mode screen); the Turn and Versus texts |
| 4132h | 0132h | `CD A3 42` | `CD X.newGame` | new game: Turn gives both players the fresh progress block |
| 41DCh | 01DCh | `3A 50 E0` | `CD X.lifeLost` | a life is lost: Turn passes the turn; Versus: player 2 wins when REST is 0 |
| 4248h | 0248h | `3A 54 E0` | `CD X.bonus` | no bonus stage in Versus |
| 4284h | 0284h | `3A 56 E0` | `C3 X.vsWin` | fifth opponent beaten: in Versus player 1 wins |
| 4583h | 0583h | `CD 10 45 57 CD 3F 45 B2` | `CD S.key1 00 00 00 00 00` | the second reader: player 1's byte of this frame |
| 45ADh | 05ADh | `03` | `09` | the title's start goes to state 9 instead of 3 |
| 7338h | 3338h | `3A 81 E1` | `C3 X.vsDecide` | the shared decision point of all five opponents' AI: in Versus player 2 decides |

Glue: `G_READ_LOCAL = rdLocal` (the reader's first half, 4510h or-ed with 453Fh: **not** 4522h itself, which writes E009h/E00Ah and
applies the demo override, so running it on one machine only would make the two machines differ), `G_SOUND_TICK = 7C5Ch`,
`G_CHECK_ADDR = E100h`, `G_CHECK_LEN = 200h`.

What this example shows about the format:
- **No new field was needed**, even to add game modes. The new code is an ordinary asset placed by `layout` in the image's free page 2, and
  every hook into it is an ordinary patch with expected bytes.
- **State that both machines read must start equal on both.** INIT clears only E000h-E3FFh, so the mode, the current player and Turn's
  saved blocks live in the stub, whose bytes the loader copies; the extension keeps in RAM only bytes it writes before it reads them.
- **Menus are inputs like any other.** The play-mode screen reads only `PN_P1`, so only player 1 chooses, and both machines see the same
  choice on the same frame.
- **Taking over a CPU character** is possible when its AI chooses among shared action routines: one patch at the decision point gives the
  choice to `PN_P2`, and the opponent's animations, hit boxes and timers stay the game's.
- The GPF is 1830 bytes: it fits PLAYNET's 3 KB buffer.

---

# Part II: Reference

## 7. Package format: `msxpi-rom-patch` version 2

Version 2 is version 1 (`software/ROM-Patcher/FORMAT.md`) with the changes below. Tools must keep accepting version 1 packages, read as
packages with the music ABI.

### 7.1 Changes to the common fields

| Field | Version 2 rule |
|---|---|
| `version` | `2` |
| `abi` | New. A non-empty array of ABI names the package uses: `"msxpi-music-v1"`, `"msxpi-netplay-v1"`. |
| `music`, `sounds`, `defaults` | Required only when `abi` contains `msxpi-music-v1` |
| `netplay` | Required when `abi` contains `msxpi-netplay-v1` (7.2) |
| `source.crc32` | New, required with the netplay ABI. Integer, the CRC-32 (8.1) of the original ROM. The MSX identifies the dump with it; the Pi and PC tools still check `source.sha256`. |
| `source.file` | New, required with the netplay ABI. The 8.3 file name the loader opens by default, upper case, for example `"SOCCER.ROM"`. |
| `output.target` | New. `"rom-file"` (default, as in version 1: a new ROM is written for msxarch) or `"ram-image"` (PLAYNET: the image is built in RAM and never written) |
| `source`, `layout`, `patches`, `assets` | Unchanged. For `netplay.transport = "none"` there is no ROM: `source` is `null` and `layout`, `patches` and `assets` are empty. |

### 7.2 The `msxpi-netplay-v1` section

```json
"netplay": {
  "abi": "msxpi-netplay-v1",
  "game_id": "soccer",
  "title": "Konami's Soccer",
  "roles": ["H", "C"],
  "transport": "lockstep",
  "input_bytes": 1,
  "image": {"host": "plain", "base": 16384},
  "stub": {"asset": "stub", "load": 61440, "max": 564},
  "transport_area": {"address": 62004, "size": 204},
  "game_ram": [[57344, 61439], [62220, 62335]],
  "irq_handler": 16430,
  "start": "header-init",
  "min_playnet": 1
}
```

| Field | Type and rule |
|---|---|
| `abi` | `"msxpi-netplay-v1"` |
| `game_id` | 1-8 characters `a-z 0-9 -`. The id players type (`/play NICK soccer`), and in upper case the GPF file name. |
| `title` | 1-24 printable ASCII characters |
| `roles` | Two words of 1-8 characters `A-Z a-z 0-9`, for seat 0 (the inviter) and seat 1 |
| `transport` | `"lockstep"`: PLAYNET runs the game (everything below applies). `"none"`: the game is its own program and makes its own connection; only `command` applies. |
| `input_bytes` | 1-4: bytes of input per player per frame (the input width, 4.4). Default 1. |
| `command` | Only for `"none"`: the MSX-DOS command line: a template of at most 37 characters of `A-Z a-z 0-9 space . _ : / -` and the placeholders `{role}`, `{peer}`, `{token}`. The chat checks the line again after replacing them, because it must still fit the keyboard buffer. |
| `image.host` | `"plain"`, or `"mapper-ram"` for a MegaROM (7.3, PLAYNET 3) |
| `image.base` | CPU address of output offset 0: `16384` (4000h) or `32768` (8000h, for a 16 KB ROM that lives there). The output must end at or below BFFFh. |
| `stub.asset` | Name of the asset holding the built stub (engine + glue, Part II, 9) |
| `stub.load`, `stub.max` | Where it is copied, and the most bytes it may ever take. Must be in page 3 (`C000h-F37Fh`). |
| `transport_area` | Where PLAYNET installs the transport (10). `size` must be at least `TRANSPORT_AREA_MIN` = 512 (the largest transport plus the UNAPI buffer; `patch_rom.py` refuses less). In page 3, outside `game_ram` and the stub, and below the lowest MSX-DOS TPA top PLAYNET supports with a TCP/IP stack loaded, because the UNAPI and hybrid transports are written into MSX-DOS's page 3 too (`tcpFootprint` checks it at run time; the limit is in 10.2). One area serves every link: no profile names a link or a transport. |
| `game_ram` | Inclusive `[low, high]` ranges of every address the game writes, including its stack. Must not overlap the stub or the transport area. |
| `irq_handler` | The game's interrupt handler; `XIRQ` ends by jumping there |
| `start` | `"header-init"` (jump to the INIT address in the image's `AB` header, as the BIOS would) or a CPU address |
| `min_playnet` | The oldest PLAYNET release that may run this package (integer). Older releases refuse it with "update PLAYNET". |
| `requires` | List of what the game needs from the machine or from PLAYNET; today only `"mapper-ram"` (required when `image.host` is `mapper-ram`). Never a link or a transport. Optional, default `[]`. |

Validation (tools and the MSX loader): all addresses in range; output size 16384 or 32768 for `plain`; every layout and patch range
inside its buffer; patches non-overlapping with equal expected/replacement lengths; stub and transport area disjoint from each other,
from `game_ram`, from the image, and inside page 3; the stub asset no longer than `stub.max`.

### 7.3 Image host `mapper-ram` (PLAYNET 3)

A MegaROM of 8 KB banks runs from memory mapper segments. The MSX mapper switches 16 KB and the cartridge 8 KB, so a segment holds
a **pair** of banks, the two windows of one page. The package patches every bank-register write of the game into a call to the
stub's bank engine (`software/Client/src/playnet/engine/mapper_k8.asm`), which maps the segment holding the new pair, or builds it
first. Design and measurements: `documents/SALAMANDER-DESIGN.md`, section 5. First package: `profiles/salamander`.

```json
"image": {"host": "mapper-ram", "mapper": "konami-scc", "bank_size": 8192, "banks": 16, "block": 53909,
          "start_banks": [0, 1, 2, 3], "page1_pairs": [[0, 1], [0, 4]], "page2_pairs": [[2, 3], [5, 6], [2, 12]],
          "pinned": [2, 2], "min_segments": 22}
```

| Field | Rule |
|---|---|
| `mapper` | `"konami-scc"` (1) or `"ascii8"` (2, 1942); the bank engine works for any 8 KB mapper, the patches decide which registers) |
| `bank_size` | `8192` |
| `banks` | 2-64, a power of two. The ROM (`source.size`, `output.size`) is `banks` x 8 KB, and the layout is the identity: one entry, the whole input at 0. |
| `block` | Address of the bank engine's block (`MK_BLOCK`) inside the stub. The loader fills it. Its first 4 bytes are the engine's version (1), the bank mask, and the room of its two tables. |
| `start_banks` | The banks of the four windows when the game starts (W0 4000h, W1 6000h, W2 8000h, W3 A000h) |
| `page1_pairs`, `page2_pairs` | The pairs to build, `[low window's bank, high window's bank]`, most useful first. At most 60 per page. |
| `pinned` | How many of each list are never replaced. Each bank's home is the first pinned pair holding it (page 1's list first, the low half first); every bank needs one. The start pairs must be pinned. |
| `min_segments` | The fewest segments the loader accepts (at least the pinned pairs plus one spare per page). Below it the game would pause too often: PLAYNET refuses with "Not enough memory". |

Patch offsets are ROM offsets (bank x 8 KB + offset in the bank), and a patch may not cross a bank. `netplay.irq_handler` and `start`
lie in 4000h-BFFFh.

The loader: takes up to every pair plus one spare per page in segments (the mapper support routines' user segments, or on MSX-DOS 1
the segments above the TPA's four), fills table 1 with every page-1 pair and a spare, table 2 with as many page-2 pairs as memory
allows (and a spare when all fit), reads each bank into its home, applies the patches there, copies the homes into the other pairs,
and maps the start pairs just before INIT. Pages 1 and 2 must be RAM of the same mapper. On the way back (14) it maps MSX-DOS's own
segments again first. The segments only ever hold ROM bytes, so how many a machine has changes the speed, never the game: two
machines with different mappers stay in lockstep. PLAYNET 3 refuses a `mapper-ram` game over TCP/IP (the UNAPI transport puts page
2 back from its own record, which the bank engine would make wrong).

**Trust.** Patches and assets are Z80 code that runs with full control of the machine. Validation protects against a corrupt or
mismatched package, not against a malicious one. Install packages only from the official index or from people you trust.

## 8. GPF: the compiled package

A GPF file is what the MSX reads. `patch_rom.py --gpf` produces it from a version 2 package with the netplay ABI. The Pi serves it from
`games/`, and on an MSX without a Pi it is read from `GAMES\` (MSX-DOS2/Nextor) or the current directory (MSX-DOS1).

### 8.1 Conventions

- Integers are little-endian. Addresses are 16-bit CPU addresses. Offsets and sizes are 32-bit, so MegaROM images fit later.
- CRC-32 is the IEEE 802.3 polynomial as in zlib (`zlib.crc32`): reflected, initial value `FFFFFFFFh`, final XOR `FFFFFFFFh`.
- Text fields are ASCII, padded with `00h`.
- The maximum GPF size for format 1 is 16 KB.

### 8.2 Layout

Header, 128 bytes:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `'GPF1'` |
| 4 | 1 | format = 1 |
| 5 | 1 | flags: bit 0 = transport `lockstep` (0 = `none`); bits 1-2 = image host (0 `plain`, 1 `mapper-ram`, which needs the `MAPPER` section) |
| 6 | 2 | body length (bytes after the header) |
| 8 | 4 | **profile hash**: CRC-32 of the whole file, computed with these 4 bytes set to 0 |
| 12 | 8 | game id |
| 20 | 24 | title |
| 44 | 8 | role of seat 0 |
| 52 | 8 | role of seat 1 |
| 60 | 38 | command (transport `none` only), zero-terminated |
| 98 | 1 | `min_playnet` |
| 99 | 1 | `requires`: what the game needs, one bit each: bit 0 `mapper-ram` (a memory mapper for the image). Never a link: one package serves every link. A bit this PLAYNET does not know: refused ("This game needs a newer PLAYNET") |
| 100 | 28 | reserved, 0 |

Body: a list of sections, each `type (1), length (2), payload`, ending with type 0 and length 0. Readers must skip unknown section
types. Sections appear in the order below; each appears at most once, except `ASSET`.

| Type | Section | Payload |
|---|---|---|
| 1 | `SOURCE` | size (4), CRC-32 (4), file name (12, for example `SOCCER.ROM`) |
| 2 | `NETPLAY` | image base (2), input bytes (1), stub asset index (1), stub load (2), stub max (2), transport area (2), transport size (2), IRQ handler (2), start (2, `0000h` = header INIT), number of RAM ranges (1), then that many (low (2), high (2)) |
| 3 | `LAYOUT` | output size (4), fill byte (1), count (1), then count x (source (1): `FFh` = the ROM, else asset index; source offset (4); size (4); destination offset (4)) |
| 4 | `PATCH` | count (2), then count x (output offset (4), length (1), expected bytes, replacement bytes) |
| 5 | `ASSET` | the bytes of one asset. Assets are numbered 0, 1, ... in file order. |
| 6 | `MAPPER` | (image host 1 only) type (1, 1 = Konami SCC, 2 = ASCII8), bank size in KB (1, = 8), banks (1), block address (2), the 4 start banks (4), pinned page-1 pairs (1), pinned page-2 pairs (1), min segments (1), page-1 pairs n1 (1), page-2 pairs n2 (1), then n1 + n2 pairs of 2 bytes (low bank, high bank). `NETPLAY`'s image base is 4000h. |

The profile hash is what players compare: it appears in invitations (12), in the peer handshake (11.3) and in the session record (13).
Because the stub is an asset inside the file, the hash covers the engine and the glue too.

### 8.3 Loading (what an implementation does)

1. Check the magic, the format, the body length and the hash. Refuse with a clear message if the file is newer than this PLAYNET (`min_playnet`).
2. Open the ROM: `SOURCE` file name, size and CRC-32 must match.
3. Build the output with `LAYOUT` (fill, then copies), then apply each `PATCH`: **the expected bytes must be found exactly**, or the load stops.
4. Check the `NETPLAY` rules from 7.2 again. A file from a disk is not trusted more than one from the Pi.
5. Copy the stub asset to `stub load`, and write its header fields (9.1).

## 9. The stub

The stub is the shared lockstep engine assembled with the game's glue, one binary per game. It lives at `stub.load` while the game runs.

### 9.1 Header (first 5 bytes of the stub asset)

| Offset | Field | Written by |
|---|---|---|
| 0 | stub ABI version = 2 | the build |
| 1 | seat (0 or 1) | the loader |
| 2 | input delay in frames (2-7) | the loader, from the handshake |
| 3 | flags: bit 0 = end the game on a desync (1 in release builds, 0 in test builds; see Appendix B, point 2) | the build |
| 4 | K: a packet every K frames (1-3) | the loader, from the handshake (stub ABI 2) |

### 9.2 Rules for the engine and the glue

- `PN_TICK` is called exactly once per game frame, at the same point on both machines, before the game uses any input.
- `PN_TICK` may wait for the opponent's input. It enables interrupts while it waits.
- The stub calls the network only through the transport vector (10). It never touches I/O ports or slots itself.
- The stub's stack use, plus the transport's (at most 16 bytes), must stay inside what the `game_ram` measurement allowed for the stack.
- Sound: `PN_IRQ` counts interrupts. Each frame record carries, after its W input bytes, the number of interrupts its sender counted
  between its last two `PN_TICK`s. Frame F ticks `G_SOUND_TICK` T times, T = the count in player 1's record for F, limited to 1-8.
  Both machines use the same T, so the driver's state stays in lockstep; T follows player 1's real frame length, so the music keeps
  the original's tempo (measured on Soccer: 60 ticks a second, as the original, against 20-39 with one tick a frame). A network stall
  pauses the music instead of fast-forwarding it.
- The input width costs stub RAM: a frame record is W + 1 bytes. The rings take 16 x (2W + 3) bytes and the two packet buffers
  2 x (14 + 8W). That is 124 bytes for W = 1 and 268 bytes for W = 4. Plan `stub.max` accordingly.
- `PN_FRAME` counts game frames from 0 (8-bit, wrapping). Code that depends on "the first frame" must keep its own state, because the
  counter wraps every 256 frames.

### 9.3 Engine interface

Symbols the glue defines:

| Symbol | Meaning |
|---|---|
| `G_INPUT_BYTES` | The input width W, 1-4. Must equal `netplay.input_bytes`. |
| `G_READ_LOCAL` | Reads the local player's input once per frame. W = 1: returns the byte in A. W > 1: is called with HL = a W-byte buffer and fills it. It may clobber AF, BC, DE, HL. |
| `G_SOUND_TICK` | The sound driver. The engine calls it T times a frame (9.2), with interrupts disabled, after the exchange. `0` = none. |
| `G_CHECK_ADDR`, `G_CHECK_LEN` | Region checksummed every 32 frames (`G_CHECK_LEN` even, at most 512) |
| `ORG` | `stub.load` (the build sets it) |
| `TRANSPORT` | `transport_area.address` (the build sets it) |

Symbols the engine provides:

| Symbol | Meaning |
|---|---|
| `PN_TICK` | Runs one frame of the exchange. On return, `PN_P1` and `PN_P2` hold this frame's inputs. Preserves BC, DE, HL, IX, IY. |
| `PN_P1`, `PN_P2` | W bytes each, one after the other: the inputs of player 1 (seat 0) and player 2 (seat 1) for the current frame |
| `PN_FRAME` | Frame counter |
| `PN_END` | Ends the game: A = result code (13.2). Does not return. (An alias of the transport's `XEND`.) |

Built in to the engine: the exit key, **Ctrl+Shift+F5 for every game** (the same key as the ROM-Patcher games). The engine reads it
once per frame from the keyboard matrix (rows 6 and 7), calls `PN_END` with code 1, and makes the opponent end with code 2. There is
no per-game override: a game that needs this combination for itself is not a PLAYNET candidate (R10).

## 10. The transport vector

PLAYNET installs a transport at `transport_area`, relocated to that address. It starts with four entries:

| Offset | Entry | Contract |
|---|---|---|
| +0 | `XCHG` | In: HL = game packet to send (L = 14 + 8W bytes, 11.1), or 0; DE = an L-byte receive buffer. The loader tells the transport L when it installs it. Out: A = 0 nothing received, 1 a packet was stored at DE, 2 the opponent is gone (no news for 15 s), 3 the opponent left (B = their reason); E = the interrupts that were taken away from the game during the call (MSX-DOS's handler took them; always 0 on the MSXPi path), which the engine adds to its interrupt count. Bounded time. Returns with interrupts enabled. Clobbers AF, BC, DE, HL and the alternate set; preserves IX, IY. |
| +3 | `XEND` | In: A = result code. Tells the opponent (BYE), records the result, then restores MSX-DOS (14) or resets. Does not return. |
| +6 | `XIRQ` | Target of the game's H.KEYI hook. Ends by jumping to `irq_handler`. |
| +9 | reserved | `RET` |

What follows the vector is private to each transport and the loader that installs it (the generated include
`transport_msxpi.inc` gives the MSXPi transport's field offsets).

Two implementations exist:
- **MSXPi (native).** Each `XCHG` is one opcode-C9 transaction with the Pi (10.1). `XIRQ` is a plain `JP irq_handler`.
  It is 458 bytes (`software/Client/src/playnet/transport_msxpi.asm`); a game's `transport_area.size` must be at least that
  for PLAYNET to run it over the MSXPi.
- **UNAPI** (`software/Client/src/playnet/transport_unapi.asm`, `PLAYNET /T`). The game gets a **page-3 segment of its own**: the
  trampoline copies MSX-DOS's page 3 into a new segment and switches to it, so the game's RAM, its stack and the hooks it is given never
  touch MSX-DOS's. That matters because the TCP/IP stack keeps its state in MSX-DOS's work area inside a typical game's RAM (`RAMAD1-3`
  at F341h-F344h, F1A2h-F1C6h, F336h-F37Fh with InterNestor Lite on MSX-DOS 1: measured, PLAYNET-DESIGN.md 8a).
  `XCHG` switches page 3 back to MSX-DOS's segment (the transport is installed at the same address in both), maps the network
  engine's segment (`PLAYNET.OVL`) into page 2 and records it with `PUT_P2` (a RAM implementation's helper puts back the page-2
  segment `PUT_P2` recorded), runs it with interrupts on, and switches back. For a stack that runs from a timer routine (InterNestor Lite; any implementation in RAM, `/S1` forces it, `/S0` turns it off), the engine also calls MSX-DOS's H.TIMI hook itself with interrupts off and A = 80h, once per interrupt period of the game and not when an interrupt has already run it during a call (PLAYNET-TCPIP-PERFORMANCE.md 5.2). The transport reads MSX-DOS's `JIFFY` before and after the call; the difference is added to the game's tick counter and returned in E. Only
  registers cross a page-3 switch: packets go through the engine's I/O block in page 2. The engine's buffers for the UNAPI calls
  are the last 128 bytes of `transport_area` in MSX-DOS's page 3, and its stack is under MSX-DOS's TPA top: a RAM implementation maps
  its own segments into pages 1 and 2 while it runs. `XIRQ` (in the game's page 3 only) counts ticks, the engine's clock, and jumps
  to the game's handler; it never writes `JIFFY`, so games that read it see what they would see on a cartridge. It needs a
  `transport_area` of 512 bytes, inside the TPA (it is written into MSX-DOS's page 3 too), and two mapper segments: the engine's
  and the game's page 3. The transport is 346 bytes, plus the 128-byte buffer at +384 of the 512-byte area.
- **Hybrid** (`transport_hybrid.asm`, link 2). `XCHG` is the MSXPi transaction; every `KEEP_EVERY`th call (8) it also serves the chat
  connection through the overlay. It is 384 bytes, the whole of its 384-byte code space (`ASSERT` in the source).

Sizes today (`software/Client/src/playnet/build/`): MSXPi 458, UNAPI 346, hybrid 384 bytes; `transport_area` is 512.

### 10.1 MSXPi opcode C9 transaction

```
MSX -> Pi   C9, FLAGS, L, P[L], SUM              SUM = sum of P mod 256; L = 0 when no packet is sent
Pi  -> MSX  L, P[L], SUM                         a game packet (L = 22..46), or a DELTA (L = 6..19)
            00, 00                               nothing
            FF, 00                               the opponent is gone
            FE, REASON                           the opponent left (BYE)
            A0+STATE, DELAY, K                   when FLAGS bit 7 is set (K = 1 until ready)
```

| FLAGS bit | Meaning |
|---|---|
| 0 | send P to the opponent |
| 1 | return the oldest received game packet |
| 2 | P is a DELTA |
| 3 | the reply may be a DELTA: the MSX holds the last packet the Pi gave it |
| 5 | send BYE; L = 1 and P[0] = the result code |
| 6 | (re)start the session handshake |
| 7 | return the status instead |

STATE: 0 connecting, 1 ready (DELAY valid), 2 incompatible (different profile or protocol), 3 failed (no answer, timed out), 4 the
opponent left. The Pi relays game packets without looking inside them, so it does not need to know the game's input width. A bad SUM
means the packet part is lost; the transport tolerates loss. The MSX side bounds every wait (about 0.5 s) and
resets the link with `FFh` to port 56h on a timeout. The connect phase uses bits 6 and 7 from `PLAYNET.COM`, before the game starts.

**DELTA.** Every byte on the MSXPi link is a handshake with the Pi, and consecutive game packets repeat most of their 8 frame records.
A packet that **follows** the previous one in the same direction (same kind and W, F d = 1..3 frames later, d being the send interval
K, and its first 8 - d records that packet's last 8 - d) may travel as a DELTA: seq, F, the d new records (W + 1 bytes each), check
tag, check value: d(W + 1) + 4 bytes instead of 14 + 8W (7 instead of 30 for W = 2 and K = 1). The receiver rebuilds the packet from the previous one and handles it as if it had come in full; the Pi relays only
whole packets over UDP (11), so the peer protocol does not change.

- Replies: the Pi sends a DELTA only when the MSX set bit 3 and the packet follows the last one it gave that MSX. A reply of fewer
  than 22 bytes (the shortest full packet) is a DELTA; the receiver takes d from the F it carries. The MSX transport sets bit 3 while its receive buffer still holds the last packet it received (in full or
  rebuilt) and clears it after a bad SUM.
- From the MSX: the transport sends DELTAs only after the Pi has sent one (bit 2 means nothing to an older Pi, which never sends
  DELTAs either), and only for a packet 1-3 frames after the last one it sent. The engine builds every packet from one ring
  of frame records, so such a packet repeats the last one's records. The Pi drops a DELTA that does not follow the last packet it
  got from that MSX; the stub's resend (a full packet: same F) puts the two back in step.
- A link timeout clears both: the next packets go in full.

### 10.2 Where the transport area may be

The UNAPI and hybrid transports run in MSX-DOS's page 3 as well as the game's, at the same address, so `transport_area` + 512
(`TRANSPORT_AREA_MIN`) must lie below MSX-DOS's TPA top, the word at 0006h, with the TCP/IP stack loaded (the stack lowers it).
`tcpFootprint` in `PLAYNET.COM` checks this at run time and refuses with "The TCP/IP driver uses memory this game overwrites".
Measured with `software/Client/tests/soccernet/tpatop.sh` (TPATOP.COM before the stack, after MSR I / RAMHELPR I, after INL I), 2026-10-24:

| Set-up | Top before the stack | Top with the stack | Largest `transport_area` |
|---|---|---|---|
| MSX-DOS 1 on the MSXPi, no drive of its own (Canon V-25, ram2mb) + MSR + INL | D606h | **D406h** | D206h |
| the same, CTRL held while booting | DC06h | **DA06h** | D806h |
| MSX-DOS 1.8, the machine's own drive (Panasonic FS-A1WSX, ram4mb) + MSR + INL | C906h | **C806h** | C606h |
| the same, CTRL held while booting | D606h | **D406h** | D206h |
| Nextor (MegaFlashROM SCC+ SD) + RAMHELPR + INL | D706h | **D706h** | D506h |

Holding CTRL while MSX-DOS 1 boots leaves out the second drive and frees 1536 bytes (600h) on both machines.

The areas of Soccer, Ping Pong and Yie Ar Kung-Fu (C500h) fit every set-up. Salamander's (D000h) fits all but one: a machine with a
drive of its own booted without CTRL (C806h). Its game RAM is the whole of C000h-CFFFh, so no 512-byte window exists below C806h for any
package data to name. There PLAYNET refuses, before connecting, with "Restart the MSX holding CTRL (frees 1.5 KB), or use Nextor";
the MSXPi transport (link 0) needs no stack and is not affected. Measured on the emulator: Salamander on MSX-DOS 1 with the stack
loaded (D406h, the same top as the Panasonic with CTRL) passes the check and reaches "Connecting". `build_games.py` prints a note for
every package and measured set-up where the area does not fit (`patch_rom.TPA_TOPS`).

Could the transport be reworked to need less? Only the code between its two page-3 switches (about 80 bytes of code and data) has to
sit at the same address in both segments; the rest and the 128-byte buffer could live in MSX-DOS's memory alone. That would shrink
the requirement from `transport_area` + 512 to `transport_area` + 80. It would not help Salamander on the C806h machine: the address
must be free in the game's page 3 (Salamander: D000h or above) and TPA in MSX-DOS's, and everything above C806h there is MSX-DOS's
and the stack's own data. Not done; decision D-6 (owner, 2026-10-25): no DOS 2 requirement, hold CTRL or use Nextor.
The earlier figure of D406h under MSX-DOS 1 and D706h under Nextor (HANDOVER-salamander 4b) is confirmed; C806h, which the PChess
memory test recorded, is the drive-of-its-own machine without CTRL.

## 11. MSXNP: the peer protocol (UDP)

### 11.1 Datagrams

Every datagram starts with a **kind** byte: 1-6 = a control datagram, 10h = a game packet. Anything else, or a datagram whose length
does not match its kind, is dropped. STUN replies on the same socket are recognised first, by the magic cookie `2112A442h` at bytes 4-7
(and a length of 20 or more).

**Game packet, L = 14 + 8W bytes** (W = the game's input width, 1-4, so L = 22 to 46). It is built by the stub and relayed unchanged by
the transport:

| Byte | Field |
|---|---|
| 0 | kind = 10h |
| 1 | sequence number, incremented for every new packet (8-bit). A receiver drops a packet whose number equals the last one it accepted. |
| 2 | F, the sender's current frame |
| 3 | W, the input width. A packet with another W than the package's is dropped. |
| 4 ... 11+8W | the sender's records for frames F+D-7 ... F+D (D = the input delay), oldest first, W + 1 bytes each: the W input bytes, then the interrupt count (9.2) |
| 12+8W | check tag: a frame number with the low 5 bits zero, or FFh = no check |
| 13+8W | check value: the sender's checksum for that frame. Compared for equality only. |

Each packet repeats the last 8 frame records, so up to 7 consecutive lost packets are repaired by the next one. A packet goes out every K-th frame (K = 1..3, agreed in the handshake, 11.3);
the frames between call `XCHG` only while the remote input is missing. A machine waiting for
an input resends its last packet when 3 interrupts (about 50 ms) have passed since the last send. With W = 4 a packet is 46 bytes: the per-frame cost on the MSXPi link (one C9
transaction of L + 4 bytes each way) has to be measured on real hardware before such a package is accepted.

**Control datagram, 14 bytes**: type (1, the kind byte), version (1), nonce (4), a (4), b (4).

| Type | Name | a | b | Sent |
|---|---|---|---|---|
| 1 | HELLO | profile hash | K (bits 0-7), S (bits 8-15) of the sender's transport | every 200 ms while connecting |
| 2 | PING | ping number | 0 | by the leader, every 100 ms |
| 3 | PONG | the ping number | 0 | answer to a PING, in any state |
| 4 | SETUP | input delay | K, the agreed send interval | by the leader, every 200 ms until ACK |
| 5 | ACK | input delay | K, as received | answer to SETUP |
| 6 | BYE | result code (13.2) | 0 | 3 times, 100 ms apart, when a game ends |

`version` is the MSXNP protocol version, 2. `nonce` is a random 32-bit value chosen at each session start. It must differ between the two
machines, and must not come from a generator seeded identically on both. On the MSX, mix the R register, `JIFFY` and the local address.

### 11.2 Finding the opponent (NAT traversal)

1. Each side opens a UDP socket. On the MSX, it is the session's port (13), the same port `MCHAT` used for STUN.
2. Each side knows the other's **candidates** from the invitation: its LAN address and, when STUN answered, its public address.
3. Both sides send HELLO to every candidate at the same time. That opens the NAT mapping on both routers (hole punching).
4. Until the opponent is locked, accept datagrams only from candidate IP addresses (any port: a NAT may change it). The first datagram
   accepted while connecting **locks** the opponent's address and port. After that, only datagrams from that address count, and every
   send goes there only.
5. There is no relay. Behind symmetric or carrier-grade NAT the connection fails, and both players are told so.

STUN (RFC 5389): a 20-byte Binding Request from the game socket itself, to `stun.l.google.com:19302` by default, retried once. The answer's
XOR-MAPPED-ADDRESS (or MAPPED-ADDRESS) is the public candidate.

### 11.3 Session state machine

```
CONNECT --HELLO from the opponent--> (leader known) --leader: 8 PINGs, >= 4 PONGs--> SETUP --ACK or a game packet--> READY
   |  HELLO with another profile hash or version -> INCOMPATIBLE (answer later HELLOs, so the opponent learns it too)
   |  120 s without READY -> FAILED
READY --first game packet--> PLAYING --15 s with nothing from the opponent--> GONE
   |  60 s after READY without a game packet -> GONE                            PLAYING --BYE--> LEFT
```

- **Leader**: the side with the higher nonce. Equal nonces: both choose new ones and continue.
- **Input delay**, decided by the leader: take the round trips of the PINGs answered (at least 4, up to 64 PINGs), sort them, take element
  `int(0.9 x (n-1))` (milliseconds), and compute `ceil(rtt / 2 / 20) + 2 + (K - 1) + S`, clamped to 2..7 (the rings hold 16 frames and the records run up to 2D frames ahead, so D <= 7). An MSX measuring in jiffies converts with its
  own rate (50 or 60 Hz). The follower uses the leader's value.
- **K and S** (MSXNP 2): each side announces in HELLO the send interval K (1-3 frames) its transport wants and its service latency S (frames between
  a packet's arrival and the game seeing it): the MSXPi link 1 and 0, a software TCP/IP stack 2 and 1, a hardware one 1 and 0. The leader takes
  K = the larger K and S = the larger S, and sends K in SETUP (ACK echoes it). Both sides use the same K. With K = 2 each record is in 4 packets, so 3
  consecutive losses are repaired instead of 7.
- **SETUP/ACK**: the follower answers each SETUP with ACK and is READY. The leader is READY at the ACK, or at the first game packet from
  the follower.
- **Times**: connect 120 s; start (READY to the first game packet) 60 s; gone after 15 s with no datagram while playing.

## 12. MSXG: invitations over IRC

Private messages (`PRIVMSG nick :...`) between the two players' chat programs. They must never be shown as chat, and they are never sent
to a channel. Fields are separated by one space. Unknown verbs are ignored.

```
MSXG1 INVITE  <game_id> <profhash> <token>
MSXG1 ACCEPT  <token> <candidates>
MSXG1 GO      <token> <candidates>
MSXG1 DECLINE <token> <reason>
MSXG1 CANCEL  <token>
```

| Field | Format |
|---|---|
| `game_id` | as in 7.2 |
| `profhash` | the GPF profile hash, 8 lower-case hex digits |
| `token` | 8 lower-case hex digits, random, chosen by the inviter |
| `candidates` | up to 3 `a.b.c.d:port`, separated by commas, LAN first; `-` when the game's transport is `none` |
| `reason` | `busy`, `declined`, `unknown-game`, `profile` (different hash), `no-mapper` (a TCP/IP player without a memory mapper) |

Flow:
1. A sends INVITE and waits up to **120 s**.
2. B checks that it has the same game with the same hash and is not busy. Otherwise it sends DECLINE with the reason. The player answers
   `/accept` or `/decline`.
3. On accept, B opens its UDP socket, learns its candidates and sends ACCEPT.
4. A opens its socket, learns its candidates, sends GO, and is ready. B is ready when GO arrives.
5. Each side has **180 s** to start the game. Either side may CANCEL at any time before that. Messages with a token that is not the current
   one are ignored. One game at a time per player.

## 13. The session record

### 13.1 Layout

How the chat hands the game to `PLAYNET`. It is the same structure everywhere:
- on the Pi, `PLAYNET` reads the first 40 bytes with the MSXPi command `playnet session`,
- on TCP/IP, `MCHAT /t` writes `PLAYNET.SES` (256 bytes) in the current directory and leaves with `PLAYNET /T` typed. `PLAYNET /T`
  with no arguments reads it (it refuses a record whose link is not 1, whose state is not 0 or that has no candidate). When the game
  ends, or cannot start, `PLAYNET` writes state 2 and the result code (bytes 32-33) back into the file and types `MCHAT /T`, which
  reads them, reports the result, takes the IRC connection back and empties the file.

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `'PNS1'` |
| 4 | 4 | token (the 8 hex digits as 4 bytes) |
| 8 | 1 | seat: 0 = inviter, 1 = invitee |
| 9 | 1 | link: 0 = MSXPi, 1 = TCP/IP UNAPI, 2 = TCP/IP chat with the game's packets through the MSXPi (`transport_hybrid.asm`; no candidates, the Pi has the opponent from `playnet peers`) |
| 10 | 2 | local UDP port (TCP/IP only; 0 on MSXPi) |
| 12 | 4 | profile hash |
| 16 | 8 | game id, upper case, padded with spaces (= the GPF file name) |
| 24 | 8 | opponent's nick, truncated (display only) |
| 32 | 1 | state: 0 ready to start, 1 started, 2 finished |
| 33 | 1 | result code (13.2), valid when state = 2 |
| 34 | 6 | reserved, 0 |
| 40 | 1 | TCP/IP only: number of opponent candidates (0-3) |
| 41 | 18 | 3 x (IPv4 address 4, port 2) |
| 59 | 1 | IRC TCP connection number left open by `MCHAT /t` (FFh = none) |
| 60 | 17 | own nick, zero-terminated |
| 77 | 1 | number of rooms (0-3) |
| 78 | 72 | 3 x room name (24, zero-terminated) |
| 150 | 106 | reserved, 0 |

### 13.2 Result codes

| Code | Meaning |
|---|---|
| 0 | none yet |
| 1 | ended by this player (exit key) |
| 2 | ended by the opponent |
| 3 | connection lost |
| 4 | desync detected |
| 5 | could not connect (no answer, timed out) |
| 6 | incompatible (different game package or protocol) |
| 7 | cancelled before the start |
| 8 | ROM missing, or not the expected dump |
| 9 | not possible on this machine (no memory mapper for TCP/IP, not enough memory, or the TCP/IP stack's page-3 code is inside the game's RAM) |

## 14. Ending a game and returning to MSX-DOS

`XEND` brings the machine back to the MSX-DOS prompt with `MCHAT` typed, whenever the loader managed to save the DOS area:

1. **Saved by the loader**, just before the game starts: from a start address to `FFFEh` (at most 16 KB, so the start is C000h or
   above), with an 8-byte header (`'PNSV'`, start, length). The start is `HIMEM`, or the lowest `game_ram` address at or above the TPA
   top (the word at 0006h) when that is lower: MSX-DOS 2 keeps code and data between the TPA top and `HIMEM`, and the game may use
   part of it (Soccer's E000h-F37Fh against Nextor's `HIMEM` E6FEh). A `game_ram` range below the TPA top is TPA, so nothing is kept. The loader keeps the primary slot register and what is at `FFFFh` (the sub-slot register of page 3's slot,
   complemented, or the RAM byte when that slot is not expanded) in the transport and in its own memory. On the MSXPi path the area goes
   to the Pi (`playnet save`), with or without a mapper. On the TCP/IP path nothing is saved: the game has a page 3 of its own (10),
   and MSX-DOS's is never touched.
2. **Restore**. The game never maps page 0's RAM, so `PLAYNET.COM` is still there. `XEND` sends BYE, puts back MSX-DOS's slot registers
   (page 0 is RAM again) and jumps to `PLAYNET.COM`'s return routine with the result code. That routine uses a stack under MSX-DOS's TPA
   top (never page 0, which `CALSLT` turns into the BIOS; never page 1, which the mapper routines map; never page 2, the restore buffer),
   silences the PSG, fetches the area (`playnet restore`) into page 2, checks its header and length, copies it back, writes `FFFFh`
   (TCP/IP: `XEND` has already switched back to MSX-DOS's page 3; the routine gives the two segments back), enables interrupts (MSX-DOS's hooks are back, and the MSX2 BIOS waits
   for interrupts while it sets the screen up), calls `INITXT` or `INIT32` through `CALSLT` as `SCRMOD` says, puts `MCHAT` (`MCHAT /T` after a
   TCP/IP game) and Enter in the keyboard buffer and jumps to `0000h` (the MSX-DOS warm start). Back in the chat, the Pi says "Game with X ended (reason)".
3. **Fallback**: if nothing was saved, or the restore fails (link error, wrong header or length), back to the game's slots (BIOS in page 0),
   wipe the `AB` header of the RAM image and reset. A game started without the chat (`PLAYNET <game> <role>`) has no session on the Pi,
   so its save is refused and it always ends this way.

On the TCP/IP path the IRC connection does **not** stay open through the game. `MCHAT /T` sends `QUIT :bye` and closes it when it
hands the game over, and writes FFh in `PLAYNET.SES` byte 59 (no connection kept). The connection used to be kept (the engine read
it twice a second and answered `PING`s), but measured on the rig it cost 3-27 % of the frame rate on link 1 and 12-54 % on link 2,
the open connection alone about 4 ms a frame (PLAYNET-TCPIP-PERFORMANCE.md 5.6a). Back from the game, `MCHAT /T` finds byte 59
FFh, connects again with the same nick and joins the default room (the other rooms are not rejoined, and the scrollback from before
the game is not kept). The engine's I/O block byte 133 is FFh in that case, so the keep-alive code does nothing. It still works for
a `PLAYNET.SES` that carries a connection number (an older `MCHAT`): twice a second it reads what arrived on it (at most 4 x 56 bytes),
throws it away, and answers each `PING x` with `PONG x`; it stops if the connection reports an error.

## 15. MSXPi commands used by PLAYNET

Sent over the MSXPi command channel, like `mchat`. Data blocks use the MSXPi block transfer that other MSXPi clients use
(LINK2 since MSXPi 1.7.0: `LINK_SEND` / `LINK_RECV` on the MSX). On success the reply block has the header code `RC_SUCCESS` (E0h) and carries the
payload below. On failure it has `RC_FAILED` (E7h) and carries a message starting with `Pi:Er:`, which PLAYNET shows to the player.

| Command | Reply on success |
|---|---|
| `playnet session` | the first 40 bytes of the session record (13). Fails if no game was handed to the MSX. Fetching it marks the game as started. |
| `playnet profile <game_id>` | the GPF file. Works with or without a chat session. Fails for a game that is not installed, or whose transport is `none`. |
| `playnet save` | After the command, the MSX sends the saved area (14) as one block transfer that the Pi's `recvdata2` takes: one handshake, then blocks of at most 8 KB (`RC_READY` on all but the last, `RC_SUCCESS` on the last). At most 16640 bytes; PLAYNET sends the 8-byte header in the first block, then the area (14). Reply `OK`. Fails when no game is in progress. |
| `playnet restore` | the saved area. The Pi then forgets it, so a second restore fails. |
| `playnet result <code>` | `OK`. The chat shows the result (13.2) when the player is back in `MCHAT`. |
| `playnet open <game_id>` | link 2: the Pi opens its game socket. Reply text `<profhash> <candidates>` (8 hex digits, then `ip:port,...` or `-`). Fails for a game that is not installed. |
| `playnet peers <token> <seat> <game_id> <candidates>` | link 2: the Pi takes the opponent's candidates and the game's profile hash; the C9 connect (10.1) then runs the session. Reply `OK`. |

On the Pi, the games are the GPF files in `MSXPIHOME/games/` (`/home/pi/msxpi/games/`). The file name must be the game id in upper
case. A file with a bad header or checksum, or the wrong name, is skipped and logged.

## 16. Versions and compatibility

| Item | Version | Where it is stated |
|---|---|---|
| Package format | `msxpi-rom-patch` 2 | `version` |
| Netplay ABI | `msxpi-netplay-v1` | `netplay.abi` |
| GPF | 1 | header byte 4 |
| Stub ABI | 2 | stub header byte 0 |
| Bank engine (image host `mapper-ram`) | 1 | `MK_BLOCK` byte 0 |
| PLAYNET release | 3 (`mapper-ram`; stub ABI 2 from release 2) | `min_playnet` |
| Peer protocol | MSXNP 2 | control datagram `version` |
| Invitations | MSXG1 | message prefix |
| Session record | PNS1 | magic |

- Any change to a byte layout or a rule in this document raises the matching version.
- A reader that sees a higher version than it knows must refuse with a message naming what to update. It must not guess.
- Two players can play each other only when both run the same package (same profile hash) and the same MSXNP version. The chat checks the
  first; the handshake checks both again.

## 17. Conformance

An implementation of one of the roles is conformant when it passes the matching tests against the Python reference:

| Role | Tests |
|---|---|
| Chat agent (MSXG) | the invitation flows of `test_games.py` (invite, accept, decline, cancel, busy, unknown game, different hash, expiry), against `msxpi_games.Invites`, in both directions |
| Session engine (MSXNP) | handshake, leader election with equal nonces, delay choice, version and profile mismatch, BYE, start and dead timeouts, loss and reordering, against `msxpi_netplay.Netplay` over real UDP |
| Loader (GPF) | the GPF test vectors: a valid file; and one file for each failure (bad hash, wrong ROM CRC, an expected byte that differs, a range overlapping `game_ram`, a stub outside page 3, a newer `min_playnet`). Each must be refused with the right message. |
| End to end | the two-emulator rig with one MSXPi node and one TCP/IP node, through the chat, 3000 frames identical, and both machines back in `MCHAT` after the exit key |

---

## Appendix A: glossary

| Term | Meaning |
|---|---|
| seat | 0 = the player who sent the invitation, 1 = the other |
| role | the word a game gives each seat (Soccer: `H`, `C`) |
| frame | one run of the game's per-frame logic, normally one display interrupt |
| input delay | how many frames ahead inputs are sent; also the fixed input lag the players feel |
| package | the integrator's directory: `profile.json`, glue sources, the built stub |
| GPF | the compiled package the MSX reads |
| profile hash | CRC-32 of the GPF; equal hashes mean identical patches, engine and glue |
| stub | the shared lockstep engine plus a game's glue, resident while the game runs |
| transport | MSXPi (opcode C9) or TCP/IP UNAPI, behind the vector of section 10 |
| candidate | an `ip:port` where a player may be reachable |
| input width (W) | bytes of input per player per frame, 1-4, fixed by the package |

## Appendix B: review points

| # | Point | Status |
|---|---|---|
| 1 | Exit key | **Decided**: Ctrl+Shift+F5 for every game, no per-game override (9.3, R10) |
| 2 | Desync: end the game, or warn | **Decided**: release builds end the game on both machines and show the frame number; test builds only record it (see below) |
| 3 | More than one input byte per frame | **Decided**: supported in version 1, input width 1-4 (4.4, 7.2, 11.1). Every datagram now starts with a kind byte, and the C9 transaction carries the packet length. |
| 4 | Connect timeout | **Decided**: 120 s (was 300 s in the Python prototype). The player can press Esc on the "Connecting" screen. |

**On point 2, desync.** A desync means the two machines are no longer running the same game: from the first different byte on, every
frame drifts further apart. Both screens keep moving and both players keep playing, but each sees their own version. A goal can appear on
one screen and not on the other, and the final score differs.

- **It is not recoverable in version 1.** Only inputs cross the network. Nothing can bring the two machines back to the same state.
  Recovery would need a resynchronisation: at a frame boundary one machine sends its whole state (game RAM, about 5 KB for Soccer; VRAM,
  16 KB; VDP and PSG registers) and the other loads it. That is possible in principle, but it is a later feature, not part of version 1.
- **What a warning would give the players:** nothing they can act on. After the warning they can only press Ctrl+Shift+F5. Until then
  they play a match whose result means nothing.
- **What a warning gives integrators:** during development the game keeps running after the first mismatch, so the frame traces show where
  and why the machines diverged. A warning also survives a false alarm, which comes from a checksum region that includes bytes that
  legitimately differ between the machines. That is a bug in the package, which the test pair (4.9) should catch.

**Decision:** in release builds a desync ends the game on both machines at once (BYE with result 4). Both players see "Game ended: the
machines lost sync at frame N (please report it)", in PLAYNET and back in the chat, so the report reaches the integrator. Builds made for
testing set stub flag bit 0 to 0 and only record the first mismatched frame, as the current test rig does.
