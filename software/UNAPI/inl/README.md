# InterNestor Lite for MSXPi

## What is here

- `inl-2.3-ram-implementation.patch` — two fixes to InterNestor Lite 2.3 that it
  needs before it can use an Ethernet UNAPI implementation living in a **mapped
  RAM segment**, which is what this driver is.
- `msr-from-ramhelpr.asm` — Konamiman's `ramhelpr.asm` with the N80-only
  directives replaced by a plain `INSTALL_MSR: equ 1`, so it can be built with
  sjasm. Produces `MSR.COM` (mapper support routines + UNAPI RAM helper), which
  MSX-DOS 1 needs and which is not distributed as a binary.

Both built products are vendored in `../bin/`.

## Building

Both INL and MSR assemble with **sjasm 0.39h+ using the Compass compatibility
switch** (`-c`), which is what INL's own `DOCS/building.md` recommends. Nestor80
is not required.

```
sjasm -c INL-TRAN.ASM inl-tran.dat
sjasm -c INL-RES.ASM  inl-res.dat
cat inl-tran.dat inl-res.dat > INL.COM

sjasm -c msr-from-ramhelpr.asm MSR.COM
```

The toolchain is verified, not assumed: assembling the same source with
`INSTALL_MSR: equ 0` reproduces Konamiman's official `RAMHELPR.COM`
**byte for byte** (sha1 `eb97f7fd9d4d1991beb0f732c38138cd22f804d1`). So the
`MSR.COM` built here can be trusted to the same degree.

## Why INL needs patching

InterNestor Lite is normally used with ROM-based Ethernet UNAPI implementations
such as ObsoNET, where the discovery procedure reports segment `$FF`. This
driver lives in a mapped RAM segment, and INL 2.3's handling of that case has
two defects — which is presumably why they were never noticed.

### 1. The RAM helper address is fetched only when it is not needed

```asm
ld   (_UN_SEG),a          ; A = segment number
ld   (_UN_ADDRESS),hl
cp   #FF
jr   nz,SRCHUNAPI_2       ; segment != FF -> SKIP fetching the helper
;ld  a,#FF
call EXTBIO
ld   (_UN_RAMCALL),hl
```

The test is inverted. `_UN_RAMCALL` is initialised to 0 and is set only when the
segment is `$FF`, i.e. when the implementation is *not* in mapped RAM and the
helper is not needed. INL's own comment elsewhere states the requirement: *"JP
to CALSLT if segment is #FF, to UN_RAMCALL otherwise."*

For a RAM implementation `_UN_RAMCALL` therefore stays 0, and the later
`ld ix,(_UN_RAMCALL)` / `jp (ix)` jumps to address 0.

Observed as: `Searching Ethernet UNAPI implementation... OK` / `Found` with no
name printed, then a return to the DOS prompt.

The patch inverts the test, and restores the `ld a,#FF` that was commented out
(it was redundant only because the old test fell through with A already `$FF`)
plus the `ld hl,0` the RAM helper query requires.

### 2. The name is read through CALL_MAP instead of RD_MAP

`_UN_RAMCALL` holds the base of the helper's jump table, whose `+0` entry is
`CALL_MAP` — used correctly for calling routines at `EXEUNAP3`. The
implementation-name loop wants to *read a byte from a segment*, which is
`RD_MAP` at `+3`:

```asm
ld ix,(_UN_RAMCALL)   ;RAMCALL: In: A=Slot, HL=Dir, B=Seg; Out: A=Data
```

The signature in that comment is `RD_MAP`'s, but the address is `CALL_MAP`'s.
The patch adds the `+3`.

With both applied, INL installs:

```
Searching Ethernet UNAPI implementation... OK
Found MSXPi Ethernet UNAPI v0.1 at slot 2, segment 126
InterNestor Lite has been installed. Have fun! (^^)/
```

## Worth reporting upstream

These are defects in InterNestor Lite itself, not workarounds for anything
MSXPi-specific — any RAM-segment Ethernet UNAPI implementation would hit them.
Source: https://github.com/Konamiman/MSX/tree/master/SRC/INL

## Open

`INL S` reports "InterNestor Lite is not installed" immediately after a
successful install. Not yet diagnosed.
