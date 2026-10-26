; MSXPi Interface
; Version 1.6.1
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
; LINK2 - the MSX side (documents/LINK2-DESIGN.md, section 8).
;
; The executable reference is software/Server/Python/tests/link2_sim.py, class
; Msx: this code puts the same bytes on the wire in the same order and reacts
; to every answer the same way.  Where this file and Msx disagree, Msx is
; right.  Written in the subset both assemblers accept: sjasmplus builds the BIOS
; half, msxpiext.bin and the tests, zmac the DOS half.
;
; Public entry points (paired with the server's link_* names, design 5.3):
;
;   LINK_SEND     DE = source, BC = length          one whole transfer, MSX -> Pi
;                 NC: DE = source + length, BC = 0, A = RC_SUCCESS
;                 C : A = RC_*  (RC_PROTOERR, RC_ESCPRESSED)
;   LINK_RECV     A = mode, DE = buffer, BC = largest block (the buffer needs
;                 BC+1 bytes in modes 0 and 1)       one whole transfer, Pi -> MSX
;                   mode 0  blocks are read into the buffer and dropped
;                   mode 1  each block is printed (a zero is put after it)
;                   mode 2  blocks follow one another from the buffer
;                 NC: A = the transfer's result code (RC_SUCCESS, or the code
;                     the Pi ended it with), DE = end of data (mode 2),
;                     BC = bytes received
;                 C : A = RC_*
;   LINK_COMMAND  DE = zero terminated command      LINK_SEND of the string
;   LINK_SEND_BYTE / LINK_RECV_BYTE                 one polled transfer, A = byte
;
; Everything is kept in a frame on the stack (IX), so the code can be linked
; into ROM.  The CRC runs in the shadow registers (DE' = CRC, H' = table page):
; the BIOS interrupt routine saves and restores both sets.
;
; LINK2_CRC_NOTABLE computes each CRC step without the 512-byte table, in
; L2_CRC_BYTE: same CRC, about 135 T-states more a byte, and it uses B' and C'
; too.  Written for the DOS half, which kept the table in the end (the Ethernet
; driver made room); no image uses it, the tests still do.
; ------------------------------------------------------------------------------

HELLO2:               EQU $B2
HELLO2_ACK:           EQU $B3
SIZE_MARK:            EQU $B4
LINK_ACK:             EQU $5A
LINK_NAK:             EQU $A5
LINK_ABORT:           EQU $0F
LINK2_FLAG_BURST:     EQU $01
LINK2_RETRIES:        EQU 10
LINK2_SENDER_CAP:     EQU 32
LINK2_WRONG_ANSWERS:  EQU 16
LINK2_FLOOD_MARGIN:   EQU 16
RC_PROTOERR:          EQU $F0

; --- the frame --------------------------------------------------------------
; L2_ENTER pushes the caller's AF, BC, DE and HL and clears L2_FRAME bytes below
; them; IX points at the cleared part.  The caller's registers are the
; transfer's arguments and stay where they were pushed.
L2_HDR:      EQU 0     ; 6: type, len lo, len hi (bit 7 = burst), seq, crc lo, crc hi
L2_FLAGS:    EQU 6     ; bit 0 burst_ok, bit 1 have_last
L2_SEQ:      EQU 7     ; sender: seq of the block; receiver: the next seq
L2_LAST:     EQU 8     ; receiver: last seq accepted
L2_NAKS:     EQU 9     ; receiver: consecutive NAKs; sender: attempts left
L2_LEN:      EQU 10    ; 2: length of the current block
L2_CRC:      EQU 12    ; 2: the payload CRC received ...
L2_END:      EQU 14    ; ... and the end mark after it.  Sender: non-zero = burst
L2_DUP:      EQU 15    ; the block being read is a duplicate
L2_TOTAL:    EQU 16    ; 2: bytes received
L2_FRAME:    EQU 18    ; even: L2_ENTER clears it a word at a time
L2_MODE:     EQU L2_FRAME+1    ; the caller's A   (LINK_RECV)
L2_SIZE:     EQU L2_FRAME+2    ; the caller's BC: largest block
L2_PTR:      EQU L2_FRAME+4    ; the caller's DE: buffer, then the current position
L2_REM:      EQU L2_FRAME+6    ; the caller's HL: bytes still to send (LINK_SEND)
L2_ARGS_LEN: EQU 8

