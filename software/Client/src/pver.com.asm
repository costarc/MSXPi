;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.9.                                                            |
;|                                                                           |
;| Copyright (c) 2015-2016 Ronivon Candido Costa (ronivon@outlook.com)       |
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
; 0.9.0  : Updated code to support new v0.9 logic

        ORG     $0100

; Print hw interface version (CPLD logic and pcb)
        LD      HL,HWVER
        CALL    PRINT
        IN      A,(CONTROL_PORT2)
        CALL    DESCHWVER

; Print msxpi-server version
        LD      BC,4
        LD      DE,COMMAND
        CALL    DOSSENDPICMD

WAIT_LOOP:
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_WAIT
        JR      NZ,WAIT_RELEASED
        CALL    CHKPIRDY
        JR      WAIT_LOOP

WAIT_RELEASED:

        CP      RC_FAILED
        JP      Z,PRINTPISTDOUT
        CP      RC_SUCCESS
        JP      Z,MAINPROGRAM

PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

MAINPROGRAM:
        JP      PRINTPISTDOUT

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
        call    PRINTNLINE
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
        dw      ifukn

ifv1:   DB      "(0001) Wired up prototype, without EPROM,EPM3064ALC-44","$"
ifv2:   DB      "(0010) Semi-wired up prototype, with EPROM, EPM3064ATC-44","$"
ifv3:   DB      "(0011) Limited 10-samples PCB, with EPROM, EPM3064ALC-44","$"
ifv4:   DB      "(0100) Limited 1 sample PCB, with EPROM, EPM3064ALC-44, 4 bits mode","$"
ifv5:   DB      "(0101) Limited 10 samples PCB Rev.3, EPROM, EPM3064ALC-44","$"
ifv6:   DB      "(0110) Wired up prototype, with EPROM, EPM7128SLC-84","$"
ifv7:   DB      "(0111) General Release v0.7 Rev.3 - Rev.7, EPM3064ALC-44, EPROM 27C256","$"
ifv8:   DB      "(1000) Limited 10 samples, Big v0.8.1 Rev.0, EPM7128SLC-84","$"
ifv9:   DB      "(1001) General Release v1.1, EPM3064ALC-44, EEPROM AT28C256","$"
ifukn:  DB      "Could not identify. Possibly an earlier version with old CPLD logic","$"
ifdummy: DB      "MSXPi not detected","$"

COMMAND:DB      "PVER"

HWVER:  DB      "Interface version:"
        DB      TEXTTERMINATOR

SRVVER: DB      "msxpi-server version:"
        DB      TEXTTERMINATOR

ROMCER: DB      "MSXPi ROM version:"
        DB      TEXTTERMINATOR

PVERHWNFSTR:
        DB      "MSXPi Interface not found","$"
PICOMMERR:
        DB      "Communication Error",13,10,"$"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"




