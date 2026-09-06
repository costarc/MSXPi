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