; --- CRC step: A = byte, DE' = CRC, H' = table page --------------------------
 ifdef LINK2_CRC_NOTABLE
L2_CRC_STEP MACRO
    call L2_CRC_BYTE
    ENDM
 else
L2_CRC_STEP MACRO
    exx
    xor  d
    ld   l,a
    ld   a,(hl)
    xor  e
    ld   d,a
    inc  h
    ld   e,(hl)
    dec  h
    exx
    ENDM
 endif

; --- frame in and out --------------------------------------------------------
; Called first thing by LINK_SEND and LINK_RECV.  Keeps DE.
L2_ENTER:
    ex   (sp),hl                ; HL = our return address, the caller's HL in its place
    push de
    push bc
    push af
    ld   bc,0
    ld   a,L2_FRAME/2
L2E_CLR:
    push bc
    dec  a
    jr   nz,L2E_CLR
    ld   ix,0
    add  ix,sp
    jp   (hl)

; Leave with A and carry as they are; DE and BC are the caller's results.
L2_LEAVE:
    push af
    pop  iy
    ld   sp,ix
    ld   hl,L2_FRAME+L2_ARGS_LEN
    add  hl,sp
    ld   sp,hl
    push iy
    pop  af
    ret

; ============================================================================
; Byte primitives (design 8.3).  AF only; LINK_SEND_BYTE keeps A.
; ============================================================================
LINK_RECV_BYTE:
    call PAYLOAD_WAIT
    ret  c
    xor  a
    out  (CONTROL_PORT1),a
    call PAYLOAD_WAIT
    ret  c
    in   a,(DATA_PORT1)
    ret

LINK_SEND_BYTE:
    push af
    call PAYLOAD_WAIT
    jr   c,L2SB_ESC
    pop  af
    out  (DATA_PORT1),a
    or   a
    ret
L2SB_ESC:
    inc  sp
    inc  sp
    ret

; ============================================================================
; CRC-16/CCITT-FALSE (design 8.2).  The CRC lives in the shadow set.
; ============================================================================
L2_CRC_INIT:
    exx
    ld   de,$FFFF
 ifndef LINK2_CRC_NOTABLE
    ld   h,LINK_CRC_TABLE_HI>>8
 endif
    exx
    ret

; DE = the CRC so far
L2_CRC_GET:
    exx
    push de
    exx
    pop  de
    ret

 ifdef LINK2_CRC_NOTABLE
; One step without the table: x = (crc >> 8) ^ byte, x ^= x >> 4,
; crc = (crc << 8) ^ (x << 12) ^ (x << 5) ^ x.  A = byte.  Uses AF, B', C'.
L2_CRC_BYTE:
    exx
    xor  d
    ld   b,a
    rrca
    rrca
    rrca
    rrca
    and  $0F
    xor  b
    ld   b,a                    ; B' = x
    rrca
    rrca
    rrca
    ld   c,a                    ; C' = x rotated right 3
    and  $1F                    ; x >> 3
    xor  e
    ld   d,a
    ld   a,b
    rlca
    rlca
    rlca
    rlca
    and  $F0                    ; (x << 4) & F0h
    xor  d
    ld   d,a                    ; high byte: low ^ (x >> 3) ^ (x << 4)
    ld   a,c
    and  $E0                    ; (x << 5) & E0h
    xor  b
    ld   e,a                    ; low byte: x ^ (x << 5)
    exx
    ret
 endif

; HL = address, BC = count.  Uses AF, BC, E, HL.
LINK_CRC:
    ld   e,b
    ld   b,c
    inc  b
    dec  b
    jr   z,L2CM_RUNS
L2CM_PART:
    ld   a,(hl)
    inc  hl
    L2_CRC_STEP
    djnz L2CM_PART
L2CM_RUNS:
    ld   a,e
    or   a
    ret  z
L2CM_RUN:                       ; B = 0: 256 bytes a run
    ld   a,(hl)
    inc  hl
    L2_CRC_STEP
    djnz L2CM_RUN
    dec  e
    jr   nz,L2CM_RUN
    ret

; DE = the CRC of the first B bytes of the frame (B < 256); HL is left after them.
L2_FRAME_CRC:
    call L2_CRC_INIT
    push ix
    pop  hl
    ld   c,b
    ld   b,0
    call LINK_CRC
    jr   L2_CRC_GET

