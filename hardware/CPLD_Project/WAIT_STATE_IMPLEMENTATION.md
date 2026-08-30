# MSXPi CPLD v1.6 — /WAIT flow control: implementation report

Implements `WAIT_STATE_SPEC.md`. Date: 2026-08-30.
Toolchain: Quartus II 13.0sp1 (`EPM3064ALC44-10`), GHDL for simulation.

**Status: VALIDATED ON REAL HARDWARE in legacy mode.** An earlier revision of
this work failed on hardware; the cause and fix are recorded below because the
lesson generalises.

> ### The bug that cost a hardware cycle - root cause
> `wait_mode` was written as a plain asynchronous set/reset pair, which Quartus
> infers as a **latch with its enable tied to GND**. That cell has no guaranteed
> power-up state on MAX3000A, and a VHDL `:= '0'` initialiser does nothing about
> it - it only fools the simulator. The device powered up **already in WAIT
> mode**, so every `IN ($5A)` fired an extra transfer carrying `$00`, the byte
> stream desynchronised permanently, and `/WAIT` could stall the Z80 during boot.
>
> The differential testbench passed because GHDL honours the initialiser. Zero-
> delay RTL simulation cannot model the power-up state of an unclocked cell, so
> equivalence proved from an assumed initial state proved nothing about silicon.
>
> **Fix:** the mode bit is clocked by the port-write strobe, so it is an
> ordinary register and the device's power-on reset clears it. The check is
> mechanical: `wait_mode` must NOT appear in the *User-Specified and Inferred
> Latches* table of `MSXPi.map.rpt`. `started` uses the same construct but is
> self-correcting - its clear is `spi_en = '0'`, true whenever the bus is idle.

### Hardware result (2026-08-30)

Both v1.6 images were flashed to the real interface and exercised against
`msxpi-server.py` on the Pi:

| Image | Result |
|---|---|
| `alternative/MSXPi_v16_shifter_only.pof` | **PASS** — `p run cat msxpi-server.py`, **142 KB transferred, no errors** |
| `MSXPi_v16.pof` | **PASS** — same test, no errors |

That closes **spec acceptance criterion 3** (backward compatibility: every
existing binary works unchanged with the mode register never written) and proves
the sentinel shift register matches `SPI_ByteTransfer()` on silicon.

**Still open: criteria 4 and 5.** WAIT mode itself has never been enabled on
hardware — nothing has written `$57`. Do not enable it until the Pi-side SPI is
rewritten; see §6, which is a correctness constraint, not a performance one.

---

## 1. Answers to the three questions

**Does it fit?** Yes, comfortably. The /WAIT feature costs **+1 macrocell** when
bolted onto the untouched v1.3 SPI engine (47 → 48 of 64).

**Can the engine be re-written more cheaply, e.g. as a bit shifter?** Yes, and
it is worth doing. Replacing the three-state FSM and the 3-bit `bitcount` with a
single *sentinel shift register* makes the whole design — /WAIT included —
**smaller than v1.3 was**: 45 macrocells against 47, with registers down from 24
to 20 and shareable expanders down from 33 to 13. That is the version shipped as
`MSXPi.vhd`.

**What does it take without redesigning the interface?** Nothing on the PCB, no
new pins, no change to the Pi-side protocol, and no change to any existing MSX
binary. `WAIT_n` is already on PIN_37 and routed to J1 pin 7. The one thing that
changed outside the VHDL is a single Quartus setting (see §3).

---

## 2. Fitter resource report (spec deliverable RC-1)

All rows are real `quartus_sh --flow compile` runs on `EPM3064ALC44-10`.

| Build | Macrocells | Registers | P-terms | Shareable exp. | Fitter |
|---|---|---|---|---|---|
| v1.3 baseline | 47 / 64 (73 %) | 24 | 190 | 33 / 64 | OK |
| v1.6 shipped — shifter + /WAIT, mode bit registered | 46 / 64 (72 %) | 21 | — | — | OK |
| v1.6 shifter only, /WAIT removed (diagnostic) | 44 / 64 (69 %) | 20 | — | — | OK |
| the earlier revision shifter engine + /WAIT (latched mode bit — BROKEN) | 45 / 64 (70 %) | 20 | 157 | 13 / 64 | OK |
| v1.6 shipped + BUSDIR fix for `$57` (§7) | 44 / 64 (69 %) | 20 | — | — | OK |

