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

        org     $0100
        
        ld      de,command  
        call    SENDCOMMAND
        jr      c, PRINTPIERR 
        call    CLEARBUF
        ld      de,buf
        ld      bc,BLKSIZE
        call    RECVDATA
        jr      c, PRINTPIERR 
        call    SETCLOCK
        ret
        
PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

SETCLOCK:
        LD      IX,buf
        LD      A,(IX + 0)
        LD      L,A
        LD      A,(IX + 1)
        LD      H,A
        LD      A,(IX + 2)
        LD      D,A
        LD      A,(IX + 3)
        LD      E,A
        LD      C,$2B
        PUSH    IX
        CALL    5
        POP     IX

; set time
        LD      A,(IX + 4)
        LD      H,A
        LD      A,(IX + 5)
        LD      L,A
        LD      A,(IX + 6)
        LD      D,A
        LD      A,(IX + 7)
        LD      E,A
        LD      C,$2D
        CALL    BDOS
        RET
               

command: db "pdate   ",0
PICOMMERR:  DB      "Communication Error",13,10,0
        
INCLUDE "include.asm"
INCLUDE "putchar-clients.asm"
INCLUDE "msxpi_bios.asm"
buf:    equ     $
        ds      BLKSIZE
        db      0

