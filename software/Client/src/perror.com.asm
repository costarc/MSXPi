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
        LD      HL,PICMD
        LD      DE,$80
        LD      BC,27
        LDIR

; Send RUN command to Pi, along with buffer in DOS command line
        LD      BC,3
        LD      DE,MYCMD
        CALL    DOSSENDPICMD
        JR      C,PRINTPIERR

        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_WAIT
        SCF
        RET     NZ
WAITLOOP:
        CALL    CHECK_ESC
        JR      C,PRINTPIERR
        CALL    CHKPIRDY
        JR      C,WAITLOOP
; Loop waiting download on Pi
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_FAILED
        JR      Z,EXITSTDOUT
        CP      RC_SUCCESS

EXITSTDOUT:
        CALL    PRINTPISTDOUT
        RET

PRINTPIERR:
        LD      HL,PICOMMERR
        CALL    PRINT
        JP      0

CHECK_ESC:
	ld	b,7
	in	a,(0AAh)
	and	11110000b
	or	b
	out	(0AAh),a
	in	a,(0A9h)	
	bit	2,a
	jr	nz,CHECK_ESC_END
	scf
CHECK_ESC_END:
	ret

MYCMD:  DB      "RUN"
PICMD:  DB      26," cat /tmp/msxpi_error.log",$0D

PICOMMERR:
        DB      "Communication Error",13,10,"$"


INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

