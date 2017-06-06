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
; 0.7    : Release updated to sync with other components
;          Added slot search routines for pages 1,2,3
; 0.6c   : Initial version commited to git
;

; ================================================================
; API AND OTHER SUPPORTING FUNCTIONS STARTS HERE
; ================================================================

;-----------------------
; PIAPPRESET           |
;-----------------------
PIAPPRESET:
            LD      A,(CMDRESET)
            PUSH    AF
            CALL    SENDIFCMD       ; Reset the Interface
            POP     AF
            CALL    SENDPICMD       ; Reset Pi App
            LD      A,34
            CALL    TRANSFBYTE
            LD      A,41H
            CALL    TRANSFBYTE
            LD      A,34
            CALL    TRANSFBYTE
            RET

;-----------------------
; PISERVERSHUT         |
;-----------------------

PISERVERSHUT:
            LD      A,(CMDPIOFF)
            CALL    SENDPICMD
            RET

;-----------------------
; CHKPISTATUS          |
;-----------------------
CHKPISTATUS:
            LD      A,(CMDVERIFY)
            CALL    SENDPICMD       ; Send command do PI
            RET                     ; C flag is set if error

;-----------------------
; READCMD              |
;-----------------------
READCMD:                            ;Read a string from command line
                                    ;Return buffer to string in HL
            LD      HL,PROMPT
            CALL    PRINT
READCMD0:
            CALL    INLIN
            LD      HL,INLINBUF     ;return buffer address to calling program
            RET

;-----------------------
; PARSECMD             |
;-----------------------
PARSECMD:                           ;Return Command address in HL,
                                    ;and parameters buff in DE

            LD      DE,COMMANDLIST
PARSE0:
PARSE1:
            PUSH    HL
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
            LD      (PARMBUF),HL    ;Save pamaters address
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
; SETPARM              |
;-----------------------
;SETPARM will set the Pi variable to the specified parameter
;Do not validate the parameter - vefore calling this routine,
;the parameter should be validated by PARSEPARM
;
;As for version 0.6d, the following identifiers are valid:
;
; * http://site/url   or http://site:port/url
; * ftp://site/url
; * nfs://server-nameorip/sharedfolder
; * win://server-nameorip/sharedfolder
; * and also, local filesystems, as for example / , /usr, /etc, and so on.
;
;The string with the parameter info must be in the address pointed by (PARMBUF)

SETPARM:
            LD      A,(CMDSETPARM)
            CALL    SENDPICMD
            RET     C               ;Error

;-----------------------
; SENDPARM             |
;-----------------------
;           Start reading the actual parameter to send
SENDPARM:
            LD      HL,(PARMBUF)
