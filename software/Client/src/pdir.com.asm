;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 1.4                                                             |
;|                                                                           |
;| Copyright (c) 2015-2025 Ronivon Costa (ronivon@outlook.com)               |
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
DSKBLOCKSIZE:   EQU 1

        org     $0100
        ld      de,command
        call    SendCommandToMSXPi
        jr      c, PRINTPIERR
		xor		a 
		ld		bc,MAXBUFSIZE
		ld		de,buf
		call    PRINTPISTDOUT
		ret
PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

command:    DB      "dir /Windows/System32",0
PICOMMERR:  db      "Communication error",0

INCLUDE "include.asm"
INCLUDE "putchar-clients.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "debug.asm"

buf:    equ     $
