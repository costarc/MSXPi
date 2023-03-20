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

; ==================================================================
; BASIC I/O FUNCTIONS STARTS HERE.
; These are the lower level I/O routines available, and must match
; the I/O functions implemented in the CPLD.
; Other than using these functions you will have to create your
; own commands, using OUT/IN directly to the I/O ports.
; ==================================================================

NOSTDOUT: ret

;-----------------------
; CHKPIRDY             |
;-----------------------
CHKPIRDY:
        ld      a,7
        out    ($AA),a
        in      a,($A9)
        bit     2,a                         ; Test ESC key 
        scf
        ret     z
        in      a,(CONTROL_PORT1)  ; verify spirdy register on the msxinterface
        or      a
        jr      nz,CHKPIRDY
        ret

;-----------------------
; PIREADBYTE           |
;-----------------------
PIREADBYTE:
            call    CHKPIRDY
            jr      c,PIREADBYTE1
            xor     a                  ; do not use xor to preserve c flag state
            out     (CONTROL_PORT1),a  ; send read command to the interface
            call    CHKPIRDY           ; wait interface transfer data to pi and
                                       ; pi app processing
                                       ; no ret c is required here, because in a,(7) 
                                       ; does not reset c flag
PIREADBYTE1:
            in      a,(DATA_PORT1)     ; read byte
            ret                        ; return in a the byte received

;-----------------------
; PIWRITEBYTE          |
;-----------------------
PIWRITEBYTE:
            push    af
            call    CHKPIRDY
            pop     af
            out     (DATA_PORT1),a     ; send data, or command
            ret

;-----------------------
; PIEXCHANGEBYTE       |
;-----------------------
PIEXCHANGEBYTE:
            call    PIWRITEBYTE
            call    CHKPIRDY
            in      a,(DATA_PORT1)     ; read byte
            ret

PSYNC:  
        CALL    TRYABORT
        RET     C
        LD      BC,4
        LD      DE,PINGCMD
        CALL    SENDPICMD
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_SUCCNOSTD
        JR      NZ,PSYNC
        RET

TRYABORT:
        LD      A,4
        CALL    SNSMAT
        BIT     5,A
        RET     Z
        LD      A,ABORT
        CALL    PIEXCHANGEBYTE
        CP      READY
        RET     Z
        CP      SENDNEXT
        JR      NZ,TRYABORT
        LD      A,1
        CALL    PIEXCHANGEBYTE
        XOR     A
        CALL    PIEXCHANGEBYTE
        LD      A,'X'
        CALL    PIEXCHANGEBYTE
        CALL    PIEXCHANGEBYTE
        OR      A
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

;---------------------------------------------------------------
; RECVDATA- SENDDATA
;---------------------------------------------------------------
; 01/03/2023
;
; Receive / Send BC bytes of data plus a checksum (1 byte)
; Calculates teh checksum locally as data is coming, and send it back.
; Compares the local checksum with received checksum, and
; if they differ return with C flag set.
;
; Input:
;   de = memory address for the data
;   bc = block size
; Output:
;   Flag C set if error
;  DE next available address
RECVDATA:
RECVDATABLOCK:
        di
        ld      hl,0                       ; will store checksum in HL
RECV0:
        push    bc
        call    PIREADBYTE
        ld      (de),a
        inc     de
        ld      b,0
        ld      c,a
        add     hl,bc
        pop     bc
		dec     bc
        ld      a,b
        or      c
        jr      nz,RECV0
        call    PIREADBYTE      ; read checksum byte from msxpi server
        ld      c,a
        ld      a,l
        add     a,h
        ld      l,a
        call    PIWRITEBYTE     ; send checksum calculated here
        ei
        ld      a,c                         ; get MSXPi chksum
        cp      l                           ; compare checksum
        ret     z                           ; return if match, C is 0
        scf                                 ; differ, set flag for Error
        ret

SENDDATA:
SENDDATABLOCK:
        di
        ld      hl,0                       ; will store checksum in HL
