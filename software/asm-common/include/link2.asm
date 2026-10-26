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
; right.  Assembled with sjasmplus only (-DMSXPI_LINK2).
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
L2_HDR:      EQU 0     ; 6: type, len lo, len hi (bit 7 = burst), seq, crc lo, crc hi
L2_FLAGS:    EQU 6     ; bit 0 burst_ok, bit 1 have_last, bit 2 buffer outside page 1
L2_SIZE:     EQU 7     ; 2: largest block
L2_SEQ:      EQU 9     ; sender: seq of the block; receiver: the next seq
L2_LAST:     EQU 10    ; receiver: last seq accepted
L2_NAKS:     EQU 11    ; receiver: consecutive NAKs; sender: attempts
L2_MODE:     EQU 12
L2_PTR:      EQU 13    ; 2: current buffer position
L2_START:    EQU 15    ; 2: buffer start
L2_TOTAL:    EQU 17    ; 2: bytes received
L2_LEN:      EQU 19    ; 2: length of the current block
L2_CRC:      EQU 21    ; 2: payload CRC (received, or computed for sending)
L2_END:      EQU 23    ; end mark received / sender: burst flag
L2_REM:      EQU 24    ; 2: bytes still to send
L2_DUP:      EQU 26    ; the block being read is a duplicate
L2_FRAME:    EQU 28

L2_ARGS:     EQU L2_FRAME   ; the caller's HL, DE, BC and AF, pushed below the frame
L2_ARGS_LEN: EQU 8

; --- CRC step: A = byte, DE' = CRC, H' = table page --------------------------
    MACRO L2_CRC_STEP
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

; --- frame in and out --------------------------------------------------------
    MACRO L2_ENTER
    push af
    push bc
    push de
    push hl
    ld   hl,-L2_FRAME
    add  hl,sp
    ld   sp,hl
    push hl
    pop  ix
    ld   (hl),0
    ld   d,h
    ld   e,l
    inc  de
    ld   bc,L2_FRAME-1
    ldir
    ENDM

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
; Byte primitives (design 8.3).  AF only.
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
    ld   h,LINK_CRC_TABLE_HI>>8
    exx
    ret

; DE = the CRC so far
L2_CRC_GET:
    exx
    push de
    exx
    pop  de
    ret

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

; The CRC of the 4 or 5 byte frame at IX in DE:  B = bytes covered
L2_FRAME_CRC:
    call L2_CRC_INIT
    push ix
    pop  hl
    ld   c,b
    ld   b,0
    call LINK_CRC
    jr   L2_CRC_GET

; ============================================================================
; Polled payload: HL = source (LINK_PUT) or DE = destination (LINK_GET), BC = count
; ============================================================================
LINK_PUT:
    ld   a,b
    or   c
    ret  z
L2P_LOOP:
    ld   a,c
    or   a
    call z,PAYLOAD_ESCAPE
    ret  c
    call PAYLOAD_WAIT
    ret  c
    ld   a,(hl)
    out  (DATA_PORT1),a         ; the byte goes out ...
    inc  hl
    dec  bc
    L2_CRC_STEP                 ; ... while the CRC takes it in
    ld   a,b
    or   c
    jr   nz,L2P_LOOP
    ret

; Stores through STORE_BYTE (a destination in page 1 goes through WRSLT) and
; updates the CRC with every byte.  The next transfer is started before the byte
; just read is stored and taken into the CRC, so that work runs while the Pi clocks
; the next byte.
LINK_GET:
    ld   a,b
    or   c
    ret  z
    call PAYLOAD_WAIT
    ret  c
    xor  a
    out  (CONTROL_PORT1),a      ; the first transfer
L2G_LOOP:
    call PAYLOAD_WAIT
    ret  c
    in   a,(DATA_PORT1)
    ld   l,a
    dec  bc
    ld   a,b
    or   c
    jr   z,L2G_LAST
    ld   a,c
    or   a
    call z,PAYLOAD_ESCAPE
    ret  c
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
; byte.  HL = buffer, D = number of 256 byte runs (at least 1).
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
; Sends B bytes of the frame at IX  (the header and the size frame)
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

; ============================================================================
; LINK_OPEN (design 8.4).  IX = frame with L2_SIZE set, bit 2 of L2_FLAGS set
; when the buffer is outside page 1.
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
    jp   L2_PROTO
