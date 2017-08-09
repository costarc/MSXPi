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
; 0.8    : Re-worked protocol as protocol-v2:
;          RECVDATABLOCK, SENDDATABLOCK, SECRECVDATA, SECSENDDATA,CHKBUSY
;          Moved to here various routines from msxpi_api.asm
; 0.7    : Replaced CHKPIRDY retries to $FFFF
;          Removed the RESET when PI is not responding. This is now responsability
;           of the calling function, which might opt to do something else.
; 0.6c   : Initial version commited to git
;

; Inlude file for other sources in the project

;-----------------------
; SYNCH                |
;-----------------------
SYNCH:
            push    bc
            push    de
            ld      a,RESET
            call    SENDIFCMD
            call    CHKPIRDY
            ld      bc,3
            ld      de,CHKPICMD
            call    SENDPICMD
            pop     de
            pop     bc
            ret     c
            call    PIEXCHANGEBYTE
            ret     c
            cp      READY
            ret     z
            cp      ABORT
            scf
            ret     z
            cp      SENDNEXT
            jr      nz, SYNCH
            ret

CHKPICMD:   DB      "SYN",0

;-----------------------
; SENDPICMD            |
;-----------------------
; Send a command to Raspberry Pi
; Input:
;   de = should contain the command string
;   bc = number of bytes in the command string
; Output:
;   Flag C set if there was a communication error
SENDPICMD:
; Save flag C which tells if extra error information is required
		call    SENDDATABLOCK
        ret

;-----------------------
; RECVDATABLOCK        |
;-----------------------
; 21/03/2017
; Receive a number of bytes from PI
; This routine expects PI to send SENDNEXT control byte
; Input:
;   de = memory address to write the received data
; Output:
;   Flag C set if error
;   A = error code
;   de = Original address if routine finished in error,
;   de = Next current address to read if finished successfully
; -------------------------------------------------------------
RECVDATABLOCK:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        cp      SENDNEXT
        scf
        ret     nz

;Get number of bytes to transfer
        call    READDATASIZE

; CLEAR CRC and save block size
        ld      h,0
        push    bc
        push    de

RECVDATABLOCK1:
; send info that msx is in transfer mode
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        ld      (de),a
        xor     h
        ld      h,a
        inc     de
		dec     bc
        ld      a,b
        or      c
        jr      nz,RECVDATABLOCK1

; Now exchange CRC

        ld      a,h
        call    PIEXCHANGEBYTE

; Compare CRC received with CRC calcualted

        cp      h
        jr      nz,RECVDATABLOCK_CRCERROR

; Discard de, because we want to return current memory address

        pop     af

;Return number of bytes read

        pop     bc
        or      a
        ret

; Return de to original value and flag error
RECVDATABLOCK_CRCERROR:
        pop     de
        pop     bc
        ld      a,RC_CRCERROR
        scf
        ret

;-------------------
; SENDDATABLOCK    |
;-------------------
; 21/03/2017
; Send a number of bytes to MSX
; This routine expects PI to send SENDNEXT control byte
; Input:
;   bc = number of byets to send
;   de = memory to start reading data
; Output:
;   Flag C set if error
;   A = error code
;   de = Original address if routine finished in error,
;   de = Next current address to read if finished successfully
; -------------------------------------------------------------
SENDDATABLOCK:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        cp      SENDNEXT
        scf
        ret     nz

; MSX is synced with PI, then send size of block to transfer
        ld      a,c
        call    PIWRITEBYTE
        ld      a,b
        call    PIWRITEBYTE

; clear H to calculate CRC using simple xor oepration
        ld      h,0
        push    de

; loop sending bytes until bc is zero
SENDDATABLOCK1:
        ld      a,(de)
        ld      l,a
        xor     h
        ld      h,a
        ld      a,l
        call    PIWRITEBYTE
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,SENDDATABLOCK1

; Finished sending block of data
; Now exchange CRC

        ld      a,h
        call    PIEXCHANGEBYTE

; Compare CRC received with CRC calcualted

        cp      h
        jr      nz,SENDDATABLOCK_CRCERROR

; Discard de, because we want to return current memory address
        pop     af
        or      a
        ret

; Return de to original value and flag error
SENDDATABLOCK_CRCERROR:
        pop     de
        ld      a,RC_CRCERROR
        scf
        ret

; Return de to original value and flag error
SENDDATABLOCK_OFFSYNC:
        ld      a,RC_OUTOFSYNC
        scf
        ret

