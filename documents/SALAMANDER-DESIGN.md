# Salamander online co-op (PLAYNET): analysis and design

Written 2026-10-23. It brings Konami's Salamander (MSX, RC-758) to PLAYNET as a **co-op** game: two players on two machines fly
together in the game's own two-player mode, DUALPLAY. PLAYNET is specified in `documents/PLAYNET-PROTOCOLS.md` and was proven with
Konami's Soccer. Yie Ar Kung-Fu (`feature/yiear-netplay`) is the other game in design.

| | |
|---|---|
| Dump | `SALAMAND.ROM`, 131072 bytes, CRC-32 `C36F559D`, SHA-256 `edbbba820ac67d6a55b9dc5da9309e45979936d5620c07d09793efaf077e86b9` (the user's copy is `C:\Users\roniv\Dev\MSX\gameroms\SALAMAND.ROM`; never commit it or anything derived from it, such as the disassembly) |
| Mapper | Konami SCC: 16 banks of 8 KB, registers 5000h/7000h/9000h/B000h, SCC sound at 9800h with 3Fh in 9000h |
| Game id / GPF | `salamander` / `SALAMAND.GPF` |
| Roles | `P1` (seat 0, the inviter: Vic Viper), `P2` (seat 1: Lord British) |
| Input width | 2 bytes (joystick, function keys) |
| Package | `software/ROM-Patcher/profiles/salamander/` (glue, rebuild script, profile). The bank engine is `software/Client/src/playnet/engine/mapper_k8.asm`. |
| State | Analysis done (static and dynamic, in openMSX with the real cartridge). The stub assembles, and the 77 patches match the dump. **Not runnable yet**: it needs the mapper-RAM host in PLAYNET (section 9). |

---

## 1. Summary

- **Co-op comes with the game.** The title offers PLAY SELECT: 1PLAYER, EXCHANGE (taking turns) and **DUALPLAY** (both at once).
  In DUALPLAY the reader fills two player blocks, player 1 from joystick port 1 and the keyboard, player 2 from port 2 and a second
  set of keys. The package gives the game player 1's network input where it reads port 1 and player 2's where it reads port 2. No
  new game logic is needed, unlike Yie Ar's Versus.
- **The frame is the usual Konami one**: H.KEYI handler at 4069h, a sound busy flag, a frame busy flag and one input reader per frame.
  That gives a clean TICK site.
- **The hard part is the cartridge, not the game.** Salamander is a 128 KB MegaROM. PLAYNET 1 only hosts plain 16/32 KB ROMs, and
  format version 2 reserves image host `mapper-ram` for this case. This design defines that host, using the method `msxarch` already
  uses: bank writes patched into calls, and pairs of 8 KB banks held in 16 KB mapper segments.
- **Memory is the price.** The game switches banks about 14 times a frame and uses 24 different page-2 pairs. Smooth play needs
  about 28 segments for the game: a **512 KB memory mapper**. Less memory still plays the same game, with pauses (section 5.4).
- **Sound**: no SCC in a RAM host, so the SCC part of the music is lost and the PSG part stays. A later option can use a real SCC
  cartridge (section 10).
- **No third-party loader is needed** (section 11).

---

## 2. Decisions to confirm

| # | Question | Proposal |
|---|---|---|
| D1 | Modes online | DUALPLAY is the co-op. 1PLAYER and EXCHANGE also work, controlled by player 1 only (EXCHANGE's second player cannot play their turn yet, see 12.2). |
| D2 | Who uses the PLAY SELECT menu | Player 1 (the inviter), as for Yie Ar. Alternative: start in DUALPLAY directly. |
| D3 | Pause (F1), continue (F5) and the Y/N prompt | Either player, so both machines pause and continue together |
| D4 | Memory | Refuse below 22 free segments (with 20, the trace gives about one 0.1 s pause a second). Recommend 512 KB. |
| D5 | SCC sound | Removed in release 1 (PSG only). Optional real-SCC output later (section 10). |
| D6 | Salamander + Nemesis 2 in another slot (the special ending) | Off: both machines must see the same world |
| D7 | Where the stub lives | D000h-D5FFh stub (1393 of 1536 bytes used), D600h-D7FFh transport, in the 4 KB the game never touches |
| D8 | PLAYNET release | The mapper host is **release 3**. It does not depend on Yie Ar's release 2 (8 KB GPFs): this GPF is about 2.5 KB. |

---

## 3. What the ROM does

All of this was measured in openMSX with the real cartridge (`-romtype KonamiSCC`), by disassembly of every bank and by Tcl
watchpoints over 5-10 minute DUALPLAY runs. The scripts are in this session's scratchpad. Section 3.7 lists what is still to verify.

### 3.1 Start, frame and interrupt

| | |
|---|---|
| Header | `AB`, INIT = 40DAh |
| INIT 40DAh | `di; im 1`. H.KEYI = `JP 4069h` (operand at **40E3h**). SP = F0F0h. Own slot to page 2 (412Fh, ENASLT), own slot saved in F0F6h (414Fh). Banks 0/1/2/3 to W0-W3, copies in F0F0h-F0F3h. Clears E000h-EFFFh. Then 50D0h (sound init), B599h (cartridge probe), `ei; jr $`. |
| Handler 4069h | `call RDVDP; di`. F0F7h += 1 (16-bit), E23Ah += 1, `call 4E7Fh` (a per-interrupt countdown). Sound busy flag **E214h**: if clear, banks 4/5/6, `call 6978h` (sound driver), banks back from F0F1h-F0F3h. Frame busy flag **E205h**: if clear, `ei`, then **`call 51A7h`** (input, at 40B5h), `call 5208h` (function keys), `call 524Ch` (frame). |
| Game state | E200h (0 attract ... 5 play, 9 a second play state), E202h bit 6 = a human plays. The state machine is at 524Ch. |

### 3.2 Banks

- W0 (4000h-5FFFh) is always bank 0, the fixed code. W1 (6000h-7FFFh) takes 1, 4, 7 or 13. W2 (8000h-9FFFh) takes 2, 5, 8, 10 or 14,
  and 3Fh to show the SCC. W3 (A000h-BFFFh) takes 3, 6, 9, 11, 12 or 15. The select routines at 416Eh-41FFh confirm the sets.
- **Every bank switch is a direct `ld (nn),a`**: 45 sites, the same list `mapper_detect.py` finds, all confirmed by the traces.
  36 of them are in bank 0, 1 in bank 1 and 8 in the sound driver (bank 4).
- Traffic over 10 minutes: page 1 changed pair 73,671 times, page 2 495,950 times (about 14 a frame). The sound driver runs with
  4/5/6 on every interrupt and the game restores its own banks afterwards.
- Pairs used: page 1 (0,1) (0,4) (0,7) (0,13). Page 2: **24 pairs**, most to least used: (2,3) (2,12) (2,15) (14,15) (14,3) (2,11)
  (5,6) (2,6) (5,3) (2,9) (10,15) (10,3) (5,15) (14,6) (5,12) (5,11) (5,9) (8,9) (8,6) (10,6) (10,9) (10,11) (8,3) (8,11).
- **No writes into 8000h-BFFFh other than the bank and SCC registers** (the others seen in the traces are the BIOS RAM test at boot).
  So bank copies in RAM stay pure ROM.

### 3.3 Inputs

| Reader | What it does |
|---|---|
| 51A7h (from the TICK site) | E200h = 5 or 9 (DUALPLAY): 513Dh, both blocks. Otherwise `call 51BFh` (port 1) into E30Fh (held) / E30Eh (new). |
| 513Dh | For IY = E300h (player 1) and E380h (player 2): `bit 0,(iy+21h)` picks the port. 0: 51BFh. 1: port 2 (`ld e,CFh; call 51F1h`) plus keyboard rows 6, 3 and 5 (516Ah, which also writes E60Dh). Then the edge logic at 51B8h into the block's +0Fh/+0Eh. Measured: E321h = 0, E3A1h = 1. |
| 51BFh | Joystick 1 (`WRTPSG` R15 = 8Fh, `RDPSG` R14) OR cursors and space (row 8) OR M/N as trigger B (row 4). Bits 0-5. Writes no RAM. |
| 51FFh (from 57DCh) | The same, for the menus; edge state at E211h/E210h |
| 5208h | Only while playing and nobody moves: rows 6, 7 and 8 folded into 6 bits into E219h/E218h. F1 (bit 0) pauses (542Dh, 55CFh). |
| 55F9h | Row 7, `rra; rra`: carry = F5 not pressed. This is the "CONTINUE F5" of the game-over screen (55DBh, 55EAh). |
| 57CCh / 57D4h | Y (row 5 bit 6) / N (row 4 bit 3): a Y/N prompt with a timeout (571Fh) |

No other keyboard or joystick read exists: every `SNSMAT`, `RDPSG` and `WRTPSG` call in the 16 banks is one of these, or the
sound driver's PSG writes. Ctrl+Shift+F5 (the PLAYNET exit) is free: the game uses F5 alone.

### 3.4 Determinism

| Source | Finding | Action |
|---|---|---|
| R register | **12 `ld a,r`**: 4E58h (bank 0), 65ABh 67DAh 718Bh 7274h 73D5h 7544h (bank 1), 99F1h 9CCAh 9CD3h (bank 10), AE7Ah B03Ah (bank 12) | Each one and the instruction after it -> a call to the same instruction on a xorshift value |
| Interrupt counts | F0F7h (read at 4DA1h), E23Ah (read at 585Bh) and the 4E7Fh countdown advance per interrupt | Moved into the per-frame sound tick, which runs T times a frame on both machines |
| Other slots | B599h looks for a Nemesis 2 cartridge in every slot with RDSLT (sets F0F5h, F0F4h). If found, 5B91h copies code to C000h and data from the other cartridge, and 6E44h maps it into page 2. | The probe returns "none", and F0F4h = the own slot (it is otherwise never initialised, and 6E2Bh reads it) |
| JIFFY | Not read (the five `9E FC` byte pairs are data in bank 5) | - |
| VDP status | Read only by RDVDP in the handler and at INIT, result unused. The one `in a,(99h)` is graphics data (bank 8). | - |
| SCC | Write-only for the game | Removed (3.5) |

### 3.5 SCC sound

The sound driver (bank 4) writes the SCC through two routines and two blocks: 7346h (one register, 16 callers), 73A9h (waveform
upload), 65C2h-65CDh (volume) and 6604h-6622h (mute). In RAM there is no SCC, and the writes would land in the bank copies. So 7346h
and 73A9h become `ret`, and the enables and register writes in the two blocks become no-ops. The `ld (9000h),05h` that ends each
block stays a real bank switch. The PSG part of the driver is untouched.

### 3.6 RAM

| Range | Use (measured over 10 minutes of DUALPLAY, all PCs recorded) |
|---|---|
| C000h-CFFFh | Game: C000h-C3FFh read and written from bank 2 code (8884h), C400h-CFFFh used throughout |
| **D000h-DFFFh** | **Never touched by the game.** Only the BIOS RAM test at boot writes it. -> the stub and the transport. |
| E000h-EFFFh | Game variables, cleared at INIT. Players at E300h/E380h, sound state E000h-E1FFh, E600h+ |
| F000h-F0F8h | The stack (F0F0h down, lowest seen F0AAh at an interrupt) and F0F0h-F0F8h (bank copies, slots, counters) |
| F0F9h-F37Fh | Not used by the game |

### 3.7 Still to verify (implementation step 1)

- The RAM footprint and the bank pairs **in every stage**: the runs reached stage 1 and its boss only. Use an infinite-lives poke.
- The stack depth with `PN_TICK`, the sound tick and a bank build nested at the TICK site (budget: F000h-F0A9h).
- That 6E2Bh, 5B91h and 5BB5h are only reached with F0F5h set (callers 5888h, 8B9Fh, 8F7Fh test it).
- Whether the game reads C000h-CFFFh before writing it (INIT does not clear it). If it does, the loader must clear it.
- What the Y/N prompt at 571Fh asks.
- The checksum region (E300h, 200h bytes) is a good one: it must change every frame in play and hold no machine-dependent byte.

---

## 4. Architecture

```
            page 0              page 1 (4000h-7FFFh)          page 2 (8000h-BFFFh)          page 3
 game:      BIOS                segment = (bank 0, W1 bank)    segment = (W2 bank, W3 bank)   C000h-CFFFh game
                                4 prebuilt pairs               up to 30 pairs, LRU-ish        D000h stub: engine, glue, bank engine
                                                                                              D600h transport
 PLAYNET:   PLAYNET.COM (kept)                                                                E000h-F0F8h game, stack
                     patched ld (nn),a  --->  MK_W0..MK_W3 (stub)  --->  OUT (FDh) / OUT (FEh), or build the pair
```

| Piece | Lives | Contains |
|---|---|---|
| Stub | D000h, at most 1536 bytes (1393 used) | PLAYNET's engine, the 8 KB bank engine with its tables (`MK_BLOCK`, 190 bytes), and the glue |
| Transport | D600h, 512 bytes | PLAYNET's (MSXPi or TCP/IP), unchanged except 9.3 |
| Game image | 10 to 34 mapper segments | the 16 banks, as pairs |

---

## 5. The mapper-RAM host (8 KB banks)

### 5.1 Why pairs

The MSX mapper switches 16 KB, the cartridge 8 KB, so page 1 alone holds two banks that change independently. Mapping cannot express
any pair, and copying 8 KB costs about 48 ms. But a page is fully determined by the pair of banks in its two windows, and a game uses
few pairs. So a segment holds a **pair**, and a switch to a pair already built is one `OUT`. This is `msxarch`'s pair cache
(`ascii8Handlers`, which brought NEMESIS from 2.7 to 60 music steps a second), with three changes for lockstep:

1. **It runs from the stub at its own address**, so it can use absolute jumps, unlike the relocated `msxarch` block.
2. **Pinned homes**: the first entries of each table are never replaced, and every bank has its home in one of them. For
   Salamander, page 1's four pairs and (2,3) (5,6) (8,9) (10,11) (14,15) (2,12) hold all 16 banks in 10 segments. A missing pair is
   built from the homes. Patches are applied to the homes before any copy, so every copy has them.
3. **Masking and the clock**: the written value is masked to the ROM size (as the cartridge decodes it), and a miss replaces a spare
   entry with the clock (second-chance) algorithm, a cheap approximation of LRU. On the 10-minute trace, LRU misses 1.5-2 times less
   than round-robin at every size.

### 5.2 Bank engine (`mapper_k8.asm`, host ABI 1)

- `MK_W0`-`MK_W3`: A = the value written. They preserve every register and the flags, and keep the caller's interrupt state.
  The same bank again is ignored. Otherwise the page's pair is looked up, and built if missing (interrupts off), then mapped.
- A build maps the target at 8000h and each home at 4000h, copies 2 x 8 KB, and puts both pages back. The stub and the stack are in
  page 3, so the caller's page-1 code is back before the return.
- `MK_BLOCK` (filled by the loader): version, bank mask, the bank in each window, the segment in each page, each bank's home
  (segment, half), and per page: entries in use, pinned, the clock hand, then the entries (low bank, high bank, segment, referenced).
- No spare entry left: `PN_END` with result 9 ("not possible on this machine"). The loader prevents this by checking the count.

### 5.3 Determinism

The segments only ever hold ROM bytes (3.2), so what the cache does affects time, never results. Two machines with different
mappers play the same game. The one with fewer segments pauses more, and lockstep makes the other wait.

### 5.4 Memory

Misses for the 10-minute trace, with page 1 fully built (4 segments) and the 6 pinned page-2 homes:

| Page-2 spares | Game segments | Misses a second (LRU) | Time spent copying |
|---|---|---|---|
| 4 | 14 | 142 | unplayable |
| 8 | 18 | 3.3 | 31 % |
| 10 | 20 | 0.85 | 8 % |
| 14 | 24 | 0.23 | 2 % |
| 18 | 28 | 0.03 | 0.3 % |
| 24 (all 30 possible pairs) | 34 | 0 | 0 |

A machine has the mapper's segments minus page 0 (PLAYNET.COM) and page 3 (MSX-DOS), minus what MSX-DOS 2 or Nextor keep, minus 2 on
the TCP/IP path. With 512 KB that leaves 26-30. **Minimum 22, recommended 30.** A 256 KB machine (about 12-14) would pause many times a
second, so it is refused with a clear message instead.

The loader builds the page-2 pairs in the package's order (pinned, then by measured use, then the six never seen) until it runs out
of segments. The rest of the table starts empty for the clock.

---

## 6. Co-op

| Game read | Patched to | Online |
|---|---|---|
| `call 51A7h` at 40B5h | `tickSite`: `PN_TICK`, then 51A7h | the TICK site, once per frame |
| 514Fh: which port a player block reads | `dual`: IY = E300h -> `PN_P1`, E380h -> `PN_P2`, then the edge logic at 51B8h | DUALPLAY: each player flies their own ship |
| `call 51BFh` at 51B2h | `p1` | 1PLAYER, EXCHANGE: player 1 |
| `call 51FFh` at 57DCh | `p1` | PLAY SELECT and other menus: player 1 (D2) |
| 521Fh (function keys) | `fkeys`: either player's, then 5242h | pause/continue from either player (D3) |
| 55F9h (F5) | `f5key`: carry = neither pressed | CONTINUE F5 |
| 57CCh / 57D4h (Y / N) | `keyY` / `keyN`: Z = pressed by either | the Y/N prompt |

**Local input** (`G_READ_LOCAL` = `rdLocal`, 2 bytes): byte 0 is what 51BFh returns (bits 0-5: joystick 1 or cursors, space, M/N),
plus Y in bit 6 and N in bit 7. Byte 1 is the 6-bit value of 521Fh-5240h (computed the way the game computes it), plus F5 alone in
bit 6. **Each player uses their own joystick in port 1 or the cursor keys**, whichever seat they have. The game's second-player
keyboard set (516Ah) is no longer read.

Both machines derive everything from `PN_P1`/`PN_P2`, so they stay identical: the mode chosen, who moves, pause, continue.

---

## 7. Patch table (77 patches, generated by `rebuild.py`)

Offsets are ROM offsets: bank x 2000h + (CPU - window). `S.x` = a stub entry, `T` = D600h (the transport).

| Group | Sites | Replacement |
|---|---|---|
| Interrupt hook | 40E3h `69 40` | `T+6` (XIRQ, which jumps to 4069h) |
| Interrupt body | 406Dh `2A F7 F0 23 22 F7` | `CD S.PN_IRQ C3 AC 40`: count, then the frame. 406Dh-40ABh are now done by `sndTick`. |
| Inputs | 40B5h, 514Fh, 51B2h, 521Fh, 55F9h, 57CCh, 57D4h, 57DCh | section 6 |
| Cartridge probe | B59Dh (bank 3) `01 00 04` | `C3 S.probeOff` |
| `ld a,r` | the 12 of 3.4 | `CD S.rXxx` (+ `00` for the 4-byte ones) |
| Bank switches | 43 `32 nn nn` | `CD S.MK_Wn` |
| SCC | 9 register writes / enables, 2 routine entries | `00 00 00` / `C9` |

`rebuild.py --rom SALAMAND.ROM` checks every expected byte against the dump, that no `ld (nn),a` to a bank register is left, that the
patches do not overlap, and that the pinned pairs hold every bank. A check that no jump lands inside a patched span was run on the
disassembly: the 11 hits are data or code in another bank of the same window.

`sndTick` (`G_SOUND_TICK`, T times a frame, interrupts off): F0F7h += 1, E23Ah += 1, `call 4E7Fh`, banks 4/5/6, `call 6978h`,
banks back from F0F1h-F0F3h. This is the handler's per-interrupt work, in the same order.

`netplay` section (abridged; `profile.json` is generated):

```json
"netplay": {
  "abi": "msxpi-netplay-v1", "game_id": "salamander", "title": "Salamander (co-op)", "roles": ["P1", "P2"],
  "transport": "lockstep", "input_bytes": 2,
  "image": {"host": "mapper-ram", "mapper": "konami-scc", "bank_size": 8192, "banks": 16, "block": 53909,
            "start_banks": [0, 1, 2, 3], "page1_pairs": [[0,1],[0,4],[0,7],[0,13]], "page2_pairs": [[2,3], "... 30 pairs"],
            "pinned": [4, 6], "min_segments": 22, "recommended_segments": 30},
  "stub": {"asset": "stub", "load": 53248, "max": 1536},
  "transport_area": {"address": 54784, "size": 512},
  "game_ram": [[49152, 53247], [57344, 61688]],
  "irq_handler": 16489, "start": "header-init", "min_playnet": 3
}
```

---

## 8. Lockstep details

- **One TICK a frame**, at 40B5h, inside the frame busy flag. An interrupt during `PN_TICK` only counts (`PN_IRQ`) and returns,
  because E205h is set (R6).
- **Sound and the game's interrupt counters** follow T, player 1's interrupt count for the frame (PROTOCOLS 9.2). So the music keeps
  its tempo, and the game logic that reads F0F7h/E23Ah sees the same values on both machines.
- **Bank switches inside `sndTick`** go through the bank engine like any other.
- **Checksum**: E300h-E4FFh, both player blocks and what follows, every 32 frames.
- **50 Hz against 60 Hz**: the game runs at the slower machine's pace, as for Soccer.

---

## 9. Changes outside the package (PLAYNET release 3)

### 9.1 Format and tools (`FORMAT.md`, `patch_rom.py`, PROTOCOLS 7.2 / 8.2)

- `netplay.image.host = "mapper-ram"` with the fields of section 7. Rules: the layout is the identity (the ROM, unchanged in size),
  patch offsets are ROM offsets, `block` lies inside the stub, the pinned pairs hold every bank, `min_segments` is at least the pinned
  count plus one spare.
- GPF flags bits 1-2 = 1 (`mapper-ram`), plus a new `MAPR` section: mapper type, bank size and count, block address, start banks, the
  two pair lists, the pinned counts and the minimum segments. `read_gpf` currently refuses any host but `plain` (patch_rom.py line 431),
  which is right for PLAYNET 1 and 2.
- The save rule (PROTOCOLS 14.1) takes the stub and the transport into account too: the save starts at the lowest of `HIMEM` and every
  page-3 area the game image or the stub writes at or above the TPA top. Here the stub (D000h) can be above the TPA top.
- `ram-image` builds of a mapper package for tests: `patch_rom.py --banks DIR` writes the patched banks, for the rig.

### 9.2 Loader (`playnet.asm`, `playnet_tcp.asm`)

1. **Segments**: on MSX-DOS 2 / Nextor, `ALL_SEG` (user segments) from the mapper support routines. On MSX-DOS 1, the detection
   `msxarch` uses (`detectMapperSegments`: sentinel in segment 0, then count up to the wrap), minus the four TPA segments. Refuse with
   "This game needs a 512 KB memory mapper" below `min_segments`.
2. **ROM**: read in 8 KB blocks through the bounce buffer (DOS cannot read into page 1) and copied into each bank's **home**, mapped
   in page 2. The CRC-32 runs over the stream as now.
3. **Patches**: offset -> bank -> home (segment, half). The expected bytes are checked there, as now.
4. **Pairs**: copy the homes into the other page-1 pairs (bank 0 into all four), then build page-2 pairs in order while segments last.
5. **Block**: fill `MK_BLOCK` after the stub is installed. Map the start pairs (0,1) and (2,3), set `mkCur` = 0, 1, 2, 3.
6. **Return**: before `pnBack` uses 4000h-BFFFh as its restore buffer, put MSX-DOS's own segments back in pages 1 and 2 (saved with
   `GET_P1`/`GET_P2`, or the TPA segments 2 and 1 on MSX-DOS 1). Free the segments on MSX-DOS 2.
7. `PLAYNET_VERSION` 3, `min_playnet` 3. Older loaders refuse the GPF with "This game needs a newer PLAYNET".

### 9.3 TCP/IP transport

`XCHG` maps the network engine into page 2 and must put back the game's page 2 afterwards. It restores the segment from `MK_SEG2` (the
loader gives the transport its address, a new field in the install block) instead of the value `PUT_P2` recorded, because the bank
engine changes page 2 with `OUT` and never tells MSX-DOS. The game writes C000h-CFFFh, so R8 applies: with InterNestor Lite on
MSX-DOS 1 (page-3 code from C806h), PLAYNET refuses to start, as for any game that writes that range.

