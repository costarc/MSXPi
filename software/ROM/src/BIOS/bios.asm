;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.9.1                                                           |
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
; 0.1    : initial version
; 0.9.1  : Changes to supoprt new transfer logic

TEXTTERMINATOR: EQU 0
BDOS:           EQU $F37D
PageSize:       EQU $4000   ; 16kB

        org     $4000
; ### ROM header ###

    db "AB"     ; ID for auto-executable ROM
    dw 0000     ; Main program execution address - no used becuase it is CALL handler
    dw CALLHAND ; STATEMENT
    dw 0        ; DEVICE
    dw 0        ; TEXT
    dw 0,0,0    ; Reserved

;---------------------------
 
; General BASIC CALL-instruction handler
CALLHAND:
 
    PUSH    HL
    LD  HL,CALL_TABLE         ; Table with "_" instructions
.CHKCMD:
    LD  DE,PROCNM
.LOOP:  LD  A,(DE)
    CP  (HL)
    JR  NZ,.TONEXTCMD   ; Not equal
    INC DE
    INC HL
    AND A
    JR  NZ,.LOOP    ; No end of instruction name, go checking
    LD  E,(HL)
    INC HL
    LD  D,(HL)
    POP HL      ; routine address
    CALL    GETPREVCHAR
    CALL    .CALLDE     ; Call routine
    AND A
    RET
 
.TONEXTCMD:
    LD  C,0FFH
    XOR A
    CPIR            ; Skip to end of instruction name
    INC HL
    INC HL      ; Skip address
    CP  (HL)
    JR  NZ,.CHKCMD  ; Not end of table, go checking
    POP HL
        SCF
    RET
 
.CALLDE:
    PUSH    DE
    RET
  
GETSTRPNT:
; OUT:
; HL = String Address
; B  = Lenght
 
        LD      HL,($F7F8)
        LD      B,(HL)
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        RET
 
EVALTXTPARAM:
    CALL    CHKCHAR
    DEFB    "("             ; Check for (
    LD  IX,FRMEVL
    CALL    CALBAS      ; Evaluate expression
        LD      A,(VALTYP)
        CP      3               ; Text type?
        JP      NZ,TYPE_MISMATCH
        PUSH    HL
        LD  IX,FRESTR         ; Free the temporary string
        CALL    CALBAS
        POP HL
    CALL    CHKCHAR
    DEFB    ")"             ; Check for )
        RET
 
 
CHKCHAR:
    CALL    GETPREVCHAR ; Get previous basic char
    EX  (SP),HL
    CP  (HL)            ; Check if good char
    JR  NZ,SYNTAX_ERROR ; No, Syntax error
    INC HL
    EX  (SP),HL
    INC HL      ; Get next basic char
 
GETPREVCHAR:
    DEC HL
    LD  IX,CHRGTR
    JP      CALBAS
 
 
TYPE_MISMATCH:
        LD      E,13
        DB      1
 
SYNTAX_ERROR:
        LD      E,2
    LD  IX,ERRHAND  ; Call the Basic error handler
    JP  CALBAS
 
;================================================================
; call Commands start here
; ================================================================

;-----------------------
; call MSXPIVER        |
;-----------------------
_MSXPIVER:
        push    hl
        ld      hl,MSXPIVERSION
        call    PRINT
        pop     hl
        ret
        
;-----------------------
; call MSXPISTATUS     |
;-----------------------
_MSXPISTATUS:
        PUSH    HL
        LD      BC,4
        LD      DE,PINGCMD
        CALL    SENDPICMD
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        ld      hl,PIOFFLINE
        JR      C,PRINTSTATUSMSG
        CP      RC_SUCCNOSTD
        jr      NZ,PRINTSTATUSMSG
        ld      hl,PIONLINE
PRINTSTATUSMSG:
        call      PRINT
        POP       HL
        ret


;--------------------------------------------------------------------
; Call MSXPI BIOS function                                          |
;--------------------------------------------------------------------
; Verify is command has STD parameters specified
; Examples:
; call mspxi("pdir")  -> will print the output
; call mspxi("0,pdir")  -> will not print the output
; call msxpi("1,pdir")  -> will print the output to screen
; call msxpi("2,F000,pdir")  -> will store output in buffer (MSXPICALLBUF - $E3D8)       
_MSXPI:
        CALL    EVALTXTPARAM    ; Evaluate text parameter
        PUSH    HL
        CALL    GETSTRPNT
        EX      DE,HL
        CALL    PARMSEVAL
        
