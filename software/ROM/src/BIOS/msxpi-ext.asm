;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 1.1                                                             |
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
; 0.2    : Changed the tansfer routines for v1.1 interface
;
; TEXTTERMINATOR: EQU     0
; BDOS:           EQU     $F37D

;---------------------------
; ROM installer
;---------------------------
        db    $fe
        dw    inicio
        dw    fim-romprog+rotina+1
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
        call    CHPUT
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

        org    $4000

romprog:

; ROM-file header
 
        DEFW    $4241,0,CALLHAND,0,0,0,0,0
 
 
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

; ---------------------
; Supporting functions|
;----------------------
GETSTRPNT:
; OUT:
; HL = String Address
; B  = Length
 
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
        LD      IX,FRMEVL
        CALL    CALBAS      ; Evaluate expression
        LD      A,(VALTYP)
        CP      3               ; Text type?
        JP      NZ,TYPE_MISMATCH
        PUSH    HL
        LD      IX,FRESTR         ; Free the temporary string
        CALL    CALBAS
        POP HL
        CALL    CHKCHAR
        DEFB    ")"             ; Check for )
        RET
 
 
CHKCHAR:
        CALL    GETPREVCHAR ; Get previous basic char
        EX      (SP),HL
        CP      (HL)            ; Check if good char
        JR      NZ,SYNTAX_ERROR ; No, Syntax error
        INC     HL
        EX      (SP),HL
        INC     HL      ; Get next basic char
 
GETPREVCHAR:
        DEC     HL
        LD      IX,CHRGTR
        JP      CALBAS
 
 
TYPE_MISMATCH:
        LD      E,13
        DB      1
 
SYNTAX_ERROR:
        LD      E,2
        LD      IX,ERRHAND  ; Call the Basic error handler
        JP      CALBAS
 
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
        
;--------------------------------------------------------------------
; Call MSXPI BIOS function                                          |
;--------------------------------------------------------------------
; Verify if command has STD parameters specified
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
; Registers at this point:
; A  = contain the output required for the command
; B  = contain number of chars in the command
; DE = contain string address of command to send to RPi
; HL = contain buffer address to store data from RPi (if provided by user, otherwise 0)
;
; Routine explanation:
; MSX Send the command to RPi
; RPi reply with a sort message (BLKSIZE) with the following structure:
; | RC | LSB | MSB | Message or DATA |
; RC = RC_FAILED: Pi error. Message available to print
; RC = RC_SUCCESS: Pi processing succeed - data available and there is another block
; RC = RC_TERMINATE: Pi processing succeed - data available and this is last block

        PUSH    AF
        CALL    SENDPICMD
        JR      NC,CALL_MSXPI2
CALL_MSXPI2_ERR:
        POP     AF
CALL_MSXPI2_ERR2:
        LD      A,RC_TXERROR
        LD      (HL),A
        POP     HL
        OR      A
        RET
CALL_MSXPI2:
        POP     AF
        CP      '2'
        JR      Z,CALL_MSXPISAVE

; Will print RPi response to screen
CALL_MSXPI3:
        push    af
        push    hl
        call    READ1BLOCK
        pop     hl
        ld      a,RC_TXERROR
        jr      c,CALL_MSXPI3B1
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
CALL_MSXPI3A:
        pop     af
        push    af
        push    hl
        push    bc
        ld      bc,BLKSIZE
        cp      '0'                      ; should print ?
        call    nz,PRINTPISTDOUT
        pop     hl
        ld      bc,BLKSIZE
        or      a
        sbc     hl,bc
        jr      nc,CALL_MSXPI3B
        pop     hl
        ld      a,(hl)  ; will keep/return to BASIC the existing RC from RPi
CALL_MSXPI3B1:
        pop     bc
        ld      (hl),a
        pop     hl
        or      a
        ret
CALL_MSXPI3B:
        ld      b,h
        ld      c,l
        pop     hl
        push    hl
        push    bc
        call    READ1BLOCK
        pop     bc
        pop     hl
        ld      a,RC_TXERROR
        jr      c,CALL_MSXPI3B1
        jr      CALL_MSXPI3A

READ1BLOCK:
        push    hl
        ld      bc,BLKSIZE
        call    CLEARBUF
        pop     de
        ld      bc,BLKSIZE
        call    RECVDATA
        ret

CALL_MSXPISAVE:
        PUSH    HL
        LD      D,H
        LD      E,L
CALL_MSXPISAVE1:
        PUSH    HL
        LD      BC,BLKSIZE
        CALL    RECVDATA
        POP     HL
        JR      C,CALL_MSXPISERR
        DEC     DE
        LD      A,(DE)
        INC     DE
        OR      A
        JR      NZ,CALL_MSXPISAVE1      ; Read/Save another block
        POP     HL
        POP     HL
        OR      A
        RET
CALL_MSXPISERR:
        RET
        
;----------------------------------------
; Call MSXPI BIOS function SENDDATA     |
;----------------------------------------
_MSXPISEND:
; Send a block (BLKSIZE) )of data to RPi
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
        LD      D,H
        LD      E,L
        LD      BC,BLKSIZE
        CALL    SENDDATA
        POP     HL
        JR      NC,MSXPISEND2
        LD      A,RC_TXERROR
        LD      (HL),A
MSXPISEND2:
; skip the parameters before returning: ("xxxx") = 8 positions to skip
        POP     HL
        OR      A
        RET

;----------------------------------------
; Call MSXPI BIOS function RECVDATA     |
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
        PUSH    HL
        LD      D,H
        LD      E,L
        LD      BC,BLKSIZE
        CALL    RECVDATA
        POP     HL
        JR      NC,MSXPIRECV2
        LD      A,RC_TXERROR
        LD      (HL),A
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
        or        a
        jr        z,GETPOINTERSEXIT
        dec        a
        inc     hl
        inc     hl
        jr        GETPOINTERS1

GETPOINTERSEXIT:
        ld        e,(hl)
        inc     hl
        ld        h,(hl)
        ld        l,e
        ld      (PROCNM),hl
        pop     de
        or      a
        ret

BIOSENTRYADDR:  EQU     $
        DW      _MSXPIVER
        DW      _MSXPI
        DW      _MSXPISEND
        DW      _MSXPIRECV
        DW      RECVDATA
        DW      SENDDATA
        DW      CHKPIRDY
        DW      PIREADBYTE
        DW      PIWRITEBYTE
        DW      PIEXCHANGEBYTE
        DW      SENDPICMD
        DW      PRINT
        DW      PRINTNLINE
        DW      PRINTNUMBER
        DW      PRINTDIGIT
        DW      PRINTPISTDOUT
        

; ================================================================
; Text messages used in the loader
; ================================================================

MSXPIVERSION:
        DB      13,10,"MSXPi BIOS v1.1."
BuildId: DB "20230404.417"
        DB      13,10
        DB      "    RCC (c) 2017-2023",0
        DB      "Commands available:",13,10
        DB      "MSXPI MSXPISEND MSXPIRECV MSXPIVER ",13,10,0

PIOFFLINE:
        DB      "Communication Error",13,10,0

PIONLINE:
        DB      "Raspberry Pi is online",13,10,0

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

        DB      "GETPOINT",0
        DW      _GETPOINTERS

        DB      "MSXPISND",0
        DW      _MSXPISEND

        DB      "MSXPIRCV",0
        DW      _MSXPIRECV

        DB      "MSXPI",0
        DW      _MSXPI

ENDOFCMDS:
        DB      00

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "putchar-msxdos.asm"

fim:    equ $
buf:    equ $
