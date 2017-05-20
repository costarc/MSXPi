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
        LD      DE,PGETCMD
        CALL    DOSSENDPICMD
        JR      C,PRINTPIERR

        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      SENDNEXT
        JR      NZ,LOADPROGERR

;        LD      A,SENDNEXT
;        CALL    PIEXCHANGEBYTE
;        LD      (RUNOPTION),A

;        LD      A,SENDNEXT
;        CALL    PIEXCHANGEBYTE
;        LD      (SAVEOPTION),A

;        LD      A,SENDNEXT
;        CALL    PIEXCHANGEBYTE
;        CP      SENDNEXT
;        JR      NZ,LOADPROGERR


;        LD      A,(SAVEOPTION)
;        CP      1
;        JR      NZ,LOADROMPROG
; receive filename to save

        CALL    INIFCB
        LD      DE,FILEFCB+1
        CALL    RECVDATABLOCK

; debug
;        ld      de,INIFCB+1
;        ld      b,12
dbgloop1:
;        ld      a,(de)
;        call    PUTCHAR
;        inc     de
;        djnz    dbgloop1
; end debug

; About to start trasnfer, then need to open the file to write
;        CALL    OPENFILEW
;        LD      HL,FILEERR1
;        JR      C,PRINTERR

LOADROMPROG:
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      SENDNEXT
        JR      NZ,LOADPROGERR

LOADBLOCK:
        ld      a,'O'
        call    PUTCHAR

; BLOCK SIZE TO USE
        LD      BC,8192

; BUFFER TO STORE DATA RECEIVED
        LD      DE,BUF

; SHOW PROGRESSION DOTS
        LD      A,1

; READ 1 BLOCK OF DATA AND STORE IN (DE)
        CALL    DOWNLOADDATA
        JR      C,PRINTPIERR

; Or there was not more data and it finished successfuly ?
        CP      ENDTRANSFER
        JR      Z,CONSUMEDATA

        CP      RC_SUCCESS
        JR      NZ,LOADPROGERR

USEDATABLOCK:
; IMPLEMENT HERE THE CODE TO PROCESS THE BLOCK OF DATA RECEIVED
        LD      A,"P"
        CALL    PUTCHAR

; CRC status can also be verified here and retry can be implemented.
; < more code here >
; Read next nlock
        JR      LOADBLOCK

; Finished readig data
; Print final Pi message to screen
CONSUMEDATA:

LOADPROGERR:
        ld      a,'Q'
        call    PUTCHAR
        CALL    PRINTPISTDOUT
        JP      0

PRINTPIERR:
        ld      a,'R'
        call    PUTCHAR
        LD      HL,PICOMMERR
PRINTERR:
        ld      a,'S'
        call    PUTCHAR
        CALL    PRINT
        JP      0

PGETMVCMD:
        LD      HL,PARMS
        LD      DE,$81
        LD      BC,16
        LDIR
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

PICOMMERR:  DB      "Communication Error",13,10,"$"
LOADPROGERRMSG: DB  "Error download file from network",13,10,"$"
FILEERR1:   DB      "Error opening disk file",13,10,"$"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

PGETCMD:     DB      "PGET"
LOADDATACMD: DB      "LOADDATA"
PARMS:       DB      " /tmp/pget.file",13
RUNOPTION:   DB      0
SAVEOPTION:  DB      0

FILEFCB:     DS     40
BUF:         EQU    $

