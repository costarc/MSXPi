;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.7                                                            |
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
; 0.7    : Moved BIOS functions to top of RAM
;          Added ID to facilitte localization by inter-slot callers/programs.
;           ID terminates in zero.
;          Added the 4 BIOS entry points to the ROM as headers, right after
;           the ID. Each entry is composed of two bytes (call address).
;           function is composed of 2 bytes (addres).
;          Added slot search routines for pages 1,2,3
; 0.6d   : Changed header of ROM to: <size><exec address><rom binary>
;          Size and exec address are two bytes long each.
; 0.6c   : Initial version commited to git
;

MODEL4b:        EQU     0

MSXLOADERADDR:  equ     $C000

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

START_CODE1:    EQU $
;----------------------------------------
; ROM HEADER
;----------------------------------------

        org     $4000
        dw      $4241           ; ID
        dw      ROM_START       ; INIT
        dw      CALL_CHECK      ; CALL STATEMENT TO SHOW VERSION
        dw      $0000           ; DEVICE
        dw      $0000           ; TEXT
        db      0,0,0,0,0,0     ; RESERVED

;----------------------------------------
; MSXPi ID and BIOS function entry points
;----------------------------------------

; This table's purpose is to provide the entry addresses of
; the BIOS functions. The ID can be used to locate the slot where
; the BIOS is allocated, and the addresses pickedup from the table.
;-------------------------------------------------------------------
        DB      "MSXPi"         ; ID is fixed string MSXPi, 5 chars long
        DB      0,7,0           ; Version is thee bytes long: Major, Minor, Review
        DW      READBYTE        ; Two bytes long, READBYTE function
        DW      TRANSFBYTE      ; Two bytes long, TRANSFBYTE function
        DW      CHKPIRDY        ; Two bytes long, CHKPIRDY function
        DW      SENDIFCMD       ; Two bytes long, SENDIFCMD function
        DW      PG1RAMSEARCH    ; Search slot where $4000 is RAM
        DW      PG2RAMSEARCH    ; Search slot where $8000 is RAM
        DW      PG3RAMSEARCH    ; Search slot where $C000 is RAM
        DW      MYSLOTID        ; Search slot where my program is running
        DW      MYEXPTBL        ; Get my EXPTBL entry

; ==================================================================
; BASIC I/O FUNCTIONS STARTS HERE - BIOS
; These are the lower level I/O routines available, and must match
; the I/O functions implemented in the CPLD.
; Other than using these functions you will have to create your
; own commands, using OUT/IN directly to the I/O ports.
; ==================================================================


IF MODEL4b
    INCLUDE    "msxpi_io_4bits.asm"
ELSE
    INCLUDE    "msxpi_io.asm"
ENDIF

;============================================
; Print titLe and version upon boot
;============================================

ROM_START:
        LD      HL,MSXPIVERSTR
        CALL    PRINT
        RET

;============================================
; Rotina de chaveamento de memória
;============================================

; Read a byte from RAM Page 3
; HL = address to read
; Output byte is in A
SLTRDBYTE:
        IN      A,($A8)         ; get current memory map
        AND     %11000000       ; Keeps only pages 3 of RAM
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    RDSLT
        RET

;Write a byte from RAM Page 3
;A = byte to write
;HL = address to write
SLTWRBYTE:
        LD      E,A
        IN      A,($A8)         ; get current memory map
        AND     %11000000       ; Keeps only pages 3 of RAM
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    WRSLT
        RET

SLCALLPROG:
        IN      A,($A8)         ; get current memory map
        AND     %11000000       ; Keeps only pages 3 of RAM
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        LD      C,0
        LD      B,A
        PUSH    BC
        POP     IY
        PUSH    HL
        POP     IX
        CALL    CALSLT
        RET

RAMCHK:
        CALL    SLTRDBYTE
        PUSH    AF
        LD      A,$AA
        CALL    SLTWRBYTE          ; WRITE A TEST BYTE TO MEMORY
        XOR     A
        CALL    SLTRDBYTE
        LD      B,A
        POP     AF
        PUSH    BC
        CALL    SLTWRBYTE          ; WRITE A TEST BYTE TO MEMORY
        POP     AF
        CP      $AA
        RET     Z           ; Memory found Z set
        SCF                 ; Memory not found,C set
        RET

;============================================

CALL_CHECK:
        PUSH    HL

;       HL is loaded with parameters sent by CALL
        LD      HL,PROCNM

;       DE is loaded with the available commands in this ROM
        LD      DE,STR_CALL_CMD

        CALL    PARSECMD        ;C set ==> cmd not found
        JR      C,ENDFAIL       ;Command not found

