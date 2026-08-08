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
;
; Retries the block (up to GLOBALRETRIES times, see
; asm-common/include/include.asm) on a checksum mismatch, matching
; recvdata2()/recvdata2_oneblock()'s own resend expectation on the Python
; side - see SENDDATA's own comment at the mismatch branch below.
; ---------------------------------------------------------
SENDDATA:
    ; Preserve the original src/size on the STACK, not in a fixed memory
    ; variable: this file is sometimes linked straight into ROM (e.g. as
    ; part of MSX-DOS/msxpidos.rom), where a `ld (nn),a`-style static
    ; would silently fail to write. The CPU stack always lives in RAM
    ; regardless of where the executing code sits - push/pop/call/ret
    ; require that - so it's safe here. IX holds the retry counter for
    ; the same reason (a register, not memory); IX/IY are otherwise
    ; unused in this routine.
    push    de              ; [de(orig src)]
    push    bc              ; [bc(orig size), de(orig src)]
    ld      ix,0            ; IX = retry_count

; -------------------------
; 1. Initial handshake (once per call, not repeated on retry - matches
; recvdata2()'s own structure: its handshake runs once, outside the
; block-receive loop that a retry re-enters)
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

SD2_RETRY:
    ; "Peek" the stack-preserved originals without losing them: pop them
    ; off, then push them straight back. This attempt's working copy ends
    ; up in bc/de (about to be consumed by the send loop below), while the
    ; stack keeps holding the pristine originals in case of a further retry.
    pop     bc
    pop     de
    push    de
    push    bc

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
SD2_HS_ERR:
    scf
    jr      SD2_EXIT

SD2_CONN_ERR:
    scf
    jr      SD2_EXIT

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
    jr      z,SD2_CHK_OK

; -------------------------
; Checksum mismatch: Python's receivers (recvdata2/recvdata2_oneblock)
; always loop back to await a fresh header on mismatch (see their own
; comments) - resend the whole block from scratch, up to GLOBALRETRIES
; times (asm-common/include/include.asm), instead of erroring out on the
; first bad block like before.
; -------------------------
    push    ix
    pop     hl
    inc     l
    ld      h,0
    push    hl
    pop     ix              ; IX = retry_count + 1
    ld      a,l
    cp      GLOBALRETRIES
    jr      nc,SD2_CHKSUM_ERR
    jr      SD2_RETRY

SD2_CHKSUM_ERR:
    scf
    jr      SD2_EXIT

SD2_CHK_OK:
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

    or      a                        ; clear carry (success)

