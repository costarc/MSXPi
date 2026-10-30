; Penguin-kun Wars 2 (ASCII, MSX2, 256 KB ASCII16 MegaROM): the game's side of the PLAYNET stub, versus.
; Assembled by ../rebuild.py together with the shared engine (playnet_engine.asm) and the ASCII16 mapper host
; (mapper_a16.asm), both copied here from software/Client/src/playnet/engine.
; Analysis and design: documents/PWARS2-DESIGN.md.
;
;   sjasmplus [-DSCRIPTED] [-DLOCAL] --raw=../assets/stub.bin --sym=stub.sym glue.asm
;
; The cartridge is a one-player game: a series of matches against computer opponents. Versus: player 1 plays
; the game's own penguin; player 2 takes over the computer opponent of every match (its AI decides in three
; states of a state machine, B134h: 0 pick a ball, 20h walk to it, 30h hold it; here player 2's joystick does).
; Menus, the map and the continue screen are player 1's.
;
; -DLOCAL: a test build without the network, for openMSX with the cartridge itself (implies the mapper host's
; CART): player 1 on the keyboard or joystick 1, player 2 on joystick 2.
;
; Memory: INIT copies 15 KB of code to B400h-EFFEh, the game copies data into 8000h-B3FFh, its stack is F100h
; downwards. Never written: A622h-A6FFh and A800h-AC7Fh (page 2, the game's own RAM segment under PLAYNET),
; and F100h-F37Fh (the transport). A700h-A7FFh only holds a copy of a table of bank 1, which the glue reads from
; the bank instead (xTab): the stub takes A630h-AC7Fh.
PN_TRANSPORT:   EQU     $F100                   ; netplay.transport_area.address
PN_ORG:         EQU     $A630                   ; netplay.stub.load
STUB_MAX:       EQU     $AC80-$A630             ; netplay.stub.max

        IFDEF   LOCAL
        DEFINE  CART
        ENDIF

G_INPUT_BYTES:  EQU     1                       ; bits 0-3: the joystick direction (0-8), bit 4: the trigger
G_READ_LOCAL:   EQU     rdLocal
G_SOUND_TICK:   EQU     sndTick                 ; the game's H.TIMI handler: music, the match clock, the throw
G_SOUND_MIN:    EQU     0                       ; power. A TICK is an input poll: no interrupt, no tick
G_CHECK_ADDR:   EQU     $B000                   ; the balls (B000h), the penguin (B100h), the opponent (B120h),
G_CHECK_LEN:    EQU     $0200                   ; the clock and the stage (B1F0h-B1FFh)

MK_BANKS:       EQU     32                      ; 16 banks of 16 KB = 32 halves of 8 KB
MK_P1_MAX:      EQU     17                      ; the 16 banks, and the spare the loader wants
MK_P2_MAX:      EQU     2                       ; page 2: the game's RAM, and a spare

GTSTCK:         EQU     $00D5
GTTRIG:         EQU     $00D8
RSLREG:         EQU     $0138
GAME_TIMI:      EQU     $E6AC                   ; the game's H.TIMI handler
FRAME:          EQU     $B1F2                   ; the game's frame counter
MUSIC:          EQU     $EF88                   ; the music playing (FFh: none)
; the opponent (B120h-B13Fh)
O_X:            EQU     $B121
O_STEP:         EQU     $B123
O_DIR:          EQU     $B124
O_TARGET:       EQU     $B128
O_WIDTH:        EQU     $B129
O_SPEED:        EQU     $B12A
O_STATE:        EQU     $B134
O_ANIM:         EQU     $B13A
O_ANIMT:        EQU     $B13C
O_WAIT:         EQU     $B126
; the opponent's AI states and its shared routines (RAM, from bank 0)
AI_PICK:        EQU     $D0BF                   ; state 0: choose a ball, walk to it
AI_WALK:        EQU     $D12A                   ; state 20h: walk, pick it up
AI_HOLD:        EQU     $D1E1                   ; state 30h: hold it, aim, throw
AI_MOVE:        EQU     $CC55                   ; one step towards O_DIR
AI_STEPANIM:    EQU     $CCA9                   ; the walking animation
AI_TAKE:        EQU     $D154                   ; pick up the ball at IX (O_TARGET = its number)
AI_THROW:       EQU     $D26C                   ; throw the ball held
AI_OPP:         EQU     $CB7F                   ; one opponent of a two-opponent match
BALL:           EQU     $E1B7                   ; A = ball number -> IX = its record (B000h + 16 A)

        OUTPUT  "stub.bin"
        IFDEF   LOCAL
        org     PN_ORG
pnHeader:       defb    2, 0, 2, 0, 1           ; as the engine's header, so the build and the symbols match
        ELSE
        INCLUDE "playnet_engine.asm"
        ENDIF
        INCLUDE "mapper_a16.asm"

; ---- inputs ------------------------------------------------------------------------------------------------
; The local input byte, read as the game's own readers do: the joystick in port 1 or the cursor keys, the
; trigger A or the space bar.
rdLocal:
        ld      a,1
        call    GTSTCK
        ld      b,a
        xor     a
        call    GTSTCK
        or      b                               ; (the game ors the two directions too)
        and     $0F
        push    af                              ; (the BIOS readers clobber BC)
        ld      a,1
        call    GTTRIG
        push    af
        xor     a
        call    GTTRIG
        pop     bc
        or      b
        and     $10
        pop     bc
        or      b
        ret

; Player 1's direction and trigger, as the game's readers return them (C764h: the direction; C753h: FFh while the
; trigger is held, else 0). t...: a TICK first (every input poll outside the match frame is one); c...: this
; frame's value (inside the match frame, whose TICK is at its start: tickInc).
tStk:   call    PN_TICK
cStk:   ld      a,(PN_P1)
        and     $0F
        ret
tTrg:   call    PN_TICK
cTrg:   ld      a,(PN_P1)
        and     $10
        ret     z
        ld      a,$FF
        ret

; ---- the frame: TICKs where the game counts its frames, and where it waits for the music --------------------
tickInc:
        call    PN_TICK
        ld      hl,FRAME
        inc     (hl)
        ret
tickDec:
        call    PN_TICK
        ld      hl,FRAME
        dec     (hl)
        ret
sndWait:                                        ; ld a,(EF88h): the wait for a tune to end (B697h)
        call    PN_TICK
        ld      a,(MUSIC)
        ret

; The game's H.TIMI handler, ticked by the engine (interrupts off). It may select bank 7 (the clock's "hurry"
; jingle at 20 s): the TICK can be inside code of another bank, so the bank is put back.
sndTick:
        push    ix
        push    iy
        exx
        push    bc
        push    de
        push    hl
        exx
        ex      af,af'
        push    af
        ex      af,af'
        call    MK_CUR
        push    af
        call    GAME_TIMI
        pop     af
        call    MK_SEL
        ex      af,af'
        pop     af
        ex      af,af'
        exx
        pop     hl
        pop     de
        pop     bc
        exx
        pop     iy
        pop     ix
        ret

