;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.9                                                             |
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
; 0.9    : Rewritten to support new block download logic

        ORG     $0100
        LD      BC,6
        LD      DE,COMMAND
        CALL    DOSSENDPICMD
        JR      C,PRINTPIERR
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_WAIT
        JR      NZ,PRINTPIERR
        CALL    CHKPIRDY
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_SUCCESS
        JP      NZ,EXITSTDOUT

LOADREADY:

        LD      HL,LOADPROGRESS
        CALL    PRINT
        CALL    LOADROM

LOADROMPROG1:

        PUSH    HL
        LD      HL,0
        LD      A,($FCC1)
        CALL    ENASLT
        POP     HL
        JP      (HL)

PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

;-----------------------
; LOADROM              |
;-----------------------
LOADROM:
; Will load the ROM directly on the destiantion page in $4000
; Might be slower, but that is what we have so far...
;Get number of bytes to transfer
        LD      DE,$4000
LOADROM0:
        LD      A,'.'
        CALL    PUTCHAR
        CALL    RECVDATABLOCK
        RET     C
        CP      ENDTRANSFER
        JR      Z,LOADROMEND
        CP      RC_SUCCESS
        SCF
        RET     NZ
        JR      LOADROM0
; File load successfully.
; Return C reseted, and A = filetype
LOADROMEND:
        LD      HL,($4002)    ;ROM exec address
        OR      A             ;Reset C flag
        RET

LOADPROGERR:
        LD      HL,LOADPROGERRMSG
        CALL    PRINT
        SCF
        RET

EXITSTDOUT:
        CALL    PRINTNLINE
        CALL    PRINTPISTDOUT
        jp      0

COMMAND:
        DB      "PLOADR"

PICOMMERR:
        DB      "Communication Error",13,10,"$"

LOADPROGERRMSG:
        DB      "Error loading file",13,10,"$"

LOADPROGRESS:
        DB      "Loading game...$"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"




