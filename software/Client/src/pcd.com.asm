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
        
; Sending Command and Parameters to RPi
        ld      de,command
        call    SENDCOMMAND
        jr      c, PRINTPIERR
        ld      hl,buf
        ld      bc,BLKSIZE
        call    CLEARBUF
        call    SENDPARMS
        jr      c, PRINTPIERR
MAINPROG:
        call    READ1BLOCK
        jr      c, PRINTPIERR
        ld      hl,buf
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        xor     a                   ; header in 1st block
MAINPROG1:
        push    bc
        ld      bc,BLKSIZE
        call    PRINTPISTDOUT
        pop     hl
        ld      bc,BLKSIZE
        or      a
        sbc     hl,bc
        ret     c
        ld      b,h
        ld      c,l
        push    bc
        call    READ1BLOCK
        pop     bc
        jr      c,PRINTPIERR
        ld      a,1                 ; no header in next blocks
        ld      hl,buf
        jr      MAINPROG1
        
READ1BLOCK:
        ld      hl,buf
        ld      bc,BLKSIZE
        call    CLEARBUF
        ld      de,buf
        ld      bc,BLKSIZE
        call    RECVDATA
        ret
        
PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

PICOMMERR:  DB      "Communication Error",13,10,0

command: db "pcd     ",0
INCLUDE "include.asm"
INCLUDE "putchar-clients.asm"
INCLUDE "msxpi_bios.asm"
buf:    equ     $
        ds      BLKSIZE
        db      0
