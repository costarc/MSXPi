; Resident netplay stub (installed at F000h by SOCCERNET.COM).
; GENERATED into stub.asm by gen_stub.py (script tables); edit this template.
;
;   sjasmplus --raw=stub.bin --sym=stub.sym [-DSCRIPTED] stub.asm
;
; Lockstep input exchange. Both machines run the whole game; only the two pad
; bytes cross the network. The patched ROM calls:
; The patched ROM calls (addresses exported to the loader through stub.inc):
;   pad1t  at 4896h (lee_los_mandos, once per frame): runs the network tick -
;          send my input, wait for the opponent's - then returns P1
;   pad1c / pad2c   cached P1 / P2 for the other callers in the same frame
;   rng1 / rng2     replace the two ld a,r coin flips (frame counter instead)
;   ROLE   0 = host (P1 local), 1 = client (P2 local); set by the loader
; Frame F uses the local input read at frame F-DELAY and the remote input for
; F. Frame numbers are 8-bit and wrap: the live window is never above 16
; frames, so differences are taken modulo 256. A packet carries the last 8
; local inputs, so a loss of up to 7 consecutive packets is repaired by the
; next one. If the remote input for F is missing, the frame stalls in the wait
; loop (interrupts stay on so the sound driver keeps ticking) and resends
; every 1024 polls.
;
; Transport (mailboxes, swapped for UNAPI UDP later; only send/recv change):
;   txbuf: seq, len, F, 8 inputs   (seq is bumped LAST)
;   rxbuf: same layout, written by the transport (seq written LAST)

DELAY:  EQU     3                       ; fixed delay (mailbox build); the native build negotiates it
        IFDEF   NATIVE
PL:     EQU     13                      ; packet: seq, len, F, 8 inputs, check tag, check value
        ELSE
PL:     EQU     11
        ENDIF
        MACRO   ADDDELAY k              ; A += delay - k   (HL is clobbered in the native build)
        IFDEF   NATIVE
        ld      hl,delay
        add     a,(hl)
        sub     k
        ELSE
        add     a,DELAY-k
        ENDIF
        ENDM
FRAME:  EQU     $E003
LEEMANDO1: EQU  $48B9
SNDTIC: EQU     $4F25                   ; tic_del_sonido

        org     $F000

pad1c:  ld      a,(cur1)
        ret
pad2c:  ld      a,(cur2)
        ret
rng1:   ld      a,(FRAME)
        rra
        ret
rng2:   ld      a,(FRAME)
        and     6
        ret

pad1t:  push    bc
        push    de
        push    hl
        push    ix
        push    iy
        ei
        call    tick
tickDone:
        di                              ; the sound driver ticks exactly once per
        call    SNDTIC                  ; game frame, here (see soccernet.asm)
        ei
        pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        ld      a,(cur1)
        ret

tick:   ld      hl,nf
        inc     (hl)                    ; F
        IFDEF   NATIVE
        call    z,connect               ; frame 0: handshake with the opponent first
        call    chkTick
        ENDIF
        call    readLocal
        ld      c,a
        ld      a,(nf)
        ADDDELAY 0
        and     15
        ld      e,a
        ld      d,0
        ld      hl,ownVal
        add     hl,de
        ld      (hl),c                  ; own[F+DELAY] = local input
        call    send
        IFDEF   NATIVE
        ld      a,3                     ; send txbuf and take a packet, one transaction
        call    xchg
.wait:  call    recv                    ; process what the last transaction brought
        call    haveRem
        jr      z,.got
        ld      a,(dead)
        or      a
        jp      nz,fatal                ; no news from the opponent for too long
        ld      hl,stallCnt
        inc     (hl)
        ld      a,(hl)
        and     15
        ld      a,2                     ; just poll...
        jr      nz,.poll
        ld      a,3                     ; ...and every 16th poll resend as well
.poll:  call    xchg
        jr      .wait
        ELSE
.wait:  call    recv
        call    haveRem
        jr      z,.got
        ld      hl,stallCnt
        inc     (hl)
        jr      nz,.wait
        inc     hl                      ; stallHi, the byte after stallCnt
        inc     (hl)
        ld      a,(hl)
        and     3
        call    z,send                  ; every 1024 polls, ~30 ms
        jr      .wait
        ENDIF
.got:   IFDEF   NATIVE
        ld      a,(desync)
        or      a
        call    nz,onDesync
        ENDIF
        ld      a,(nf)
        and     15
        ld      e,a
        ld      d,0
        ld      hl,remVal
        add     hl,de
        ld      b,(hl)                  ; remote input for F
        ld      hl,ownVal
        add     hl,de
        ld      c,(hl)                  ; my input for F
        ld      a,(ROLE)
        or      a
        jr      nz,.client
        ld      a,c
        ld      (cur1),a
        ld      a,b
        ld      (cur2),a
        ret
.client:
        ld      a,b
        ld      (cur1),a
        ld      a,c
        ld      (cur2),a
        ret

