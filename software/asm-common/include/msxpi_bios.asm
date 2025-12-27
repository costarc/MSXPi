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
            
; resetMSXPI
; Called on beginning of every command
; In openMSX implementation, will clear the queue 
; avoiding checksum loop after an interruption
resetMSXPI:
		ld		a,$FF
		out		(CONTROL_PORT1),a
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
;  RECVDATA_ONEBLOCK (minimal, no retries)
;
;  A  = expected_block_index
;  DE = dest pointer
;  BC = msx_blocksize
; ================================================================

PerformHandshake:
    push    af          ; expected_index
    push    de          ; original dest
    push    bc          ; msx_blocksize


r2_handshake_loop:

    ld      a, READY
    call    PIWRITEBYTE
    jr      c, handshake_err   ; write must succeed

    call    PIREADBYTE
    jr      c, handshake_err
    cp      READY_ACK
    jr      nz, r2_handshake_loop

    ; send msx_blocksize (from stack)
    pop     bc              ; BC = msx_blocksize
    ld      a, c
    call    PIWRITEBYTE
    jr      c, handshake_exit
    ld      a, b
    call    PIWRITEBYTE
    ; C flag set if error
handshake_exit:
    pop     de
    pop     af
    ret
handshake_err:
    pop     bc
    jr      handshake_exit


RECVDATA_ONEBLOCK:
    push    af          ; expected_index
    push    de          ; original dest

; ------------------------------------------------------------
; 1. INITIAL HANDSHAKE
; ------------------------------------------------------------
; must have been performed before calling this function

; ------------------------------------------------------------
; 2. HEADER: [RC][LEN_LO][LEN_HI][INDEX]
; ------------------------------------------------------------

    call    PIREADBYTE      ; header_rc
    jr      c, r2_conn_err
    ld      h, a            ; H = header_rc

    call    PIREADBYTE      ; length low
    jr      c, r2_conn_err
    ld      c, a

    call    PIREADBYTE      ; length high
    jr      c, r2_conn_err
    ld      b, a            ; BC = length

    call    PIREADBYTE      ; block_index
    jr      c, r2_conn_err
    ld      l, a            ; L = received_index

    ; Recover original values
    pop     de              ; de = original dest
    pop     af              ; A = expected_index
    push    de              ; dest
    push    bc              ; msx_blocksize received from server
                            ; last block is usually smaller thant the msx_blocksize sent to server
    ; Check index
    cp      l
    jr      nz, r2_unexpecteddata   ; index sent by server must match msx index
; ------------------------------------------------------------
; 3. PAYLOAD + CHECKSUM
; ------------------------------------------------------------
    ; now:
    ; BC = length of this block
    ; DE = dest
    ; H = header_rc
    ; L = received_index
    ; AF on stack (expected index)
    ; dest, maxbuf also on stack
    push    bc
    push    de
    exx 				  ; save length (BC) and RC (h) for later
    pop     de            
    pop     bc            ; restore length
    ld      hl, 0         ; 16-bit checksum accumulator
r2_payload_loop:
    ld      a, b
    or      c
    jr      z, r2_payload_done

    call    PIREADBYTE
    jr      c, r2_conn_err

    ld      (de), a
    inc     de

    ; HL += A
    add     a, l
    ld      l, a
    jr      nc, r2_no_carry
    inc     h
r2_no_carry:
    dec     bc
    jr      r2_payload_loop

; ------------------------------------------------------------
; ERROR PATHS
; ------------------------------------------------------------

r2_chksum_err:
    ld      a, RC_CHKSUM_ERR
    scf
    jr      r2_exit

r2_unexpecteddata:
    ld      a, RC_UNEXPECTEDDATA
    scf
    jr      r2_exit

r2_bufovflw:
    ld      a, RC_BUFOVFLW
    scf
    jr      r2_exit

r2_handshake_err:
    ld      a, RC_HANDSHAKEERR
    scf
    jr      r2_exit

r2_conn_err:
    ld      a, RC_CONNERR
    scf

; ------------------------------------------------------------
; EXIT: clean stack & return
; ------------------------------------------------------------

