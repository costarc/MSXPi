; PLAYNET mapper-RAM host for ASCII16 MegaROMs (16 KB banks, page 1 switched): the bank engine (host ABI 1).
; First user: Penguin-kun Wars 2 (profiles/pwars2, documents/PWARS2-DESIGN.md).
;
; The loader (mapper_host.asm, mapper type 3) knows only 8 KB banks, so the package describes the ROM in 8 KB
; halves: its 16 KB bank N is the pair (2N, 2N+1). Page 1's table lists every such pair, all pinned: each bank
; is one mapper segment, built once by the loader and never copied again. A switch is a table read and one OUT.
; MK_BLOCK has mapper_k8.asm's layout (the loader fills it the same way); only what is used here is read.
;
; A game's glue defines MK_BANKS (8 KB halves in the ROM: 2 x the 16 KB banks, at most 64), MK_P1_MAX and
; MK_P2_MAX (table entries; the loader wants one spare in each), then INCLUDEs this file after playnet_engine.asm.
; The package patches the game's page-1 bank select into MK_A16 (A = the 16 KB bank). Page 2 is never switched
; by this engine: a game whose page 2 is its own RAM keeps the segment the loader mapped there.
; Build with -DCART for a test stub that runs from the cartridge itself: MK_A16 then writes the ASCII16
; register (6000h) instead of mapping a segment.
;
; MK_BLOCK (filled by the loader; the build zeroes it):
;   +0  version (1)     +1  mask (MK_BANKS-1)    +2  entries of table 1, of table 2 (MK_P1_MAX, MK_P2_MAX)
;   +4  8 KB bank in W0..W3  +8  segment in page 1, page 2
;   +10 home of each 8 KB bank: segment, half (2 bytes a bank)
;   then for page 1 and page 2: entries in use, pinned entries, clock hand (3 bytes each)
;   then the tables: MK_P1_MAX, then MK_P2_MAX entries of (low bank, high bank, segment, referenced)

        ASSERT  MK_BANKS >= 4 && MK_BANKS <= 64 && (MK_BANKS & (MK_BANKS-1)) == 0
        ASSERT  MK_P1_MAX >= MK_BANKS/2+1 && MK_P2_MAX >= 2 && MK_P1_MAX + MK_P2_MAX <= 63

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

; ---- MK_A16: the game selects 16 KB bank A in page 1. Keeps AF; interrupts are on afterwards (the cartridge
; routine this replaces ends with EI). MK_SEL does the same with interrupts left as they are and keeps HL, BC.
MK_A16: di
        call    MK_SEL
        ei
        ret

MK_SEL: push    hl
        push    af
        and     MK_BANKS/2-1                    ; the cartridge decodes only the bank lines
        add     a,a
        ld      (mkCur),a                       ; the two 8 KB windows of page 1, as the block records them
        ld      l,a
        inc     a
        ld      (mkCur+1),a
        IFDEF   CART
        ld      a,l
        rrca
        ld      ($6000),a
        ELSE
        ld      a,l
        add     a,a                             ; the home of half 2N: mkHome + 4N (its half is 0)
        add     a,mkHome & $FF
        ld      l,a
        ld      a,0
        adc     a,mkHome >> 8
        ld      h,a
        ld      a,(hl)
        ld      (mkSeg),a
        out     ($FD),a
        ENDIF
        pop     af
        pop     hl
        ret

; A = the 16 KB bank in page 1 now
MK_CUR: ld      a,(mkCur)
        rrca
        ret
