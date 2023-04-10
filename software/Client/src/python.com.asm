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
        
        ld      hl,msg_pycred
        call    PRINT
        
pyInterp:
        call    PRINTNLINE
        ld      de,cmdbuf
        call    readPyCmd
        call    PRINTNLINE
        ld      de,cmdbuf
        call    sendPyCommand
        jr      c,PRINTPIERR
        jr      pyInterp
        
readPyCmd:
        push    de
        LD      C,01
        call    BDOS
        pop     de
        cp      13
        jr      z,exitPyCmd
        cp      10
        jr      z,exitPyCmd
        ld      (de),a
        inc     de
        jr      readPyCmd
exitPyCmd:
        xor     a
        ld      (de),a
        ret

sendPyCommand:
        push    de
        ld      de,command
        call    SENDCOMMAND
        ret     c
        pop     de
        ld      bc,BLKSIZE
        call    SENDDATA
        ret     c
        ld      de,buf
        ld      bc,BLKSIZE
        call    RECVDATA
        ld      hl,buf + 3
        call    PRINT
        ret
        
PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT
        
PICOMMERR:  DB      "Communication Error",13,10,0

; Command maximun lenght is 8 characters. 
; Always terminate the command with a trailing zero
command: db "py",0

; Comand line parameters can be 255 characters maximum
; Always terminate the string with a trailing zero

BuildId: DB "20230410.000"
msg_success: db "Checksum match",13,10,0
msg_error: db "Checksum did not match",13,10,0
msg_cmd: db "Sending command...",0
msg_parms: db "Sending parameters... ",0
msg_recv: db "Now reading MSXPi response... ",0
msg_pycred: db "MSXPi Python v0.1",13,10,0
; Core MSXPi APIs / BIOS routines.
INCLUDE "include.asm"
INCLUDE "putchar-clients.asm"
INCLUDE "msxpi_bios.asm"

; All MSX-DOS programs must have this buf defined.
; It's used by the MSXPi APIs in several commands.

cmdbuf: equ     $
        ds      BLKSIZE
        db      0,0,0,0
buf:    equ     $


