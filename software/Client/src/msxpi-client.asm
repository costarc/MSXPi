;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.7.0.1                                                          |
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
; 0.7    : Revised to sync with other component´s verisons
; 0.6d   : Changed header of Client to: <size><exec address><rom binary>
;          Size and exec address are two bytes long each.
;          Size is inserted by the MSXPi Server App.
; 0.6c   : Initial version commited to git
;
 
MODEL4b:    EQU     0

INLINBUF:   EQU     $F55E
INLIN:      EQU     $00B1
CHPUT:      EQU     $00A2
CHGET:      EQU     $009F
INITXT:     EQU     $006C
EXPTBL:     EQU     $FCC1
RDSLT:      EQU     $000C
WRSLT:      EQU     $0014
CALSLT:     EQU     $001C
ENASLT:     EQU     $0024
CSRY:       EQU     $F3DC
CSRX:       EQU     $F3DD
ERAFNK:     EQU     $00CC
DSPFNK:     EQU     $00CF
PROCNM:     EQU     $FD89
XF365:      EQU     $F365                  ; routine read primary slotregister

            DW      PROG

            ORG     0D000H
CLIENTSTART:EQU     $
PROG:
            CALL    ERAFNK
            CALL    INITXT
            LD      HL,TITLE
            CALL    PRINT
            CALL    FINDRAMSLOTS
            CALL    CHKPICONN

PROGLOOP:
            CALL    READCMD
; PARSE cmd will return in DE address of parameter after command
; This can be used for exaple to load a file such as in a command like:
; LOAD "FILE.EXT"
            CALL    PARSECMD        ;C set ==> cmd not found
            JR      C,CMDNOTFOUND0   ;Command not found
            OR      A
            JR      Z,PROGLOOP      ;A=0 ==> Input has no chars to parse
            LD      BC,PROGLOOP
            PUSH    BC              ;Return address
            JP      (HL)            ;Execute command. DE contain address of parameter in BUF

CMDNOTFOUND0:
            CALL    CMDNOTFOUND
            JR      PROGLOOP

CMDNOTFOUND:
            LD      HL,NOCMDMSG
            CALL    PRINT
            RET

; ================================================================
; MSX PI Interface Front-End Commands start here
; ================================================================

;-----------------------
; PIPOWEROFF           |
;-----------------------

PIPOWEROFF:
            CALL    PISERVERSHUT
            RET

;-----------------------
; CLS                  |
;-----------------------
CLS:
            LD      A,12
            CALL    CHPUT
            RET

;-----------------------
; CHKPICONN            |
;-----------------------
CHKPICONN:
            CALL    CHKPISTATUS       ;Send command do PI
            LD      HL,PIONLINE
            JP      NC,PRINT
            LD      A,255
            CALL    SENDIFCMD       ;reinitialize interface state
            LD      HL,PIOFFLINE
            JP      PRINT

;-----------------------
; EXIT                |
;-----------------------
EXIT:
            POP     DE
            CALL    DSPFNK
            RET

;-----------------------
; HELP                 |
;-----------------------
HELP:
            LD      HL,HLPTXT
            CALL    PRINT
            RET


LOADPROG:
; HL is required if file type is RAW.
; Other file types are recognized automatically and loaded into
; the address in the headers
            CALL    LOAD
            JR      C,LOADBINERR     ;Load failed.
            LD      C,A
            LD      A,(AUTORUN)
            OR      A
            RET     Z               ;Autorun not set
            LD      A,C
            CP      4
            JR      Z,EXECROMPROG

;SWITCH OFF PI because we are going to run a game,
;and it is not possible to reset or exit to BASIC
; Therefore it is safer to shutdown PI before runnign the program

;            CALL    PIPOWEROFF
            JP      (HL)

EXECROMPROG:

;run the program

;does not work
            PUSH    HL
            LD      A,(SLOTRAM1)
            LD      H,40h ; b01000000 = page 1
            CALL    ENASLT
            POP     HL
            JP      (HL)

LOADBINERR:
; FILE NOT FOUND
            LD      HL,FNOTFOUND
            CP      $EE
            JR      Z,PRINTPARMERR0

; OTHER ERROR
PRINTPARMERR:
            LD      HL,PARMERRMSG   ;Parameters invalid. Print Error.
PRINTPARMERR0:
            CALL    PRINT
            RET

;-----------------------
; PIAPPSTATE           |
;-----------------------
PIAPPSTATE:
            LD      A,(CMDGETSTAT)
            CALL    SENDPICMD
            JP      C,PRINTPIERR
            LD      HL,PIAPPMSG
            CALL    PRINT
            CALL    READBYTE
            CALL    PRINTNUMBER 
            CALL    PRINTNLINE
            RET

