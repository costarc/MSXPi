;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 1.0                                                             |
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
; 1.0    : I/O re-written to support /wait signal
; 0.1    : initial version
;
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
        LD	HL,CMDS	        ; Table with "_" instructions
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

CALL_MSXPI:
        CALL	EVALTXTPARAM	; Evaluate text parameter
        PUSH	HL
        CALL    GETSTRPNT

CALL_MSXPI_PARM:
; Verify if command has parameters specified
; Examples:
; call msxpi("0,0000,pdir")  -> will not print the output
; call msxpi("1,0000,pdir")  -> will print the output to screen
; call msxpi("2,F000,pdir")  -> will store output in buffer (MSXPICALLBUF - $E3D8)
        PUSH    DE

        CALL    PARMSEVAL
        JR      NC,CALL_MSXPI1
        LD      HL,BUFERRMSG
        CALL    PRINT
        JP      CALL_MSXPIERR2
CALL_MSXPI1:
; Retrieve position with start of command to HL,
; Store buffer address in stack
        EX      (SP),HL
; Save command address to stack
; BC contain lenght of the commands
        PUSH    HL
        CALL    SENDDATABLOCK_OLD
        LD      E,1
        JP      C,CALL_MSXPI2
        
; protocol to detect result of command sent to RPi
        call    PIREADBYTE
        cp      RC_WAIT
        jp      nz,CALL_MSXPIERR
        call    z,CHKPIRDY
        call    PIREADBYTE
        cp      RC_WAIT
        jr      nz,CALL_MSXPI_RC
        call    PIREADBYTE

CALL_MSXPI_RC:
        LD      E,1
        CP      RC_FAILED
        JR      Z,CALL_MSXPISTD
        LD      E,0
        CP      RC_SUCCESS
        JR      Z,CALL_MSXPISTD
        CP      RC_SUCCNOSTD
        JR      Z,CALL_MSXPI2
        LD      HL,txt_undef
        call    PRINT
        jr      CALL_MSXPI2

CALL_MSXPISTD:
; Restore address of string with command
        POP     DE
; Verify if user wants to print STDOUT from RPi
        INC     DE
        LD      A,(DE)
        CP      ','
; User did not specify. Default is to print
        JR      NZ,CALL_MSXPISTDOUT
        DEC     DE
        LD      A,(DE)
        CP      '1'
        JR      Z,CALL_MSXPISTDOUT
        CP      '2'
        JR      Z,CALL_MSXPISAVSTD
        CALL    NOSTDOUT
; Discard buffer addres in stack
        POP     HL
        LD      E,0
        JR      CALL_MSXPI3

CALL_MSXPISTDOUT:
; Discard buffer address
        CALL    PRINTPISTDOUT
        LD      E,0
        JR      CALL_MSXPI3

  
txt_undef: db "Unexpected return code",13,10,0
BUFERRMSG: DB    "Buffer address invalid",13,10,0
CALL_MSXPIBUFER:
        LD      HL,BUFERRMSG
        CALL    PRINT

CALL_MSXPIERR:
        LD      E,1

; return to BASIC
CALL_MSXPI2:
; Discard address of string containing command and buffer address
        POP     HL
CALL_MSXPI3:
CALL_MSXPIERR2:
        POP     HL
; Send RC / return code to BASIC
CALL_MSXPI4:
        LD      HL,ERRFLG
        LD      A,(RAMAD3)
        CALL    WRSLT
        POP     HL
        OR      A
        RET

; This routine will save the RPi data to (STREND)
CALL_MSXPISAVSTD:
; Retrieve buffer address from stack
        POP     DE
        ;CALL    DBGDE
;Save buffer address
        PUSH    DE
        INC     DE
        INC     DE
        CALL    RECVDATABLOCK_OLD

        POP     HL

;Save buffer address again
        PUSH    HL

; Exchange buffer address with end of data received
; to alow SBC and get the size of data received
        EX      DE,HL
        OR      A
        SBC     HL,DE

        POP     DE
        EX      DE,HL

; DE now contain size of data received