; Z = DE equals the word at HL (low byte first); HL is left at its high byte.
L2_CMP_DE:
    ld   a,(hl)
    cp   e
    ret  nz
    inc  hl
    ld   a,(hl)
    cp   d
    ret

; ============================================================================
; Polled payload: HL = source (LINK_PUT) or DE = destination (LINK_GET), BC = count.
; Counted in runs of up to 256 with DJNZ; CTRL+ESC is checked once a run.
; LINK_PUT uses AF, BC, E, HL; LINK_GET AF, BC, DE, HL.
; ============================================================================
LINK_PUT:
    ld   a,b
    or   c
    ret  z
    ld   e,b                    ; E = runs: a partial one of C bytes first, if any,
    ld   b,c                    ; then runs of 256 (B = 0)
    inc  b
    dec  b
    jr   z,L2P_RUN
    inc  e
L2P_RUN:
    call PAYLOAD_ESCAPE
    ret  c
L2P_LOOP:
    call PAYLOAD_WAIT
    ret  c
    ld   a,(hl)
    out  (DATA_PORT1),a         ; the byte goes out ...
    inc  hl
    L2_CRC_STEP                 ; ... while the CRC takes it in
    djnz L2P_LOOP
    dec  e
    jr   nz,L2P_RUN
    ret

; Stores through STORE_BYTE (a destination in page 1 goes through WRSLT) and
; updates the CRC with every byte.  The next transfer is started before the byte
; just read is stored and taken into the CRC, so that work runs while the Pi clocks
; the next byte.
LINK_GET:
    ld   a,b
    or   c
    ret  z
    ld   h,b                    ; H = runs, as in LINK_PUT; L = the byte just read
    ld   b,c
    inc  b
    dec  b
    jr   z,L2G_FIRST
    inc  h
L2G_FIRST:
    call PAYLOAD_WAIT
    ret  c
    xor  a
    out  (CONTROL_PORT1),a      ; the first transfer
L2G_LOOP:
    call PAYLOAD_WAIT
    ret  c
    in   a,(DATA_PORT1)
    ld   l,a
    dec  b
    jr   nz,L2G_NEXT
    dec  h
    jr   z,L2G_LAST             ; the last byte: no next transfer
    call PAYLOAD_ESCAPE         ; a new run of 256
    ret  c
L2G_NEXT:
    xor  a
    out  (CONTROL_PORT1),a      ; the next transfer, while this byte is processed
    ld   a,l
    call STORE_BYTE
    L2_CRC_STEP
    inc  de
    jr   L2G_LOOP
L2G_LAST:
    ld   a,l
    call STORE_BYTE
    L2_CRC_STEP
    inc  de
    or   a
    ret

; ============================================================================
; Bursts (design 3.4, 8.3): only straight after a polled read of the Pi's GO
; byte.  HL = buffer, D = number of 256 byte runs (at least 1).  Uses AF, BC, D, HL.
; ============================================================================
LINK_BURST_RECV:
    ld   a,1
    out  (CONTROL_PORT2),a
    ld   bc,DATA_PORT1
L2BR_RUN:
    inir
    dec  d
    jr   nz,L2BR_RUN
    xor  a
    out  (CONTROL_PORT2),a
    ret

LINK_BURST_SEND:
    ld   a,1
    out  (CONTROL_PORT2),a
    ld   bc,DATA_PORT1
L2BS_RUN:
    otir
    dec  d
    jr   nz,L2BS_RUN
    xor  a
    out  (CONTROL_PORT2),a
    ret

; Z = this interface has no hardware /WAIT.  What $57 reads must change when wait
; mode goes on (the same test as DSKIO_RXSIZE).  Uses AF, BC.
L2_HASWAIT:
    in   a,(CONTROL_PORT2)
    ld   b,a
    ld   a,1
    out  (CONTROL_PORT2),a
    in   a,(CONTROL_PORT2)
    ld   c,a
    xor  a
    out  (CONTROL_PORT2),a
    ld   a,c
    cp   b
    ret

; ============================================================================
; B bytes of the frame at IX out (L2_PUT_FRAME), or B bytes in to HL (L2_GET_BYTES)
; ============================================================================
L2_PUT_FRAME:
    push ix
    pop  hl
L2PF_LOOP:
    ld   a,(hl)
    inc  hl
    call LINK_SEND_BYTE
    ret  c
    djnz L2PF_LOOP
    ret

