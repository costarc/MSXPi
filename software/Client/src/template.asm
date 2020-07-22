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
; template.asm
; A tempalte for MSXPi DOS development

; This template will implement the command template.com
; This command can be invoked usign the following syntaxe:
;
; gabarito
; gabarito help
; gabarito fastresponse
; gabarito slowresponse
; gabarito ???? what else?
;
; Here it is the generic communication flow between MSX and RPi.
; It may change depending on the command being implemented,
; therefore, the flow is designed to represent the functions
; implemented in this sample command.
;
; MSX                           RPi
;   1|--------  command -------->|
;   2|)/buswait                  |)Parse Command
;   3|<----------- rc -----------|
;   4|)Parse rc                  |)Wait
;   5|------- poll (0x5b) ------>|
;   6|<-------- busy (1) --------|
;   7|)wait until (0x5b) = 0)    |)Process requested data
;   8|<----------- rc -----------|
;   9|)Parse rc                  |)Wait
;  10|<--------- data -----------|

;
; Important points to consider in the above sequence:
; Line 1: command can be any text, any size. Do not exagerate.
; Line 2: Wait state has a short live. It can timeout and induce MSX into error, if it is too long (couple of seconds for example)
; Line 3: rc is a single byte return code (rc). Check file include.asm
; Line 4: Parse on the MSX Side means that, if rc is error code, MSX might have to stop the command. The rc code should tell what to do, for example, it may mean that MSX should ask Pi for a error message, or it may tell MSX to not try to communicate again with Pi, because it has stopped the communication in its side. If you insist and try, Pi won't be prepared to respond, and may result in MSX hanging
; Line 5:RPi may need to tell MSX that it will need an extended, undertermined time to process the command and have data ready, In this situation, it should send a "rc_wait" return code to MSX.
; Line 6:MSX should loop polling I/O port (0x5b) waiting for it to change to zero. In mean while, RPi should be preparing the data to send to MSX. It can take as long as necessary, since it has sent rc_wait to MSX
; Line 7:Continuation of loop started in 5. Wait until port (0x5b) = 0
; Line 8: Once porr (0x5b) returns zero, MSX can request the return code from MSXPi. rc is a single byte return code (rc). Check file include.asm
; Line 9: parce the return code, and proceed processing as appropriate. RC ma flat that more data is coming, or no data will be sent. 
; Line 10:MSX enters a loop to receive the data. Usually, this loop should have a termination agreement between MSX and RPi, such as, that both parts terminate teh communication and stays in sync. Pi should finish its function at this point, and return to the "listed for new command" mode. MSX should return to command prompt.


TEXTTERMINATOR: EQU '$'

        ORG     $0100

; -------------------------------------------------------------
; Sequence 1
; This block of code will send your command to Raspberry Pi
; You should not need to change anything here.
; The actual command is defined in "COMMAND:  DB"
; at the end of this template.
; This block correspponds to Step (1) in the sequence diagram
; -------------------------------------------------------------
        org     $0100
        ld      bc,COMMAND_END - COMMAND
        ld      hl,COMMAND
        call    DOSSENDPICMD

; Note that if there is a communication error,
; the command is interruped right away.
; Communication error means: MSX could not talk to Pi, or
; in other words, the command never reached Pi.

        JR      C,PRINTPIERR
; -------------------------------------------------------------
; Sequence 3
; The rc code is now read from RPi.
; Note that MSX has always to request data to RPI, in this sense,
; the code is different than the sequence diagram.
; But this is how Sequence 3 is implemented, stick to it.
; MSX Ask RPi, "what is the rc for the last command I sent?"
; Then MSX reads the answer.
;
; At this stage, MSX only will accept:
;    RC_WAIT:   This answer implies that port (0x5b) will return "1"
;               when polled, until RPi completes the processing. MSX
;               program should loop waiing the port change to "1".

;    Other RC:  The Code on the RPi must return one of the
;               rc in the "indlude.asm" file. If a invalid RC is returned,
;               it might happen that there was sync error,
;               or MSX just read spurios data in the I/O
;               port - that is, not an actual response from RPi.
;
; Note: If first RC is RC_WAIT, then necessarily another RC will 
;       need to be send by RPi after processing is completed.
;       If first RC is not RC_WAIT, but it is a valid RC, then
;       the MSX can continue processing the data becasue the 2nd
;       Rc will not be sent (not necessary). 
; -------------------------------------------------------------
        call    PIREADBYTE    ; read return code
        cp      RC_WAIT
        call    z,CHKPIRDY    ; Poll port (0x5b) until it returns "0"
        call    PIREADBYTE    ; Proceed, get the RPi process return code

                              ; some examples of return codes RPi program could return:
        ; CP    RC_SUCCESS    ; Generic success return code
        ; CP    RC_FAILED     ; Generic fail return code
        ; CP    RC_SUCCNOSTD  ; Success rc, but no data is returned

        jp      PRINTPISTDOUT ; Print output data to screen

PICOMMERR:
        DB      "Communication Error",13,10,"$"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

COMMAND:     DB      "template"
COMMAND_SPC: DB " " ; Do not remove this space, do not add code or data after this buffer.
COMMAND_END: EQU $