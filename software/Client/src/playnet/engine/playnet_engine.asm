; PLAYNET lockstep engine (stub ABI 1). Specification: documents/PLAYNET-PROTOCOLS.md, sections 9-11.
;
; A game's glue defines these, then INCLUDEs this file, then adds the entry points its patches call:
;   PN_ORG         netplay.stub.load: where the stub is copied (page 3)
;   PN_TRANSPORT   netplay.transport_area.address: the transport vector PLAYNET installs
;   G_INPUT_BYTES  W, 1-4: input bytes per player per frame (netplay.input_bytes)
;   G_READ_LOCAL   reads the local player's input once per frame: W = 1 returns it in A,
;                  W > 1 fills the W bytes at HL. May clobber AF, BC, DE, HL.
;   G_SOUND_TICK   the sound driver, called with interrupts off after the exchange, T times a frame (0 = none)
;   G_CHECK_ADDR, G_CHECK_LEN   region checksummed every 32 frames (even length, at most 512)
; Optional: SCRIPTED (test builds: the local input comes from a fixed table, not from G_READ_LOCAL).
; The game's own per-interrupt sound calls are patched to PN_IRQ, which only counts interrupts.
;
; Both machines run the whole game; only the inputs cross the network. Frame F uses the local input read
; at frame F-D and the remote input for F (D = the input delay agreed before the game started; frames
; 0..D-1 need no remote input). Frame numbers are 8-bit and wrap; the live window is never above 16
; frames, so differences are taken modulo 256. A packet carries the last 8 frames of local input, so a
; loss of up to 7 consecutive packets is repaired by the next one. While the remote input for F is
; missing, the frame waits here with interrupts on, polling the transport and resending every 16th poll.
;
; Sound: the original ticks its driver on every interrupt, and the game reads the driver's state (it
; waits for a jingle to end), so the number of ticks must be the same on both machines. Each frame record
; carries, after the W input bytes, the interrupts its sender counted during its last frame. Frame F ticks
; the driver T times, T = the count in player 1's record for F (seat 0), limited to 1..SND_MAX.

W:              EQU     G_INPUT_BYTES
REC:            EQU     W+1                     ; frame record: W input bytes, then the interrupt count
PL:             EQU     6+8*REC                 ; game packet: kind, seq, F, W, 8 records, check tag, value
SND_MAX:        EQU     8                       ; at most this many sound ticks a frame (a stall pauses the music)
KIND_GAME:      EQU     $10
XCHG:           EQU     PN_TRANSPORT+0          ; HL = packet or 0, DE = receive buffer -> A status
XEND:           EQU     PN_TRANSPORT+3          ; A = result code; never returns
SNSMAT:         EQU     $0141
R_EXIT:         EQU     1                       ; result codes (13.2): this player pressed the exit key
R_LEFT:         EQU     2                       ; the opponent ended it
R_LOST:         EQU     3                       ; connection lost
R_DESYNC:       EQU     4                       ; the machines lost sync

        ASSERT  W >= 1 && W <= 4
        ASSERT  G_CHECK_LEN >= 2 && G_CHECK_LEN <= 512 && (G_CHECK_LEN & 1) == 0

        MACRO   MULBY n                         ; A = A * n (n = 1..6, A < 16); E is scratch
        IF      n == 2 || n == 4
        add     a,a
        ENDIF
        IF      n == 4
        add     a,a
        ENDIF
        IF      n == 3 || n == 5 || n == 6
        ld      e,a
        add     a,a
        IF      n == 5
        add     a,a
        ENDIF
        add     a,e
        ENDIF
        IF      n == 6
        add     a,a
        ENDIF
        ENDM

        org     PN_ORG

; ---- header (stub ABI 1) -----------------------------------------------------------------
pnHeader:       defb    1                       ; stub ABI version
pnSeat:         defb    0                       ; written by the loader: 0 = player 1 (the inviter), 1 = player 2
pnDelay:        defb    3                       ; written by the loader: input delay in frames, 2-6
        IFDEF   SCRIPTED
pnFlags:        defb    0                       ; set by the build: bit 0 = end the game on a desync
        ELSE                                    ; (release builds); test builds only record it
pnFlags:        defb    1
        ENDIF

; ---- PN_TICK: once per game frame, before the game uses any input -----------------------
; Preserves BC, DE, HL, IX, IY. Returns with interrupts enabled.
PN_TICK:
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        ei
        call    tick
tickDone:
        IF      G_SOUND_TICK
        ld      a,(sndN)                        ; the sound driver ticks here, as often as
        or      a                               ; player 1's machine counted interrupts
        jr      nz,.n1
        inc     a
.n1:    cp      SND_MAX+1
        jr      c,.n2
        ld      a,SND_MAX
.n2:    ld      b,a
.snd:   push    bc
        di
        call    G_SOUND_TICK
        ei
        pop     bc
        djnz    .snd
        ENDIF
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        ret

