; PLAYNET image host "mapper-ram" (PLAYNET-PROTOCOLS 7.3): a MegaROM of 8 KB banks in memory mapper segments.
; Included by playnet.asm. Design: documents/SALAMANDER-DESIGN.md, section 5.
;
; A 16 KB segment holds a PAIR of banks, as the game's two 8 KB windows of a page show them. The package lists the
; pairs; the first `pinned` of each page are never replaced, and each bank's home is the first pinned pair that
; holds it. The loader takes the segments, fills the tables of the stub's bank engine (MK_BLOCK, mapper_k8.asm)
; directly in the stub image, reads every bank into its home, patches the homes, then copies the homes into the
; other pairs. The game starts with the start pairs mapped (trampoline); the return maps MSX-DOS's own back.
;
; Segments: the mapper support routines when there are some (MSX-DOS 2, Nextor, MSR), user segments of the primary
; mapper; else (MSX-DOS 1) every segment above the TPA's four, counted the way msxarch counts them. The RAM of pages
; 1 and 2 must be that mapper. Direct OUTs to FDh/FEh are always undone before MSX-DOS runs again.
;
; This part runs in page 1 (playnet.asm copies it to 4000h at the start): it is only used before the image is in
; RAM, and a plain game's image later lands over it. What maps page 1 itself (mBuild), what runs on the way back
; (mUnmap) and the variables are in mapper_low.asm, in page 0.

RAMAD2:         EQU     $F343                   ; slot of the RAM in page 2
MCHUNK:         EQU     $0800                   ; the ROM is read 2 KB at a time: chunks never cross a bank
MSEGMAX:        EQU     64
MSEGL:          EQU     BOUNCE+CHUNK-MSEGMAX    ; the segments taken: only until the ROM's first chunk is read
        ASSERT  MCHUNK <= CHUNK && MSEGL >= BOUNCE+MCHUNK

; parseGpf, image host 1: MAPPER section and the image (check numbers 50-53)
mParse: ld      hl,(pMapper)
        ld      a,h
        or      l
        ld      a,50
        jp      z,badPkg
        ld      de,mRec
        ld      bc,mRecEnd-mRec
        ldir
        ld      (mPairs),hl
        ld      hl,(mType)                      ; type 1 (Konami SCC), 8 KB banks
        ld      de,$0801
        or      a
        sbc     hl,de
        ld      a,51
        jp      nz,badPkg
        ld      a,(mBanks)                      ; 2-64 banks, a power of two
        ld      b,a
        dec     a
        and     b
        ld      a,b
        jp      nz,.bad51
        cp      2
        jp      c,.bad51
        cp      65
        jp      nc,.bad51
        ld      l,b                             ; the ROM and the output: banks x 8 KB, the layout the identity
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                           ; HL = size / 256
        ld      (mSize),hl
        ld      de,mSize-1                      ; size bytes: 0, L, H, 0
        ld      hl,srcSize
        call    cmp4
        jp      nz,.bad52
        ld      de,mSize-1
        ld      hl,outSize
        call    cmp4
        jp      nz,.bad52
        ld      a,(outSize+5)                   ; one layout entry: the ROM (FFh), 0, its size, at 0
        dec     a
        jp      nz,.bad52
        ld      hl,(pLayEnt)
        ld      a,(hl)
        inc     a
        jp      nz,.bad52
        inc     hl
        ld      b,4
.z1:    ld      a,(hl)
        or      a
        jp      nz,.bad52
        inc     hl
        djnz    .z1
        ld      de,srcSize
        call    cmp4
        jp      nz,.bad52
        ld      b,4
.z2:    ld      a,(hl)
        or      a
        jp      nz,.bad52
        inc     hl
        djnz    .z2
        ld      hl,(npBase)                     ; the windows: 4000h-BFFFh
        ld      de,$4000
        or      a
        sbc     hl,de
        jp      nz,.bad52
        ld      hl,$C000
        ld      (imgEnd),hl
        ld      a,(mN1)                         ; 1 <= pinned <= pairs, for each page
        ld      b,a
        ld      a,(mPin1)
        call    .pin
        ld      a,(mN2)
        ld      b,a
        ld      a,(mPin2)
        call    .pin
        ld      a,(mN1)                         ; every bank of every pair inside the ROM
        ld      b,a
        ld      a,(mN2)
        add     a,b
        jp      c,.bad53
        add     a,a
        jp      c,.bad53
        ld      b,a
        ld      hl,(mPairs)
        ld      a,(mBanks)
        ld      c,a
.pb:    ld      a,(hl)
        cp      c
        jp      nc,.bad53
        inc     hl
        djnz    .pb
        ld      a,(mPin1)                       ; min_segments >= the pinned pairs and a spare for each page
        ld      b,a
        ld      a,(mPin2)
        add     a,b
        add     a,2
        ld      b,a
        ld      a,(mMinSeg)
        cp      b
        ret     nc
