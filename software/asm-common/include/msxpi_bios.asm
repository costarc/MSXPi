; MSXPi Interface
; Version 1.2
; ------------------------------------------------------------------------------
; MIT License
; 
; Copyright (c) 2015-2025 Ronivon Costa
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
; -----------------------
; CHKPIRDY
; -----------------------
; Returns:
;   C = 1  → ESC pressed (error)
;   C = 0  → OK, CONTROL_PORT1 is 0 or 2
; Uses: A
; -----------------------
CHKPIRDY:
        ; --- Check ESC key (row 7, bit 2) ---
        ld      a,7
        out     ($AA),a
        in      a,($A9)
        bit     2,a
        jr      nz,CHKPIRDY_NO_ESC    ; bit=1 → key not pressed
        scf                             ; ESC pressed → error
        ret

; --- ESC not pressed, check MSXPi ready state ---
CHKPIRDY_NO_ESC:
        in      a,(CONTROL_PORT1)
        cp      0
        jr      z,CHKPIRDY_OK         ; 0 → MSXPi physical interface, OK

        cp      2                     ; 2 → openMSX interface, OK
        jr      nz,CHKPIRDY           ; anything else → recheck ESC + ready

CHKPIRDY_OK:
        and     a                     ; clear carry (success)
        ret

;-----------------------
; PIREADBYTE           |
;-----------------------
PIREADBYTE:
            call    CHKPIRDY
            jr      nc,PIREADBYTE1	   ; PI Responding
PIREADBYTE_ESC:
			ld 		a,$FF
			ret                        ; Return error - ESC Pressed
PIREADBYTE1:			
            xor     a                  ; clear A - but not really necessary
            out     (CONTROL_PORT1),a  ; send read command to the interface
			
			call    CHKPIRDY
			jr		c,PIREADBYTE_ESC   ; ESC Pressed
		    ; Verify if it is openMSX or real MSXPi hardware
			push	af				   ; save CHKPIRDY state temporarily
			in		a,(CONTROL_PORT2)  ; Need to check if it is MSXPi interface
			cp		$FE                ; openMSX will return $FE
			jr		c,PIREADBYTE_SUCC  ; iT IS PHYSICAL msxpI
			pop		af				   ; restore CHKPIRDY state
PIREADBYTE2:
			call    CHKPIRDY
			jr		c,PIREADBYTE_ESC   ; ESC Pressed
			cp		2
			jr		nz,PIREADBYTE2
			push    af
PIREADBYTE_SUCC:
			pop		af
			or		a				   ; reset carry flag
            in      a,(DATA_PORT1)     ; read byte - probably has nothing useful since
			                           ; there was an error in the comms
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
            or      a				   ; clear C flag
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

; resetMSXPI
; Called on beginning of every command
; In openMSX implementation, will clear the queue 
; avoiding checksum loop after an interruption
resetMSXPI:
		ld		a,$FF
		out		(CONTROL_PORT1),a
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
       
; ---------------------------------------------------------
; SENDDATA (single-block, size <= MAXBUFSIZE)
;   DE = src pointer
;   BC = size (number of bytes to send)
;
; Output:
;   NC: success, DE = src + size
;   C : error
;
; Uses:
;   AF, BC, DE, HL
; ---------------------------------------------------------
SENDDATA:

; -------------------------
; 1. Initial handshake
; -------------------------
SD2_HS_LOOP:
    ld      a,READY
    call    PIWRITEBYTE
    jr      c,SD2_HS_ERR

    call    PIREADBYTE
    jr      c,SD2_HS_ERR
	
    cp      READY_ACK
    jr      nz,SD2_HS_LOOP          ; wait until READY_ACK

    ; Send msxmaxbuf (MAXBUFSIZE)
    ld      a,MAXBUFSIZE_LO
    call    PIWRITEBYTE
    jr      c,SD2_CONN_ERR

    ld      a,MAXBUFSIZE_HI
    call    PIWRITEBYTE
    jr      c,SD2_CONN_ERR

; -------------------------
; 2. Single-block header
; -------------------------
    ld      a,RC_SUCCESS            ; header_rc
    call    PIWRITEBYTE
    jr      c,SD2_CONN_ERR

    ld      a,c                     ; length low
    call    PIWRITEBYTE
    jr      c,SD2_CONN_ERR

    ld      a,b                     ; length high
    call    PIWRITEBYTE
    jr      c,SD2_CONN_ERR

    ld      a,0                     ; block_index = 0
    call    PIWRITEBYTE
    jr      c,SD2_CONN_ERR

    ld      hl,0                    ; HL = checksum

