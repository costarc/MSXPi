# LINK2 - MSXPi link protocol 2: design

Branch `feature/link2` (off `feature/tcpip-games`). Companion documents: LINK2-IMPLEMENTATION-PLAN.md,
LINK2-TEST-PLAN.md. Background and measurements: BLOCK-RETRIES-FAULT-INJECTION.md.

## 1. Goals and constraints

- **No silent corruption**: an undetected bad block must need 4+ flipped bits in one block.
- **No desync from a single fault**: every fault ends either in a successful retry or in a clean,
  reported abort that leaves both ends idle for the next command.
- **No speed loss**: no slower than today on any path, and burst writes restored, which is faster.
- **No CPLD change**: v1.6 firmware as it is.
- **Server speaks both protocols**: the legacy protocol stays for the MSX-DOS ROM half, older
  EEPROMs and the existing .COM tools, so the MSX can keep booting from MSXPi throughout. Each
  transfer announces its protocol in its first byte.
- **Scope**: LINK2 is first used by the BIOS-only ROM half (`msxpibas.rom`) and `msxpiext.bin`.
  The MSX-DOS driver half follows once the code has been optimised and is known to fit. The .COM
  tools come after that.
- **Distribution**: `msxpiupd feature/link2` must deliver the whole thing: the server through
  `p update`, and the MSX files (ROM image, msxpiext.bin, test tools) from the branch's `target/`.

## 2. What is wrong with the legacy protocol (summary)

