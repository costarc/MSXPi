;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.7                                                             |
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
; 0.8    : Moved several routines to msxpi_bios.asm
; 0.7    : Release updated to sync with other components
;          Added slot search routines for pages 1,2,3
; 0.6c   : Initial version commited to git
;

; ================================================================
; API AND OTHER SUPPORTING FUNCTIONS STARTS HERE
; ================================================================

PRINTCOMMERROR:
            LD      HL,PICOMMERR
            JP      PRINT

;-----------------------
; READCMD              |
;-----------------------
READCMD:                            ;Read a string from command line
                                    ;Return buffer to string in HL
            LD      HL,PROMPT
            CALL    PRINT
READCMD0:
            CALL    INLIN
            RET

;-----------------------
; PARSECMD             |
;-----------------------
; Input:
;   INLINBUF should contain the string to parse
; Output:
;   HL = EXEC address of command when found
;   BC = Number of characters in the buffer
;
PARSECMD:                           ;Return Command address in HL,
                                    ;and parameters buff in DE
            LD      DE,COMMANDLIST
PARSE0:
            LD      HL,INLINBUF
PARSE1:
PARSE2:
            LD      A,(DE)
            CP      (HL)
            JR      Z,PARSE2A
            ADD     32
            CP      (HL)
            JR      NZ,PARSE3
PARSE2A:
            INC     HL
            INC     DE
            LD      A,(DE)
            OR      A
            JR      NZ,PARSE2       ;This command has more characters to verify

FOUNDCMD:
            INC     DE
            LD      A,(DE)
            LD      L,A
            INC     DE
            LD      A,(DE)
            LD      H,A
            PUSH    HL
; CALC buffer size and return in BC
            CALL    FINDENDCMD
            POP     HL
            LD      A,1             ;A=1 ==> Found a valid command
            OR      A               ;Reset C Flag
            RET                     ;Return in HL Address of command

FINDENDCMD:
            LD      HL,INLINBUF
FINDENDCMD0:
            LD      B,H
            LD      C,L
FINDENDCMD1:
            LD      A,(HL)
            INC     HL
            OR      A
            JR      NZ,FINDENDCMD1
            SBC     HL,BC
            LD      B,H
            LD      C,L
            RET

PARSE3:                             ;Not this command, skip to next
            INC     DE
            LD      A,(DE)
            OR      A
            JR      NZ,PARSE3
PARSE4:                             ;Found end of this command, get next
            INC     DE
            INC     DE              ;Skip two bytes of command Address
            INC     DE              ;Point to start of next command, or zero if no more commands available
            LD      A,(DE)
            OR      A
            JR      NZ,PARSE0          ;Check next command
PARSEERR:
            SCF                     ;Command not found, set error flag
            RET

;-----------------------
; PARSEPARM            |
;-----------------------
; Return:
; Flag C - set if there is not parameter, or is invalid
; A = 0 there is not a parameter
; A = 1 there is a valid parameter
; A = 2 there is a potentially valid parameter (terminate without quotes)
; A = 255 syntax error in parameter

PARSEPARM:
            LD      DE,(PARMBUF)
PARSEPARM0:
            LD      A,(DE)
            OR      A
            JR      NZ,PARSEPARM1
            SCF                     ;no parameters found, A = 0
            RET

PARSEPARM1:
            INC     DE
            CP      34
            JR      Z,PARSEPARM2A
            CP      32
            JR      Z,PARSEPARM0

PARSEPARM2:
            DEC     DE
PARSEPARM2A:
            LD      (PARMBUF),DE    ;Save start address of parameter
            LD      B,255           ;Maximum size of paramter
            XOR     A
            LD      (AUTORUN),A

PARSEPARM3:
            LD      A,(DE)
            CP      34      ;is it quote?
            JR      Z,CHECKRUN      ;Verify is there is ",R"
            OR      A
            JR      Z,PARSEPARM4     ;Return, PARMBUFF got the parameter, terminated in 0 or quote (")
            INC     DE
            DJNZ    PARSEPARM3
            LD      A,255           ;syntax error in parameters
            SCF                     ;Parameters are too long
            RET
PARSEPARM4:
; Found paramater, set A = 1
            LD      A,1
            OR      A
            RET

CHECKRUN:                          ;Check for additional paratmers after quote, such as ",R"
            INC     DE
            LD      A,(DE)
            CP      ','             ;is it comma?
            JR      Z,PMORE1
            CP      ' '
            JR      Z,CHECKRUN
            OR      A
            JR      Z,PARSEPARM4    ;End of paramters
            LD      A,2
            SCF                     ;Syntax error
            RET
PMORE1:
            INC     DE
            LD      A,(DE)
            CP      'R'             ;Is it an parameter to run the program after load?
            JR      Z,PMORE2
            CP      'r'
            JR      Z,PMORE2
            CP      32
            JR      Z,PMORE1
            LD      A,2
            SCF                     ;Syntax error
            RET
PMORE2:
            LD      A,1
            LD      (AUTORUN),A
            OR      A
            RET

;-----------------------
; PG0RAMSEARCH         |
;-----------------------
; Search for slot/subslot where RAM page 0 ($0000) is allocated
; Works for any MSX model, and for expanded slots as well
; Register A returns the slot information, in the correct format
; to call RDSLT or WRSLT
; Output: A = slot id
;
; Becore calling PG1RAMSEARCH, set Register C to value $00:
;
; LD C,$00
; CALL PG0RAMSEARCH
;-----------------------
PG0RAMSEARCH:
            LD      HL,EXPTBL
	        LD      B,4
	        XOR     A
PG0RAMSEARCH1:
            AND     03H
	        OR      (HL)
PG0RAMSEARCH2:
            PUSH    BC
	        PUSH    HL
	        LD      H,C
PG0RAMSEARCH3:
            LD      L,10H
PG0RAMSEARCH4:
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
	        JR      NZ,PG0RAMSEARCH6
	        POP     AF
	        DEC     L
	        JR      NZ,PG0RAMSEARCH4
	        INC     H
	        INC     H
	        INC     H
	        INC     H
	        LD      C,A
	        LD      A,H
	        CP      40H
	        JR      Z,PG0RAMSEARCH5
	        CP      80H
	        LD      A,C
	        JR      NZ,PG0RAMSEARCH3
PG0RAMSEARCH5:
            LD      A,C
	        POP     HL
	        POP     HL
	        RET
PG0RAMSEARCH6:
            POP     AF
	        POP     HL
	        POP     BC
	        AND     A
	        JP      P,PG0RAMSEARCH7
	        ADD     A,4
	        CP      90H
	        JR      C,PG0RAMSEARCH2
PG0RAMSEARCH7:
            INC     HL
	        INC     A
	        DJNZ    PG0RAMSEARCH1
	        SCF
	        RET

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

FINDRAMSLOTS:
            ld      c,$40
            call    PG1RAMSEARCH
            ld      (SLOTRAM1),a
;            call    PG2RAMSEARCH
;            ld      (SLOTRAM2),a
;            call    PG3RAMSEARCH
;            ld      (SLOTRAM3),a
            ei
            ret


