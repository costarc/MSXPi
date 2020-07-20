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
        org     $0100
        ld      bc,COMMAND_END - COMMAND
        ld      hl,COMMAND
        call    DOSSENDPICMD
        call    PIREADBYTE    ; read return code
        cp      RC_WAIT
        call    z,CHKPIRDY
        CALL    PDATE
        CALL    PRINTPISTDOUT
        RET
; --------------------------------
; CODE FOR YOUR COMMAND GOES HERE
; --------------------------------
PDATE:
; set date

        CALL    PIREADBYTE
        LD      L,A
        CALL    PIREADBYTE
        LD      H,A
        CALL    PIREADBYTE
        LD      D,A
        CALL    PIREADBYTE
        LD      E,A
        LD      C,$2B
        CALL    BDOS

; set time
        CALL    PIREADBYTE
        LD      H,A
        CALL    PIREADBYTE
        LD      L,A
        CALL    PIREADBYTE
        LD      D,A
        CALL    PIREADBYTE
        LD      E,A
        LD      C,$2D
        CALL    BDOS
        RET

PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

; --------------------------------------
; End of your command
; You should not modify this code below
; --------------------------------------

PICOMMERR:
        DB      "Communication Error",13,10,"$"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

COMMAND:     DB      "pdate"
COMMAND_SPC: DB " " ; Do not remove this space, do not add code or data after this buffer.
COMMAND_END: EQU $