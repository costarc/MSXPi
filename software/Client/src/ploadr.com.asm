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
; 0.1    : Initial version.
; 0.9    : Rewritten to support new block download logic
; 1.1    : Ported to protocol v1.1

        ORG     $0100

; Sending Command and Parameters to RPi
        ld      de,command
        call    SENDCOMMAND
        jr      c, PRINTPIERR
        ld      de,buf
        ld      bc,BLKSIZE
        call    CLEARBUF
        call    SENDPARMS
        jr      c, PRINTPIERR
        ld      de,buf
MAINPROG:
        ld      bc,BLKSIZE
        call    CLEARBUF
        push    de
        call    RECVDATA
        pop     hl
        jr      c, PRINTPIERR
        ld      a,(hl)          ; return code
        inc     hl
        ld      c,(hl)          ; lsb of data size
        inc     hl
        ld      b,(hl)          ; msb of data size
        inc     hl
        ld      d,h
        ld      e,l
        cp      RC_FAILED
        jp      z,PRINTPISTDOUT            ; if RPi sent Error, print message to screen
        cp      RC_TERMINATE
        jp      z,PRINTPISTDOUT
        CALL    LOADROM
        PUSH    HL
        LD      HL,0
        LD      A,($FCC1)
        CALL    ENASLT
        POP     HL
        JP      (HL)

;-----------------------
; LOADROM              |
;-----------------------
LOADROM:
; Will load the ROM directly on the destiantion page in $4000
; Might be slower, but that is what we have so far...
;Get number of bytes to transfer
        LD      A,' '
        CALL    PUTCHAR
        LD      A,10
        LD      (buf),a             ; counter for cosmetic feature
        LD      BC,(buf + 1)        ; Read the number of bytes to transfer
        LD      DE,romaddr - 3      ; Address to store the ROM
LOADROML:
        LD      A,(buf)
        OR      A
        JR      Z,LOADROM1
        DEC     A
        LD      (buf),a
        CP      9
        JR      Z,LOADROM2
        LD      A,'.'
        OUT     ($98),A
        JR      LOADROM2
LOADROM1:
        LD      A,'.'
        CALL    PUTCHAR
        LD      A,10
        LD      (buf),A
LOADROM2:
        LD      A,E
        LD      (currptx),A
        LD      A,D
        LD      (currptx + 1),A
        LD      BC,BULKBLKSIZE     ; block size to transfer
        CALL    RECVDATA
        RET     C
        CALL    MOVEROM
        LD      A,(currptx)         ; curret RC from RPi
        CP      RC_READY
        JR      Z,LOADROML          ; More data ready to transfer
        LD      HL,($4002)    ;ROM exec address
        OR      A             ;Reset C flag
        RET
        
; Move each block to its dinal position
; Needed because each block comes with a 3 bytes header - need to strip it
; Return C reseted, and A = filetype
MOVEROM:
        LD      HL,(currptx)
        LD      D,H
        LD      E,L
        INC     HL
        INC     HL
        INC     HL
        LD      BC,BULKBLKSIZE - 3
        LDIR
        RET

COMMAND:
        DB      "PLOADR"

PICOMMERR:
        DB      "Communication Error",13,10,"$"

LOADPROGERRMSG:
        DB      "Error loading file",13,10,"$"

LOADPROGRESS:
        DB      "Loading game...$"

INCLUDE "include.asm"
INCLUDE "putchar-clients.asm"
INCLUDE "msxpi_bios.asm"
currptx: DB     0,0
buf:    equ     $
romaddr: equ     $4000