### 9.4 Engine

`SCRIPTED` builds store only the first input byte when W > 1. Extend the scripted tables to W bytes (byte 1 = 0), so the rig can play
Salamander.

---

## 10. SCC sound (later, optional)

The game never reads the SCC, so SCC writes do not affect lockstep, and each player can have SCC or not independently. A player
with a real SCC (a Konami SCC cartridge, an SCC+ Sound Cartridge, a MegaFlashROM SCC+) in another slot could hear the full music. Instead
of `ret`, 7346h and 73A9h would go to glue that switches page 2 to the SCC's slot (selecting its SCC mode), does the writes, and puts
page 2 back. The loader finds the SCC at start-up. This needs a slot switch from the stub (allowed for the loader, not today for the
stub: PROTOCOLS 9.2 says the stub never touches slots), so it is a separate decision.

---

## 11. Third-party loaders (SofaRun) assessed

SofaRun runs Konami SCC MegaROMs from mapper RAM on MSX-DOS. Using it would mean producing a pre-patched ROM and letting SofaRun
load it. That does not fit:

- PLAYNET must connect the two machines and install the stub and transport before the game starts. SofaRun takes over the machine
  (its resident block, its slot set-up) and starts the ROM itself. The stub would have to install itself from inside the ROM, but bank 0
  has no free byte (no filler run of 64 bytes or more in bank 0 to 5).
