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
        CP      RC_CONNERR
        JR      Z,PRINTERRMSG
        LD      HL,PICRCERR
        CP      RC_CRCERROR
        JR      Z,PRINTERRMSG
        LD      HL,DSKERR
        CP      RC_DSKIOERR
        JR      Z,PRINTERRMSG
        LD      HL,PIUNKNERR
PRINTERRMSG:
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

; BLOCK SIZE TO USE -- will be determined by RPi
;        LD      BC,DSKNUMREGISTERS

; Buffer where data is stored during transfer, and also DMA for disk access
        LD      DE,DMA

; READ ONE BLOCK OF DATA AND STORE IN THE DMA

; A = 1 Tells the download routine to show dots or every 256 bytes transfered
; HL = buffer to store data
; The routine returns C set is there was a communication error
        LD      A,1
        CALL    BUFRECV
        RET     C

; The routine return
;     Carry set for any error
;     A = status code
;    DE = size of the last block received
;
; A = ENDTRANSFER means the transfer ended.
; Note that the last block of data was transferd in the previous call,
; which means that in this call (the last call) there will never be data to save.
        CP      ENDTRANSFER
        JR      NZ,DSKREADBLK1
        CALL    DSKWRITE
        OR      A
        LD      A,RC_SUCCESS
        RET     Z
        LD      A,RC_DSKIOERR
        SCF
        RET

; The routine returned SUCCESS, this means the block of data was transferred,
; Also means there may be more data, and another call is needed (fater saving this block)
; If the STATUS code is something else, set flag C and terminate the routine with error
DSKREADBLK1:
        CP      RC_SUCCESS
        SCF
        RET     NZ
        CALL    DSKWRITE
        OR      A
        JR      Z,DSKREADBLK
        LD      A,RC_DSKIOERR
        RET

DSKWRITE:
; DE contain size of buffer
; DSKWRITEBLK needs DE=buffer and HL=size of buffer
        LD      HL,DMA
        EX      DE,HL
        CALL    DSKWRITEBLK
        RET


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

BUFSEND:
; Send BC blocks of size DE in buffer HL
; All registers are mnodified.
; The number of blocks, and block size is sent first
; Inputs:
;   bc = number of blocks
;   de = block size
;   hl = buffer address
;   A = 1 to show dots
; Outputs:
; Carry Flg: set for any error detected
; A = error code:
;     RC_SUCCESS
;     RC_CRCERROR
;     RC_CONNERR
        push    af
        or      a
        jr      z,BUFSEND0
        ld      a,'.'
        call    PUTCHAR
BUFSEND0:
; Transfer 1 block (stored in DE)
        exx
        call    BLOCKSEND
        exx
        jr      c,BUFERR
        dec     bc
        ld      a,b
        or      c
; If zero, transfer is completed and jump to END
        jr      z,BUFSNDEND
; DE is updated to next block of data
; (previous value + block size)
        add     hl,de
; restore dots flag
        pop     af
        jr      BUFSEND
BUFERR:
        pop     bc
        scf
        ret
BUFSNDEND:
        pop     af
        ld      a,RC_SUCCESS
        or      a
        ret

BLOCKSEND:
;-------------------------------------------------------
; Send DE bytes from buffer in HL
; Check CRC and retry the number of GLOBARETRIES
;     (retries is specified by RPi)
; The number of bytes to transfer is sent first to RPi
; Inputs:
;   de = number of bytes to send
;   hl = buffer address
; Outputs:
; Carry Flg: set for any error detected
; A = error code:
;     RC_SUCCESS
;     RC_CRCERROR
;     RC_CONNERR
;
; AF,DE,HL are modified.
;-------------------------------------------------------
; Start syncing with RPi
        ld      a,STARTSENDER
        call    PIEXCHANGEBYTE
; If there was a communication error, stop routine
        jr      c,BLKSNDERR2
        cp      STARTTRANSFER
        jr      nz,BLKSNDERR2
; Get number of retries
        call    PIEXCHANGEBYTE
        cp      MAXRETRIES+1
        jr      nc,BLKSNDERR2
;ld      ixl,a
; Send size of buffer
        ld      a,e
        call    PIWRITEBYTE
        ld      a,d
        call    PIWRITEBYTE
; All set, will start data transfer
; Save BC
        push    bc
; Transfer the number of bytes stored in DE
BLKTRPSAV:
        push    de
        push    hl
        ld      c,0     ;c=crc
BLKSNDLOOP:
        ld      a,(hl)
        ld      b,a
; Calc CRC
        xor     c
        ld      c,a
        ld      a,b
        call    PIWRITEBYTE
        jr      c,BLKSNDERR1
        inc     hl
        dec     de
        ld      a,d
        or      e
        jr      nz,BLKSNDLOOP
; finished transf. Check CRC
        ld      a,c
        call    PIEXCHANGEBYTE
; If CRC does not match, jump to crcerror routine
        pop     hl
        pop     de
        cp      c
        jr      z,BLKSNDEND
