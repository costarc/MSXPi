# MSXPi CPLD — Hardware Flow Control via /WAIT

**Specification for a separate work stream.**
Target firmware: MSXPi CPLD v1.6 (`MSXPIVer = "1110"`)
Baseline: v1.3 (`MSXPIVer = "1101"`), `hardware/CPLD_Project/MSXPi.vhd`
Date: 2026-08-30

---

## 1. Purpose

Today every byte moved between the MSX and the Raspberry Pi costs the Z80 a
**software** handshake: `CHKPIRDY` polls `CONTROL_PORT1` bit 0 in a loop before
each byte. Measured from the source, that is **~330 T-states (~92 µs at
3.58 MHz) per byte**, on top of whatever the Pi itself takes.

This change makes the CPLD assert the MSX bus `/WAIT` signal so the **hardware**
performs the handshake. The Z80 then transfers bytes with block I/O
(`inir` / `otir`, 21 T-states/byte) and the CPU is stalled by hardware exactly
as long as the Pi needs, with no polling instructions at all.

### Why this is needed

The consumer is a new UNAPI networking driver (Ethernet UNAPI + InterNestor
Lite). InterNestor Lite runs **from the 50/60 Hz timer interrupt hook** and
calls the Ethernet driver on every interrupt. Two hard consequences:

1. The transfer loop must be short and bounded — there is ~59,600 T-states per
   interrupt slot, shared with the BIOS ISR.
2. `CHKPIRDY` currently scans the **ESC key on every byte** (`out ($AA),a` /
   `in a,($A9)` — the PPI keyboard row-select register). Doing that 60×/second
   from inside an ISR corrupts the BIOS keyboard scan. The new driver cannot
   use the existing primitives, and hardware /WAIT is what lets it stop needing
   them.

### What this change does NOT fix — read before starting

The Z80's 92 µs/byte is **not currently the dominant cost**. The Pi-side
bit-banged SPI in `msxpi-server.py` (`SPI_ByteTransfer`) is a Python loop with a
`time.sleep(0.00001)` per clock tick and a `while GPIO.input(SPI_CS): pass`
spin — realistically **200–600 µs per byte**.

So /WAIT alone yields perhaps **10–30 %**. Its full value is only realised once
the Pi-side SPI is rewritten in C or moved to the hardware SPI peripheral. The
two changes are complementary and the Pi-side one should be scheduled first or
in parallel. **Do not benchmark this change against the current Python
server and conclude it failed.**

---

## 2. Current design (baseline v1.3)

| Item | Value |
|---|---|
| Device | `EPM3064ALC44-10` (MAX3000A, **64 macrocells**, PLCC44) |
| I/O ports | `CTRLPORT1` = `$56`, `CTRLPORT2` = `$57`, `DATAPORT1` = `$5A` |
| `WAIT_n` | **PIN_37, routed, currently `'Z'` (never driven)** |
| Clocking | FSM clocked on `rising_edge(SPI_SCLK)` — SCLK is an **input from the Pi** |

Behaviour:
- Read `$56` → `"0000000" & SPI_RDY_s` (bit 0 = busy/ready)
- Read `$57` → `"0000" & MSXPIVer` (`$0D` today). Write to `$57` is **ignored**
- Read/write `$5A` → data byte; a write to `$56` or `$5A` starts an SPI transfer
- Write `$FF` to `$56` → asynchronous `RESET`
- `BUSDIR_n` asserted only for reads of `$56`/`$5A`

---

## 3. Functional requirements

**FR-1 — /WAIT assertion.** When the MSX performs an I/O read of `$5A` (or a
write to `$5A`/`$56` that starts a transfer) while the interface is not ready to
complete it, the CPLD shall drive `WAIT_n` low, and release it (return to `'Z'`)
as soon as the data is available / the transfer has been accepted.

**FR-2 — Tri-state when inactive.** `WAIT_n` shall be driven low only while
actively stalling, and be high-impedance at all other times. It must never be
driven high — `/WAIT` is an open-collector-style shared bus signal.

**FR-3 — Mode bit, default OFF.** /WAIT assertion shall be **disabled at
power-up** and enabled only by an explicit host action (see FR-4). In the
disabled state the device shall be **bit-for-bit behaviourally identical to
v1.3**.

**FR-4 — Enable/disable interface.** A write to `CTRLPORT2` (`$57`) shall set
the mode register:
- `D = $01` → /WAIT mode ON
- `D = $00` → /WAIT mode OFF
- other values → reserved, treat as no-op

Port `$57` is currently write-ignored by the CPLD and **no existing software
writes to it** (verified across the whole `software/` tree — every reference is
an `IN`/read for version detection). This makes it the safe choice.

**FR-5 — Reset clears the mode.** The existing `RESET` condition (write `$FF` to
`$56`) shall clear the mode register to OFF. This is deliberate: it gives any
legacy program a way to restore known-good behaviour, and gives the new driver a
fail-safe. The driver is expected to re-enable after each reset.

**FR-6 — Version bump.** `MSXPIVer` shall change from `"1101"` to `"1110"`, so
software can feature-detect /WAIT support by reading `$57`.

---

## 4. Backward-compatibility requirements — MANDATORY

Existing binaries in the field must keep working with no recompilation:
the ROM BIOS (`msxpibios.rom`), the MSX-DOS driver (`msxpidos.rom`), the Nextor
driver, and all `.COM` tools.

**BC-1 — Default-off is absolute.** With the mode register OFF the device must
behave exactly as v1.3: same port decode, same `SPI_RDY_s` semantics, same
reset, same `BUSDIR_n`, `WAIT_n` never driven.

