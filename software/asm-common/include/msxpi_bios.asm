; MSXPi Interface
; Version 1.6
; ------------------------------------------------------------------------------
; MIT License
;
; Copyright (c) 2015-2026 Ronivon Costa
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
; ------------------------------------------------------------------------------
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
;   C = 1  -> ESC pressed (error)
;   C = 0  -> OK, CONTROL_PORT1 is 0 or 2 (value left in A)
; Uses: A
; -----------------------
; Headers use the shared readiness helper too. It preserves BC/DE/HL,
; restores PPI row selection and does not change the caller's interrupt state.
; Payload loops sample ESC at byte intervals and also while busy waiting.
CHKPIRDY:
        call PAYLOAD_ESCAPE
        ret c
        jp PAYLOAD_WAIT

;-----------------------
; PIREADBYTE           |
;-----------------------
; The push/pop pairs that used to bracket the $57 check were only balancing
; the stack between the two paths into PIREADBYTE_SUCC - the saved AF was
; overwritten by the IN below on one path and unused on the other. Removing
; them costs nothing and saves 21 T-states on every byte.
PIREADBYTE:
            call    CHKPIRDY
            jr      c,PIREADBYTE_ESC   ; ESC Pressed

            xor     a
            out     (CONTROL_PORT1),a  ; send read command to the interface

            call    CHKPIRDY
            jr      c,PIREADBYTE_ESC   ; ESC Pressed

            ; Verify if it is openMSX or real MSXPi hardware
            in      a,(CONTROL_PORT2)  ; Need to check if it is MSXPi interface
            cp      $FE                ; openMSX will return $FE
            jr      c,PIREADBYTE_SUCC  ; below $FE -> physical MSXPi

PIREADBYTE2:                           ; openMSX: wait for state 2
            call    CHKPIRDY
            jr      c,PIREADBYTE_ESC   ; ESC Pressed
            cp      2
            jr      nz,PIREADBYTE2

PIREADBYTE_SUCC:
            or      a                  ; reset carry flag
            in      a,(DATA_PORT1)     ; read byte
            ret                        ; return in a the byte received

PIREADBYTE_ESC:
            ld      a,$FF
            ret                        ; carry still set by CHKPIRDY

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
; Not assembled into the ROM: the disk driver never calls resetMSXPI, and the
; ROM is full.  Every other consumer of this file (the .COM tools in
; Client/src) still gets it.
 ifdef MSXPI_DRIVER
 else
resetMSXPI:
		ld		a,$FF
		out		(CONTROL_PORT1),a
		ret
 endif
		      
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
    jp      c,SD2_HS_ERR

    call    PIREADBYTE
    jp      c,SD2_HS_ERR

    cp      READY_ACK
    jr      nz,SD2_HS_LOOP          ; wait until READY_ACK

    ; Send msxmaxbuf (MAXBUFSIZE)
    ld      a,MAXBUFSIZE_LO
    call    PIWRITEBYTE
    jp      c,SD2_CONN_ERR

    ld      a,MAXBUFSIZE_HI
    call    PIWRITEBYTE
    jp      c,SD2_CONN_ERR

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
    jp      c,SD2_CONN_ERR

    ld      a,c                     ; length low
    call    PIWRITEBYTE
    jp      c,SD2_CONN_ERR

    ld      a,b                     ; length high
    call    PIWRITEBYTE
    jp      c,SD2_CONN_ERR

    ld      a,0                     ; block_index = 0
    call    PIWRITEBYTE
    jp      c,SD2_CONN_ERR

; The disk driver stages sectors in the kernel buffer before SENDDATA.
; Command strings remain direct ROM reads; neither needs per-byte RDSLT.
    ld      hl,0
 ifdef MSXPI_DRIVER
    ; Length bit 15 (sent above as part of the length): burst this payload.
    ; CF is clear here (the last PIWRITEBYTE succeeded); a good burst leaves
    ; BC=0 so PAYLOAD_TX returns at once, a failed one skips it.
    bit     7,b
    call    nz,PAYLOAD_TX_BURST
    call    nc,PAYLOAD_TX
 else
    call    PAYLOAD_TX
 endif
    jp      c,SD2_CONN_ERR
    jr      SD2_SEND_DONE

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
    jp      c,SD2_CONN_ERR

    call    PIREADBYTE              ; receive remote checksum
    jp      c,SD2_CONN_ERR

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
 ifdef MSXPI_DRIVER
    pop     bc              ; a retry never bursts: clear length bit 15 in
    res     7,b             ; the saved original
    push    bc
 endif
    jp      SD2_RETRY