;-------------------
; SECRECVDATA      |
;-------------------
; 21/03/2017
; Read data in 512 bytes blocks
; This routine expects PI to send SENDNEXT control byte
; Input:
;   de = memory address to store data
; Output:
;   Flag C set if error
; -------------------------------------------------------------
SECRECVDATA:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        cp      SENDNEXT
        scf
        ret     nz

;Get number of bytes to transfer
        call    READDATASIZE

SECRECVDATA0:
; save remaining bytes qty
        push    bc
        ld      a,GLOBALRETRIES
SECRECVDATARETRY:
; retries
        push    af
        push    de
        call    RECVDATABLOCK
        jr      nc,SECRECVDATA1
        pop     de
        pop     af
        dec     a
        jr      nz,SECRECVDATARETRY

SECRECVDATAERR:
        pop     af
        scf
        ret

SECRECVDATA1:
        pop     af
        pop     af
;get remaining bytes to transfer
        pop     hl
        ld      bc,512
        sbc     hl,bc
        jr      c,SECRECVDATAEND
        jr      z,SECRECVDATAEND
        ld      b,h
        ld      c,l
        jr      SECRECVDATA0

; File load successfully.
; Return C reseted, and A = filetype
SECRECVDATAEND:
        or      a               ;reset c flag
        ret

;-------------------
; SECSENDDATA      |
;-------------------
; 21/03/2017
; Read data in 512 bytes blocks
; This routine expects PI to send SENDNEXT control byte
; Input:
;   bc = total number of bytes to send
;   de = memory address to read data
; Output:
;   Flag C set if error
; -------------------------------------------------------------
SECSENDDATA:
        call    CHECKBUSY
        ret     c

;Get number of bytes to transfer
        call    SENDDATASIZE
        ret     c

SECSENDDATA0:
; save remaining bytes qty
        push    bc
        ld      a,GLOBALRETRIES
SECSENDDATARETRY:
; retries
        push    af
        push    de
        call    SENDDATABLOCK
        jr      nc,SECSENDDATA1
        pop     de
        pop     af
        dec     a
        jr      nz,SECSENDDATARETRY

SECSENDDATAERR:
        pop     af
        scf
        ret

SECSENDDATA1:
        pop     af
        pop     af
;get remaining bytes to transfer
        pop     hl
        ld      bc,512
        sbc     hl,bc
        jr      c,SECSENDDATAEND
        jr      z,SECSENDDATAEND
        ld      b,h
        ld      c,l
        jr      SECSENDDATA0

; File load successfully.
; Return C reseted, and A = filetype
SECSENDDATAEND:
        or      a               ;reset c flag
        ret

READDATASIZE:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        ld      c,a
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        ld      b,a
        ret

SENDDATASIZE:
        ld      a,c
        call    PIEXCHANGEBYTE
        ld      a,b
        call    PIEXCHANGEBYTE
        ret


;-------------------
; DOWNLOADDATA     |
;-------------------
; Load data using configurable block size.
; Every call will read next block until data ends.
; Input:
;   A  = 1 to show dots for every 256 bytes
;   BC = block size to transfer
;   DE = Buffer to store data
; Output:
;   Flag C: Set if occurred and error during transfer,such as CRC
;        Z: Set if end of data
;           Unset if there is still data
;        A: Error code
;           A = error code, or
;           A = RC_SUCCESS - block transfered, there is more data
;           A = ENDTRANSFER - end of transfer, no more data.
;
; Modifies: AF,BC,DE,HL
;
DOWNLOADDATA:
; save option to show dots
        ld      l,a

; Synch start of transfer
        ld      a,STARTTRANSFER
        call    PIEXCHANGEBYTE
        ret     c
        cp      ENDTRANSFER
        ret     z
        cp      STARTTRANSFER
; Inexpected control code received.
        ret     nz
; Pi was not expecting this, then error

; now send block size
        ld      a,c
        call    PIEXCHANGEBYTE
        ld      a,b
        call    PIEXCHANGEBYTE

; And received Pi info if there is still data or if data has ended
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        cp      ENDTRANSFER
        ret     z

; Maybe the remaining data size is smaller than a block.
; Because of that, we now read back the actual block size that should be read

        call    READDATASIZE
;       call    DBGBC

RETRYLOOP:

; Initialize crc checker
        ld      h,0

; start rading the data
READDLOOP:
        ld      a,l
        or      a
        jr      z,READDLOOP2
        inc     a
        or      a
        jr      nz,READDLOOP1
        inc     a
        ld      l,a
        ld      a,"."
        call    PUTCHAR
        jr      READDLOOP2