| Problem | Effect |
|---|---|
| 8-bit folded sum | Two flips of the same bit in opposite directions cancel (about 1 in 16 two-bit errors). |
| Each end decides on retries by itself | Different limits lead to a lockup (server resends into the MSX's next command) or a hang (pcopy upload). A corrupted checksum byte makes the two ends disagree. |
| Header and status bytes unprotected | A corrupted length or block number puts the two ends out of step. |
| READY race at the start of OTIR | `$56` = 0 can be sampled during the microseconds the Pi leaves READY up after finishing a byte. OTIR then starts with no burst running, and its first bytes overwrite each other in the CPLD write latch. This is why burst disk writes are disabled. |
| `ETH_RC_OK` = 0x00 | An idle or out-of-step link reads 0x00, which means "frame sent OK". |

## 3. Wire protocol

### 3.1 Byte codes

| Name | Value | Direction | Meaning |
|---|---|---|---|
| `READY` | 0xAA | MSX -> Pi | opens a **legacy** transfer (unchanged) |
| `HELLO2` | 0xB2 | MSX -> Pi | opens a **LINK2** transfer |
| `HELLO2_ACK` | 0xB3 | Pi -> MSX | the server speaks LINK2 |
| `SIZE_MARK` | 0xB4 | MSX -> Pi | first byte of the size frame (3.2) |
| `ACK` | 0x5A | receiver -> sender | header or block accepted; also the Pi's "go" byte for bursts |
| `NAK` | 0xA5 | receiver -> sender | resend |
| `ABORT` | 0x0F | either | give up this transfer |

ACK, NAK and ABORT differ from each other in at least 4 bits. **Any other value read where one of
them is expected is treated as NAK.** That includes 0x00 and 0xFF, the values a stale or idle link
gives. **One exception, found by the fault-sweep tests (section 3.7): the answer to a block header**
(and to the size frame) **counts as ACK unless it is exactly NAK or ABORT.** 0xB2 and 0xB3 are used by nothing else: the RC codes are 0xE0-0xEF, the handshake bytes
0xA0-0xAE, the Ethernet opcodes 0xC0-0xC9.

### 3.2 Opening a transfer

Every transfer starts with the MSX, exactly as the legacy one does (SENDDATA, PerformHandshake):

```
MSX -> HELLO2                        (repeated until HELLO2_ACK; see below)
Pi  -> HELLO2_ACK
Pi  -> flags     bit 0: the Pi can burst in both directions (native/fast GPIO, or TCP-framed openMSX)
MSX -> SIZE_MARK (0xB4), size lo, size hi, crc lo, crc hi     "size frame", CRC-16 of mark+size
Pi  -> ACK | NAK                     a frame with a bad CRC or mark is NAKed and sent again
```

- The size word is the largest block the MSX accepts; **bit 15 = this transfer may burst** (the MSX
  has /WAIT and its buffer is outside page 1).
- **HELLO2, then the answer and the flags are always read as a unit** (three transfers), so that a
  damaged HELLO2_ACK costs one retry and leaves both ends in step: after sending the answer and the
  flags the Pi reads the next byte, and a HELLO2 there means "I missed your answer", which it
  answers again.
- **Bursts** are used for a block only when both the Pi flag and the MSX's bit 15 are set, the
  block is a non-empty multiple of 256 bytes, and the MSX buffer is not in page 1.
- **The MSX's wait for `HELLO2_ACK`** counts only exchanges that completed with a wrong answer.
  Time spent waiting for the Pi to be ready is not counted, because the server may be busy.
  After 16 wrong answers the MSX gives up with RC_PROTOERR, "server does not speak LINK2" (an
  old server answers 0x00). It never hangs.
- **The server** hunts for READY or HELLO2. Whichever it sees decides the protocol for that
  transfer, and only that transfer. No state is kept between transfers, so legacy and LINK2
  transfers can follow each other freely.

### 3.3 One block (sender -> receiver)

```
S -> type, len lo, len hi, seq          type = RC_READY (more blocks follow), RC_SUCCESS (last) or an RC error
S -> hcrc lo, hcrc hi                   CRC-16 of the four header bytes
R -> ACK | NAK                          header check; when R is the Pi and the block bursts, this ACK is the GO byte
[Pi -> ACK]                             GO byte, only for a Pi -> MSX burst (the Pi is the sender)
S -> payload (len bytes)                OTIR/INIR when bursting, polled otherwise
S -> crc lo, crc hi                     CRC-16 of the payload
S -> end mark                           seq XOR 0xFF (3.7)
R -> ACK | NAK | ABORT                  sent twice when the block is the final one (type not RC_READY);
                                        the sender takes either (3.7)
```

- `len` bit 15 = "this block bursts". It is protected by the header CRC.
- **End mark**: the receiver NAKs a block whose CRC is right but whose end mark is not; that is a
  misaligned block that matched its CRC by chance (3.7). The end mark is always sent polled,
  after the CRC, also when the payload burst.
- `seq` counts 0..255 per transfer and wraps.
- On a header NAK, the sender resends the header (counted as an attempt).
- On a payload NAK, the sender resends the whole block (header included) with the **same seq**.
- **Duplicates**: the receiver remembers the last seq it accepted. A block that arrives with that
  same seq means its ACK was lost: the receiver reads it in full, discards it and ACKs again. Any
  seq other than the last one or the next one makes the receiver ABORT, and so does a header
  type that is not an RC code (0xE0-0xF0: RC_READY or a final code).
- **Capacity**: a block that does not fit the room the receiver has left is ABORTed in its header
  slot, never ACKed: an ACK followed by a drop would tell the sender the transfer succeeded. A
  duplicate is exempt, since the block it repeats is already counted.
- **One retry limit, on the receiver**: after `LINK2_RETRIES` (10) consecutive NAKs for one block,
  the receiver sends ABORT. The sender has no limit of its own except a safety cap (32 attempts)
  and CTRL+ESC on the MSX, for a receiver that has disappeared.
- **A receiver that aborts keeps answering ABORT** for one block and its framing (the block size
  limit + 16 transfers). A sender that slipped out of step reads its answer slots at the wrong
  place, and a single ABORT lands where it never looks; repeated, the next slot it reads holds
  one. The Pi stops early when the MSX's next transfer begins (a HELLO2 or READY arrives in the
  same transfers), so the next command is not held up.
- **A sender that reads HELLO2 in an answer slot stops**: the MSX has given the transfer up and
  is opening the next one.
- **After the final block's ACK** both ends are idle. The legacy READY / status / READY_ACK step
  after each block is gone: the ACK replaces it.
- **Final block**: the receiver leaves as soon as it has answered, so its answer is sent twice
  (section 3.7). A single damaged byte can no longer make the sender resend to a receiver that
  has gone. Two damaged bytes in the same answer still can; the sender then reaches its cap and
  reports an error for a transfer that in fact succeeded, never silent corruption.

### 3.4 Why the READY race cannot happen

A burst only starts after the MSX has read the Pi's GO (or header-ACK) byte with a *polled* read:
`OUT ($56)`, wait for `$56` = 0, then `IN`. A polled read is a single transfer whose result is
only read once it has completed, so a stale READY level cannot fool it. The Pi raises READY before
offering that byte and **keeps it up** without a gap into the payload. So every `IN`/`OUT` of the
INIR/OTIR finds READY up and is held by /WAIT until the Pi has clocked it. On the Pi side this is
one RDY-held run: the existing native `msxpi_gpio_burst()` already takes both a transmit and a
receive buffer, so `[ACK] + N receives` or `[ACK] + N sends` is a single call, with no C change.