SD2_CHKSUM_ERR:
    scf
    jr      SD2_EXIT

SD2_CHK_OK:
; -------------------------
; 3. Status handshake
; -------------------------
    call    PIREADBYTE              ; expect READY
    jp      c,SD2_HS_ERR
    cp      READY
    jr      nz,SD2_HS_ERR

    call    PIREADBYTE              ; expect status_from_python
    jp      c,SD2_CONN_ERR
    cp      RC_SUCCESS
    jr      nz,SD2_CONN_ERR

    ld      a,READY_ACK             ; send READY_ACK
    call    PIWRITEBYTE
    jp      c,SD2_HS_ERR

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
    jr      c, handshake_exit_err
    ld      a, b
    call    PIWRITEBYTE
    jr      c, handshake_exit_err
; Return the handshake's OWN result in the carry. Restoring the entry AF -
; which is what a single `pop af` here used to do - threw it away, so every
; caller saw the flags it arrived with: a failed handshake looked like a good
; one and the caller went on to read a block the other end never sent.
; (LDRPATCH197's `jr c,readpatch_neterr_ei` has been waiting for this.)
; A is still the expected_index the caller passed in, as before.
handshake_exit:
    pop     de
    pop     af
    or      a               ; CF=0: handshake done, A unchanged
    ret
handshake_err:
    pop     bc
handshake_exit_err:
    pop     de
    pop     af
    scf                     ; CF=1: handshake failed, A unchanged
    ret


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
    jp      c,r2_conn_err
    push    af
    call    PIREADBYTE      ; length low
    jr      c,r2_header_err
    ld      c,a
    call    PIREADBYTE      ; length high
    jr      c,r2_header_err
    ld      b,a
    ; One workarea lookup for all three metadata bytes. Keep retries in IX.
    push    ix
    push    de
    push    bc
    call    MSXPI_GETSTASH
    ld      bc,5
    add     hl,bc
    pop     bc
    pop     de
    pop     ix
    pop     af
    ld      (hl),a
    inc     hl
    ld      (hl),c
    inc     hl
    ld      (hl),b          ; raw: in the driver, bit 7 of this byte (length
                            ; bit 15) says the server sent this block as a
                            ; /WAIT burst - DSKIO_TXSIZE reads it to decide
                            ; whether writes may burst. Only the disk driver
                            ; asks for bursts, and it ignores the length.
    jr      r2_header_ok
r2_header_err:
    pop     af
    jp      r2_conn_err
r2_header_ok:
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
 ifdef MSXPI_DRIVER
    ; CF is clear here (the index compare above matched). A burst block
    ; leaves BC=0 on success, so PAYLOAD_RX returns at once; on failure
    ; CF skips it.
    bit     7,b
    call    nz,PAYLOAD_RX_BURST
    call    nc,PAYLOAD_RX
 else
    call PAYLOAD_RX
 endif
    jp c,r2_conn_err_x
    jp r2_payload_done

; ------------------------------------------------------------
; STORE_BYTE - write A to (DE), correctly even when DE is in page 1
; ------------------------------------------------------------
; When DE lands in #4000-#7FFF this ROM is banked in there - DOS reaches the
; driver by inter-slot call, which selects our slot in page 1 - so a plain
; LD (DE),A writes to the EEPROM and the byte is silently lost.
;
; Found on real hardware: loading a 26 KB .COM over MSXPi under MSX-DOS 1
; failed at exactly relative sector 31 of a 50-sector read - destination
; 0x100 + 31*512 = 0x3F00, the first sector to cross #4000.  Proven to track
; the ADDRESS and not the disk: the same-sized INLSTOCK.COM, at completely
; different absolute sectors, failed at the same relative index.  Every MSXPi
; tool is under ~16 KB and so stays below #4000, which is why a driver this
; old had never hit it.
;
; Decided per byte, not per block, because a block can begin in page 0 and
; cross into page 1 part way through - exactly the failing case - and because
; it keeps every caller of RECVDATA_ONEBLOCK correct without any of them
; having to know about it.
;
; Preserves A, BC, DE and HL: the payload loop needs the byte for its
; checksum and is using the other three as count, destination and running
; sum.  WRSLT is documented to corrupt AF, BC and E, hence the saves.  It is
; reached at 0014H, which is valid under MSX-DOS - the kernel keeps the
; inter-slot entry points live in page-0 RAM.  WRSLT switches SLOTS only,
; never mapper segments, so the segment DOS selected for page 1 stays put.
STORE_BYTE:
    bit     7, d
    jr      nz, STORE_BYTE_1
    bit     6, d
    jr      z, STORE_BYTE_1
    push    af
    push    hl
    push    bc
    ld      h, d
    ld      l, e            ; HL = destination
    ld      e, a            ; E  = data
    ld      a, (RAMAD1)     ; A  = slot holding RAM in page 1
    call    WRSLT
    ld      d, h
    ld      e, l            ; DE = destination again (WRSLT keeps HL)
    pop     bc
    pop     hl
    pop     af
    ret
STORE_BYTE_1:
    ld      (de), a
    ret

 ifdef MSXPI_DRIVER
; ------------------------------------------------------------
; PAYLOAD_RX_BURST / PAYLOAD_TX_BURST - payload with hardware /WAIT
; ------------------------------------------------------------
; In wait mode every IN from or OUT to $5A starts one transfer and stalls
; the Z80 until it has completed, so INIR/OTIR move a byte in 21 T-states
; instead of the polled loop's few hundred. The Pi holds READY for the whole
; block (SPI_BurstOut / SPI_BurstIn); waiting for it once first is what
; keeps the first INIR/OTIR from running before the burst has started (see
; ethtrans.asm).
;
; Receive: used when the server marked the block length with bit 15, which
; it only does when this side asked (bit 15 of the size sent by
; PerformHandshake; the disk driver asks when port $57 shows /WAIT).
; Send: used by SENDDATA when its length has bit 15 set, which the disk
; driver only does after the server has sent it a burst (DSKIO_TXSIZE).
;
; The buffer must not be in page 1 (the block instructions access memory
; directly); the disk driver only bursts to its caller's buffer outside page
; 1 or its private buffer. Only whole, non-empty 256-byte runs are marked (a
; 512-byte sector), so there is no remainder or empty case. The checksum is
; taken from memory afterwards, in either direction.
;
; The direction lives in E across the loop - NOT in F': an interrupt handler
; that uses EX AF,AF' without saving it (firmware, cartridge or DOS timer
; hooks may) would flip a read into a send in the middle of a burst.
;
; In:  DE = buffer, BC = length with bit 15 set, HL = 0
; Out: as PAYLOAD_RX/PAYLOAD_TX - DE advanced, BC = 0, HL = sum, CF = 0;
;      CF = error (ESC while waiting for the Pi)
PAYLOAD_TX_BURST:
    scf                         ; CF=1: send (OTIR)
    db      3Eh                 ; LD A,n - swallows the OR A below
