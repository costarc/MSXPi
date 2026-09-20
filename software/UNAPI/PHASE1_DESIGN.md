# MSXPi Ethernet UNAPI — Phase 1 Design

Branch: `unapi-ethernet` (off `MSXPiv1.6`)
Date: 2026-08-30
Baseline: CPLD v1.6 (`MSXPIVer "1110"`), BIOS v1.6, post-`498316e`

**Goal:** implement the 12-routine **Ethernet UNAPI** on MSXPi, and run
**InterNestor Lite** on top of it to supply the full 30-routine TCP/IP UNAPI —
so that stock UNAPI applications (telnet, HGET, SNTP, MSXHUB) work on a
Canon V-25 with an MSXPi.

---

## 1. Transport baseline — what v1.6 actually gives us

### 1.1 CPLD semantics (read from `MSXPi.vhd`, not assumed)

| Condition | Behaviour |
|---|---|
| `OUT ($57),$01` | `wait_mode` = 1 |
| `OUT ($57),$00`, or `OUT ($56),$FF` (reset) | `wait_mode` = 0 |
| `IN ($57)` | `$0E` mode off, **`$8E` mode on** (bit 7 = mode read-back) |
| `wait_mode=0` | identical to v1.3 — `WAIT_n` never driven |
| `wait_mode=1`, `IN ($5A)`, `SPI_RDY=1` | **starts a transfer AND stalls the Z80** until the byte completes |
| `wait_mode=1`, `IN ($5A)`, `SPI_RDY=0` | no transfer, no stall — returns the stale buffer |

`spi_en <= ... or (wait_mode='1' and readoper='1' and is_data='1' and SPI_RDY='1')`

The `SPI_RDY` gate is the safety property that makes this usable: with no Pi
present, a burst read degrades to reading stale bytes instead of hanging the bus.

### 1.2 The fast path exists and is unused

`grep` across the whole `software/` tree: **nothing writes `$57`, and there is
no `INIR`/`OTIR` anywhere.** The v1.6 speed-up (~80%) came from tightening
`CHKPIRDY`'s poll loop and the Pi-side `/dev/gpiomem` fast GPIO path — all in
**legacy mode**.

So the hardware `/WAIT` burst path has **no consumer yet**. This driver will be
the first, and it inherits the fast path with no legacy-compatibility burden.

### 1.3 Per-byte cost

| Path | Z80 cost/byte |
|---|---|
| `PIREADBYTE` (legacy, current) | ~240 T-states (~67 µs) — was ~330 T |
| `INIR` with hardware `/WAIT` | 21 T-states + however long the Pi stalls us |

**The Pi is still the dominant term and its current value is unmeasured.** The
profiler added in v1.6 (`MSXPI_PROFILE=1`) exists precisely to answer this.
See §6 — this number gates the MTU decision and nothing else in this document
depends on it.

### 1.4 Doc nit found while reading

`MSXPi.vhd` D_out process: one comment line says *"$0E disabled, $1E enabled"*,
the later block correctly says *"Reads $0E with the mode off, $8E with it on."*
The code (`wait_mode & '0' & "00" & MSXPIVer`) gives **$8E**. The `$1E` line is
stale. Harmless, but it will mislead whoever writes the detection code.

---

## 2. BLOCKING ISSUE — MSXPi is a single shared channel

**This is the one thing that must be decided before any code is written.**

InterNestor Lite runs from the **50/60 Hz timer interrupt hook** and calls
`ETH_IN_STATUS` (and often `ETH_GET_FRAME`) on *every* interrupt.

Meanwhile, on this setup MSXPi is also the **disk**: the boot disk and Drive A:
are served by `msxpi-server.py` over the same ports `$56`/`$57`/`$5A`.

So the moment INL is resident:

> A foreground MSX-DOS/Nextor disk read is part-way through a `SENDDATA` /
> `RECVDATA_ONEBLOCK` block transfer. The timer interrupt fires. Our ISR issues
> its own `IN ($5A)`. **Both streams desynchronise permanently.**