; PN_END: A = result code. The transport tells the opponent and leaves the game.
PN_END:         EQU     XEND

; PN_IRQ: the game's interrupt handler calls this where it ticked its sound driver. Preserves all.
PN_IRQ: push    af
        ld      a,(irqCnt)
        inc     a
        ld      (irqCnt),a
        pop     af
        ret

tick:   ld      a,(started)                     ; frame numbers wrap: guard by state, not by the counter
        or      a
        call    z,prime
        ld      hl,nf
        inc     (hl)                            ; F
        call    exitKey
        call    chkTick
        ld      a,(nf)                          ; own[F+D] = the local input read now
        call    addDelay
        call    ownSlot
        call    readLocal
        ld      a,(nf)                          ; and after it, the interrupts since the last tick
        call    addDelay
        call    ownSlot
        ld      de,W
        add     hl,de
        ld      a,(irqLast)
        ld      c,a
        ld      a,(irqCnt)
        ld      (irqLast),a
        sub     c
        ld      (hl),a
        call    send                            ; txbuf := F, own[F+D-7 .. F+D]
        ld      hl,txbuf
.xchg:  ld      de,rxbuf
        call    XCHG                            ; send and/or take a packet, one transaction
        ld      c,a
        ld      hl,irqCnt                       ; E = interrupts the call took away from the game: count them
        di
        ld      a,(hl)
        add     a,e
        ld      (hl),a
        ei
        ld      a,c
        call    onStatus
        ld      a,(nf)                          ; has the remote input for F arrived?
        call    remSlot
        ld      a,(nf)
        cp      (hl)
        jr      z,.got
        ld      hl,stallCnt
        inc     (hl)
        ld      a,(hl)
        and     15
        ld      hl,0                            ; just poll...
        jr      nz,.xchg
        ld      hl,txbuf                        ; ...and every 16th poll resend as well
        jr      .xchg
.got:                                           ; PN_P1, PN_P2 := this frame's inputs, by seat
        ld      a,(nf)
        call    remSlot
        inc     hl
        push    hl                              ; the remote input
        ld      a,(nf)
        call    ownSlot                         ; HL = the local input
        pop     de
        ld      a,(pnSeat)
        or      a
        jr      z,.seat0
        ex      de,hl
.seat0: push    de                              ; HL = player 1's, DE = player 2's
        push    hl
        ld      de,W
        add     hl,de
        ld      a,(hl)                          ; player 1's interrupt count: this frame's sound ticks
        ld      (sndN),a
        pop     hl
        ld      de,PN_P1
        ld      bc,W
        ldir
        pop     hl
        ld      bc,W                            ; DE = PN_P2, right after PN_P1
        ldir
        ret

; First tick: frames 0..D-1 need no remote input (their inputs stay zero on both machines).
prime:  ld      a,1
        ld      (started),a
        ld      a,(pnDelay)
        ld      b,a
.i:     ld      a,b
        dec     a
        ld      c,a
        call    remSlot
        ld      (hl),c                          ; tag of frame C = C
        djnz    .i
        ret

; A = A + D (mod 256)
addDelay:
        ld      hl,pnDelay
        add     a,(hl)
        ret

; A = frame -> HL = its slot. Own ring: 16 records of REC bytes. Remote ring: 16 x (tag, REC bytes).
; Clobber AF, DE.
ownSlot:
        and     15
        MULBY   REC
        ld      hl,ownVal
        jr      slotAt
remSlot:
        and     15
        MULBY   REC+1
        ld      hl,remRing
slotAt: ld      e,a
        ld      d,0
        add     hl,de
        ret

; HL = the own slot of frame F+D: store the local input there
readLocal:
        IFDEF   SCRIPTED
        push    hl
        ld      a,(pnSeat)                      ; 8 entries per seat, one per 16 frames:
        rrca                                    ; index = seat * 8 + (F / 16) mod 8
        ld      e,a
        ld      a,(nf)
        and     $70
        or      e
        rlca
        rlca
        rlca
        rlca
        ld      e,a
        ld      d,0
        ld      hl,scr0
        add     hl,de
        ld      a,(hl)
        pop     hl
        ld      (hl),a
        ret
        ELSE
        IF      W == 1
        push    hl
        call    G_READ_LOCAL
        pop     hl
        ld      (hl),a
        ret
        ELSE
        jp      G_READ_LOCAL
        ENDIF
        ENDIF

; txbuf := kind, seq+1, F, W, own[F+D-7 .. F+D] (each REC bytes); the check fields are set by chkTick
send:   ld      a,(nf)
        ld      (txbuf+2),a
        call    addDelay
        sub     7
        ld      b,8                             ; 8 frames
        ld      de,txbuf+4
.l:     push    af
        push    bc
        push    de
        call    ownSlot
        pop     de
        ld      bc,REC
        ldir
        pop     bc
        pop     af
        inc     a
        djnz    .l
        ld      hl,txbuf+1
        inc     (hl)                            ; a new sequence number
        ret

