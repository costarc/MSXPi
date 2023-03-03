;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.8.1                                                             |
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

        org     $0100
        
        ld      hl,msg_title
        call    PRINT
        ld      hl,command  
        call    SETBUF
        ld      hl,msg_transf
        call    PRINT
        
msxpicmd:
        ld      de,buf
        call    SENDDATA
        call    print_msgs          ; print informative message based on flag C
        
        ld      hl,msg_recv
        call    PRINT
        call    CLEARBUF
        ld      de,buf
        call    RECVDATA
        push    af
        call    print_msgs          ; print informative message based on flag C
        pop     af
        ld      hl,buf
        call   PRINT            ; if received data correctly, display in screen
        ret
        
print_msgs:
        ld      hl,msg_error
        jp      c,PRINT
        ld      hl,msg_success
        call    PRINT
        ret
       
msg_success: db "Checksum match",13,10,"$"
msg_error: db "Checksum did not match",13,10,"$"
command: db "MSXPi Text Transmission test - testing 1,2,3",0
msg_transf: db "Starting transfer...",13,10,"$"
msg_title: db "PTEST.COM starting",13,10,"$"
msg_recv: db "Now reading MSXPi response...",13,10,"$"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"



