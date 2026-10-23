; PLAYNET mapper-RAM host for 8 KB-bank MegaROMs (Konami SCC, Konami, ASCII8): the bank engine (host ABI 1).
; Design: documents/SALAMANDER-DESIGN.md, section 5. First user: Salamander (profiles/salamander).
;
; A game's glue defines MK_BANKS (banks in the ROM, a power of two), MK_P1_MAX and MK_P2_MAX (table entries
; for page 1 and page 2), then INCLUDEs this file after playnet_engine.asm. The package patches every
; bank-register write of the game (ld (nn),a) into CALL MK_W0..MK_W3, one entry per 8 KB window:
; W0 4000h-5FFFh, W1 6000h-7FFFh, W2 8000h-9FFFh, W3 A000h-BFFFh.
;
; The MSX mapper switches 16 KB, the cartridge 8 KB. So each page is one mapper segment holding the PAIR of
; banks of its two windows. The loader builds the pairs the package lists, fills MK_BLOCK and maps the start
; pairs. A switch to a pair in the table is one OUT. Any other pair is built into a spare entry (a clock
; approximation of least recently used): two 8 KB copies from the banks' homes, about 100 ms with interrupts
; off. The first `pinned` entries of each table are never replaced, and every bank has its home in one of
; them, so a bank can always be copied.
;
; The segments only ever hold ROM bytes, so the cache cannot change what the game computes: two machines with
; different amounts of memory run the same game, the smaller one with more pauses.
;
; MK_BLOCK (filled by the loader; the build zeroes it):
;   +0  version (1)     +1  bank mask (MK_BANKS-1)    +2  entries of table 1, of table 2 (MK_P1_MAX, MK_P2_MAX)
;   +4  bank in W0..W3  +8  segment in page 1, page 2
;   +10 home of each bank: segment, half (0 = low window, 1 = high window), 2 bytes a bank
;   then for page 1 and page 2: entries in use, pinned entries, clock hand (3 bytes each)
;   then the tables: MK_P1_MAX, then MK_P2_MAX entries of (low bank, high bank, segment, referenced)
; The TCP/IP transport puts page 2 back from MK_SEG2 after each exchange (it maps the network engine there).

        ASSERT  MK_BANKS >= 2 && MK_BANKS <= 64 && (MK_BANKS & (MK_BANKS-1)) == 0
        ASSERT  MK_P1_MAX >= 1 && MK_P2_MAX >= 1 && MK_P1_MAX + MK_P2_MAX <= 63

MK_BLOCK:
mkVer:          defb    1
mkMask:         defb    MK_BANKS-1
                defb    MK_P1_MAX, MK_P2_MAX
mkCur:          defs    4
mkSeg:          defs    2
MK_SEG2:        EQU     mkSeg+1
mkHome:         defs    2*MK_BANKS
mkPg1:          defs    3
mkPg2:          defs    3
mkTab1:         defs    4*MK_P1_MAX
mkTab2:         defs    4*MK_P2_MAX
MK_BLOCK_END:

; ---- MK_W0..MK_W3: the patched ld (nn),a. A = the value written. Preserves every register and the flags.
MK_W0:  push    hl
        ld      l,0
        jr      mkSw
MK_W1:  push    hl
        ld      l,1
        jr      mkSw
MK_W2:  push    hl
        ld      l,2
        jr      mkSw
MK_W3:  push    hl
        ld      l,3
mkSw:   push    af
        push    bc
        push    de
        ld      b,a
        ld      a,(mkMask)                      ; the cartridge decodes only the bank lines: 3Fh on a
        and     b                               ; 16-bank ROM selects bank 0Fh
        ld      e,a
        ld      c,l
        ld      b,0
        ld      hl,mkCur
        add     hl,bc
        ld      a,(hl)
        cp      e
        jr      z,mkOut                         ; the same bank again: nothing changes
        ld      (hl),e
        ld      a,i                             ; P/V = the caller's interrupt state
        push    af
        di
        ld      a,c
        and     2
        ld      c,a                             ; C = 0: page 1 (W0, W1), 2: page 2 (W2, W3)
        ld      hl,mkCur
        add     hl,bc
        ld      d,(hl)                          ; D = the bank of the page's low window
        inc     hl
        ld      e,(hl)                          ; E = the bank of its high window
        call    mkFind                          ; A = the segment holding (D, E)
        ld      hl,mkSeg
        bit     1,c
        jr      nz,.p2
        ld      (hl),a
        out     ($FD),a
        jr      .done
.p2:    inc     hl
        ld      (hl),a
        out     ($FE),a
.done:  pop     af
        jp      po,mkOut
        ei
mkOut:  pop     de
        pop     bc
        pop     af
        pop     hl
        ret

; C = page (0/2), D = low bank, E = high bank -> A = segment. Preserves C, D, E. Interrupts are off.
mkFind: push    ix
        ld      ix,mkPg1
        ld      hl,mkTab1
        bit     1,c
        jr      z,.scan0
        ld      ix,mkPg2
        ld      hl,mkTab2
.scan0: ld      b,(ix+0)
        push    hl
.scan:  ld      a,(hl)
        inc     hl
        cp      d
        jr      nz,.no1
        ld      a,(hl)
        cp      e
        jr      nz,.no1
        inc     hl
        ld      a,(hl)                          ; a hit: the segment
        inc     hl
        ld      (hl),1                          ; referenced
        pop     hl
        pop     ix
        ret
.no1:   inc     hl
        inc     hl
        inc     hl
        djnz    .scan
        ld      a,(ix+1)                        ; a miss
        cp      (ix+0)
        jr      nc,mkNone                       ; no spare entry: the loader refuses such a machine
.clock: pop     hl
        push    hl
        ld      a,(ix+2)                        ; the hand, in [pinned, in use)
        add     a,a
        add     a,a
        add     a,l
        ld      l,a
        jr      nc,.c1
        inc     h
.c1:    ld      a,(ix+2)
        inc     a
        cp      (ix+0)
        jr      c,.c2
        ld      a,(ix+1)
.c2:    ld      (ix+2),a
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)
        or      a
        jr      z,.take
        ld      (hl),0                          ; referenced since the hand passed: a second chance
        jr      .clock
.take:  ld      (hl),1
        dec     hl
        ld      a,(hl)                          ; the victim's segment
        dec     hl
        ld      (hl),e
        dec     hl
        ld      (hl),d
        pop     hl
        pop     ix
        push    bc
        push    af
        call    mkBuild
        pop     af
        pop     bc
        ret

mkNone: ld      a,9                             ; result 9: not possible on this machine
        jp      PN_END

; A = segment, D = low bank, E = high bank: copy the two banks from their homes into it. The target is
; mapped at 8000h and the homes at 4000h; both pages are put back afterwards (the stack is in page 3).
mkBuild:
        out     ($FE),a
        push    de
        ld      a,d
        ld      de,$8000
        call    mkCopy
        pop     de
        push    de
        ld      a,e
        ld      de,$A000
        call    mkCopy
        pop     de
        ld      a,(mkSeg)
        out     ($FD),a
        ld      a,(MK_SEG2)
        out     ($FE),a
        ret

; A = bank, DE = destination (8000h or A000h)
mkCopy: add     a,a
        add     a,mkHome & $FF
        ld      l,a
        ld      a,0
        adc     a,mkHome >> 8
        ld      h,a
        ld      a,(hl)                          ; the home segment
        out     ($FD),a
        inc     hl
        ld      a,(hl)                          ; the half it is in
        ld      hl,$4000
        or      a
        jr      z,.c
        ld      h,$60
.c:     ld      bc,$2000
        ldir
        ret