; local input for this frame
readLocal:
        IFDEF   SCRIPTED
        ld      a,(nf)                  ; 8 entries per role, one per 16 frames
        rrca
        rrca
        rrca
        rrca
        and     7
        ld      e,a
        ld      a,(ROLE)
        add     a,a
        add     a,a
        add     a,a                     ; client reads the second half
        add     a,e
        ld      e,a
        ld      d,0
        ld      hl,scr0
        add     hl,de
        ld      a,(hl)
        ret
        ELSE
        jp      LEEMANDO1               ; joystick port 1 + cursor keys + space
        ENDIF

; txbuf := F, own[F+DELAY-7 .. F+DELAY]; seq bumped last
send:   ld      a,(nf)
        ld      (txbuf+2),a
        ADDDELAY 7
        and     15
        ld      e,a
        ld      hl,txbuf+3
        ld      b,8
.l:     push    hl
        ld      d,0
        ld      hl,ownVal
        add     hl,de
        ld      a,(hl)
        pop     hl
        ld      (hl),a
        inc     hl
        inc     e
        ld      a,e
        and     15
        ld      e,a
        djnz    .l
        ld      a,10
        ld      (txbuf+1),a
        ld      hl,txbuf
        inc     (hl)
        ret

; take a new packet from rxbuf, if any
recv:   ld      a,(rxbuf)
        ld      hl,rxSeen
        cp      (hl)
        ret     z
        ld      (hl),a
        IFDEF   NATIVE
        call    rxChk
        ENDIF
        ld      a,(rxbuf+2)             ; the sender's F
        ADDDELAY 7
        ld      c,a                     ; C = g, first frame in the packet
        ld      hl,rxbuf+3
        ld      b,8
.lp:    ld      a,(nf)
        ld      d,a
        ld      a,c
        sub     d                       ; g - F, modulo 256
        cp      16
        jr      nc,.no                  ; already consumed, or absurdly ahead
        ld      a,c
        and     15
        ld      e,a
        ld      d,0
        push    hl
        ld      a,(hl)
        ld      hl,remVal
        add     hl,de
        ld      (hl),a
        ld      hl,remTag
        add     hl,de
        ld      (hl),c
        pop     hl
.no:    inc     hl
        inc     c
        djnz    .lp
        ret

; Z if the remote input for frame F has arrived
haveRem:
        ld      a,(nf)
        and     15
        ld      e,a
        ld      d,0
        ld      hl,remTag
        add     hl,de
        ld      a,(nf)
        cp      (hl)
        ret

        IFDEF   NATIVE
; MSXPi-native transport: one transaction on ports 56h/5Ah, polled mode, no slot
; switching, no keyboard access. Server side: msxpi_netplay.py.
;   MSX -> C9, flags, txbuf(11), sum      Pi -> n (0|11), n bytes, sum
; A = flags (1 send txbuf, 2 take a packet into rxbuf). Every wait is bounded; on a
; timeout or bad reply the link is reset (FFh to 56h) and the transaction counts as
; lost, which the protocol tolerates. Interrupts are off during the transaction.
xchg:   di
        ld      (xf),a
        ld      hl,txbuf
        ld      b,PL
        xor     a
.s:     add     a,(hl)
        inc     hl
        djnz    .s
        ld      (xs),a
        ld      hl,xhdr                 ; C9, flags, txbuf, sum
        ld      d,PL+3
.t:     ld      a,(hl)
        call    txb
        jr      c,xfail
        inc     hl
        dec     d
        jr      nz,.t
        call    rxb
        jr      c,xfail
        or      a
        jr      z,.none
        cp      $FF
        jr      z,.dead
        cp      $A0
        jr      nc,xstat
        cp      PL
        jr      nz,xfail
        ld      hl,rxtmp
        ld      d,PL
.r:     call    rxb
        jr      c,xfail
        ld      (hl),a
        inc     hl
        dec     d
        jr      nz,.r
        call    rxb                     ; the sum
        jr      c,xfail
        ld      e,a
        ld      hl,rxtmp
        ld      b,PL
        xor     a
.v:     add     a,(hl)
        inc     hl
        djnz    .v
        cp      e
        jr      nz,xdone                ; corrupted: drop it
        ld      hl,rxtmp
        ld      de,rxbuf
        ld      bc,PL
        ldir
        jr      xdone
.dead:  ld      a,1
        ld      (dead),a
.none:  call    rxb                     ; the sum of nothing
        jr      c,xfail
xdone:  ei
        ret
xstat:  and     $0F                     ; A0+state, delay, sum
        ld      (stState),a
        call    rxb
        jr      c,xfail
        ld      (stDelay),a
        call    rxb
        jr      c,xfail
        jr      xdone
xfail:  ld      a,$FF
        out     ($56),a                 ; reset the link; the next transaction starts clean
        jr      xdone