### 3.5 Error check: CRC-16/CCITT-FALSE

- **Polynomial and init**: 0x1021, **init 0xFFFF**, no reflection. On the server this is
  `binascii.crc_hqx(data, 0xFFFF)` (C code). Not init 0 (CRC-16/XMODEM): with 0 an all-zero frame
  has CRC 0, and the idle link is all zeros - a hunting Pi offers 0x00 on every transfer - so an
  MSX that had slipped out of step read it as a valid empty final block (section 3.7).
- **Detection**: every 1-, 2- and 3-bit error and every odd number of flipped bits in blocks up to
  4 KB, and every burst of 16 bits or fewer. For 8 KB blocks the only two-bit errors it misses are
  those exactly 32,767 bits apart.
- **On the MSX**: a 512-byte table (high and low bytes in two page-aligned 256-byte halves) and a
  tight loop:
  - polled transfers update the CRC with the previous byte while the next transfer is still
    running, which hides it inside the wait;
  - burst transfers checksum the buffer after INIR/OTIR, at about 65-75 T-states a byte against
    about 86 for today's sum loop.

  These are estimates and get measured in the plan's phase 2.
- **ROM placement**: the BIOS half has about 13 KB free, so the table is in ROM. msxpiext.bin
  carries it too, aligned relative to its 4000h load address. For the DOS half see section 6.

### 3.6 Page 1, RAM and slots

As today: a buffer in 4000h-7FFFh is written through WRSLT (STORE_BYTE) and never bursts, because
INIR/OTIR address memory directly. The CRC routine reads the buffer with plain loads, so the table
and the loop live in the ROM/extension in page 1 and the buffer is outside page 1.

### 3.7 What the fault sweep changed

`tests/link2_faults.py` flips one bit at every byte position of a transfer, in both directions,
for burst and polled blocks. The first sweeps found five places where one damaged byte put the
two ends out of step. The rules above are what removed them:

| Damaged byte | What went wrong | Rule |
|---|---|---|
| HELLO2_ACK | The MSX asked again while the Pi was already reading the size word. | The answer and flags are read as a unit; a HELLO2 where the Pi expects the size frame is answered again. |
| size word | A damaged size or mark was skipped; the MSX thought it had opened. | The size is a five-byte frame with its own CRC, answered ACK or NAK. |
| header answer (ACK) | The sender read it as NAK and resent the header while the receiver was already waiting for the payload: an endless mismatch. | Only an exact NAK or ABORT makes the sender resend or stop; anything else counts as ACK. A NAK damaged into garbage is far rarer (it needs a fault in the header first) and is bounded by the limits. |
| answer to the final block | The receiver leaves as soon as it has answered, so a damaged answer sent the sender into the next command's bytes (a hang after the next READY-looking payload byte). | The answer to the final block is sent twice and the sender takes either. This closes the "false error" corner case of section 3.3. |
| GO byte (Pi -> MSX) | A damaged GO made the MSX NAK a burst the Pi was already running. | The MSX does not check the value of the GO byte; it only synchronises. |

Faults of two bits or more in the same byte are covered by the CRC (and by the random multi-bit
test), not by these rules.

The audit of phase 1 added a second sweep, `sweep_slip`: at every MSX transfer of a transfer, one
**slips** - completes on the MSX side without the Pi taking part, as a write lost in the CPLD latch
or a stale read does. Bit flips never change how many transfers each side sees; slips do. It found:

| Slip | What went wrong | Rule |
|---|---|---|
| during the opening, Pi -> MSX | The MSX went on reading the idle link (all 0x00) and took it as a valid empty final block: wrong data, reported as success. | CRC init 0xFFFF (3.5), and a header type must be an RC code. |
| during the data, Pi -> MSX | The MSX aborted, but its ABORT landed where the out-of-step Pi never reads; the Pi resent the block up to 32 times and swallowed every retry of the next command. | The aborting receiver repeats ABORT for one block and its framing; a sender stops on HELLO2 in an answer slot. |

With these rules a slip anywhere ends in a reported abort and never hangs, and the next command
works within three tries (most at once). Results: 2,384 slip positions over two block sizes and
both directions, no hang, no stuck link.