L2_GET_BYTES:
    call LINK_RECV_BYTE
    ret  c
    ld   (hl),a
    inc  hl
    djnz L2_GET_BYTES
    ret

; ============================================================================
; LINK_SEND_BLOCK (design 8.5).  IX = frame; A = type, L2_PTR = source,
; L2_LEN = length, L2_SEQ = seq.
; ============================================================================
L2_SEND_BLOCK:
    ld   (ix+L2_HDR),a
    ld   c,(ix+L2_LEN)
    ld   b,(ix+L2_LEN+1)
    ld   (ix+L2_HDR+1),c
    ld   d,0                    ; D = 80h: this block bursts
    bit  0,(ix+L2_FLAGS)
    jr   z,L2S_HEADER
    ld   a,c
    or   a
    jr   nz,L2S_HEADER          ; not a multiple of 256
    or   b
    jr   z,L2S_HEADER           ; empty
    bit  7,(ix+L2_PTR+1)
    jr   z,L2S_HEADER           ; source in page 0 or 1
    ld   d,$80
L2S_HEADER:
    ld   (ix+L2_END),d
    ld   a,b
    or   d
    ld   (ix+L2_HDR+2),a
    ld   a,(ix+L2_SEQ)
    ld   (ix+L2_HDR+3),a
    ld   b,4
    call L2_FRAME_CRC
    ld   (ix+L2_HDR+4),e
    ld   (ix+L2_HDR+5),d
    ld   (ix+L2_NAKS),LINK2_SENDER_CAP+1
L2S_TRY:
    dec  (ix+L2_NAKS)
    jr   z,L2_PROTO             ; the cap: LINK2_SENDER_CAP attempts
    ld   b,6
    call L2_PUT_FRAME
    ret  c
    call LINK_RECV_BYTE         ; the answer; for a burst it is the GO byte
    ret  c
    cp   LINK_ABORT
    jr   z,L2_PROTO
    cp   LINK_NAK
    jr   z,L2S_TRY
    call L2_CRC_INIT
    ld   l,(ix+L2_PTR)
    ld   h,(ix+L2_PTR+1)
    ld   c,(ix+L2_LEN)
    ld   b,(ix+L2_LEN+1)
    ld   a,(ix+L2_END)
    or   a
    jr   z,L2S_POLLED
    push hl
    push bc
    ld   d,b
    call LINK_BURST_SEND
    pop  bc
    pop  hl
    call LINK_CRC               ; the CRC pass over what was sent
    jr   L2S_TAIL
L2S_POLLED:
    call LINK_PUT               ; sends and takes the CRC in one pass
    ret  c
L2S_TAIL:
    call L2_CRC_GET
    ld   a,e
    call LINK_SEND_BYTE
    ret  c
    ld   a,d
    call LINK_SEND_BYTE
    ret  c
    ld   a,(ix+L2_SEQ)
    cpl                         ; the end mark
    call LINK_SEND_BYTE
    ret  c
    call LINK_RECV_BYTE
    ret  c
    ld   d,a
    ld   e,a
    ld   a,(ix+L2_HDR)
    cp   RC_READY
    jr   z,L2S_ONE
    call LINK_RECV_BYTE         ; the final block's answer comes twice
    ret  c
    ld   e,a
L2S_ONE:                        ; either one ACK: done; else either one ABORT: give up
    ld   a,LINK_ACK
    cp   d
    jr   z,L2_OK
    cp   e
    jr   z,L2_OK
    ld   a,LINK_ABORT
    cp   d
    jr   z,L2_PROTO
    cp   e
    jr   z,L2_PROTO
    jr   L2S_TRY

L2_PROTO:
    ld   a,RC_PROTOERR
    scf
    ret
L2_OK:
    or   a
    ret

; ============================================================================
; LINK_OPEN (design 8.4).  IX = frame; L2_SIZE and L2_PTR set.  A buffer at
; 8000h or above may burst.
; ============================================================================
L2_OPEN:
    ld   b,LINK2_WRONG_ANSWERS
L2O_HELLO:
    ld   a,HELLO2
    call LINK_SEND_BYTE
    ret  c
    call LINK_RECV_BYTE
    ret  c
    ld   c,a                    ; the answer and the flags are always read together
    call LINK_RECV_BYTE
    ret  c
    ld   d,a                    ; flags
    ld   a,c
    cp   HELLO2_ACK
    jr   z,L2O_ACKED
    djnz L2O_HELLO
    jr   L2_PROTO
