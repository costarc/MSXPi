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
; 0.1    : initial version
DBGA:
        DI
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    PRINTNUMBER
        LD      A,' '
        CALL    PUTCHAR
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        EI
        RET
DBGBC:
        DI
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,B
        CALL    PRINTNUMBER
        LD      A,C
        CALL    PRINTNUMBER
        LD      A,' '
        CALL    PUTCHAR
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        EI
        RET

DBGDE:
        DI
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,D
        CALL    PRINTNUMBER
        LD      A,E
        CALL    PRINTNUMBER
        LD      A,' '
        CALL    PUTCHAR
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        EI
        RET

DBGHL:
        DI
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,H
        CALL    PRINTNUMBER
        LD      A,L
        CALL    PRINTNUMBER
        LD      A,' '
        CALL    PUTCHAR
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        EI
        RET