ENDPSUCCESS:
        JP      (HL)            ;Execute command sent by CALL

ENDFAIL:
        POP     HL
        RET

; ================================================================
; CALL Commands start here
; ================================================================

;-----------------------
; CALL MSXPIVER        |
;-----------------------
MSXPIVER:
        CALL    ROM_START
        POP     HL
        XOR     A
        RET

;-----------------------
; CALL MSXPIHELP       |
;-----------------------
MSXPIHELP:
        LD      HL,MSXPIHELPSTR
        CALL    PRINT
        POP     HL
        XOR     A
        RET

;-----------------------
; CALL MSXPISTATUS     |
;-----------------------
MSXPISTATUS:

; check if Pi is responding
        CALL    CHKPIRDY
        LD      HL,PIOFFLINESTR

; Pi App is not available, print error message
        JR      C,PRINTSTATUSMSG

; Pi App is online
        LD      HL,PIONLINESTR

PRINTSTATUSMSG:
        CALL    PRINT
        POP     HL

; reset flag C and restore HL to return to BASIC
        XOR     A
        RET

;-----------------------
; CALL MSXPILOAD       |
;-----------------------
MSXPILOAD:
        LD      HL,MSXPISTR
        CALL    PRINT

        CALL    CHKPIRDY
        JR      C,LOADERERR_A

        LD      HL,MSXLOADERADDR
        CALL    RAMCHK
        JR      C,MSXPILOADERR      ;RAM not found, cannot continue

RELOCLOADER:

        LD      HL,FOUNDRAMMSG
        CALL    PRINT

        LD      HL,RELOCMSG
        CALL    PRINT

        LD      DE,END_CODE1
        LD      HL,MSXLOADERADDR
        LD      BC,END_CODE2 - START_CODE2

RECLOADLP0:
        LD      A,(DE)
        PUSH    BC
        PUSH    DE
        PUSH    HL
        CALL    SLTWRBYTE
        POP     HL
        POP     DE
        POP     BC
        INC     HL
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,RECLOADLP0

        LD      HL,JUMPMSG
        CALL    PRINT

        LD      HL,MSXLOADERADDR
        CALL    SLCALLPROG
        POP     HL
        XOR     A
        RET


; Page switch should be placed here to find RAM
; and to enable RAM in $C000

; <code here>

; After page switch allocate RAM on page 3,
; the code can be moved.

MSXPILOADERR:
        LD      HL,RAMNOTFOUNDMSG
        CALL    PRINT
        POP     HL
        SCF
        RET

LOADERERR_A:
        LD      HL,PIOFFLINESTR
        CALL    PRINT
        POP     HL
        RET

;-----------------------
; CALL MEMMAP          |
;-----------------------

MEMMAP:
        LD      HL,PG0MSG
        IN      A,($A8)
        AND     %00000011
        CALL    TESTRAM0
        LD      HL,PG1MSG
        IN      A,($A8)
        AND     %00001100
        RRCA
        RRCA
        CALL    TESTRAM0
        LD      HL,PG2MSG
        IN      A,($A8)
        AND     %00110000
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    TESTRAM0
        LD      HL,PG3MSG
        IN      A,($A8)
        AND     %11000000
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    TESTRAM0
        POP     HL
        XOR     A
        RET

TESTRAM0:
        LD      B,A
        CALL    PRINT
        LD      A,B
        CALL    PRINTNUMBER
        CALL    PRINTNLINE
        RET

PG0MSG: DB      "Page 0 is on slot ",0
PG1MSG: DB      "Page 1 is on slot ",0
PG2MSG: DB      "Page 2 is on slot ",0
PG3MSG: DB      "Page 3 is on slot ",0

; ================================================================
; Verify if command in CALL is in our list
; ================================================================

;Parse a command string in DE
;Return Command address in HL, and paramters address in DE
;Return C set if command not found or format not valid

PARSECMD:
PARSE0:
        LD      A,(DE)
        OR      A
        SCF                     ;flag error for command not found
        RET     Z               ;End of commands
PARSE1:
        PUSH    HL
        LD      A,(DE)
PARSE2:
        CP      (HL)
        JR      NZ,PARSE3
        INC     HL
        INC     DE
        LD      A,(DE)
        OR      A
        JR      NZ,PARSE2       ;This command has more characters to verify

FOUNDCMD:
        POP     BC              ;DISCARD STACK WITH START OF BUFF
        PUSH    HL              ;Save current BUF position, might be a parameter
        INC     DE
        LD      A,(DE)
        LD      L,A
        INC     DE
        LD      A,(DE)
        LD      H,A
        POP     DE              ;Return Address for parameters, if any
        LD      A,1             ;A=1 ==> Found a valid command
        OR      A               ;Reset C Flag
        RET                     ;Return in HL Address of command

