; MSXPi Interface
; Version 1.6.1
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
;
; File history :
; 0.1    : initial version
; 0.9.1  : Changes to support new transfer logic
; 1.1    : Changes to support new transfer routines
; 1.2    : Removed MSX-DOS 1 Kernel; Replaced by MSXPio BIOS
; 1.6    : Back as the second 16KB bank of the 32KB EEPROM: the same CALL
;          MSXPI handler and Ethernet UNAPI driver as the MSX-DOS ROM, without
;          the MSX-DOS 1 kernel.
;
; =============================================================================
; MSXPi BIOS-only ROM (no MSX-DOS)
; =============================================================================
; The EEPROM is 32KB and the A14/A15 jumper selects one 16KB half.  The build
; writes target/msxpi32k.rom as
;
;   0000-3FFF  msxpibios.rom - MSX-DOS 1 kernel + MSXPi driver + UNAPI
;   4000-7FFF  msxpibas.rom  - this file: CALL MSXPI + UNAPI, no disk system
;
; so "MSXPi boots MSX-DOS 1" and "MSXPi next to Nextor, no drives, no disk
; RAM" are a jumper apart instead of an EEPROM rewrite apart.
;
; What the DOS kernel provided, and this ROM now provides itself:
;
;   GETSLT/GETWRK  ethrom.bin - the UNAPI driver, the SAME binary the DOS ROM
;                  carries - calls them at the fixed addresses KERNEL_GETSLT/KERNEL_GETWRK
;                  (unapi_wrk.inc).
;                  Jumps sit at exactly those addresses.
;   Work area      The kernel's secondary-diskrom path (A580C) allocates
;                  MYSIZE below HIMEM and stores it in SLTWRK.  INIT does the
;                  same, with a copy of the kernel's allocator.
;   Stash          msxpi_bios.asm keeps 3 bytes at work-area offsets 5..7;
;                  -DMSXPI_ROM_STASH points it at GETWRK below.
;
; The work area can only be taken when a disk kernel has ALREADY initialised
; (DEVICE 1..7Fh), i.e. with MSXPi in a higher slot than Nextor - the README's
; recommended setup.  A disk ROM initialising AFTER us assumes F1C9..F37F is
; free, and a block taken from HIMEM before it would land inside that area.
; Without a disk system nothing could use UNAPI anyway, so INIT then installs
; nothing and GETWRK hands the CALL handler PROCNM instead: the CALL name has
; been matched by the time the stash is used, and nothing else reads PROCNM
; while CALL MSXPI runs.
; =============================================================================

        INCLUDE "unapi_wrk.inc"         ; UNAPI_WRKEND, UNAPI_ORG

SLTWRK:     EQU     $FD09
HOKVLD:     EQU     $FB20
MEMSIZ:     EQU     $F672
STKTOP:     EQU     $F674
SAVSTK:     EQU     $F6B1
FILTAB:     EQU     $F860
NULBUF:     EQU     $F862
BOTTOM:     EQU     $FC48

MYSIZE:     EQU     UNAPI_WRKEND        ; the DOS ROM's work area, same layout

; =============================================================================
; Living next to the DOS ROM in one EEPROM
; =============================================================================
; On the board (hardware/Schematic, J3 "ROM_SWITCH") the EEPROM /CE is /SLTSL
; alone and its A14 pin is jumpered to CPU A15 or CPU A14.  The chip therefore
; answers in every page of its slot, and whichever half is not at 4000h is
; mirrored at 8000h:
;
;   A15 jumper   4000h = lower half (DOS ROM)   8000h = upper half (this ROM)
;   A14 jumper   4000h = upper half (this ROM)  8000h = lower half (DOS ROM)
;
; The BIOS runs "AB" headers found at 8000h as well, and calls the INIT and
; STATEMENT addresses they hold - which lie in page 1, i.e. in the OTHER ROM.
; So each header's addresses must be harmless in the other ROM.  The DOS ROM
; is left untouched; this ROM does all the fitting, at addresses the build
; reads out of msxpibios.rom and passes in:
;
;   DOS_INIT  the DOS header's INIT.  Here: RET - A14 jumper, the mirrored DOS
;             header does nothing instead of running this ROM's code.
;   DOS_STMT  the DOS header's STATEMENT, and ours too.  Here: JP CALLHAND.
;             Either handler reached through the mirror only runs after the
;             page-1 one did not recognise the statement, and then does not
;             recognise it either.
;   DOS_RET   the DOS ROM's MTOFF, a plain RET (via the fixed JP at 401Fh), and
;             our INIT.  Here: JP INIT.  A15 jumper: our mirrored header lands
;             on the DOS ROM's RET.
;
; The addresses move with every DOS ROM build, so the two must always be built
; together - ../../build does that, and checks the DOS side of the bargain.
; Device mode, so code can be placed at those addresses in any order.
        DEVICE  NOSLOT64K

    IFNDEF DOS_INIT
        DISPLAY "define DOS_INIT, DOS_STMT and DOS_RET (see ../../build)"
        ERROR   "DOS ROM addresses missing"
    ENDIF

        ORG     $4000

