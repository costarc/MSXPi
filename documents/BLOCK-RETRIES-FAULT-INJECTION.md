# Block retries and link faults: what recovers, what desyncs

Branch `fix/otir-desync-retries` (off `feature/tcpip-games`, 2026-10-25). Question: after the OTIR
change, a real MSX desynced twice in one day. Would a larger `GLOBALRETRIES` (3 -> 20) help, and
does MSX-DOS + the MSXPi driver recover from link errors at all?

## How a block is retried

Every block is `[header_rc][len lo][len hi][index][payload][checksum]`. The receiver echoes its own
checksum, and **each end compares the two checksums and decides by itself** whether to resend.
Nothing on the wire says "I give up". So a retry limit only works when the other end stops at the
same point, or never stops and just follows:

| Direction | MSX side (limit) | Server side (limit) |
|---|---|---|
| ROM `SENDDATA` -> `recvdata2` (disk writes, commands, CALL MSXPI) | `GLOBALRETRIES` = 3 | none, follows the MSX |
| Pi `senddata_oneblock` -> ROM `RECVDATA_ONEBLOCK` (disk reads) | `GLOBALRETRIES` = 3 | `MAX_BLOCK_RETRIES` = 3 |
| Pi `senddata_oneblock` -> C `RECVDATA_ONEBLOCK` + caller loop (pcopy, mchat, ssh...) | `MAX_BLOCK_RETRIES` = 3 (msxpi.h) | `MAX_BLOCK_RETRIES` = 3 |
| C `SENDDATA2` -> `recvdata2_oneblock` (pcopy upload) | none | **3 - mismatch, see below** |

When the limits differ:

- **Server resends after the MSX gave up.** The server is still pushing an 8 KB block when the MSX's
  next transaction starts. In MSX-DOS that is DSKIO (`dskios`), so every Retry at
  "Disk error reading drive A" is eaten by the stale resend. Seen as 60+ retry prompts in a row
  (config B below).
- **MSX resends after the server gave up.** The server is back in its command loop and never answers
  with a matching checksum, so a sender without a limit (C `SENDDATA2`) loops until CTRL+ESC. That is
  the pcopy upload hang below, and it is in the released code today.

Retries only cover a corrupted **payload**. A corrupted header, status byte or checksum byte fails
the transfer at once, whatever the limit. Those were seen to be reported ("Disk error writing",
"Error connecting to MSXPi server") and to recover at the next command, because every transaction
starts by hunting for READY.

## Test harness

`software/Server/Python/tests/fault_server.py` runs msxpi-server.py with `tcp_exchange` wrapped: every
byte of the openMSX virtual-SPI link, in either direction, gets one random bit flipped with probability
`FAULT_RATE`. `fault_inject_openmsx.py` boots Canon_V-25 + MSXPi (MSX-DOS from a scratch msxpiboot.dsk)
and runs FI.BAT:

```
pcopy /tmp/fi/fi1.com          (msxarch.com, 14 KB)  pcopy download + DSKIO writes
pcopy /tmp/fi/fi2.com          (ssh.com,     12 KB)
pcopy /tmp/fi/fi3.com          (pchess1.com, 41 KB)
pcopy A:MCHAT.COM /tmp/fi/up.com                     pcopy upload + DSKIO reads
p date                                               command channel still alive?
```

It answers "Abort, Retry, Ignore" with R, then compares every file byte by byte. Verdicts:
PASS; FAILED = a transfer was aborted and reported, and the file is missing or a clean prefix of the
source; CORRUPT = wrong bytes landed; HUNG = FI.BAT never finished.

```
python fault_inject_openmsx.py --rate 0.00015 --seed 1 2 3 4 5 6 7 8 --timeout 150
    [--rom rom32.rom] [--server-retries N] [--pcopy PCOPY.COM] [--server-src dir]
```

`--rom` needs `Documents/openMSX/share/extensions/MSXPiTest.xml`, a copy of MSXPi.xml without sha1s
whose `<filename>` is `C:/tmp/fi/msxpitest.rom`. Test ROMs were built with the commands in
ETH-DRIVER-SPEED-HANDOVER.md section 5 (zmac + sjasmplus). An unchanged build reproduces the shipped
`msxpi32k.rom` (sha1 50096592) byte for byte, so each test ROM differs only in its retry constants.

The rate is about 10,000 times worse than a healthy link (100-180 flipped bits per run). It is
chosen so that 3 attempts at an 8 KB block often fail, which is exactly the case being asked about.

## Results (8 seeds per config, rate 1.5e-4; same seed = same faults across configs)

| Config | ROM send / recv | Server recv-from-MSX / send | pcopy | PASS | FAILED (reported) | HUNG | CORRUPT |
|---|---|---|---|---|---|---|---|
| A shipped | 3 / 3 | upload 3 / 3 | 3 | 0 | 0 | **2 of 2** | 0 |
| A' upload fix only | 3 / 3 | follows / 3 | 3 | 0 | 8 | 0 | 0 |
| F (send 20) | 20 / 3 | follows / 3 | 3 | 1 | 7 | 0 | 0 |
| F10 (this branch) | 10 / 3 | follows / 3 | 3 | 1 | 7 | 0 | 0 |
| B | 20 / 20 | follows / 20 | 3 | 1 | 0 | **7** | 0 |
| E all 20 | 20 / 20 | follows / 20 | 20 | 6 | 0 | 0 | **2** |

