; Konami's F1 Spirit (RC-?, Konami SCC MegaROM, 128 KB): the game's side of the PLAYNET stub.
; Assembled by ../rebuild.py together with the shared engine (playnet_engine.asm) and the 8 KB-bank mapper
; host (mapper_k8.asm), both copied here from software/Client/src/playnet/engine.
;
;   sjasmplus [-DSCRIPTED] --raw=../assets/stub.bin --sym=stub.sym glue.asm
;
; Two players, one on each machine: player 1 (seat 0, the inviter) plays where the game reads port 1 (joystick 1,
; cursors, space, M/N), player 2 (seat 1) where it reads port 2. Each machine reads its own joystick 1 / cursor
; keys; the menus are player 1's. In the game's 1PLAYER mode only player 1 matters.

; C000h-DFFFh and F100h-F37Fh: never touched by the game (measured after the BIOS start: no read, no write).
; The game owns E000h-F0FFh (SP = F0F0h at INIT).
; The transport comes first: on the TCP/IP path it is in MSX-DOS's page 3 as well, below the TPA top (D706h under
; Nextor with RAMHELPR and INL, D406h under MSX-DOS 1 with MSR); the stub is only ever in the game's.
PN_TRANSPORT:   EQU     $D000                   ; netplay.transport_area.address
PN_ORG:         EQU     $D200                   ; netplay.stub.load
STUB_MAX:       EQU     1792                    ; netplay.stub.max

G_INPUT_BYTES:  EQU     2                       ; byte 0: the pad (6 bits), byte 1: function keys F1-F5 (see rdLocal)
G_READ_LOCAL:   EQU     rdLocal
G_SOUND_TICK:   EQU     sndTick
G_SOUND_BATCH:  EQU     1                       ; G_SOUND_BEGIN/G_SOUND_END: banks 13-15 once a frame
G_SOUND_BEGIN:  EQU     sndBegin
G_SOUND_END:    EQU     sndEnd
G_CHECK_ADDR:   EQU     $E2C0                   ; the two players' blocks (E2C0h, E380h) and what follows
G_CHECK_LEN:    EQU     $0200
G_CATCHUP:      EQU     2                       ; the frame catch-up for the interrupts XCHG took (isrEnd)

MK_BANKS:       EQU     16                      ; 128 KB of 8 KB banks
MK_P1_MAX:      EQU     7                       ; page 1 uses 5 pairs: (0,1) (0,4) (0,7) (0,10) (0,13)
MK_P2_MAX:      EQU     27                      ; page 2: 5 x 5 pairs (W2: 2 5 8 11 14, W3: 3 6 9 12 15)
MK_MAP:         EQU     $DA00                   ; the bank engine's pair map, DA00h-DDFFh (after the stub)

JOY1:           EQU     $4367                   ; the game's own port-1 reader: joystick 1, cursors, space, M/N (6 bits)
FKEYS:          EQU     $43D1                   ; the game's function-key reader: F1-F5 in bits 0-4
BANKS:          EQU     $F0F1                   ; the game's copy of the banks in W1, W2, W3
SND_OUT:        EQU     $6AA5                   ; the sound driver's output stage (bank 13)
SND_QUE:        EQU     $4140                   ; the queue of sound requests (calls 6000h in bank 13)
SND_SEQ:        EQU     $6422                   ; the sound sequencer (bank 13)
COUNTDOWN:      EQU     $4155                   ; the 16-bit countdown of F0F7h-F0F8h, one per interrupt

        INCLUDE "playnet_engine.asm"
        INCLUDE "mapper_k8.asm"

