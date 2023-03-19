;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.9.0                                                           |
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
; 0.9.0  : Changes to supoprt new transfer logic

BDOS:   EQU     5
DSKNUMREGISTERS:   EQU 8192
DSKBLOCKSIZE:   EQU 1

        ORG     $0100

MAINPROGRAM:

        CALL    INIFCB

; READ FILENAME
        CALL    READPARMS
        JR      C,PRINTPIERR

        CALL    PRINTFNAME

        CALL    OPENFILEW

        CALL    SETFILEFCB

        CALL    GETFILE
        JR      C,PRINTPIERR

        CALL    CLOSEFILE

        JP      0

EXITSTDOUT:
        CALL    PRINTNLINE
        CALL    PRINTPISTDOUT
        jp      0

FILEERR:
        LD      A,RC_FAILED
        CALL    PIEXCHANGEBYTE
        LD      HL,PRINTPIERR
        CALL    PRINT
        JP      0
        
PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

PRINTFNAME:
        LD      HL,FNTITLE
        CALL    PRINT
        LD      HL,FILEFCB
        ld      a,(HL)
        INC     HL
        OR      A
        JR      Z,PRINTFNAME2
        CP      1
        LD      A,'A'
        JR      Z,PRINTFNAME1
        LD      A,'B'
PRINTFNAME1:
        CALL    PUTCHAR
        LD      A,':'
        CALL    PUTCHAR
PRINTFNAME2:
        LD      B,8
        CALL    PLOOP
        LD      A,'.'
        CALL    PUTCHAR
        LD      B,3
        CALL    PLOOP
        CALL    PRINTNLINE
        RET
PLOOP:
        LD      A,(HL)
        CALL    PUTCHAR
        INC     HL
        DJNZ    PLOOP
        RET

; This routime will read the whole file from Pi
; it will use blocks size DSKNUMREGISTERS (because disk block is 1)
; Each block is written to disk after download
GETFILE:
DSKREADBLK:

        LD      A,'.'
        CALL    PUTCHAR

; Buffer where data is stored during transfer, and also DMA for disk access
        LD      DE,DMA
        LD      BC,DSKNUMREGISTERS
; READ ONE BLOCK OF DATA AND STORE IN THE DMA
        CALL    RECVDATA
        RET     C
        
        ; Set HL with the number of bytes received
        LD      A,(DMA)
        LD      L,A
        LD      A,(DMA +1)
        LD      H,A        
        LD      DE,FILEFCB
        LD      C,$26
        CALL    BDOS
        
        ; now verify if data received was less thant DMA bufffer - if so, finished transferinf
        LD      DE,DSKNUMREGISTERS
        LD      A,(DMA + 1)
        LD      L,A
        LD      A,(DMA + 2)
        LD      H,A
        OR      A                   ; reset flag C 
        SBC HL,DE               ; NUM BYTES READ - BUFFER SIZE
        JR      NC,DSKREADBLK       ; data read less than buffer - finished transfer
        RET

READPARMS:
; READ FILENAME DIRECTLY INTO THE FCB AREA
        LD      DE,FILEFCB
        LD      B,12
READPARMS0:
        CALL    PIREADBYTE
        LD      (DE),A
        INC     DE
        DJNZ    READPARMS0
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

SETFILEFCB:
        LD      DE,DMA+3
        LD      C,$1A
        CALL    BDOS
        LD      HL,DSKBLOCKSIZE
        LD      (FILEFCB+$0E),HL
        LD      HL,0
        LD      (FILEFCB+$20),HL
        LD      (FILEFCB+$22),HL
        LD      (FILEFCB+$24),HL
        RET

CLOSEFILE:
        LD      DE,FILEFCB
        LD      C,$10
        CALL    BDOS
        RET

COMMAND:    DB      "PCOPY000",0
FNTITLE:    DB      "Saving file:",0
PICOMMERR:  DB      "Communication Error",13,10,0
PIUNKNERR:  DB      "Unknown error",13,10,0
PICRCERR:   DB      "CRC Error",13,10,0
DSKERR:     DB      "DISK IO ERROR",13,10,0
LOADPROGERRMSG: DB  "Error download file from network",13,10,10
FOPENERR:   DB      "Error opening file",13,10,0
PARMSERR:   DB      "Invalid parameters",13,10,0
USERESCAPE: DB      "Cancelled",13,10,0
RUNOPTION:  db  0
SAVEOPTION: db  0
REGINDEX:   dw  0
FILEFCB:    ds     40

;INCLUDE "debug.asm"
INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"

buf:    equ     $
        ds      BLKSIZE
        db      0


