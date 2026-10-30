; Konami's Salamander (RC-758, Konami SCC MegaROM, 128 KB): the game's side of the PLAYNET stub, co-op.
; Assembled by ../rebuild.py together with the shared engine (playnet_engine.asm) and the 8 KB-bank mapper
; host (mapper_k8.asm), both copied here from software/Client/src/playnet/engine.
; Analysis and design: documents/SALAMANDER-DESIGN.md.
;
;   sjasmplus [-DSCRIPTED] --raw=../assets/stub.bin --sym=stub.sym glue.asm
;
; Co-op is the game's own DUALPLAY: player 1 (seat 0) flies the Vic Viper, player 2 (seat 1) the Lord
; British. Each machine reads its own joystick 1 or keyboard; the game gets player 1's input where it read
; port 1 and player 2's where it read port 2.

; D000h-DFFFh: never touched by the game (measured: only the BIOS RAM test writes it). The game owns
; C000h-CFFFh, E000h-F0F8h (SP = F0F0h at INIT, measured down to F0AAh) and F0F0h-F0F8h.
; The transport comes first: on the TCP/IP path it is in MSX-DOS's page 3 as well, below the TPA top (D706h under
; Nextor with RAMHELPR and INL, D406h under MSX-DOS 1 with MSR); the stub is only ever in the game's.
PN_TRANSPORT:   EQU     $D000                   ; netplay.transport_area.address
PN_ORG:         EQU     $D200                   ; netplay.stub.load
STUB_MAX:       EQU     1792                    ; netplay.stub.max

G_INPUT_BYTES:  EQU     2                       ; byte 0: joystick, byte 1: function keys (see rdLocal)
G_READ_LOCAL:   EQU     rdLocal
G_SOUND_TICK:   EQU     sndTick
G_CHECK_ADDR:   EQU     $E300                   ; the two players' blocks (E300h, E380h) and what follows
G_CHECK_LEN:    EQU     $0200
G_CATCHUP:      EQU     2                       ; the frame catch-up for the interrupts XCHG took (isrEnd)

MK_BANKS:       EQU     16                      ; 128 KB of 8 KB banks
MK_P1_MAX:      EQU     6                       ; page 1 uses 4 pairs: (0,1) (0,4) (0,7) (0,13)
MK_P2_MAX:      EQU     30                      ; page 2: 5 x 6 possible pairs, 24 seen in play
MK_MAP:         EQU     $DA00                   ; the bank engine's pair map, DA00h-DDFFh (after the stub)

SNSMAT_:        EQU     $0141
JOY1:           EQU     $51BF                   ; the game's own port-1 reader: joystick 1, cursors, space, M/N
GAME_RD:        EQU     $51A7                   ; the game's reader: one player, or both in DUALPLAY
IRQ_CNT:        EQU     $F0F7                   ; 16-bit interrupt counter (read at 4DA1h)
IRQ_CNT8:       EQU     $E23A                   ; 8-bit interrupt counter (read at 585Bh)
TIMER:          EQU     $4E7F                   ; per-interrupt countdown (E631h/E632h)
SND_DRV:        EQU     $6978                   ; the sound driver, banks 4/5/6 at 6000h-BFFFh
BANKS:          EQU     $F0F1                   ; the game's copy of the banks in W1, W2, W3
OWNSLOT:        EQU     $F0F6                   ; the game's own slot (set at 414Fh)
CARTSLOT:       EQU     $F0F4                   ; the slot of a Nemesis 2 cartridge, when one was found

        INCLUDE "playnet_engine.asm"
        INCLUDE "mapper_k8.asm"