; -------------------------
; 2b. Payload loop
; -------------------------
SD2_SEND_LOOP:
    ld      a,b
    or      c
    jr      z,SD2_SEND_DONE         ; all bytes sent
    ld      a,(de)                  ; A = payload byte
	push    de
    push    bc
	ld      e,a                     ; e = payload copy
	call    PIWRITEBYTE
	jr      nc,SD2_SEND_LOOP1
    pop     bc
	pop     de
	jr      SD2_CONN_ERR
SD2_SEND_LOOP1:
    ld      a,e						; a = payload copy
    ld      b,0
    ld      c,a
    add     hl,bc
    pop     bc
	pop     de 
	inc     de
    dec     bc
    jr      SD2_SEND_LOOP


; -------------------------
; Errors
; -------------------------
SD2_CHKSUM_ERR:
    scf
    ret

SD2_HS_ERR:
    scf
    ret

SD2_CONN_ERR:
    scf
    ret

; -------------------------
; 2c. Checksum exchange
; -------------------------
SD2_SEND_DONE:
    ld      a,l
    add     a,h                     ; (low + high) & 0xFF
    ld      l,a                     ; L = localChecksum

    ld      a,l                     ; send local checksum
    call    PIWRITEBYTE
    jr      c,SD2_CONN_ERR

    call    PIREADBYTE              ; receive remote checksum
    jr      c,SD2_CONN_ERR

    cp      l                       ; compare with localChecksum
    jr      nz,SD2_CHKSUM_ERR

; -------------------------
; 3. Status handshake
; -------------------------
    call    PIREADBYTE              ; expect READY
    jr      c,SD2_HS_ERR
    cp      READY
    jr      nz,SD2_HS_ERR

    call    PIREADBYTE              ; expect status_from_python
    jr      c,SD2_CONN_ERR
    cp      RC_SUCCESS
    jr      nz,SD2_CONN_ERR

    ld      a,READY_ACK             ; send READY_ACK
    call    PIWRITEBYTE
    jr      c,SD2_HS_ERR

    or      a                        ; clear carry
    ret

; ================================================================
;  RECVDATA_ONEBLOCK
;  Receive exactly one block from Python using the DATA2 protocol.
;
;  INPUT:
;     A  = expected_block_index
;     DE = destination pointer
;     BC = maxbuf (expected block size / MSX max payload)
;
;  OUTPUT:
;     Carry = 0 → success
;     Carry = 1 → failure
;     A  = RC_* return code
;     DE = advanced pointer after storing payload
;     BC = actual block length received
;     HL = destroyed
;
;  LOCALS (IX-based stack frame, 8 bytes):
;     (IX+0) = expected_block_index
;     (IX+1) = header_rc
;     (IX+2) = localChecksum
;     (IX+3) = remoteChecksum
;     (IX+4) = maxbuf_lo
;     (IX+5) = maxbuf_hi
;     (IX+6) = length_lo
;     (IX+7) = length_hi
; ================================================================

RECVDATA_ONEBLOCK:

    ; ------------------------------------------------------------
    ; Allocate 8-byte local frame on stack
    ; ------------------------------------------------------------
    push    bc
    push    de
    push    hl
    push    af              ; 4 pushes = 8 bytes

    ld      ix,0
    add     ix,sp           ; IX -> base of locals

    ; Store expected_block_index and maxbuf
    ld      (ix+0),a        ; expected_block_index
    ld      (ix+4),c        ; maxbuf_lo
    ld      (ix+5),b        ; maxbuf_hi


; ------------------------------------------------------------
; 1. INITIAL HANDSHAKE
;    MSX -> READY
;    Python -> READY_ACK
;    MSX -> maxbuf_lo, maxbuf_hi
; ------------------------------------------------------------

r2_handshake_loop:
    ld      a,READY
    call    PIWRITEBYTE
    jr      c,r2_handshake_err

    call    PIREADBYTE
    jr      c,r2_handshake_err
    cp      READY_ACK
    jr      nz,r2_handshake_loop

    ; Handshake OK → send maxbuf (original BC from locals)
    ld      a,(ix+4)        ; maxbuf_lo
    call    PIWRITEBYTE
    jr      c,r2_conn_err

    ld      a,(ix+5)        ; maxbuf_hi
    call    PIWRITEBYTE
    jr      c,r2_conn_err