**End mark**: a slip misaligns the block, and a misaligned block is accepted when it happens to
match its CRC: 1 in 65,536 per misaligned block for any 16-bit check. The sweep hit exactly one
(Pi -> MSX, 512 bytes, slip at MSX transfer 37: the shifted payload and the shifted CRC bytes
agree, 0x856F). Bit flips cannot do this; only slips can. So every block now ends with an end
mark, `seq XOR 0xFF`, after its CRC: a misaligned block must also bring the right end mark to the
right place, 1 in 16.7 million, for one extra transfer per block. With the end mark the sweep is
clean: 2,384 slip positions, no wrong data, no hang, no stuck link, and the case at transfer 37
is NAKed and resent.

## 4. Ethernet (UNAPI) - protocol 3

- **What changes**: ETH_SEND_FRAME and ETH_GET_FRAME bursts start with the Pi's GO byte (as in
  3.4), and `ETH_RC_OK` becomes non-zero (0x5A). The frame check stays the 8-bit sum: the hot path
  is speed-critical, and IP, TCP and UDP carry checksums of their own. This is open question 2 in
  the implementation plan.
- **Choosing the version**: the driver sends `OP_PROBE3` (0xCA) instead of `OP_PROBE` (0xC0). The
  server answers with protocol 3 and serves that driver in v3 until the next probe. Only one ROM
  half is ever mapped, so only one ROM driver is active at a time.
- **The choice survives a server restart**: a driver probes only when it starts and on ETH_RESET, so a
  server that came back in protocol 2 would fail every transaction of a v3 driver until the MSX is reset.
  The server keeps the last probe's version as `ETHPROTO` in msxpi.ini (written only when a probe changes
  it, as `p update` keeps `DriveM`) and the shuttle starts from it. A v2 driver probes when it starts, so a
  value left at 3 cannot mislead it. `--reset-ini` drops it; the next probe sets it again.
- **One protocol at a time**: a v2 RAM driver (`ETHUNAPI.COM`) installed next to the BIOS half's v3 ROM
  driver switches the server back to 2 when it probes, and the ROM driver then fails until its next
  probe. Use one or the other; this is not worked around.
- **Builds**: `ethrom.bin` is built twice, v2 for the DOS half (unchanged) and v3 (`ethrom3.bin`, from
  `ethrom3.asm`, which defines `ETH_V3` and includes `ethrom.asm`) for the BIOS half. The v3 image is 1381
  bytes and starts at `UNAPI_ORG3` = 7A80h, 73 bytes below the v2 origin (7AC9h), to make room; 27 bytes
  are left below 8000h, and the build reports them.
- **As built**: the MSX reads GO in `ETH_GO` (polled, with wait mode off for that one byte) at the start of
  each reply (`ETH_OPX`, the first block of `FN_GET_FRAME`) and before `ETH_TX_BLOCK`'s OTIR. The server
  sends each reply as one run, GO first (`spi_burst_send`), and takes ETH_SEND_FRAME's payload with
  `spi_burst_recv`. The RC check is a compare with `ETH_RC_OK`, not a test for zero.
