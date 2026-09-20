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
; UCOUNT.COM - count installed UNAPI implementations, by identifier
; =============================================================================
; Prints how many implementations of "ETHERNET" and of "TCP/IP" the standard
; discovery procedure reports.
;
; Written to settle one question: after INL installs successfully it reports
; "InterNestor Lite is not installed" on the next invocation. Its check is
;
;     copy "TCP/IP" to ARG; EXTBIO with A=0; if B=0 -> not installed
;
; so either INL never registered a TCP/IP implementation, or the count is fine
; and its check fails further along. Those need completely different fixes, and
; guessing between them is how the last several hours went.
;
;   ETHERNET 01, TCP/IP 00  -> INL did not register
;   ETHERNET 01, TCP/IP 01  -> registration is fine, INL's own check is at fault
;   ETHERNET 00             -> our driver is not installed either; start there
; =============================================================================

_TERM0:     equ     00h
_STROUT:    equ     09h
BDOS:       equ     0005h
EXTBIO:     equ     0FFCAh
ARG:        equ     0F847h

            org     100h

            ld      de,BANNER_S
            ld      c,_STROUT
            call    BDOS

            ld      hl,ID_ETH
            ld      de,ETH_S
            call    COUNT_AND_PRINT

            ld      hl,ID_TCP
            ld      de,TCP_S
            call    COUNT_AND_PRINT

; --- Dump exactly what INL's "am I installed?" check compares ---------------
; It walks TCP/IP implementations and skips any whose entry point is >= C000h
; (page 3), or whose slot differs from RAMAD1 (F344h), or whose segment is FFh.
; Printing all four values says which test rejects it, instead of guessing.
; INL's FIRST gate: if the mapper support routines are not detected it reports
; "not installed" without checking anything else. EXTBIO DE=0402h returns
; A = number of mapper slots, 0 if none.
            ld      de,MAPR_S
            ld      c,_STROUT
            call    BDOS
            ld      de,0402h
            xor     a
            call    EXTBIO
            call    PRINT_HEX8
            ld      de,CRLF_S
            ld      c,_STROUT
            call    BDOS

            ld      de,DETAIL_S
            ld      c,_STROUT
            call    BDOS

            ld      a,(0F344h)              ; RAMAD1: slot of page-1 RAM
            call    PRINT_HEX8
            ld      de,SP_S
            ld      c,_STROUT
            call    BDOS

            ld      hl,ID_TCP               ; re-arm ARG with "TCP/IP"
            ld      de,ARG
.c2:
            ld      a,(hl)
            ld      (de),a
            inc     hl
            inc     de
            or      a
            jr      nz,.c2

            ld      de,2222h
            xor     a
            ld      b,0
            call    EXTBIO
            ld      a,b
            or      a
            jr      z,.nodetail

            ld      de,2222h
            ld      a,1                     ; first implementation
            call    EXTBIO                  ; A=slot, B=segment, HL=entry
            push    hl
            push    bc
            call    PRINT_HEX8              ; slot
            ld      de,SP_S
            ld      c,_STROUT
            call    BDOS
            pop     bc
            ld      a,b
            call    PRINT_HEX8              ; segment
            ld      de,SP_S
            ld      c,_STROUT
            call    BDOS
            pop     hl
            ld      a,h
            call    PRINT_HEX8              ; entry high byte
            ld      a,l
            call    PRINT_HEX8
.nodetail:
            ld      de,CRLF_S
            ld      c,_STROUT
            call    BDOS

            ld      c,_TERM0
            jp      BDOS

; --- HL = zero-terminated identifier, DE = label to print ------------------
COUNT_AND_PRINT:
            push    hl
            ld      c,_STROUT
            call    BDOS                    ; print the label
            pop     hl

            ld      de,ARG                  ; copy identifier to ARG
.copy:
            ld      a,(hl)
            ld      (de),a
            inc     hl
            inc     de
            or      a
            jr      nz,.copy

            ld      de,2222h
            xor     a                       ; A=0: count implementations
            ld      b,0
            call    EXTBIO
            ld      a,b
            call    PRINT_HEX8
            ld      de,CRLF_S
            ld      c,_STROUT
            jp      BDOS

PRINT_HEX8:
            push    af
            rrca
            rrca
            rrca
            rrca
            call    .nib
            pop     af
.nib:
            and     0Fh
            add     a,"0"
            cp      "9"+1
            jr      c,.emit
            add     a,7
.emit:
            ld      e,a
            ld      c,02h
            push    hl
            push    bc
            call    BDOS
            pop     bc
            pop     hl
            ret

; The identifiers must match exactly what each specification defines - the
; comparison is case-insensitive but the string is not otherwise interpreted.
ID_ETH:     db      "ETHERNET",0
ID_TCP:     db      "TCP/IP",0

BANNER_S:   db      "UCOUNT - UNAPI implementations",13,10,13,10,"$"
ETH_S:      db      "ETHERNET: $"
TCP_S:      db      "TCP/IP:   $"
MAPR_S:     db      "mapper slots: $"
DETAIL_S:   db      "RAMAD1 slot seg entry",13,10,"$"
SP_S:       db      " $"
CRLF_S:     db      13,10,"$"