; ------------------------------------------------------------
; 2. READ HEADER
;    header_rc, length_lo, length_hi, block_index
; ------------------------------------------------------------

    ; header_rc
    call    PIREADBYTE
    jr      c,r2_conn_err
    ld      (ix+1),a        ; header_rc

    ; length low
    call    PIREADBYTE
    jr      c,r2_conn_err
    ld      c,a             ; BC = length (low in C)
    ld      (ix+6),a        ; length_lo

    ; length high
    call    PIREADBYTE
    jr      c,r2_conn_err
    ld      b,a             ; BC = length (high in B)
    ld      (ix+7),a        ; length_hi

    ; block_index
    call    PIREADBYTE
    jr      c,r2_conn_err
    ; A = received block_index
    cp      (ix+0)          ; compare with expected_block_index
    jr      nz,r2_unexpecteddata


; ------------------------------------------------------------
; 3. VALIDATE LENGTH  (length <= maxbuf ?)
; ------------------------------------------------------------
    ; Compare BC (length) with maxbuf (from locals)
    ld      a,b
    cp      (ix+5)          ; compare high bytes
    jr      c,r2_len_ok     ; length_hi < maxbuf_hi → OK
    jr      nz,r2_bufovflw  ; length_hi > maxbuf_hi → overflow

    ; high bytes equal → compare low
    ld      a,c
    cp      (ix+4)
    jr      c,r2_len_ok     ; length_lo < maxbuf_lo → OK
    jr      z,r2_len_ok     ; equal → OK

    ; length_lo > maxbuf_lo → overflow
    jr      r2_bufovflw



; ------------------------------------------------------------
; ERROR PATHS
; ------------------------------------------------------------
r2_unexpecteddata:
    ld      a,RC_UNEXPECTEDDATA
    scf
    jr      r2_exit

r2_bufovflw:
    ld      a,RC_BUFOVFLW
    scf
    jr      r2_exit

r2_chksum_err:
    ; You don't have RC_CHKSUM_ERR; map to RC_FAILED
    ld      a,RC_FAILED
    scf
    jr      r2_exit

r2_handshake_err:
    ld      a,RC_HANDSHAKEERR
    scf
    jr      r2_exit

r2_conn_err:
    ld      a,RC_CONNERR
    scf
    jr      r2_exit
	
r2_len_ok:
    ; BC already holds length, which we also want to return.


; ------------------------------------------------------------
; 4. RECEIVE PAYLOAD + CHECKSUM ACCUMULATION
; ------------------------------------------------------------
    ld      hl,0            ; checksum accumulator

r2_payload_loop:
    ld      a,b
    or      c
    jr      z,r2_payload_done   ; BC == 0 → done

    call    PIREADBYTE
    jr      c,r2_conn_err

    ld      (de),a
    inc     de

    ; HL += A
    add     a,l
    ld      l,a
    jr      nc,r2_ck_nocarry
    inc     h
r2_ck_nocarry:

    dec     bc
    jr      r2_payload_loop

r2_payload_done:


; ------------------------------------------------------------
; 5. FOLD CHECKSUM (16-bit → 8-bit)
;    localChecksum = (L + H) & 0xFF
; ------------------------------------------------------------
    ld      a,l
    add     a,h
    ld      (ix+2),a        ; localChecksum


; ------------------------------------------------------------
; 6. RECEIVE REMOTE CHECKSUM
; ------------------------------------------------------------
    call    PIREADBYTE
    jr      c,r2_conn_err
    ld      (ix+3),a        ; remoteChecksum


; ------------------------------------------------------------
; 7. SEND LOCAL CHECKSUM BACK
; ------------------------------------------------------------
    ld      a,(ix+2)        ; localChecksum
    call    PIWRITEBYTE
    jr      c,r2_conn_err


; ------------------------------------------------------------
; 8. COMPARE CHECKSUMS
; ------------------------------------------------------------
    ld      a,(ix+2)        ; localChecksum
    cp      (ix+3)          ; remoteChecksum
    jr      nz,r2_chksum_err