; ---- interrupt: what the handler did before the frame (402Ah-407Ch), once per sound tick --------------------
; The handler at 4018h is patched, right after it sets its busy flag, to count the interrupt (PN_IRQ), draw the
; screen's deferred update when no frame is running (40BBh, the same step the cartridge takes: it reads nothing
; of the banks 13-15) and go on at 407Dh. The sound driver, its request queue, its sequencer and the countdown
; (the cartridge runs them on every interrupt, with banks 13-15 in W1-W3) move here, T times a frame on both
; machines: the game reads their state (the jingles' flags), so they advance with the frames. The countdown stays per
; interrupt: the frame logic waits on it inside a frame (a 6 s pause at 7E0Dh) and no TICK comes meanwhile.
isrA:   call    PN_IRQ
        call    COUNTDOWN                       ; per interrupt, not per frame: the frame logic spins on it (865Ch, from 7E0Dh)
        ld      a,($E1C5)
        rrca                                    ; carry = no frame is running
        call    nc,$40BB
        jp      $407D

; The game's banks are saved before a frame's first tick and put back after its last (G_SOUND_BEGIN, G_SOUND_END), not
; around each tick: the interrupt handler that can run between two ticks only uses bank 0 and page 3. Each tick maps banks
; 13-15 again only when its calls changed them.
sndBegin:
        ld      hl,(BANKS)                      ; as 402Ah-4045h: the game's banks saved
        ld      (sndSave),hl
        ld      a,(BANKS+2)
        ld      (sndSave+2),a
        ret

sndTick:
        ld      hl,BANKS                        ; as 402Ah-4045h: banks 13-15 in
        ld      (hl),13
        inc     hl
        ld      (hl),14
        inc     hl
        ld      (hl),15
        call    snd13
        call    SND_OUT
        call    snd13                           ; the banks again, as 4049h-4055h
        call    SND_QUE
        jp      SND_SEQ

snd13:  ld      a,13                            ; W1 := 13 (MK_W1 returns at once when it is there)
        call    MK_W1
        ld      hl,(mkCur+2)                    ; W2, W3 := 14, 15 in one switch, unless they are there
        ld      de,$0F0E
        or      a
        sbc     hl,de
        ret     z
        ld      de,$0E0F
        jp      MK_W23

sndEnd: ld      hl,(sndSave)                    ; and the game's banks back, as 4068h-407Ch
        ld      (BANKS),hl
        ld      a,(sndSave+2)
        ld      (BANKS+2),a
        ld      d,h
        ld      e,a
        ld      a,l
        call    MK_W1
        jp      MK_W23
sndSave:defs    3

; ---- the game's bank selects ------------------------------------------------------------------------
; 441Bh (W1, W2, W3 := A, A+1, A+2) and 4447h (W2, W3 := A, A+1) write W2 and W3 one after the other: through the bank
; engine that is a switch to a pair of one new and one old bank, then a second one. These set W2 and W3 in one switch
; (MK_W23). Same results: the game's copy F0F1h-F0F3h, A and the flags of the last "inc a", interrupts on.
sel3:   push    hl                              ; 441Ch, after the di
        push    de
        ld      hl,BANKS
        ld      (hl),a
        call    MK_W1
        inc     l
        inc     a
        ld      (hl),a
        ld      d,a
        inc     l
        inc     a
        ld      (hl),a
        ld      e,a
        call    MK_W23
        pop     de
        pop     hl
        ei
        ret

sel2:   ld      (BANKS+1),a                     ; 4448h, after the di
        push    de
        ld      d,a
        inc     a
        ld      (BANKS+2),a
        ld      e,a
        call    MK_W23
        pop     de
        ei
        ret

; ---- the start ----------------------------------------------------------------------------------------
; PLAYNET starts the game (INIT, 40E4h) on MSX-DOS's stack, which is in the stub's area (about D560h under MSX-DOS 1 on the
; V-25, elsewhere under Nextor): RSLREG and ENASLT (40E5h-4104h) would push into the stub before the game's own
; "ld sp,F0F0h" at 4114h, and did (the bank engine's tables). The same stack, set first; the game clears it at 4117h.
initSp: di                                      ; 40E4h: di / call 0138h
        ld      sp,$F0F0
        call    $0138
        jp      $40E8

; ---- inputs ------------------------------------------------------------------------------------------
; Local input, 2 bytes at HL:
;   byte 0: the game's port-1 reader (4367h): joystick 1, cursors, space and the M/N keys, bits 0-5
;   byte 1: the function keys of 43D1h: F1-F5 in bits 0-4
rdLocal:
        push    hl
        call    JOY1
        pop     hl
        ld      (hl),a
        inc     hl
        push    hl
        call    FKEYS
        pop     hl
        ld      (hl),a
        ret

; TICK site: call 4335h at 40A4h, once per frame, before the game reads any input
tickSite:
        call    PN_TICK
        jp      $4335

; the game's two readers: the title's menu (4281h) and the frame's (4344h) take player 1, the other (4350h) player 2
p1:     ld      a,(PN_P1)
        and     $3F
        ret

p2:     ld      a,(PN_P2)
        and     $3F
        ret

; the function keys from either player: at 4335h
fk:     ld      a,(PN_P2+1)
        ld      hl,PN_P1+1
        or      (hl)
        and     $1F
        ret

; ---- the passwords ------------------------------------------------------------------------------------
; B3A9h (bank 3) scans the whole keyboard for the password's letters: not part of the shared input. No key.
; (patched in place: scf, ret)

; ---- ld a,r ------------------------------------------------------------------------------------------
; R differs between machines. Each "ld a,r" and the instruction after it becomes a call to this: the same
; instruction on a deterministic value (xorshift, bit 7 clear as R's would be).
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

rRrca:  call    rnd                             ; 7327h (bank 1), 9021h (bank 2): ld a,r / rrca
        rrca
        ret

; ---- the frame catch-up ----------------------------------------------------------------------------------------
; Every frame is one run of the frame logic in the H.KEYI handler, and an interrupt that comes while it runs only
; counts (the flag E1C5h bit 0). In the race (modes 2 and 5) a frame starts on every 3rd interrupt (F0FCh, 409Ah): the
; cartridge's frame fits in 3 periods, ours (the exchange, the sound ticks of a frame, the bank engine) often not, and a
; frame that ends past the gate would wait for the next interrupt, a whole period. So a race frame that ends with F0FCh
; at 3 or more is followed by the next one at once (40A2h resets the counter: no credit builds up, the pace is never above
; the cartridge's). The interrupts that MSX-DOS's handler took inside XCHG (TCP/IP; G_CATCHUP 2: the engine's late) go
; into F0FCh, as the cartridge would have counted them. In the other modes (a frame every interrupt) such an interrupt
; runs the next frame at once. F0FCh is read nowhere else (40A2h/409Ah only): only the pace changes, never what a frame
; computes.
; 40B0h (bank 0), in place of "ld hl,E1C5h / res 0,(hl)" (5 bytes): the flag cleared, or the next frame now
isrEnd: ld      hl,late
        ld      b,(hl)                          ; B = the interrupts XCHG took since the last frame end (0 on the MSXPi link)
        ld      (hl),0
        ld      a,($E1C0)
        cp      5
        jr      z,.race
        cp      2
        jr      z,.race
        ld      a,b
        or      a
        jr      nz,.again
        jr      .clr
.race:  ld      hl,$F0FC
        ld      a,(hl)
        add     a,b
        jr      nc,.sum
        ld      a,$FF
.sum:   ld      (hl),a
        cp      3
        jr      nc,.again                       ; past the gate: the next frame now
.clr:   ld      hl,$E1C5
        res     0,(hl)
        ret
.again: pop     af                              ; the return address: the frame runs again from 408Fh
        call    $40BB                           ; after the deferred screen update the handler runs first (it changes the game's
        jp      $408F                           ; counters): interrupts off, the flag still set
stubEnd:
        ASSERT  stubEnd <= PN_ORG + STUB_MAX
        ASSERT  PN_TRANSPORT + 512 <= PN_ORG && PN_ORG + STUB_MAX <= MK_MAP && MK_MAP + 1024 <= $E000