.bad53: ld      a,53
        jp      badPkg
.bad51: ld      a,51
        jp      badPkg
.bad52: ld      a,52
        jp      badPkg
.pin:   or      a
        jp      z,.bad53
        dec     a
        cp      b
        ret     c
        jr      .bad53

; ---- segments and the bank engine's block --------------------------------------------------------
; Check numbers 54-57. Out of memory: R_MACHINE with a message.
mSetup: ld      hl,(mBlock)                     ; the block inside the stub: mBlk = stub image + offset
        ld      de,(npStubLoad)
        or      a
        sbc     hl,de
        ld      a,54
        jp      c,badPkg
        push    hl
        ld      de,(stubSrc)
        add     hl,de
        ld      (mBlk),hl
        push    hl
        pop     ix
        ld      a,(ix+0)                        ; host ABI 1, and the stub was built for this many banks
        dec     a
        jp      nz,.bad54
        ld      a,(ix+1)
        inc     a
        ld      hl,mBanks
        cp      (hl)
        jp      nz,.bad54
        ld      a,(ix+2)                        ; its end: 16 + 2 x banks + 4 x the table entries
        add     a,(ix+3)
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        ld      a,(mBanks)
        add     a,a
        add     a,16
        ld      e,a
        ld      d,0
        add     hl,de
        pop     de
        add     hl,de
        ex      de,hl
        ld      hl,(stubLen)
        call    cpHLDE
        jp      c,.bad54
        ld      a,(mN1)                         ; table 1: every page-1 pair and a spare
        inc     a
        ld      (mCnt1),a
        cp      (ix+2)
        jr      z,.c1
        jp      nc,.bad55
.c1:    ld      a,(RAMAD1)                      ; the image is pages 1 and 2 of one mapper
        ld      hl,RAMAD2
        cp      (hl)
        ld      hl,msgOneMapper
        jp      nz,mNoMem
        call    mSegs
        ld      ix,(mBlk)                       ; EXTBIO's handlers need not keep IX
        ld      a,(mCnt1)                       ; table 2: what is left, at most every pair and a spare
        ld      b,a
        ld      a,(mGot)
        sub     b
        jp      c,mNoSegs
        ld      c,a
        ld      a,(mN2)
        inc     a
        cp      c
        jr      nc,.c2
        ld      c,a
.c2:    ld      a,(ix+3)                        ; and what the stub has room for
        cp      c
        jr      nc,.c3
        ld      c,a
.c3:    ld      a,c
        ld      (mCnt2),a
        ld      a,(mPin2)                       ; with a spare beyond the pinned ones
        cp      c
        jp      nc,mNoSegs
        ld      a,(mMinSeg)
        ld      hl,mGot
        cp      (hl)
        jr      z,.ok
        jp      nc,mNoSegs
.ok:    ld      hl,(mBlk)                       ; the block: banks of the 4 windows, segment records
        ld      de,4
        add     hl,de
        ex      de,hl
        ld      hl,mStart
        ld      bc,4
        ldir
        call    mTab1                           ; HL = table 1
        ld      bc,(mCnt1)                      ; C = entries
        ld      a,(mN1)
        ld      b,a
        ld      de,(mPairs)
        ld      iy,MSEGL
        call    mFill
        call    mTab2                           ; IY and DE go on from table 1
        ld      bc,(mCnt2)
        ld      a,(mN2)
        ld      b,a
        call    mFill
        ld      hl,(mBlk)                       ; page records: in use, pinned, hand = pinned
        ld      a,(mBanks)
        add     a,a
        add     a,10
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,(mCnt1)
        ld      (hl),a
        inc     hl
        ld      a,(mPin1)
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      a,(mCnt2)
        ld      (hl),a
        inc     hl
        ld      a,(mPin2)
        ld      (hl),a
        inc     hl
        ld      (hl),a
        ld      de,(mStart)                     ; the start pairs' segments
        call    mTab1
        ld      a,(mPin1)
        call    mPair
        jp      c,.bad56
        ld      (ix+8),a
        ld      de,(mStart+2)
        call    mTab2
        ld      a,(mPin2)
        call    mPair
        jp      c,.bad56
        ld      (ix+9),a
        ld      a,(mBanks)                      ; every bank's home: the first pinned pair holding it
        ld      c,a
.home:  dec     c
        call    mTab1
        ld      a,(mPin1)
        call    mBank
        jr      nc,.got
        call    mTab2
        ld      a,(mPin2)
        call    mBank
        jp      c,.bad56
