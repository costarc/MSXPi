;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.8.1                                                           |
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
; 0.8    : Re-worked protocol as protocol-v2:
;          RECVDATABLOCK, SENDDATABLOCK, SECRECVDATA, SECSENDDATA,CHKBUSY
;          Moved to here various routines from msxpi_api.asm
; 0.7    : Replaced CHKPIRDY retries to $FFFF
;          Removed the RESET when PI is not responding. This is now responsability
;           of the calling function, which might opt to do something else.
; 0.6c   : Initial version commited to git
;

; Inlude file for other sources in the project
;
; ==================================================================
; BASIC I/O FUNCTIONS STARTS HERE.
; These are the lower level I/O routines available, and must match
; the I/O functions implemented in the CPLD.
; Other than using these functions you will have to create your
; own commands, using OUT/IN directly to the I/O ports.
; ==================================================================

;-----------------------
; SENDIFCMD            |
;-----------------------
SENDIFCMD:
            out     (CONTROL_PORT1),a       ; Send data, or command
            ret

;-----------------------
; CHKPIRDY             |
;-----------------------
CHKPIRDY:
      in    a,(CONTROL_PORT1)
      or    a
      jr    nz,CHKPIRDY
      ret
      
            push    af
            push    bc
            ld      bc,0ffffh
CHKPIRDY0:
            in      a,(CONTROL_PORT1); verify spirdy register on the msxinterface
            or      a
            jr      z,CHKPIRDYOK    ; rdy signal is zero, RPi is alive
                                    ; for next command/byte
            dec     bc              ; pi not ready, wait a little bit
            ld      a,b
            or      c
            jr      nz,CHKPIRDY0
CHKPIRDYNOTOK:
            scf
CHKPIRDYOK:
            pop     bc
            pop     af
            ret

;-----------------------
; PIREADBYTE           |
;-----------------------
PIREADBYTE:
            di                          ; disable interrupts in case /wait is too long
            in      a,(DATA_PORT1)      ; read byte
            ei
            ret                         ; return in a the byte received
PIREADBYTESEC:
            push   hl
PIREADBYTESEC0:
            call   PIREADBYTE
            ld     l,a
            xor    CRC
            ld     h,a
            call   PIREADBYTE
            cp     h
            jr     z,PIREADBYTESEC_OK
            ld     a,RESEND
            call   PIWRITEBYTE
            jr     PIREADBYTESEC0
PIREADBYTESEC_OK:
            ld     a,ENDTRANSFER
            call   PIWRITEBYTESEC
            ld     a,l
            pop    hl
            ret
            
;-----------------------
; PIWRITEBYTE          |
;-----------------------
PIWRITEBYTE:
            di
            out     (DATA_PORT1),a       ; send data, or command
            ei
            ret

PIWRITEBYTESEC:
            push   af
            call   PIWRITEBYTE
            xor    CRC
            call   PIWRITEBYTE
            call   PIREADBYTE
            cp     ENDTRANSFER
            jr     z,PIWRITEBYTESEC_OK
            pop    af
            jr     PIWRITEBYTESEC
PIWRITEBYTESEC_OK:
            pop    af
            ret

;-----------------------
; PIEXCHANGEBYTE       |
;-----------------------
PIEXCHANGEBYTE:
            call    PIWRITEBYTE
            jr      PIREADBYTE