- The return to the chat (PROTOCOLS 14) relies on PLAYNET.COM staying in page 0 and on the saved DOS area. Under SofaRun the only way
  out is a reset.
- The TCP/IP path is impossible: the transport needs PLAYNET's segments and its page-3 arrangement.
- SofaRun's pair handling would be one more thing outside the package hash that must be identical on both machines.
- The part SofaRun would save us is the mapper host. `msxarch` already has the method, and this design reuses it.

**Conclusion: no third-party loader.** It is not needed and would cost features. A future MSXPi Mega board (MegaROM from RAM with a
Konami SCC mapper in hardware, `MSXPiMega/cpld`) would make the host trivial: no pairs, no copies, any MSX. That is the natural second
implementation of `mapper-ram`.

---

## 12. Risks and open points

### 12.1 Risks

| # | Risk | Mitigation |
|---|---|---|
| K1 | Later stages use pairs or RAM the traces did not see | Step 1 measures every stage. Unseen pairs are already in the table (the six never seen) or built on demand. |
| K2 | Indirect bank writes (`ld (hl),a`) somewhere not yet run | Statically none found. The rig checks, through a watchpoint, that every write to a bank register comes from a patched PC. |
| K3 | Stack overflow below F0AAh with the nested stub calls | Measure (3.7). The stub can switch to its own stack in D800h-DFFFh inside `PN_TICK` if needed. |
| K4 | Memory: few players have 512 KB | The refusal is clear, and the minimum may come down after step 1 measures real pauses. The MSXPi Mega host removes the limit. |
| K5 | The loader grows past PLAYNET.COM's room (0100h-23FFh) | The mapper code is about 600 bytes. If it does not fit, it moves to a part loaded into a segment, as the TCP/IP overlay is. |
| K6 | 50/60 Hz and pauses make the slower machine lead | That is lockstep's normal behaviour: the game runs at the slower machine's pace. |

