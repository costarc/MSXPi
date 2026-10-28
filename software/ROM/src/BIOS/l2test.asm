; MSXPi Interface
; Version 1.7.0
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
; L2TEST.BIN - LINK2 test program for BASIC (documents/LINK2-TEST-PLAN.md, T4 and T6).
;
; CALL MSXPI cannot send bulk data to the Pi, so this does what it cannot: a
; LINK_SEND of N bytes of a known pattern, with OTIR when the buffer allows, checked by
; the server's `l2test sink` command.  Nothing is needed on a floppy: CALL MSXPI loads
; it into RAM (the BIN is the raw program, and CALL MSXPI("2,C000,..") puts a 3 byte
; header in front, so it is assembled to run from C003).
;
;   CALL MSXPI("2,C000,l2test bin")
;   DEFUSR=&HC003
;   POKE &HE000,...                 the parameters below (the harness does it)
;   A=USR(0)
;
; Parameters (all RAM at E000, outside the program):
;   E000  command, zero terminated   e.g. "l2test sink 512 7"
;   E040  N, bytes to send (word)
;   E042  seed (byte): byte i of the pattern is i*13 + (i>>8)*7 + seed
;   E044  buffer address (word): a buffer at 8000h or above may burst (OTIR)
;   E046  repetitions (word)
; Prints, in hex:  L2T OK=xxxx F=xxxx T=xxxx  (short: the BASIC screen may be 29 columns)
; OK counts the repetitions whose reply began with "L2TEST OK"; F the failed ones; T is the JIFFY
; (1/50 or 1/60 s) the whole loop took, the buffer filling excluded.

    DEFINE MSXPI_LINK2
    DEFINE MSXPI_RAM_STASH

P_CMD:      EQU $E000
P_LEN:      EQU $E040
P_SEED:     EQU $E042
P_BUF:      EQU $E044
P_REPS:     EQU $E046
R_OK:       EQU $E050
R_FAIL:     EQU $E052
R_REPLY:    EQU $E100      ; 256 bytes
JIFFY:      EQU $FC9E

    ORG $C003

L2T_MAIN:
    ld   hl,0
    ld   (R_OK),hl
    ld   (R_FAIL),hl
    ld   hl,(P_BUF)
    ld   (L2T_PTR),hl
    ld   de,(P_LEN)
    ld   a,(P_SEED)
    ld   b,a                    ; B = the pattern byte for i = 0
    xor  a
    ld   (L2T_I),a
L2T_FILL:
    ld   a,d
    or   e
    jr   z,L2T_FILLED
    ; value = i*13 + (i>>8)*7 + seed, kept in B incrementally: B += 13 per byte,
    ; plus 7 for every 256 bytes (when the low byte of i wraps)
    ld   a,b
    ld   hl,(L2T_PTR)
    ld   (hl),a
    inc  hl
    ld   (L2T_PTR),hl
    ld   a,b
    add  a,13
    ld   b,a
    ld   a,(L2T_I)
    inc  a
    ld   (L2T_I),a
    jr   nz,L2T_NOWRAP
    ld   a,b
    add  a,7
    ld   b,a
L2T_NOWRAP:
    dec  de
    jr   L2T_FILL
L2T_FILLED:
    ld   hl,(JIFFY)
    ld   (L2T_T0),hl
L2T_REP:
    ld   hl,(P_REPS)
    ld   a,h
    or   l
    jr   z,L2T_DONE
    dec  hl
    ld   (P_REPS),hl
    ld   de,P_CMD
    call LINK_COMMAND
    jr   c,L2T_FAILED
    ld   de,(P_BUF)
    ld   bc,(P_LEN)
    call LINK_SEND
    sbc  a,a                    ; FFh when the send failed
    ld   (L2T_SENDF),a
    ; The reply is read either way: the server's sink answers a failed receive
    ; too, and an unread answer would meet the next repetition's command.
    ld   de,R_REPLY
    ld   bc,128
    ld   a,2
    call LINK_RECV
    jr   c,L2T_FAILED
    ld   a,(L2T_SENDF)
    or   a
    jr   nz,L2T_FAILED
    ld   hl,R_REPLY
    ld   de,L2T_OKTEXT
    ld   b,9
L2T_CMP:
    ld   a,(de)
    cp   (hl)
    jr   nz,L2T_FAILED
    inc  hl
    inc  de
    djnz L2T_CMP
    ld   hl,(R_OK)
    inc  hl
    ld   (R_OK),hl
    jr   L2T_REP
L2T_FAILED:
    ld   hl,(R_FAIL)
    inc  hl
    ld   (R_FAIL),hl
    jr   L2T_REP
L2T_DONE:
    ld   hl,(JIFFY)
    ld   de,(L2T_T0)
    or   a
    sbc  hl,de
    ld   (L2T_T0),hl
    ld   hl,L2T_MSG1
    call PRINT
    ld   hl,(R_OK)
    call L2T_HEX16
    ld   hl,L2T_MSG2
    call PRINT
    ld   hl,(R_FAIL)
    call L2T_HEX16
    ld   hl,L2T_MSG3
    call PRINT
    ld   hl,(L2T_T0)
    call L2T_HEX16
    ld   a,13
    call PUTCHAR
    ld   a,10
    call PUTCHAR
    ret

L2T_HEX16:
    ld   a,h
    push hl
    call PRINTNUMBER
    pop  hl
    ld   a,l
    jp   PRINTNUMBER

L2T_OKTEXT: DB "L2TEST OK"
L2T_MSG1:   DB "L2T OK=",0
L2T_MSG2:   DB " F=",0
L2T_MSG3:   DB " T=",0
L2T_PTR:    DW 0
L2T_I:      DB 0
L2T_SENDF:  DB 0
L2T_T0:     DW 0

    INCLUDE "include.asm"
    INCLUDE "msxpi_bios.asm"
    INCLUDE "putchar_msxdos.asm"