L2O_ACKED:
    ld   e,0                    ; E = 1: this transfer may burst on the MSX side
    bit  7,(ix+L2_PTR+1)
    jr   z,L2O_NOWAIT
    call L2_HASWAIT
    jr   z,L2O_NOWAIT
    inc  e
L2O_NOWAIT:
    ld   a,d
    and  e
    ld   (ix+L2_FLAGS),a        ; burst_ok = Pi flag and /WAIT and buffer ok
    ld   (ix+L2_HDR),SIZE_MARK
    ld   a,(ix+L2_SIZE)
    ld   (ix+L2_HDR+1),a
    ld   a,e
    rrca                        ; bit 15: this transfer may burst
    or   (ix+L2_SIZE+1)
    ld   (ix+L2_HDR+2),a
    ld   b,3
    call L2_FRAME_CRC
    ld   (ix+L2_HDR+3),e
    ld   (ix+L2_HDR+4),d
    ld   b,LINK2_SENDER_CAP
L2O_FRAME:
    push bc
    ld   b,5
    call L2_PUT_FRAME
    pop  bc
    ret  c
    call LINK_RECV_BYTE
    ret  c
    cp   LINK_ABORT
    jr   z,L2_PROTO
    cp   LINK_NAK
    jr   nz,L2_OK
    djnz L2O_FRAME
; ============================================================================
; LINK_RECV_BLOCK (design 8.6).  IX = frame.  Out: NC, A = the block's type, the
; payload at L2_PTR (a duplicate goes over its original), L2_LEN its length.
; ============================================================================
L2_RECV_BLOCK:
    ld   (ix+L2_NAKS),0
L2R_HDR:
    push ix
    pop  hl
    ld   b,6
    call L2_GET_BYTES
    ret  c
    ld   b,4
    call L2_FRAME_CRC
    call L2_CMP_DE
    jp   nz,L2R_HNAK
    ; a header that is right: is it one we can take?
    ld   a,(ix+L2_HDR)
    sub  RC_SUCCESS
    cp   RC_PROTOERR-RC_SUCCESS+1
    jr   nc,L2R_BAD             ; not an RC code
    ld   c,(ix+L2_HDR+1)
    ld   a,(ix+L2_HDR+2)
    and  $7F
    ld   b,a
    ld   (ix+L2_LEN),c
    ld   (ix+L2_LEN+1),b
    ld   a,(ix+L2_HDR+3)        ; A = seq
    ld   d,0                    ; D = 1: a duplicate
    bit  1,(ix+L2_FLAGS)
    jr   z,L2R_NODUP
    cp   (ix+L2_LAST)
    jr   nz,L2R_NODUP
    inc  d
L2R_NODUP:
    ld   (ix+L2_DUP),d
    dec  d
    jr   z,L2R_SEQOK
    cp   (ix+L2_SEQ)
    jr   nz,L2R_BAD             ; neither the last seq nor the next
L2R_SEQOK:
    ld   l,(ix+L2_SIZE)
    ld   h,(ix+L2_SIZE+1)
    or   a
    sbc  hl,bc
    jr   c,L2R_BAD              ; longer than the largest block
    ; Mode 2: the caller gives no size, so the room is what the RAM has: a buffer
    ; below F380h (the system area) must end by there, any buffer by 10000h.
    ; Not for a duplicate, which goes over the block it repeats.
    ld   a,(ix+L2_DUP)
    or   a
    jr   nz,L2R_ACK
    ld   a,(ix+L2_MODE)
    cp   2
    jr   nz,L2R_ACK
    ld   a,b
    or   c
    jr   z,L2R_ACK
    ld   l,(ix+L2_PTR)
    ld   h,(ix+L2_PTR+1)
    dec  bc
    add  hl,bc                  ; HL = the last byte of the block
    inc  bc
    jr   c,L2R_BAD              ; past 10000h: never
    ld   de,$10000-$F380
    add  hl,de
    jr   nc,L2R_ACK             ; ends by F380h
    ld   l,(ix+L2_PTR)          ; ends past it (or exactly at 10000h): only
    ld   h,(ix+L2_PTR+1)        ; from a buffer already there
    add  hl,de
    jr   c,L2R_ACK
    ; (falls into L2R_BAD)

