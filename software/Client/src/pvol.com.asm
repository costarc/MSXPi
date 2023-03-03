;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.9.0                                                           |
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
; 0.9.0  : Updates code to suport v0.9 logic

         ORG     $0100

        LD      HL,COMMAND
        CALL    DOSSENDPICMD

        JR      NC,MAINPROGRAM

PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

MAINPROGRAM:
        LD      DE,buf
        CALL    RECVDATA
        LD      HL,buf
        call      PRINTPISTDOUT
        dec     hl                              ;check last byte in buffer. if zero, no more data
        ld      a,(hl)
        or      a
        jr      nz,MAINPROGRAM
        ret


PICOMMERR:
        DB      "Communication Error",13,10,"$"

COMMAND: DB      "PRUN amixer set PCM -- "

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"