- **GO is checked here** (unlike LINK2's, 3.7): an Ethernet reply has no header or CRC, so GO is the only
  thing that says a burst follows. When the server refuses ETH_SEND_FRAME's length it answers BADLEN in
  the GO slot; with GO unchecked the MSX ran its OTIR anyway, and the frame went into the server's opcode
  hunt, where any byte C0h-CAh in it is taken as an opcode (the test sends a frame of C8h, OP_RESET). It
  also stops an IN_STATUS reply, which has no result code, being taken from a link that is out of step. A
  wrong GO fails the transaction, and `ETH_FAIL`'s resync drains the rest.
- **Tested**: `test_ethshuttle` (shuttle, both protocols, the kept version) and `test_eth3_z80`: the
  assembled driver, v2 and v3, in /WAIT and polled mode, against the real shuttle on the lockstep wire
  (probe, in_status, get_frame, send_frame 16..1514, bad checksum, GO placement, a refused length, a server
  restart). Not yet run: ETHTEST/ETHBENCH in openMSX with a disk system, and real hardware (phase 4).

## 5. Software structure

### 5.1 MSX side

- **New, paired names** (section 5.3) with the register contracts of the legacy routines. The
  legacy names (`SENDDATA`, `PerformHandshake`, `RECVDATA_ONEBLOCK`, `SendCommandToMSXPi`...)
  remain as aliases only for callers not yet converted. `msxpi_call.asm` and `msxpiext.asm` move
  to the new names in phase 2, the DOS driver in phase 6, the .COM tools in phase 7.
- **Selected at build time** with `-DMSXPI_LINK2`. The BIOS half and msxpiext.bin set it; the DOS
  half does not until phase 6 of the plan.
- **New code goes in its own file**, `asm-common/include/link2.asm`: CRC table and update, block
  send/receive, header and ack handling, the burst entry with GO. The legacy code stays in
  `msxpi_bios.asm` under `IFNDEF MSXPI_LINK2`, so each image carries only one protocol.
- **Size work**: `msxpi_call.asm` (the CALL MSXPI parser) and `msxpi_bios.asm` get an optimisation
  pass and may be rewritten (user's note). Every byte saved there is room the DOS driver needs.

### 5.2 Server

- **`msxpi_link2.py`**: the LINK2 framing, written against the same transport primitives. Its
  functions are named `link2_*` (`link2_accept`, `link2_send_block`...): they are the LINK2 half
  behind the public `link_*` functions of `msxpi_blocks.py`, not a second API.
- **`msxpi_blocks.py`** has the paired names of section 5.3 as its public functions. Each one
  hunts for READY or HELLO2 and then runs the legacy or the LINK2 framing. Every command handler
  was converted in one rename-only commit and the old names are gone.
- **Transport** gains `spi_burst_send(data)` and `spi_burst_recv(n)`: GO plus payload in one
  READY-held run, for native GPIO, fast GPIO and the TCP-framed openMSX link.
- **Ethernet**: `msxpi_eth.py` gets protocol 3 next to 2 (`OP_PROBE3`, GO bursts, `RC_OK` 0x5A).

### 5.3 Naming: one name per wire operation, paired across the link

Today the same operation has unrelated names on the two sides. The MSX's `SENDDATA` is answered
by the server's `recvdata2`; the MSX's `RECVDATA_ONEBLOCK` by `sendmultiblock` /
`senddata_oneblock`; `PerformHandshake` exists on both sides with different roles. LINK2 names
every operation once, from the side that runs it:

- **Rules**:
  - same noun on both sides, opposite verb: what one side **sends** the other **receives**
  - prefix `LINK_` on the MSX (asm labels, upper case) and `link_` on the server (snake case);
    C on the MSX uses the asm names in lower case (`link_send()`)
  - suffixes: `_BYTE` (one transfer), `_BLOCK` (one framed block), none (a whole transfer of one or
    more blocks)
- **Pairs**:

| Wire operation | MSX side | Server side |
|---|---|---|
| open a transfer (HELLO2 exchange) | `LINK_OPEN` | `link_accept` |
| one byte, MSX -> Pi | `LINK_SEND_BYTE` | `link_recv_byte` |
| one byte, Pi -> MSX | `LINK_RECV_BYTE` | `link_send_byte` |
| one block, MSX -> Pi | `LINK_SEND_BLOCK` | `link_recv_block` |
| one block, Pi -> MSX | `LINK_RECV_BLOCK` | `link_send_block` |
| whole transfer, MSX -> Pi | `LINK_SEND` | `link_recv` |
| whole transfer, Pi -> MSX | `LINK_RECV` | `link_send` |
| command (name + parameters) | `LINK_COMMAND` | `link_recv_command` (server main loop) |
| burst payload, MSX -> Pi (OTIR after GO) | `LINK_BURST_SEND` | `spi_burst_recv` |
| burst payload, Pi -> MSX (INIR after GO) | `LINK_BURST_RECV` | `spi_burst_send` |
| CRC-16 | `LINK_CRC` | `link_crc` |
| claim / release the shared link | `LINK_CLAIM` / `LINK_RELEASE` | - |

- **Legacy names map onto these**: `SENDDATA` -> `LINK_SEND`, `RECVDATA_ONEBLOCK` ->
  `LINK_RECV_BLOCK`, `PIREADBYTE` -> `LINK_RECV_BYTE`, `PIWRITEBYTE` -> `LINK_SEND_BYTE`,
  `SendCommandToMSXPi` -> `LINK_COMMAND`, `PerformHandshake` -> `LINK_OPEN`. On the server:
  `recvdata2` -> `link_recv` (and `link_recv_command` in the main loop), `sendmultiblock` ->
  `link_send`, `senddata_oneblock` -> `link_send_block`, `recvdata2_oneblock` ->
  `link_recv_block`, `PerformHandshake` and `pcopy_handshake` -> `link_accept`, and
  `SPI_ByteTransfer` -> the `link_send_byte` / `link_recv_byte` pair (one primitive bound to both
  names, so the hot path has no extra call; both return the byte the MSX sent). `senddata`, the
  legacy sender for receivers that confirm every block (C `RECVDATA`), becomes
  `link_send_confirmed`; under LINK2 it is the same as `link_send`. The legacy framing keeps its
  own internal names; only the public entry points change.
- **The other BIOS routines** get the same treatment in the phase 5 rewrite: one verb-noun scheme
  (`PRINT_PI_STDOUT`, `PARSE_CALL_PARAMETERS`...), no mixed case, and no two names for one
  routine.

## 6. The DOS half (later phase)

The DOS half has about 60-80 bytes free today; LINK2 needs the table (512 bytes) and its code
there. The budget comes from, in order:

1. the legacy routines that LINK2 replaces (SENDDATA, RECVDATA_ONEBLOCK, the status handshakes),
2. the optimised CALL handler and BIOS code,
3. only if still short: a table-less CRC in the DOS half alone (+~40 T-states a byte on burst
   reads), or moving part of the Ethernet driver out of the DOS half.

The decision is made from measured sizes, not estimates.

## 7. Compatibility

| MSX side | Server | Result |
|---|---|---|
| legacy ROM / .COM tools | new server | legacy protocol, as today (plus the upload-hang fix) |
| LINK2 BIOS half / msxpiext.bin | new server | LINK2 |
| LINK2 BIOS half / msxpiext.bin | old server | clean error: "server does not speak LINK2 - update" |
| DOS half (legacy) + BIOS half (LINK2) in one EEPROM | new server | each half speaks its own protocol; a jumper apart |

**Update order**: server first (`msxpiupd` runs from MSX-DOS, which is still legacy), then flash
the ROM image and copy msxpiext.bin. `msxpiupd` itself keeps working throughout.

## 8. MSX implementation reference (for phase 2)

The executable reference is **`software/Server/Python/tests/link2_sim.py`, class `Msx`**: the Z80
code must put the same bytes on the wire in the same order, and react to every answer the same
way. It is what the server's tests run against (the unit tests, the flip and slip sweeps, 10,000
random transfers). Where the Z80 code or this section disagrees with `Msx`, `Msx` is right and
the document gets fixed.

### 8.1 Constants (asm `EQU`s)

Values as on the server (`msxpi_const.py`, and `FLOOD_MARGIN` in `msxpi_link2.py`); the
MSX-only `WRONG_ANSWERS` and the MSX's own `FLOOD_MARGIN` are in `link2_sim.Msx`.

| Name | Value | Use |
|---|---|---|
| `HELLO2` / `HELLO2_ACK` / `SIZE_MARK` | 0xB2 / 0xB3 / 0xB4 | opening |
| `LINK_ACK` / `LINK_NAK` / `LINK_ABORT` | 0x5A / 0xA5 / 0x0F | answers; ACK is also the GO byte |
| `LINK2_FLAG_BURST` | 0x01 | bit 0 of the flags after HELLO2_ACK |
| `LINK2_RETRIES` | 10 | NAKs per block before the receiver aborts |
| `LINK2_SENDER_CAP` | 32 | attempts per block (and per size frame) before the sender gives up |
| `LINK2_WRONG_ANSWERS` | 16 | completed HELLO2 exchanges with a wrong answer before RC_PROTOERR |
| `LINK2_FLOOD_MARGIN` | 16 | ABORT flood length = the MSX's block size + 16 |
| `RC_PROTOERR` | 0xF0 | protocol error; valid header types are 0xE0-0xF0 |

### 8.2 CRC-16/CCITT-FALSE

- Poly 0x1021, init 0xFFFF, MSB first, no reflection, no final XOR. Check value:
  CRC("123456789") = **0x29B1** (`binascii.crc_hqx(b"123456789", 0xFFFF)`).
- Table, MSB first: for i in 0..255: c = i << 8; 8 times: c = ((c << 1) ^ 0x1021) if c & 0x8000
  else (c << 1); T[i] = c & 0xFFFF. Kept as two 256-byte page-aligned halves (high bytes, low
  bytes), generated by `asm-common/transport/generate.py`.
- Update for one byte b: idx = (crc >> 8) ^ b; crc = ((crc << 8) & 0xFFFF) ^ T[idx]. With the CRC
  in DE (D high) and the byte in A: `xor d / ld l,a / ld h,TBL_HI / ld a,(hl) / xor e / ld d,a /
  inc h / ld e,(hl)`.
- Covers the size frame (mark, lo, hi), the block header (4 bytes) and the payload, each with its
  own CRC; sent low byte first.

### 8.3 Byte primitives

- **Polled read** (`LINK_RECV_BYTE`): wait for `$56` = 0, `OUT ($56),0`, wait for `$56` = 0,
  `IN ($5A)`. One transfer, read only after it has completed.
- **Polled write** (`LINK_SEND_BYTE`): wait for `$56` = 0, `OUT ($5A),byte`. Returns at once; the
  next primitive's wait covers completion.
- **Burst** (`LINK_BURST_RECV` / `LINK_BURST_SEND`): only straight after a polled read of the Pi's
  GO byte (3.4): `OUT ($57),1`, INIR/OTIR in 256-byte runs, `OUT ($57),0`, then the CRC pass over
  the buffer. Never with a buffer in page 1.
- CTRL+ESC is checked in every wait, as today (`PAYLOAD_ESCAPE`), and returns RC_ESCPRESSED.

### 8.4 LINK_OPEN (the MSX opens every transfer)

```
repeat:  write HELLO2; read answer; read flags          (always all three)
         answer = HELLO2_ACK -> done; else wrong += 1; wrong = 16 -> RC_PROTOERR
size word = block size | 0x8000 if (/WAIT present and buffer not in page 1 and the caller allows)
repeat up to 32: write SIZE_MARK, lo, hi, crc lo, crc hi; read answer
         ABORT -> RC_PROTOERR; NAK -> again; anything else -> open
burst allowed = (flags bit 0) and (size word bit 15)
```

### 8.5 LINK_SEND_BLOCK (MSX -> Pi)

```
burst = allowed and len > 0 and len % 256 = 0
repeat up to 32 (same seq every time):
    write type, len lo, len hi (| 0x80 if burst), seq, hcrc lo, hcrc hi
    read answer: ABORT -> RC_PROTOERR; NAK -> again; anything else -> go on (if burst, it was GO)
    payload: OTIR (burst) or polled writes
    write crc lo, crc hi, end mark (seq XOR 0xFF)
    read 1 answer (2 when type is not RC_READY): any ACK -> done; any ABORT -> RC_PROTOERR; else again
cap reached -> RC_PROTOERR
```

### 8.6 LINK_RECV_BLOCK (Pi -> MSX)

```
loop:
    read 6 header bytes; header crc wrong -> write NAK (1 byte), count it, again
    type not in 0xE0..0xF0, or seq neither next nor last, or len > block size or > room left
    in the caller's buffer (a duplicate: block size only)
        -> write ABORT, flood, RC_PROTOERR
    write ACK; burst: polled read of GO (value not checked), then INIR; else polled reads
    read crc lo, crc hi, end mark
    crc or end mark wrong -> write NAK (twice if type is not RC_READY), count it, again
    write ACK (twice if type is not RC_READY)
    seq = last seq (a duplicate) -> discard it, reset the count, again
    keep it: last = seq, next = seq + 1; return type and length
count reaches 10 -> write ABORT (twice if final), flood, RC_PROTOERR
flood = block size + 16 polled writes of ABORT
```

A transfer (`LINK_RECV`) repeats `LINK_RECV_BLOCK` until a type other than RC_READY, which is the
transfer's result code for the caller. `LINK_SEND` cuts the data into blocks no larger than the
Pi's limit, tags every block but the last RC_READY and the last RC_SUCCESS (or the caller's code).

