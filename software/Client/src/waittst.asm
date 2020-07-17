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
; gabarito.asm
; A tempalte for MSXPi development

; This template will implement the command gabarito.com
; Thsi command can be invoked usign the following syntaxed:
;
; gabarito
; gabarito help
; gabarito fastresponse
; gabarito slowresponse
; gabarito ???? whaat else?
;
; Here it is the generic communication flow between MSX and Pi.
; It may change depending on the command being implemented,
; therefore, the flow is designed to represent the functions
; implemented in this sample command.
;
; MSX                           RPi
;   1|--------  command -------->|
;   2|)Wait                      |)Parse Command
;   3|<----------- rc -----------|
;   4|)Parse rc                  |)Wait
;   5|--------- sendnext ------->|
;   6|<--------- rc_wait --------|
;   7|wait forever               |)Process requested data
;   8|<----------- rc -----------|
;   9|)Parse rc                  |)Wait
;  10|-------- sendnext -------->|
;  11|<--------- data -----------|
;  12|terminate                  |terminate
;
; Important points to consider in the above sequence:
; Line 1: command can be any text, any size. Do not exagerate.
; Line 2: Wait state has a short live. It can timeout and induce MSX into error, if it is too long (couple of seconds for example)
; Line 3: rc is a single byte return code (rc). Check file include.asm
; Line 4: Parse on the MSX Side means that, if rc is error code, MSX might have to stop the command. The rc code should tell what to do, for example, it may mean that MSX should ask Pi for a error message, or it may tell MSX to not try to communicate again with Pi, because it has stopped the communication in its side. If you insist and try, Pi won't be prepared to respond, and may result in MSX hanging
; Line 5:If rc was a success return code, then MSX can request (sendnext) next stream of data  as required by the command being implemented.
; Line 6:RPi may need to tell MSX that it will need an extended, undertermined time to process the command and have data ready, In this situation, it should send a "rc_wait" command do MSX.
; Line 7:MSX should loop waiting for a new rc from RPi. In meanwhile, RPi should be preparing the data to send to MSX. It can take as long as necessary, since it has sent rc_wait to MSX
; Line 8:After completing processing the data to send to MSX, RPi should send another rc to MSX: "rc_success" or "rc_failed"
; Line 9: rc is a single byte return code (rc). Check file include.asm
; Line 10:In case the rc allow further communication with RPi, then MSX send a request for the data (sendnext).
; Line 11:MSX enters a loop to receive the data. Usually, this loop should have a termination agreement between MSX and RPi, such as, that both parts terminate teh communication and stays in sync. Pi should finish its function at this point, and return to the "listed for new command" mode. MSX should return to command prompt.

        ORG     $0100

        LD      HL,MYCOMMAND
        LD      BC,MYCOMMAND_END - MYCOMMAND
        LD      A,C
        OUT     (DATA_PORT1),A
        LD      A,B
        OUT     (DATA_PORT1),A
L1:
        LD      A,(HL)
        OUT     (DATA_PORT1),A
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,L1
L2:
        IN      A,(DATA_PORT1)
        LD      C,A
        IN      A,(DATA_PORT1)
        LD      B,A
        DEC     BC
L3:
        IN      A,(DATA_PORT1)
        PUSH    BC
        CALL    PUTCHAR
        POP     BC
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,L3
        RET

MYCOMMAND:  DB      "GBT"
MYCOMMAND_END:

PICOMMERR:  DB      "Communication Error",13,10,"$"
PARMSERR:   DB      "Invalid parameters",13,10,"$"
            DB      0


INCLUDE "debug.asm"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