L2O_ACKED:
    ld   e,0                    ; E = 1: this transfer may burst on the MSX side
    bit  2,(ix+L2_FLAGS)
    jr   z,L2O_NOWAIT
    call L2_HASWAIT
    jr   z,L2O_NOWAIT
    inc  e
L2O_NOWAIT:
    ld   a,d
    and  e
    and  LINK2_FLAG_BURST
    jr   z,L2O_SIZE
    set  0,(ix+L2_FLAGS)        ; burst_ok = Pi flag and /WAIT and buffer ok
L2O_SIZE:
    ld   (ix+L2_HDR),SIZE_MARK
    ld   a,(ix+L2_SIZE)
    ld   (ix+L2_HDR+1),a
    ld   a,(ix+L2_SIZE+1)
    bit  0,e
    jr   z,L2O_WORD
    or   $80                    ; bit 15: this transfer may burst
L2O_WORD:
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
    jp   z,L2_PROTO
    cp   LINK_NAK
    jp   nz,L2_OK
    djnz L2O_FRAME
L2_PROTO:
    ld   a,RC_PROTOERR
    scf
    ret
L2_OK:
    or   a
    ret

; ============================================================================
; LINK_SEND_BLOCK (design 8.5).  IX = frame; A = type, L2_PTR = source,
; L2_LEN = length, L2_SEQ = seq.
; ============================================================================
L2_SEND_BLOCK:
    ld   (ix+L2_HDR),a
    ld   d,0                    ; D = 1: this block bursts
    bit  0,(ix+L2_FLAGS)
    jr   z,L2S_HEADER
    ld   a,(ix+L2_LEN)
    or   a
    jr   nz,L2S_HEADER          ; not a multiple of 256
    ld   a,(ix+L2_LEN+1)
    or   a
    jr   z,L2S_HEADER           ; empty
    bit  7,(ix+L2_PTR+1)
    jr   z,L2S_HEADER           ; source in page 0 or 1
    inc  d
L2S_HEADER:
    ld   (ix+L2_END),d
    ld   a,(ix+L2_LEN)
    ld   (ix+L2_HDR+1),a
    ld   a,(ix+L2_LEN+1)
    bit  0,d
    jr   z,L2S_LENHI
    or   $80
L2S_LENHI:
    ld   (ix+L2_HDR+2),a
    ld   a,(ix+L2_SEQ)
    ld   (ix+L2_HDR+3),a
    ld   b,4
    call L2_FRAME_CRC
    ld   (ix+L2_HDR+4),e
    ld   (ix+L2_HDR+5),d
    ld   (ix+L2_NAKS),0         ; attempts
L2S_TRY:
    ld   a,(ix+L2_NAKS)
    cp   LINK2_SENDER_CAP
    jp   nc,L2_PROTO
    inc  (ix+L2_NAKS)
    ld   b,6
    call L2_PUT_FRAME
    ret  c
    call LINK_RECV_BYTE         ; the answer; for a burst it is the GO byte
    ret  c
    cp   LINK_ABORT
    jp   z,L2_PROTO
    cp   LINK_NAK
    jr   z,L2S_TRY
    ld   l,(ix+L2_PTR)
    ld   h,(ix+L2_PTR+1)
    call L2_CRC_INIT
    bit  0,(ix+L2_END)
    jr   z,L2S_POLLED
    ld   d,(ix+L2_LEN+1)
    push hl
    call LINK_BURST_SEND
    pop  hl
    ld   c,(ix+L2_LEN)          ; the CRC pass over what was sent
    ld   b,(ix+L2_LEN+1)
    call LINK_CRC
    jr   L2S_TAIL
L2S_POLLED:
    ld   c,(ix+L2_LEN)
    ld   b,(ix+L2_LEN+1)
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
    xor  $FF                    ; the end mark
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
L2S_ONE:
    ld   a,d
    cp   LINK_ACK
    jp   z,L2_OK
    ld   a,e
    cp   LINK_ACK
    jp   z,L2_OK
    ld   a,d
    cp   LINK_ABORT
    jp   z,L2_PROTO
    ld   a,e
    cp   LINK_ABORT
    jp   z,L2_PROTO
    jp   L2S_TRY

; ============================================================================
; LINK_RECV_BLOCK (design 8.6).  IX = frame.  Out: NC, A = the block's type, the
; payload at L2_PTR (a duplicate goes over its original), L2_LEN its length.
; ============================================================================
L2_RECV_BLOCK:
    xor  a
    ld   (ix+L2_NAKS),a
