# MegaROM mapper detection and patching — findings

Working notes behind `Server/Python/src/mapper_detect.py`. Recorded because
most of the value here is in what does **not** work; several of the obvious
improvements are actively harmful and were only caught by measuring against the
whole ROM set.

## Bank-select addresses

From `EXECROM.MAC`'s own MegaROM table (git `173f41c2`), which this project
already ships a working loader for:

| Mapper | Bank-select addresses |
|---|---|
| Konami4 | `6000h`, `8000h`, `A000h` (single addresses) |
| Konami5 (SCC) | `5000-57FF`, `7000-77FF`, `9000-97FF`, `B000-B7FF` |
| ASCII8 | `6000-67FF`, `6800-6FFF`, `7000-77FF`, `7800-7FFF` |
| ASCII16 | `6000-6FFF`, `7000-7FFF` |

ASCII8's four 2KB windows nest exactly inside ASCII16's two 4KB windows, so the
two cannot be told apart by address alone.

These are a property of the **original cartridge mapper**, so they are valid
regardless of what the ROM is being loaded into. That is the part of EXECROM
that transfers to us — its *conversion* does not, because EXECROM targets
MegaRAM hardware and merely retargets the address (`ld ix,4000h` …), keeping
opcode `32h`. With no such hardware we must convert to `CALL <handler>`.

## Detection uses exact addresses; patching uses ranges

This asymmetry is deliberate. Measured against all 51 ROMs:

| Attempt | Result |
|---|---|
| Widen the first test of the chain to 2KB ranges | **23 of 33 megaROMs became ASCII8** — at that granularity nearly every large ROM contains some unrelated store in the window |
| Require a preceding "load A" to reject data | Removed **real** switches; XEVIOUS lost all sites and became unrecognizable |
| Range-scoring with per-mapper hit counts | Misclassified ROMs verified by running (BILLIARD → Konami5, ZANACEX → Konami4) |

The jobs have opposite error costs. In **detection**, one false hit changes the
answer for the whole ROM, so specificity wins. In **patching**, the type is
already known and a missed switch is fatal while a stray patch costs a few
bytes, so coverage wins.

ASCII16 owns no address of its own, so it can only be identified by
**elimination** — which is why the chain is ordered and the order matters more
than it looks.

## The one safe way to loosen detection: repetition

A genuine bank-select address is written many times; a data coincidence appears
once or twice.

* `BUBBLE.ROM` — `7FF8h` ×133, `77F8h` ×31, `6FF8h` ×3
* `ISHTAR.ROM` — `77FFh` ×97, `67FFh` ×68, plus `6827h`/`7877h` ×4

Neither hits `6800h` or `7800h` exactly, so the strict chain rejected both.
Applying a repetition threshold **only as a fallback for ROMs the strict chain
rejects** identifies them with no collateral damage:

| ROM | before | after |
|---|---|---|
| BUBBLE.ROM | unrecognized (rejected, never transferred) | ASCII8 |
| ISHTAR.ROM | unrecognized (rejected) | ASCII16 |
| other 31 megaROMs | — | unchanged |

0 disagreements with ROMs verified by actually running them.

**Unconfirmed:** ISHTAR's ASCII8-vs-ASCII16 call. Its repeated addresses are
`77FFh`/`67FFh` (two windows ⇒ ASCII16), but `6827h`/`7877h` ×4 hint ASCII8.
Only running it settles this.

## Known limits of static patching

* **Indirect writes are invisible.** `ARCTIC.ROM` switches its 0x4000 bank via
  `ld hl,6002h` / `ld (hl),a`. No scan for opcode `32h` can find that. Would
  need `ld hl,<addr in window>` … `ld (hl),a` pair detection.
* **8KB mappers cannot be emulated by mapping alone.** The MSX memory mapper
  switches in 16KB units, but Konami/ASCII8 use 8KB banks, and page 1 alone
  holds two independently-switchable banks. An arbitrary pair cannot be
  expressed by selecting one 16KB segment, so the handler must copy 8KB —
  about 172,000 T-states (~48ms) per switch. ASCII16 has no such problem: 16KB
  banks map one-to-one onto segments and a switch is a single `OUT`.
* An obvious unimplemented win: the 8K handlers copy unconditionally, with no
  check for "this bank is already loaded". Games rewrite the same bank often.

## Konami SCC — diagnosed, not yet fixed

