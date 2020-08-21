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

; gabarito.asm
; A tempalte for MSXPi development

; This template to use for developmet of MSXPi DOS Commands
; This code implements command "template.com" on MSX. On the Raspberry Pi,
; loop for the msxpi-server.py function "template".
;
; Here it is the generic communication flow between MSX and Pi.
; It may change depending on the command being implemented,
; therefore, the flow is designed to represent the functions
; implemented in this sample command.
;
; MSX                           RPi
;   1|--------  command -------->|
;   2|)wait                      |)Parse Command
;   3|<-------- RC_WAIT ---------|
;   4|)Wait                      |)Process command
;   5|<----------- RC -----------| Send return code
;   6|-------- sendnext -------->| Check if in sync
;   7|<--------- data -----------|
;   8|terminate                  |terminate
;
; Important points to consider in the above sequence:
; Line 1: command can be any text, any size. Do not exagerate.
; Line 2: Wait state has a short live. It can timeout and induce MSX into error, if it is too long (couple of seconds for example)
; Line 3:RPi may need to tell MSX that it will need an extended, undertermined time to process the command and have data ready, In this situation, it should send a "rc_wait" command do MSX.
; Line 4: MSX should loop waiting the interface to be available (port 0x56). In meanwhile, RPi should be preparing the data to send to MSX. It can take as long as necessary, since it has sent rc_wait to MSX
; Line 5:After completing processing the data to send to MSX, RPi should send another rc to MSX: "rc_success" or "rc_failed"
; Line 6:In case the rc allow further communication with RPi, then MSX send a request for the data (sendnext).
; Line 7:MSX enters a loop to receive the data. Usually, this loop should have a termination agreement between MSX and RPi, such as, that both parts terminate teh communication and stays in sync. Pi should finish its function at this point, and return to the "listed for new command" mode. MSX should return to command prompt.
;
; This logic is implemented in below.

        ORG     $0100

; -------------------------------------------------------------
; Sequence 1
; This block of code will send your command to Raspberry Pi
; You should only change the string in COMMAND (register DE)
; and the command size (register BC) need to change anything here.
; The actual command is defined in "COMMAND:  DB  "TEMPLATE"
; at the end of this file.
; -------------------------------------------------------------
        LD      A,($82)
        LD      (COMMAND + 8),A
        LD      BC,9
        LD      DE,COMMAND
        CALL    DOSSENDPICMD

; Note that if there is a communication error,
; the command is interruped right away.
; Communication error means: MSX could not talk to Pi, or
; in other words, the command never reached Pi.

        JR      C,PRINTPIERR
; -------------------------------------------------------------
; Sequence 2 to 5:
; The rc code is now read from RPi. It might be RC_WAIT, in 
; which case MSX will call CHKPIRDY to test port (0x56)
; Once the port returns status available, the MSX will read 
; anotehr byte - this should be the return code
; in sequence line 5.
; -------------------------------------------------------------



WAIT_LOOP:
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE      ; Sequence line 2
        CP      RC_WAIT             ; Sequence line 3
        JR      NZ,WAIT_RELEASED
        CALL    CHKPIRDY            ; Sequence line 4
        JR      WAIT_LOOP           ; Sequence line 4

; -------------------------------------------------------------
; At this stage, MSX only will accept:
;    RC_FAILED: RPi could not get the data MSX requested
;               (for example, a file as not found)
;    SENDNEXT:  RPi completed the command and is ready to
;               send the result to MSX
;    Aything else: The Code on the RPi must return one of the
;               two rc above. If anything else is returned,
;               it might happen that there was sync error,
;               or MSX just read spurios data in the I/O
;               port - that is, not an actual response from RPi.
; -------------------------------------------------------------

WAIT_RELEASED:                       ; Sequence line 5

        CP      RC_FAILED
        JP      Z,PRINTPISTDOUT
        CP      RC_SUCCESS
        JP      Z,MAINPROGRAM        ; Jump to sequence line 6

PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

MAINPROGRAM:
        CALL    PIEXCHANGEBYTE
        RET

COMMAND:  DB      "DOS INI ",0,0
PICOMMERR:  DB      "Communication Error",13,10,"$"
PARMSERR:   DB      "Invalid parameters",13,10,"$"


; INCLUDE "debug.asm"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

; Your buffers and other temporary volatile temporary date should go here.