L2R_HDR:
    push ix
    pop  hl
    ld   b,6
L2R_H1:
    call LINK_RECV_BYTE
    ret  c
    ld   (hl),a
    inc  hl
    djnz L2R_H1
    ld   b,4
    call L2_FRAME_CRC
    ld   a,e
    cp   (ix+L2_HDR+4)
    jp   nz,L2R_HNAK
    ld   a,d
    cp   (ix+L2_HDR+5)
    jp   nz,L2R_HNAK
    ; a header that is right: is it one we can take?
    ld   a,(ix+L2_HDR)
    sub  RC_SUCCESS
    cp   RC_PROTOERR-RC_SUCCESS+1
    jp   nc,L2R_BAD             ; not an RC code
    ld   a,(ix+L2_HDR+1)
    ld   (ix+L2_LEN),a
    ld   a,(ix+L2_HDR+2)
    and  $7F
    ld   (ix+L2_LEN+1),a
    ld   e,(ix+L2_HDR+3)        ; E = seq
    ld   d,0                    ; D = duplicate
    bit  1,(ix+L2_FLAGS)
    jr   z,L2R_NODUP
    ld   a,(ix+L2_LAST)
    cp   e
    jr   nz,L2R_NODUP
    inc  d
L2R_NODUP:
    ld   (ix+L2_DUP),d
    bit  0,d
    jr   nz,L2R_SEQOK
    ld   a,(ix+L2_SEQ)
    cp   e
    jp   nz,L2R_BAD             ; neither the last seq nor the next
L2R_SEQOK:
    ld   l,(ix+L2_SIZE)
    ld   h,(ix+L2_SIZE+1)
    ld   c,(ix+L2_LEN)
    ld   b,(ix+L2_LEN+1)
    or   a
    sbc  hl,bc
    jp   c,L2R_BAD              ; longer than the largest block
L2R_ROOM:
    bit  0,(ix+L2_DUP)
    jr   nz,L2R_ACK
    ld   a,(ix+L2_MODE)
    cp   2
    jr   nz,L2R_ACK
    ld   l,(ix+L2_PTR)          ; mode 2: the caller gives no size, so the room is
    ld   h,(ix+L2_PTR+1)        ; what the RAM has: a buffer below F380h (the system
    add  hl,bc                  ; area) must end by there, any buffer by 10000h
    jr   c,L2R_WRAP
    ld   a,h
    cp   $F3
    jr   c,L2R_ACK
    jr   nz,L2R_CEIL
    ld   a,l
    cp   $81
    jr   c,L2R_ACK
L2R_CEIL:                       ; ends past F380h: fine only from a buffer already there
    ld   a,(ix+L2_PTR+1)
    cp   $F3
    jp   c,L2R_BAD
    jr   nz,L2R_ACK
    ld   a,(ix+L2_PTR)
    cp   $80
    jp   c,L2R_BAD
    jr   L2R_ACK
L2R_WRAP:                       ; past 10000h: never. Ending exactly there is the
    ld   a,h                    ; end past F380h above (a buffer below F380h would
    or   l                      ; run over the system area on its way)
    jp   nz,L2R_BAD
    jr   L2R_CEIL
L2R_ACK:
    ld   a,LINK_ACK
    call LINK_SEND_BYTE
    ret  c
    ld   e,(ix+L2_PTR)          ; where the payload goes
    ld   d,(ix+L2_PTR+1)
    bit  0,(ix+L2_DUP)
    jr   z,L2R_DEST
    ld   a,(ix+L2_MODE)
    cp   2
    jr   nz,L2R_DEST
    ld   l,e                    ; a duplicate in mode 2 goes over the block it repeats
    ld   h,d
    or   a
    sbc  hl,bc
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
    ld   a,b
    or   a
    jr   z,L2R_POLL
    ex   de,hl                  ; HL = destination
    push hl
    ld   d,b                    ; runs of 256
    call LINK_BURST_RECV
    pop  hl
    ld   c,(ix+L2_LEN)
    ld   b,(ix+L2_LEN+1)
    call LINK_CRC               ; the CRC pass over what was received
    jr   L2R_TRAIL
L2R_POLL:
    call LINK_GET
    ret  c