; ROM header
        db      "AB"
        dw      DOS_RET         ; INIT      - JP INIT here, RET in the DOS ROM
        dw      DOS_STMT        ; STATEMENT - JP CALLHAND here
        dw      0               ; DEVICE
        dw      0               ; TEXT
        dw      0,0,0           ; reserved

; =============================================================================
; INIT
; =============================================================================
INIT:
        ld      hl,MSXPIVERSION
        call    PRINT

        ; Only under a disk system that is already up (see the header).
        ; DEVICE is the disk kernels' own counter: 0 = none yet, bit 7 = the
        ; disk system was aborted (SHIFT held at boot).
        ld      a,(DEVICE)
        or      a
        ret     z
        ret     m
        ld      a,(HOKVLD)
        rrca                    ; EXTBIO hook initialised?
        ret     nc

        ; The UNAPI init guards against a second INIT, but only after this
        ; point - so do not allocate a second work area either.
        call    SLTWRKP
        ld      a,(hl)
        inc     hl
        or      (hl)
        ret     nz

        di                      ; ALLOC moves the stack, as in the kernel
        ld      hl,MYSIZE
        call    ALLOC
        ret     c               ; no room: no UNAPI, CALL MSXPI still works
        ex      de,hl
        call    SLTWRKP
        ld      (hl),e
        inc     hl
        ld      (hl),d          ; SLTWRK entry = work area
        jp      UNAPI_ORG       ; the UNAPI driver's init, as INIENV does

; -----------------------------------------------------------------------------
; ALLOC - allocate HL bytes below HIMEM
; -----------------------------------------------------------------------------
; A verbatim copy of the MSX-DOS 1 kernel's allocator (A5EE8 in msx-dos.mac):
; lowers HIMEM and moves the stack and the BASIC file buffers down with it.
; Output: CF set = no room; otherwise HL = start of the block.
ALLOC:
        ld      a,l
        or      h
        ret     z
        xor     a
        sub     l
        ld      l,a
        ld      a,000H
        sbc     a,h
        ld      h,a
        ld      c,l
        ld      b,h
        add     hl,sp
        ccf
        ret     c
        ld      de,(BOTTOM)
        sbc     hl,de
        ret     c
        ld      a,h
        cp      002H
        ret     c
        push    bc
        ld      hl,00000H
        add     hl,sp
        ld      e,l
        ld      d,h
        add     hl,bc
        push    hl
        ld      hl,(STKTOP)
        and     a
        sbc     hl,de
        ld      c,l
        ld      b,h
        inc     bc
        pop     hl
        ld      sp,hl
        ex      de,hl
        ldir
        pop     bc
        ld      hl,(HIMEM)
        add     hl,bc
        ld      (HIMEM),hl
        ld      de,0FDEAH
        add     hl,de
        ld      (FILTAB),hl
        ex      de,hl
        ld      hl,(MEMSIZ)
        add     hl,bc
        ld      (MEMSIZ),hl
        ld      hl,(NULBUF)
        add     hl,bc
        ld      (NULBUF),hl
        ld      hl,(STKTOP)
        add     hl,bc
        ld      (STKTOP),hl
        dec     hl
        dec     hl
        ld      (SAVSTK),hl
        ld      l,e
        ld      h,d
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        ld      a,002H
ALLOC1:
        ex      de,hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ex      de,hl
        ld      bc,00007H
        ld      (hl),b
        add     hl,bc
        ld      (hl),b
        ld      bc,00102H
        add     hl,bc
        dec     a
        jr      nz,ALLOC1
        ret

; -----------------------------------------------------------------------------
; MY_GETSLT - A = slot id of page 1 (this ROM), expanded-slot bits included
; -----------------------------------------------------------------------------
; Reads the slot registers directly rather than through F365h as the kernel
; does: F365h is only set up by a disk kernel, and this ROM also runs without
; one.  Corrupts AF, BC, HL; DE preserved (ethrom.asm relies on it).
MY_GETSLT:
        in      a,($A8)
        rrca
        rrca
        and     %00000011       ; primary slot of page 1
        ld      c,a
        ld      b,0
        ld      hl,EXPTBL
        add     hl,bc
        bit     7,(hl)          ; expanded?
        ld      a,c
        ret     z
        inc     hl
        inc     hl
        inc     hl
        inc     hl              ; SLTTBL entry of this primary slot
        ld      a,(hl)
        and     %00001100       ; page-1 secondary slot
        or      c
        or      $80
        ret

