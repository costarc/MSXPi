;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.8.2                                                           |
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
; 0.8.2  : Commands ported to support Python version
; 0.8.1  : Client now uses protocol-v2.
; 0.7    : Revised to sync with other component´s verisons
; 0.6d   : Changed header of Client to: <size><exec address><rom binary>
;          Size and exec address are two bytes long each.
;          Size is inserted by the MSXPi Server App.
; 0.6c   : Initial version commited to git
;

TEXTTERMINATOR: EQU 0


            DB      $FE
            DW      PROG
            DW      FIM
            DW      PROG

            ORG     0C000H
CLIENTSTART:EQU     $
MSXPIBUFF:  EQU     $-513
PROG:
            CALL    ERAFNK
            CALL    INITXT
            LD      HL,TITLE
            CALL    PRINT
            LD      A,RESET
            CALL    SENDIFCMD
;CALL    SYNCH
            CALL    FINDRAMSLOTS
PROGLOOP:

; Read keyboard, return data in buffer INLINBUF
            CALL    READCMD

; PARSE cmd and return in DE the buffer address with the text
; This can be used for exaple to load a file such as in a command like:
; LOAD "FILE.EXT"
            CALL    PARSECMD        ;C set ==> cmd not found
            JR      C,CMDNOTFOUND0   ;Command not found
            OR      A
            JR      Z,PROGLOOP      ;A=0 ==> Input has no chars to parse
            PUSH    HL
            LD      HL,PROGLOOP
            EX      (SP),HL
            LD      DE,INLINBUF
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

PSET:
PWIFI:
PCD:
DIRPROG:
RUNPICMD:
        DEC     BC
        CALL    SENDPICMD
        JP      C,PRINTPIERR
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_WAIT
        JR      NZ,PRINTPIERR

WAITLOOP:
        CALL    CHECK_ESC
        JR      C,PRINTPIERR
        CALL    CHKPIRDY
        JR      C,WAITLOOP
; Loop waiting download on Pi
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_FAILED
        JP      Z,PRINTPISTDOUT
        CP      RC_SUCCESS
        JP      Z,PRINTPISTDOUT
        CP      RC_SUCCNOSTD
        JR      NZ,WAITLOOP
        RET

PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

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
            CALL    SENDPICMD
            CALL    PIEXCHANGEBYTE
            CP      READY
            JP      NZ,PRINTCOMMERROR
            LD      HL,PIONLINE
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

LOADROMPROG:
        CALL    SENDPICMD
        JP      C,LOADPROGERR
; wait RPi to load the program
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_WAIT
        JR      NZ,PRINTPIERR

WAITLOOPL1:
        CALL    CHECK_ESC
        JR      C,PRINTPIERR
        CALL    CHKPIRDY
        JR      C,WAITLOOPL1
; Loop waiting download on Pi
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_FAILED
        JR      Z,PRTSTD
        CP      RC_SUCCESS
        JR      Z,PRTSTD
        CP      RC_SUCCNOSTD
        JR      NZ,WAITLOOPL1

LOADREADY:
        LD      HL,LOADPROGRESS
        CALL    PRINT
        CALL    LOADROM

LOADROMPROG1:
        CALL    PIEXCHANGEBYTE
        PUSH    HL
        PUSH    AF
        CALL    PRINTPISTDOUT
        POP     AF
        POP     HL
        CP      ENDTRANSFER
        LD      A,(SLOTRAM1)
        LD      H,40h ; b01000000 = page 1
        CALL    ENASLT
        LD      HL,($4002)
        JP      (HL)
PRTSTD:
        CALL    PRINTPISTDOUT
        JP      PRINTNLINE

;-----------------------
; LOADROM              |
;-----------------------
LOADROM:
; Will load the ROM directly on the destiantion page in $4000
; Might be slower, but that is what we have so far...
;Get number of bytes to transfer
        LD      A,STARTTRANSFER
        CALL    PIEXCHANGEBYTE
        RET     C
        CP      STARTTRANSFER
        SCF
        RET     NZ
        LD      A,(SLOTRAM1)
        LD      H,40h ; b01000000 = page 1
        CALL    ENASLT
        LD      DE,$4000
        CALL    RECVDATABLOCK
        JR      C,LOADPROGERR
; File load successfully.
; Return C reseted, and A = filetype
LOADROMEND:
        LD      HL,($4002)    ; ROM exec address
        LD      A,ENDTRANSFER
        OR      A             ;Reset C flag
        RET

