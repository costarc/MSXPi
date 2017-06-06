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
            PUSH    BC
			LD      B,A
            AND     $F0
            RRA
            RRA
            RRA
            RRA
            OUT     (CONTROL_PORT2),A
            LD      A,B
            AND     $0F
            OUT     (CONTROL_PORT),A       ; Send data, or command
            POP     BC
            RET

;-----------------------
; CHKPIRDY             |
;-----------------------
CHKPIRDY:
            PUSH    BC
            LD      BC,0FFFFH
CHKPIRDY0:
            IN      A,(CONTROL_PORT); Verify SPIRDY register on the MSXInterface
            AND     $0F
            OR	    A
            JR      Z,CHKPIRDYOK    ; RDY signal is zero, Pi App FSM is ready
                                    ; for next command/byte
            DEC     BC              ; Pi not ready, wait a little bit
            LD      A,B
            OR      C
            JR      NZ,CHKPIRDY0
CHKPIRDYNOTOK:
            SCF
CHKPIRDYOK:
            POP     BC
            RET

;-----------------------
; PIREADBYTE           |
;-----------------------
PIREADBYTE:
            PUSH    BC
            CALL    CHKPIRDY
            JR      C,PIREADBYTE1
            XOR     A                   ; do not use XOR to preserve C flag state
            OUT     (CONTROL_PORT2),A    ; Send READ command to the Interface
            OUT     (CONTROL_PORT),A    ; Send READ command to the Interface
            CALL    CHKPIRDY            ;Wait Interface transfer data to PI and
                                        ; Pi App processing
                                        ; No RET C is required here, because IN A,(7) does not reset C flag
PIREADBYTE1:
            IN      A,(CONTROL_PORT2)   ; read MSB part of the byte
            SLA     A
            SLA     A
            SLA     A
            SLA     A            ; four SLA to rotate for bits to the left,
                                 ; since this data is the LSB
            LD      B,A          ; save LSB to later merge with MSB
            IN      A,(DATA_PORT); read MSB part of the byte
            AND     $0F          ; clean left four bits because
            OR      B            ; Merge LSB with MSB to get the actual byte received
            POP     BC
            RET                  ; Return in A the byte received

;-----------------------
; PIWRITEBYTE          |
;-----------------------
PIWRITEBYTE:
            PUSH    BC
            PUSH    AF
            CALL    CHKPIRDY
            POP     AF
            LD      B,A
            AND     $F0
            RRA
            RRA
            RRA
            RRA     
            OUT     (CONTROL_PORT2),A
            LD      A,B
            AND     $0F
            OUT     (DATA_PORT),A       ; Send data, or command
            POP     BC
            RET

;-----------------------
; PIEXCHANGEBYTE       |
;-----------------------
PIEXCHANGEBYTE:
            PUSH    BC
            CALL    PIWRITEBYTE
            CALL    CHKPIRDY
            IN      A,(CONTROL_PORT2)   ; read MSB part of the byte
            SLA     A
            SLA     A
            SLA     A
            SLA     A            ; four SLA to rotate for bits to the left,
                                 ; since this data is the LSB
            LD      B,A          ; save LSB to later merge with MSB
            IN      A,(DATA_PORT); read MSB part of the byte
            AND     $0F          ; clean left four bits because
            OR      B            ; Merge LSB with MSB to get the actual byte received
            POP     BC
            RET                  ; Return in A the byte received
