; Konami's Yie Ar Kung-Fu (RC-725): the game's side of the PLAYNET stub, Single mode.
; Assembled by ../rebuild.py together with the shared engine (playnet_engine.asm, copied here from
; software/Client/src/playnet/engine). Analysis: documents/YIEAR-DESIGN.md, section 3.
;
;   sjasmplus [-DSCRIPTED] --raw=../assets/stub.bin --sym=stub.sym glue.asm

; C100h-C5FFh: TPA under every MSX-DOS set-up and never written by the game (it writes nothing outside
; E000h-E401h, measured over 15 minutes through all five opponents, four levels and the bonus stages).
; C000h-C0FFh is PLAYNET's start-up code. The stack (E400h down, to E3B8h at the sample points) stays the game's.
PN_ORG:         EQU     $C100                   ; netplay.stub.load
PN_TRANSPORT:   EQU     $C500                   ; netplay.transport_area.address
STUB_MAX:       EQU     1024                    ; netplay.stub.max

G_INPUT_BYTES:  EQU     1                       ; joystick 1 / cursor keys + space, one byte
G_READ_LOCAL:   EQU     rdLocal
G_SOUND_TICK:   EQU     $7C5C                   ; the sound driver
G_CHECK_ADDR:   EQU     $E100                   ; Oolong, the opponent and the projectiles
G_CHECK_LEN:    EQU     $0200

READ_JOY:       EQU     $4510                   ; the game's joystick 1 reader: A = bits 0-5
READ_KEY:       EQU     $453F                   ; the game's keyboard reader: A = the same bits
DEMO_EDGE:      EQU     $452B                   ; the rest of the main reader: the demo override, then the edge logic

        INCLUDE "playnet_engine.asm"

; ---- entries the patches call --------------------------------------------------------------
; The first half of the main reader (4522h): the hardware, joystick 1 or the keyboard, and nothing written
; to the game's RAM (E009h/E00Ah and the demo override come after, at 452Bh, on the cached input).
rdLocal:
        call    READ_JOY
        push    af
        call    READ_KEY
        pop     hl
        or      h
        ret

; TICK site: call 4522h at 4053h, once per frame, in the interrupt handler under the busy flag.
; The exchange, then the main reader's second half on the byte of the player who plays now: player 1's, except
; in Turn mode while player 2 has the turn (tCur = 1).
tickSite: call  PN_TICK
        ld      a,(tCur)
        or      a
        ld      a,(PN_P1)
        jp      z,DEMO_EDGE
        ld      a,(PN_P2)
        jp      DEMO_EDGE

; ---- the extension's state (documents/YIEAR-DESIGN.md 5.2) ------------------------------------------------
; Here and not in the game's RAM because the loader copies these initialised bytes: INIT clears only E000h-E3FFh, so
; a RAM byte of the extension would start with whatever each machine had there, and the tick above reads tCur.
TURN_N:         EQU     23                      ; E049h-E05Fh: score, REST, stage, opponent, level, counters
tMode:          defb    0                       ; 0 Single, 1 Turn, 2 Versus
tCur:           defb    0                       ; the player who plays now (Turn)
tOut:           defb    0, 0                    ; Turn: the player has no REST left
tBlk:           defs    TURN_N * 2              ; Turn: each player's saved block

; the second reader (4583h: title, demo and game-over screens) in place of its two hardware reads
key1:   ld      a,(PN_P1)
        ret
stubEnd:
        ASSERT  stubEnd <= PN_ORG + STUB_MAX
        ASSERT  PN_ORG + STUB_MAX <= PN_TRANSPORT
