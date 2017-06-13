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

        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        LD      (RUNOPTION),A

        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        LD      (SAVEOPTION),A

        LD      A,(SAVEOPTION)
        CP      1
        JR      NZ,PGETRECVFILE

; receive filename to save
        LD      DE,SAVFNAME
        CALL    RECVDATABLOCK
        CALL    INITSAVEFILE

PGETRECVFILE:
; read 512 bytes at a time, and save to disk
; look at loadrom.com.asm to understand the required headers
;
; get the total file size
;->

; read 512 bytes at a time - this is determined by the server routine
; I recommend to use secrecvdata becuase it retransmits data
; in case of crc errors.
; but you can also try RECVDATABLOCK for a slightly faster transfer
;

        CALL    LOADROM

        PUSH    HL
        PUSH    AF
        CALL    PRINTPISTDOUT
        POP     AF
        POP     HL
        CP      ENDTRANSFER
        JP      NZ,0
        PUSH    HL
        LD      HL,0
        LD      A,($FCC1)
        CALL    ENASLT
        POP     HL
        JP      (HL)

INITSAVEFILE:
        RET
WRITEFILETODISK:
        RET

PGETEND:
        CALL    PRINTPISTDOUT
        JP      0

PRINTPIERR:
        LD      HL,PICOMMERR
        CALL    PRINT
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
        LD      A,ENDTRANSFER
        CALL    PIEXCHANGEBYTE
        CP      ENDTRANSFER
        SCF
        RET     NZ
        LD      HL,($4002)    ; ROM exec address
        LD      A,ENDTRANSFER
        OR      A             ;Reset C flag
        RET

DIRCMD: DB      "PGET"

PICOMMERR:
        DB      "Communication Error",13,10,"$"
RUNOPTION:  db  0
SAVEOPTION: db  0

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

SAVFNAME:   equ $