;        CALL    DBGDE
;        call    DBGHL
; two first bytes of buffer contain size of data received.
; Decrement by two to return only actual size of buffer
        DEC     DE
        DEC     DE
        LD      (HL),E
        INC     HL
        LD      (HL),D
        LD      E,0
        JR      CALL_MSXPI3

;----------------------------------------
; Call MSXPI BIOS function SENDDATABLOCK|
;----------------------------------------
MSXPISEND:
        CALL	EVALTXTPARAM	; Evaluate text parameter
        PUSH	HL
        CALL    GETSTRPNT
        LD      H,D
        LD      L,E
        CALL    STRTOHEX
        JR      NC,MSXPISEND1
; Buffer address is not valid hex number
        LD      HL,BUFERRMSG
        CALL    PRINT
        POP     HL
        SCF
        RET
MSXPISEND1:
; Save buffer address to later store return code
        PUSH    HL
; First byte of buffer is saved to store return code
        INC     HL
; Next four bytes in buffer must be size of buffer (ASCII for equivalente HEX value)
; store buffer size in BC
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        INC     HL
        LD      D,H
        LD      E,L
        CALL    SENDDATABLOCK_OLD
; Restore buffer address
        POP     HL
; Return return code in 1st buffer position
        LD      (HL),A
        POP     HL
        OR      A
        RET

;----------------------------------------
; Call MSXPI BIOS function RECVDATABLOCK|
;----------------------------------------
MSXPIRECV:
        CALL	EVALTXTPARAM	; Evaluate text parameter
        PUSH	HL
        CALL    GETSTRPNT
        LD      H,D
        LD      L,E
        CALL    STRTOHEX
        JR      NC,MSXPIRECV1
; Buffer address is not valid hex number
        LD      HL,BUFERRMSG
        CALL    PRINT
        POP     HL
        SCF
        RET
MSXPIRECV1:
        LD      D,H
        LD      E,L
        PUSH    HL
; Save first buffer address to store return core
        INC     DE
; Save two memory positions to store buffer size
        XOR     A
        LD      (DE),A
        INC     DE
        LD      (DE),A
        INC     DE
        CALL    RECVDATABLOCK_OLD
; Restore buffer address
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

; ---------------------
; Supporting functions|
;----------------------
GETSTRPNT:
; OUT:
; HL = String Address
; BC = Length
 
        LD      HL,(USR)
        LD      C,(HL)
        LD      B,0
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        RET
 
EVALTXTPARAM:
        CALL	CHKCHAR
        DEFB	"("             ; Check for (
        LD      IX,FRMEVL
        CALL	CALBAS		; Evaluate expression
        LD      A,(VALTYP)
        CP      3               ; Text type?
        JP      NZ,TYPE_MISMATCH
        PUSH	HL
        LD      IX,FRESTR         ; Free the temporary string
        CALL	CALBAS
        POP     HL
        CALL	CHKCHAR
        DEFB	")"             ; Check for )
        RET
 
 
CHKCHAR:
        CALL	GETPREVCHAR	; Get previous basic char
        EX      (SP),HL
        CP      (HL) 	        ; Check if good char
        JR      NZ,SYNTAX_ERROR	; No, Syntax error
        INC     HL
        EX      (SP),HL
        INC     HL		; Get next basic char
     
GETPREVCHAR:
        DEC     HL
        LD      IX,CHRGTR
        JP      CALBAS
 
 
TYPE_MISMATCH:
        LD      E,13
        DB      1
 
SYNTAX_ERROR:
        LD      E,2
        LD      IX,ERRHAND	; Call the Basic error handler
        JP      CALBAS

;---------------------------
CMDS:
 
; List of available instructions (as ASCIIZ) and execute address (as word)
 
        DEFB	"MSXPI",0      ; Print upper case string
        DEFW	CALL_MSXPI
        DEFB    "MSXPISEND",0
        DEFW    MSXPISEND
        DEFB    "MSXPIRECV",0
        DEFW    MSXPIRECV
        DEFB	0               ; No more instructions

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "basic_stdio.asm"
INCLUDE "debug.asm"

fim:    equ $
