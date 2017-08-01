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
; 0.1    : Initial version.

TEXTTERMINATOR: EQU '$'

        ORG     $0100
; Using the existing RUN command to shutdown Pi
; This is the lazy approach, but it won't require any extra
; code implementation on the server side.

; move shutdown command to DOS command line buffer
        LD      HL,SHUTDMD
        LD      DE,$80
        LD      BC,17
        LDIR

; Send RUN command to Pi, along with buffer in DOS command line
        LD      BC,3
        LD      DE,DIRCMD
        CALL    DOSSENDPICMD
        JR      C,PRINTPIERR
        JP      0

PRINTPIERR:
        LD      HL,PICOMMERR
        CALL    PRINT
        JP      0

DIRCMD: DB      "RUN"
SHUTDMD:DB      17," shutdown -h now",$0D
PICOMMERR:
        DB      "Communication Error",13,10,"$"


INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

