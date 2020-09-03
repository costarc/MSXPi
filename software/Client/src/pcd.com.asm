;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.9.0                                                           |
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
; 0.1    : Initial version.
; 0.9.0  : Changes to supoprt new transfer logic

        ORG     $0100

        LD      BC,3
        LD      DE,COMMAND
        CALL    DOSSENDPICMD

WAIT_LOOP:
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_WAIT
        JR      NZ,WAIT_RELEASED
        CALL    CHKPIRDY
        JR      WAIT_LOOP

WAIT_RELEASED:

        CP      RC_FAILED
        JP      Z,PRINTPISTDOUT
        CP      RC_SUCCESS
        JP      Z,MAINPROGRAM

PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

MAINPROGRAM:
        JP      PRINTPISTDOUT

PICOMMERR:
    DB      "Communication Error",13,10,"$"

COMMAND: DB      "PCD"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"




