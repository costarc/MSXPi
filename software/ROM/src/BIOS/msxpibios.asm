;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 1.3                                                             |
;|                                                                           |
;| Copyright (c) 2015-2025 Ronivon Candido Costa (ronivon@outlook.com)       |
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
; 0.9.1  : Changes to support new transfer logic
; 1.1    : Changes to support new transfer routines
; 1.2    : Removed MSX-DOS 1 Kernel; Replaced by MSXPio BIOS 
				 
    ORG         $4000
; ### ROM header ###

    db "AB"     ; ID for auto-executable ROM
    dw 0000     ; Main program execution address - no used becuase it is CALL handler
    dw CALLHAND ; STATEMENT
    dw 0000     ; DEVICE
    dw 0000     ; TEXT
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
        
; Now that it processed the parameters, check if Buffer address was passed
; If not passed, will allocate a buffer of size BLOCKSIZE at the top of the ram
; Output: IX = HL = Buffer address
        PUSH    AF
        LD      A,H
        OR      L
        JR      NZ,CALL_BUFFERPASSED
        LD      HL,(HIMEM)
        PUSH    BC
        LD      BC,BLKSIZE
        OR      A               ; reset C to avoid carry being used in the SBC command
        SBC     HL,BC           ; Allocate Buffer on top of RAM
        DEC     HL
        DEC     HL
        DEC     HL
        POP     BC
CALL_BUFFERPASSED:
        PUSH    HL
        POP     IX              ; IX = WORK AREA ( BYTES )

CALL_MSXPI1:
; Registers at this point:
; A  = contain the output required for the command
; B  = contain number of chars in the command
; DE = contain string address of command to send to RPi
; HL = IX = contain buffer address to store data from RPi (if provided by user, otherwise 0)
;
; Routine explanation:
; MSX Send the command to RPi
; RPi reply with data block (BLKSIZE) with the following structure:
; | RC | LSB | MSB | DATA |
; RC = RC_FAILED: Pi error. Message available to print
; RC = RC_READY: Pi processing succeed - data available and there is another block
; RC = RC_SUCCESS : Pi processing succeed - data available and this is last block
; RC = RC_TXERROR : Error in the connection with RPi
;
; Send commands (in CALL parameters) to RPi
        
        PUSH    HL
        CALL    SENDPICMD
        POP     DE
        JR      NC,CALL_MSXPI3
CALL_MSXPI2_ERR:
        POP     AF
CALL_MSXPISERR:
        LD      A,RC_TXERROR
        LD      (HL),A
        POP     HL
        OR      A
        RET
CALL_MSXPI3:
        POP     AF
        CP      '2'
        JR      Z,CALL_MSXPISAVE
        LD      C,A
; Will print RPi response to screen
CALL_PRINTBUF:
        ld      a,c                 ; stdout option
        push    af
        ld      bc,BLKSIZE
        call    CLEARBUF
        push    de
        ld      bc,BLKSIZE
        call    RECVDATA
        pop     hl
        ld      a,RC_TXERROR
        jr      c,CALL_MSXPI2_ERR
        pop     af
        push    hl
        push    af
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      d,h
        ld      e,l
        pop     af
        pop     hl
        push    af
        push    hl
        ld      bc,BLKSIZE
        cp      '0'                      ; should print ?
        call    nz,PRINTPISTDOUT
        pop     de
        pop     af
        ld      c,a
        ld      a,(de)
        cp      RC_READY
        jr      z,CALL_PRINTBUF
        pop     hl
        or      a
        ret

CALL_MSXPISAVE:
        PUSH    DE
        LD      BC,BLKSIZE
        CALL    RECVDATA
        POP     HL                      ; HL = Start of buffer, DE=Address next block
        JR      C,CALL_MSXPISERR
        LD      A,(HL)
        CP      RC_READY
        JR      NZ,CALL_MSXPISAVEXIT    ; No more data to trasnfer
CALL_MSXPISAVE2:
        PUSH    DE
        LD      BC,BLKSIZE
        CALL    RECVDATA
        POP     HL                      ; HL = Start of buffer, DE=Address next block
        JR      C,CALL_MSXPISERR
        LD      A,(HL)
        LD      (IX + 0),A              ; Update return code
        CALL    SUMBLOCKSIZES           ; Add block size to full data block size
        DEC     DE
        DEC     DE
        DEC     DE
        PUSH    DE
        LD      BC,BLKSIZE
        CALL    SHIFTDATA
        POP     DE
        LD      A,(IX + 0)
        CP      RC_READY
        JR      Z,CALL_MSXPISAVE2
CALL_MSXPISAVEXIT:
        POP     HL
        OR      A
        RET

; SUMBLOCKSIZES
; Add size of each block to the block address
; Note that it the data to receive is too big,
; it will corrupt the memory and crash the program
; This routines are not supposed to transfer huge files.
; Inputs:
; IX = Address of total data size (will be updated in this routine)
; HL = Address of current block
; Changed registries: AF, BC
SUMBLOCKSIZES:
        PUSH    HL
        INC     HL
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        LD      L,(IX + 1)
        LD      H,(IX + 2)
        ADD     HL,BC
        LD      (IX + 1),L
        LD      (IX + 2),H
        POP     HL
        RET
        
SHIFTDATA:
        LD      D,H
        LD      E,L
        INC     HL
        INC     HL
        INC     HL
        LDIR
        RET                 ; DE = Next block address
		
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
        EX      DE,HL
        JR      NC,MSXPISEND1
; Buffer address is not valid hex number
        LD      HL,BUFERRMSG
        CALL    PRINT
        POP     HL
        OR      A
        RET
MSXPISEND1:
; Save buffer address to later store return code
        PUSH    DE
        LD      BC,BLKSIZE
        CALL    SENDDATA
        POP     DE
        JR      NC,MSXPISEND2
        LD      A,RC_TXERROR
        LD      (DE),A
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
        EX      DE,HL
        JR      NC,MSXPIRECV1
; Buffer address is not valid hex number
        LD      HL,BUFERRMSG
        CALL    PRINT
        POP     HL
        OR      A
        RET
MSXPIRECV1:
        PUSH    DE
        LD      BC,BLKSIZE
        CALL    RECVDATA
        POP     DE
        JR      NC,MSXPIRECV2
        LD      A,RC_TXERROR
        LD      (DE),A
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

BIOSENTRYADDR:   EQU     $
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
        DB      13,10,"MSXPi BIOS v1.3"
BuildId: DB ".20251016.005"
        DB      13,10
        DB      "    RCC (c) 2015-2025",0
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

        DB      "GETPOINTER",0
        DW      _GETPOINTERS

        DB      "MSXPISEND",0
        DW      _MSXPISEND

        DB      "MSXPIRECV",0
        DW      _MSXPIRECV

        DB      "MSXPI",0
        DW      _MSXPI

ENDOFCMDS:
        DB      00

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "putchar_msxdos.asm"
fim:    equ $
buf:    equ $
DEFS	$8000-$,0