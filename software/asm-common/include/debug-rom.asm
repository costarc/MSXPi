;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.8                                                             |
;|                                                                           |
;| Copyright (c) 2015-2016 Ronivon Candido Costa (ronivon@outlook.com)       |
;|                                                                           |
;| All rights reserved                                                       |
;|                                                                           |
;| Redistribution and use in source and compiled forms, with or without      |
;| modification, are permitted under GPL license.                            |
;|                                                                           |
;|===========================================================================|
;|                                                                           |
;| This file is part of MSXPi Interface project.                             |
;|                                                                           |
;| MSX PI Interface is free software: you can redistribute it and/or modify  |
;| it under the terms of the GNU General Public License as published by      |
;| the Free Software Foundation, either version 3 of the License, or         |
;| (at your option) any later version.                                       |
;|                                                                           |
;| MSX PI Interface is distributed in the hope that it will be useful,       |
;| but WITHOUT ANY WARRANTY; without even the implied warranty of            |
;| MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             |
;| GNU General Public License for more details.                              |
;|                                                                           |
;| You should have received a copy of the GNU General Public License         |
;| along with MSX PI Interface.  If not, see <http://www.gnu.org/licenses/>. |
;|===========================================================================|
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
        
BDOS:   EQU     5
ROM_PUTCHAR:
        push    bc
        push    de
        push    hl
        ld      e,a
        ld      c,2
        call    BDOS
        pop     hl
        pop     de
        pop     bc
        ret


