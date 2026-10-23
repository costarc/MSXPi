; Konami's Yie Ar Kung-Fu: the extension, in page 2 (A000h). Design: documents/YIEAR-DESIGN.md, section 5.
; Assembled by ../rebuild.py after the stub: stub_syms.inc (the stub's PN_P1) and strings.inc (the menu texts in the
; game's own encoding) are written by it.
;
;   sjasmplus --raw=../assets/ext.bin ext.asm
;
; Runs only from the game's frame logic (the state dispatch), never from PN_TICK or the interrupt's busy path.
; State 9, the play-mode screen, sits between the title ("PUSH SPACE KEY") and "PLAY START". Only player 1 chooses (D2).

        ORG     $A000

        INCLUDE "stub_syms.inc"                 ; PN_P1
        INCLUDE "strings.inc"                   ; STR_PUSH, STR_TITLE, STR_SINGLE, STR_TURN, STR_VERSUS

STATE:          EQU     $E000                   ; the game's state, then sub-state (E001h)
SUBSTATE:       EQU     $E001
FRAME:          EQU     $E003
OLD_DISPATCH:   EQU     $4071                   ; the game's state dispatcher (the table follows its call)
PRINT:          EQU     $449E                   ; DE = string: draw
ERASE:          EQU     $44B5                   ; DE = string: erase

; extension RAM (E480h-E4FFh: inside game_ram, never touched by the game)
MODE:           EQU     $E480                   ; 0 Single, 1 Turn, 2 Versus
CURSOR:         EQU     $E481
PREV:           EQU     $E482                   ; player 1's input of the last frame
MODES:          EQU     3

; 409Ch: call 4071h -> call dispatch. A = the state. States 0-8 go on to the game's dispatcher with the stack untouched.
dispatch:
        cp      9
        jp      nz,OLD_DISPATCH
        pop     hl                              ; the table address the call pushed
menu:   ld      a,(SUBSTATE)
        or      a
        jr      nz,.loop
        ld      de,STR_PUSH                     ; sub-state 0: the title's text goes, the menu's comes
        call    ERASE
        ld      de,STR_TITLE
        call    PRINT
        ld      a,(PN_P1)                       ; the press that got us here is still held: not a new press
        ld      (PREV),a
        xor     a
        ld      (CURSOR),a
        ld      (MODE),a
        ld      hl,SUBSTATE
        inc     (hl)
        ret
.loop:  ld      a,(PN_P1)
        ld      b,a
        ld      a,(PREV)
        cpl
        and     b
        ld      c,a                             ; C = newly pressed
        ld      a,b
        ld      (PREV),a
        ld      a,(CURSOR)
        bit     0,c                             ; up
        jr      z,.nu
        or      a
        jr      nz,.u1
        ld      a,MODES
.u1:    dec     a
.nu:    bit     1,c                             ; down
        jr      z,.nd
        inc     a
        cp      MODES
        jr      c,.nd
        xor     a
.nd:    ld      (CURSOR),a
        bit     4,c                             ; trigger or space: confirmed
        jr      nz,.go
        ld      b,0                             ; draw the three entries, the chosen one blinking
        ld      de,STR_SINGLE
        call    item
        ld      b,1
        ld      de,STR_TURN
        call    item
        ld      b,2
        ld      de,STR_VERSUS
        jr      item
.go:    ld      a,(CURSOR)
        ld      (MODE),a
        ld      de,STR_TITLE                    ; the menu goes; "PLAY START" follows as after the title's start (45A7h)
        call    ERASE
        ld      de,STR_SINGLE
        call    ERASE
        ld      de,STR_TURN
        call    ERASE
        ld      de,STR_VERSUS
        call    ERASE
        ld      hl,3
        ld      (STATE),hl                      ; state 3, sub-state 0
        ret

; B = the entry's number, DE = its string: drawn, except while it is the chosen one and the blink is off
item:   ld      a,(CURSOR)
        cp      b
        jr      nz,.draw
        ld      a,(FRAME)
        and     8
        jp      z,ERASE
.draw:  jp      PRINT
extEnd:
        ASSERT  extEnd <= $C000