; ---- interrupt: what the handler did before the frame (4069h-40ABh), once per sound tick ------------
; The handler is patched to count the interrupt and go straight to the frame (406Dh). Everything it did per
; interrupt is done here instead, T times a frame on both machines: the two counters and the countdown are
; read by the game, so they must advance with the frames, not with each machine's interrupts.
sndTick:
        ld      hl,(IRQ_CNT)
        inc     hl
        ld      (IRQ_CNT),hl
        ld      hl,IRQ_CNT8
        inc     (hl)
        call    TIMER
        ld      a,4                             ; the driver's banks, as at 4085h
        call    MK_W1
        ld      de,$0506                        ; W2 and W3 in one switch
        call    MK_W23
        call    SND_DRV
        ld      a,(BANKS)                       ; and the game's banks back, as at 4099h
        call    MK_W1
        ld      a,(BANKS+1)
        ld      d,a
        ld      a,(BANKS+2)
        ld      e,a
        jp      MK_W23

; ---- inputs ------------------------------------------------------------------------------------------
; Local input, 2 bytes at HL:
;   byte 0: bits 0-5 as the game's port-1 reader (51BFh) returns them; bit 6 Y, bit 7 N (the Y/N prompt)
;   byte 1: bits 0-5 the function-key value of 521Fh-5240h (F1-F5 and the keys sharing their bits);
;           bit 6 F5 alone (the "CONTINUE F5" test at 55F9h)
rdLocal:
        push    hl
        call    JOY1
        ld      b,a
        ld      a,5
        call    SNSMAT_
        bit     6,a                             ; Y
        jr      nz,.y
        set     6,b
.y:     ld      a,4
        call    SNSMAT_
        bit     3,a                             ; N
        jr      nz,.n
        set     7,b
.n:     pop     hl
        ld      (hl),b
        inc     hl
        push    hl
        ld      a,6                             ; 521Fh-5240h, as the game does it
        call    SNSMAT_
        cpl
        rlca
        rlca
        rlca
        push    af
        ld      a,7
        call    SNSMAT_
        cpl
        rlca
        rlca
        rlca
        pop     bc
        or      b
        push    af
        ld      a,8
        call    SNSMAT_
        cpl
        rrca
        rrca
        rrca
        pop     bc
        or      b
        and     $3F
        ld      b,a
        ld      a,7
        call    SNSMAT_
        bit     1,a                             ; F5
        jr      nz,.f
        set     6,b
.f:     pop     hl
        ld      (hl),b
        ret

; TICK site: call 51A7h at 40B5h, once per frame, before the game reads any input
tickSite: call   PN_TICK
        jp      GAME_RD

; one player (1PLAYER, EXCHANGE, the menus): player 1. At 51B2h and 57DCh, for call 51BFh / call 51FFh.
p1:     ld      a,(PN_P1)
        and     $3F
        ret

; DUALPLAY: at 514Fh, for the test of which port a player block reads. IY = E300h: player 1, E380h: player 2.
dual:   ld      a,iyl
        or      a
        ld      a,(PN_P1)
        jr      z,.m
        ld      a,(PN_P2)
.m:     and     $3F
        ret

; the function keys, from either player (pause, continue): at 521Fh, then on at 5242h
fkeys:  ld      a,(PN_P2+1)
        ld      hl,PN_P1+1
        or      (hl)
        and     $3F
        ret

; F5 at 55F9h: carry = not pressed, as rra / rra of keyboard row 7. Preserves HL (SNSMAT did).
f5key:  push    hl
        ld      hl,PN_P2+1
        ld      a,(PN_P1+1)
        or      (hl)
        pop     hl
        and     $40
        sub     1
        ret

; Y at 57CCh, N at 57D4h: Z = pressed, from either player
keyY:   ld      a,$40
        jr      keyYN
keyN:   ld      a,$80
keyYN:  push    hl
        push    bc
        ld      b,a
        ld      hl,PN_P2
        ld      a,(PN_P1)
        or      (hl)
        cpl
        and     b
        pop     bc
        pop     hl
        ret