;-----------------------
; RESET                |
;-----------------------
RESET:
            CALL    PIAPPRESET
            RET


;-----------------------
; RUNPICMD             |
;-----------------------
RUNPICMD:
            CALL    PARSEPARM
            JP      C,PRINTPARMERR
            CALL    SETPARM
            JP      C,PRINTPARMERR
            LD      A,(CMDRUNPICMD)
            CALL    SENDPICMD
            JP      C,PRINTPIERR
            SCF
            CALL    READTEXTSTREAM
            CALL    PRINTNLINE
            RET

;-----------------------
; MORE                 |
;-----------------------
MOREPROG:
            CALL    PARSEPARM
            JP      C,PRINTPARMERR
            LD      HL,(PARMBUF)
            LD      A,(HL)
            OR      A

;MORE need a file name. If there is not a parameter,
;print error message
            JP      Z,PRINTPARMERR
            CALL    SETPARM
            JP      C,PRINTPARMERR

MOREPRG0:
            LD      A,(CMDMORE)
            CALL    SENDPICMD
            JP      C,PRINTPIERR
            SCF
            CALL    READTEXTSTREAM
            CALL    PRINTNLINE
            RET

;-----------------------
; CD                    |
;-----------------------
CDPROG:
            CALL    PARSEPARM
            OR      A
            JR      NZ,CDPROG2

; No parameters... will set to root "/"
CDPROG1:
            LD      HL,(PARMBUF)
            LD      A,'/'
            LD      (HL),A
            INC     HL
            XOR     A
            LD      (HL),A

CDPROG2:
            LD      A,(CMDSETDIR)
            CALL    SENDPICMD
            RET     C               ;Error
            CALL    SENDPARM
            RET

;-----------------------
; PWD                  |
;-----------------------
PWDPROG:
            LD      A,(CMDPWD)
            CALL    SENDPICMD
            JP      C,PRINTPIERR
            CALL    READTEXTSTREAM
            CALL    PRINTNLINE
            RET

;-----------------------
; DIR                  |
;-----------------------
DIRPROG:
            CALL    PARSEPARM
            CP      255
            JR      Z,PRINTPIERR
            OR      A
            JR      Z,DIR0
            CALL    SETPARM
            JP      C,PIERRRMSG
DIR0:
            LD      A,(CMDFILES)
            CALL    SENDPICMD
            JR      C,PRINTPIERR
            CALL    READTEXTSTREAM
;           CALL    READBYTE
;           CALL    READBYTE
;           CALL    READBYTE
            CALL    PRINTNLINE
            RET

PRINTPIERR:

            LD      HL,PIERRRMSG
            JP      PRINT


;-----------------------
; SET                  |
;-----------------------
SETPROG:
            CALL    PARSEPARM
            OR      A
            JP      Z,PRINTPARMERR
            LD      A,(CMDSETVAR)
            CALL    SENDPICMD
            RET     C               ;Error
            CALL    SENDPARM
            CALL    READTEXTSTREAM
            CALL    PRINTNLINE
            RET

;-----------------------
; WIFI                 |
;-----------------------
WIFIPROG:
            CALL    PARSEPARM
            CP      255
            JR      Z,PRINTPIERR
            OR      A
            JR      Z,WIFIPRGERR
            CALL    SETPARM
            JP      C,PIERRRMSG
WIFIPROG0:
            LD      A,(WIFICFG)
            CALL    SENDPICMD
            JR      C,PRINTPIERR
            CALL    READTEXTSTREAM
            CALL    PRINTNLINE
            RET

WIFIPRGERR:
            LD      HL,PARMERRMSG
            JP      PRINT

; ================================================================
; API AND OTHER SUPPORTING FUNCTIONS STARTS HERE
; ================================================================

INCLUDE    "msxpi_api.asm"

; ==================================================================
; BASIC I/O FUNCTIONS STARTS HERE.
; These are the lower level I/O routines available, and must match
; the I/O functions implemented in the CPLD.
; Other than using these functions you will have to create your
; own commands, using OUT/IN directly to the I/O ports.
; ==================================================================

; There are two prototype versions:
; 1st model, which has only 4 bits for the MSX Data bus.
; 2nd model, which has all 8 bits for the MSX Data bus.
; Model4b = 1 means we are compiling the ROM for the 1st model.
; Model4b = 0 means we are compilig the ROM for the 2nd model.

IF MODEL4b
    INCLUDE    "msxpi_io_4bits.asm"
ELSE
    INCLUDE    "msxpi_io.asm"
ENDIF


; ==================================================================
; LIST OF COMMAND CODES, SHOULD MATCH COMMANDS DEFINED IN THE PI APP
; ==================================================================

