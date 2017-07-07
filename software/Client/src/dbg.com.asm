;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.8                                                             |
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

TEXTTERMINATOR: EQU '$'

        ORG     $0100
        LD      BC,13
        LD      DE,DBGCMD
        CALL    SENDDATABLOCK
        LD      A,ENDTRANSFER
        CALL    PIEXCHANGEBYTE
        CP      ENDTRANSFER
        JR      NZ,PRINTPIERR
        JP      0

PRINTPIERR:
        LD      HL,PICOMMERR
        CALL    PRINT
        JP      0

DBGCMD: DB      "DEBUG COMMAND",0

PICOMMERR:
        DB      "Communication Error",13,10,"$"

;-----------------------
; SENDIFCMD            |
;-----------------------
SENDIFCMD:
            out     (CONTROL_PORT),a       ; Send data, or command
            ret

;-----------------------
; CHKPIRDY             |
;-----------------------
CHKPIRDY:
            push    bc
            ld      bc,0ffffh
CHKPIRDY0:
            in      a,(CONTROL_PORT); verify spirdy register on the msxinterface
            and     $01
            jr      z,CHKPIRDYOK    ; rdy signal is zero, pi app fsm is ready
                                    ; for next command/byte
            dec     bc              ; pi not ready, wait a little bit
            ld      a,b
            or      c
            jr      nz,CHKPIRDY0
CHKPIRDYNOTOK:
            scf
CHKPIRDYOK:
            pop     bc
            ret

;-----------------------
; PIREADBYTE           |
;-----------------------
PIREADBYTE:
            call    CHKPIRDY
            jr      c,PIREADBYTE1
            xor     a                   ; do not use xor to preserve c flag state
            out     (CONTROL_PORT),a    ; send read command to the interface
            call    CHKPIRDY            ;wait interface transfer data to pi and
                                        ; pi app processing
                                        ; no ret c is required here, because in a,(7) does not reset c flag
PIREADBYTE1:
            in      a,(DATA_PORT)       ; read byte
            ret                         ; return in a the byte received

;-----------------------
; PIWRITEBYTE          |
;-----------------------
PIWRITEBYTE:
            push    af
            call    CHKPIRDY
            pop     af
            out     (DATA_PORT),a       ; send data, or command
            ret

;-----------------------
; PIEXCHANGEBYTE       |
;-----------------------
PIEXCHANGEBYTE:
            call    PIWRITEBYTE
            call    CHKPIRDY
            in      a,(DATA_PORT)       ; read byte
            ret

            in      a,(CONTROL_PORT)
            sla     a
            or      a
            jr      z,PIEXCHANGEBYTE
            out     (DATA_PORT),a
PIEXCHANGEBYTE1:
            in      a,(CONTROL_PORT)
            sla     a
            or      a
            jr      z,PIEXCHANGEBYTE1
            in      a,(DATA_PORT)
            ret



INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxdos_stdio.asm"

