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
DSKNUMREGISTERS:   EQU 8192
DSKBLOCKSIZE:   EQU 1

        ORG     $0100

        LD      BC,5
        LD      DE,PCOPYCMD
        CALL    DOSSENDPICMD
        JR      C,PRINTPIERR

; SYNC TO RECEIVE FILENAME
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_FAILED
        JR      Z,EXITSTDOUT
        CP      SENDNEXT
        JR      NZ,PRINTPIERR

        CALL    INIFCB

; READ FILENAME
        CALL    READPARMS
        JR      C,PRINTPIERR

; Sync to wait Pi download the file
; Since a network transfer my get delayed, this routine
; will loop waiting RC_SUCCESS until Pi responds
; Loop can be interrupted by ESC

        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_WAIT
        SCF
        RET     NZ
WAITLOOP:
        CALL    CHECK_ESC
        JR      C,PRINTPIERR
        CALL    CHKPIRDY
        JR      C,WAITLOOP
; Loop waiting download on Pi
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_FAILED
        JR      Z,EXITSTDOUT
        CP      RC_SUCCESS
        JR      NZ,WAITLOOP

        CALL    PRINTFNAME

        CALL    OPENFILEW

        CALL    SETFILEFCB

        CALL    GETFILE
        JR      C,PRINTPIERR

        CALL    PRINTNLINE
        CALL    PRINTPISTDOUT

        CALL    CLOSEFILE

        JP      0

EXITSTDOUT:
        CALL    PRINTNLINE
        CALL    PRINTPISTDOUT
        jp      0

PRINTPIERR:
        LD      HL,PICOMMERR
        CALL    PRINT
        JP      0

FILEERR:
        LD      A,RC_FAILED
        CALL    PIEXCHANGEBYTE
        LD      HL,PRINTPIERR
        CALL    PRINT
        JP      0

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

; SEND COMMAND TO TRANSFER NEXT BLOCK
        LD      BC,5
        LD      DE,PCOPYCMD
        CALL    DOSSENDPICMD
        JR      C,PRINTPIERR

; BLOCK SIZE TO USE
        LD      BC,DSKNUMREGISTERS

; Buffer where data is stored during transfer, and also DMA for disk access
        LD      DE,DMA

; READ ONE BLOCK OF DATA AND STORE IN THE DMA

; A = 1 Tells the download routine to show dots or every 256 bytes transfered
; The routine rturns C set is there was a communication error
        LD      A,1
        CALL    DOWNLOADDATA
        RET     C

; The routine return A = status code,
; ENDTRANSFER means the transfer ended.
; Note that the last block of data was transferd in the previous call,
; which means tht in this call (the last call) there will never be data to save.
        CP      ENDTRANSFER
        RET     Z

; The routine returned SUCCESS, this means the block of data was transferred,
; Also means there may be more data, and another call is needed (fater saving this block)
; If the STATUS code is something else, set flag C and terminate the routine with error
        CP      RC_SUCCESS
        SCF
        RET     NZ

; Set HL with the number of bytes transfered.
; This is needed because the last block may be smaller than DSKNUMREGISTERS,
; And this math below will make sure only the actual number of bytes are written to disk.
; When the DOWNLOADDATA routine ends, DE contain the DMA + number of bytes transfered
; Also, clearing Carry with "OR A" "is required or the math may be incorrect.
        LD      HL,DMA
        EX      DE,HL
        OR      A
        SBC     HL,DE
        CALL    DSKWRITEBLK
        JR      DSKREADBLK

READPARMS:
VERDRIVE:
; READ FILENAME
        LD      DE,DMA
        CALL    RECVDATABLOCK
        PUSH    AF
        XOR     A
        LD      (DE),A
        POP     AF
        RET     C
        LD      HL,DMA+1
        LD      A,(HL)
        DEC     HL
        CP      ":"
        JR      Z,GETDRIVEID
        XOR     A

; This function will fill the FCB with a valid filename
; Longer filenames are truncated yo 8.3 format.

GET_NAME:
READPARMS0:
        LD      DE,FILEFCB
        LD      (DE),A
        INC     DE
        LD      B,8
READPARMS1:
        LD      A,(HL)
        CP      "."
        JR      Z,FILLNAME
        CP      0
        JR      Z,FILLNAMEEXT
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    READPARMS1

GET_EXT:
        LD      B,3
        LD      A,(HL)
        INC     HL
        CP      0
        JR      Z,FILLEXT
        CP      "."
        JR      Z,READPARMS1B
        DEC     HL
READPARMS1B:
        LD      A,(HL)
        CP      0
        JR      Z,FILLEXT
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    READPARMS1B
        RET

FILLNAMEEXT:
        INC     B
        INC     B
        INC     B
        JR      FILLEXT

FILLNAME:
        LD      A,$20
FILLNAME0:
        LD      (DE),A
        INC     DE
        DJNZ    FILLNAME0
        JR      GET_EXT

FILLEXT:
        LD      A,$20
FILLEXT0:
        LD      (DE),A
        INC     DE
        DJNZ    FILLEXT0
        RET

GETDRIVEID:
READPARMS3:
        LD      A,(HL)
        LD      B,'A'
        CP      'a'
        JR      C,READPARMS4
        LD      B,'a'
READPARMS4:
        SUB     B
        ADD     1
        INC     HL
        INC     HL
        JR      GET_NAME

OPENFILEW:
        LD      DE,FILEFCB
        LD      C,$16
        CALL    BDOS
        OR      A
        RET     Z
; Error opening file
        SCF
        RET


DSKWRITEBLK:
        LD      DE,FILEFCB
        LD      C,$26
        CALL    BDOS
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
        LD      DE,DMA
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

CHECK_ESC:
	ld	b,7
	in	a,(0AAh)
	and	11110000b
	or	b
	out	(0AAh),a
	in	a,(0A9h)	
	bit	2,a
	jr	nz,CHECK_ESC_END
	scf
CHECK_ESC_END:
	ret

PCOPYCMD:   DB      "PCOPY"
LOADROMCMD: DB      "PLOADROM"
FNTITLE:    DB      "Saving file:$"
PICOMMERR:  DB      "Communication Error",13,10,"$"
LOADPROGERRMSG: DB  "Error download file from network",13,10,10
FOPENERR:   DB      "Error opening file",13,10,"$"
PARMSERR:   DB      "Invalid parameters",13,10,"$"
RUNOPTION:  db  0
SAVEOPTION: db  0
REGINDEX:   dw  0
FILEFCB:    ds     40
INCLUDE "debug.asm"
INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

DMA:     EQU    $