- **A**: the run is stuck in a pcopy upload. After 3 bad blocks `recvdata2_oneblock` returns
  RC_CHKSUM_ERR ("writeblock received nothing (rc=0xad)"). pcopy's SENDDATA2 has no limit and keeps
  resending its 8 KB block into the command loop, which logs thousands of "out of step" lines. Only
  CTRL+ESC or a reboot ends it.
- **A', F**: no hangs and no wrong bytes. Every FAILED is a reported abort: "Transfer aborted by
  server" when a pcopy 8 KB download block failed 3 times on both sides, and the odd
  "Disk error ..." that one Retry cleared. The faults are seeded, so A' and F see the same ones; F's
  extra send retries saved one disk write (seed 2).
- **B**: the server resends a download block 20 times while pcopy (3) has already given up, then
  eats each DSKIO the DOS retry issues: 60+ "Disk error reading drive A" in a row, never recovering.
  That is what a server-only, or ROM-plus-server-only, raise to 20 does to every client left at 3.
- **E**: everything at 20 gets every transfer through, but twice it wrote wrong bytes into a file of
  the right size. In seed 6, FI3.COM has 2 bytes wrong, in sectors 19 and 27 of the same 8 KB block:
  two bit errors that cancel in the 8-bit folded checksum (+2^k in one byte, -2^k in another).
  A single bit error always changes the sum. Two errors in one block cancel about 1 time in 16 (same
  bit, opposite direction). A link bad enough to need many retries is exactly one with multi-error
  blocks, so **every extra attempt is another chance to accept a bad block**. 3 attempts never let
  one through here; 20 did.

## Recommendation

A larger `GLOBALRETRIES` does have downsides:

- **The limits must match.** Raising it to 20 everywhere is only safe if every MSX binary and the
  server change together: the ROM, pcopy and every C client, the ROM-Patcher game ROMs, and every
  EEPROM already in the field. Any unit left at 3 turns a clean "Transfer aborted" into a lockup
  (config B). The worst case is therefore not "the same as a desync": the mismatch is what *causes* one.
- **The checksum is weak.** On a link noisy enough for retries to matter, more attempts mean more
  bad blocks accepted silently (config E). A desync is noticed; a wrong byte in a file is not.
- Time is not a concern: a sector resend costs milliseconds.

What this branch does:

1. **`SENDRETRIES` = 10** (new, include.asm) for the MSX's own sends: SENDDATA and playnet's `sendBlk`.
   Every server follows the MSX there, so this is safe with old and new servers alike. 10 rather
   than 20: a link that fails half of its blocks aborts 1 time in 8 at 3 attempts and 1 in 1000 at 10,
   while each attempt past that only adds exposure to the checksum weakness.
2. **`GLOBALRETRIES` stays 3** for receiving, matched to the server's `MAX_BLOCK_RETRIES`. The
   comments on both now say they must agree.
3. **`recvdata2_oneblock` follows the sender** like `recvdata2`: no limit. This fixes the pcopy upload
   hang (config A: 2 of 2 hung; with the fix, the upload completed in every run of A', F and F10).
   The released pcopy resends without a limit, so a server limit cannot help it either way.

Follow-ups, not in this branch:

- **A stronger block check** (a 16-bit sum without the fold, or CRC-16) is the real cure for the
  silent-corruption case, and it would make higher retry counts safe. It is a protocol change on
  every MSX binary and the server, so it needs a version flag.
- **More receive retries** need the MSX to tell the server its limit, e.g. a flag in the
  PerformHandshake size word that only new servers honour. Old servers read that word as a size,
  so this needs care.
- **A limit on C `SENDDATA2`** (and `RECVDATA`), so a new pcopy cannot loop forever on a dead link.

## Not explained by retries: the Ethernet OTIR send

The only OTIR left in the ROM is ETH_SEND_FRAME (`459a9d6b`); disk writes have been polled since
`b5d4b574`, because on the Canon V-25 an OTIR could start before the Pi raised READY for the burst
and lose its first bytes. ETH_TX_BLOCK uses the same guard that did not prevent this for disk
writes: one wait for `$56` = 0, then OTIR. If leading bytes are lost, `_op_send_frame` keeps reading
the payload, and the MSX's read of the result code clocks a passive byte, 0x00. 0x00 is `ETH_RC_OK`,
so the MSX believes the frame went out while the Pi is still collecting it, and the MSX's next
transaction (a disk command, if DOS is busy) is taken as payload. That would be a silent desync of
the whole link, visible in MSX-DOS as disk errors. This is reasoning from the code, not reproduced:
the emulator does not have the READY race. It only applies when the Ethernet driver is in use
(INL / TCP/IP). Worth checking whether the two real-MSX desyncs happened with INL loaded.

## Other things found

- pcopy leaves a partial (or empty) file on A: after "Transfer aborted by server".
- `p.c` and `msxarch.c` call C `RECVDATA_ONEBLOCK` once, with no retry loop, while the server resends
  up to 3 times: the same server-resends-after-MSX-gave-up pattern as above, just shorter.
- C `SENDDATA2` and `RECVDATA` have no limit at all; only CTRL+ESC ends them on a dead link.