### 12.2 Open points

1. EXCHANGE online: the player whose turn it is should get their own input. That needs the game's "current player" variable (not
   looked for yet). Until then EXCHANGE is player 1 only.
2. Should the inviter's PLAY SELECT cursor start on DUALPLAY? (D2)
3. Fold the mapper host into the same release as Yie Ar's 8 KB GPFs, or keep it separate? (D8)

---

## 13. Implementation plan

| Step | Work | Done when |
|---|---|---|
| 1 | Verify 3.7 with the cartridge in openMSX: all stages (infinite lives), footprint, pairs, stack, the probe paths, C000h before write | Every "to verify" closed; the pair list and `min_segments` updated |
| 2 | Format: `mapper-ram` in `FORMAT.md`, `patch_rom.py` (validation, `MAPR` section, `--banks`), PROTOCOLS 7.2/8.2/14.1, tests | `rebuild.py` compiles `SALAMAND.GPF` and `test_gpf.py` covers it |
| 3 | A host simulator: a Python model of the bank engine run over the recorded traces (hits, misses, builds) | It reproduces 5.4, and the loader's tables come from the same code |
| 4 | PLAYNET 3 loader, MSXPi path (9.2) | One node boots Salamander from RAM in openMSX with a 512 KB mapper and plays a stage |
| 5 | Two-node rig, scripted inputs (9.4), checksums and full-RAM compare | 30 minutes of DUALPLAY in lockstep, no desync, with different segment counts on the two nodes |
| 6 | TCP/IP path (9.3) | The same over UNAPI |
| 7 | Real hardware with a 512 KB mapper, and publish (`target/games`, index, quick start) | Human play test |

Tests to add (T-numbers continue Yie Ar's plan):

- T20: `rebuild.py --rom` (expected bytes, no bank write left, homes cover every bank).
- T21: host simulator over the traces: miss counts per segment budget, and that pinned entries are never evicted.
- T22: one node, every stage reached, the screen compared with the cartridge at the same frame (scripted input).
- T23: two nodes with 30 and 22 segments: the same RAM every 32 frames.
- T24: exit with Ctrl+Shift+F5 back to MCHAT; MSX-DOS's pages 1/2 restored (run a DOS command afterwards).
- T25: watchpoint on 5000h-57FFh, 7000h-77FFh, 9000h-97FFh, B000h-B7FFh: no write from an unpatched PC in a full game.
- T26: Soccer regression: its `stub.bin` and GPF stay byte-identical (the engine change in 9.4 must be behind `IF W > 1`).