Verified: there is **no guard of any kind** in `msxpi_bios.asm` or
`msxpi-driver.mac` — no semaphore, no in-use flag, no `DI` around block
transfers. Nothing today needs one, because nothing else ever touched the port.

It gets worse in WAIT mode: our ISR would also flip `$57`, changing the transfer
semantics underneath a foreground routine that assumes legacy polling.

### 2.0.1 A second, independent failure: the per-byte device check

`PIREADBYTE` decides *what kind of device it is talking to* on *every byte*:

```
in   a,(CONTROL_PORT2)   ; $57
cp   $FE                 ; openMSX returns $FE
jr   c,PIREADBYTE_SUCC   ; below $FE -> physical MSXPi
```

While our driver holds wait mode on, `$57` reads `$8E`. Trace both devices:

| device | `$57`, wait mode on | stock code concludes | result |
|---|---|---|---|
| real MSXPi v1.6 | `$8E` | `$8E < $FE` -> physical | **correct** - same branch as `$0E` |
| openMSX | `$8E` | `$8E < $FE` -> physical | **wrong** - skips the "wait for state 2" loop |

So a leaked wait mode is harmless to legacy code on real hardware, because
`$0E` and `$8E` both select the same branch - but in emulation it makes stock
routines read stale bytes. That is the same class of bug as the `ETH_WAIT_DATA`
defect fixed in Phase 5b, where accepting `$56 = 0` from openMSX returned the
`$FF` "no data ready" filler as if it were real data.

Two consequences:

1. Wait mode being per-transaction is not just tidiness, it is load-bearing -
   and `ETH_END` must be on every exit path, including error paths.
2. It is a second, independent reason Option A matters: even with a correct
   driver, disk I/O running *during* one of our transactions would misdetect
   the device in emulation. The byte-stream desync above and this device
   misdetection are separate failures with the same root cause.

### 2.1 Options

**Option A — shared in-use flag (recommended).**
A single byte in a fixed RAM location. The existing block routines
(`SENDDATA`, `RECVDATA_ONEBLOCK`, `PerformHandshake`, `SendCommandToMSXPi`) set
it on entry and clear it on exit. Our ISR does a `DI`-protected
test-and-set; if the flag is already set it **returns "no frames available"
immediately and tries again on the next interrupt.**

- Cost: a small, surgical change to shared BIOS code, and a coordinated release
  (ROM and driver must ship together — see the existing rule that ROM and
  bitstream are flashed separately).
- Missing a poll for one or two 60 Hz ticks is harmless: TCP retransmits, and
  frames sit in the Pi's buffer meanwhile.
- Cheap, correct, and the ISR never blocks the foreground.

**Option B — ISR skips while any I/O is in flight**, detected by reading
`$56`/`SPI_RDY` state. Rejected: not atomic, and it cannot distinguish "Pi busy
with someone else's byte" from "Pi busy with mine".

**Option C — foreground `DI` around block transfers.** Rejected: a 512-byte
block with interrupts off is ~34 ms at the current rate, which would break the
50/60 Hz clock, key repeat, and INL's own timers.

**Option D — do not use MSXPi as the disk while networking.** Boot and run from
the MegaFlashROM SCC+SD instead, leaving MSXPi exclusively for the network. No
code change at all. Viable as a **first-milestone workaround**, and it makes the
early phases much simpler, but it is not a shippable end state.

### 2.2 Decision — AGREED 2026-08-30

**Build against Option D, ship Option A.** Phases 2–6 run with the disk on the
MegaFlashROM SCC+SD so no shared-channel work blocks the UNAPI development;
Option A (the shared in-use flag in the block routines, plus the `DI`-protected
test-and-set in the ISR) is added as a discrete task before release. The openMSX
harness must be able to model both configurations.

Consequences for the phases that follow:

- **Phase 2 harness** builds the openMSX config as `Canon_V-25` +
  `MegaFlashROM_SCC+_SD` (disk/mapper) + `MSXPi` (network only). Item O4 is
  therefore on the critical path for Phase 2, not a nice-to-have.
