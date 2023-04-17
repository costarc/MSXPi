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

; Print hw interface version (CPLD logic and pcb)
        LD      HL,HWVER
        CALL    PRINT
        IN      A,(CONTROL_PORT2)
        CALL    DESCHWVER
        call    PRINTNLINE

; Sending Command and Parameters to RPi
        ld      de,command
        call    SENDCOMMAND
        jr      c, PRINTPIERR
        ld      de,buf
MAINPROG:
        ld      bc,BLKSIZE
        call    CLEARBUF
        push    de
        call    RECVDATA
        pop     de
        jr      c, PRINTPIERR
        inc     de
        inc     de
        inc     de
        call    PRINTPISTDOUT
        ld      de,buf
        ld      a,(de)
        cp      RC_READY
        jr      z,MAINPROG
        call    PRINTNLINE
        ret
        
PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

PICOMMERR:  DB      "Communication Error",13,10,0
        
DESCHWVER:
        ld      hl,iftable
DESCHWVER0:
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        or      a
        jr      z,PRINTIFVER
        dec     a
        jr      DESCHWVER0

PRINTIFVER:
        ld      h,d
        ld      l,e
        call    PRINT
        ret

iftable:
        dw      ifdummy
        dw      ifv1
        dw      ifv2
        dw      ifv3
        dw      ifv4
        dw      ifv5
        dw      ifv6
        dw      ifv7
        dw      ifv8
        dw      ifv9
        dw      ifvA
        dw      ifukn

ifv1:   DB      "(0001) Wired up prototype, EPM3064ALC-44",0
ifv2:   DB      "(0010) Semi-wired up prototype, EPROM 27C256, EPM3064ATC-44",0
ifv3:   DB      "(0011) Limited 10-samples PCB, EPROM 27C256, EPM3064ALC-44",0
ifv4:   DB      "(0100) Limited 1 sample PCB, EPROM 27C256, EPM3064ALC-44, 4 bits mode",0
ifv5:   DB      "(0101) Limited 10 samples PCB Rev.3, EPROM 27C256, EPM3064ALC-44",0
ifv6:   DB      "(0110) Wired up prototype, EPROM 27C256, EPM7128SLC-84",0
ifv7:   DB      "(0111) General Release V0.7 Rev.4, EPROM 27C256, EPM3064ALC-44",0
ifv8:   DB      "(1000) Limited 10 samples, Big v0.8.1 Rev.0, EPM7128SLC-84",0
ifv9:   DB      "(1001) General Release V1.0 Rev 0, EPROM 27C256, EPM3064ALC-44",0
ifvA:   DB      "(1010) General Release V1.1 Rev 0, EEPROM AT28C256, EPM3064ALC-44",0
ifukn:  DB      "Could not identify. Possibly an earlier version with old CPLD logic",0
ifdummy: DB      "MSXPi not detected - may need firmware update",0

HWVER:  DB      "Interface version:"
        DB      0

SRVVER: DB      "msxpi-server version:"
        DB      0

ROMCER: DB      "MSXPi ROM version:"
        DB      0

PVERHWNFSTR:
        DB      "MSXPi Interface not found",0

command: db "pver",0

INCLUDE "include.asm"
INCLUDE "putchar-clients.asm"
INCLUDE "msxpi_bios.asm"
buf:    equ     $
        ds      BLKSIZE
        db      0