r2_exit:
    pop     hl      ; discard
    pop     de      ; dest (advanced if success or original address)
    ret

r2_payload_done:
    ; Fold 16-bit checksum into one byte (like Python)
    ld      a, l
    add     a, h
    ld      l, a           ; L = local_sum

    ; Receive Python's local_sum
    call    PIREADBYTE
    jr      c, r2_conn_err
    cp      l
    jr      nz, r2_chksum_err

    ; Send our checksum back
    ld      a, l
    call    PIWRITEBYTE
    jr      c, r2_conn_err

    ; Advance DE for caller: DE = final dest
    pop     ix              ; original msx_blocksize (discard)
    pop     ix              ; original dest (discard)

    push    de              ; new dest
    push    bc              ; length again

; ------------------------------------------------------------
; 4. STATUS HANDSHAKE (match Python)
; ------------------------------------------------------------

    ; MSX must send: READY, status_for_next, then expect READY_ACK
    ld      a, READY
    call    PIWRITEBYTE
    jr      c, r2_conn_err

    ; Use header_rc we got from Python (in H) as status_for_next,
    ; BUT your Python expects status_from_msx == RC_SUCCESS.
    ; For now, always report RC_SUCCESS to keep it simple:

    ld      a, RC_SUCCESS
    call    PIWRITEBYTE
    jr      c, r2_conn_err

    ; Read READY_ACK from Python
    call    PIREADBYTE
    jr      c, r2_conn_err
    cp      READY_ACK
    jr      nz, r2_handshake_err
    ; Success
    exx                     ; Get back original BC (length) and RC (H)
    ld      a, h            ; A = header_rc
    or      a               ; clear carry
    jr      r2_exit

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
    call    PerformHandshake    ; Required before calling RECVDATA_ONEBLOCK
	xor		a					; block number
PRINTPISTDOUT0:
    push	af					; save block number
    push    bc					; maxbufsize expected
	push	de					; save buffer address
	call	RECVDATA_ONEBLOCK	; Read 1 block
	ld		l,a					; save return code
	ld 		a,TEXTTERMINATOR 
	ld		(de),a 				; Terminator for text
	ld      a,l
	pop 	de 					; restore buffer address
	pop 	hl 					; restore maxbufsize
    pop     iy
	ret		c 					; Error reading data
    push    iy					; save block number again
	push    af					; save return code
	push    hl					; push msxbufsize again to stack
    push    de					; save buffer address again
	ex 		de,hl 				; HL = buffer to print
	call    PRINT
    pop     de 
	pop     bc					; maxbufsize
	pop     af					; return code
    pop     iy					; block number
	cp      RC_READY			; Is there another block?
	ret     nz					; No more blocks, return    
    push	iy					; save block number
    pop		af					; restore index
    inc		a					; next block number
	JR      PRINTPISTDOUT0

STDOUTTONULL:
    call    PerformHandshake    ; Required before calling RECVDATA_ONEBLOCK
	xor		a					; block number
STDOUTTONULL0:
    push	af					; save block number
    push    bc					; maxbufsize expected
	push	de					; save buffer address
	call	RECVDATA_ONEBLOCK	; Read 1 block
    pop     de
    pop     bc
    pop     hl
    cp      RC_SUCCESS
    ret     z
    cp      RC_READY
    scf
    ret     nz                  ; some error ocurred
    ld      a,h
    inc		a					; next block number
	JR      STDOUTTONULL0    
    
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
; Convert the 4 bytes ascii values in buffer DE to hex
; Preserves HL
; Output:
; BC = The hex value converted
; DE = Points to next char in the string addess
        PUSH    HL
        LD      H,D
        LD      L,E
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
        INC     HL          ; ";"
        INC     HL          ; "COMMAND"
        CALL    ATOHEX
        JR      C,STREXIT
        OR      E
        LD      B,D         ; BC = Converted hex value
        LD      C,A
        LD      D,H
        LD      E,L         ; DE = Next char in the string - should be the command
STREXIT:
        POP     HL
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
		