; A block we cannot take: ABORT in its header slot, then the flood.  The flood
; keeps answering ABORT for one block and its framing.
L2R_BAD:
    ld   bc,LINK2_FLOOD_MARGIN+1
L2R_FLOOD:
    ld   l,(ix+L2_SIZE)
    ld   h,(ix+L2_SIZE+1)
    add  hl,bc
L2R_FL:
    ld   a,LINK_ABORT
    call LINK_SEND_BYTE
    ret  c
    dec  hl
    ld   a,h
    or   l
    jr   nz,L2R_FL
    jp   L2_PROTO

; Counts a NAK.  A = NAK, or ABORT when that makes LINK2_RETRIES.
L2R_NAKS:
    inc  (ix+L2_NAKS)
    ld   a,(ix+L2_NAKS)
    cp   LINK2_RETRIES
    ld   a,LINK_NAK
    ret  c
    ld   a,LINK_ABORT
    ret

L2R_HNAK:                       ; a bad header: a single answer
    call L2R_NAKS
    call LINK_SEND_BYTE
    jr   L2R_NAKED
L2R_PNAK:                       ; a bad payload: doubled for a final block
    call L2R_NAKS
    call L2_ANSWER
L2R_NAKED:
    ret  c
    cp   LINK_ABORT
    jp   nz,L2R_HDR
    ld   bc,LINK2_FLOOD_MARGIN
    jr   L2R_FLOOD

L2R_ACK:
    ld   a,LINK_ACK
    call LINK_SEND_BYTE
    ret  c
    ld   e,(ix+L2_PTR)          ; where the payload goes
    ld   d,(ix+L2_PTR+1)
    ld   a,(ix+L2_DUP)
    or   a
    jr   z,L2R_DEST
    ld   a,(ix+L2_MODE)
    cp   2
    jr   nz,L2R_DEST
    ex   de,hl                  ; a duplicate in mode 2 goes over the block it repeats
    sbc  hl,bc                  ; (CF = 0: A was 2)
    ex   de,hl
L2R_DEST:
    call L2_CRC_INIT
    bit  7,(ix+L2_HDR+2)
    jr   z,L2R_POLL
    call LINK_RECV_BYTE         ; GO: its value is not checked, it only synchronises
    ret  c
    bit  0,(ix+L2_FLAGS)        ; INIR only when we allowed bursts and the length suits it;
    jr   z,L2R_POLL             ; a damaged flags byte can leave the Pi bursting to a polled MSX
    ld   a,c
    or   a
    jr   nz,L2R_POLL
    or   b
    jr   z,L2R_POLL
    ex   de,hl                  ; HL = destination
    push hl
    push bc
    ld   d,b                    ; runs of 256
    call LINK_BURST_RECV
    pop  bc
    pop  hl
    call LINK_CRC               ; the CRC pass over what was received
    jr   L2R_TRAIL
L2R_POLL:
    call LINK_GET
    ret  c
L2R_TRAIL:                      ; crc lo, crc hi, end mark
    push ix
    pop  hl
    ld   de,L2_CRC
    add  hl,de
    push hl
    ld   b,3
    call L2_GET_BYTES
    pop  hl
    ret  c
    call L2_CRC_GET
    call L2_CMP_DE
    jr   nz,L2R_PNAK
    inc  hl
    ld   a,(ix+L2_HDR+3)
    cpl
    cp   (hl)
    jr   nz,L2R_PNAK
    ld   a,LINK_ACK
    call L2_ANSWER
    ret  c
    ld   a,(ix+L2_DUP)
    or   a
    jp   nz,L2_RECV_BLOCK       ; a duplicate: dropped, the next block starts its count afresh
    ld   a,(ix+L2_HDR+3)
    ld   (ix+L2_LAST),a
    inc  a
    ld   (ix+L2_SEQ),a
    set  1,(ix+L2_FLAGS)
    ld   a,(ix+L2_HDR)
    or   a
    ret

; A out once, or twice after a final block (type other than RC_READY).  Keeps A.
L2_ANSWER:
    ld   b,a
    call LINK_SEND_BYTE
    ret  c
    ld   a,(ix+L2_HDR)
    cp   RC_READY
    ld   a,b
    ret  z
    jp   LINK_SEND_BYTE

; ============================================================================
; LINK_SEND
; ============================================================================
LINK_SEND:
    ld   hl,MAXBUFSIZE