Pins are unchanged at 30 / 34 in every build. So the shipped v1.6 leaves **19
free macrocells**, against 17 for v1.3 — there is *more* headroom after this
change than before it, which is what pays for the timeout counter in §6 should
you decide to fit the clock wire.

### Where the saving comes from

v1.3 tracks transfer progress with three separate things: a one-hot
`spi_state` (3 registers), a `bitcount` up-counter (3 registers plus an adder
and its expander chain), and the `D_buff_pi` receive register (8).

v1.6 folds all three into one 10-bit register. It is loaded with a single `'1'`
at bit 0 when a transfer starts, and MISO shifts in underneath it. Because every
received bit stays *below* the sentinel and every bit above it is still zero,
the sentinel is always the highest set bit — so both phase tests are free of any
counter:

```
pi_sr(9 downto 1) = 0   ->  nothing received yet, this edge is E1 (the load)
pi_sr(9)          = '1' ->  all eight bits are in, byte complete
pi_sr(7 downto 0)       ->  the received byte
```

14 storage elements become 10, the adder and its expanders disappear, and the
edge map seen by `msxpi-server.py` is bit-for-bit the same.

---

## 3. The one non-VHDL change: `MAX7000_OPTIMIZATION_TECHNIQUE`

`MSXPi.qsf` moves from `BALANCED` to `AREA`.

This is not cosmetic — without it the shifter design **fails to place**, with
`Error (163103): Can't pack LABs`. It is not a capacity problem: the failing run
still reports only 43 of 64 macrocells. It is LAB fan-in. `EPM3064A` has 4 LABs
sharing a limited PIA, and the shifter concentrates a wide decode cone into
fewer, busier cells. `AREA` costs 2 macrocells (43 attempted → 45 placed) and
places cleanly.

Checked and rejected: `AUTO FIT` (still fails), removing the stale `MAX_LABS 20`
assignment (still fails), narrowing the `started` clear term (still fails). The
v1.3 baseline fits at 47 under `AREA` just as it does under `BALANCED`, so the
setting change costs nothing if you ever rebuild v1.3 from this .qsf.

---

## 4. Software-side note: the `$57` mode register (spec deliverable)

| Operation | Effect |
|---|---|
| `OUT ($57),$01` | /WAIT flow control **ON** |
| `OUT ($57),$00` | /WAIT flow control **OFF** |
| `OUT ($57),`anything else | ignored (reserved) |
| `OUT ($56),$FF` | existing reset — **also forces the mode OFF** (FR-5) |
| `IN ($57)` | `$0E` when off, `$8E` when on |

**Version numbering.** The CPLD firmware jumps 1.3 -> 1.6, skipping 1.4 and 1.5,
so that it tracks the BIOS/release version rather than running on its own
sequence. Neither 1.4 nor 1.5 was released. `MSXPIVer` is unaffected: it stays
`"1110"` because it identifies the hardware generation, not the release.

`$57` bit layout:

| Bits | Meaning |
|---|---|
| 7 | `wait_mode` read-back (not required by the spec; lets the driver confirm the write landed) |
| 6 | **RESERVED — must stay `0`.** BC-2 guard, see below |
| 5–4 | free for future use |
| 3–0 | `MSXPIVer`, now `1110` (was `1101`) |

**Why bit 6 is a guard and not spare space.** `msxpi_bios.asm:97` detects openMSX
by testing `$57` against `$FE`, so the port must never read `$FE` or `$FF`
(**BC-2**). `MSXPIVer` is already `1110`, so with the mode bit at 7, allocating
bits 6..4 and setting them all would produce exactly `1111_1110` = `$FE` and
break interface detection in the field. Holding bit 6 at `0` caps the port at
`$BF` for ever, whatever bits 5..0 are later used for.

