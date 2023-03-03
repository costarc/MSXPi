;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.9.0                                                           |
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
; 0.9.0  : Changes to supoprt new transfer logic
;
;Parameters:    C = 2BH (_SDATE)
;HL = Year 1980...2079
;D = Month (1=Jan...12=Dec)
;E = Date (1...31)
;Results:       A = 00H if date was valid
;FFH if date was invalid
;
;Parameters:    C = 2DH (_STIME)
;H = Hours (0...23)
;L = Minutes (0...59)
;D = Seconds (0...59)
;E = Centiseconds (ignored)
;Results:       A = 00H if time was valid

; Start of command - You may not need to change this

        ORG     $0100

        LD      HL,COMMAND
        CALL    DOSSENDPICMD

        JR      NC,MAINPROGRAM

PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

MAINPROGRAM:        
        CALL    SETCLOCK
        call    CLEARBUF
        LD      DE,buf
        CALL    RECVDATA
        LD      HL,buf
        call      PRINTPISTDOUT
        dec     hl                              ;check last byte in buffer. if zero, no more data
        ld      a,(hl)
        or      a
        jr      nz,MAINPROGRAM
        ret

; --------------------------------
; CODE FOR YOUR COMMAND GOES HERE
; --------------------------------
SETCLOCK:
        call    CLEARBUF
        LD      DE,buf
        CALL    RECVDATA
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
        CALL    BDOS
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

SETCLOCK_OLD:
; set date
        CALL    PIEXCHANGEBYTE
        LD      L,A
        CALL    PIEXCHANGEBYTE
        LD      H,A
        CALL    PIEXCHANGEBYTE
        LD      D,A
        CALL    PIEXCHANGEBYTE
        LD      E,A
        LD      C,$2B
        CALL    BDOS

; set time
        CALL    PIEXCHANGEBYTE
        LD      H,A
        CALL    PIEXCHANGEBYTE
        LD      L,A
        CALL    PIEXCHANGEBYTE
        LD      D,A
        CALL    PIEXCHANGEBYTE
        LD      E,A
        LD      C,$2D
        CALL    BDOS
        RET

; Replace with your command name here
COMMAND:  DB      "PDATE",0

; --------------------------------------
; End of your command
; You should not modify this code below
; --------------------------------------

PICOMMERR:
        DB      "Communication Error",13,10,"$"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"