LINK_SEND_SIZE:                 ; HL = the largest block to send
    push hl
    push bc
    pop  hl                     ; L2_REM = length
    pop  bc                     ; L2_SIZE = largest block
    call L2_ENTER
    call L2_OPEN
    jp   c,L2_LEAVE
L2SEND_LOOP:
    ld   l,(ix+L2_REM)
    ld   h,(ix+L2_REM+1)
    ld   c,(ix+L2_SIZE)
    ld   b,(ix+L2_SIZE+1)
    ld   a,RC_READY
    or   a
    sbc  hl,bc
    jr   c,L2SEND_LAST          ; size >= remaining: the last block
    jr   z,L2SEND_LAST
    ld   (ix+L2_REM),l
    ld   (ix+L2_REM+1),h
    jr   L2SEND_BLOCK
L2SEND_LAST:
    add  hl,bc
    ld   b,h
    ld   c,l
    ld   a,RC_SUCCESS
L2SEND_BLOCK:
    ld   (ix+L2_LEN),c
    ld   (ix+L2_LEN+1),b
    call L2_SEND_BLOCK
    jp   c,L2_LEAVE
    ld   l,(ix+L2_PTR)
    ld   h,(ix+L2_PTR+1)
    ld   c,(ix+L2_LEN)
    ld   b,(ix+L2_LEN+1)
    add  hl,bc
    ld   (ix+L2_PTR),l
    ld   (ix+L2_PTR+1),h
    inc  (ix+L2_SEQ)
    ld   a,(ix+L2_HDR)
    cp   RC_READY
    jr   z,L2SEND_LOOP
    ex   de,hl                  ; DE = source + length
    ld   bc,0                   ; A = RC_SUCCESS, the last block's type
    or   a
    jp   L2_LEAVE

; ============================================================================
; LINK_RECV.  In modes 0 and 1 L2_PTR stays at the buffer.
; ============================================================================
LINK_RECV:
    call L2_ENTER
    call L2_OPEN
    jp   c,L2_LEAVE
L2RECV_LOOP:
    call L2_RECV_BLOCK
    jp   c,L2_LEAVE
    ld   c,(ix+L2_LEN)
    ld   b,(ix+L2_LEN+1)
    ld   l,(ix+L2_TOTAL)
    ld   h,(ix+L2_TOTAL+1)
    add  hl,bc
    ld   (ix+L2_TOTAL),l
    ld   (ix+L2_TOTAL+1),h
    ld   l,(ix+L2_PTR)
    ld   h,(ix+L2_PTR+1)
    add  hl,bc                  ; HL = the end of this block
    ld   a,(ix+L2_MODE)
    cp   1
    jr   c,L2RECV_NEXT          ; mode 0: dropped
    jr   z,L2RECV_PRINT
    ld   (ix+L2_PTR),l          ; mode 2: the next block follows it
    ld   (ix+L2_PTR+1),h
    jr   L2RECV_NEXT
L2RECV_PRINT:                   ; mode 1: terminate and print
    ld   (hl),TEXTTERMINATOR
    ld   l,(ix+L2_PTR)
    ld   h,(ix+L2_PTR+1)
    call PRINT
L2RECV_NEXT:
    ld   a,(ix+L2_HDR)
    cp   RC_READY
    jr   z,L2RECV_LOOP
    ld   e,(ix+L2_PTR)
    ld   d,(ix+L2_PTR+1)
    ld   c,(ix+L2_TOTAL)
    ld   b,(ix+L2_TOTAL+1)
    or   a
    jp   L2_LEAVE

; ============================================================================
; LINK_COMMAND: DE = zero terminated string.  C when it is empty.
; ============================================================================
LINK_COMMAND:
    ld   h,d
    ld   l,e
    xor  a
    ld   b,a
    ld   c,a
    cpir                        ; BC = -(length + 1)
    ld   a,b
    cpl
    ld   b,a
    ld   a,c
    cpl
    ld   c,a                    ; BC = length
    or   b
    jp   nz,LINK_SEND
    scf
    ret

 ifndef LINK2_CRC_NOTABLE
    DEFS (256-($ & 255)) & 255,0        ; the table starts on a page
    INCLUDE "link2_crc_table.asm"
  ifdef __SJASMPLUS__
    ASSERT LINK_CRC_TABLE_LO == LINK_CRC_TABLE_HI+256
    ASSERT (LINK_CRC_TABLE_HI & 255) == 0
  endif
 endif
