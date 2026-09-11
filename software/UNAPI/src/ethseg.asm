; MSXPi Interface
; Version 1.6
; ------------------------------------------------------------------------------
; MIT License
;
; Copyright (c) 2015-2026 Ronivon Costa
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
; ------------------------------------------------------------------------------

; =============================================================================
; MSXPi Ethernet UNAPI - resident code, RAM (mapped segment) build
; =============================================================================
; This is the part that lives in a mapped RAM segment.  It is assembled as a
; standalone binary at 4000h and INCBIN'd by the installer (ethunapi.asm),
; because sjasm 0.39j has no phase/disp directive.  The installer reads the
; symbol addresses it needs to patch from the export file sjasm writes.
;
; Structure follows examples/unapi-ram.asm from the MSX-UNAPI specification.
;
; This file holds only what is specific to the RAM build: the EXTBIO hook as
; the RAM helper enters it, the slot/segment the installer patches in, and the
; work area.  The entry point and dispatch table are in ethcore.asm, the
; transport in ethtrans.asm and the routines in ethops.asm - all three shared
; byte-for-byte with the ROM build (ethrom.asm).
;
; The ROM build is the primary one: reporting segment $FF is what puts
; InterNestor Lite on its CALSLT path, the one every field implementation
; uses.  This build stays as the option for people who cannot reflash.
; =============================================================================

EXTBIO:     equ     0FFCAh
ARG:        equ     0F847h

            include "../../asm-common/include/unapi_wrk.inc"

            org     4000h

SEG_CODE_START:

; =============================================================================
; EXTBIO hook execution - MUST be at 4000h
; =============================================================================
; The RAM helper's segment-call routine enters here.  Per MSX-UNAPI 3.3 the
; rules are: not our DE -> chain; A=FFh -> chain (lets the RAM helper install);
; wrong API id -> chain; A=0 -> B=B+1 and chain; A=1 -> answer; A>1 -> A=A-1
; and chain.
DO_EXTBIO:
            push    hl
            push    bc
            push    af

            ld      a,d
            cp      22h
            jr      nz,JUMP_OLD
            cp      e                   ; DE must be 2222h
            jr      nz,JUMP_OLD

            ; --- Compare the identifier at ARG with ours, case-insensitively
            ld      hl,UNAPI_ID
            ld      de,ARG
ID_LOOP:
            ld      a,(de)
            call    TOUPPER
            cp      (hl)
            jr      nz,JUMP_OLD2
            inc     hl
            inc     de
            or      a                   ; both ended at the terminating zero?
            jr      nz,ID_LOOP

            ; --- A=FFh: chain, so the RAM helper can install
            pop     af
            push    af
            inc     a
            jr      z,JUMP_OLD2

            ; --- A=0: count us and chain
            pop     af
            pop     bc
            or      a
            jr      nz,DO_EXTBIO2
            inc     b
            pop     hl
            ld      de,2222h
            jp      OLD_EXTBIO
DO_EXTBIO2:

            ; --- A=1: report slot, segment and entry point.  Do NOT chain.
            dec     a
            jr      nz,DO_EXTBIO3
            pop     hl
            ld      a,(MY_SEG)
            ld      b,a
            ld      a,(MY_SLOT)
            ld      hl,UNAPI_ENTRY
            ld      de,2222h
            ret

            ; --- A>1: decrement (already done) and chain
DO_EXTBIO3:
            pop     hl
            ld      de,2222h
            jp      OLD_EXTBIO

JUMP_OLD2:
            ld      de,2222h
JUMP_OLD:
            pop     af
            pop     bc
            pop     hl
            jp      OLD_EXTBIO

; --- Patched by the installer once the segment is allocated -----------------
; These two must stay adjacent and in this order: the installer writes both
; with a single 16-bit store.
MY_SLOT:    db      0
MY_SEG:     db      0

TOUPPER:
            cp      "a"
            ret     c
            cp      "z"+1
            ret     nc
            sub     20h
            ret

; --- ETH_WRK: point IX at the work area.
; The ROM build gets this from the MSX-DOS kernel's GETWRK; here it is simply
; a fixed address, so the shared code does not have to know which build it is
; in.  Corrupts IX only, but the contract allows AF, BC and HL too.
ETH_WRK:
            ld      ix,ETH_STATE
            ret

; =============================================================================
; Data
; =============================================================================

; The identifier must be zero-terminated and is compared case-insensitively.
UNAPI_ID:
            db      "ETHERNET",0
UNAPI_ID_END:

; At most 63 characters plus the terminating zero, printable only, and it must
; live in the same segment as the code (MSX-UNAPI rule 5).
APIINFO:
            db      "MSXPi Ethernet UNAPI",0

; =============================================================================
; Shared with the ROM build
; =============================================================================
            include "ethtrans.asm"
            include "ethops.asm"
            include "ethcore.asm"

SEG_CODE_END:

; =============================================================================
; Work area
; =============================================================================
; Deliberately placed just PAST the image the installer copies, not inside it.
; sjasm drops a trailing `ds` from the output binary, so a work area inside the
; image would make the installer's `ldir` read past the end of ethseg.bin and
; copy whatever followed it in memory.  Everything here is already zero: the
; installer clears the whole segment before copying, and MACADDR in particular
; MUST start as zeros so that a cached address is provably a fetched one.
;
; The first UNAPI_WRK bytes are unused here.  They exist so that the offsets in
; unapi_wrk.inc, which in the ROM build have to skip the disk driver's own part
; of its work area, are identical in both builds.
ETH_STATE:      equ     SEG_CODE_END
OLD_EXTBIO:     equ     ETH_STATE+o_OLD_EXTBIO

            export  DO_EXTBIO
            export  OLD_EXTBIO
            export  MY_SLOT
            export  MY_SEG
            export  UNAPI_ENTRY
            export  APIINFO
            export  UNAPI_ID
            export  UNAPI_ID_END
            export  SEG_CODE_START
            export  SEG_CODE_END
            export  ETH_STATE
            export  ETH_DETECT
            export  ETH_POLLMODE
            export  ETH_VERIFY