; ------------------------------------------------------------
; 9. STATUS HANDSHAKE AFTER GOOD BLOCK
;    MSX -> READY
;    MSX -> status_for_next (RC_SUCCESS)
;    Python -> READY_ACK
; ------------------------------------------------------------
    ld      a,READY
    call    PIWRITEBYTE
    jr      c,r2_handshake_err

    ld      a,RC_SUCCESS
    call    PIWRITEBYTE
    jr      c,r2_conn_err

    call    PIREADBYTE
    jr      c,r2_handshake_err
    cp      READY_ACK
    jr      nz,r2_handshake_err


; ------------------------------------------------------------
; 10. INTERPRET header_rc FOR CALLER
;     header_rc:
;       RC_SUCCESS → last block
;       RC_READY   → more blocks to come
;       else       → RC_CONNERR
; ------------------------------------------------------------
    ld      a,(ix+1)        ; header_rc
    cp      RC_SUCCESS
    jr      z,r2_success

    cp      RC_READY
    jr      z,r2_ready

    jr      r2_conn_err


; ------------------------------------------------------------
; SUCCESS PATHS
; ------------------------------------------------------------
r2_success:
    ld      a,RC_SUCCESS
    or      a               ; clear carry
    jr      r2_exit

r2_ready:
    ld      a,RC_READY
    or      a               ; clear carry
    jr      r2_exit

; ------------------------------------------------------------
; COMMON EXIT: restore stack, preserve A and flags
; ------------------------------------------------------------
r2_exit:
    push    af
    push    ix
    pop     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    pop     af
    ld      sp,hl
    ret

; ---------------------------------------------------------
; SendPCommand
;
; Input:
;   None - it picks the command from MSX-DOS command line
;
; Output:
;   NC: success (carry from SENDDATA)
;   C:  error (empty string or SENDDATA error)
;   DE: advanced by SENDDATA on success
;
; Uses:
;   AF, BC, DE, HL
; ---------------------------------------------------------
SendPCommand:
	ld		de,$80
	ld		a,(de)
	ld 		c,a 
	ld 		b,0 
	inc     de 
	call    SendCommandToMSXPi
	ret
	
; ---------------------------------------------------------
; SendCommandToMSXPi
;
; Input:
;   DE = pointer to zero-terminated command string
;
; Output:
;   NC: success (carry from SENDDATA)
;   C:  error (empty string or SENDDATA error)
;   DE: advanced by SENDDATA on success
;
; Uses:
;   AF, BC, DE, HL
; ---------------------------------------------------------
SendCommandToMSXPi:

    ; Check empty first char
    ld      a,(de)
    or      a
    jr      nz,SCM_HaveFirst

    scf                     ; empty → error
    ret

SCM_HaveFirst:
    ; HL = walk pointer, BC = length
    ld      hl,0            ; BC will be length, so clear it
    ld      b,h
    ld      c,l

    push    de              ; save original start pointer

SCM_CountLoop:
    ld      a,(de)
    or      a
    jr      z,SCM_CountDone

    inc     de
    inc     bc              ; length++
    jr      SCM_CountLoop

SCM_CountDone:
    pop     de              ; restore DE = start of string

    ld      a,b
    or      c
    jr      nz,SCM_HaveLength

    ; length == 0 (shouldn't happen if first char non-zero, but be safe)
    scf
    ret

SCM_HaveLength:
    ; DE = src, BC = size
    call    SENDDATA
    ret                     ; propagate carry from SENDDATA


;-----------------------
; PRINTPISTDOUT
;-----------------------
PRINTPISTDOUT:
    push    bc					; maxbufsize expected
	xor		a					; block number
	push	de					; save buffer address
	call	RECVDATA_ONEBLOCK	; Read 1 block
	ld		l,a					; save return code
	ld 		a,TEXTTERMINATOR 
	ld		(de),a 				; Terminator for text
	ld      a,l
	pop 	de 					; restore buffer address
	pop 	hl 					; restore maxbufsize
	ret		c 					; Error reading data
	push    af					; save return code
	push    hl					; push msxbufsize again to stack
	ex 		de,hl 				; HL = buffer to print
	call    PRINT
	pop     bc					; maxbufsize
	pop     af					; return code
	cp      RC_READY			; Is there another block?
	jr      z,PRINTPISTDOUT
	ret

;-----------------------
; PRINT
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
		
		DS 		128
heap_top: equ     $
		