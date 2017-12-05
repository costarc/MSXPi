;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.8.1                                                             |
;|                                                                           |
;| Copyright (c) 2015-2017 Ronivon Candido Costa (ronivon@outlook.com)       |
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

        ORG     $0100

        LD      BC,5
        LD      DE,MYCMD
        CALL    DOSSENDPICMD
        JR      C,PRINTPIERR

        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_WAIT
        JR      NZ,PRINTPIERR

WAITLOOP:
        CALL    CHECK_ESC
        JR      C,PRINTPIERR
        CALL    CHKPIRDY
        JR      C,WAITLOOP

; Loop waiting download on Pi
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE

        CP      RC_FAILED
        JP      Z,PRINTPISTDOUT

        CP      RC_SUCCESS
        JP      Z,PRINTPISTDOUT

        CP      RC_SUCCNOSTD
        RET     Z

        CP      RC_FAILNOSTD
        RET     Z

        JR      WAITLOOP

PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

PICOMMERR:
    DB      "Communication Error",13,10,"$"

MYCMD: DB      "PPLAY"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