CALL_MSXPI1:
; At this point:
; HL = contain buffer address to store data from RPi
; DE = contain string address of command to send to RPi
; A  = contain the output required for the command
; B  = contain number of chars in the command
;
        PUSH    AF
        PUSH    HL
        LD      C,B
        LD      B,0
        LD      H,D
        LD      L,E
        CALL    SENDPICMD
        JR      NC,CALL_MSXPI_LOOP
        POP     HL
        POP     AF
        POP     HL
        SCF
        RET

CALL_MSXPI_LOOP:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        cp      RC_WAIT
        jr      NZ,CALL_MSXPI_RELEASED
        call    CHKPIRDY
        JR      CALL_MSXPI_LOOP

CALL_MSXPI_RELEASED: 
        CP      RC_FAILED
        JR      Z,CALL_MSXPISTD
        CP      RC_SUCCESS
        JR      Z,CALL_MSXPISTD
        POP     HL
        POP     AF
        CP      1
        JR      NZ,CALL_MSXPIERR2
        LD      A,RC_CONNERR
        LD      (HL),A                  ; Store return code in buffer
CALL_MSXPIERR2:
        POP     HL
        OR      A
        RET

CALL_MSXPISTD:
                                        ; Restore address of buffer and stdout option
        POP     DE     ; buffer address
        POP     AF     ; stdout option

                                        ; Verify if user wants to print STDOUT from RPi
        CP      '1'
                                        ; User did not specify. Default is to print
        JR      Z,CALL_MSXPISTDOUT
        CP      '2'
        JR      Z,CALL_MSXPISAVSTD

        CALL    NOSTDOUT
        LD      (DE),A
        POP     HL
        OR      A
        RET

CALL_MSXPISTDOUT:
        PUSH    DE
        CALL    PRINTPISTDOUT
        POP     DE
        LD      (DE),A
        POP     HL
        OR      A
        RET

                                        ; This routine will save the RPi data to (STREND)
CALL_MSXPISAVSTD:
        PUSH    DE
        INC     DE
        INC     DE
        INC     DE
        CALL    RECVDATABLOCK
        POP     HL
        LD      (HL),A                  ; return code
        INC     HL
        LD      (HL),C                  ; Return buffer size to BASIC in first two 
                                        ; positions of buffer
        INC     HL
        LD      (HL),B
        POP     HL
        OR      A
        RET

;----------------------------------------
; Call MSXPI BIOS function SENDDATABLOCK|
;----------------------------------------
_MSXPISEND:
; retrive CALL parameters from stack (second position in stack)
        CALL    EVALTXTPARAM    ; Evaluate text parameter
        PUSH    HL
        CALL    GETSTRPNT
        CALL    STRTOHEX
        JR      NC,MSXPISEND1
; Buffer address is not valid hex number
        LD      HL,BUFERRMSG
        CALL    PRINT
        POP     HL
        OR      A
        RET
MSXPISEND1:
; Save buffer address to later store return code
        PUSH    HL
; First byte of buffer is saved to store return code
        INC     HL
; Second two bytes in buffer must be size of buffer
; store buffer size in BC
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        INC     HL
        LD      D,H
        LD      E,L
        CALL    SENDDATABLOCK
; skip the parameters before returning: ("xxxx") = 8 positions to skip
        POP     HL
        LD      (HL),A
        POP     HL
        OR      A
        RET

;----------------------------------------
; Call MSXPI BIOS function RECVDATABLOCK|
;----------------------------------------
_MSXPIRECV:
        CALL    EVALTXTPARAM    ; Evaluate text parameter
        PUSH    HL
        CALL    GETSTRPNT
        CALL    STRTOHEX
        JR      NC,MSXPIRECV1
; Buffer address is not valid hex number
        LD      HL,BUFERRMSG
        CALL    PRINT
        POP     HL
        OR      A
        RET
MSXPIRECV1:
        LD      D,H
        LD      E,L
        PUSH    HL
