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