; A = byte to send. CF set on timeout. Corrupts AF, BC, E.
txb:    ld      e,a
        call    wrdy
        ret     c
        ld      a,e
        out     ($5A),a
        ret
; A = byte received. CF set on timeout. Corrupts AF, BC.
rxb:    call    wrdy
        ret     c
        xor     a
        out     ($56),a                 ; request a byte
        call    wrdy
        ret     c
        in      a,($5A)
        or      a
        ret
; spin until port 56h reads 0 (about 0.5 s at most)
wrdy:   ld      bc,0
.l:     in      a,($56)
        or      a
        ret     z
        dec     bc
        ld      a,b
        or      c
        jr      nz,.l
        scf
        ret
rxtmp:  defs    PL
delay:  defb    3
stState: defb   0                       ; 0 connecting, 1 ready, 2 version mismatch, 3 failed
stDelay: defb   0
dead:   defb    0
desync: defb    0
desyncF: defb   0
ownT:   defb    $FF
ownV:   defb    0
remT:   defb    $FF
remV:   defb    0
        ENDIF

        IFDEF   NATIVE
; ---- session: handshake, delay, desync check, fatal ----------------------------------
; Frame 0: restart the session on the Pi and wait until both sides are ready. The Pi
; checks the version, measures the round trip, agrees DELAY and reports it.
connect:
        ld      a,(stState)             ; frame numbers wrap: only the very first time
        or      a
        ret     nz
        ld      a,$C0                   ; restart session + status
.c:     call    xchg
        ld      a,(stState)
        or      a
        ld      a,$80                   ; status only from now on
        jr      z,.c
        ld      a,(stState)
        cp      1
        jp      nz,fatal
        ld      a,(stDelay)
        ld      (delay),a
        ld      d,a                     ; frames 0..delay-1 need no remote input
        ld      hl,remTag
        ld      bc,$1000                ; B = 16 entries, C = 0
.i:     ld      a,c
        cp      d
        jr      c,.k
        ld      a,$FF
.k:     ld      (hl),a
        inc     hl
        inc     c
        djnz    .i
        ret
; every 32nd frame: checksum of the players and the ball (E100-E2FF)
chkTick:
        ld      a,(nf)
        and     31
        ret     nz
        ld      hl,$E100
        ld      b,0
        xor     a
.l:     add     a,(hl)
        inc     hl
        add     a,(hl)
        inc     hl
        djnz    .l
        ld      b,a
        ld      a,(nf)
        ld      c,a
        ld      (txbuf+11),a
        ld      (ownT),a
        ld      a,b
        ld      (txbuf+12),a
        ld      (ownV),a
        ld      hl,remT                 ; did the opponent's check for this frame arrive first?
        jr      cmpChk
; a packet arrived: remember its check; compare it if ours for that frame exists
rxChk:  ld      a,(rxbuf+11)
        ld      c,a
        and     31
        ret     nz
        ld      a,c
        ld      (remT),a
        ld      a,(rxbuf+12)
        ld      b,a
        ld      (remV),a
        ld      hl,ownT
; tag C, value B against the (tag, value) pair at HL
cmpChk: ld      a,(hl)
        cp      c
        ret     nz
        inc     hl
        ld      a,(hl)
        cp      b
        ret     z
markDesync:
        ld      a,(desync)              ; keep the frame of the first one
        or      a
        ret     nz
        ld      a,(nf)
        ld      (desyncF),a
        ld      a,1
        ld      (desync),a
        ret
onDesync:
        IFDEF   DESYNC_ABORT
        jr      fatal
        ELSE
        ret
        ENDIF
fatal:  di
        xor     a
        ld      (4000h),a               ; wipe the 'AB' header of the RAM copy, or the BIOS
        ld      (4001h),a               ; would boot it as a cartridge after the reset
        jp      0                       ; reset the machine: the match is over
        ENDIF

ROLE:   defb    0                       ; set by the loader
nf:     defb    $FF                     ; current frame, -1 before the first tick
cur1:   defb    0
cur2:   defb    0
rxSeen: defb    0
stallCnt: defb  0
stallHi: defb   0
ownVal: defs    16
remVal: defs    16
remTag: defb    0,1,2                   ; frames 0..DELAY-1 need no remote input
        defb    $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        IFDEF   NATIVE
xhdr:   defb    $C9
xf:     defb    0
        ENDIF
txbuf:  defs    11
        IFDEF   NATIVE
        defb    $FF,0                   ; check tag, value
xs:     defb    0
        ENDIF
rxbuf:  defs    PL
        IFDEF   SCRIPTED
scr0:
@SCR0@
@SCR1@
        ENDIF
stubEnd:
        IFDEF   NATIVE
        ASSERT  stubEnd <= $F300               ; scripted test build; production ends 16 bytes sooner (stack reaches F30E)
        ELSE
        ASSERT  stubEnd <= $F280               ; the game's own stack residue starts at F322
        ENDIF