;dec     ixl
        jr      nz,BLKTRPSAV
        pop     bc
        ld      a,RC_CRCERROR
        scf
        ret
BLKSNDERR1:
        pop     hl
        pop     de
        pop     bc
BLKSNDERR2:
        ld      a,RC_CONNERR
        scf
        ret
BLKSNDEND:
        pop     bc
        ld      a,RC_SUCCESS
        ret


BUFRECV:
; Read blocks of data from until receive ENDTRANSFER or error
; All registers are mnodified.
; Inputs:
;   hl = buffer address
;   A = 1 to show dots every block transfered
; Outputs:
; Carry Flg: set for any error detected
; A = error code:
;     RC_SUCCESS
;     RC_CRCERROR
;     RC_CONNERR
;     ENDTRANSFER
        push    af
        or      a
        jr      z,BUFRCV0
        ld      a,'.'
        call    PUTCHAR
BUFRCV0:
; Sync
        ld      a,STARTTRANSFER
        call    PIEXCHANGEBYTE
; If there was a communication error, stop routine
        jr      c,BUFRCVERR2
        cp      STARTTRANSFER
        jr      nz,BUFRCVERR1
; Transfer 1 block (stored in DE)
        push    hl
        call    BLOCKRECV       ;DE return size of block receivd
        pop     hl
        add     hl,de       ;next address in buffer
        cp      RC_SUCCESS
        jr      nz,BUFRCVERR1
; Block received. Verify if there is more data
        ld      a,STARTTRANSFER
        call    PIEXCHANGEBYTE
; If there was a communication error, stop routine
        jr      c,BUFRCVERR2
        cp      ENDTRANSFER
        jr      z,BUFRCVEND
        cp      STARTTRANSFER
        jr      nz,BUFRCVERR2
; restore dots flag
        pop     af
        jr      BUFRECV
BUFRCVERR1:
        pop     de      ;Discard flag in register A,
                        ;preserving return code in A
; error. A contain error code
        scf
        ret
BUFRCVERR2:
        ld      a,RC_CONNERR
        jr      BUFRCVERR1
BUFRCVEND:
        pop     af
        ld      a,ENDTRANSFER
        or      a
        ret

BLOCKRECV:
;-------------------------------------------------------
; RECEIVE a single block of bytes and store in buffer pointed by HL
; Check CRC and retry the number of GLOBARETRIES
;     (retries is specified by RPi)
; The number of bytes to transfer is received first from RPi
; Inputs:
;   HL = buffer address
; Outputs:
; Carry Flg: set for any error detected
;   DE = number of bytes received
;   A = error code:
;     RC_SUCCESS
;     RC_CRCERROR
;     RC_CONNERR
;
; AF,BC,DE,HL are modified.
;-------------------------------------------------------
; Start syncing with RPi
        ld      a,STARTTRANSFER
        call    PIEXCHANGEBYTE
; If there was a communication error, stop routine
        jr      c,BLKRCVERR2
        cp      STARTTRANSFER
        jr      nz,BLKRCVERR2
; Get number of retries
        call    PIEXCHANGEBYTE
        cp      MAXRETRIES+1
        jr      nc,BLKRCVERR2
        push    af
; Recv size of block
        call    PIWRITEBYTE
        ld      e,a
        call    PIWRITEBYTE
        ld      d,a
; All set, will start data transfer
; DE is saved to return to the caller the size of the block
        pop     af
        push    de
; Transfer the number of bytes stored in DE
BLKTRPSAV:
        push    af      ;retries
        push    de      ;size of block
        push    hl      ;buffer address
        ld      c,0     ;c=crc
BLKRCVLOOP:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        jr      c,BLKRCVERR1
        ld      (hl),a
; Calc CRC
        xor     c
        ld      c,a
        inc     hl
        dec     de
        ld      a,d
        or      e
        jr      nz,BLKRCVLOOP
; finished transf. Check CRC
        ld      a,c
        call    PIEXCHANGEBYTE
; If CRC does not match, jump to crcerror routine
        pop     hl
        pop     de
        cp      c
        jr      z,BLKRCVEND
        pop     af
        dec     a
        jr      nz,BLKTRPSAV
        pop     de
        pop     bc
        ld      a,RC_CRCERROR
        scf
        ret
BLKRCVERR1:
        pop     hl
        pop     de
        pop     af
        pop     de      ;size of block
BLKRCVERR2:
        ld      a,RC_CONNERR
        scf
        ret
BLKRCVEND:
        pop     af
        pop     de
        ld      a,RC_SUCCESS
        ret
PCOPYCMD:   DB      "PCOPY"
LOADROMCMD: DB      "PLOADROM"
FNTITLE:    DB      "Saving file:$"
PICOMMERR:  DB      "Communication Error",13,10,"$"
PIUNKNERR:  DB      "Unknown error",13,10,"$"
PICRCERR:   DB      "CRC Error",13,10,"$"
DSKERR:     DB      "DISK IO ERROR",13,10,"$"
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
