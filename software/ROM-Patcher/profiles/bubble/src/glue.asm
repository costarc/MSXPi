; Taito's Bubble Bobble (MSX2, 128 KB ASCII8 MegaROM): the game's side of the PLAYNET stub, two players at once.
; Assembled by ../rebuild.py together with the shared engine (playnet_engine.asm) and the 8 KB-bank mapper
; host (mapper_k8.asm), both copied here from software/Client/src/playnet/engine.
; Analysis: ../README.md.
;
;   sjasmplus [-DSCRIPTED] --raw=../assets/stub.bin --sym=stub.sym glue.asm
;
; The game runs entirely from its H.KEYI handler (42D5h): sound, then a cooperative task scheduler (4231h), then
; 4323h, which reads both players' inputs once per interrupt (player 1: joystick 1, cursors, space...; player 2:
; joystick 2, D, G, CTRL, SHIFT). That read is the TICK: player 1 (Bub) is seat 0, the inviter; player 2 (Bob)
; is seat 1. The game's own 2P START mode then plays both dragons at once, each machine's player steering one.

; Page 3 after INIT (measured, 10 minutes of two-player play; the game clears C000h-F37Dh at INIT): the task
; stacks C000h-C94Fh (tasks 0-8, the scheduler's table has no more), game data D030h-E65Fh and EF80h-F37Fh.
; Free: C950h-D02Fh and E660h-EF7Fh. The transport and the pair map go in the first, the stub in the second.
PN_TRANSPORT:   EQU     $C950                   ; netplay.transport_area.address (512 bytes, C950h-CB4Fh)
PN_ORG:         EQU     $E660                   ; netplay.stub.load
STUB_MAX:       EQU     $EF80-$E660             ; netplay.stub.max

G_INPUT_BYTES:  EQU     1                       ; bits 0-5 as the game's readers return them, bit 6 = STOP (pause)
G_READ_LOCAL:   EQU     rdLocal
G_SOUND_TICK:   EQU     0                       ; the handler ticks its sound driver once a frame itself: deterministic
G_CHECK_ADDR:   EQU     $E100                   ; the game's variables (players, level, the random seed E10Bh)
G_CHECK_LEN:    EQU     $0200

MK_BANKS:       EQU     16                      ; 128 KB of 8 KB banks
MK_P1_MAX:      EQU     3                       ; page 1: (0,4), (0,11) and a spare (the loader wants one)
MK_P2_MAX:      EQU     22                      ; 20 pairs listed by rebuild.py, and room
MK_MAP:         EQU     $CC00                   ; the bank engine's pair map, CC00h-CFFFh

GAME_PAD:       EQU     $4353                   ; E = 8Fh / CFh: joystick 1 / 2 -> A = bits 0-5
GAME_KEY1:      EQU     $4364                   ; player 1's keys -> A
GAME_KEY2:      EQU     $43B3                   ; player 2's keys -> A
SHADOW_W2:      EQU     $E489                   ; the game's copies of the W2, W3 bank registers
SHADOW_W3:      EQU     $E48A
SNSMAT_:        EQU     $0141
GAME_BUSY:      EQU     $D032                   ; the handler's busy flag
GAME_FRAME:     EQU     $42E3                   ; the handler, after its busy check

        INCLUDE "playnet_engine.asm"
        INCLUDE "mapper_k8.asm"

; ---- inputs ------------------------------------------------------------------------------------------
; Local input: this machine's player may use either joystick port and either key set (the game's own readers),
; and STOP (row 7 bit 4) is bit 6, so a pause is seen on both machines on the same frame.
rdLocal:
        ld      e,$8F
        call    GAME_PAD
        push    af
        call    GAME_KEY1
        push    af
        ld      e,$CF
        call    GAME_PAD
        push    af
        call    GAME_KEY2
        ld      b,a
        pop     af
        or      b
        ld      b,a
        pop     af
        or      b
        ld      b,a
        pop     af
        or      b
        and     $3F
        ld      b,a
        ld      a,7
        call    SNSMAT_
        and     $10
        ld      a,b
        ret     nz
        or      $40
        ret

