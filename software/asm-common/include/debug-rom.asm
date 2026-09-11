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

ROM_DBGBC:
        DI
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,B
        CALL    ROM_PRINTNUMBER
        LD      A,C
        CALL    ROM_PRINTNUMBER
        LD      A,' '
        CALL    ROM_PUTCHAR
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        EI
        RET

ROM_DBGDE:
        DI
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,D
        CALL    ROM_PRINTNUMBER
        LD      A,E
        CALL    ROM_PRINTNUMBER
        LD      A,' '
        CALL    ROM_PUTCHAR
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        EI
        RET

ROM_DBGHL:
        DI
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      A,H
        CALL    ROM_PRINTNUMBER
        LD      A,L
        CALL    ROM_PRINTNUMBER
        LD      A,'-'
        CALL    ROM_PUTCHAR
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        EI
        RET

ROM_DBGA:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    ROM_PRINTNUMBER    ; A still holds the caller's value here
        LD      A,'#'
        CALL    ROM_PUTCHAR
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

;-----------------------
; ROM_PRINTNUMBER          |
;-----------------------
ROM_PRINTNUMBER:
        push    de
        ld      e,a
        push    de
        AND     0F0H
        rra
        rra
        rra
        rra
        call    ROM_PRINTDIGIT
        pop     de
        ld      a,e
        AND     0FH
        call    ROM_PRINTDIGIT
        pop     de
        ret

ROM_PRINTDIGIT:
        cp      0AH
        jr      c,ROM_PRINTNUMERIC
ROM_PRINTALFA:
        ld      d,37H
        jr      ROM_PRINTNUM1

ROM_PRINTNUMERIC:
        ld      d,30H
ROM_PRINTNUM1:
        add     a,d
        call    ROM_PUTCHAR
        ret
        
ROM_PUTCHAR:
        push    bc
        push    de
        push    hl
        ld      e,a
        ld      c,2
        call    $A2             ; matches putchar_msxdos.asm's PUTCHAR -
                                ; the standard "call 5" BDOS entry isn't
                                ; safe to use from a ROM-resident routine
                                ; invoked mid-CALL from BASIC
        pop     hl
        pop     de
        pop     bc
        ret


