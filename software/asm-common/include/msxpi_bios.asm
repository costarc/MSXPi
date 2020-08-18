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
; 0.9    : Simplification of block transfers routines.
;          Removed some deprecated routines.
; 0.8    : Re-worked protocol as protocol-v2:
;          RECVDATABLOCK, SENDDATABLOCK, SECRECVDATA, SECSENDDATA,CHKBUSY
;          Moved to here various routines from msxpi_api.asm
; 0.7    : Replaced CHKPIRDY retries to $FFFF
;          Removed the RESET when PI is not responding. This is now responsability
;           of the calling function, which might opt to do something else.
; 0.6c   : Initial version commited to git
;

;-----------------------
; SYNCH                |
;-----------------------
SYNCH:
            push    bc
            push    de
            in      a,(CONTROL_PORT2)
            cp      9
            jr      nc,SYNCH1
            ld      a,RESET
            call    SENDIFCMD
SYNCH1:
            call    CHKPIRDY
            ld      bc,4
            ld      de,PINGCMD
            call    SENDPICMD
            pop     de
            pop     bc
            ret     c
            call    PIEXCHANGEBYTE
            ret     c
            cp      RC_SUCCNOSTD
            ret     z
            call    PSYNCH
            ret

; Restore communication with Pi by sending ABORT commands
; Until RPi responds with READY.

PSYNCH:
        CALL    TRYABORT
        LD      BC,4
        LD      DE,PINGCMD
        CALL    SENDPICMD
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_SUCCNOSTD
        JR      NZ,PSYNCH
        RET

TRYABORT:
        LD      A,ABORT
        CALL    PIEXCHANGEBYTE
        CP      READY
        JR      NZ,TRYABORT
        RET

PRECON_ERR:
        EI
        SCF
        RET

PINGCMD: DB      "ping",0

; Input:
; A = byte to calculate CRC
; HL' = Current CRC 
; Output:
; HL' = CRC
; 
CRC16:
        exx
        xor     h
        ld      h,a
        ld      b,8
rotate16:
        add     hl,hl ; 11t - rotate crc left one
        jr      nc, nextbit16 ; 12/7t - only xor polyonimal if msb set
        ld      a,h ; 4t
        xor     $10 ; 7t - high byte with $10
        ld      h,a ; 4t
        ld      a,l ; 4t
        xor     $21 ; 7t - low byte with $21
        ld      l,a ; 4t - hl now xor $1021
nextbit16:
        djnz rotate16 ; 13/8t - loop over 8 bits
        exx
        ret

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
; It will return with return code ENDTRANSFER when
;    size of block = zero
; Input:
;   de = memory address to write the received data
; Output:
;   Flag C set if error
;   A = error code
;   BC = number of bytes received, 0 if finished transfer
;   de = Original address if routine finished in error,
;   de = Next current address to write data when terminated successfully
; -------------------------------------------------------------
RECVDATABLOCK:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        cp      SENDNEXT
        scf
        ld      a,RC_OUTOFSYNC
        ret     nz
;Get number of bytes to transfer
        call    READDATASIZE
        ld      a,b
        or      c
        ld      a,ENDTRANSFER
        ret     z

        push    de
; Get number of attempts
        call    PIEXCHANGEBYTE
        ld      l,a     ; number of attempts

RECVDATABLOCK0:
        push    bc      ; blocksize   
; CLEAR CRC and save block size
        exx
        ld      hl,$ffff
        exx
RECVDATABLOCK1:

; send info that msx is in transfer mode
        call    PIEXCHANGEBYTE
        ld      (de),a
        call    CRC16
        inc     de
		dec     bc
        ld      a,b
        or      c
        jr      nz,RECVDATABLOCK1

; Now exchange CRC
        exx
        ld      a,l
        call    PIEXCHANGEBYTE
        cp      l
        jr      nz,RECVDATABLOCK_CRCERROR
        ld      a,h
        call    PIEXCHANGEBYTE
        cp      h
        jr      nz,RECVDATABLOCK_CRCERROR
        exx

;Return number of bytes read
        pop     bc
; Discard de, because we want to return current memory address
        pop     af
        ld      a,RC_SUCCESS
        or      a
        ret

; Return de to original value and flag error
RECVDATABLOCK_CRCERROR:
        exx
        pop     bc             ; restore blocksize
        ld      a,l            ; get number of attemps
        dec     a
        ld      l,a
        or      a
        jr      nz,RECVDATABLOCK0  ; try again
        pop     de                 ; restore original address in DE
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
        ld      a,RC_OUTOFSYNC
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
        ld      a,RC_SUCCESS
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


; =================================================================
; PRINTPISTDOUT (Same as RECVDATABLOCK but printing to SCREEN) 
; Inputs: (PRINTPISTDOUT0)
;  E = 0 - Print data to screen
;      $ff - Do not print
; Output:
; HL' = CRC16
; A = Return Code (RC_SUCCESS or RC_CRCERROR)
;
; Changes: AF,BC,E,L,HL',BC'
; =================================================================
PRINTPISTDOUT:
        ld      e,0

PRINTPISTDOUT0:
    ; CLEAR CRC and save block size
        exx
        ld      hl,$ffff
        exx
PRINTPISTDOUT1:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        cp      SENDNEXT
        ld      a,RC_OUTOFSYNC
        ret     nz
