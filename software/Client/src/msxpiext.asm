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
; 0.1    : initial version
; 0.9.0  : Changes to supoprt new transfer logic

TEXTTERMINATOR: EQU     0
BDOS:           EQU     $F37D

;---------------------------
; ROM installer
;---------------------------
		db	$fe
		dw	inicio
        dw	fim-romprog+rotina+1
        dw  inicio

        org     $b000

inicio:
        jr      inicio0
returncode:
        db      0
inicio0:
        ld      hl,msgstart
        call    localprint

        ld      c,040H
        call    PG1RAMSEARCH

        ei

        ld      hl,msgramnf
        jr      c,printmsg

instcall:

        push    af
        call    ramcheck
        pop     af

        ld      hl,msgramnf
        jr      nz,printmsg

        push    af
        ld      hl,msgdoing
        call    localprint
        pop     af

        push    af
        call    relocprog
        pop     af

        and     %00000011
        ld      hl,SLTATR
        ld      de,16
        or      a
        jr      z,setcall2
        ld      b,a

setcall1:
        add     hl,de
        djnz    setcall1

setcall2:
        xor     a
        set     5,a
        inc     hl
        ld      (hl),a

        ld      hl,msgcallhlp
        call    localprint

; Reserve RAM for MSXPI commands
        ld      hl,MSXPICALLBUF
        ld      (HIMEM),hl
        ret

printmsg:
        call    localprint
        ret



relocprog:
        ld de, rotina
        ld hl, romprog
        ld bc, fim-romprog+1

relocprog1:
        push    af
        push    bc
        push    de
        push    hl
        ld      c,a
        ld      a,(de)
        ld      e,a
        ld      a,c
        call    WRSLT
        pop     hl
        pop     de
        pop     bc
        pop     af
        inc     hl
        inc     de
        dec     bc
        push    af
        ld      a,b
        or      c
        jr      z,relocfinish
        pop     af
        jr      relocprog1

    relocfinish:
        pop     af
        ret

msgstart:   db      "Search for ram in $4000",13,10,0
msgramnf:   db      "ram not found",13,10,0
msgdoing:   db      "Installing MSXPi extension...",13,10,0
msgcallhlp: db      "Installed. Use ",13,10
            db      "CALL MSXPI(",$22,"<option,><buffer,><commmand>",$22,") to run MSXPi Commands",13,10
            db      "CALL MSXPISEND(",$22,"<buffer>",$22,") to send data to RPi",13,10
            db      "CALL MSXPIRECV(",$22,"<buffer>",$22,") to read data from RPi",13,10
            db      "flag: 0=no screen output, 1=screen output(default), 2=store output in buffer", 13,10
            db      "buffer = valid hexadecimal number (4 digits)"
            db      13,10,0

ramcheck:
        push    af
        ld      e,$aa
        ld      hl,$4000
        call    WRSLT
        pop     af
        ld      hl,$4000
        call    RDSLT
        cp      $aa     ;set Z flag if found ram
        ret

localprint:
        ld      a,(hl)
		or      a
		ret     z
		call	CHPUT
		inc     hl
		jr      localprint


PG1RAMSEARCH:
        LD      HL,EXPTBL
        LD      B,4
        XOR     A
PG1RAMSEARCH1:
        AND     03H
        OR      (HL)
PG1RAMSEARCH2:
        PUSH    BC
        PUSH    HL
        LD      H,C
PG1RAMSEARCH3:
        LD      L,10H
PG1RAMSEARCH4:
        PUSH    AF
        CALL    RDSLT
        CPL
        LD      E,A
        POP     AF
        PUSH    DE
        PUSH    AF
        CALL    WRSLT
        POP     AF
        POP     DE
        PUSH    AF
        PUSH    DE
        CALL    RDSLT
        POP     BC
        LD      B,A
        LD      A,C
        CPL
        LD      E,A
        POP     AF
        PUSH    AF
        PUSH    BC
        CALL    WRSLT
        POP     BC
        LD      A,C
        CP      B
        JR      NZ,PG1RAMSEARCH6
        POP     AF
        DEC     L
        JR      NZ,PG1RAMSEARCH4
        INC     H
        INC     H
        INC     H
        INC     H
        LD      C,A
        LD      A,H
        CP      40H
        JR      Z,PG1RAMSEARCH5
        CP      80H
        LD      A,C
        JR      NZ,PG1RAMSEARCH3
