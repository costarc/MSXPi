;|===========================================================================|
;|                                                                           |
;| MSXPi Interface Software Template                                         |
;|                                                                           |
;| Version : 0.1                                                             |
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

;Send the command to MSX
; BC = Number of characters in my command (without parameters, only the text)
;      Parameters will be picked up by "DOSSENDPICMD" and sent to Pi.
; After running "DOSSENDPICMD", flag C is Set if command failed
LOADROMPROG:
        LD      BC,8
        LD      DE,LOADROMCMD
        CALL    DOSSENDPICMD
        JR      C,LOADPROGERR

; Now run my logic
        CALL    LOADROM

        ...

; save A because it contain error code
        PUSH    AF

; print stdout sent by Pi
        CALL    PRINTPISTDOUT

; Restore A with the error code
        POP     AF

        ...

; Did it finish sucessully*
        CP      ENDOFTRANSFER

; Failed, them return to MSX-DOS
        JP      NZ,0

; Success, then do my post-processing (Execute the Game in this example)
        PUSH    HL
        LD      HL,0
        LD      A,($FCC1)
        CALL    ENASLT
        POP     HL
        JP      (HL)

;-----------------------
; LOADROM              |
;-----------------------
LD      A,STARTTRANSFER
        CALL    PIEXCHANGEBYTE
        RET     C

        ...

        CALL    RECVDATABLOCK

        ...

        LD      A,ENDOFTRANSFER
        CALL    PIEXCHANGEBYTE
        CP      ENDOFTRANSFER
        SCF
        RET     NZ
        ...
        OR      A
        RET


PRINTPIERR:
        LD      HL,PICOMMERR
        CALL    PRINT
        JP      0

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxdos_stdio.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "debug.asm"

LOADROMCMD: DB      "PLOADROM",0

PICOMMERR:
        DB      "Communication Error",13,10,"$"