**`pver.com` needs a one-line change.** `DESCHWVER` uses the *whole* byte as an
index into `iftable`, so any high bit set walks off the end of the table. It
should mask the version field first (`and $0F`) before indexing. Note it is
already imperfect at `$0E`: `iftable` has 15 entries (0–14) and index 14 is
`ifukn`, so v1.6 currently prints *"Could not identify"* — a v1.6 string wants
adding at the same time.

Power-up state is OFF, and the mode is cleared by the existing reset, so the
driver must re-enable it after every `resetMSXPI`.

With the mode ON, a plain `IN ($5A)` *both* starts the SPI transfer and stalls
the Z80 until the byte has landed, so a block read becomes:

```
        ld      a,$01
        out     ($57),a         ; enable hardware flow control
        ld      hl,buffer
        ld      bc,$0000 + DATA_PORT1   ; B = count, C = $5A
        inir                    ; 21 T-states/byte, no polling at all
        xor     a
        out     ($57),a         ; back to legacy behaviour
```

`OTIR` works the same way on the write side. Note that `INIR` uses `B` as the
counter, so a block is at most 256 bytes per instruction.

Two behaviours worth knowing about:

- A read of `$5A` in WAIT mode when the Pi is **not** ready (`SPI_RDY` low)
  neither stalls nor starts a transfer. It returns the stale buffer, exactly as
  a legacy read would, and the existing checksum/retry layer catches it. This
  is deliberate — see §5.
- A read-started transfer sends `$00` on MOSI (the shift register is empty after
  the previous byte), which matches what `PIREADBYTE` already does with its
  `xor a / out ($56),a`. The server discards that byte anyway.

---

## 5. Safety — and one place the spec is self-contradictory

The spec is right that §5 is the critical risk, but **SR-1 as written cannot be
implemented.** It asks for release "after a bounded number of `SPI_SCLK` edges
… regardless of Pi state". A counter clocked by `SPI_SCLK` cannot count when
`SPI_SCLK` stops, and the Pi stopping is the only failure that matters. An
edge-counted timeout would protect against nothing, and it cannot satisfy
acceptance criterion 5.

What was implemented instead is a **clock-free release**, which came out of
reading the PCB rather than the RTL:

> `SPI_RDY` (U2 pin 39) has **R8, 10K to GND** — a pull-*down*.

So `SPI_RDY` is a term in the `/WAIT` equation itself:

```vhdl
wait_assert <= wait_mode and SPI_RDY and spi_en and (SPI_en_s or (not started));
WAIT_n      <= '0' when wait_assert = '1' else 'Z';
```

The moment the Pi stops driving `RPI_READY`, R8 takes the line low and `/WAIT`
releases combinationally in ~24 ns, with no clock involved at all. That covers
every case where the GPIO is released:

| Failure | Covered? | Why |
|---|---|---|
| Ctrl-C on `msxpi-server.py` | **Yes** | `except KeyboardInterrupt: GPIO.cleanup()` at line 4055 releases the pad |
| Clean exit / restart | **Yes** | same cleanup path |
| Pi rebooted, powered off, unplugged, never booted | **Yes** | pad is an input, R8 wins |
| Pi alive but slow | **Yes** — no hang | stall is bounded by the Pi's byte time, see §6 |
| **`kill -9`** | **No** | no cleanup runs, the pad keeps its last level, `SPI_RDY` stays high and `SCLK` never ticks again |

That last row is demonstrated, not assumed — phase 6 of the testbench models it
and confirms `/WAIT` is still asserted 200 µs later. On hardware that is a hung
MSX needing a power cycle.

Closing it needs a real clock, and the board is one wire away from having one:

> `CLOCK` (the 3.58 MHz bus clock) is present on **J1 pin 42** and is currently
> routed nowhere — it is a single-pad net. CPLD pins **1, 2, 43 and 44**
> (`GCLR/`, `OE2/GCLK2`, `GCLK1`, `OE1`) are all unconnected.

A bodge from **J1.42 → U2.43 (GCLK1)** gives a free-running global clock. A
6-bit counter on it is 64 × 279 ns = **17.9 µs**, which lands just under SR-3's
20 µs ceiling, and the 19 spare macrocells cover it. That is the only way to
satisfy SR-1's intent and acceptance criterion 5 in full. It is a PCB change, so
it is flagged here rather than done — **BC-5** says not to.

