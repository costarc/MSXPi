;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 1.0                                                             |
;|                                                                           |
;| Copyright (c) 2015-2020 Ronivon Candido Costa (ronivon@outlook.com)       |
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
; 1.0    : For MSXPi interface with /buswait support

; Start of command - You may not need to change this
        org     $0100
        ld      bc,COMMAND_END - COMMAND
        ld      hl,COMMAND
        call    DOSSENDPICMD
        call    PIREADBYTE    ; read return code
        cp      RC_WAIT
        call    z,CHKPIRDY
        CALL    READDATASIZE
        CALL    PTEST
        RET

PTEST:
       push    bc
       ld      hl,txt_testsend
       call    PRINT
       call    DBGBC
       ld      hl,txt_bytes
       call    PRINT
       ld      de,0
LOOP:
       ld      a,e
       call    PIWRITEBYTE
       ld      a,d
       call    PIWRITEBYTE
       inc     de
       dec     bc
       ld      a,b
       or      c
       jr      nz,LOOP

       call    READDATASIZE
       ld      hl,txt_senderr
       call    PRINT
       call    DBGBC
       call    PRINTNLINE

PTEST_RECV:
       pop     bc
       ld      hl,txt_testrecv
       call    PRINT
       call    DBGBC
       ld      hl,txt_bytes
       call    PRINT
       ld      hl,0
       ld      de,0
LOOP_RECV:
       call    PIREADBYTE
       cp      l
       jr      z,LOOP1
       inc     de
LOOP1:
       call    PIREADBYTE
       cp      h
       jr      z,LOOP2
       inc     de
LOOP2:
       inc     hl
       dec     bc
       ld      a,b
       or      c
       jr      nz,LOOP_RECV
       
       ld      hl,txt_recverr
       call    PRINT
       call    DBGDE
       call    PRINTNLINE
       ret

waitrpi:
       push   bc
       ld     b,0
waitpi2:
       djnz   waitpi2
       pop    bc
       ret

txt_senderr: DB      "Errors sending:$"
txt_recverr: DB      "Errors receiving:$"
txt_testsend: DB "Sending $"
txt_bytes: DB " Bytes",13,10,"$"
txt_testrecv: DB "Receiving $"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

COMMAND:     DB      "ptest"
COMMAND_SPC: DB " " ; Do not remove this space, do not add code or data after this buffer.
COMMAND_END: EQU $