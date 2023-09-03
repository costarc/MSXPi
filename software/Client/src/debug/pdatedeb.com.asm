;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 1.1                                                             |
;|                                                                           |
;| Copyright (c) 2015-2023 Ronivon Candido Costa (ronivon@outlook.com)       |
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
; 0.2   : Structural changes to support a simplified transfer protocol with error detection
; 0.1    : Initial version.
;
; This is a generic template for MSX-DOS command to interact with MSXPi
; This command must have a equivalent function in the msxpi-server.py program
; The function name must be the same defined in the "command" string in this program
;
; debugging pdate - will skip the code that gets the date from RPi
; Will inject a known date value in the memory - as returned by RPI
; Then will proceed to update the MSX with the date and assess results
; This date was colleted from RPi when pdate as executed:
; Date: 2023-09-02 18:43:27.713594 bytearray(b'\xe7\x07\t\x02\x12+\x1b\x00')
;

; https://map.grauw.nl/resources/dos2_functioncalls.php#_SDATE
        org     $0100

        ld      de,buf
        ld      bc,CMDSIZE
        call    CLEARBUF
        
        call    SETCLOCK
        ld      hl,PIOK
        call    PRINT
        call    PRINTNLINE
        ret
  
SETCLOCK:
        LD      IX,buf + 3
        LD      A,$e7
        LD      L,A
        LD      A,$07
        LD      H,A
        LD      A,$02
        LD      D,A
        LD      A,$12
        LD      E,A
        LD      C,$2B
        PUSH    IX
        CALL    5
        POP     IX

; set time
        LD      A,0
        LD      H,A
        LD      A,0
        LD      L,A
        LD      A,0
        LD      D,A
        LD      A,0
        LD      E,A
        LD      C,$2D
        CALL    BDOS
        RET
               
        
PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT
        
PICOMMERR:  DB      "Communication Error",13,10,0

command: db "pdate",0

PIOK: db "Pi:Ok",0
INCLUDE "include.asm"
INCLUDE "putchar-clients.asm"
INCLUDE "msxpi_bios.asm"
buf:    equ     $
        ds      BLKSIZE
        db      0