### 8.7 What the MSX can rely on from the server

- It answers HELLO2 again whenever a HELLO2 arrives where the size frame should be.
- Every Pi -> MSX burst starts with the GO byte, and READY stays up into the payload.
- It sends single answers in header slots and doubled answers after a final block.
- When it aborts it repeats ABORT until the MSX's next HELLO2 or READY arrives.
- A legacy READY transfer and a LINK2 transfer can follow each other with no reset between them.

### 8.8 The MSX code as built (phase 2: `asm-common/include/link2.asm`)

Public entry points (registers in the file header of `link2.asm`):

| Entry | In | Out |
|---|---|---|
| `LINK_SEND` | DE = source, BC = length | NC: DE = source + length, BC = 0. C: A = RC_* |
| `LINK_SEND_SIZE` | as `LINK_SEND`, HL = largest block (default 8192) | as `LINK_SEND` |
| `LINK_RECV` | A = mode, DE = buffer, BC = largest block | NC: A = the transfer's result code, DE = end of data (mode 2), BC = bytes received. C: A = RC_* |
| `LINK_COMMAND` | DE = zero terminated string | as `LINK_SEND`; C and nothing sent when empty |
| `LINK_SEND_BYTE` / `LINK_RECV_BYTE` | A = byte / - | A = byte; C = CTRL+ESC (A = RC_ESCPRESSED) |