; At 432Fh, in place of "ld e,8Fh / call 4353h / ld c,a / call 4364h / or c": the exchange, then player 1's input
inP1:   ld      a,(irqCnt)                      ; the engine adds here the interrupts MSX-DOS took during XCHG (TCP/IP)
        ld      (irqAt),a
        ld      a,1
        ld      (inTick),a
        call    PN_TICK
        xor     a
        ld      (inTick),a
        ld      a,(irqAt)
        ld      hl,irqCnt
        cp      (hl)
        jr      z,.p1
        ld      a,1                             ; an interrupt went by during the exchange: catch it up
        ld      (pend),a
.p1:    ld      a,(PN_P1)
        and     $3F
        ret

; ---- catching up the frames the network took ---------------------------------------------------------------
; Every frame is one run of the H.KEYI handler, and an interrupt that comes while it runs is dropped (the busy
; flag D032h): a frame that the exchange makes longer than an interrupt period costs a whole period. The cartridge
; drops interrupts too, when its own work is long, and that stays as it was. But an interrupt that came during
; PN_TICK (in the game's page 3, or taken by MSX-DOS's handler inside XCHG on TCP/IP) is not dropped: the next
; frame runs as soon as this one ends (one at most). Only the pace changes, never what a frame computes.
; 42DDh, in place of "ld a,(D032h) / and a / jr nz,431Eh" (431Eh: ret)
busyChk:
        ld      a,(GAME_BUSY)
        and     a
        ret     z                               ; not busy: the handler goes on
        ld      a,(inTick)
        or      a
        jr      z,.drop
        ld      (pend),a
.drop:  pop     af                              ; out of the handler, as its own "ret" at 431Eh
        ret
; 431Ah, in place of "xor a / ld (D032h),a" (then 431Eh: ret)
isrEnd: di
        ld      a,(pend)
        or      a
        jr      z,.end
        xor     a
        ld      (pend),a
        jp      GAME_FRAME                      ; the next frame now (D032h still set)
.end:   ld      (GAME_BUSY),a
        ret
inTick: defb    0
pend:   defb    0
irqAt:  defb    0
; At 4342h, in place of the same for player 2 (E = CFh, 43B3h)
inP2:   ld      a,(PN_P2)
        and     $3F
        ret

; Bank 13 (B084h): the pause. "ld a,7 / call SNSMAT / bit 4,a": STOP of either player, from this frame's inputs.
; SNSMAT changes AF and C only; this changes AF.
stopKey:
        push    hl
        ld      hl,PN_P1
        ld      a,(PN_P2)
        or      (hl)
        pop     hl
        and     $40
        ld      a,$FF
        ret     z
        ld      a,$EF
        ret

; ---- INIT ------------------------------------------------------------------------------------------
; At 4079h, in place of the game's "call 6825h" with HL = C000h, BC = 337Eh (it clears C000h-F37Dh): the same,
; around the transport, the pair map and the stub. 6825h leaves A = D = 0, BC = 0, HL = F37Eh.
; No CALL in here: the stack is at F37Eh (this routine's return address), and the last range ends at F37Dh.
        MACRO   ZERO from, len
        ld      hl,from
        ld      de,from+1
        ld      bc,len-1
        ld      (hl),0
        ldir
        ENDM
clrGame:
        ZERO    $C000, PN_TRANSPORT-$C000
        ZERO    PN_TRANSPORT+512, MK_MAP-PN_TRANSPORT-512
        ZERO    MK_MAP+1024, PN_ORG-MK_MAP-1024
        ZERO    stubEnd, $F37E-stubEnd          ; from the stub's end: the game reads EF7Eh-EF7Fh (a table it never
                                                ; writes; 0 on the cartridge), and MSX-DOS left its own bytes there
        ld      hl,$F37E
        ld      d,b
        ld      a,b
        ret

