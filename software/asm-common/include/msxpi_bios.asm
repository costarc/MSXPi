; MSXPi Interface
; Version 1.2
; ------------------------------------------------------------------------------
; MIT License
; 
; Copyright (c) 2024 Ronivon Costa
; 
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
; 
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
; 
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
; -----------------------------------------------------------------------------
;
; File history :
; 1.2    : CHKPIRDY now return values 0 (pi online), 1 (pi offline), 2(byte ready)
;           PIREADBYTE now loops until it receives 2 from CHKPIRDY (this add
;           support for the openMSX extension
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
        ret     z
        cp      2
        jr      nz,CHKPIRDY
        ret

;-----------------------
; PIREADBYTE           |
;-----------------------
PIREADBYTE:
            call    CHKPIRDY
            jr      c,PIREADBYTE2
			;push	af
			;add		a,48
			;out		($98),a
			;pop		af
			cp		1
			jr		z,PIREADBYTE       ; Pi not ready - keep trying
			cp		2                  ; openMSX extension will return 2
			                           ; when data is available for reading
			jr      z,PIREADBYTE1      ; is openMSX extension - read data
		    or		a
			jr		nz,PIREADBYTE      ; Status not 0, keep trying - otherwise:
			in		a,(CONTROL_PORT2)  ; Need to check if it is MSXPi interface
			                           ; or MSXPi extension in openMSX
			cp		$FE                ; openMSX will return $FE
			jr		z,PIREADBYTE       ; openMSX does not have data ready when status = 0
			                           ; need to keep trying			
PIREADBYTE1:
            xor     a                  ; do not use xor to preserve c flag state
            out     (CONTROL_PORT1),a  ; send read command to the interface
            call    CHKPIRDY           ; wait interface transfer data to pi and
                                       ; pi app processing
                                       ; no ret c is required here, because in a,(7) 
                                       ; does not reset c flag
PIREADBYTE2:
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

; Clear buffer area
; Input:
; BC = buffer size
; DE = Buffer Address
;
CLEARBUF:
        push    bc
        push    de
        push    hl
        ld      h,d
        ld      l,e
        inc     de
        xor     a
        ld      (hl),a
        ldir
        pop     hl
        pop     de
        pop     bc
        ret
        
;-----------------------
; SENDPICMD            |
;-----------------------
; Send a command to Raspberry Pi
; This routine allocate BLKSIZE bytes at the top of th RAM
; This buffer is used for command & parameters transfer
; Input:
;   de = should contain the command string
;   hl = buffer address - optional. if zero, will use buffer at top of ram
;   B = size of command + parameters
; Output:
;   Flag C set if there was a communication error
;   hl = buffer address (never zero)
;   af,bc,de,hl are modified
;
SENDPICMD:
        EX      DE,HL
        PUSH    BC
        LD      BC,BLKSIZE
        CALL    CLEARBUF
        POP     BC

; Call GETCMD, which will parse the whole string in the CALL command area,
; get only the first string and send as Command - the remaining of the string
; will be the parameters
; The Command string is copied to the transfer buffer area (DE) and then
; SENDCOMMAND is called

        PUSH    DE
        CALL    GETCMD
        POP     DE
        PUSH    HL              ; Next parmameters address
        PUSH    DE
        PUSH    BC
        LD      BC,CMDSIZE
        CALL    SENDDATA
        POP     BC
        POP     DE
        POP     HL
        RET     C
; Clear the buffer again, and pass the remaining of the string
; as parameters to RPi

        PUSH    BC
        LD      BC,BLKSIZE
        CALL    CLEARBUF
        POP     BC

        PUSH    DE
        CALL    GETPARMS
        POP     DE
        LD      BC,BLKSIZE
        CALL    SENDDATA
        RET
        
GETCMD:
        LD      A,(HL)
        CP      ' '
        RET     Z
        CP      $22             ; QUOTE (")
        RET     Z
        CP      ')'
        RET     Z
        LD      (DE),A
        INC     DE
        INC     HL
        DEC     B
        JR      NZ,GETCMD
        RET
GETPARMS:
        XOR     A
        CP      B
        RET     Z
        LD      A,(HL)
        CP      ' '
        JR      Z,GETPARMS2
GETPARMS1:
        LD      A,(HL)
        CP      $22
        JR      Z,GETPARMS2
        CP      ')'
        JR      Z,GETPARMS2
        LD      (DE),A
        INC     DE
GETPARMS2:
        INC     HL
        DJNZ    GETPARMS1
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
        call    PIWRITEBYTE             ; send Sync byte
        ld      hl,0                    ; will store checksum in HL
RECV0:
        push    bc
        call    PIREADBYTE
        ld      (de),a
        inc     de
        ld      b,0
        ld      c,a
        add     hl,bc                   ; calculating the CRC
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
        jr      nz,RECVRETRY     ;go for another retry
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
        ld      a,(hl)      ;get a character to print
        cp      TEXTTERMINATOR
        ret     z
        cp      10
        jr      nz,PRINT1
        call    PUTCHAR
        ld      a,13
PRINT1:
        call    PUTCHAR     ;put a character
        inc     hl
        jr      PRINT

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
;  A = 0: Data contain header
;  DE: Buffer address
;  BC: Buffer lenght
; Changes: AF,BC,HL
; =================================================================
PRINTPISTDOUT:
        ld      a,(de)
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
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,PRINTPISTDOUT
        or      a
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
;  A = Output type (as below cases)
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
; Size of buffer is fixed (CMDSIZE) but command can be up to 8 chars
SENDCOMMAND:
        ld      hl,buf
        ex      de,hl
        ld      bc,CMDSIZE
        push    hl
        call    CLEARBUF
        pop     hl
        ld      b,CMDSIZE - 1
SENDCOMMAND0:                       ; Move command to buffer area
        ld      a,(hl)
        LD      (de),a
        or      a
        jr      z,SENDCOMMAND1
        inc     hl
        inc     de
        djnz    SENDCOMMAND0
SENDCOMMAND1:
        ld      bc,CMDSIZE
        ld      de,buf
        call    SENDDATA
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