; ---- INIT: the same RAM on both machines ------------------------------------------------------------------
; INIT clears only E000h-EFFFh. C000h-CFFFh (PLAYNET's trampoline and MSX-DOS's leftovers), the stack area
; F000h-F0DFh and the interrupt counter F0F7h-F0F8h would otherwise start with whatever each machine had
; there. At 410Bh, in place of ld hl,E000h (SP = F0EEh here: F0E0h-F0EFh is left alone).
clrRam: ld      hl,$C000
        ld      bc,$1000
        call    .z
        ld      hl,$F000
        ld      bc,$00E0
        call    .z
        ld      hl,0
        ld      (IRQ_CNT),hl
        ld      hl,$E000
        ret
.z:     ld      (hl),0
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.z
        ret

; ---- the other cartridge -----------------------------------------------------------------------------
; B599h looks for a Nemesis 2 cartridge in every slot (RDSLT) and, if found, later maps that slot and reads
; it. The two machines must see the same world: at B59Dh, right after F0F5h = 0, return "none found", with
; F0F4h set to the game's own slot (the game does not initialise it otherwise).
probeOff:
        ld      a,(OWNSLOT)
        ld      (CARTSLOT),a
        ret

; ---- ld a,r ------------------------------------------------------------------------------------------
; R differs between machines. Each "ld a,r" and the instruction after it becomes a call to one of these:
; the same instruction on a deterministic value (xorshift, bit 7 clear as R's would be).
rnd:    push    hl
        ld      hl,(rndS)
        ld      a,h
        rra
        ld      a,l
        rra
        xor     h
        ld      h,a
        ld      a,l
        rra
        ld      a,h
        rra
        xor     l
        ld      l,a
        xor     h
        ld      h,a
        ld      (rndS),hl
        and     $7F
        pop     hl
        ret
rndS:   defw    $A5C3

rLdB:   call    rnd                             ; 4E58h, 7544h: ld a,r / ld b,a
        ld      b,a
        ret
rRrca:  call    rnd                             ; 65ABh: ld a,r / rrca
        rrca
        ret
rRra:   call    rnd                             ; 99F1h: ld a,r / rra
        rra
        ret
rXorHL: call    rnd                             ; 718Bh: ld a,r / xor (hl)
        xor     (hl)
        ret
rAdd:   call    rnd                             ; 9CCAh, 9CD3h: ld a,r / add a,a
        add     a,a
        ret
rAnd07: call    rnd                             ; 67DAh: ld a,r / and 07h
        and     $07
        ret
rAnd1F: call    rnd                             ; AE7Ah, B03Ah: ld a,r / and 1Fh
        and     $1F
        ret
rAnd3F: call    rnd                             ; 73D5h: ld a,r / and 3Fh
        and     $3F
        ret
rAnd78: call    rnd                             ; 7274h: ld a,r / and 78h
        and     $78
        ret

; ---- the frame catch-up (the engine's PN_AGAIN) ---------------------------------------------------------------
; Every frame is one run of the H.KEYI handler, and an interrupt that comes while it runs only counts (the busy flag
; E205h): a frame that the exchange makes longer than an interrupt period costs a whole period. When an interrupt
; went by inside the exchange, taken by MSX-DOS's handler in XCHG (TCP/IP; G_CATCHUP 2), the next frame runs as soon
; as this one ends (one at most). Interrupts that the game's own work makes it miss stay dropped, as on the cartridge,
; and so do those its handler saw during PN_TICK (G_CATCHUP 1 catches those too: see the README). Only the
; pace changes, never what a frame computes.
; 40BEh (bank 0), in place of "xor a / ld (E205h),a" (4 bytes): the busy flag cleared, or the next frame now
isrEnd: call    PN_AGAIN
        jr      nz,.again
        ld      ($E205),a                       ; A = 0, as the game clears it
        ret
.again: pop     af                              ; the return address: the frame runs again from 40B4h
        jp      $40B4                           ; (ei, then the frame, the busy flag still set)
stubEnd:
        ASSERT  stubEnd <= PN_ORG + STUB_MAX
        ASSERT  PN_TRANSPORT + 512 <= PN_ORG && PN_ORG + STUB_MAX <= MK_MAP && MK_MAP + 1024 <= $E000