PRINTPI0:
        call    READDATASIZE
        ld      a,b
        or      c
        ld      a,ENDTRANSFER
        ret     z
        call    PIEXCHANGEBYTE    ; read attempts, but will not use it
PRINTPI1:
        ld      a,SENDNEXT
        call    PIEXCHANGEBYTE
        push    af
        call    CRC16
        pop     af
        ld      l,a
        ld      a,e
        cp      $ff
        jr      z,PRINTPI3          ; nostdout - not printing to screen
        ld      a,l
        cp      10
        jr      nz,PRINTPI2
        call    PUTCHAR
        ld      a,13
PRINTPI2:
        call    PUTCHAR
PRINTPI3:
        dec     bc
        ld      a,b
        or      c
        jr      nz,PRINTPI1

; Now exchange CRC
        exx
        ld      a,l
        call    PIEXCHANGEBYTE
        cp      l
        jr      nz,PRINTPI4
        ld      a,h
        call    PIEXCHANGEBYTE
        cp      h
        jr      nz,PRINTPI4
        ld      a,RC_SUCCESS
        jr      PRINTPI5
PRINTPI4: 
        ld      a,RC_CRCERROR
PRINTPI5:
        exx
        ret

NOSTDOUT:
        push    de
        ld      e,$ff
        call    PRINTPISTDOUT0
        pop     de
        ret
        
STRTOHEX:
; Convert the 4 bytes ascii values in buffer HL to hex
        PUSH    DE
        LD      DE,0
        LD      A,(HL)
        CALL    ATOHEX
        JR      C,STREXIT
        SLA     A
        SLA     A
        SLA     A
        SLA     A
        LD      D,A
        INC     HL
        LD      A,(HL)
        CALL    ATOHEX
        JR      C,STREXIT
        OR      D
        LD      D,A
        INC     HL
        LD      A,(HL)
        CALL    ATOHEX
        JR      C,STREXIT
        SLA     A
        SLA     A
        SLA     A
        SLA     A
        LD      E,A
        INC     HL
        LD      A,(HL)
        CALL    ATOHEX
        JR      C,STREXIT
        OR      E
        LD      H,D
        LD      L,A
STREXIT:POP     DE
        RET
ATOHEX:
        CP      '0'
        RET     C
        CP      '9'+1
        JR      NC,ATOHU
        SUB     '0'
        RET
ATOHU:
        CP      'A'
        RET     C
        CP      'G'
        JR      NC,ATOHL
        SUB     'A'-10
        RET
ATOHL:
        CP      'a'
        RET     C
        CP      'g'
        JR      NC,ATOHERR
        SUB     'a'-10
        RET
ATOHERR:
        SCF
        RET

; Evaluate CALL Commands to check for optional parameters
; Returns Buffer address in HL (or HL=0000 if parameter not found)
; Input:
;  DE = Call full command (after the ")
; Output:
;  A = Outout type (as below cases)
;  DE = Point to start of command to send to RPi (pdir in the case below)
;  HL = Address of buffer to store data if stdout = 2
;
; Cases:
; call mspxi("pdir")  -> will print the output
; call mspxi("0,pdir")  -> will not print the output
; call msxpi("1,pdir")  -> will print the output to screen
; call msxpi("2,F000,pdir")  -> will store output in buffer (MSXPICALLBUF - $E3D8)
; 
PARMSEVAL:
        INC     DE
        LD      A,(DE)
        DEC     DE
        CP      ','
        LD      A,'1'
        JR      NZ,PARMSEVAL1      ; no output device privided, USE DEFAULT
        LD      A,(DE)
        PUSH    AF                 ; save output device
        INC     DE
        INC     DE
        DEC     B
        DEC     B
        POP     AF
PARMSEVAL1:
        PUSH    AF
; Check if a buffer address has been passed
        PUSH    DE
        INC     DE
        INC     DE
        INC     DE
        INC     DE
        LD      A,(DE)
        CP      ','
        JR      NZ,PARMSEVAL2       ; no buffer address provided

; CALL has a buffer address in this format:
; CALL MSXPI("XXXX,COMMAND")
; Move pointer to start of command
        INC     DE                  ; Point to command (pdir)
        DEC     B                   ;
        DEC     B
        DEC     B
        DEC     B
        DEC     B
        POP     HL
; Convert ascii chars pointed by HL to hex. Return value in HL
; Flag C is set if there was an error
        CALL    STRTOHEX
        POP     AF
        RET

; CALL did not have buffer address.
; We set this case with 00 n the stack
PARMSEVAL2:
        POP     DE 
        POP     AF
;Buffer not passed in CALL, then we set adddress to 0000
        LD      HL,0
        RET

; -------------------------------------------------------------
; CHECK_ESC
; -------------------------------------------------------------
; This routine is required by the communication
; protocol to allow user to ESCAPE from a blocked state
; when Pi stops responding MSX for some reason.
; Note that this routine must be called by you in your code.
; -------------------------------------------------------------
CHECK_ESC:
        LD      B,7
        IN      A,($AA)
        AND     11110000b
        OR      B
        OUT     ($AA),A
        IN      A,($A9)
        BIT     2,A
        JR      NZ,CHECK_ESC_END
        SCF
CHECK_ESC_END:
        RET

TESTMSXPISTR:
        DB      'MSXPi'
confatual:
        DB      00
slotatual:
        DB      00
subsatual:
        DB      00