; -----------------------------------------------------------------------------
; SLTWRKP - HL = this ROM's page-1 SLTWRK entry (the kernel's A5FCD layout)
; -----------------------------------------------------------------------------
; Corrupts AF, BC, HL; DE preserved.
SLTWRKP:
        call    MY_GETSLT
        ld      b,a
        and     %00000011
        rlca
        rlca
        rlca
        rlca                    ; primary * 16
        ld      c,a
        ld      a,b
        and     %00001100       ; secondary * 4
        or      c
        inc     a               ; page 1
        add     a,a             ; word entries
        ld      c,a
        ld      b,0
        ld      hl,SLTWRK
        add     hl,bc
        ret

; -----------------------------------------------------------------------------
; MY_GETWRK - HL = IX = work area; PROCNM when INIT allocated none
; -----------------------------------------------------------------------------
; Corrupts AF, HL, IX; BC and DE preserved (msxpi_bios.asm's stash contract is
; AF/HL/IX only, stricter than the kernel's GETWRK).
MY_GETWRK:
        push    bc
        call    SLTWRKP
        pop     bc
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        or      h
        jr      nz,MY_GETWRK1
        ld      hl,PROCNM       ; no work area: CALL-time scratch, see header
MY_GETWRK1:
        push    hl
        pop     ix
        ret

; =============================================================================
; CALL handler - shared with the MSX-DOS ROM and msxpiext.bin
; =============================================================================
        INCLUDE "msxpi_call.asm"

MSXPIVERSION:
        DB      13,10,"MSXPi BIOS v1.6.1",13,10
		DB		"Build "
BuildId: DB "20260930.065"
        DB      13,10,"RCC (c) 2015-2026",13,10,0

CALL_TABLE:
        DB      "MSXPIVER",0
        DW      _MSXPIVER
        DB      "MSXPI",0
        DW      _MSXPI
ENDOFCMDS:
        DB      00

        INCLUDE "include.asm"
; -DMSXPI_ROM_STASH from the build: msxpi_bios.asm then takes its stash from
; GETWRK below, without the DSKIO-only code MSXPI_DRIVER would pull in.
        INCLUDE "msxpi_bios.asm"
        INCLUDE "putchar_msxdos.asm"
CODE_END:

; =============================================================================
; Fixed entry points for ethrom.bin (GETSLT/GETWRK in UNAPI/src/ethrom.asm)
; =============================================================================
        ASSERT  CODE_END <= KERNEL_GETSLT
        ORG     KERNEL_GETSLT
GETSLT:
        jp      MY_GETSLT
        ORG     KERNEL_GETWRK
GETWRK:
        jp      MY_GETWRK

; =============================================================================
; Entries at the DOS ROM's header addresses (see "Living next to the DOS ROM")
; =============================================================================
; Each is 3 bytes and must sit in free space: above the code, clear of the
; GETSLT/GETWRK jumps, below the UNAPI image, and clear of each other.
    MACRO CHECK_FREE addr
        ASSERT  addr >= CODE_END && addr+3 <= UNAPI_ORG
        ASSERT  addr+3 <= KERNEL_GETSLT || addr >= KERNEL_GETWRK+3
    ENDM
        CHECK_FREE DOS_INIT
        CHECK_FREE DOS_STMT
        CHECK_FREE DOS_RET
        ASSERT  DOS_INIT+3 <= DOS_STMT || DOS_STMT+3 <= DOS_INIT
        ASSERT  DOS_INIT+3 <= DOS_RET  || DOS_RET+3  <= DOS_INIT
        ASSERT  DOS_STMT+3 <= DOS_RET  || DOS_RET+3  <= DOS_STMT

        ORG     DOS_INIT
        ret
        ORG     DOS_STMT
        jp      CALLHAND
        ORG     DOS_RET
        jp      INIT

; =============================================================================
; Ethernet UNAPI driver - the same image as in the MSX-DOS ROM
; =============================================================================
        ORG     UNAPI_ORG
        INCBIN  "ethrom.bin"
        ASSERT  $ <= $8000

        SAVEBIN OUTFILE,$4000,$4000
