; Konami's Ping Pong (1985): the game's side of the PLAYNET stub.
; Assembled by ../rebuild.py together with the shared engine (playnet_engine.asm, copied here from
; software/Client/src/playnet/engine). Analysis: documents/PINGPONG-NETPLAY.md.
;
;   sjasmplus [-DTESTPADS] --raw=../assets/stub.bin --sym=stub.sym glue.asm

; C100h-C5FFh: TPA under every MSX-DOS set-up and never written by the game (it writes nothing outside
; E000h-E3FFh, measured over 2 x 5 minutes of random play in 1 and 2 player mode). C000h-C0FFh is PLAYNET's
; start-up code. The stack (E400h down, to E3BAh at the sample points) stays the game's.
PN_ORG:         EQU     $C100                   ; netplay.stub.load
PN_TRANSPORT:   EQU     $C500                   ; netplay.transport_area.address
STUB_MAX:       EQU     1024                    ; netplay.stub.max

G_INPUT_BYTES:  EQU     1                       ; joystick 1 / cursor keys + space, one byte
G_READ_LOCAL:   EQU     rdLocal
G_SOUND_TICK:   EQU     $5195                   ; the sound driver
G_CHECK_ADDR:   EQU     $E000                   ; the game's state: scene, score, ball and paddles (E1C0h-E3FFh is idle)
G_CHECK_LEN:    EQU     $0200

READ_PSG:       EQU     $4800                   ; the game's joystick 1 reader (PSG): A = bits 0-5
READ_KEY:       EQU     $4812                   ; its cursor-key + space reader: A = the same bits
FRAME_INPUT:    EQU     $47E3                   ; once per interrupt: reads both pads, then caches them in E008h-E009h, E048h-E049h

        INCLUDE "playnet_engine.asm"

; ---- entries the patches call --------------------------------------------------------------
        IFDEF   TESTPADS
; Test builds (rebuild.py --test-gpf): the local pad is pseudo-random, held 12 frames, seeded per seat, so two emulators
; with nobody at the keys really play (the engine's own SCRIPTED table is too tame: nobody ever serves or scores).
padSeed:        defw    $5A5A
padCnt:         defb    1
padVal:         defb    0
rdLocal:
        ld      a,(padCnt)
        dec     a
        jr      nz,.hold
        ld      hl,(padSeed)
        ld      d,h
        ld      e,l
        add     hl,hl
        add     hl,hl
        add     hl,de
        ld      de,$3619
        add     hl,de
        ld      (padSeed),hl
        ld      a,(pnSeat)
        or      a
        ld      a,h
        jr      z,.s0
        rrca
        rrca
        rrca
        xor     $A5
.s0:    and     $1F                             ; up, down, left, right, trigger
        ld      (padVal),a
        ld      a,12
.hold:  ld      (padCnt),a
        ld      a,(padVal)
        ret
        ELSE
; Player 1's hardware read (4800h joystick, 4812h keys), the way the game combines them at 47E6h.
rdLocal:
        call    READ_PSG
        ld      d,a
        call    READ_KEY
        or      d
        ret
        ENDIF

; TICK site: the call to 47E3h at 4033h, once per frame, in the interrupt handler under the busy flag.
; The exchange first; the game's own reader follows, with its two pads patched to the two bytes below.
tickSite:
        call    PN_TICK
        jp      FRAME_INPUT

; The pad of this frame, in place of the game's hardware reads (47E6h player 1, 4845h player 2, and the two menu
; readers at 42ABh and 43A7h, which read player 1 only).
key1:   ld      a,(PN_P1)
        ret
key2:   ld      a,(PN_P2)
        ret

; 43CDh: the title menu stores the mode (40h = 1 player, 60h = 2 players) in E002h. Online there is nobody to play
; against but the other player, so both choices are the 2 player mode.
forceTwo:
        or      $20
        ld      ($E002),a
        ret
stubEnd:
        ASSERT  stubEnd <= PN_ORG + STUB_MAX
        ASSERT  PN_ORG + STUB_MAX <= PN_TRANSPORT