; A = transport status after XCHG: 0 nothing, 1 a packet in rxbuf, 2 the opponent is gone, 3 it left
onStatus:
        or      a
        ret     z
        dec     a
        jr      z,recv
        dec     a
        ld      a,R_LOST
        jp      z,PN_END
        ld      a,R_LEFT
        jp      PN_END

; take the packet in rxbuf. Its kind, width and length were checked by the session layer (the Pi, or
; PLAYNET's network engine), and equal profile hashes mean the same W on both sides.
recv:   ld      a,(rxbuf+1)
        ld      hl,rxSeen
        cp      (hl)
        ret     z                               ; a duplicate of the last one
        ld      (hl),a
        call    rxChk
        ld      a,(rxbuf+2)                     ; the sender's F
        call    addDelay
        sub     7
        ld      c,a                             ; C = g, first frame in the packet
        ld      hl,rxbuf+4
        ld      b,8
.lp:    ld      a,(nf)
        neg
        add     a,c                             ; g - F, modulo 256
        cp      16
        jr      nc,.no                          ; already consumed, or absurdly ahead
        push    hl
        ld      a,c
        call    remSlot
        ld      (hl),c                          ; tag = g
        inc     hl
        ex      de,hl
        pop     hl
        push    hl
        push    bc
        ld      bc,REC
        ldir                                    ; the record of frame g
        pop     bc
        pop     hl
.no:    ld      de,REC
        add     hl,de
        inc     c
        djnz    .lp
        ret

; Ctrl+Shift+F5 ends the game on both machines (row 6: bit 0 SHIFT, bit 1 CTRL; row 7: bit 1 F5)
exitKey:
        ld      a,6
        call    SNSMAT
        and     3
        ret     nz
        ld      a,7
        call    SNSMAT
        and     2
        ret     nz
        ld      a,R_EXIT
        jp      PN_END

; every 32nd frame: an 8-bit sum of the checksum region, sent with the packets and compared
chkTick:
        ld      a,(nf)
        and     31
        ret     nz
        ld      hl,G_CHECK_ADDR
        ld      b,(G_CHECK_LEN/2) & 255
        xor     a
.l:     add     a,(hl)
        inc     hl
        add     a,(hl)
        inc     hl
        djnz    .l
        ld      b,a
        ld      a,(nf)
        ld      c,a
        ld      (txbuf+4+8*REC),bc              ; the packet's check tag, value
        ld      (ownT),bc                       ; ownT = tag, ownV = value
        ld      hl,remT                         ; did the opponent's check for this frame arrive first?
        jr      cmpChk
; a packet arrived: remember its check; compare it if ours for that frame exists
rxChk:  ld      bc,(rxbuf+4+8*REC)              ; C = tag, B = value
        ld      a,c
        and     31
        ret     nz
        ld      (remT),bc
        ld      hl,ownT
; tag C, value B against the (tag, value) pair at HL
cmpChk: ld      a,(hl)
        cp      c
        ret     nz
        inc     hl
        ld      a,(hl)
        cp      b
        ret     z
        ld      a,(pnFlags)                     ; release builds end the game at once
        rrca
        ld      a,R_DESYNC
        jp      c,PN_END
        ld      a,(desync)                      ; test builds keep the frame of the first one
        or      a
        ret     nz
        ld      a,(nf)
        ld      (desyncF),a
        ld      a,1
        ld      (desync),a
        ret

; ---- state -------------------------------------------------------------------------------
started:        defb    0
nf:             defb    $FF                     ; current frame, -1 before the first tick
PN_FRAME:       EQU     nf
rxSeen:         defb    $FF
stallCnt:       defb    0
desync:         defb    0
desyncF:        defb    0
irqCnt:         defb    0                       ; interrupts seen by PN_IRQ (wraps)
irqLast:        defb    0                       ; irqCnt at the last tick
sndN:           defb    0                       ; sound ticks for this frame
ownT:           defb    $FF, 0                  ; tag, value of our last check
remT:           defb    $FF, 0                  ; tag, value of the opponent's last check
PN_P1:          defs    W
PN_P2:          defs    W
ownVal:         defs    16*REC
remRing:
        DUP     16
                defb    $FF                     ; tag: no frame yet
                defs    REC
        EDUP
txbuf:          defb    KIND_GAME, 0, 0, W
                defs    8*REC
                defb    $FF, 0                  ; check tag, value
rxbuf:          defs    PL
        IFDEF   SCRIPTED
scr0:   defb    $10,$10,$10,$10,$08,$10,$02,$10 ; seat 0 } the tables of the SOCCERNET test rig (seeded
        defb    $02,$04,$00,$10,$00,$10,$04,$04 ; seat 1 } random, gen_stub.py): they play a real match
        ENDIF
pnEngineEnd:
