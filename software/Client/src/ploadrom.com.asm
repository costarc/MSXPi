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

        ORG     $0100

LOADROMPROG:
        LD      BC,8
        LD      DE,LOADROMCMD
        CALL    DOSSENDPICMD
        JR      C,LOADPROGERR
        CALL    LOADROM
LOADROMPROG1:
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

LOADPROGERR:
        LD      HL,LOADPROGERRMSG
        CALL    PRINT
        JP      0

LOADROMCMD:
        DB      "PLOADROM"

PICOMMERR:
        DB      "Communication Error",13,10,"$"

LOADPROGERRMSG:
        DB      "Error loading file",13,10,"$"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"




