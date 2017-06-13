;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.8                                                             |
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
; 0.1    : Initial version.

TEXTTERMINATOR: EQU '$'

        ORG     $0100

        LD      BC,4
        LD      DE,DIRCMD
        CALL    DOSSENDPICMD
        JR      C,PRINTPIERR

        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE

        CP      RC_SUCCESS
        JR      NZ,PGETEND

        CALL    PRINTPISTDOUT
        CALL    PRINTNLINE

LOADROMPROG:
; add url to the DOS command line buffer to simulate user type in
        CALL    PGETMVCMD

        LD      BC,8
        LD      DE,LOADROMCMD
        CALL    DOSSENDPICMD
        JR      C,LOADPROGERR
        CALL    LOADROM

        PUSH    HL
        PUSH    AF
        CALL    PRINTPISTDOUT
        POP     AF
        POP     HL
        CP      ENDOFTRANSFER
        JP      NZ,0
        PUSH    HL
        LD      HL,0
        LD      A,($FCC1)
        CALL    ENASLT
        POP     HL
        JP      (HL)

PRINTPIERR:
        LD      HL,PICOMMERR
        CALL    PRINT
        JP      0

LOADPROGERR:
        LD      HL,LOADPROGERRMSG
        CALL    PRINT
        JP      0

PGETMVCMD:
        LD      HL,PARMS
        LD      DE,$81
        LD      BC,16
        LDIR
        RET

PARMS:  DB " /tmp/pget.file",13
PGETEND:
        CALL    PRINTPISTDOUT
        JP      0

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
        LD      DE,$4000
        CALL    READDATASIZE
LOADROM0:
        PUSH    BC
        LD      A,GLOBALRETRIES
LOADROMRETRY:
; retries
        PUSH    AF
        CALL    RECVDATABLOCK
        JR      NC,LOADROM1
        POP     AF
        DEC     A
        JR      NZ,LOADROMRETRY
        LD      A,ABORT
        POP     BC
        OR      A
        RET

LOADROM1:
        LD      A,'.'
        CALL    PUTCHAR
        POP     AF
;Get rom address to write
        POP     HL

;DE now contain ROM address
        SBC     HL,BC
        JR      C,LOADROMEND
        JR      Z,LOADROMEND
        LD      B,H
        LD      C,L
        JR      LOADROM0

; File load successfully.
; Return C reseted, and A = filetype
LOADROMEND:
        LD      A,ENDOFTRANSFER
        CALL    PIEXCHANGEBYTE
        CP      ENDOFTRANSFER
        SCF
        RET     NZ
        LD      HL,($4002)    ; ROM exec address
        LD      A,ENDOFTRANSFER
        OR      A             ;Reset C flag
        RET

FILLFCB:
; DE contain the buffer with the file name.
        LD      HL,FILEFCB
        EX      HL,DE
        XOR     A
        LD      (DE),A
        CALL    SKIPSPC
        CALL    GETNEXTCHAR
        LD      C,A
        INC     HL
        LD      A,(HL)
        DEC     HL
        CP      ":"
        LD      A,C
        JR      NZ,GETFEXT
        INC     HL
        INC     HL
        SUB     $41
        JR      C,DRIVEINVALID
        INC     A
        LD      (DE),A
        JR      GETFEXT

DRIVEINVALID:
        LD      A,$FF
        LD      (DE),A

GETFEXT:
        INC     DE
        LD      C,0
        LD      B,8
        CALL    GETFNAME
        LD      A,(HL)
        CP      "."
        JR      NZ,GETEXTEXIT
        INC     HL
        LD      B,3
        CALL    GETFNAME0
GETEXTEXIT:
        LD      A,C
        RET

GETFNAME:
        CALL    GETNEXTCHAR
        JR      C,NOTCHAR
        JR      Z,NOTCHAR
GETFNAME0:
        CALL    GETNEXTCHAR
        JR      C,GETFNAMEEXIT
        JR      Z,GETFNAMEEXIT
        INC     HL
        INC     B
        DEC     B
        JR      Z,GETFNAME0
        CP      "*"
        JR      Z,ISWILDCARD
        LD      (DE),A
        INC     DE
        DEC     B
        CP      "?"
        JR      Z,FOUNDWILDCARD
        JR      GETFNAME0
ISWILDCARD:
        CALL    USEWILDCARD

FOUNDWILDCARD:
        LD      C,1

NOTCHAR:
        LD      A,E
        ADD     A,B
        LD      E,A
        RET     NC
        INC     D
        RET


GETFNAMEEXIT:
        INC     B
        DEC     B
        RET     Z
        LD      A,$20
        JR      FILLSPC

USEWILDCARD:
        LD      A,"?"

FILLSPC:
        LD      (DE),A
        INC     DE
        DJNZ    FILLSPC
        RET

SKIPSPC:
        LD      A,(HL)
        INC     HL
        CALL    CHKSPC
        JR      Z,SKIPSPC
        DEC     HL
        RET

GETNEXTCHAR:
        LD      A,(HL)
        CP      "a"
        JR      C,GETNXCH1
        CP      $7B
        JR      NC,GETNXCH1
        SUB     $20

GETNXCH1:
        CP      ":"
        RET     Z
        CP      "."
        RET     Z
        CP      $22
        RET     Z
        CP      "["
        RET     Z
        CP      "]"
        RET     Z
        CP      "_"
        RET     Z
        CP      "/"
        RET     Z
        CP      "+"
        RET     Z
        CP      "="
        RET     Z
        CP      ";"
        RET     Z
        CP      ","
        RET     Z
CHKSPC:
        CP      $09
        RET     Z
        CP      " "
        RET

OPENFILEW:
        LD      DE,FILEFCB
        LD      C,$16
        CALL    BDOS
        OR      A
        RET     Z
; Error opening file
        SCF
        RET

INIFCB:
        EX      AF,AF'
        EXX
        LD      HL,FILEFCB
        LD      (HL),0
        LD      DE,FILEFCB+1
        LD      BC,$0023
        LDIR
        LD      HL,FILEFCB+1
        LD      (HL),$20
        LD      HL,FILEFCB+2
        LD      BC,$000A
        LDIR
        EXX
        EX AF,AF'
        RET


DIRCMD:     DB      "PGET"
LOADROMCMD: DB      "PLOADROM"

PICOMMERR:  DB      "Communication Error",13,10,"$"
LOADPROGERRMSG: DB  "Error download file from network",13,10,10
RUNOPTION:  db  0
SAVEOPTION: db  0

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

FILEFCB: DS 40