L2R_TRAIL:
    call LINK_RECV_BYTE
    ret  c
    ld   (ix+L2_CRC),a
    call LINK_RECV_BYTE
    ret  c
    ld   (ix+L2_CRC+1),a
    call LINK_RECV_BYTE
    ret  c
    ld   (ix+L2_END),a
    call L2_CRC_GET
    ld   a,e
    cp   (ix+L2_CRC)
    jp   nz,L2R_PNAK
    ld   a,d
    cp   (ix+L2_CRC+1)
    jp   nz,L2R_PNAK
    ld   a,(ix+L2_HDR+3)
    xor  $FF
    cp   (ix+L2_END)
    jp   nz,L2R_PNAK
    ld   a,LINK_ACK
    call LINK_SEND_BYTE
    ret  c
    ld   a,(ix+L2_HDR)
    cp   RC_READY
    jr   z,L2R_ACKED
    ld   a,LINK_ACK             ; the final block's answer goes out twice
    call LINK_SEND_BYTE
    ret  c
L2R_ACKED:
    bit  0,(ix+L2_DUP)
    jr   z,L2R_NEW
    ld   (ix+L2_NAKS),0         ; a duplicate: the next block starts its count afresh
    jp   L2R_HDR
L2R_NEW:
    ld   a,(ix+L2_HDR+3)
    ld   (ix+L2_LAST),a
    set  1,(ix+L2_FLAGS)
    inc  a
    ld   (ix+L2_SEQ),a
    ld   a,(ix+L2_HDR)
    or   a
    ret

L2R_HNAK:
    ld   c,0
    jp   L2R_NAK
L2R_PNAK:
    ld   c,1
L2R_NAK:                        ; C = 1 when the payload phase (the answer is doubled for a final block)
    inc  (ix+L2_NAKS)
    ld   a,(ix+L2_NAKS)
    cp   LINK2_RETRIES
    ld   b,LINK_NAK
    jr   c,L2R_NAK1
    ld   b,LINK_ABORT
L2R_NAK1:
    ld   a,b
    call LINK_SEND_BYTE
    ret  c
    bit  0,c
    jr   z,L2R_NAK2
    ld   a,(ix+L2_HDR)
    cp   RC_READY
    jr   z,L2R_NAK2
    ld   a,b
    call LINK_SEND_BYTE
    ret  c
L2R_NAK2:
    ld   a,b
    cp   LINK_ABORT
    jp   nz,L2R_HDR
    jp   L2R_FLOOD
L2R_BAD:
    ld   a,LINK_ABORT           ; in the header slot: a single answer
    call LINK_SEND_BYTE
    ret  c
L2R_FLOOD:                      ; keep answering ABORT for one block and its framing
    ld   c,(ix+L2_SIZE)
    ld   b,(ix+L2_SIZE+1)
    ld   hl,LINK2_FLOOD_MARGIN
    add  hl,bc
    ld   b,h
    ld   c,l
L2R_FL:
    ld   a,LINK_ABORT
    call LINK_SEND_BYTE
    ret  c
    dec  bc
    ld   a,b
    or   c
    jr   nz,L2R_FL
    jp   L2_PROTO

; ============================================================================
; LINK_SEND
; ============================================================================
LINK_SEND:
    ld   hl,MAXBUFSIZE
LINK_SEND_SIZE:                 ; HL = the largest block to send
    L2_ENTER
    ld   e,(ix+L2_ARGS+2)
    ld   d,(ix+L2_ARGS+3)
    ld   c,(ix+L2_ARGS+4)
    ld   b,(ix+L2_ARGS+5)
    ld   l,(ix+L2_ARGS)
    ld   h,(ix+L2_ARGS+1)
    ld   (ix+L2_PTR),e
    ld   (ix+L2_PTR+1),d
    ld   (ix+L2_REM),c
    ld   (ix+L2_REM+1),b
    ld   (ix+L2_SIZE),l
    ld   (ix+L2_SIZE+1),h
    bit  7,d
    jr   z,L2SEND_OPEN
    set  2,(ix+L2_FLAGS)
L2SEND_OPEN:
    call L2_OPEN
    jp   c,L2_LEAVE