; ---- the interrupt handler's own bank switches -----------------------------------------------------------
; 42E8h: "ld a,0Eh / ld (77F8h),a / ld a,0Fh / ld (7FF8h),a" (the sound driver's banks): one switch of page 2
sndMap: push    de
        ld      de,$0E0F
        call    MK_W23
        pop     de
        ld      a,$0F
        ret
; 42F9h: "ld a,(E489h) / ld (77F8h),a / ld a,(E48Ah) / ld (7FF8h),a": back to the game's banks in one switch
gameMap:
        push    de
        ld      a,(SHADOW_W2)
        ld      d,a
        ld      a,(SHADOW_W3)
        ld      e,a
        call    MK_W23
        pop     de
        ret

; ---- the game's bank switches -----------------------------------------------------------------------------
; The game writes the bank registers from 163 places (ld (6FF8h/77F8h/7FF8h),a). As GPF patches they would make
; the file too big for PLAYNET's 3 KB buffer, so the stub applies them itself: at INIT (405Ah, in place of the
; game's first call, before its first bank switch) it maps every segment the loader built into page 2 and turns
; each site into CALL MK_W1/MK_W2/MK_W3. Segments built later are copied from the homes, which are patched by
; then. The loader has checked the ROM's CRC-32, so the offsets are right; a site is patched only if it holds
; "ld (nn),a" with nn = xxF8h (the build checks every site against the dump: rebuild.py --rom).
; sites.asm (written by rebuild.py): per bank, "defb bank, count" and count words: register (1-3) << 13 | offset;
; FFh at the end. Interrupts are off (INIT, 4054h).
stubInit:
        ld      hl,mkTab1
        ld      a,(mkPg1)
        call    sTab
        ld      hl,mkTab2
        ld      a,(mkPg2)
        call    sTab
        ld      a,(MK_SEG2)
        out     ($FE),a
        jp      $4184                           ; the game's own call
; HL = a table, A = its entries in use (spares hold the pair FFh, FFh)
sTab:   or      a
        ret     z
        ld      b,a
.l:     push    bc
        push    hl
        ld      d,(hl)                          ; low bank
        inc     hl
        ld      e,(hl)                          ; high bank
        inc     hl
        ld      a,d
        cp      MK_BANKS
        jr      nc,.n
        ld      a,e
        cp      MK_BANKS
        jr      nc,.n
        ld      a,(hl)                          ; the segment
        out     ($FE),a
        ld      a,d
        ld      c,$80
        push    de
        call    sBank
        pop     de
        ld      a,e
        ld      c,$A0
        call    sBank
.n:     pop     hl
        ld      bc,4
        add     hl,bc
        pop     bc
        djnz    .l
        ret
; A = bank, C = the high byte of the window it is mapped at (80h, A0h): patch its sites
sBank:  ld      b,a
        ld      hl,siteTab
.g:     ld      a,(hl)
        cp      $FF
        ret     z
        inc     hl
        cp      b
        ld      a,(hl)                          ; count
        inc     hl
        jr      z,.f
        add     a,a
        ld      e,a
        ld      d,0
        add     hl,de
        jr      .g
.f:     ld      b,a
.s:     ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    hl
        ld      a,d
        and     $1F
        add     a,c
        ld      h,a
        ld      l,e                             ; HL = the site
        ld      a,(hl)
        cp      $32
        jr      nz,.k
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      $F8
        jr      nz,.k
        ld      a,d                             ; the register, 1-3: its entry
        rlca
        rlca
        rlca
        and     3
        add     a,a
        ld      e,a
        ld      d,0
        push    hl
        ld      hl,sTarget-2
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        pop     hl
        ld      (hl),$CD
        inc     hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
.k:     pop     hl
        djnz    .s
        ret
sTarget:
        defw    MK_W1, MK_W2, MK_W3
siteTab:
        INCLUDE "sites.asm"

; ---- ld a,r ------------------------------------------------------------------------------------------
; R differs between machines. Each "ld a,r" and the instruction after it becomes a call to one of these:
; the same instruction on a deterministic value (a 16-bit LFSR, bit 7 clear as R's would be). Flags as the
; original's second instruction leaves them.
rnd:    push    hl                              ; also "ld a,r / and 7Fh"
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

rAnd01: call    rnd
        and     $01
        ret
rAnd03: call    rnd
        and     $03
        ret
rAnd07: call    rnd
        and     $07
        ret
rAnd0F: call    rnd
        and     $0F
        ret
rAnd10: call    rnd
        and     $10
        ret
rAnd3F: call    rnd
        and     $3F
        ret
rXorH:  call    rnd
        xor     h
        ret
rXorL:  call    rnd
        xor     l
        ret
rAddB:  call    rnd
        add     a,b
        ret
rAddC:  call    rnd
        add     a,c
        ret

stubEnd:
        ASSERT  stubEnd <= PN_ORG + STUB_MAX
        ASSERT  PN_TRANSPORT + 512 <= MK_MAP && MK_MAP + 1024 <= $D030 && PN_TRANSPORT >= $C950