PARSE3:                             ;Not this command, skip to next
        INC     DE
        LD      A,(DE)
        OR      A
        JR      NZ,PARSE3
PARSE4:                             ;Found end of this command, get next
        POP     HL              ;Restore buffer address to HL
        INC     DE
        INC     DE              ;Skip two bytes of command Address
        INC     DE              ; Point to start of next command, or zero if no more commands available
        JR      PARSE0          ;Check next command

PRINT:
        LD	A,(HL)		;get a character to print
        OR	A
        RET	Z
        CALL	CHPUT		;put a character
        INC	HL
        JR	PRINT

PRINTNLINE:
        LD      A,13
        CALL    CHPUT
        LD      A,10
        CALL    CHPUT
        RET

;-----------------------
; PRINTNUMBER          |
;-----------------------
PRINTNUMBER:
        PUSH    DE
        LD      E,A
        PUSH    DE
        AND     0F0H
        RRA
        RRA
        RRA
        RRA
        CALL    PRINTDIGIT
        POP     DE
        LD      A,E
        AND     %00001111
        CALL    PRINTDIGIT
        POP     DE
        RET

PRINTDIGIT:
        CP      0AH
        JR      C,PRINTNUMERIC
PRINTALFA:
        LD      D,37H
        JR      PRINTNUM1

PRINTNUMERIC:
        LD      D,30H
PRINTNUM1:
        ADD     A,D
        CALL    CHPUT
        RET

; ================================================================
; Functions to support the commands
; ================================================================
;-----------------------
; PG1RAMSEARCH         |
;-----------------------
; Search for slot/subslot where RAM page 1 ($4000) is allocated
; Works for any MSX model, and for expanded slots as well
; Register A returns the slot information, in the correct format
; to call RDSLT or WRSLT
; Output: A = slot id
;
; Becore callingPG1RAMSEARCH, set Register C to value $40:
;
; LD C,$40
; CALL PG1RAMSEARCH
;-----------------------
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

;-----------------------
; PG3RAMSEARCH         |
;-----------------------
; Search for slot/subslot where RAM page 3 ($C000) is allocated
; Works for any MSX model, and for expanded slots as well
; Register A returns the slot information, in the correct format
; to call RDSLT or WRSLT
; Output: A = slot id
;-----------------------
PG3RAMSEARCH:

	
PG3RAMSEARCH1:
            ld      b,6
	        defb    021H                    ; LD HL,xxxx (skips next instruction)

;-----------------------
; PG2RAMSEARCH         |
;-----------------------
; Search for slot/subslot where RAM page 2 ($8000) is allocated
; Works for any MSX model, and for expanded slots as well
; Register A returns the slot information, in the correct format
; to call RDSLT or WRSLT
; Output: A = slot id
;-----------------------
PG2RAMSEARCH:

	
PG2RAMSEARCH1:
            ld      b,4
	        call    XF365
	        push    bc

PG2RAMSEARCH2:
            rrca
	        djnz    PG2RAMSEARCH2
	        call    MYEXPTBL1
	        pop     bc
	        or      (hl)
	        ld      c,a
	        inc     hl
	        inc     hl
	        inc     hl
	        inc     hl
	        ld      a,(hl)
	        dec     b
	        dec     b

PG2RAMSEARCH3:
            rrca
	        djnz    PG2RAMSEARCH3
	        jr      MYSLOTID1

;-----------------------
; MYSLOTID             |
;-----------------------
; get my slotid
; Output: A = slotid
;-------------------------------------

MYSLOTID:
            call    MYEXPTBL
	        or      (hl)
	        ret     p                       ; non expanded slot, quit
	        ld      c,a
	        inc     hl
	        inc     hl
	        inc     hl
	        inc     hl
	        ld      a,(hl)

MYSLOTID1:
            and     00CH
	        or      c
	        ret

;-----------------------
; MYEXPTBL             |
;-----------------------
; get my EXPTBL entry
; Output: HL = pointer to SLTWRK entry
;-------------------------------------

MYEXPTBL:
            call    XF365
	        rrca
	        rrca

MYEXPTBL1:
            and     003H
	        ld      hl,EXPTBL

MYEXPTBL2:
            ld      b,000H

MYEXPTBL3:
            ld      c,a
	        add     hl,bc
	        ret

; ================================================================
; Text messages used in the loader
; ================================================================

