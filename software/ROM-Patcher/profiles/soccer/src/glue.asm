; Konami's Soccer (RC-732): the game's side of the PLAYNET stub.
; Assembled by ../rebuild.py together with the shared engine (playnet_engine.asm, copied here from
; software/Client/src/playnet/engine). Analysis: documents/PLAYNET-PROTOCOLS.md, section 5.
;
;   sjasmplus [-DSCRIPTED] --raw=../assets/stub.bin --sym=stub.sym glue.asm

; C100h-C5FFh: TPA under every MSX-DOS set-up (even with InterNestor Lite the TPA ends at C806h) and never
; written by the game (measured over a full match). C000h-C0FFh is PLAYNET's start-up code. The stack
; (F380h down, to about F2E8h with an interrupt nested in PN_TICK) and E000h-F37Fh stay the game's.
PN_ORG:         EQU     $C100                   ; netplay.stub.load
PN_TRANSPORT:   EQU     $C500                   ; netplay.transport_area.address
STUB_MAX:       EQU     1024                    ; netplay.stub.max

G_INPUT_BYTES:  EQU     1                       ; joystick 1 / cursor keys + space, one byte
G_READ_LOCAL:   EQU     $48B9                   ; lee_el_mando_1: player 1's reader
G_SOUND_TICK:   EQU     $4F25                   ; tic_del_sonido
G_CHECK_ADDR:   EQU     $E100                   ; players and ball
G_CHECK_LEN:    EQU     $0200

FRAME:          EQU     $E003                   ; the game's frame counter

        INCLUDE "playnet_engine.asm"

; ---- entries the patches call --------------------------------------------------------------
; lee_los_mandos (4896h) reads player 1 then player 2 once per frame; two more reads happen
; later in the same frame (4564h, 4569h). The first read is the TICK site.
pad1t:  call    PN_TICK                         ; patched over call 48B9h at 4897h
        ld      a,(PN_P1)
        ret
pad1c:  ld      a,(PN_P1)                       ; at 4565h
        ret
pad2c:  ld      a,(PN_P2)                       ; at 456Ah and 48ADh
        ret
; the two coin flips read the R register: derived from the frame counter instead
rng1:   ld      a,(FRAME)                       ; replaces ld a,r : rra at B006h
        rra
        ret
rng2:   ld      a,(FRAME)                       ; replaces ld a,r : and 6 at B028h
        and     6
        ret
stubEnd:
        ASSERT  stubEnd <= PN_ORG + STUB_MAX
        ASSERT  PN_ORG + STUB_MAX <= PN_TRANSPORT