SENDD0:
        push    bc
        ld      a,(de)
        inc     de
        ld      b,0
        ld      c,a
        add     hl,bc
        call    PIWRITEBYTE
        pop     bc
		dec     bc
        ld      a,b
        or      c
        jr      nz,SENDD0
        ld      a,l
        add    a,h                         ; sum two bytes of checksum to obtain final cum
        ld      l,a
        call    PIWRITEBYTE     ; send checksum calculated here
        call    PIREADBYTE      ; read checksum byte from msxpi server
        ei
        cp      l                           ; compare checksum
        ret     z                           ; return if match, C is 0
        scf                                 ; differ, set flag for Error
        ret
        
; -----------------------------------------------------------------------------------------------
; This is the original MSXPi routine as per v1.0.1
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
RECVDATABLOCK_LEGACY:
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

; Get number of attempts
        call    PIEXCHANGEBYTE
        ld      l,a     ; number of attempts

RECVDATABLOCK0:
        push    de
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
        pop     de             ; restore original buffer address
        ld      a,l            ; get number of attemps
        dec     a
        ld      l,a
        or      a
        jr      nz,RECVDATABLOCK0  ; try again
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
SENDDATABLOCK_LEGACY:
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
        ld      a,(hl)		;get a character to print
        cp      TEXTTERMINATOR
        jr      Z,PRINTEXIT
        cp      10
        jr      nz,PRINT1
        call    PUTCHAR
        ld      a,13
PRINT1:
        call	PUTCHAR		;put a character
        inc     hl
        jr      PRINT
PRINTEXIT:
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
        ld      a,(hl)
        or      a
        scf
        ret     z
        cp      10
        jr      nz,printchar
        push    bc
        call    PUTCHAR
        pop     bc
        ld      a,13
printchar:
        call    PUTCHAR
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,PRINTPISTDOUT
        scf
        ccf
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

SENDPARMS:
        call    CLEARBUF
; check if there are parameters in the command line
        ld      hl,$80
        ld      a,(hl)
        ld      b,a
        or      a
        jr      z,SENDPARMS2

; b contain number of chars passed as arguments in the command
        inc     hl
        call    EATSPACES
        jr      c,SENDPARMS2
        ld      de,buf
; Move CLI parameters to buffer
SENDPARMS1:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        djnz    SENDPARMS1
SENDPARMS2:
        ld      de,buf
        ld      bc,BLKSIZE
        call    SENDDATA
        ret

; Send a simple command to MSXPi
; DE = Command name, terminated in zero
; Size is fixed: CMDSIZE
SENDCOMMAND:
        ld      bc,CMDSIZE               ; command lenght set to fixed size
        call      SENDDATA
        ret

SETBUF:
        push    de
        call    CLEARBUF
        pop     hl
        ld      de,buf
SETBUF0:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        or      a
        jr      nz,SETBUF0
        ret
        
CLEARBUF:
        ld      hl,buf
        ld      de,buf + 1
        ld      bc,BLKSIZE
        xor     a
        ld      (hl),a
        ldir
        ret
                
PUTCHAR:
        push    bc
        push    de
        push    hl
        ld      e,a
        ld      c,2
        call   $A2
        pop     hl
        pop     de
        pop     bc
        ret

EATSPACES:
        ld      a,(hl)
        cp      32
        jr      nz,EATSPACEEND
        inc     hl
        djnz    EATSPACES
        scf
        ret
EATSPACEEND:
        or      a
        ret

DELAY:
        PUSH    DE
        PUSH    HL
DELAY0:
        PUSH    BC
        LD          BC,$FFFF
DELAY1:
        EXX
        EXX
        EXX
        EXX
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,DELAY1
        POP     BC
        DEC     BC
        LD         A,B
        OR      C
        JR      NZ,DELAY0
        POP     HL
        POP     DE
        RET
              
TESTMSXPISTR:
        DB      'MSXPi'
confatual:
        DB      00
slotatual:
        DB      00
subsatual:
        DB      00
