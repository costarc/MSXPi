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
; ETHMODE.COM - report or force the Ethernet UNAPI transport backend
; =============================================================================
;   ETHMODE      report the mode currently in effect
;   ETHMODE P    force the polled backend
;   ETHMODE W    force hardware /WAIT
;
; This is the ROM-build replacement for "ETHUNAPI P".  The .COM installer could
; be told to stay on the bounded transport because it did the probing itself;
; the ROM driver probes lazily, on the first UNAPI call, so by the time a user
; could object the choice has already been made.  This lets them change it
; afterwards.
;
; WHY IT MATTERS, beyond tidiness.  Polled is bounded everywhere and cannot
; hang.  Hardware /WAIT can: the CPLD holds /WAIT for exactly as long as the Pi
; holds RPI_READY, with no timeout, so a Pi that stops clocking mid-transfer
; stalls the Z80 until the power goes off.  When something hangs and the
; transport is a suspect, this is how you take it out of the picture - run
; ETHMODE P, then whatever hung.
;
; Forcing is not sticky across a reboot: the driver's state lives in the disk
; driver work area and is re-initialised at every boot.
;
; Uses implementation-specific routine 128, whose B values are
; 0 report, 1 polled-hardware, 2 /WAIT, 3 polled-openMSX, and which returns the
; mode that was in effect BEFORE the call.
; =============================================================================

_TERM0:     equ     00h
_STROUT:    equ     09h
BDOS:       equ     0005h
CALSLT:     equ     001Ch
EXTBIO:     equ     0FFCAh
ARG:        equ     0F847h

FN_SET_MODE:  equ   128
MODE_REPORT:  equ   0
MODE_POLL_HW: equ   1
MODE_WAIT:    equ   2

            org     100h

            ld      de,BANNER_S
            ld      c,_STROUT
            call    BDOS

; --- Work out what was asked for -------------------------------------------
; The DOS command tail is at 0080h (length) and 0081h onwards (text, starting
; with the separating space).  No argument means "report only".
            ld      b,MODE_REPORT
            ld      a,(0080h)
            or      a
            jr      z,.have_arg
            ld      a,(0082h)
            and     11011111b               ; crude upper-case
            cp      "P"
            jr      nz,.not_p
            ld      b,MODE_POLL_HW
            jr      .have_arg
.not_p:
            cp      "W"
            jr      nz,.have_arg
            ld      b,MODE_WAIT
.have_arg:
            ld      a,b
            ld      (WANTED),a

; --- Find the implementation ------------------------------------------------
; No RAM helper is needed to ASK where it is; whether one is needed to CALL it
; depends on the segment, and is checked below.
            ld      de,2222h
            ld      hl,0
            ld      a,0FFh
            call    EXTBIO
            ld      (HELPER_ADD),hl

            ld      hl,UNAPI_ID
            ld      de,ARG
            ld      bc,UNAPI_ID_LEN
            ldir

            ld      de,2222h
            xor     a
            ld      b,0
            call    EXTBIO
            ld      a,b
            or      a
            jr      nz,.found
            ld      de,NONE_S
            jp      DIE
.found:
            ld      de,2222h
            ld      a,1
            call    EXTBIO
            ld      (IMP_SLOT),a
            ld      a,b
            ld      (IMP_SEG),a
            ld      (IMP_ENTRY),hl

            inc     a                       ; segment FFh -> in ROM
            jr      z,.callable
            ld      hl,(HELPER_ADD)
            ld      a,h
            or      l
            jr      nz,.callable
            ld      de,NOHELPER_S
            jp      DIE
.callable:

; --- Report the old mode, then the new one ---------------------------------
            ld      a,(WANTED)
            ld      b,a
            ld      a,FN_SET_MODE
            call    CALL_UNAPI
            ld      (WAS),a

            ld      de,WAS_S
            ld      c,_STROUT
            call    BDOS
            ld      a,(WAS)
            call    PRINT_MODE

            ld      a,(WANTED)
            or      a
            jr      z,.done                 ; report only: nothing changed

            ; Read it back rather than assuming the write took.  Routine 128
            ; is the only way to see the driver's state at all, and a silent
            ; no-op here would be indistinguishable from a working force.
            ld      b,MODE_REPORT
            ld      a,FN_SET_MODE
            call    CALL_UNAPI
            push    af
            ld      de,NOW_S
            ld      c,_STROUT
            call    BDOS
            pop     af
            call    PRINT_MODE
.done:
            ld      c,_TERM0
            jp      BDOS

; --- CALL_UNAPI: invoke routine A.  Segment FFh means the implementation is in
; ROM and a plain inter-slot call reaches it; anything else is a mapped RAM
; segment and goes through the RAM helper's CALL_MAP.
CALL_UNAPI:
            push    af
            ld      a,(IMP_SLOT)
            ld      iyh,a
            ld      ix,(IMP_ENTRY)
            ld      a,(IMP_SEG)
            inc     a
            jr      z,.rom
            dec     a
            ld      iyl,a
            ld      hl,(HELPER_ADD)
            pop     af
            jp      (hl)
.rom:
            pop     af
            call    CALSLT
            ei
            ret

; --- PRINT_MODE: A = a MODE_* value as the driver reports it (0 polled
; hardware, 1 /WAIT, 2 polled openMSX, FFh never probed).
PRINT_MODE:
            ld      de,M_POLLED_S
            or      a
            jr      z,.emit
            dec     a
            ld      de,M_WAIT_S
            jr      z,.emit
            dec     a
            ld      de,M_OMSX_S
            jr      z,.emit
            ld      de,M_UNKNOWN_S
.emit:
            ld      c,_STROUT
            jp      BDOS

DIE:
            ld      c,_STROUT
            call    BDOS
            ld      c,_TERM0
            jp      BDOS

; --- Data -------------------------------------------------------------------
HELPER_ADD: dw      0
IMP_SLOT:   db      0
IMP_SEG:    db      0
IMP_ENTRY:  dw      0
WANTED:     db      0
WAS:        db      0

UNAPI_ID:   db      "ETHERNET",0
UNAPI_ID_LEN: equ   $-UNAPI_ID

BANNER_S:   db      "ETHMODE - transport backend",13,10,13,10,"$"
WAS_S:      db      "Was: $"
NOW_S:      db      "Now: $"
M_POLLED_S: db      "polled",13,10,"$"
M_WAIT_S:   db      "hardware /WAIT",13,10,"$"
M_OMSX_S:   db      "polled (openMSX)",13,10,"$"
M_UNKNOWN_S: db     "not probed yet",13,10,"$"
NONE_S:     db      "*** No ETHERNET implementation found.",13,10,"$"
NOHELPER_S: db      "*** Implementation is in a RAM segment and no UNAPI RAM",13,10
            db      "    helper is installed. Run RAMHELPR I first.",13,10,"$"