L2SEND_LOOP:
    ld   e,(ix+L2_REM)
    ld   d,(ix+L2_REM+1)
    ld   l,(ix+L2_SIZE)
    ld   h,(ix+L2_SIZE+1)
    or   a
    sbc  hl,de
    jr   nc,L2SEND_LAST         ; size >= remaining: the last block
    ld   l,(ix+L2_SIZE)
    ld   h,(ix+L2_SIZE+1)
    ld   (ix+L2_LEN),l
    ld   (ix+L2_LEN+1),h
    ex   de,hl                  ; HL = remaining, DE = size
    or   a
    sbc  hl,de
    ld   (ix+L2_REM),l
    ld   (ix+L2_REM+1),h
    ld   a,RC_READY
    jr   L2SEND_BLOCK
L2SEND_LAST:
    ld   (ix+L2_LEN),e
    ld   (ix+L2_LEN+1),d
    xor  a
    ld   (ix+L2_REM),a
    ld   (ix+L2_REM+1),a
    ld   a,RC_SUCCESS
L2SEND_BLOCK:
    call L2_SEND_BLOCK
    jp   c,L2_LEAVE
    ld   l,(ix+L2_PTR)
    ld   h,(ix+L2_PTR+1)
    ld   e,(ix+L2_LEN)
    ld   d,(ix+L2_LEN+1)
    add  hl,de
    ld   (ix+L2_PTR),l
    ld   (ix+L2_PTR+1),h
    inc  (ix+L2_SEQ)
    ld   a,(ix+L2_HDR)
    cp   RC_READY
    jr   z,L2SEND_LOOP
    ld   e,(ix+L2_PTR)
    ld   d,(ix+L2_PTR+1)
    ld   bc,0
    ld   a,RC_SUCCESS
    or   a
    jp   L2_LEAVE

; ============================================================================
; LINK_RECV
; ============================================================================
LINK_RECV:
    L2_ENTER
    ld   e,(ix+L2_ARGS+2)
    ld   d,(ix+L2_ARGS+3)
    ld   c,(ix+L2_ARGS+4)
    ld   b,(ix+L2_ARGS+5)
    ld   a,(ix+L2_ARGS+7)
    ld   (ix+L2_MODE),a
    ld   (ix+L2_PTR),e
    ld   (ix+L2_PTR+1),d
    ld   (ix+L2_START),e
    ld   (ix+L2_START+1),d
    ld   (ix+L2_SIZE),c
    ld   (ix+L2_SIZE+1),b
    bit  7,d
    jr   z,L2RECV_OPEN
    set  2,(ix+L2_FLAGS)
L2RECV_OPEN:
    call L2_OPEN
    jp   c,L2_LEAVE
L2RECV_LOOP:
    call L2_RECV_BLOCK
    jp   c,L2_LEAVE
    ld   l,(ix+L2_TOTAL)
    ld   h,(ix+L2_TOTAL+1)
    ld   c,(ix+L2_LEN)
    ld   b,(ix+L2_LEN+1)
    add  hl,bc
    ld   (ix+L2_TOTAL),l
    ld   (ix+L2_TOTAL+1),h
    ld   a,(ix+L2_MODE)
    cp   2
    jr   z,L2RECV_STORE
    or   a
    jr   z,L2RECV_NEXT          ; mode 0: dropped
    ld   l,(ix+L2_START)        ; mode 1: terminate and print
    ld   h,(ix+L2_START+1)
    add  hl,bc
    ld   (hl),TEXTTERMINATOR
    ld   l,(ix+L2_START)
    ld   h,(ix+L2_START+1)
    call PRINT
    jr   L2RECV_NEXT
L2RECV_STORE:
    ld   l,(ix+L2_PTR)
    ld   h,(ix+L2_PTR+1)
    ld   c,(ix+L2_LEN)
    ld   b,(ix+L2_LEN+1)
    add  hl,bc
    ld   (ix+L2_PTR),l
    ld   (ix+L2_PTR+1),h
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
    ld   a,(de)
    or   a
    jr   nz,L2C_HAVE
    scf
    ret
L2C_HAVE:
    ld   bc,0
    push de
L2C_COUNT:
    ld   a,(de)
    or   a
    jr   z,L2C_DONE
    inc  de
    inc  bc
    jr   L2C_COUNT
L2C_DONE:
    pop  de
    jp   LINK_SEND

    ALIGN 256
    INCLUDE "link2_crc_table.asm"
    ASSERT LINK_CRC_TABLE_LO == LINK_CRC_TABLE_HI+256