CMDLDFILE:  DB      0F1H    ;FILE LOAD
CMDFILES:   DB      01DH    ;LIST DIR
WIFICFG:    DB      01AH    ;SET WIFI CREDENTIALS
CMDVERIFY:  DB      0AAH    ;ACK CODE, SUCCESS, READY, APP IS OK
CMDGETSTAT: DB      055H    ;Status of PI App state machine
CMDRESET:   DB      0FFH    ;Reset App internal status
CMDSETPARM: DB      07AH    ;Set msx_parm1 or msx_parm2 on Pi App
CMDPIOFF:   DB      066H    ; Shutdown Pi
CMDSETDIR:  DB      07BH
CMDRUNPICMD:DB      0CCH    ;run commands on Pi
CMDPWD:     DB      07CH    ;PWD command
CMDMORE:    DB      07DH    ;MORE command
CMDSETVAR:  DB      0D1H    ;SET command

; ==================================================================
; LIST OF COMMAND RESPONSE CODES
; ==================================================================
NOT_READY:  DB      0AFH

; ==================================================================
; FRONTE-END TITLE, HELP AND ERROR MESSAGES
; ==================================================================

TITLE:
            DB      "MSXPi Hardware Interface v0.7",13,10
            DB      "MSXPi Cloud OS (Client) v0.7.0.1",13,10
            DB      "(c) Ronivon C. Costa,2017",13,10
            DB      "TYPE HELP for available commands",13,10
            DB      00

HLPTXT:     DB      "BASIC CHKPICONN CD",34,"<url>|dir",34," CLS DIR HELP "
            DB      "LOAD ",34,"<url>|file",34,"<,R> MORE PIAPPSTATE #(Pi command) "
            DB      "PIPOWEROFF PWD RESET SET WIFI",13,10
            DB      00


PROMPT:
            DB      "CMD:",0

LOADERRMSG:
            DB      "Error "
LOADMSG:
            DB      "Loading a program from Raspbery PI ",13,10
            DB      00

FNOTFOUND:
            DB      "File not Found.",13,10
            DB      00

PIERRRMSG:
            DB      "Pi responded with and error",13,10
            DB      00

NOCMDMSG:
            DB      "Command not found",13,10
            DB      00

PARMERRMSG: DB      "Syntax error in command",13,10
            DB      00

PIOFFLINE:  DB      "Raspberry PI not responding",13,10
            DB      "Verify if server App is running",13,10
            DB      00

PIONLINE:   DB      "Rasperry PI is online",13,10
            DB      00

PIAPPMSG:   DB      "Rasperry PI App internal status is "
            DB      00

MSGPAUSE:   DB      "Enter..."
            DB      00

; ==================================================================
; TABLE OF COMMANDS IMPLEMENTED IN THIS FRONT-END
; ==================================================================

COMMANDLIST:

RUNPICMDSTR:
            DB      "#",0
            DW      RUNPICMD

CLSSTR:
            DB      "CLS",0
            DW      CLS

EXITSTR:

            DB      "BASIC",0
            DW      EXIT
FILESTR:
            DB      "DIR",0
            DW      DIRPROG
HELPSTR:
            DB      "HELP",0
            DW      HELP
LOADSTR:
            DB      "LOAD",0
            DW      LOADPROG

CHECKPISTR:
            DB      "CHKPICONN",0
            DW      CHKPICONN

PIAPPSTATESTR:
            DB      "PIAPPSTATE",0
            DW      PIAPPSTATE

PIPOWEROFFSTR:
            DB      "PIPOWEROFF",0
            DW      PIPOWEROFF

RESETSTR:
            DB      "RESET",0
            DW      RESET

CDSTR:
            DB      "CD",0
            DW      CDPROG

PWDSTR:
            DB      "PWD",0
            DW      PWDPROG

MORESTR:
            DB      "MORE",0
            DW      MOREPROG

SETSTR:     DB      "SET",0
            DW      SETPROG

SETWIFICFG: DB      "WIFI",0
            DW      WIFIPROG

ENDOFCMDS:  DB      00

; ==================================================================
; VARIABLES AND BUFFERS USED IN THIS FRONT-END
; ==================================================================

AUTORUN:    DB      00

PISTATUS:   DB      00

STARTADDR:  DW      0000

ENDADDR:    DW      0000

EXECADDR:   DW      0000

FSIZE:      DW      0000

PARMBUF:    DW      0000

FILELOADADDR:
            DW      0000

SLOTRAM0:   DB      00
SLOTRAM1:   DB      00
SLOTRAM2:   DB      00
SLOTRAM3:   DB      00

FILETYPE:   DB      00

PAUSEVAR:   DB      00

MCSRY:      DB      00

MCSRX:      DB      00

CNT1:       DB      00

VAR1:       DB      00

FIM:        EQU     $

            END

