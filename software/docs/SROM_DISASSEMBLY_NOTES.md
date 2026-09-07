# SofaROM (SROM.COM) — disassembly notes

Read to answer one question: **does SofaROM copy 8KB on every bank switch for
8KB mappers, or is there a cheaper way?** Addresses are SROM.COM v3.0 loaded at
0100h (32192 bytes, 0100h-7EC0h).

## The headline: SofaROM mostly does not emulate mappers at all

It is **device-first**. `/Dx` selects among nine devices — Memory mapper, turboR
mapper, SD Snatcher, Snatcher, MegaRAM, ESE SCC, MegaFlashROM SCC(+/SD),
Carnivore 2 — and *"SofaROM will pick the best suitable ROM device depending on
the ROM type"*.

For every device that is real mapper hardware, it writes a **mode byte to
7FFFh** and lets the cartridge do the banking. From 0E6Bh onwards:

    ld a,#04 / ld (7FFFh),a    ; then banks at 5000/7000/9000/B000  -> Konami SCC
    ld a,#24 / ld (7FFFh),a    ; same addresses, variant
    ld a,#84 / ld (7FFFh),a    ; then banks at 6000/6800/7000/7800  -> ASCII8
    ld a,#C4 / ld (7FFFh),a    ; then banks at 6000/7000            -> ASCII16
    ld a,#44 / ld (7FFFh),a    ; 5000/7000/9000/B000                -> Konami SCC

followed by initialising banks 0,1,2,3:

    xor a / ld (5000h),a / inc a / ld (7000h),a / inc a / ld (9000h),a ...

**No patching and no copying**, because the hardware implements the mapper.
That is where SofaROM's speed and breadth come from, and it is hardware we do
not have on MSXPi.

## What it does on the Memory mapper device — our comparable case

SROM.TXT is explicit:

    * Memory mapper
      - ROMs will be patched at load time by SofaROM for all ROM types.
      - Disk accesses during ROM execution.

So on the one device comparable to ours it is in the **same category we are**:
it patches the ROM, and it does not hold everything resident. It has no magic
zero-cost path for 8KB mappers on a 16KB-granular mapper.

## The mapper-port handler: a single OUT

The resident blob is copied from 6F6Fh to F975h, 0118h bytes (0FA5h):

    ld hl,6F6Fh / ld de,F975h / ld bc,0118h / ldir

Inside it, the bank-switch handlers are as cheap as possible:

    F97D:  out (FDh),a       ; page 1 mapper segment
           ld (F989h),a      ; remember what is currently mapped
           ret
    F983:  out (FEh),a       ; page 2 mapper segment
           ld (F98Ah),a
           ret

and the dispatcher picks the page from the write address with a single bit test
(`bit 7,h`: 50h/70h -> page 1, 90h/B0h -> page 2), then loads a precomputed
segment number and jumps to one of the two stubs above.

**One OUT per switch, and it tracks the currently-mapped segment** so a
redundant switch costs nothing.

### What this does NOT establish

A single OUT maps a **16KB segment per page**, but Konami and ASCII8 have **two
independently switchable 8KB windows per page**. One OUT cannot express an
arbitrary pair of 8KB banks. So this handler is the 16KB-granular path; the
disassembly does not show a trick that makes arbitrary 8KB pairs free, and
given the SROM.TXT wording above there probably is not one. The 8KB copy cost
looks inherent without cartridge hardware.

## Techniques worth stealing

1. **Borrow the resident region, do not claim it.** SofaROM saves the existing
   0180h bytes at F975h into an allocated buffer before use (44C3h-44D3h) and
   copies them back afterwards (4D1Ch-4D28h). We overwrite that region blind,
   which is exactly the area where writing past FAD5h hung an unrelated ROM.

2. **Track the currently-mapped segment** (F989h/F98Ah). Our 8K handlers copy
   unconditionally with no "already loaded" check; games rewrite the same bank
   constantly.

3. **Self-modifying resident code.** SofaROM pokes opcodes into the resident
   routine to specialise it - FBh (EI), C9h (RET), C3h (JP) written to F9FBh,
   F9FCh, F9E8h etc. from 3586h-362Eh - so one blob serves many configurations
   without carrying branches. That is how it fits real functionality into a few
   hundred bytes.

4. **Twelve mapper variants**, not four: ASCII16, ASCII16F8, ASCII8, ASCII8F8,
   Konami SCC, Konami, ASCII16W, ASCII8W, Linear, Linear0, LinearC, BASIC.

## Consequences for msxarch

* **ASCII16 already matches SofaROM's best approach** - our handler is a single
  `out (FDh),a`/`out (FEh),a` with no copy, the same shape as F97Dh/F983h. It is
  the family that can run at full speed, and worth prioritising.
* **The 8KB copy is probably not avoidable** by cleverness. SofaROM's speed on
  Konami/ASCII8 comes from cartridge hardware, not from a better algorithm. What
  IS available to us is the redundant-switch check (technique 2), which costs
  ~12 bytes and skips the copy whenever the requested bank is already mapped.
* **Adopt save/restore of F975h-FAF5h** (technique 1) before anything else in
  that region.