`LINK_RECV` modes: 0 = blocks are read into the buffer and dropped (`STDOUTTONULL`); 1 = each block is
printed, a zero put after it first, so the buffer needs BC+1 bytes (`PRINTPISTDOUT`); 2 = blocks follow
one another from the buffer (`CALL MSXPI("2,..")`). The legacy names that remain are `SENDDATA`,
`SendCommandToMSXPi`, `PRINTPISTDOUT` and `STDOUTTONULL`, as thin aliases; `PerformHandshake` and
`RECVDATA_ONEBLOCK` have no equivalent (a transfer is opened and read in one call), and the `BIOSENTRY`
table of msxpiext.bin lists `LINK_SEND_SIZE`, `LINK_RECV`, `LINK_SEND` and `LINK_COMMAND` in their slots.

How it differs from the paper description above, on purpose:

- **State** lives in a frame on the stack (IX), so the code runs from ROM. Nothing outlives a call.
- **CRC in the shadow set** (DE' = CRC, H' = table page): the BIOS interrupt routine saves and restores
  both sets. Polled receive starts the next transfer before it stores and checksums the byte it has just
  read, and polled send takes each byte into the CRC while that byte goes out, so the CRC work happens
  inside the wait for the Pi. The burst paths run a CRC pass over the buffer after INIR/OTIR.