**BC-2 — `$57` must stay readable and below `$FE`.** `msxpi_bios.asm:97` reads
`$57` and compares against `$FE` to distinguish real hardware from openMSX
(which returns `$FE`). The new value `"1110"` reads as `$0E` — compliant. Never
let `$57` return `$FE` or `$FF`.

**BC-3 — `CTRLPORT1` bit 0 semantics unchanged.** Legacy software polls it. It
must keep meaning the same thing in both modes, so a program that polls *and*
has /WAIT enabled simply finds the flag already settled.

**BC-4 — Reset behaviour unchanged.** Write `$FF` to `$56` must continue to
reset the SPI FSM and clear the data buffer, in both modes.

**BC-5 — No new pins, no PCB change.** `WAIT_n` is already on PIN_37 and routed.
The change must fit the existing PCB v1.1/v1.2 hardware.

---

## 5. Safety requirements — the critical risk

**There is no free-running clock on this CPLD.** The only clock is `SPI_SCLK`,
an input driven by the Pi. If the CPLD asserts `WAIT_n` and the Pi then stops
clocking — crash, process kill, SD-card stall, `Ctrl-C` on the server — there is
**no clock edge left to time out on, and the MSX hangs permanently** with no
recovery short of a power cycle.

This is the single most important thing to get right.

**SR-1 — Bounded assertion.** `WAIT_n` shall be released after a bounded number
of `SPI_SCLK` edges (suggest 8–16, i.e. one byte period) regardless of Pi state.
On timeout, release `/WAIT` and let the read return whatever is in the buffer;
the software layer's existing checksum/retry logic will catch the bad byte.

**SR-2 — Assert only during a Pi-active window.** Only assert `/WAIT` when a
transfer has actually been started and `SPI_CS` is active, i.e. when the Pi is
committed to clocking. Never assert while merely idle-waiting for the Pi to
become ready — that is the unbounded case.

**SR-3 — Maximum stall duration.** Total `/WAIT` assertion for any single I/O
cycle must stay under **~20 µs**. Longer stalls disturb VDP access timing and
interrupt latency. Note this interacts with §1: if the Pi needs 200–600 µs per
byte, /WAIT **cannot** cover the whole wait, which is another reason the
Pi-side SPI speed-up is a prerequisite for the full benefit.

**SR-4 — Independent escape hatch.** Provide at least one recovery path that
does not depend on the Pi: the FR-5 reset, and ideally a hardware option
(depopulated resistor or jumper on the PIN_37 net) so a bricked bus can be
recovered on the bench.

**SR-5 — Z80 /WAIT timing.** `WAIT_n` must be valid before the falling edge of
T2 of the I/O machine cycle to be sampled. Note the Z80 already inserts one
automatic wait state in I/O cycles. Verify against the MSX bus timing spec, not
just simulation.

---

## 6. Resource constraints

**RC-1 — Must fit `EPM3064ALC44-10`: 64 macrocells.** This is the binding
constraint and the main reason this is a separate work stream. The v1.3 design
already uses a meaningful share. Adding an FSM, a mode register, and a timeout
counter may not fit. **Report actual pre- and post-change macrocell utilisation
from the Quartus fitter as part of the deliverable.**

**RC-2 — If it does not fit**, options in order of preference:
1. Shrink the timeout counter (3 bits is enough for an 8-edge timeout)
2. Share/reuse the existing `bitcount` counter for timeout duty
3. Migrate to `EPM7128` (used in earlier revisions per the project history) —
   but this is a PCB/BOM change and needs your approval first

**RC-3 — Toolchain.** Quartus II (same version used for v1.3). Existing files:
`MSXPi.qpf`, `MSXPi.qsf`, `MSXPi.vhd`, `MSXPi_package.vhd`, plus the testbench
`tb_MSXPi.vhd` and `sim.sh` (GHDL).

---

## 7. Acceptance criteria

1. **Fitter**: compiles clean for `EPM3064ALC44-10`, 0 errors; macrocell usage
   reported.
2. **Simulation**: `tb_MSXPi.vhd` extended to cover — legacy mode is
   cycle-identical to v1.3; /WAIT asserts and releases correctly in WAIT mode;
   the SR-1 timeout fires when `SPI_SCLK` stops; reset clears the mode.
3. **Regression on real hardware**: with the mode register never written (i.e.
   every existing binary), the MSX boots and all current MSXPi software works
   unchanged — `pdir`, `ploadr`, MSX-DOS boot, Nextor driver.
4. **New path on real hardware**: a small test program enables WAIT mode, runs
   an `inir` burst read, and gets correct data; timing measured against the
   legacy polled loop.
5. **Recovery verified**: kill `msxpi-server.py` mid-transfer with WAIT mode
   enabled — the MSX must not hang.

---

## 8. Deliverables

- Updated `MSXPi.vhd` / `MSXPi_package.vhd`
- Updated `tb_MSXPi.vhd` with the new cases
- New `.pof`
- Fitter resource report (before/after)
- Short note documenting the `$57` mode register for the software side

---

## 9. Open questions for the implementer

1. Is 8 `SPI_SCLK` edges the right timeout, or should it be tied to the FSM
   state instead of an edge count?
2. `BUSDIR_n` is currently **not** asserted for reads of `$57`
   (`is_ctrl_or_data` excludes `CTRLPORT2`) — a latent bug on expanded slots.
   Worth fixing in the same pass?
3. `D_buff_msx <= D when (...)` infers a latch. Intentional, or should it become
   a proper registered capture while the design is being touched?

---

## 10. Context

Consumer of this change: MSXPi UNAPI networking (Ethernet UNAPI + InterNestor
Lite). Test machine: **Canon V-25 (MSX2)** with MegaFlashROM SCC+SD 512 KB
mapper. This CPLD work is a **prerequisite for good performance but not for
first function** — the UNAPI work proceeds in parallel against the legacy
polled transport.