READDLOOP1:
        ld      l,a
READDLOOP2:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        ld      (de),a
        xor     h
        ld      h,a
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,READDLOOP
; now exchange CRC with Pi
        ld      a,h
        call    PIEXCHANGEBYTE
        cp      h
        ld      a,RC_SUCCESS
        ret     z
        ld      a,RC_CRCERROR
        ret

;-------------------
; UPLOADDATA     |
;-------------------
; TO-DO
UPLOADDATA:
        ret

;-------------------
; LOADBINPROG      |
;-------------------
; Load a .bin program in BASIC environment
LOADBINPROG:
        ld      a,STARTTRANSFER
        call    PIEXCHANGEBYTE
        cp      STARTTRANSFER
        scf
        ccf
        ret     nz

; get filesize from PI and put in bc
        call    READDATASIZE

; Read file header and check if it is BASIC binary program
        ld      a,SENDNEXT
       	call    PIEXCHANGEBYTE

; Read start address
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        ld      e,a
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        ld      d,a

; Discard END address
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE

; Read EXEC address
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        ld      l,a
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        ld      h,a
        push    hl
        call    LOADBINBLOCKS
        pop     hl
        ret

;Read 512 bytes at a time
LOADBINBLOCKS:
        push    bc
        ld      a,GLOBALRETRIES
LOADBINRETRY:
        push    af
        call    RECVDATABLOCK
        jr      nc,LOADBIN1
        pop     af
        dec     a
        jr      nz,LOADBINRETRY
        pop     bc
        ld      a,RC_CRCERROR
        ret

LOADBIN1:
		ld      a,'.'
        call    PUTCHAR
        pop     af

; Restore number of bytes left
        pop     hl

        sbc     hl,bc
        jr      c,LOADBINEND
        jr      z,LOADBINEND
        ld      b,h
        ld      c,l
        jr      LOADBINBLOCKS
LOADBINEND:
        ld      a,ENDTRANSFER
        call    PIEXCHANGEBYTE
        cp      ENDTRANSFER
        ret     z
        ld      a,RC_OUTOFSYNC
        SCF
        ret

CHECKBUSY:
        push    bc
        ld      b,BUSYRETRIES
CHECKBUSY1:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        cp      SENDNEXT
        jr      z,CHECKBUSY3
        cp      ABORT
        jr      z,CHECKBUSY2
        ld      a,RESET
        call    SENDIFCMD
        djnz    CHECKBUSY1
CHECKBUSY2:
        SCF
CHECKBUSY3:
        pop     bc
        ret

;-----------------------
; PRINT                |
;-----------------------
PRINT:
        push    af
        ld      a,(hl)		;get a character to print
        cp      TEXTTERMINATOR
        jr      Z,PRINTEXIT
        cp      10
        jr      nz,PRINT1
        pop     af
        push    af
        ld      a,10
        jr      nc,PRINT1
        call    PUTCHAR
        ld      a,13
PRINT1:
        call	PUTCHAR		;put a character
        INC     hl
        pop     af
        jr      PRINT
PRINTEXIT:
        pop     af
        ret

PRINTNLINE:
        ld      a,13
        call    PUTCHAR
        ld      a,10
        call    PUTCHAR
        ret

;-----------------------
; PRINTNUMBER          |
;-----------------------
PRINTNUMBER:
        push    de
        ld      e,a
        push    de
        AND     0F0H
        rra
        rra
        rra
        rra
        call    PRINTDIGIT
        pop     de
        ld      a,e
        AND     0FH
        call    PRINTDIGIT
        pop     de
        ret

PRINTDIGIT:
        cp      0AH
        jr      c,PRINTNUMERIC
PRINTALFA:
        ld      d,37H
        jr      PRINTNUM1

PRINTNUMERIC:
        ld      d,30H
PRINTNUM1:
        add     a,d
        call    PUTCHAR
        ret

PRINTPISTDOUT:
        push    af
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        cp      SENDNEXT
        jr      z,PRINTPI0
        pop     af
        scf
        ret
PRINTPI0:
        call    READDATASIZE
        pop     af
        push    hl
        ld      h,0
PRINTPI1:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        ld      l,a
        xor     h
        ld      h,a
        ld      a,l
        cp      10
        jr      nz,PRINTPI2
        call    PUTCHAR
        ld      a,13
PRINTPI2:
        call    PUTCHAR
        dec     bc
        ld      a,b
        or      c
        jr      nz,PRINTPI1
        ld      a,h
        call    PIEXCHANGEBYTE
        pop     hl
        ret