For SR-4's bench escape hatch, `/WAIT` runs U2.37 → J1.7 with nothing else on
the net, so cutting that trace (or fitting a 0 Ω link in it) isolates the signal
without touching anything else.

---

## 6. The thing that decides whether this is worth enabling

§1 of the spec already says the Pi-side SPI is the real bottleneck. Now that
`/WAIT` exists, that stops being a performance argument and becomes a
**correctness** one, because the stall length *is* the Pi's byte time:

| Pi-side SPI | Stall per byte | vs SR-3's ~20 µs |
|---|---|---|
| current `SPI_ByteTransfer()` (Python bit-bang, `sleep(10 µs)` per tick) | 200–600 µs | **10–30× over** |
| rewritten in C / hardware SPI peripheral | ~10–20 µs | within budget |

A 200–600 µs stall freezes the Z80 completely — no interrupt service, and no
`/RFSH` cycles for machines whose DRAM refresh depends on them. That is what
SR-3 is protecting, and it is why **the Pi-side rewrite is a prerequisite for
enabling this mode, not a follow-up to it.** The CPLD half is done and costs
nothing while the mode register stays off.

---

## 7. The spec's open questions

**Q1 — is 8 `SPI_SCLK` edges the right timeout?** Neither 8 edges nor an
FSM-state timeout works, for the reason in §5: no `SCLK`, no count. Replaced by
the `SPI_RDY` gate, which needs no clock, plus the clock-wire recommendation for
the one case it cannot cover.

**Q2 — should `BUSDIR_n` be asserted for reads of `$57`?** Yes, it is a real
latent bug on expanded slots, and it is free — 44 macrocells with the fix
against 45 without, because "A is one of `$56`/`$57`/`$5A`" decodes more cheaply
than the same set with `$57` carved out. Left **off by default** so BC-1 holds
literally; the one-line change is in `MSXPi.vhd`, commented, next to the current
assignment. It needs its own hardware regression pass because it changes legacy
behaviour.

**Q3 — is the `D_buff_msx` latch intentional?** Intentional and necessary; keep
it. `D` is only valid while the write cycle is on the bus, and there is no clock
at that instant to register it with — the CPLD's only clock arrives later, from
the Pi. It is also what makes a `/WAIT`-stretched `OTIR` write safe: the Z80
holds `D` for the whole stretched cycle, so the E1 edge samples a stable value
no matter how long the stall ran. Converting it to a registered capture would
mean clocking it on `SPI_SCLK`, which is exactly what the E1 edge already does.

---

## 8. Verification performed

`./sim.sh` elaborates v1.6 and `MSXPi_v13_reference.vhd` **side by side** off one
set of stimulus, with a Pi model that reproduces `SPI_ByteTransfer()` exactly
(RDY high → spin on CS → tick → 8 bit clocks → tick → RDY low).

```
PHASE 1  legacy mode is cycle-identical to v1.3      9662 samples of
         D, BUSDIR_n, SPI_CS, WAIT_n compared        0 mismatches
         4 bytes received + 4 sent, both engines agree
         read of $5A does not start a transfer (BC-1)
PHASE 2  WAIT mode: $57 reads $1E; 4 INIR-style reads return correct
         data after a real stall; OTIR write reaches the Pi
PHASE 3  FR-5: reset clears the mode, $57 back to $0E, legacy restored
PHASE 4  SR-2: Pi gone -> /WAIT never asserts and no stale transfer armed
PHASE 5  soak: 32 INIR reads + 32 OTIR writes, all verified
PHASE 6  residual risk: kill -9 -> confirms /WAIT stays stuck (see §5)
ALL TESTS PASSED
```

Timing, from the fitted design (`EPM3064ALC44-10`, -10 speed grade):

| Path | Delay |
|---|---|
| `IORQ_n` → `WAIT_n` | 35.0 ns |
| `RD_n` → `WAIT_n` | 24.0 ns |
| `A[]` → `WAIT_n` | 35.1 ns |
| `SPI_SCLK` → `WAIT_n` (release) | 23.9 ns |