SENDPARM0:
            LD      A,(HL)
            OR      A
            RET     Z
            CP      34
            JR      Z,SENDPARM2     ; discard quote (")
SENDPARM1:
            ;CALL    CHPUT
            CALL    TRANSFBYTE      ;Send first char
SENDPARM2:
            INC     HL
            LD      A,(HL)
            OR      A
            JR      Z,SENDZERO      ;finished transfering paramaters
            CP      34
            JR      Z,SENDZERO
            JR      SENDPARM1
SENDZERO:
            XOR     A
            CALL    TRANSFBYTE
            RET

;-----------------------
; READTEXTSTREAM       |
;-----------------------
; Read a stream of characters and display on screen
; Stop when receive zero or specified number of bytes are read
; print new line at end of the stream

; reads 80 bytes at a time and display
; request ACK before reading more data

; this initial setup is to allow app to choose to pause scroll
READTEXTSTREAM:

            LD      DE,CLIENTSTART-256
            LD      BC,80
            PUSH    DE
            OR      A
            CALL    RECVTXTDATA
            POP     HL
            JR      C,READTEXTSTREAMERR
            PUSH    AF                 ;A = 0 if end of data
            SCF
            CALL    PRINT
            POP     AF
            OR      A                  ; Is there more data?
            JR      NZ,READTEXTSTREAM
            RET

READTEXTPRINT:
            CP      10
            JP      NZ,CHPUT

READTEXTPRINT1:
            CALL    CHPUT
            CP      13
            JP      CHPUT

READTEXTSTREAMERR:
            LD      HL,PIERRRMSG
            JP      PRINT

; OLD CODE STARTS HERE
; some routines like srolling pause, to be moved to new routine above,
; then this will be delete.

            LD      C,1
            JR      C,READTEXTSTREAMA
            LD      C,0
READTEXTSTREAMA:
            LD      B,A
            LD      A,C
            LD      (PAUSEVAR),A
            PUSH    BC
;CALL    PRINTNLINE
            LD      A,(CSRY)
            LD      (MCSRY),A
            XOR     A
            LD      (MCSRX),A
            POP     AF
            LD      B,255
            JR      RDSTRMCHKPAUSE
READSTREAM1:

; scroll pause option disabled. there is a bug, need fix.
; will always pause before scroling screen
RDSTRMCHKPAUSE:
             LD      A,(PAUSEVAR)
             OR      A
             JR      Z,READSTREAM2

            LD      A,(MCSRX)
            INC     A
            CP      40
            JR      NC,READSTREAM1A
            LD      (MCSRX),A
            JR      READSTREAM2

READSTREAM1A:
            XOR     A
            LD      (MCSRX),A
            LD      A,(MCSRY)
            INC     A
            CP      23
            JR      NC,READSTREAM1B
            LD      (MCSRY),A
            JR      READSTREAM2

READSTREAM1B:
            LD      HL,MSGPAUSE
            CALL    PRINT
            CALL    CHGET
            CALL    CLS
            XOR     A
            LD      (MCSRY),A
            LD      (MCSRX),A

READSTREAM2:
            CALL    READBYTE
            OR      A
            JR      Z,ENDREADSTREAM
READSTREAM2A:
            CP      13
            JR      NZ,READSTREAM2B
            CALL    CHPUT
            LD      A,10
            JR      READSTREAM3

READSTREAM2B:
            CP      10
            JR      NZ,READSTREAM2C
            LD      A,13
            JR      READSTREAM2A
READSTREAM2C:
            CALL    CHPUT
            JR      READSTREAM1

READSTREAM3:
            CALL    CHPUT
            LD      A,39
            LD      (MCSRX),A
            LD      A,13
            JR      READSTREAM1

ENDREADSTREAM:
            CALL    PRINTNLINE
            CALL    READBYTE
            CALL    READBYTE
            CALL    READBYTE
            RET

;-----------------------
; PRINTNLINE           |
;-----------------------
PRINTNLINE:
            LD      A,13
            CALL    CHPUT
            LD      A,10
            CALL    CHPUT
            RET

;-----------------------
; LOAD                 |
;-----------------------
;Load a file from PI
; DE Contain the address of the string with filename
; Return in A the file type (see documentation for API LOAD)
; Return in HL the program EXEC address when applicable
LOAD:
            CALL    PARSEPARM       ;Parse paramenters in DE
            RET     C               ; Error

            CALL    SETPARM

;           SETPARM returned with an error?
            RET     C

; LOADING FILE
            LD      HL,LOADMSG
            CALL    PRINT

;           Send the load command
            LD      A,(CMDLDFILE)
            CALL    SENDPICMD
            RET     C

; Need to read first the file size
            CALL    READBYTE
            LD      (FSIZE),A       ; LSB part of the ROM size
            CALL    READBYTE
            LD      (FSIZE+1),A     ; MSB part of the ROM size

GUESSFTYPE:

; Read file size (two first bytes)
            CALL    READBYTE
            RET     C

            CP      $FE
            JR      Z,BINFILETYPE

            CP      $41
            JR      NZ,RAWFILETYPE2
            CALL    READBYTE
            RET     C
            CP      $42
            JR      Z,ROMFILETYPE

            LD      A,$41
            LD      (HL),A
            INC     HL
RAWFILETYPE1:
            LD      (HL),A
            INC     HL

RAWFILETYPE2:
            LD      (HL),A
            XOR     A
            LD      (FILETYPE),A
            LD      DE,(FSIZE)
            SCF
            CALL    RECVBINDATA
            RET

BINFILETYPE:
            LD      A,3
            LD      (FILETYPE),A
            CALL    READBYTE
            LD      (STARTADDR),A
            LD      E,A             ;LSB OF START ADDRESS
            CALL    READBYTE
            LD      (STARTADDR+1),A
            LD      D,A             ;MSB OF START ADDRESS

            CALL    READBYTE        ; DISCARD END ADDRESS LSB
            CALL    READBYTE        ; DISCARD END ADDRESS MSB

            CALL    READBYTE
            LD      (EXECADDR),A    ; LSB exec address
            CALL    READBYTE
            LD      (EXECADDR+1),A  ; MSX exec address
            LD      HL,(FSIZE)
            LD      BC,7
            SBC     HL,BC
            LD      B,H
            LD      C,L
            SCF                     ; Show progression
            CALL    RECVBINDATA
            LD      HL,(EXECADDR)   ;return in HL the exec address of the program
            RET

ROMFILETYPE:

            LD      A,4
            LD      (FILETYPE),A

; Will load the ROM directly on the destiantion page in $4000
; Might be slower, but that is what we have so far...
; Search for the SLOT where RAM is, return in A

            LD      A,(SLOTRAM1)
            LD      HL,$4000

; Write the ROM header
            LD      E,$41
            PUSH    AF
            CALL    WRSLT
            POP     AF
            INC     HL
            LD      E,$42
            PUSH    AF
            CALL    WRSLT
            POP     AF
            INC     HL
            PUSH    HL          ;Save destination address

            LD      HL,(FSIZE)
            DEC     HL
            DEC     HL

ROMFILE0:

            LD      A,H
            OR      L
            JR      Z,ROMFILEEND           ; END of Data
            LD      BC,512
            SBC     HL,BC
            JR      NC,ROMFILE1
; Remaining block is less than 512 bytes

            LD      BC,(FSIZE)
            LD      HL,0
            LD      (FSIZE),HL
            JR      ROMFILE2


ROMFILE1:
            LD      (FSIZE),HL  ;Remaining data size

; HL - BC is greater than 512, but
; we only read 512 bytes at a time

ROMFILE2:
            LD      DE,CLIENTSTART-513  ;512 bytes buffer address
            PUSH    BC
            PUSH    DE
            SCF
            CALL    RECVBINDATA            ; Transfer up to 512 bytes from Pi to DE address
            POP     DE
            POP     BC
            POP     HL              ;Restore destination address

; Now move the 512 bytes frm buffer into page1
; This needs inter-slots write call

            LD      A,(SLOTRAM1)

ROMFILE3:
            PUSH    AF
            PUSH    BC
            PUSH    DE
            LD      B,A
            LD      A,(DE)
            LD      E,A
            LD      A,B
            CALL    WRSLT
            POP     DE
            POP     BC
            INC     HL
            INC     DE
            DEC     BC
            LD      A,B
            OR      C
            JR      Z,ROMFILE4
            POP     AF
            JR      ROMFILE3
ROMFILE4:
            POP     AF
            PUSH    HL          ; Save next rom address to write
            LD      HL,(FSIZE)  ;Get remaining number of bytes to transfr
            JR      ROMFILE0

; File load successfully.
; Return C reseted, and A = filetype
ROMFILEEND:
            POP     HL          ;Discard next rom address, not needed anymore
            LD      HL,$4002    ; ROM exec address
            LD      A,(SLOTRAM1)
            PUSH    AF
            CALL    RDSLT
            LD      E,A
            POP     AF
            PUSH    DE
            INC     HL
            CALL    RDSLT
            POP     HL
            LD      H,A
            OR      A               ;Reset C flag
            LD      A,(FILETYPE)
            EI
            RET

;-----------------------
; RECVBINDATA          |
;-----------------------
; Read a stream of binary data from Pi.
; BC should contain the size of the stream to read
; DE should contain the address to start storing the data
; FLAG C set to show dots (progression)
RECVBINDATA:                       ;registers A,B,HL,DE and FLGAS are modified
            PUSH    AF
            CALL    C,SHOWDOTS
            CALL    READBYTE
            LD      (DE),A
            JR      C,RECVBINDATAERROR
            INC     DE
            DEC     BC
            LD      A,B
            OR      C
            JR      Z,RECVBINDATAEND
            POP     AF
            JR      RECVBINDATA
RECVBINDATAEND:
            POP     AF
            OR      A
            RET

RECVBINDATAERROR:
            POP     AF
            SCF
            RET                 ; File is now loaded in the position pointed by HL

;-----------------------
; RECVTXTDATA          |
;-----------------------
; Read a stream of text data from Pi.
; BC should contain the size of the stream to read
; DE should contain the address to start storing the data
; FLAG C set to show dots (progression)
; Registers A,B,HL,DE and FLGAS are modified
; Return flag C set if there was error.
; Return A = 0 f end of data.
; Insert zero on after the reived data.

RECVTXTDATA:
            PUSH    AF
            CALL    C,SHOWDOTS
            CALL    READBYTE
            LD      (DE),A
            INC     DE
            JR      C,RECVTXTDATAERROR
            OR      A
            JR      Z,RECVTXTDATAEND1
            DEC     BC
            LD      A,B
            OR      C
            JR      Z,RECVTXTDATAEND2
            POP     AF
            JR      RECVTXTDATA

; Received zero, then transfer shoud finish
RECVTXTDATAEND1:
            POP     AF
            XOR     A
            RET

; Read maximum number of byes, set A=1 to tell there is more data
RECVTXTDATAEND2:
            POP     AF
            XOR     A
            LD      (DE),A
            INC     A
            RET

RECVTXTDATAERROR:
            POP     AF
            SCF
            RET                 ; File is now loaded in the position pointed by HL

SHOWDOTS:
            LD      A,(CNT1)
            DEC     A
            LD      (CNT1),A
            OR      A
            RET     NZ
            LD      A,'.'
            CALL    CHPUT
            RET
;-----------------------
; PRINT                |
;-----------------------
PRINT:
            PUSH    AF
            LD      A,(HL)		;get a character to print
            OR      A
            JR      Z,PRINTEXIT
            CP      10
            JR      NZ,PRINT1
            POP     AF
            PUSH    AF
            LD      A,10
            JR      NC,PRINT1
            CALL    CHPUT
            LD      A,13
PRINT1:
            CALL	CHPUT		;put a character
            INC     HL
            POP     AF
            JR      PRINT
PRINTEXIT:
            POP     AF
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


