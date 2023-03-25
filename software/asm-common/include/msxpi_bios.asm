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
            jr      c,PIWRITEBYTE_ERR
            pop     af
            out     (DATA_PORT1),a     ; send data, or command
            or      a
            ret
PIWRITEBYTE_ERR:
            pop     af
            scf
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
; Get working area to store the command, and format it:
        PUSH    BC
        PUSH    DE
        ;CALL    GETWRK
        LD      H,D
        LD      L,E
        LD      BC,BLKSIZE
        ADD HL,BC               ; Get a workign area at the end of user's buffer        
        PUSH    HL
        LD      D,H
        LD      E,L
        LD      BC,8
        LD      A,32
        LD      (HL),A
        INC     DE
        LDIR
        XOR     A
        LD      (DE),A
        POP     DE              ; Workarea (to store command)
        POP     HL              ; Command address sent by BASIC
        POP     BC              ; Size of command
        PUSH   DE
        LDIR                       ; Move command to formated 9 bytes work area
        POP     DE              ; Restore command address (Workarea)
        CALL    SENDCOMMAND
        RET

;---------------------------------------------------------------
; RECVDATA- SENDDATA
;---------------------------------------------------------------
; 01/03/2023
;
; Receive / Send BC bytes of data plus a checksum (1 byte)
; Calculates teh checksum locally as data is coming, and send it back.
; Compares the local checksum with received checksum, and
; if they differ return with C flag set.
; Will retry transmisison a number of times: GLOBALRETRIES
;
; Input:
;   de = memory address for the data
;   bc = block size
; Output:
;   Flag C set if error
;  DE next available address
RECVDATA:
RECVDATABLOCK:
        ld      a,GLOBALRETRIES
RECVRETRY:
        di
        dec     a
        push    af                      ; save number of retries left
        ld      a,READY
        call    PIWRITEBYTE
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
        ld      a,c                         ; get MSXPi chksum
        pop     bc                      ; number of retries in B
        ei
        cp      l                           ; compare checksum
        ret     z                           ; return if match, C is 0
        ld      a,b
        or      a
        jr       nz,RECVRETRY     ;go for another retry 
        scf                                 ; differ, set flag for Error
        ret

SENDDATA:
SENDDATABLOCK:
        ld      a,GLOBALRETRIES
SENDRETRY:
        di
        dec     a
        push    af                      ; save number of retries left
        ld      a,READY
        call    PIWRITEBYTE
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
        add     a,h                         ; sum two bytes of checksum to obtain final cum
        ld      l,a
        call    PIWRITEBYTE     ; send checksum calculated here
        call    PIREADBYTE      ; read checksum byte from msxpi server
        pop     bc                      ; Number of retries left in B
        ei
        cp      l                           ; compare checksum
        ret     z                           ; return if match, C is 0
        ld      a,b                         ; Check retries left
        or      a
        jr      nz,SENDRETRY     ;go for another retry
        scf                                 ; differ, set flag for Error
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
; PRINTPISTDOUT 
; Read buffer of BC lenght and print to screen. Terminates also if zero detected
; Inputs: (PRINTPISTDOUT0)
;  HL: Buffer address
;  BC: Buffer lenght
; Changes: AF,BC,HL
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

NOSTDOUT: 
        call    PIREADBYTE
        dec     bc
        ld      a,b
        or      c
        jr      nz,NOSTDOUT
        call    PIREADBYTE      ; read two extra bytes with the Checksum/CRC
        call    PIREADBYTE
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
        ld          bc,CMDSIZE               ; command lenght set to fixed size
        call        SENDDATA
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
              
