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
| `ACK` | 0x5A | receiver -> sender | header or block accepted; also the Pi's "go" byte for bursts |
| `NAK` | 0xA5 | receiver -> sender | resend |
| `ABORT` | 0x0F | either | give up this transfer |

ACK, NAK and ABORT differ from each other in at least 4 bits. **Any other value read where one of
them is expected is treated as NAK.** That includes 0x00 and 0xFF, the values a stale or idle link
gives. 0xB2 and 0xB3 are used by nothing else: the RC codes are 0xE0-0xEF, the handshake bytes
0xA0-0xAE, the Ethernet opcodes 0xC0-0xC9.

### 3.2 Opening a transfer

Every transfer starts with the MSX, exactly as the legacy one does (SENDDATA, PerformHandshake):

```
MSX -> HELLO2                        (repeated until HELLO2_ACK; see below)
Pi  -> HELLO2_ACK
Pi  -> flags     bit 0: the Pi can burst in both directions (native/fast GPIO, or TCP-framed openMSX)
MSX -> size lo, size hi              largest block the MSX accepts; bit 15 = this MSX has /WAIT
```

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
R -> ACK | NAK | ABORT
```

- `len` bit 15 = "this block bursts". It is protected by the header CRC.
- `seq` counts 0..255 per transfer and wraps.
- On a header NAK, the sender resends the header (counted as an attempt).
- On a payload NAK, the sender resends the whole block (header included) with the **same seq**.
- **Duplicates**: the receiver remembers the last seq it accepted. A block that arrives with that
  same seq means its ACK was lost: the receiver reads it in full, discards it and ACKs again. Any
  seq other than the last one or the next one makes the receiver ABORT.
- **One retry limit, on the receiver**: after `LINK2_RETRIES` (10) consecutive NAKs for one block,
  the receiver sends ABORT. The sender has no limit of its own except a safety cap (32 attempts)
  and CTRL+ESC on the MSX, for a receiver that has disappeared.
- **After the final block's ACK** both ends are idle. The legacy READY / status / READY_ACK step
  after each block is gone: the ACK replaces it.
- **Known corner case**: if the ACK of the *final* block is corrupted, the sender resends to a
  receiver that has already left. The sender reaches its cap and reports an error for a transfer
  that in fact succeeded. That is a false error, never silent corruption. Every current command
  can safely be repeated.

### 3.4 Why the READY race cannot happen

A burst only starts after the MSX has read the Pi's GO (or header-ACK) byte with a *polled* read:
`OUT ($56)`, wait for `$56` = 0, then `IN`. A polled read is a single transfer whose result is
only read once it has completed, so a stale READY level cannot fool it. The Pi raises READY before
offering that byte and **keeps it up** without a gap into the payload. So every `IN`/`OUT` of the
INIR/OTIR finds READY up and is held by /WAIT until the Pi has clocked it. On the Pi side this is
one RDY-held run: the existing native `msxpi_gpio_burst()` already takes both a transmit and a
receive buffer, so `[ACK] + N receives` or `[ACK] + N sends` is a single call, with no C change.

### 3.5 Error check: CRC-16/XMODEM

- **Polynomial and init**: 0x1021, init 0, no reflection. On the server this is
  `binascii.crc_hqx(data, 0)` (C code).
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

## 4. Ethernet (UNAPI) - protocol 3

- **What changes**: ETH_SEND_FRAME and ETH_GET_FRAME bursts start with the Pi's GO byte (as in
  3.4), and `ETH_RC_OK` becomes non-zero (0x5A). The frame check stays the 8-bit sum: the hot path
  is speed-critical, and IP, TCP and UDP carry checksums of their own. This is open question 2 in
  the implementation plan.
- **Choosing the version**: the driver sends `OP_PROBE3` (0xCA) instead of `OP_PROBE` (0xC0). The
  server answers with protocol 3 and serves that driver in v3 until the next probe. Only one ROM
  half is ever mapped, so only one driver is active at a time.
- **Builds**: `ethrom.bin` is built twice, v2 for the DOS half (unchanged) and v3 for the BIOS half.

## 5. Software structure

### 5.1 MSX side

- **Same entry points**: the LINK2 routines keep the names and register contracts of the legacy
  ones (`SENDDATA`, `PerformHandshake`, `RECVDATA_ONEBLOCK`, `SendCommandToMSXPi`), so
  `msxpi_call.asm`, `msxpiext.asm` and later the DOS driver need no changes to their callers.
- **Selected at build time** with `-DMSXPI_LINK2`. The BIOS half and msxpiext.bin set it; the DOS
  half does not until phase 6 of the plan.
- **New code goes in its own file**, `asm-common/include/link2.asm`: CRC table and update, block
  send/receive, header and ack handling, the burst entry with GO. The legacy code stays in
  `msxpi_bios.asm` under `IFNDEF MSXPI_LINK2`, so each image carries only one protocol.
- **Size work**: `msxpi_call.asm` (the CALL MSXPI parser) and `msxpi_bios.asm` get an optimisation
  pass and may be rewritten (user's note). Every byte saved there is room the DOS driver needs.

### 5.2 Server

- **`msxpi_link2.py`**: the LINK2 framing, written against the same transport primitives.
- **`msxpi_blocks.py`** keeps its public functions (`recvdata2`, `sendmultiblock`, `senddata`,
  `recvdata2_oneblock`, `PerformHandshake`). Each one hunts for READY or HELLO2 and hands a LINK2
  transfer to `msxpi_link2`, so no command handler changes.
- **Transport** gains `SPI_BurstGoOut(data)` and `SPI_BurstGoIn(n)`: GO plus payload in one
  READY-held run, for native GPIO, fast GPIO and the TCP-framed openMSX link.
- **Ethernet**: `msxpi_eth.py` gets protocol 3 next to 2 (`OP_PROBE3`, GO bursts, `RC_OK` 0x5A).

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