- **Phase 5a** still implements the re-entrancy flag and `DI`-guarded critical
  sections — those protect the driver against *itself* (a client-initiated
  `ETH_SEND_FRAME` interleaving with the ISR's `ETH_IN_STATUS`) and are needed
  regardless of Option D.
- **Option A becomes a Phase 8**, after hardware acceptance: touch `SENDDATA`,
  `RECVDATA_ONEBLOCK`, `PerformHandshake` and `SendCommandToMSXPi` to set/clear
  the flag, then ship ROM and driver together as one coordinated release.
- Until Phase 8 lands, **running the disk over MSXPi while INL is resident is
  unsupported** and must be called out in the installer and the docs.

---

## 3. Wire protocol

### 3.1 Two tiers

The existing block protocol (`READY`/`READY_ACK` handshake, 4-byte header,
checksum, status handshake) costs **13 overhead bytes per block**. That is fine
for a 1514-byte frame and absurd for a 1-byte "any frames?" poll that INL issues
60 times a second.

**Tier 1 — fast ops.** No handshake, no checksum. One command byte out, a fixed
short reply in. Used for `ETH_IN_STATUS` and all the trivial routines.

**Tier 2 — bulk ops.** Frame in/out. Uses the burst path (§3.3) with a checksum,
because a corrupted frame is worse than a slow one.

### 3.2 Fast-op envelope

```
MSX -> Pi : [OP:1] [ARG:1]
Pi  -> MSX: [RC:1] [B0:1] [B1:1] [B2:1] [B3:1]      ; fixed 5 bytes, always
```

Fixed-length replies mean no length negotiation and no framing ambiguity after
an aborted transfer. Opcodes live in a private range that cannot collide with
the existing ASCII command set (which is 9 printable bytes — see `CMDSIZE`), so
the server can dispatch on the first byte being non-printable.

`ETH_IN_STATUS` maps to exactly one fast op:

```
RC = 0 -> no frame            RC = 1 -> frame available
B0,B1  = frame length (LE)    B2,B3  = bytes 12-13 of the frame (ether-type)
```

which is precisely the register set Ethernet UNAPI's `ETH_IN_STATUS` must
return in `A`, `BC`, `HL`. One round trip, ~6 byte times.

### 3.3 Bulk-op envelope, and the RaSCSI trick

`ETH_GET_FRAME` returns the frame **prefixed by the status of the next one**:

```
MSX -> Pi : [OP_GET_FRAME] [MAXLEN_LO] [MAXLEN_HI]
Pi  -> MSX: [LEN_LO] [LEN_HI] [FLAGS] [ ...frame... ] [CHKSUM]
                                  ^ bit 0: another frame is already queued
```

This is lifted directly from PiSCSI's `SCSIDaynaPort::Read` (`[len:2][flags:4]`,
flag `0x10` = more data pending). It means INL's *next* `ETH_IN_STATUS` is
answerable from a value we already hold — no round trip at all. Given INL polls
every interrupt, this is the single highest-value optimisation in the design.

### 3.4 Burst mode — a Pi-side requirement

`WAIT_n` is gated on `SPI_RDY`, and `SPI_RDY` is the Pi's `RPI_READY` GPIO,
which `SPI_ByteTransfer()` currently raises **per byte** and drops again at the
end of each byte.

> During that inter-byte gap `SPI_RDY=0`, so an `INIR` read would **not** start
> a transfer, would **not** stall, and would silently return a stale byte.

Therefore: **the Pi must hold `RPI_READY` high for the duration of a burst.**
Phase 3 must add a burst-aware transfer function that raises RDY once, clocks N
bytes, then drops it. Without this, `INIR` cannot be used at all — this is a
hard dependency, not an optimisation.

---

## 4. Driver structure

### 4.1 RAM implementation, not ROM

`msxpibios.rom`'s page-1 half has ~1.1 KB free. The driver is ~2–3 KB. So it
ships as a **`.COM` installer** that allocates a mapper segment, copies the
driver in, hooks `EXTBIO`, and installs the RAM helper — the `unapi-ram.asm`
model from the UNAPI spec repo.

