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
        
        ld      hl,msg_cmd
        call    PRINT
        ld      de,command  
        call    SENDCOMMAND
        call    print_msgs          ; print informative message based on flag C
        
        ld      hl,msg_parms
        call    PRINT

        ; send CLI parameters to MSXPi
        call    SENDPARMS
        call    print_msgs          ; print informative message based on flag C
        
        ld      hl,msg_recv
        call    PRINT
        
MAINPROG:
        call    CLEARBUF
        ld      de,buf
        ld      bc,BLKSIZE
        call    RECVDATA
        call    print_msgs          ; print informative message based on flag C

        ld      hl,buf
        call   PRINT            ; if received data correctly, display in screen
        ld      hl,buf
        ld      de,BLKSIZE
        add hl,de
        ld      a,(hl)
        or      a
        jr      nz,MAINPROG
        ret
        
print_msgs:
        ld      hl,msg_error
        jp      c,PRINT
        ld      hl,msg_success
        call    PRINT
        ret

; Command maximu lenght is 8 characters. 
; Always terminate the command with a trailing zero
command: db "template",0

; Comand line parameters can be 255 characters maximum
; Always terminate the string with a trailing zero
       
msg_success: db "Checksum match",13,10,0
msg_error: db "Checksum did not match",13,10,0
msg_cmd: db "Sending command...",13,10,0
msg_parms: db "Sending parameters: ",0
msg_recv: db "Now reading MSXPi response...",13,10,0

; Core MSXPi APIs / BIOS routines.
INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"

; All MSX-DOS programs must have this buf defined.
; It's used by the MSXPi APIs in several commands.

buf:    equ     $
        ds      BLKSIZE
        db      0


