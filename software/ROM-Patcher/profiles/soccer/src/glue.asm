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
G_CATCHUP:      EQU     2                       ; the frame catch-up for the interrupts XCHG took (isrEnd)

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
; ---- the frame catch-up (the engine's PN_AGAIN) ---------------------------------------------------------------
; Every frame is one run of the H.KEYI handler, and an interrupt that comes while it runs only counts (the busy flag
; E005h): a frame that the exchange makes longer than an interrupt period costs a whole period. When an interrupt
; went by inside the exchange, taken by MSX-DOS's handler in XCHG (TCP/IP; G_CATCHUP 2), the next frame runs as soon
; as this one ends (one at most). Interrupts that the game's own work makes it miss stay dropped, as on the cartridge,
; and so do those its handler saw during PN_TICK (G_CATCHUP 1 catches those too: see the README). Only the
; pace changes, never what a frame computes.
; 4044h, in place of "ld a,0 / ld (E005h),a" (5 bytes): the busy flag cleared, or the next frame now
isrEnd: call    PN_AGAIN
        jr      nz,.again
        ld      ($E005),a                       ; A = 0, as the game clears it
        ret
.again: pop     af                              ; the return address: the frame runs again from 403Dh
        jp      $403D                           ; (ei, then the frame, the busy flag still set)
stubEnd:
        ASSERT  stubEnd <= PN_ORG + STUB_MAX
        ASSERT  PN_ORG + STUB_MAX <= PN_TRANSPORT