The mapper comes from the MegaFlashROM SCC+SD (512 KB) on real hardware and from
`Ram2Mb` in openMSX.

### 4.2 ISR-safe transport primitives (Phase 5a)

The driver must **not** call `CHKPIRDY`/`PIREADBYTE`/`PIWRITEBYTE`. Even after
the v1.6 tightening, `CHKPIRDY` still does `ld a,7 / out ($AA),a / in a,($A9)`
— it writes the **PPI keyboard row-select register** — and it is called twice
per byte. Doing that 60 times a second from inside the timer ISR corrupts the
BIOS keyboard scan, which is exactly what a telnet client depends on.

New primitives, private to the driver:

- **No keyboard access.** Ever.
- **Bounded.** A spin counter, not an infinite poll. On timeout: return
  "no frames"; never hang.
- **`DI`-guarded critical sections** around any multi-byte exchange.
- **Re-entrancy flag** so a client-initiated `ETH_SEND_FRAME` and the ISR's
  `ETH_IN_STATUS` cannot interleave.
- **Wait mode is set and cleared inside the critical section**, never left on
  across a return — so the foreground world always finds the device in legacy
  mode. (Also makes Option A in §2 cheaper.)

### 4.3 Buffers

Ethernet UNAPI forbids implementations from *requiring* page-1 (`$4000-$7FFF`)
buffers, and permits refusing them. Our driver lives in a mapper segment, so
this is satisfied naturally. `ETH_GET_FRAME` with `HL=0` must discard the frame
without copying — used by INL to drop frames it doesn't want.

---

## 5. Frame policy

**MTU clamp.** Set the Pi-side TAP interface MTU low (start at **576**) so TCP
negotiates a small MSS and typical frames stay short. Revisit once §6 is
measured. Ethernet UNAPI requires accepting sends of 16–1514 bytes; we honour
that, we just arrange for the network not to produce large ones.

**Filters.** `ETH_FILTERS` configured for **unicast + broadcast only**. No
promiscuous, no multicast. Broadcast noise is the main risk to a thin link;
PiSCSI's proxy-ARP / isolated-subnet modes (`os_integration/proxyarp`) are the
fallback if a busy LAN proves too chatty.