MSXPIVERSTR:
        DB      "MSXPi Hardware Interface v0.7",13,10
        DB      "MSXPi ROM v0.7.0.1",13,10
        DB      "(c) Ronivon C. Costa,2017",13,10
        DB      "Type CALL MSXPIHELP for HELP",13,10,0

MSXPIHELPSTR:
        DB      "Commands available:",13,10
        DB      "HELP MEMMAP MSXPIHELP MSXPILOAD MSXPISTATUS MSXPIVER"
        DB      00

MSXPISTR:
db      "MSXPi Loader:",13,10
db      "Loading Client from Raspberry Pi",13,10,0

PIOFFLINESTR:
        DB      "Raspberry PI not responding",13,10
        DB      "Verify if server App is running",13,10
        DB      00

PIONLINESTR:
        DB      "Rasperry PI is online",13,10
        DB      00

RAMNOTFOUNDMSG:
        DB      "RAM not Found",13,10
        DB      00

FOUNDRAMMSG:    DB "FOUND RAM",13,10,0
RELOCMSG:       DB "RELOCATING CODE...",13,10,0
JUMPMSG:        DB "JUMPING TO RELOCATED CODE",13,10,0

; ================================================================
; Table of Commands available/implemented
; ================================================================

STR_CALL_CMD:

        DB      "MSXPIVER",0
        DW      MSXPIVER

        DB      "MSXPILOAD",0
        DW      MSXPILOAD

        DB      "MSXPISTATUS",0
        DW      MSXPISTATUS

        DB      "MSXPIHELP",0
        DW      MSXPIHELP

        DB      "HELP",0
        DW      MSXPIHELP

        DB      "MEMMAP",0
        DW      MEMMAP

ENDOFCMDS:
        DB      00

; ================================================================
; Code starting here will be relocated to $C000
; ================================================================
END_CODE1:      EQU     $


        ORG     MSXLOADERADDR

MSXPIRELOC:

START_CODE2:    EQU     $

; Send command LOADROM to Pi

        LD      HL,RUNRELOCMSG
        CALL    PRINT_B

        LD      A,2
        CALL    TRANSFBYTE_B
        JR      C,LOADERERR

; Start reading data from Pi
; First two bytes is the ROM size

; Read MSB of ROM size and store in D

        CALL    READBYTE_B
        LD      E,A

;       Read LSB of ROM size, and store in E
        CALL    READBYTE_B
        LD      D,A

; Read MSB of ROM EXEC Address and store in H

        CALL    READBYTE_B
        LD      L,A

;       Read LSB of ROM EXEC Address and store in L
        CALL    READBYTE_B
        LD      H,A

;       Now have DE set to the number of bytes to transfer,
;       And HL set to the execution address.

        LD      (MSXPICLIADDR),HL

;       This is the main loop to load the ROM

LOADER:

;       Read one byte

        CALL    READBYTE_B
        JR      C,LOADERERR

;       Store in memory

        LD      (HL),A
        INC     HL
        DEC     DE
        LD      A,D
        OR      E

;       Verify if all bytes has been read, otherwise read one more

        JR      NZ,LOADER
;       Execute the ROM file that was just loaded

        LD      HL,(MSXPICLIADDR)
        JP      (HL)

;       This routine will send READBYTE command (0) to port 6
;       and waity until Pi respond with a Ready signal
;       Then the MSX will read port 7, which contains the byte

LOADERERR:
        LD      HL,PIOFFLINESTR_B
        CALL    PRINT_B
        RET
; ================================================================
; Functions to support the commands
; ================================================================

PRINT_B:
        LD	A,(HL)		;get a character to print
        OR	A
        RET	Z
        CALL	CHPUT		;put a character
        INC	HL
        JR	PRINT_B

; ==================================================================
; BISO FUNCTIONS STARTS HERE.
; These are the lower level I/O routines available, and must match
; the I/O functions implemented in the CPLD.
; Other than using these functions you will have to create your
; own commands, using OUT/IN directly to the I/O ports.
; ==================================================================

IF MODEL4b
    INCLUDE    "msxpi_io_B_4bits.asm"
ELSE
    INCLUDE    "msxpi_io_B.asm"
ENDIF

; ================================================================
; END of BASIC I/O FUNCTIONS
; ================================================================

PIOFFLINESTR_B:
        DB      "Raspberry PI not responding",13,10
        DB      "Verify if server App is running",13,10
        DB      00

MSXPICLIADDR:   DW      $0000

RUNRELOCMSG:    DB      "NOW RUNNING RELOCATED CODE",13,10,0

END_CODE2:  EQU $

LOADER_END:

ROM_END:
            DS      $7FFF - ((END_CODE1 - START_CODE1) + (END_CODE2 - START_CODE2)) + 1