; Save first buffer address to store return core
        INC     DE
; Save two memory positions to store buffer size later
        XOR     A
        LD      (DE),A
        INC     DE
        LD      (DE),A
        INC     DE
        CALL    RECVDATABLOCK
        POP     HL
; Store return code into 1st position in buffer
        LD      (HL),A
        JR      C,MSXPIRECV2
        INC     HL
; Return buffer size to BASIC in first two positions of buffer
        LD      (HL),C
        INC     HL
        LD      (HL),B
MSXPIRECV2:
        POP     HL
        OR      A
        RET

;-----------------------
; call GETPOINTERS      |
;-----------------------
; Return in hl the Entry address of th routine indexed in A
; Input:
;  A = Routine index
; Output:
;  (sp) = address of the given routine
; Modify: af,hl
;
_GETPOINTERS:
        push    de
        ld      hl,BIOSENTRYADDR

GETPOINTERS1:
        or      a
        jr      z,GETPOINTERSEXIT
        dec     a
        inc     hl
        inc     hl
        jr      GETPOINTERS1

GETPOINTERSEXIT:
        ld      e,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,e
        ld      (PROCNM),hl
        pop     de
        or      a
        ret

;-----------------------
; call MSXPISYNC       |
;-----------------------
_MSXPISYNC:
    PUSH    HL
    CALL    PSYNC
    LD      HL,PSYNC_ERROR
    JR      C,_MSXPSYNC_EXIT
    LD      HL,PSYNC_RESTORED

_MSXPSYNC_EXIT:
    CALL    PRINT
    POP     HL
    OR      A
    RET

BIOSENTRYADDR:  EQU     $
        DW      _MSXPIVER
        DW      _MSXPISTATUS
        DW      _MSXPI
        DW      _MSXPISEND
        DW      _MSXPIRECV
        DW      _MSXPISYNC
        DW      RECVDATABLOCK
        DW      SENDDATABLOCK
        DW      READDATASIZE
        DW      SENDDATASIZE
        DW      CHKPIRDY
        DW      PIREADBYTE
        DW      PIWRITEBYTE
        DW      PIEXCHANGEBYTE
        DW      SENDIFCMD
        DW      SENDPICMD
        DW      PRINT
        DW      PRINTNLINE
        DW      PRINTNUMBER
        DW      PRINTDIGIT
        DW      PRINTPISTDOUT
        DW      PSYNC

; ================================================================
; Text messages used in the loader
; ================================================================

MSXPIVERSION:
        DB      "MSXPi ROM v0.9.1 "
build:  DB      "20200820.000"
        DB      13,10
        DB      "(c) Ronivon Costa,2017-2020",13,10,10
        DB      "Commands available:",13,10
        DB      "MSXPI MSXPISEND MSXPIRECV MSXPISTATUS MSXPISYNC MSXPIVER ",13,10,0
MSXPISKP:
        DB       "Press P to boot MSXPi DOS",13,10
        DB      00

PIOFFLINE:
        DB      "Communication Error",13,10,0

PIONLINE:
        DB      "Rasperry PI is online",13,10,0

PIWAITMSG:
        DB      13,10,"Waiting Pi boot. P to skip",13,10,0

BUFERRMSG:
        DB    "Parameters or Buffer address invalid",13,10,0

PSYNC_RESTORED:
        DB    "Communication restored",13,10,0

PSYNC_ERROR:
        DB    "Could not restore communication ",13,10,0


; ================================================================
; Table of Commands available/implemented
; ================================================================

CALL_TABLE:

        DB      "MSXPIVER",0
        DW      _MSXPIVER

        DB      "MSXPISTATUS",0
        DW      _MSXPISTATUS

        DB      "GETPOINTERS",0
        DW      _GETPOINTERS

        DB      "MSXPISEND",0
        DW      _MSXPISEND

        DB      "MSXPIRECV",0
        DW      _MSXPIRECV

        DB      "MSXPISYNC",0
        DW      _MSXPISYNC

        DB      "MSXPI",0
        DW      _MSXPI

ENDOFCMDS:
        DB      00

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "basic_stdio.asm"
INCLUDE "msxpi_io.asm"

ds PageSize - ($ - 4000h),255   

