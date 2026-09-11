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
;
; File history :
; 0.1    : Initial version.

TEXTTERMINATOR: EQU '$'

        ORG     $0100
        LD      BC,13
        LD      DE,DBGCMD
        CALL    SENDDATABLOCK
        LD      A,ENDTRANSFER
        CALL    PIEXCHANGEBYTE
        CP      ENDTRANSFER
        JR      NZ,PRINTPIERR
        JP      0

PRINTPIERR:
        LD      HL,PICOMMERR
        CALL    PRINT
        JP      0

DBGCMD: DB      "DEBUG COMMAND",0

PICOMMERR:
        DB      "Communication Error",13,10,"$"

;-----------------------
; SENDIFCMD            |
;-----------------------
SENDIFCMD:
            out     (CONTROL_PORT),a       ; Send data, or command
            ret

;-----------------------
; CHKPIRDY             |
;-----------------------
CHKPIRDY:
            push    bc
            ld      bc,0ffffh
CHKPIRDY0:
            in      a,(CONTROL_PORT); verify spirdy register on the msxinterface
            and     $01
            jr      z,CHKPIRDYOK    ; rdy signal is zero, pi app fsm is ready
                                    ; for next command/byte
            dec     bc              ; pi not ready, wait a little bit
            ld      a,b
            or      c
            jr      nz,CHKPIRDY0
CHKPIRDYNOTOK:
            scf
CHKPIRDYOK:
            pop     bc
            ret

;-----------------------
; PIREADBYTE           |
;-----------------------
PIREADBYTE:
            call    CHKPIRDY
            jr      c,PIREADBYTE1
            xor     a                   ; do not use xor to preserve c flag state
            out     (CONTROL_PORT),a    ; send read command to the interface
            call    CHKPIRDY            ;wait interface transfer data to pi and
                                        ; pi app processing
                                        ; no ret c is required here, because in a,(7) does not reset c flag
PIREADBYTE1:
            in      a,(DATA_PORT)       ; read byte
            ret                         ; return in a the byte received

;-----------------------
; PIWRITEBYTE          |
;-----------------------
PIWRITEBYTE:
            push    af
            call    CHKPIRDY
            pop     af
            out     (DATA_PORT),a       ; send data, or command
            ret

;-----------------------
; PIEXCHANGEBYTE       |
;-----------------------
PIEXCHANGEBYTE:
            call    PIWRITEBYTE
            call    CHKPIRDY
            in      a,(DATA_PORT)       ; read byte
            ret

            in      a,(CONTROL_PORT)
            sla     a
            or      a
            jr      z,PIEXCHANGEBYTE
            out     (DATA_PORT),a
PIEXCHANGEBYTE1:
            in      a,(CONTROL_PORT)
            sla     a
            or      a
            jr      z,PIEXCHANGEBYTE1
            in      a,(DATA_PORT)
            ret



INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxdos_stdio.asm"