All five Konami ROMs that reach a graphics mode and then freeze (ALESTE,
CONTRA, FANZONE2, MANBOW, USAS) are **Konami SCC**, which banks at completely
different addresses from Konami4:

| | bank-select addresses | switchable windows |
|---|---|---|
| Konami4 | `6000h`, `8000h`, `A000h` | 3 (the one at 4000h is fixed) |
| Konami SCC | `5000-57FF`, `7000-77FF`, `9000-97FF`, `B000-B7FF` | 4 |

`PATCH_WINDOWS[MAPPER_KONAMI]` only lists the Konami4 addresses, so their real
bank switches are never converted. The writes land in RAM, no switch happens,
and the game freezes the moment it needs a bank it does not already have.
Measured site counts (`ld (nn),a` targets):

    ANDROGYN   Konami4: 0    SCC: 62
    ALESTE     Konami4: 0    SCC: 16
    CONTRA     Konami4: 2    SCC: 26
    FANZONE2   Konami4: 1    SCC: 15
    MANBOW     Konami4: 0    SCC: 70

**ANDROGYN's "RUNNING" verdict is therefore suspect**: it has zero Konami4
sites, so nothing was patched for it either. It is probably animating a title
screen out of the four banks `konamiInitialSetup` preloads and never getting
any further.

### Patching the SCC addresses alone makes it worse

Tried, and CONTRA went from FROZEN (reached SCREEN 5) to NO_LAUNCH (INIT
returns immediately). Both the 2KB ranges and the exact addresses did this.
The reason is that **not every write to those addresses is a bank number**:

    ld a,#3F
    ld (9000h),a      ; enables the SCC sound chip

CONTRA does this five times. With 16 banks, 63 unmasked indexes
`table[63 >> 1] = table[31]`, far past the 8 valid entries, and maps a garbage
segment. Real hardware masks the value to the ROM size (63 & 15 = 15).

### Masking is required, and the obvious implementation regresses

Adding `ld hl,#MASK / and (hl)` to the four 8K handlers needs
`RESIDENT_SLOT_SIZE` grown from 0x40 to 0x50 (the largest handler reaches 80
bytes). Doing that took **BILLIARD.ROM from RUNNING to hung** - a working
ASCII8 ROM, which does not even use the SCC path. Cause not identified; the
mask value, the table layout and the new addresses all check out on inspection,
so something else about the slot resize or the extra resident byte is at fault.

Reverted. The three facts above are solid and were each measured; the fix is
not. Anyone picking this up should start by finding why the slot resize breaks
an unrelated mapper, because masking is a prerequisite for SCC and probably for
robustness generally.

## Why growing RESIDENT_SLOT_SIZE breaks an unrelated mapper — answered

The resident block cannot grow upwards. Measured by writing to a region with
the layout otherwise untouched, and checking BILLIARD.ROM (ASCII8, which never
uses the SCC path):

| bytes written | BILLIARD |
|---|---|
| `F975-FABF` (the shipping layout) | runs |
| `FAC0-FAFF` | hangs |
| `FAD6-FAFF` (42 bytes) | hangs |

So **the usable window is about `F975-FAD5`, ~352 bytes** — which is exactly
what SofaRun uses (`ld de,0F975h / ld bc,0160h`, 0160h = 352). Two independent
routes to the same boundary. Something the BIOS or the game needs lives
immediately above it.

Growing `RESIDENT_SLOT_SIZE` from 0x40 to 0x50 pushed the four 8K handlers from
`F9C0-FABF` to `F9C0-FAFF`, over that edge. Nothing was wrong with the masking
code or the slot arithmetic; the block simply ran out of room. Current usage is
`F975-FABF` = 331 bytes, leaving roughly **22 bytes of headroom**.

### What this means for masking

Masking needs ~4 bytes per handler and the largest 8K handler already fills its
0x40 slot exactly, so it cannot be bought by making slots bigger. It has to come
out of the existing budget:

* The four 8K handlers are nearly identical - they differ only in the
  destination window and which port they borrow. Factoring the common body into
  one routine with four small stubs would free well over 150 bytes.
* `RESIDENT_TABLE_ADDR` reserves 64 entries (`MAX_STORAGE_SEGMENTS`), but even a
  512KB ROM needs only 32. Halving it frees 32 bytes.

Either is enough; the first is the better fix and would leave room for the
per-window "bank already loaded" cache as well.