PAYLOAD_RX_BURST:
    or      a                   ; CF=0: receive (INIR)
    sbc     a,a                 ; A = FFh send, 00h receive
    ld      l,a                 ; into L: HL is 0 on entry (the sum), and
    res     7,b                 ; EX DE,HL below moves it to E
    call    PAYLOAD_WAIT        ; Pi ready (READY up); ESC still aborts
    ret     c
    ld      a,1
    out     (CONTROL_PORT2),a   ; wait mode on
    push    bc
    push    de
    ex      de,hl               ; HL = buffer, E = direction
    ld      d,b                 ; D = number of 256-byte runs (at least 1)
    ld      b,c                 ; B = 0: each INIR/OTIR moves 256 bytes
    ld      c,DATA_PORT1
PRB_RUNS:
    ld      a,e
    or      a
    jr      nz,PRB_OUT
    inir
    jr      PRB_NEXT
PRB_OUT:
    otir
PRB_NEXT:
    dec     d
    jr      nz,PRB_RUNS
    xor     a
    out     (CONTROL_PORT2),a   ; wait mode off, before any polled byte
    ld      h,a                 ; HL = 0: checksum accumulator
    ld      l,a
    pop     de
    pop     bc
PRB_SUM:                        ; checksum the block, now in memory
    ld      a,(de)
    call    PAYLOAD_ADVANCE     ; HL += A, DE++, BC--; NZ while bytes remain
    jr      nz,PRB_SUM
    ret
 endif

