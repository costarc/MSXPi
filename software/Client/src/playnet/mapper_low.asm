; PLAYNET image host "mapper-ram": the part that stays in page 0 (mapper_host.asm runs in page 1). mBuild maps
; the homes into page 1, mUnmap runs on the way back to MSX-DOS, and the variables are read after the image is in.

; A = bank -> D = its home segment, HL = 8000h or A000h (its half, seen in page 2), E kept
mHomeOf:
        add     a,a
        ld      hl,(mBlk)
        add     a,10
        add     a,l
        ld      l,a
        jr      nc,.n
        inc     h
.n:     ld      d,(hl)
        inc     hl
        ld      a,(hl)
        ld      hl,$8000
        or      a
        ret     z
        ld      h,$A0
        ret

; MSX-DOS's own segments back in pages 1 and 2
mUnmap: ld      a,(mDos1)
        out     ($FD),a
        ld      a,(mDos2)
        out     ($FE),a
        ret

; HL = table 1 / table 2 of the block
mTab1:  ld      hl,(mBlk)
        ld      a,(mBanks)
        add     a,a
        add     a,16
        add     a,l
        ld      l,a
        ret     nc
        inc     h
        ret
mTab2:  call    mTab1                           ; (table 1's room is the block's byte 2: IX is not kept
        push    de                              ; across MSX-DOS calls)
        ld      de,(mBlk)
        inc     de
        inc     de
        ld      a,(de)
        pop     de
        add     a,a
        add     a,a
        add     a,l
        ld      l,a
        ret     nc
        inc     h
        ret

; every pair that is not a bank's home gets its banks copied from their homes: page 1 shows the home (RAM slot),
; page 2 the pair being built
mBuild: call    ram1
        call    mTab1
        ld      a,(mCnt1)
        call    .tab
        call    mTab2
        ld      a,(mCnt2)
        call    .tab
        call    mUnmap
        jp      dos1
.tab:   ld      b,a
.ent:   push    bc
        ld      a,(hl)                          ; low bank, high bank, segment
        cp      $FF
        jr      z,.skip                         ; a spare
        push    hl
        inc     hl
        inc     hl
        ld      a,(hl)
        ld      (mSeg),a
        pop     hl
        push    hl
        ld      c,$80                           ; the low bank at 8000h, the high one at A000h
        call    .half
        pop     hl
        push    hl
        inc     hl
        ld      c,$A0
        call    .half
        pop     hl
.skip:  ld      de,4
        add     hl,de
        pop     bc
        djnz    .ent
        ret
.half:  ld      a,(hl)                          ; HL -> the bank, C = high byte of its place in page 2
        push    bc
        call    mHomeOf                         ; D = home segment, HL = its half in page 2
        pop     bc
        ld      a,(mSeg)
        cp      d
        jr      nz,.copy
        ld      a,h
        cp      c
        ret     z                               ; this is the home
.copy:  ld      a,d
        out     ($FD),a
        ld      a,(mSeg)
        out     ($FE),a
        ld      a,h
        sub     $40                             ; the home's half, seen in page 1
        ld      h,a
        ld      d,c
        ld      e,0
        ld      bc,$2000
        ldir
        ret

; ---- variables ---------------------------------------------------------------------------------------------
pMapper:        defw    0
mRec:                                           ; the MAPPER section's fixed part (14 bytes)
mType:          defb    0
mKb:            defb    0
mBanks:         defb    0
mBlock:         defw    0
mStart:         defs    4
mPin1:          defb    0
mPin2:          defb    0
mMinSeg:        defb    0
mN1:            defb    0
mN2:            defb    0
mRecEnd:
        ASSERT  mRecEnd-mRec == 14
mPairs:         defw    0
                defb    0                       ; } the ROM's size as 4 bytes: 0, then mSize, then 0
mSize:          defw    0                       ; } (the size / 256)
                defb    0
mBlk:           defw    0                       ; MK_BLOCK in the stub image
mCnt1:          defb    0                       ; entries in table 1, table 2
mCnt2:          defb    0
mWant:          defb    0
mGot:           defb    0
mDos1:          defb    0                       ; MSX-DOS's segments in pages 1 and 2
mDos2:          defb    0
mSeg:           defb    0
mOff:           defs    4