.got:   ld      hl,(mBlk)                       ; homes[c] = segment, half
        ld      e,c
        ld      d,0
        add     hl,de
        add     hl,de
        ld      de,10
        add     hl,de
        ld      (hl),a
        inc     hl
        ld      (hl),b
        ld      a,c
        or      a
        jr      nz,.home
        ret
.bad54: ld      a,54
        jp      badPkg
.bad55: ld      a,55
        jp      badPkg
.bad56: ld      a,56
        jp      badPkg

; HL = table, C = entries, B = pairs (C <= pairs + 1), DE = the pairs, IY = their segments. Entries past the
; pairs are spares (key FFh FFh: no bank is that). Out: DE after the pairs used. Every entry not referenced.
mFill:  ld      a,(iy+0)
        inc     iy
        push    af
        ld      a,b
        or      a
        jr      z,.spare
        dec     b
        ld      a,(de)
        ld      (hl),a
        inc     de
        inc     hl
        ld      a,(de)
        inc     de
        jr      .key
.spare: ld      a,$FF
        ld      (hl),a
        inc     hl
.key:   ld      (hl),a
        inc     hl
        pop     af
        ld      (hl),a
        inc     hl
        ld      (hl),0
        inc     hl
        dec     c
        jr      nz,mFill
        ld      a,b                             ; pairs left over (memory ran out): skip them
        add     a,a
        add     a,e
        ld      e,a
        ret     nc
        inc     d
        ret

; HL = table, A = entries to search, E = low bank, D = high bank -> A = segment; CF if none
mPair:  or      a
        scf
        ret     z
        ld      b,a
.l:     ld      a,(hl)
        cp      e
        inc     hl
        jr      nz,.n
        ld      a,(hl)
        cp      d
        jr      nz,.n
        inc     hl
        ld      a,(hl)
        ret
.n:     inc     hl
        inc     hl
        inc     hl
        djnz    .l
        scf
        ret

; HL = table, A = entries to search, C = bank -> A = segment, B = half (0/1); CF if none. Keeps C.
mBank:  or      a
        scf
        ret     z
        ld      b,a
.l:     ld      a,(hl)
        cp      c
        jr      z,.lo
        inc     hl
        ld      a,(hl)
        cp      c
        jr      z,.hi
        inc     hl
        inc     hl
        inc     hl
        djnz    .l
        scf
        ret
.lo:    inc     hl
        ld      b,0
        jr      .seg
.hi:    ld      b,1
.seg:   inc     hl
        ld      a,(hl)
        or      a                               ; CF = 0
        ret

; the segments: up to every entry of both tables (mN1 + mN2 + 2), into MSEGL; mGot = how many
mSegs:  xor     a
        ld      (mGot),a
        ld      a,(mN1)
        ld      b,a
        ld      a,(mN2)
        add     a,b
        add     a,2
        cp      MSEGMAX
        jr      c,.w
        ld      a,MSEGMAX
.w:     ld      (mWant),a
        xor     a                               ; the mapper support routines?
        ld      de,$0402
        ld      hl,0
        call    EXTBIO
        ld      (mapTab),hl
        ld      a,h
        or      l
        jr      z,.dos1
        ld      a,M_GET_P1                      ; MSX-DOS 2 / Nextor / MSR: the pages' own segments...
        call    mapper
        ld      (mDos1),a
        ld      a,M_GET_P2
        call    mapper
        ld      (mDos2),a
.all:   call    .room                           ; ...and user segments of the primary mapper
        ret     nc
        xor     a
        ld      b,a
        ld      hl,(mapTab)
        call    jpHL
        ret     c
        call    .put
        jr      .all
.dos1:  ld      a,2                             ; MSX-DOS 1: the TPA is segments 3 2 1 0 (pages 0-3)
        ld      (mDos1),a
        dec     a
        ld      (mDos2),a
        call    mCount
        ld      d,a
        ld      a,4
.d1:    cp      d
        ret     nc
        ld      e,a
        call    .room
        ret     nc
        ld      a,e
        call    .put
        ld      a,e
        inc     a
        jr      .d1
.room:  ld      a,(mGot)                        ; CF if more are wanted
        ld      hl,mWant
        cp      (hl)
        ret
.put:   ld      hl,mGot
        ld      c,(hl)
        inc     (hl)
        ld      b,0
        ld      hl,MSEGL
        add     hl,bc
        ld      (hl),a
        ret

; MSX-DOS 1: count the segments. Segment 0 (page 3) holds a sentinel at C000h; selecting segment n in page 2 and
; writing 8000h reaches it when n is the mapper's size. Every byte touched is put back. -> A = 4-255.
mCount: di
        ld      hl,$C000
        ld      b,(hl)
        ld      (hl),$A5
        ld      c,4