SD2_EXIT:
    ; DE/BC here are whatever the last attempt left them as - the advanced
    ; src pointer and consumed (=0) size on success (matching this
    ; routine's documented contract), unspecified on error. Either way,
    ; discard the two stack-preserved originals underneath - not needed
    ; any more. `pop rr` doesn't touch flags, so the scf/or a from
    ; whichever path got here survives through to ret.
    pop     hl
    pop     hl
    ret

; ================================================================
;  RECVDATA_ONEBLOCK
;
;  A  = expected_block_index
;  DE = dest pointer
;  BC = msx_blocksize
;
;  Retries the current block (up to GLOBALRETRIES times, see
;  asm-common/include/include.asm) on a checksum mismatch, matching
;  senddata_oneblock()'s own resend behavior on the Python side - see
;  RECVDATA_ONEBLOCK's own comment at the mismatch branch below.
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
    ; DE (dest) stays in the primary register for the whole call - safe,
    ; since PIREADBYTE/PIWRITEBYTE/CHKPIRDY only ever touch AF, never
    ; BC/DE/HL. expected_index and the retry counter can't live in a fixed
    ; memory variable either (this file is sometimes linked straight into
    ; ROM - see SENDDATA's own comment) - IY holds expected_index and IX
    ; the retry counter instead, both untouched by exx and by every
    ; PIREADBYTE/PIWRITEBYTE call in this routine.
    ld      l,a
    ld      h,0
    push    hl
    pop     iy              ; IY = expected_index
    ld      ix,0            ; IX = retry_count

; ------------------------------------------------------------
; 1. INITIAL HANDSHAKE
; ------------------------------------------------------------
; must have been performed before calling this function

r2_retry:
; ------------------------------------------------------------
; 2. HEADER: [RC][LEN_LO][LEN_HI][INDEX]
; ------------------------------------------------------------

    call    PIREADBYTE      ; header_rc
    jr      c, r2_conn_err
    push    ix              ; GETWRK clobbers IX (retry_count)
    push    de              ; and DE isn't verified safe across its
                            ; internal kernel calls either
    push    af
    call    GETWRK          ; HL = IX = driver workarea (offset 5+ is free -
                            ; DSKIO_SECTINFO only ever uses offsets 0-4, and
                            ; never runs concurrently with a CALL MSXPI)
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl              ; HL = workarea+5
    pop     af
    ld      (hl),a          ; stash header_rc in safe RAM
    pop     de              ; restore dest pointer
    pop     ix              ; restore retry_count

    call    PIREADBYTE      ; length low
    jr      c, r2_conn_err
    ld      c, a

    call    PIREADBYTE      ; length high
    jr      c, r2_conn_err
    ld      b, a            ; BC = length
    push    ix              ; GETWRK clobbers IX (retry_count)
    push    de              ; and DE isn't verified safe across its
                            ; internal kernel calls either
    push    bc
    call    GETWRK          ; HL = IX = driver workarea (offset 6-7 is
                            ; free - see the header_rc stash above for
                            ; offset 5, and DSKIO_SECTINFO's offsets 0-4)
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl              ; HL = workarea+6
    pop     bc
    ld      (hl),c
    inc     hl
    ld      (hl),b          ; stash length (lo,hi) in safe RAM - length
                            ; has the exact same vulnerability header_rc
                            ; had: it sits untouched in the inactive
                            ; register bank across the same long payload
                            ; wait, and the success return trusts it
                            ; survived via exx alone
    pop     de              ; restore dest pointer
    pop     ix              ; restore retry_count

    call    PIREADBYTE      ; block_index
    jr      c, r2_conn_err
    ; A = received_index. B,C(length)/D,E(dest) are both live and can't be
    ; spared - bridge the comparison against IY through the (still-unused-
    ; at-this-point) shadow set and the stack: exx doesn't touch AF, so a
    ; plain push/pop carries A safely across it.
    push    af
    exx
    push    iy
    pop     hl              ; shadow L' = expected_index
    pop     af              ; A = received_index again
    cp      l                ; compare against shadow L' = expected_index
    exx                      ; back to primary - bc/de untouched throughout
    jr      nz, r2_unexpecteddata   ; index sent by server must match msx index
; ------------------------------------------------------------
; 3. PAYLOAD + CHECKSUM
; ------------------------------------------------------------
    ; now:
    ; BC = length of this block
    ; DE = dest
    ; L = received_index
    push    bc
    push    de
    exx 				  ; save length (BC) for later - the payload loop
                          ; needs BC/DE as its own working registers
    pop     de
    pop     bc            ; restore length
    ld      hl, 0         ; 16-bit checksum accumulator
r2_payload_loop:
    ld      a, b
    or      c
    jr      z, r2_payload_done

    call    PIREADBYTE
    jr      c, r2_conn_err_x

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
; ERROR PATHS - phase 1 (before the shadow-register section below): stack
; is untouched here, safe to return directly.
; ------------------------------------------------------------

r2_unexpecteddata:
    ld      a, RC_UNEXPECTEDDATA
    scf
    ret

r2_bufovflw:
    ld      a, RC_BUFOVFLW
    scf
    ret

r2_conn_err:
    ld      a, RC_CONNERR
    scf
    ret

; ------------------------------------------------------------
; ERROR PATHS - phase 2 (inside the shadow-register section, exx active):
; must exx back to primary before returning, or the caller inherits our
; shadow bc'/de'/hl' instead of its own registers.
; ------------------------------------------------------------

r2_conn_err_x:
    exx
    ld      a, RC_CONNERR
    scf
    ret

r2_handshake_err_x:
    exx
    ld      a, RC_HANDSHAKEERR
    scf
    ret

r2_payload_done:
    ; Fold 16-bit checksum into one byte (like Python)
    ld      a, l
    add     a, h
    ld      l, a           ; L = local_sum

    ; Receive Python's local_sum
    call    PIREADBYTE
    jr      c, r2_conn_err_x
    cp      l
    jr      z, r2_chk_ok

; ------------------------------------------------------------
; CHECKSUM MISMATCH: echo our (mismatched) checksum anyway - Python's
; sender (senddata_oneblock) always does a paired read right after sending
; its own checksum, so it must get a byte here or it blocks waiting for
; one. Python will see the mismatch on its own end too (our echoed L won't
; match what it sent) and resend the entire block from scratch - so, like
; SENDDATA's own retry, go back to r2_retry and wait for a fresh header
; instead of erroring out on the first bad block.
; ------------------------------------------------------------
    ld      a, l
    call    PIWRITEBYTE
    jr      c, r2_conn_err_x

    exx                     ; back to primary - this attempt's shadow
                             ; de'/bc'/hl' are stale for a retry anyway.
                             ; B,C(length)/D,E(dest) are stale here too, but
                             ; get freshly re-read at r2_retry before
                             ; anything reads them again - so HL is free to
                             ; use as a bridge for IX.
    push    ix
    pop     hl
    inc     l
    ld      h,0
    push    hl
    pop     ix               ; IX = retry_count + 1
    ld      a,l
    cp      GLOBALRETRIES
    jr      nc, r2_chksum_err
    jp      r2_retry

r2_chksum_err:
    ; already back in primary set (exx'd above)
    ld      a, RC_CHKSUM_ERR
    scf
    ret

r2_chk_ok:
    ; Send our checksum back
    ld      a, l
    call    PIWRITEBYTE
    jr      c, r2_conn_err_x

; ------------------------------------------------------------
; 4. STATUS HANDSHAKE (match Python)
; ------------------------------------------------------------

    ; MSX must send: READY, status_for_next, then expect READY_ACK
    ld      a, READY
    call    PIWRITEBYTE
    jr      c, r2_conn_err_x

    ; Python expects status_from_msx == RC_SUCCESS, so always report that
    ; regardless of the header_rc it sent us:

    ld      a, RC_SUCCESS
    call    PIWRITEBYTE
    jr      c, r2_conn_err_x

    ; Read READY_ACK from Python
    call    PIREADBYTE
    jr      c, r2_conn_err_x
    cp      READY_ACK
    jr      nz, r2_handshake_err_x

    ; Success: DE (shadow) = advanced dest, BC (shadow) = 0
    push    de
    push    bc
    exx                     ; back to primary bank - matches what the
                            ; caller expects active on return; its own
                            ; BC/DE aren't trusted for anything below,
                            ; both get overwritten from safe RAM instead
    pop     hl               ; discard (=0)
    pop     de               ; DE = advanced dest, for the caller
    push    de              ; preserve dest pointer across GETWRK
    call    GETWRK          ; HL = IX = driver workarea
    inc     hl
    inc     hl
    inc     hl
    inc     hl
    inc     hl              ; HL = workarea+5
    ld      a,(hl)          ; A = header_rc, retrieved from safe RAM
    inc     hl              ; HL = workarea+6
    ld      c,(hl)
    inc     hl              ; HL = workarea+7
    ld      b,(hl)          ; BC = length, retrieved from safe RAM
    pop     de              ; restore dest pointer
    or      a               ; clear carry
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
		