; ---- INIT (4011h, in place of call RSLREG): the same RAM on both machines ---------------------------------------
; A cartridge starts after the BIOS cleared the RAM; under MSX-DOS it holds whatever it held. The code copy
; (B400h-EFFEh) follows; the stub (A630h-AC7Fh) stays. Then RSLREG, as the game wanted.
initGame:
        ld      hl,$8000
        ld      bc,PN_ORG-$8000
        call    zero
        ld      hl,PN_ORG+STUB_MAX
        ld      bc,$B400-PN_ORG-STUB_MAX
        call    zero
        jp      RSLREG                          ; (F000h-F0FFh is the game's stack: written before it is read;
                                                ; a cartridge's INIT runs on the BIOS's stack there)
zero:   ld      e,l
        ld      d,h
        inc     de
        dec     bc
        ld      (hl),0
        ldir
        ret

; ---- ld a,r ----------------------------------------------------------------------------------------------------
; R differs between machines. Each "ld a,r" (and the instruction next to it) becomes a call to one of these: the
; same instructions on a deterministic value (a 16-bit LFSR, bit 7 clear as R's would be).
rnd:    push    hl
        ld      hl,(rndS)
        add     hl,hl
        jr      nc,.n
        ld      a,l
        xor     $2D
        ld      l,a
.n:     ld      (rndS),hl
        ld      a,h
        and     $7F
        pop     hl
        ret
rndS:   defw    $A5C3
rndB:   ld      b,a                             ; ld b,a / ld a,r
        jp      rnd
rAddH:  call    rnd                             ; ld a,r / add a,h
        add     a,h
        ret
rAddL:  call    rnd                             ; ld a,r / add a,l
        add     a,l
        ret
rAddC:  call    rnd                             ; ld a,r / add a,c
        add     a,c
        ret

; ---- versus: player 2 is the opponent ----------------------------------------------------------------------------
; vsSet replaces "ld a,(B1F6h)" at the start of the opponent's frame (CA7Dh): player 2 controls it, and this frame's
; new trigger press is noted. In a match against two opponents (stage 4: B140h and B160h take turns in B120h),
; player 2 has the first one; aiOpp runs the second with the game's AI.
vsSet:  push    hl
        push    bc
        ld      a,1
        ld      (vsCtl),a
        ld      a,(PN_P2)
        ld      hl,vsLast
        ld      b,(hl)
        ld      (hl),a
        ld      c,a
        ld      a,b
        cpl
        and     c
        ld      (vsEdge),a
        pop     bc
        pop     hl
        ld      a,($B1F6)
        ret
aiOpp:  xor     a
        ld      (vsCtl),a
        call    AI_OPP
        ld      a,1
        ld      (vsCtl),a
        ret

vsCtl:  defb    0                               ; 1: the opponent being run is player 2's
vsLast: defb    0                               ; player 2's input in the last opponent frame
vsEdge: defb    0                               ; the bits newly set in it

; In place of the AI's "call CC55h" (the step towards O_DIR, for every state but 0, 40h, 90h, E0h): states 20h and
; 30h are player 2's, who moves in vsFree/vsHold.
vsMvG:  ld      a,(vsCtl)
        or      a
        jp      z,AI_MOVE
        ld      a,(O_STATE)
        cp      $20
        ret     z
        cp      $30
        ret     z
        jp      AI_MOVE

; P2's direction -> A = +1 (right: 2, 3, 4), FFh (left: 6, 7, 8), 0 (none). Z if none.
vsDir:  ld      a,(PN_P2)
        and     $0F
        cp      2
        jr      c,.none
        cp      5
        jr      c,.right
        cp      6
        jr      c,.none
        cp      9
        jr      nc,.none
        ld      a,$FF
        or      a
        ret
.right: ld      a,1
        or      a
        ret
.none:  xor     a
        ret

; One step in P2's direction, as AI_MOVE steps (O_STEP pixels, inside 0 .. -(width + speed)), with the walking
; animation. Out: NZ if it moved.
vsStep: call    vsDir
        ret     z
        ld      (O_DIR),a
        ld      a,7
        ld      (O_ANIMT),a
        call    AI_STEPANIM
        ld      a,(O_SPEED)
        ld      c,a
        ld      a,(O_WIDTH)
        neg
        sub     c
        ld      c,a                             ; C = the right limit
        ld      a,(O_STEP)
        or      a
        jr      nz,.s
        ld      a,2
.s:     ld      b,a
        ld      a,(O_DIR)
        cp      $80
        ld      a,(O_X)
        jr      c,.r
        sub     b
        jr      c,.no
        jr      .put
.r:     add     a,b
        jr      c,.no
        cp      c
        jr      nc,.no
.put:   ld      (O_X),a
        or      1
        ret
.no:    xor     a
        ret

; State 0 (and 20h): free. Walk; on a trigger press, pick up a ball in reach (on the opponent's half, not moving).
vsFree: ld      a,(vsCtl)
        or      a
        jr      nz,.p2
        ld      a,(O_STATE)
        or      a
        jp      z,AI_PICK
        jp      AI_WALK
.p2:    xor     a
        ld      (O_STATE),a
        call    vsStep
        ld      a,(vsEdge)
        and     $10
        ret     z
        ld      b,10                            ; the balls: is one in reach? (the AI's test, D130h-D153h)
        ld      ix,$B000
        ld      e,0
.ball:  ld      a,(ix+7)
        cp      $FF                             ; lying, nobody's
        jr      nz,.next
        ld      a,(ix+2)
        cp      $80                             ; on the opponent's half
        jr      nc,.next
        ld      c,(ix+1)
        dec     c
        dec     c
        ld      a,(O_X)
        sub     $10
        jr      c,.lo
        cp      c
        jr      nc,.next                        ; the ball is left of the reach
.lo:    ld      a,(O_X)
        ld      d,a
        ld      a,(O_WIDTH)
        add     a,d
        cp      c
        jr      c,.next                         ; right of it
        ld      a,e
        ld      (O_TARGET),a
        jp      AI_TAKE                         ; the AI's own pick-up: state 30h
.next:  push    de
        ld      de,16
        add     ix,de
        pop     de
        inc     e
        djnz    .ball
        ret

; State 30h: holding a ball. Wait for the pick-up to end, walk with it, throw it on a trigger press.
vsHold: ld      a,(vsCtl)
        or      a
        jp      z,AI_HOLD
        ld      a,(O_WAIT)
        or      a
        jr      z,.go
        dec     a
        ld      (O_WAIT),a
        ret
.go:    call    vsStep
        ld      a,(O_TARGET)                    ; the ball moves with the opponent (D235h)
        call    BALL
        ld      a,(O_X)
        add     a,$14
        ld      (ix+1),a
        ld      a,(vsEdge)
        and     $10
        ret     z
        jp      AI_THROW

; ---- the opponent's position table ----------------------------------------------------------------------------
; The game copies bank 1's 6F00h-6FFFh to A700h (C157h) and reads it as A = B = (A700h + (B121h)), C = (B121h) at
; E1AEh and in two bank copies of that routine (bank 12 7CE4h, bank 13 7907h). The copy is gone (A700h-A7FFh is
; the stub's): the table is read from bank 1 itself.
xTab:   push    hl
        ld      a,(O_X)
        ld      c,a
        call    MK_CUR
        push    af
        ld      a,1
        call    MK_SEL
        ld      h,$6F
        ld      l,c
        ld      b,(hl)
        pop     af
        call    MK_SEL
        ld      a,b
        pop     hl
        ret

; ---- LOCAL: no network; both players on this machine -----------------------------------------------------------------
        IFDEF   LOCAL
PN_TICK:
        push    bc
        push    de
        push    hl
        push    ix
        push    iy
        ei
        call    rdLocal
        ld      (PN_P1),a
        ld      a,2                             ; player 2: joystick 2
        call    GTSTCK
        and     $0F
        push    af
        ld      a,2
        call    GTTRIG
        and     $10
        pop     bc
        or      b
        ld      hl,lclP2                        ; or what a test script put there
        or      (hl)
        ld      (PN_P2),a
        di
        ld      a,(irqCnt)
        ld      b,a
        xor     a
        ld      (irqCnt),a
        ei
        ld      a,b
        or      a
        jr      z,.none
        cp      9
        jr      c,.t
        ld      b,8
.t:     di
        push    bc
        call    sndTick
        pop     bc
        ei
        djnz    .t
.none:  pop     iy
        pop     ix
        pop     hl
        pop     de
        pop     bc
        ret
PN_IRQ: push    af
        ld      a,(irqCnt)
        inc     a
        ld      (irqCnt),a
        pop     af
        ret
irqCnt: defb    0
lclP2:  defb    0                               ; LOCAL: player 2's input from a test script
PN_P1:  defb    0
PN_P2:  defb    0
        ENDIF

stubEnd:
        OUTEND
        ASSERT  stubEnd <= PN_ORG + STUB_MAX