- **Page 1**: `CALL MSXPI("2,addr,..")` runs from BASIC, where page 1 is ROM and the RAM starts at 8000h, so
  a buffer below 8000h is not a use case and is not tested. `STORE_BYTE` (WRSLT through RAMAD1, a slot only
  a disk kernel sets) serves the DOS half. A buffer below 8000h never bursts; the size word's bit 15 is set
  only for a buffer at 8000h or above on a board with /WAIT (the test of `DSKIO_RXSIZE`: does `$57` change
  when wait mode goes on).
- **Room in mode 2**: the caller gives no size, so the MSX uses what the RAM has: a block that would end past
  F380h (the system area) from a buffer below it, or past FFFFh, is ABORTed in its header. A block that ends
  exactly at 10000h wraps the sum to 0 and is judged as "past F380h" too (the first version let one from
  below F380h through). T3 covers all three.
- **Mode 1 needs BC+1 bytes**: `CALL MSXPIVER` reads up to 127 bytes into the 128 below HIMEM, so the
  terminator never lands on HIMEM itself.
- **L2TEST** reads the server's summary after every send, failed or not: the `l2test sink` command answers
  a failed receive too, and an unread answer would be taken by the next repetition's command.
- **Names**: `msxpi_call.asm` and the msxpiext table use `LINK_COMMAND`, `LINK_PRINT`, `LINK_DISCARD`,
  `LINK_RECV_BYTE` and `LINK_SEND_BYTE`; the legacy DOS half defines the first three as aliases of its own
  routines. `PIREADBYTE`/`PIWRITEBYTE` are not assembled in a LINK2 build.
- **Registers**: the `LINK_*` routines clobber IY and keep the CRC in the shadow set. Safe under the BIOS
  interrupt handler, which saves both; recheck before the DOS driver and the .COM tools move to LINK2.
- **Z80 emulator** (tests): `inc/dec (ix+d)` is 23 T-states; every opcode fetch costs the MSX's extra wait state
  (`m1_wait`, 0 for a bare Z80).
- **DOS half room**: the build prints it (`msxpibios: ... bytes free below the UNAPI driver`).
- **A damaged flags byte** can leave the Pi bursting to a MSX that thinks it cannot. The MSX reads the GO byte
  whenever a header says "burst", and uses INIR only if it allowed bursts and the length is a non-zero
  multiple of 256; otherwise it reads the payload polled, as the model does.
- **A duplicate in mode 2** is read over the block it repeats (ptr - length), never past the end of the data.
- Header, ACK and size-frame error handling, the doubled final answers, the NAK limit and the ABORT flood
  are as in 8.4 to 8.6, line for line.
