; Capcom's 1942 (ASCII, MSX, 128 KB ASCII8 MegaROM): the game's side of the PLAYNET stub, turn based.
; Assembled by ../rebuild.py together with the shared engine (playnet_engine.asm) and the 8 KB-bank mapper
; host (mapper_k8.asm), both copied here from software/Client/src/playnet/engine.
; Analysis and design: documents/1942-DESIGN.md.
;
;   sjasmplus [-DSCRIPTED] --raw=../assets/stub.bin --sym=stub.sym glue.asm
;
; 1942's two-player mode is turn based: one ship, and when it is shot down the other player takes the next
; life. Both machines run the whole game; the input that reaches it is the active player's. The game keeps
; who is active in EFA0h: bit 7 = two players, bit 0 = the first player's turn (81h, 80h = the second's).
; The game polls its own inputs in one routine (6D09h, the keyboard text entry is 6DAAh): every call of it
; is a TICK.

; The game owns C000h-DD5Fh (the stage map, built by 71A8h), E000h-E016h, EA00h-F37Fh. Free: DD60h-DFFFh and
; E017h-E9FFh. The transport comes first; the stub follows the game's variables at E018h and the pair map
; (1 KB, 256-aligned) takes the end of the free area.
PN_TRANSPORT:   EQU     $DD60                   ; netplay.transport_area.address
PN_ORG:         EQU     $E018                   ; netplay.stub.load
STUB_MAX:       EQU     $E600-$E018             ; netplay.stub.max

G_INPUT_BYTES:  EQU     2                       ; byte 0: joystick and triggers (6D09h), byte 1: text entry key (6DAAh)
G_READ_LOCAL:   EQU     rdLocal
G_SOUND_TICK:   EQU     0                       ; the game plays its sound from its main loop, not from an interrupt
G_CHECK_ADDR:   EQU     $ED00                   ; the player blocks and what follows
G_CHECK_LEN:    EQU     $0200

MK_BANKS:       EQU     16                      ; 128 KB of 8 KB banks
MK_P1_MAX:      EQU     2                       ; page 1 is always (0,1) (the game writes the W2 and W3 registers only); the loader wants a spare entry
MK_P2_MAX:      EQU     24
MK_MAP:         EQU     $E600                   ; the bank engine's pair map, E600h-E9FFh

GAME_JOY:       EQU     $6D09                   ; the game's input reader: ED10h = direction, triggers, STOP
GAME_KEY:       EQU     $6DAA                   ; the game's text entry reader: ED10h = the key pressed
INPUT:          EQU     $ED10                   ; where the game leaves what it read
TURN:           EQU     $EFA0                   ; bit 7: two players. bit 0: the first player's turn.
H_KEYI:         EQU     $FD9A

        INCLUDE "playnet_engine.asm"
        INCLUDE "mapper_k8.asm"

; ---- inputs ------------------------------------------------------------------------------------------
; Local input, 2 bytes at HL: what the game's own readers leave in ED10h (6D77h, the secret key combination, is
; patched out of 6D09h), the second one only for the text entry.
rdLocal:
        push    hl
        call    GAME_JOY
        ld      a,(INPUT)
        ld      b,a
        call    GAME_KEY
        ld      a,(INPUT)
        pop     hl
        ld      (hl),b
        inc     hl
        ld      (hl),a
        ret

; HL = the active player's input: the second player's only while two players play and it is their turn
active: ld      a,(TURN)
        and     $81
        cp      $80
        ld      hl,PN_P1
        ret     nz
        ld      hl,PN_P2
        ret

; Replacements for call 6D09h. The title menu (4468h) is the inviter's; the game over wait (4507h) is anyone's; the
; frame, the pause (43E2h, 43ECh) and everything else are the active player's.
inP1:   call    PN_TICK
        ld      a,(PN_P1)
        jr      setIn
inAny:  call    PN_TICK
        ld      a,(PN_P1)
        ld      hl,PN_P2
        or      (hl)
        jr      setIn
inAct:  call    PN_TICK
        call    active
        ld      a,(hl)
setIn:  ld      (INPUT),a
        ret

; Replacement for call 6DAAh (the hi-score name): the active player's key
keyAct: call    PN_TICK
        call    active
        inc     hl
        ld      a,(hl)
        ld      (INPUT),a
        ret

; ---- INIT: the same RAM on both machines, and the interrupt hook ----------------------------------------------
; The BIOS cleared the RAM of a cartridge game's machine; under MSX-DOS it holds whatever it held. At 4014h, in place
; of the game's four bank-register writes (the loader has mapped the start banks): SP = F380h as the game sets it at 4039h,
; the game's RAM cleared, and H.KEYI pointing at the transport's XIRQ (the transport counts interrupts there; the game
; has no handler: XIRQ ends at a RET).
initGame:
        pop     de                              ; the return address: MSX-DOS's stack is inside C000h-DD5Fh
        ld      sp,$F380
        ld      hl,$C000
        ld      bc,$1D60
        call    zero
        ld      hl,$E000
        ld      bc,$0018
        call    zero
        ld      hl,$EA00
        ld      bc,$0900                        ; EA00h-F2FFh: the stack (below F380h) is never read
        call    zero
        ld      a,$C3
        ld      (H_KEYI),a
        ld      hl,PN_TRANSPORT+6
        ld      (H_KEYI+1),hl
        ex      de,hl
        jp      (hl)
zero:   ld      e,l
        ld      d,h
        inc     de
        dec     bc
        ld      (hl),0
        ldir
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

rRra:   call    rnd                             ; ld a,r / rra
        rra
        ret
rAnd7F: call    rnd                             ; ld a,r / and 7Fh
        and     $7F
        ret
rAnd0C: call    rnd
        and     $0C
        ret
rAnd3F: call    rnd
        and     $3F
        ret
rAnd0F: call    rnd
        and     $0F
        ret

stubEnd:
        ASSERT  stubEnd <= PN_ORG + STUB_MAX
        ASSERT  PN_TRANSPORT + 512 <= $E000 && PN_ORG + STUB_MAX <= MK_MAP && MK_MAP + 1024 <= $EA00