.n:     ld      a,c
        out     ($FE),a
        ld      a,($8000)
        ld      e,a
        ld      a,$5A
        ld      ($8000),a
        ld      a,(hl)
        cp      $A5
        ld      a,e
        ld      ($8000),a
        jr      nz,.wrap
        inc     c
        jr      nz,.n
        dec     c                               ; 256 segments: use 255
.wrap:  ld      a,(mDos2)
        out     ($FE),a
        ld      (hl),b
        ei
        ld      a,c
        ret

mNoSegs:
        ld      hl,msgMemory
mNoMem: ld      a,R_MACHINE
        jp      exitResult

; ---- the ROM into the homes (loadRom, after the file is open and its size checked) ---------------------
mLoad:  call    mSetup
        call    crcStart
        ld      hl,0
        ld      (mOff),hl
        ld      (mOff+2),hl
.chunk: ld      hl,(mOff+1)                     ; done at the ROM's size (offset / 256 = mSize)
        ld      de,(mSize)
        or      a
        sbc     hl,de
        jr      z,.done
        ld      hl,(mOff)
        ld      (fcb+33),hl
        ld      hl,(mOff+2)
        ld      (fcb+35),hl
        ld      de,BOUNCE
        ld      c,F_SETDTA
        call    BDOS
        ld      de,fcb
        ld      hl,MCHUNK
        ld      c,F_RDRND
        call    BDOS
        or      a
        ld      hl,msgReadErr
        jp      nz,romErr
        ld      hl,BOUNCE
        ld      bc,MCHUNK
        call    crcUpdate
        call    mAt                             ; DE = where, segment in page 2
        ld      hl,BOUNCE
        ld      bc,MCHUNK
        ldir
        call    mUnmap
        ei
        ld      hl,(mOff+1)
        ld      de,MCHUNK/256
        add     hl,de
        ld      (mOff+1),hl
        jr      .chunk
.done:  call    crcFinish
        ld      hl,crcVal
        ld      de,srcCrc
        call    cmp4
        ld      hl,msgWrongRom
        jp      nz,romErr
        ret

; the ROM offset at mOff (3 bytes) -> its home mapped in page 2, DE = its address there, interrupts off (mUnmap,
; then ei). CF if the bank is not in the ROM; else HL = the offset inside the bank.
mAt:    ld      a,(mOff+1)                      ; bank = offset >> 13. Keeps B.
        rlca
        rlca
        rlca
        and     7
        ld      c,a
        ld      a,(mOff+2)
        cp      8
        ccf
        ret     c
        add     a,a
        add     a,a
        add     a,a
        or      c
        ld      hl,mBanks
        cp      (hl)
        ccf
        ret     c
        call    mHomeOf
        ld      a,d
        di                                      ; until mUnmap: an interrupt handler may put back the page-2
        out     ($FE),a                         ; segment the mapper routines recorded (INL, RAMHELPR)
        ld      a,(mOff+1)
        and     $1F
        ld      d,a
        ld      a,(mOff)
        ld      e,a
        push    de
        add     hl,de
        ex      de,hl
        pop     hl
        or      a
        ret

; ---- patches into the homes, then the homes into the other pairs (patchImage, image host 1) --------------
mPatch: ld      hl,(pPatch)
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                          ; count
        inc     hl
.next:  ld      a,b
        or      c
        jp      z,mBuild
        push    bc
        ld      de,mOff                         ; offset (4): mOff, and the top byte must be 0
        ld      bc,3
        ldir
        ld      a,(hl)
        inc     hl
        or      a
        jr      nz,.bad
        ld      b,(hl)                          ; length
        inc     hl
        push    hl
        call    mAt                             ; DE = target, HL = offset in the bank
        jr      c,.bad1
        ld      a,l                             ; the patch must end inside its bank
        add     a,b
        ld      a,h
        adc     a,0
        cp      $20
        jr      c,.in
        jr      nz,.bad1
        ld      a,l
        add     a,b
        jr      nz,.bad1
.in:    pop     hl                              ; HL = expected bytes
        push    de
        push    bc
.cmp:   ld      a,(de)
        cp      (hl)
        jr      nz,.differ
        inc     hl
        inc     de
        djnz    .cmp
        pop     bc
        pop     de
.put:   ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        djnz    .put
        call    mUnmap
        ei
        pop     bc
        dec     bc
        jr      .next
.differ:
        call    mUnmap
        ei
        ld      hl,msgWrongRom
        jp      romErr
.bad1:  pop     hl
.bad:   call    mUnmap
        ei
        ld      a,44
        jp      badPkg

msgOneMapper:   defb    "This game needs pages 1 and 2 in the same memory mapper",0
msgMemory:      defb    "Not enough memory: this game needs a memory mapper of 512 KB",0