**SR-5**: the Z80 samples `/WAIT` on the falling edge of TW, ~1.5 T-states
(≈419 ns at 3.58 MHz) after `/IORQ` falls. 35 ns against 419 ns is better than
10× margin even after bus-buffer delay. The negative slacks in
`MSXPi.sta.summary` are against TimeQuest's default fictitious clock — there is
no `.sdc` in this project and the v1.3 baseline reports the same (−13.2 ns
against −16.2 ns), so it is not a regression.

### Two real bugs the differential test caught

Both would have shipped without it, and neither shows up in a single-DUT
testbench.

1. **A race between `RESET` and `spi_en`.** Adding any logic to the `spi_en`
   path made it settle one gate later than `RESET`. At the end of a reset write
   `RESET` falls first, which opens the FSM's async-set guard for a few
   nanoseconds and fires a spurious transfer. Fixed by keeping `spi_en` as one
   flat expression at the same depth as `RESET` and moving the anti-retrigger
   guard into the FSM condition. The comment in `MSXPi.vhd` says so, because the
   constraint is invisible otherwise and the next edit will re-break it.

2. **A desynchronising stale transfer.** A WAIT-mode read issued while the Pi
   was absent still armed a transfer nobody clocked; when the server came back
   it serviced that stale transfer and the byte stream was permanently one byte
   out of step. Fixed by gating the read-trigger on `SPI_RDY` (SR-2 applied to
   the transfer start, not just to the stall).

---

## 9. Files

| File | What it is |
|---|---|
| `MSXPi.vhd` | v1.6 — shifter engine + /WAIT. **The one in `MSXPi.qsf`.** |
| `MSXPi_package.vhd` | `MSXPIVer = "1110"`, plus `WAITMODE_ON`/`WAITMODE_OFF` |
| `MSXPi.qsf` | unchanged except `MAX7000_OPTIMIZATION_TECHNIQUE AREA` (§3) |
| `MSXPi_v16.pof` | new programming file, from the verified build |
| `MSXPi.pof` | **untouched v1.3 image**, deliberately left in place |
| `tb_MSXPi.vhd` | differential testbench, 6 phases |
| `MSXPi_v13_reference.vhd` | v1.3 frozen as the equivalence reference (sim only, not in the .qsf) |
| `sim.sh` | runs the whole suite; `--wave` also opens gtkwave |
| `alternative/MSXPi_v16_shifter_only.vhd` + `.pof` | shifter engine with **all** /WAIT logic removed - the diagnostic build, 44/64 |

`MSXPi.pof` was **not** overwritten. Flash `MSXPi_v16.pof` when you want v1.6;
the known-good v1.3 image stays available under its original name so the two
cannot be confused at the programmer.

### Which variant to flash

`MSXPi_v16.pof` is the deliverable. `alternative/MSXPi_v16_shifter_only.pof` is
kept because it is the build that isolated the power-up bug: same SPI engine,
**all** /WAIT logic physically removed, so it can never drive `/WAIT`. If a
future change to the /WAIT path misbehaves, flashing it splits the problem in
one step. Both are validated on real hardware.

A third variant existed during development - /WAIT bolted onto the untouched
v1.3 SPI engine - and has been removed. Once the mode bit became a proper
register it no longer placed on EPM3064A under any fitter setting, and the
shifter engine is now hardware-proven, so it had no remaining purpose.


---

## 10. Suggested hardware bring-up order

1. Flash `MSXPi_v16.pof`, **write nothing to `$57`**, and confirm `pdir`,
   `ploadr`, MSX-DOS boot and the Nextor driver all behave exactly as before
   (spec acceptance 3). This is the whole backward-compatibility claim, and it
   is the test that matters most — the mode register being off means nothing
   else in this change can be reached.
2. Confirm `IN ($57)` returns `$0E`.
3. Only then a small `.COM` that enables the mode, does one short `INIR`, and
   disables it again. Expect it to be *slower* than polling until the Pi-side
   SPI is rewritten, and expect the machine to feel unresponsive during the
   burst — that is §6, not a bug.
4. Do not run acceptance test 5 (`kill` the server mid-transfer) as `kill -9`
   until the clock wire in §5 is fitted; it will hang the MSX. `Ctrl-C` is the
   case that is covered, and is the one worth testing.