; ------------------------------------------------------------
; ERROR PATHS - phase 1 (before the shadow-register section below): stack
; is untouched here, safe to return directly.
; ------------------------------------------------------------

r2_unexpecteddata:
    ld      a, RC_UNEXPECTEDDATA
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
    push    de              ; preserve dest pointer across MSXPI_GETSTASH
    call    MSXPI_GETSTASH          ; HL = IX = driver workarea
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
    ld      bc,0            ; byte count

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
    jp      SENDDATA        ; propagate carry from SENDDATA

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

; Not assembled into the ROM: the disk driver never calls PRINTNLINE, PRINTNUMBER or PRINTDIGIT, and the
; ROM is full.  Every other consumer of this file (the .COM tools in
; Client/src) still gets it.
 ifdef MSXPI_DRIVER
 else
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
 endif

STRTOHEX:
; Four hexadecimal digits followed by a delimiter. Preserve caller HL.
    push    hl
    ld      hl,0
    ld      b,4
STRTOHEX_LOOP:
    ld      a,(de)
    call    ATOHEX
    jr      c,STREXIT
    inc     de
    add     hl,hl
    add     hl,hl
    add     hl,hl
    add     hl,hl
    ld      c,a
    ld      a,l
    or      c
    ld      l,a
    djnz    STRTOHEX_LOOP
    inc     de              ; skip delimiter
    ld      b,h
    ld      c,l
STREXIT:
    pop     hl
    ret
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
; Not assembled into the ROM: the disk driver never calls CLEARBUF, and the
; ROM is full.  Every other consumer of this file (the .COM tools in
; Client/src) still gets it.
 ifdef MSXPI_DRIVER
 else
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
 endif


;-----------------------
; MSXPI_GETSTASH       |
;-----------------------
; RECVDATA_ONEBLOCK needs 3 bytes of RAM (offsets 5,6,7 of the block this
; returns) to stash header_rc and length across the payload loop - they
; can't stay in the inactive register bank, and this file is linked into
; several very different contexts, so there is no one place that is RAM
; in all of them. The includer must therefore say which it is, BEFORE the
; include line:
;
;   MSXPI_DRIVER    equ 1   ; linked into the MSX-DOS/Nextor disk driver -
;                           ; use the driver workarea via the kernel's
;                           ; GETWRK. Offsets 5+ are free there:
;                           ; DSKIO_SECTINFO only ever uses 0-4, and never
;                           ; runs concurrently with a CALL MSXPI.
;   MSXPI_RAM_STASH equ 1   ; linked into a plain .COM under MSX-DOS (or
;                           ; anything else running from RAM) - GETWRK
;                           ; doesn't exist there, so use the local buffer
;                           ; below. NOT valid for a ROM link: the writes
;                           ; would silently do nothing (see SENDDATA).
;
; Defining neither is a hard assembly error rather than a silent default,
; because the wrong choice fails silently at runtime, not at build time.
;
; Contract, identical either way: returns HL = IX = base of a block whose
; offsets 5..7 are free for this routine. Clobbers AF/HL/IX only - callers
; push whatever else they need around it.
 ifdef MSXPI_DRIVER
MSXPI_GETSTASH equ GETWRK       ; a plain alias, not a trampoline - the
                                ; driver build stays byte-identical to
                                ; what it was before this indirection
 else
  ifdef MSXPI_RAM_STASH
MSXPI_GETSTASH:
            ld      hl,MSXPI_STASH_BUF
            push    hl
            pop     ix
            ret
MSXPI_STASH_BUF:
            ; emitted as real bytes, not a ds reservation: a trailing ds
            ; is dropped from the .hex/.bin, which would leave the buffer
            ; sitting just past the end of the loaded .COM image, in RAM
            ; the host program is free to use for its own buffers.
            db      0,0,0,0,0   ; offsets 0-4 unused - kept only so the
            db      0,0,0       ; offsets match the driver workarea layout
  else
            dw      MSXPI_DRIVER_or_MSXPI_RAM_STASH_must_be_defined
  endif
 endif

        INCLUDE payload_generated.asm
