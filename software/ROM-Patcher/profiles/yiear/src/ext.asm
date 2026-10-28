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

; extension RAM (E480h-E4FFh: inside game_ram, never touched by the game). Only what is initialised before it is read:
; the menu's own, and the mode, the current player and Turn's blocks live in the stub (tMode, tCur, tOut, tBlk).
MODE:           EQU     tMode                   ; 0 Single, 1 Turn, 2 Versus
CURSOR:         EQU     $E481
PREV:           EQU     $E482                   ; player 1's input of the last frame
MODES:          EQU     3
TURN_N:         EQU     23                      ; the per-player block, E049h-E05Fh (as the stub's)
BLOCK:          EQU     $E049
REST:           EQU     $E050
OPPONENT:       EQU     $E054
DUMMY:          EQU     $E483                   ; where Versus sends the game's REST + 1
HOLD:           EQU     200                     ; frames the winner is shown (about 3 s)
LIVES2:         EQU     3                       ; player 2's lives in Versus
LIVES_AT:       EQU     2 + 8                   ; the digit in STR_LIVES (the address word, then "P2 REST ")

; 409Ch: call 4071h -> call dispatch. A = the state. States 0-8 go on to the game's dispatcher with the stack untouched.
dispatch:
        cp      9
        jp      z,.menu
        cp      5                               ; a fight in Turn or Versus: the HUD, once in a while
        jp      z,.fight
        cp      7                               ; the game-over screen of a Versus match: who won, held for a while
        jp      nz,OLD_DISPATCH
        push    af
        ld      a,(MODE)
        cp      2
        jr      nz,.old
        ld      a,(tWin)
        or      a
        jr      z,.old
        ld      de,STR_WIN1
        cp      2
        jr      c,.w1                           ; 1 (tWin is set before the game-over screen is reached)
        ld      de,STR_WIN2
.w1:    ld      a,(tHold)                       ; state 7 lasts 5 frames: stay here for HOLD frames, then the game goes on
        or      a
        jr      nz,.w2
        ld      a,HOLD
.w2:    dec     a
        ld      (tHold),a
        jr      nz,.w3
        ld      (tWin),a                        ; over: no winner any more, so the 5 frames the game has left do not start it again
        jr      .old
.w3:
        ld      a,(FRAME)
        and     15
        jr      nz,.wend
        push    bc
        push    de
        push    hl
        call    PRINT
        pop     hl
        pop     de
        pop     bc
.wend:  pop     af
        pop     hl                              ; the state's own routine is not run: back to the caller of the dispatcher
        ret
.say:   ld      a,(FRAME)
        and     15
        jr      nz,.old
        push    bc
        push    de
        push    hl
        call    PRINT
        pop     hl
        pop     de
        pop     bc
.old:   pop     af
        jp      OLD_DISPATCH
.fight: push    af
        ld      a,(MODE)
        or      a
        jr      z,.old
        ld      a,(FRAME)
        and     15
        jr      nz,.old
        push    bc
        push    de
        push    hl
        ld      a,(MODE)
        cp      2
        jr      z,.vsh
        ld      a,(FRAME)                       ; Turn, row 2 (the playfield below it is redrawn every frame): whose turn it is, and
        and     16                              ; every other 16 frames who is out (the game goes on for the other player)
        jr      z,.hud
        ld      de,STR_OUT1
        ld      a,(tOut)
        or      a
        jr      nz,.t1
        ld      de,STR_OUT2
        ld      a,(tOut+1)
        or      a
        jr      nz,.t1
.hud:   ld      de,STR_HUD1
        ld      a,(tCur)
        or      a
        jr      z,.t1
        ld      de,STR_HUD2
.t1:    call    PRINT
        jr      .fin
.vsh:   ld      a,(tLives2)                     ; Versus: player 2's lives
        add     a,$10
        ld      (STR_LIVES + LIVES_AT),a
        ld      de,STR_LIVES
        call    PRINT
.fin:   pop     hl
        pop     de
        pop     bc
        jr      .old
.menu:
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
        xor     a
        ld      (tCur),a
        ld      (tWin),a
        ld      de,STR_TITLE                    ; the menu goes; "PLAY START" follows as after the title's start (45A7h)
        call    ERASE
        ld      de,STR_SINGLE
        call    ERASE
        ld      de,STR_TURN
        call    ERASE
        ld      de,STR_VERSUS
        call    ERASE
        ld      a,(MODE)
        cp      1
        jr      nz,.st3
        ld      de,STR_PS1                      ; Turn: whose game it is, above "PLAY START"
        call    PRINT
.st3:   ld      hl,3
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

; 4132h: call 42A3h -> call newGame. The new game as the game sets it up; in Turn both players start from that block.
newGame:
        call    $42A3
        ld      a,(MODE)
        cp      2
        jr      nz,.nv
        ld      a,LIVES2
        ld      (tLives2),a                     ; Versus: player 2's lives (player 1's are the game's REST)
        ret
.nv:    cp      1
        ret     nz
        xor     a
        ld      (tCur),a
        ld      (tOut),a
        ld      (tOut+1),a
        ld      hl,BLOCK
        ld      de,tBlk
        ld      bc,TURN_N
        ldir
        ld      hl,BLOCK
        ld      bc,TURN_N
        ldir                                    ; DE went on to the second player's copy
        ret

; 41DCh: ld a,(E050h) -> call lifeLost. The game then ends if A = 0, else sets the stage up again (state 4).
; In Turn the dying player's block is saved; a player with no REST left is out; the other player, when not out,
; takes the turn (their block is loaded and state 4 sets up their stage). A = 0 only when both are out.
lifeLost:
        ld      a,(MODE)
        cp      1
        jr      z,.turn
        ld      a,(REST)
        or      a
        ret     nz
        ld      a,(MODE)                        ; no REST left: in Versus player 2 wins (unless player 1 won already)
        cp      2
        jr      nz,.zero
        ld      a,(tWin)
        or      a
        jr      nz,.zero
        ld      a,2
        ld      (tWin),a
.zero:  xor     a
        ret
.turn:  ld      a,(tCur)
        call    blockOf
        ex      de,hl
        ld      hl,BLOCK
        ld      bc,TURN_N
        ldir                                    ; save
        ld      a,(REST)
        or      a
        jr      nz,.next
        ld      hl,tOut                         ; no REST left: out
        ld      a,(tCur)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (hl),1
.next:  ld      a,(tCur)
        xor     1
        ld      e,a
        ld      d,0
        ld      hl,tOut
        add     hl,de
        ld      a,(hl)
        or      a
        jr      nz,.stay                        ; the other is out: this player goes on, or it is over
        ld      a,e
        ld      (tCur),a
        call    blockOf
        ld      de,BLOCK
        ld      bc,TURN_N
        ldir                                    ; load the other player's block
        ld      a,1
        ret
.stay:  ld      a,(tCur)                        ; still this player's turn: out (A = 0, game over) or not (A = 1)
        ld      e,a
        ld      d,0
        ld      hl,tOut
        add     hl,de
        ld      a,(hl)
        xor     1
        ret

; ---- Versus (documents/YIEAR-DESIGN.md 5.3) -----------------------------------------------------------------------
; All five AI routines share one decision point, 7335h: they run the opponent's current action while E16Bh is not zero
; (each has its own animation script) and jump to 7335h when it is. 7335h calls 5476h (facing and so on) and then decides at
; random. 7338h is patched to vsDecide, so the opponent's own executors, animations and hit boxes all stay the game's, and
; only the choice is player 2's. The starters are the AI's own: 7454h / 7458h / 7450h start action 4 / 5 / 6 (E16Ah, and
; E16Bh from the level's table), 74E7h walks one step (C = 0 right, 1 left) and draws.
WALK_MASK:      EQU     7                       ; a step every 8 frames: the AI ticks on even frames, a step is 8 pixels,
                                                ; Oolong walks one pixel per frame
FACING:         EQU     $E185
ANIM:           EQU     $E184

; 7338h: ld a,(E181h) -> jp vsDecide
vsDecide:
        ld      a,(MODE)
        cp      2
        jr      z,.vs
        ld      a,($E181)
        jp      $733B
.vs:    ld      a,(PN_P2)
        ld      b,a
        bit     5,b                             ; the second button: the opponent's jump attack
        jr      nz,.jump
        bit     4,b                             ; trigger / space: an attack, by the direction held
        jr      z,.nobtn
        bit     0,b
        jp      nz,$7458                        ; up + trigger
        bit     1,b
        jp      nz,$7450                        ; down + trigger
        jp      $7454
.nobtn: bit     0,b                             ; up alone: jump
        jr      z,.walk
.jump:  ld      a,(OPPONENT)
        ld      e,a
        ld      d,0
        ld      hl,JUMPS
        add     hl,de
        ld      a,(hl)
        jp      $7429                           ; start that action (a pose script with the airborne flag)
.walk:  ld      a,(FRAME)
        and     WALK_MASK
        jr      nz,.stand
        ld      c,0                             ; right
        bit     3,b
        jp      nz,$74E7
        inc     c                               ; left
        bit     2,b
        jp      nz,$74E7
.stand: ld      a,(FACING)                      ; stand still: animation 2 (facing left) or 3, as 74E7h picks it
        and     a
        ld      a,2
        jr      nz,.s
        inc     a
.s:     ld      (ANIM),a
        jp      $5522

; 4248h: ld a,(E054h) -> call bonus. The bonus stages follow opponents 1 and 4; Versus has none.
bonus:  ld      a,(MODE)
        cp      2
        ld      a,(OPPONENT)
        ret     nz
        xor     a
        ret

; 423Eh: ld hl,E050h (then inc (hl): REST + 1) -> call vsBeaten. The opponent is beaten. In Versus player 2 loses a life and the
; game's REST + 1 goes to a dummy byte instead of player 1; when player 2 has no life left, player 1 wins: through the game's own
; game-over path (state 6 with no REST), which keeps the high score and the title.
vsBeaten:
        ld      hl,REST
        ld      a,(MODE)
        cp      2
        ret     nz
        ld      hl,DUMMY
        ld      a,(tLives2)
        dec     a
        ld      (tLives2),a
        ret     nz
        pop     hl                              ; no life left: the routine's own ending is not run
        ld      a,1
        ld      (tWin),a
        xor     a
        ld      (REST),a
        ld      (SUBSTATE),a
        ld      ($E00B),a
        ld      a,6
        ld      (STATE),a
        ret

; the airborne action of each opponent (the pose script with the 10h flag, found in each opponent's action table)
JUMPS:  defb    3, 3, 4, 4, 0

; HL = player A's saved block
blockOf:
        ld      hl,tBlk
        or      a
        ret     z
        ld      de,TURN_N
        add     hl,de
        ret
extEnd:
        ASSERT  extEnd <= $C000