LOADPROGERR:
        LD      HL,LOADPROGERRMSG
        CALL    PRINT
        SCF
        RET

; OTHER ERROR
PRINTPARMERR:
            LD      HL,PARMERRMSG   ;Parameters invalid. Print Error.
PRINTPARMERR0:
            CALL    PRINT
            RET

;-----------------------

LOADBINPRG:
            DEC     BC
            CALL    SENDPICMD
            JP      C,LOADPROGERR
            CALL    LOADBINPROG
            JP      C,LOADPROGERR
            PUSH    AF
            PUSH    HL
            CALL    PRINTPISTDOUT
            CALL    PRINTNLINE
            POP     HL
            POP     AF
            CP      ENDTRANSFER
            RET     NZ
            JP      (HL)

;-----------------------
; RESET                |
;-----------------------
RESETPROG:
        LD      A,RESET
        CALL    SENDIFCMD
        CALL    SYNCH
        LD      BC,9
        LD      DE,CHKPICONNSTR
        CALL    CHKPICONN
        RET

GETPOINTERPRG:
            DB      "GETPOINTER "
GETPTSTUB:  DB      00
            DB      00

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

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "basic_stdio.asm"
INCLUDE "msxpi_io.asm"

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
            DB      "MSXPi Cloud OS (Client) v0.8.2",13,10
            DB      "(c) Ronivon C. Costa,2017-2018",13,10
            DB      "TYPE HELP for available commands",13,10
            DB      TEXTTERMINATOR

HLPTXT:     DB      "BASIC CHKPICONN CLS PCD PDIR HELP PLOADBIN PLOADR PRUN PRESET PSET PWIFI",13,10,TEXTTERMINATOR

            DB      00

PROMPT:
            DB      "CMD:",TEXTTERMINATOR

LOADERRMSG:
            DB      "Error "
LOADMSG:
            DB      "Loading a program from Raspbery PI ",13,10
            DB      TEXTTERMINATOR

FNOTFOUND:
            DB      "File not Found.",13,10
            DB      TEXTTERMINATOR

PICOMMERR:
            DB      "Communication Error",13,10
            DB      TEXTTERMINATOR

NOCMDMSG:
            DB      "Command not found",13,10
            DB      TEXTTERMINATOR

PARMERRMSG: DB      "Syntax error in command",13,10
            DB      TEXTTERMINATOR

PIOFFLINE:  DB      "Raspberry PI not responding",13,10
            DB      "Verify if server App is running",13,10
            DB      TEXTTERMINATOR

PIONLINE:   DB      "Rasperry PI is online",13,10
            DB      TEXTTERMINATOR

PIAPPMSG:   DB      "Rasperry PI App internal status is "
            DB      TEXTTERMINATOR

MSGPAUSE:   DB      "Enter..."
            DB      TEXTTERMINATOR

LOADPROGERRMSG:
            DB      "Error loading file",13,10,TEXTTERMINATOR


LOADPROGRESS:
            DB      "Loading game...",TEXTTERMINATOR

; ==================================================================
; TABLE OF COMMANDS IMPLEMENTED IN THIS FRONT-END
; ==================================================================

COMMANDLIST:

RUNPICMDSTR:
            DB      "prun",TEXTTERMINATOR
            DW      RUNPICMD

CLSSTR:
            DB      "CLS",TEXTTERMINATOR
            DW      CLS

EXITSTR:

            DB      "BASIC",TEXTTERMINATOR
            DW      EXIT

HELPSTR:
            DB      "HELP",TEXTTERMINATOR
            DW      HELP

LOADROMSTR:
            DB      "PLOADR",TEXTTERMINATOR
            DW      LOADROMPROG

LOADBINSTR:
            DB      "PLOADBIN",TEXTTERMINATOR
            DW      LOADBINPRG

CHKPICONNSTR:
            DB      "CHKPICONN",TEXTTERMINATOR
            DW      CHKPICONN

RESETSTR:
            DB      "PRESET",TEXTTERMINATOR
            DW      RESETPROG

DIRSTR:
            DB      "PDIR",TEXTTERMINATOR
            DW      DIRPROG

PCDCMDSTR:
            DB      "PCD",TEXTTERMINATOR
            DW      PCD

            DB      "PSET",TEXTTERMINATOR
            DW      PSET

            DB      "PWIFI",TEXTTERMINATOR
            DW      PWIFI

ENDOFCMDS:  DB      TEXTTERMINATOR

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
