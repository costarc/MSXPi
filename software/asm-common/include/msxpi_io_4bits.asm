;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.7                                                             |
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
SENDIFCMD:                     ; registers A,B and FLAGS are modified
            PUSH    BC
			LD      B,A
            AND     %11110000
            RRA
            RRA
            RRA
            RRA
            OUT     (8),A
            LD      A,B
            AND     %00001111
            OUT     (6),A       ; Send data, or command
            POP     BC
            RET

;-----------------------
; CHKPIRDY             |
;-----------------------
CHKPIRDY:
            PUSH    BC
            LD      BC,0FFFFH
CHKPIRDY0:
            IN      A,(6)           ; Verify SPIRDY register on the MSXInterface
            AND     %00001111
            JR      Z,CHKPIRDYOK
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
; READBYTE             |
;-----------------------
READBYTE:
            PUSH    BC
            XOR	    A
            OUT     (8),A       ; Send 4 bits READ command to the Interface
            OUT		(6),A
            JR      READPIBYTE

;-----------------------
; TRANSFBYTE           |
;-----------------------
TRANSFBYTE:                     ; registers A,B and FLAGS are modified
            PUSH    BC
            PUSH    AF
            CALL    CHKPIRDY
            POP     AF
            LD      B,A
            AND     %11110000
            RRA
            RRA
            RRA
            RRA     
            OUT     (8),A
            LD      A,B
            AND     %00001111
            OUT     (7),A       ; Send data, or command
READPIBYTE:
            CALL    CHKPIRDY     ;Wait Interface transfer data to PI and Pi App processing
            IN      A,(8)       ; read MSB part of the byte
            SLA     A
            SLA     A
            SLA     A
            SLA     A           ; four SLA to rotate for bits to the left, since this data is the LSB
            LD      B,A         ; save LSB to later merge with MSB
            IN      A,(7)       ; read MSB part of the byte
            AND     %00001111   ; clean left four bits because
            OR      B           ; Merge LSB with MSB to get the actual byte received
            POP     BC
            RET                 ; Return in A the byte received

;-----------------------
; SENDPICMD            |
;-----------------------
; Send a command to Raspberry Pi
; Command should be in A
; Return Flag C set if there was a communication error
; Return A = command sent if command was successfull (ack)
; Return A = 0xEE if command resulted in error during execution
SENDPICMD:
            PUSH    AF
            CALL    TRANSFBYTE      ;Send command do PI
            LD      B,1
            CALL    DELAY
            POP     DE

; now read ACK
SENDPICMD1:
            PUSH    DE
            CALL    READBYTE        ;Read response ACK

;debug to show response from Pi
;            PUSH    AF
;            CALL    PRINTNUMBER_
;            POP     AF
            POP     DE
            CP      D               ; Ack received?
            RET     Z               ; Ack correct, command executed
            CP      0AEH            ; PROCESSING ?
            JR      Z,SENDPICMD2
            CP      0EEH            ; CMDERROR on Pi, means that Pi actually ran
                                    ; the command, but it failed for some reason.
            RET     Z
            SCF                     ; set C flag when MSXPi failed to execute command
            RET

; command was run by Pi, but resulted in error.
; this should return an error string to MSX to be printed.
; delay before checking ACK again
SENDPICMD2:
            LD      B,1     ;MULTIPLIER FOR THE LOOP
            CALL    DELAY
            JR      SENDPICMD1

; Wait A cycles counting from 0 to 65535
DELAY:
            PUSH    DE
            LD      DE,0FFFFH
DELAY1:
            NOP
            NOP
            NOP
            DEC     DE
            LD      A,D
            OR      E
            JR      NZ,DELAY1
DELAY2:
            DJNZ    DELAY1
            POP     DE
            RET

;debug only
;-----------------------
; PRINTNUMBER          |
;-----------------------
PRINTNUMBER_:
            PUSH    DE
            LD      E,A
            PUSH    DE
            AND     0F0H
            RRA
            RRA
            RRA
            RRA
            CALL    PRINTDIGIT_
            POP     DE
            LD      A,E
            AND     %00001111
            CALL    PRINTDIGIT_
            POP     DE
            RET

PRINTDIGIT_:
            CP      0AH
            JR      C,PRINTNUMERIC_
PRINTALFA_:
            LD      D,37H
            JR      PRINTNUM1_

PRINTNUMERIC_:
            LD      D,30H
PRINTNUM1_:
            ADD     A,D
            CALL    CHPUT
            RET