**Padding.** Pad short frames to **128 bytes**, not the spec's 64. PiSCSI found
several real drivers break below 128 (their issues #619, #1098) and accepted a
broken checksum to do it. We generate the CRC in software anyway (TAP hands up
frames without FCS — see `CTapDriver::Crc32`), so we can pad and checksum
correctly.

---

## 6. What must be measured before Phase 5

One number, from hardware, ~5 minutes:

```
MSXPI_PROFILE=1 python3 msxpi-server.py
```

then a transfer, and read the `[prof]` line: **µs/byte**, and the
`spinning on CS` share.

It decides:
- whether `/WAIT` stalls fit the ~20 µs SR-3 budget, or whether the Pi must get
  faster before burst mode is safe to enable;
- the MTU clamp value;
- whether a full frame fits inside one 60 Hz interrupt slot (~59,600 T-states).

Nothing in Phases 2–4 depends on it.

---

## 7. Decisions taken

| # | Decision |
|---|---|
| D1 | Ethernet UNAPI (12 routines) + InterNestor Lite, not a TCP/IP UNAPI offload |
| D2 | RAM implementation via `.COM` installer, not ROM-resident |
| D3 | Two-tier wire protocol: fixed-length fast ops, checksummed bulk ops |
| D4 | Next-frame status folded into the current frame read (PiSCSI pattern) |
| D5 | Driver gets private ISR-safe primitives; stock `CHKPIRDY` is off-limits |
| D6 | Wait mode enabled per-transaction, never left on |
| D7 | MTU clamped at 576 initially; unicast+broadcast filters only |

## 8. Open items

| # | Item | Owner |
|---|---|---|
| O1 | §2 shared-channel decision — RESOLVED: Option D now, Option A as Phase 8 | done |
| O2 | Profiler µs/byte measurement | you, 5 min |
| O3 | Canon V-25 cartridge-slot mapper routing check (V-8/V-9 only routed page 2) | you, 5 min |
| O4 | openMSX config with `MSXPi` **and** `MegaFlashROM_SCC+_SD` together | Phase 2 |
| O5 | Stale `$1E` comment in `MSXPi.vhd` | trivial |


---

## 9. Interrupts are disabled on return from every UNAPI call

Not a defect in this driver, in RAMHELPR, or in UNAPI - it is the MSX platform
contract, and it is worth writing down because it is invisible until it bites.

The RAM helper's inter-segment call reaches a segment-resident implementation
through the BIOS:

```
CALLRAM__1:
        call    GET_P1__1
        ld      a,iyl
        call    PUT_P1__1
        call    CALSLT          ; <-- BIOS $001C
        pop     af
        call    PUT_P1__1
        ret
```

`CALSLT` (like `RDSLT` and `WRSLT`) disables interrupts and does not re-enable
them. So **every call into a RAM-segment UNAPI implementation returns with
interrupts disabled**, on every MSX, for every implementation - Konamiman's
examples included. Re-enabling is the caller's job.

Observed as: ETHBENCH reported zero elapsed jiffies for thousands of
transactions that were demonstrably working, because JIFFY had stopped being
updated. A control delay loop in the same program, run moments earlier, read
~37 jiffies. Adding an `ei` after each call made the timings appear.

### Why it matters for InterNestor Lite

INL runs from the timer interrupt. A foreground client that leaves interrupts
off between UNAPI calls stops that interrupt firing, so:

1. INL never processes incoming frames,
2. so `TCP_RCV` never returns data,
3. so the client keeps polling,
4. so interrupts stay off.

A deadlock, presenting as "the network hangs", with neither component looking
broken. Stock clients avoid it by re-enabling interrupts, which is why they work
in the field - but it must be verified rather than assumed, with a real client,
early in Phase 6.

### What this driver does about it

Nothing, deliberately. It has no interrupt dependence: every spin is bounded,
there are no timers, and `ETH_LOCK` no longer uses `di` (see the note there for
why the obvious `ld a,i` idiom is worse than useless). It behaves identically
whether interrupts are on or off, so the only correct place to fix this is the
caller.

Our own test programs do re-enable interrupts around their loops - see
ETHBENCH's `RUN_PASS` - which is what a well-behaved foreground client has to
do anyway.

---

# The driver moves into the ROM (2026-08-31)

## Why

InterNestor Lite's RAM-segment path is a dead end. Four defects turned up on
real hardware in code no field implementation exercises: `_UN_RAMCALL` fetched
only when the segment IS `$FF`, the implementation name read through `CALL_MAP`
instead of `RD_MAP`, `INL S` reporting "not installed" while `UCOUNT` proves
TCP/IP registers, and `INL I` hanging outright. Two are patched in `inl/`; the
other two are not understood. Forcing our transport to the bounded polled path
with `ETHUNAPI P` changed nothing, so the transport was exonerated and the
fault is entirely in INL.

A ROM implementation reports **segment `$FF`**, which puts every stock client -
InterNestor Lite included - on the `CALSLT` path that ObsoNET and every other
field implementation use. No INL patches, no RAM helper dependency, and no
installer to run.

The `.COM` installer stays as the option for people who cannot reflash.

## Where it lives

`target/msxpibios.rom` is built from `ROM/src/MSX-DOS/msxpi-driver.mac`, **not**
from `ROM/src/BIOS/msxpibios.asm` - that trap has cost time before. The driver
is assembled separately by sjasm and `INCBIN`'d into the free tail at a fixed
`UNAPI_ORG`, with `ASSERT`s on both sides: MSXPi code must not reach
`UNAPI_ORG`, and the image must end below `8000H`. Growth in either direction
is a build error rather than a corrupt ROM.

Two assemblers, because neither can do the whole job: zmac builds the ROM, and
sjasm builds the driver - the same sources also produce the RAM variant, and
they are sjasm syntax throughout. The driver calls the kernel's `GETSLT` and
`GETWRK` by hardcoded address (the two assemblers cannot share a symbol table);
`msxpi-driver.mac` `ASSERT`s both against the real labels.

## Fitting it

The free tail was 1,100 bytes and the driver was 1,240. What closed the gap:

| | bytes |
|---|---|
| a dead `DS 128` in `msxpi_bios.asm` (`heap_top`, never referenced) | 128 |
| `ChoiceStr` - "1 - Choice A" etc., and `CHOICE` returns HL=0 | 47 |
| `DSKIORDMSG` - "DSKIO READ ERROR", never printed | 19 |
| `DOS_INI`/`DOS_DRV`/`DOS_FMT` - protocol strings never sent | 36 |
| `ETH_TX_BLOCK` - dead: every send goes through `ETH_TX_SUM` | 58 |
| `ETH_TX`'s mode branch - both arms were literally identical | 17 |
| `ETH_RX`'s two arms merged; they differ only in the middle step | 13 |
| `ETH_WAIT_DATA`'s two polled loops merged into one | 23 |

That is 341 bytes against a 158-byte shortfall, and the diagnostic routine 128
survived. 38 bytes are still free below `8000H`.

## State

The ROM cannot write to itself, so every mutable byte moved into the disk
driver work area - `MYSIZE` grew from 9 to 45 and `GETWRK` hands out the
pointer. Offsets 0..7 stay with the disk driver (`DSKIO_SECTINFO` 0..4,
`MSXPI_GETSTASH` 5..7); ours start at 8. `asm-common/include/unapi_wrk.inc`
holds the layout and is included by **both** assemblers.

**Both builds use it**, reached through `IX`. The RAM build could have kept
absolute addresses, but then `ethtrans.asm` and `ethops.asm` would have needed
two versions of every state access, and they would have drifted. MSX-UNAPI 2.3
makes this legal: `IX`/`IY` "must not be used for input parameters" and are
corrupted on return, precisely so inter-slot and inter-segment calls can use
them. `UNAPI_ENTRY` sets `IX` once and every routine reads through it.

## Initialisation

From `INIENV`, not `INIHRD`. By the time the kernel calls `INIENV` it has
allocated the `MYSIZE` work area and stored it in `SLTWRK` (so `GETWRK` works)
and initialised the EXTBIO hook - either in this diskrom or in whichever one
started the disk system first, so `HOKVLD` needs no checking. The hook becomes
`RST 30h` + slot + address + `RET`, exactly five bytes, and the hook it
displaces is kept in the work area. Installing twice would chain the hook to
itself, so `INIENV` recognises its own handler and returns.

## The transport is probed lazily, and that matters

The `.COM` installer probes at install time. The ROM **cannot**: `INIENV` runs
during disk-system initialisation, when on real hardware the Pi is usually
still booting. A probe there would fail and pin the driver to the slow polled
backend for the rest of the session. So `INIENV` writes `MODE_UNKNOWN` and the
first UNAPI call runs `ETH_DETECT` - by which time the machine has booted off
the Pi and the link is known good.

That first transaction is still slower than every later one, because the other
end builds its Ethernet shuttle lazily when the first opcode arrives. With the
fixed 17 ms per-byte budget it **timed out**, and then the reply landed in a
queue nobody was reading: every later transaction read the previous one's
answer. Not a lost call - permanent desync. It showed up as ETHTEST printing
the probe's own `ETH` signature as the MAC address:

```
MAC:   455448010002      <- 'E' 'T' 'H' 01, then the real reply starting
Net:   00
```

Caught in emulation only because a cold `__pycache__` made the server's first
`import msxpi_eth` slow enough; with the bytecode cached it passed. The fix is
`(ix+o_ETH_TMO)`, the per-byte budget in units of 256 iterations: the work area
starts zeroed, which the wait loops read as the **longest** budget (~0.5 s), and
`ETH_DETECT` drops it to the normal value once the link has answered once.

The underlying hazard is older and still there: a reply that arrives after we
have given up on it poisons the next transaction, and `ETH_RESYNC` cannot
retrieve bytes already buffered on the other side. `ETH_MAXFAIL` limits the
damage; a bounded drain in `ETH_RESYNC` would be the real fix if this recurs.

## What the tests now prove

`unapi_discovery` runs `ETHTEST` from a **cold boot with nothing installed** -
no `RAMHELPR`, no `ETHUNAPI` - and gets `Found: 01`, `Seg: FF`, the real MAC
over the wire and `Net: 01`. `ETHTEST` and `ETHBENCH` both learned the `CALSLT`
path and now treat the RAM helper as optional, needed only for a mapped
segment.

`unapi_install` pins the opposite: with the ROM driver present, `ETHUNAPI.COM`
must refuse, because installing anyway would register a second implementation
of the same API.

## What INL does now

`INL I` **completes** on the ROM path:

```
Searching Ethernet UNAPI implementation... OK
Found MSXPi Ethernet UNAPI v0.1 at slot 1
InterNestor Lite has been installed. Have fun! (^^)/
```

Against the RAM implementation it hung right after the "Found" line. That was
defect (4), and going ROM fixed it - which is the whole justification for this
change. `wsl_inl` now asserts it rather than merely running it.

Defect (3) survives, and is now more interesting than it was. `INL S` still
reports "InterNestor Lite is not installed" immediately after a successful
`INL I`. Two explanations are ruled out:

* **Not the RAM-segment path.** It behaves identically with the driver in ROM.
* **Not the separate mapper card.** The standing theory was that INL's
  residency check compares against `RAMAD1`, and the harness adds `ram2mb` to a
  Canon V-25, putting the mapper in a different slot from page-1 RAM. Tested
  with `MACHINE=Philips_NMS_8245 HW=msxpi128` - 128K in the main slot, no
  `ram2mb`, mapper and page-1 RAM in the same slot - and `INL S` still says not
  installed. The theory is dead; do not spend time on it again.

`UCOUNT` proves the TCP/IP UNAPI does register, so INL itself is working and it
is specifically INL's own status command that is confused. Whatever marker
`INL S` looks for is not being left by `INL I` in this environment. It is not
blocking: nothing depends on `INL S` except a human wanting reassurance.

Still unproven: everything on real hardware, and anything that carries a real
frame. Nothing network-facing has yet moved a single one - TapLink's reader
thread, the CRC generation, frame padding and the queue policy are all still
unexecuted.

---

# Validated on real hardware (2026-09-04)

Canon V-25, MegaFlashROM SCC+SD in slot 1 running Nextor, MSXPi in slot 2,
`msxpibios.rom` sha1 `3616e00a`.

| test | result |
|---|---|
| `ETHTEST` from a cold boot, nothing installed | `Found: 01`, `Seg: FF`, `Rst: ok`, `Mode: 01`, real MAC, `Net: 01`, `P57: 0E` |
| `INL I` | installs; `UCOUNT` reports ETHERNET `01` and TCP/IP `01` |
| `ETHBENCH` | `ok=0800` on **every** line, `W-3by` included |
| `ETHTEST` again, with INL resident | correct MAC and `Net: 01` |
| `TESTRAM` | 512KB mapper passes |

Three of those are firsts.

**`W-3by` is no longer intermittent.** That 3-byte `/WAIT` transaction used to
return `0800` in one run out of three, and it is the shape of `ETH_IN_STATUS`,
which InterNestor Lite calls sixty times a second - the most exposed case in
the whole design. It is now clean. The likely reasons are that detection proves
`/WAIT` with a real probe transaction before selecting it, and that the Pi
holds `RPI_READY` across the inter-byte gap.

**Re-entrancy holds against a real interrupt-driven client.** `ETHTEST` run
while INL is resident still gets correct answers, so foreground UNAPI calls and
INL's timer-ISR polling of `ETH_IN_STATUS` coexist. That is what `ETH_LOCK` and
the ISR-safe transport core were written for, and until now it had never been
exercised by an actual ISR consumer - not on hardware, not in emulation.

## What the `INL I` hang actually was

`INL.CFG` line endings. LF only, where MSX text files need CRLF.

Not the driver, not the transport, and not the RAM-vs-ROM segment path - all
three had been suspected and all three were wrong. After installing, INL feeds
`INL.CFG` back through its own command parser one line at a time; with no CR it
never finds a line boundary, reports *"Cannot execute this command from a
configuration file"*, and then loops printing its banner. On DOS 1 that shows
as a visible loop; on Nextor it presents as a hang.

Three-way A/B in emulation settles it: LF-only stops at "Found ... at slot N";
no file at all installs cleanly; CRLF installs **and applies the static IP**.

`UNAPI/build.sh` now converts the file at copy time rather than trusting the
copy in the repo, because git's line-ending handling can rewrite it on
checkout. `wsl_inl` asserts both that the install completed and that every
config line was accepted - "has been installed" alone would not catch a config
file that was silently skipped.

## Still unproven

Anything that carries a real frame. The MAC coming back as `024D53585069` is
`msxpi_eth`'s built-in default, which means the Pi is running `MockLink`: it
answers every opcode perfectly and moves no traffic, so the whole suite passes
while nothing is connected. `TapLink`'s reader thread, the CRC generation,
frame padding and the queue policy remain unexecuted.

---

# It works (2026-09-05)

```
64 bytes from 192.168.99.2: icmp_seq=1 ttl=64 time=59.6 ms
64 bytes from 192.168.99.2: icmp_seq=2 ttl=64 time=40.2 ms
```

Canon V-25, MegaFlashROM SCC+SD in slot 1 running Nextor, MSXPi in slot 2,
`msxpibios.rom` sha1 `cba6355e`, **stock** InterNestor Lite. ARP resolved by
INL itself, ICMP echo answered.

## The last bug was ours, and it was one instruction

Both of InterNestor Lite's send sites do this:

```asm
	ld	d,1
	ethnet	ETH_SEND_FRAME
```

`D=1` is asynchronous mode. `FN_SEND_FRAME` opened by rejecting it:

```asm
            ld      a,d
            or      a
            jr      z,.sync
            ld      a,5                     ; async not supported
            ret
```

So every reply INL ever composed was refused at the final instruction. It
received frames correctly, parsed them correctly, decided to reply, and we said
no — which is exactly why every layer underneath looked perfect while nothing
came back.

The fix sends synchronously whatever `D` says and returns 0. That is safe
rather than a fudge: asynchronous mode only guarantees that transmission has
*started*, so completing it first is a stronger guarantee than the caller asked
for, and a caller polling `ETH_OUT_STATUS` gets `2`, "finished successfully".

## Two things hid it, both self-inflicted

**`ETH_OUT_STATUS` was lying by omission.** The async and bad-length paths
return early without recording anything in `o_ETH_LASTSEND`, so routine 10
reported `0` — "nothing sent since reset" — when the truth was "an attempt was
refused and not recorded". That reading sent the investigation into INL's
source for several cycles. A diagnostic that cannot distinguish "never called"
from "called and rejected" is worse than no diagnostic.

**`software/build` had `buildBIOS="no"`**, so the entire ROM block was skipped
and `ROM/src/MSX-DOS/ethrom.bin` sat at a four-day-old build while driver
changes appeared to be deployed. Any driver fix has to reach the ROM, and with
that flag off it silently never does.

## And one long-standing mystery closed

`INL S` reporting "not installed" was **caused by the RAM-implementation
patch**, not by this driver or the machine. Stock INL - built by reversing
`inl/inl-2.3-ram-implementation.patch`, vendored as `bin/INLSTOCK.COM` -
reports "installed and ACTIVE". Two explanations had already been ruled out for
that defect; the real one was self-inflicted, which is the point of running
stock software when the whole design goal was that stock software should work.

## What is still unproven

DNS, TCP and telnet. And NAT: the uplink-detection fix is in the repo but not
deployed to the Pi, so nothing routes off-subnet yet. On-link traffic works.
