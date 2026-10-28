; PLAYNET mapper-RAM host for 8 KB-bank MegaROMs (Konami SCC, Konami, ASCII8): the bank engine (host ABI 1).
; Design: documents/SALAMANDER-DESIGN.md, section 5. First user: Salamander (profiles/salamander).
;
; A game's glue defines MK_BANKS (banks in the ROM, a power of two, at most 16), MK_P1_MAX and MK_P2_MAX (table
; entries for page 1 and page 2), MK_MAP (1 KB, 256-aligned, that the game leaves alone: the pair map), then
; INCLUDEs this file after playnet_engine.asm. The package patches every bank-register write of the game (ld (nn),a) into CALL MK_W0..MK_W3, one entry per 8 KB window:
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
        ASSERT  MK_BANKS <= 16 && (MK_MAP & $FF) == 0  ; the pair map: 1 KB at MK_MAP

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
; The map (MK_MAP, 1 KB) answers a switch without a scan: per page 256 bytes of segments, indexed by low bank * 16 +
; high bank (0 = not known yet), then per page 256 "referenced" bytes for the clock. The same bank again costs about
; 85 T-states, a switch to a pair the map knows about 240 (the cartridge: 13). The map is cleared on the first
; switch (mkI1/mkI2 in the stub image, which then become the fast path), and forgets a pair the clock replaces.
MK_W0:  push    hl
        ld      hl,mkCur
        jr      mkS1
MK_W1:  push    hl
        ld      hl,mkCur+1
mkS1:   push    af
        and     MK_BANKS-1                      ; the cartridge decodes only the bank lines: 3Fh on a
        cp      (hl)                            ; 16-bank ROM selects bank 0Fh
        jp      z,mkSame                        ; the same bank again: nothing changes
        ld      (hl),a
mkF1:   jp      mkI1                            ; ld hl,(mkCur) once the map is clear: L = W0, H = W1
        ld      a,l
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      h
        ld      l,a
        ld      h,MK_MAP >> 8
        ld      a,(hl)
        or      a
        jr      z,mkSlow1                       ; a pair the map does not know yet
        inc     h
        inc     h
        ld      (hl),1                          ; referenced
        ld      (mkSeg),a
        out     ($FD),a
        pop     af
        pop     hl
        ret
mkSlow1: push   bc
        push    de
        ld      c,0
        jp      mkPage

MK_W2:  push    hl
        ld      hl,mkCur+2
        jr      mkS2
MK_W3:  push    hl
        ld      hl,mkCur+3
mkS2:   push    af
        and     MK_BANKS-1
        cp      (hl)
        jr      z,mkSame
        ld      (hl),a
mkF2:   jp      mkI2                            ; ld hl,(mkCur+2) once the map is clear: L = W2, H = W3
        ld      a,l
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      h
        ld      l,a
        ld      h,(MK_MAP >> 8) + 1
        ld      a,(hl)
        or      a
        jr      z,mkSlow2
        inc     h
        inc     h
        ld      (hl),1
        ld      (MK_SEG2),a
        out     ($FE),a
        pop     af
        pop     hl
        ret
mkSlow2: push   bc
        push    de
        ld      c,2

; C = 0: page 1 (W0, W1), 2: page 2 (W2, W3), with HL, AF, BC, DE on the stack: the pair from the tables (built if
; missing), then into the map.
mkPage: ld      a,i                             ; P/V = the caller's interrupt state
        push    af
        di
        ld      b,0
        ld      hl,mkCur
        add     hl,bc
        ld      d,(hl)                          ; D = the bank of the page's low window
        inc     hl
        ld      e,(hl)                          ; E = the bank of its high window
        call    mkFind                          ; A = the segment holding (D, E)
        push    af
        call    mkIdx
        pop     af
        ld      (hl),a                          ; known from now on
        inc     h
        inc     h
        ld      (hl),1
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
mkSame: pop     af
        pop     hl
        ret

; MK_W23: W2 := D, W3 := E in one switch of page 2, for a glue's own code that sets both (no pair of one new bank
; and one old one in between). Preserves every register and the flags.
MK_W23: push    hl
        push    af
        ld      a,d
        and     MK_BANKS-1
        ld      (mkCur+2),a
        ld      a,e
        and     MK_BANKS-1
        ld      (mkCur+3),a
        jr      mkF2

; C = page (0/2), D, E = the pair -> HL = its segment byte in the map. Clobbers A.
mkIdx:  ld      a,d
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        or      e
        ld      l,a
        ld      a,c
        rrca
        add     a,MK_MAP >> 8
        ld      h,a
        ret

; the first switch: clear the map, then put the fast path's own first instructions in place
mkI1:   call    mkClr
        jp      mkF1
mkI2:   call    mkClr
        jp      mkF2
mkClr:  push    bc
        push    de
        ld      hl,MK_MAP
        ld      de,MK_MAP+1
        ld      bc,1023
        ld      (hl),0
        ldir
        ld      a,$2A                           ; ld hl,(nn)
        ld      (mkF1),a
        ld      (mkF2),a
        ld      hl,mkCur
        ld      (mkF1+1),hl
        ld      hl,mkCur+2
        ld      (mkF2+1),hl
        pop     de
        pop     bc
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
        push    de                              ; the entry's pair: referenced (in the map) since the hand passed?
        ld      d,(hl)
        inc     hl
        ld      e,(hl)
        dec     hl
        push    hl
        call    mkIdx
        inc     h
        inc     h
        ld      a,(hl)
        or      a
        jr      z,.take
        ld      (hl),0                          ; yes: a second chance
        pop     hl
        pop     de
        jr      .clock
.take:  dec     h                               ; no: the map forgets the victim's pair
        dec     h
        ld      (hl),0
        pop     hl
        pop     de
        ld      (hl),d
        inc     hl
        ld      (hl),e
        inc     hl
        ld      a,(hl)                          ; the victim's segment
        pop     hl                              ; the table's start
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