PG1RAMSEARCH5:
        LD      A,C
        POP     HL
        POP     HL
        RET
	
PG1RAMSEARCH6:
        POP     AF
        POP     HL
        POP     BC
        AND     A
        JP      P,PG1RAMSEARCH7
        ADD     A,4
        CP      90H
        JR      C,PG1RAMSEARCH2
PG1RAMSEARCH7:
        INC     HL
        INC     A
        DJNZ    PG1RAMSEARCH1
        SCF
        RET

;---------------------------

rotina:

        org	$4000

romprog:

; ROM-file header
 
        DEFW    $4241,0,CALLHAND,0,0,0,0,0
 
 
;---------------------------
 
; General BASIC CALL-instruction handler
CALLHAND:
 
        PUSH    HL
        LD	HL,CALL_TABLE	        ; Table with "_" instructions
.CHKCMD:
        LD	DE,PROCNM
.LOOP1:
        LD	A,(DE)
        CP	(HL)
        JR	NZ,.TONEXTCMD	; Not equal
        INC	DE
        INC	HL
        AND	A
        JR	NZ,.LOOP1	; No end of instruction name, go checking
        LD	E,(HL)
        INC	HL
        LD	D,(HL)
        POP	HL		; routine address
        CALL	GETPREVCHAR
        CALL	.CALLDE		; Call routine
        AND	A
        RET
 
.TONEXTCMD:
        LD	C,0FFH
        XOR	A
        CPIR			; Skip to end of instruction name
        INC	HL
        INC	HL		; Skip address
        CP	(HL)
        JR	NZ,.CHKCMD	; Not end of table, go checking
        POP	HL
        SCF
        RET
 
.CALLDE:
        PUSH	DE
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
; call MSXPISYNCH      |
;-----------------------
_MSXPISYNCH:
    PUSH    HL
    CALL    PSYNCH
    LD      HL,PSYNCH_ERROR
    JR      C,_MSXPSYNCH_EXIT
    LD      HL,PSYNCH_RESTORED

_MSXPSYNCH_EXIT:
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
        DW      _MSXPISYNCH
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
        DW      SYNCH
        DW      PSYNCH

; ================================================================
; Text messages used in the loader
; ================================================================

MSXPIVERSION:
        DB      13,10,"MSXPi Hardware Interface v1.1",13,10
        DB      "MSXPi ROM v0.9.1",13,10
        DB      "      Build "
build:  DB      "20200817.00000"
        DB      13,10
        DB      "(c) Ronivon Costa,2017-2020",13,10,10
        DB      "Commands available:",13,10
        DB      "MSXPI MSXPISEND MSXPIRECV MSXPISTATUS MSXPISYNCH MSXPIVER ",13,10
        DB      00

PIOFFLINE:
        DB      "Communication Error",13,10,0

PIONLINE:
        DB      "Rasperry PI is online",13,10,0

PIWAITMSG:
        DB      13,10,"Waiting Pi boot. P to skip",13,10,0

BUFERRMSG:
        DB    "Parameters or Buffer address invalid",13,10,0

PSYNCH_RESTORED:
        DB    "Communication restored",13,10,0

PSYNCH_ERROR:
        DB    "Could not restore communication ",13,10,0

;---------------------------
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

        DB      "MSXPISYNCH",0
        DW      _MSXPISYNCH

        DB      "MSXPI",0
        DW      _MSXPI

ENDOFCMDS:
        DB      00

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "basic_stdio.asm"

fim:    equ $
