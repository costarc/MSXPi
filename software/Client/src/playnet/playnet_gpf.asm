; PLAYNET.COM: the game package (GPF): fetched, checked and parsed. Runs in page 1 (playnet.asm copies it to 4000h
; at the start), before the image is in RAM.

; ---- game package (8) -------------------------------------------------------------------------
getProfile:
        ld      a,(tcp)
        or      a
        jp      nz,tcpGpf
        ld      hl,cmdProfileId                 ; "playnet profile " + id
        ld      de,gameId
.cat:   ld      a,(de)
        ld      (hl),a
        inc     hl
        inc     de
        or      a
        jr      nz,.cat
        ld      de,cmdProfile
        ld      hl,GPFBUF
        ld      bc,GPFMAX+BLKSIZE               ; piCommand wants room for a whole block each time: the
        call    piCommand                       ; disk buffer above takes the excess (CRCT is above that)
        jp      c,linkErr
        cp      RC_SUCCESS
        jp      nz,piRefused
        ld      hl,GPFMAX
        call    cpHLDE.bc
        ld      hl,msgTooBig
        jp      c,exitQuiet                     ; longer than GPFMAX
gpfCheck:                                       ; BC = the GPF's length, at GPFBUF
        ld      (gpfLen),bc
        ld      hl,-128
        add     hl,bc
        ld      a,1
        jp      nc,badPkg                       ; shorter than the header
        ld      hl,GPFBUF
        ld      de,magicGPF
        call    cmp4
        ld      a,2
        jp      nz,badPkg
        ld      a,(GPFBUF+4)
        dec     a
        ld      hl,msgNewer
        ld      a,R_INCOMPAT
        jp      nz,exitResult                   ; a newer GPF format
        ld      hl,(GPFBUF+6)                   ; body length + 128 = what arrived
        ld      de,128
        add     hl,de
        ld      de,(gpfLen)
        or      a
        sbc     hl,de
        ld      a,3
        jp      nz,badPkg
        call    crcStart                        ; the profile hash: CRC-32 with bytes 8-11 as zero
        ld      hl,GPFBUF
        ld      bc,8
        call    crcUpdate
        ld      hl,zero4
        ld      bc,4
        call    crcUpdate
        ld      hl,(gpfLen)
        ld      bc,-12
        add     hl,bc
        ld      b,h
        ld      c,l
        ld      hl,GPFBUF+12
        call    crcUpdate
        call    crcFinish
        ld      hl,crcVal
        ld      de,GPFBUF+8
        call    cmp4
        ld      a,4
        jp      nz,badPkg                       ; damaged
        ld      a,(GPFBUF+98)                   ; min_playnet
        cp      PLAYNET_VERSION+1
        ld      hl,msgNewer
        ld      a,R_INCOMPAT
        jp      nc,exitResult
        ld      a,(GPFBUF+5)                    ; flags: bit 0 lockstep, bits 1-2 image host
        ld      b,a
        and     $F9
        cp      1
        ld      hl,msgOwnProgram
        jp      nz,exitResult
        ld      a,b
        rrca
        and     3
        ld      (mHost),a                       ; 0 plain, 1 mapper-ram
        cp      2
        ld      hl,msgNewer
        ld      a,R_INCOMPAT
        jp      nc,exitResult
        ld      a,(manual)
        or      a
        ret     nz
        ld      hl,sesBuf+12                    ; the session's profile hash
        ld      de,GPFBUF+8
        call    cmp4
        ld      hl,msgChanged
        ld      a,R_INCOMPAT
        jp      nz,exitResult
        ret

; Walk the sections and check the package's rules again (7.2, 8.3): a GPF from the MSXPi is not trusted
; more than one from a disk. A = check number on failure (shown to the player).
parseGpf:
        ld      hl,GPFBUF+128
.sec:   ld      c,(hl)                          ; type
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                          ; DE = length
        inc     hl                              ; HL = payload
        push    hl
        add     hl,de
        ld      (secEnd),hl
        push    de
        ld      de,(gpfLen)
        ld      hl,GPFBUF
        add     hl,de
        ld      de,(secEnd)
        or      a
        sbc     hl,de                           ; the end of the file minus the end of the section
        pop     de
        pop     hl
        ld      a,10
        jp      c,badPkg                        ; runs past the end of the file
        ld      a,c
        or      a
        jr      z,.done
        dec     a
        jr      nz,.n1
        ld      (pSource),hl
.n1:    dec     a
        jr      nz,.n2
        ld      (pNetplay),hl
.n2:    dec     a
        jr      nz,.n3
        ld      (pLayout),hl
.n3:    dec     a
        jr      nz,.n4
        ld      (pPatch),hl
.n4:    dec     a
        jr      nz,.n5
        ld      a,(nAssets)                     ; an asset: remember where and how long
        cp      8
        ld      a,11
        jp      nc,badPkg
        push    hl
        ld      a,(nAssets)
        add     a,a
        add     a,a
        ld      c,a
        ld      b,0
        ld      hl,assetTab
        add     hl,bc
        pop     bc                              ; BC = asset address
        ld      (hl),c
        inc     hl
        ld      (hl),b
        inc     hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      hl,nAssets
        inc     (hl)
        jr      .next
.n5:    dec     a
        jr      nz,.next
        ld      (pMapper),hl
.next:  ld      hl,(secEnd)
        jr      .sec
.done:  ld      hl,(pSource)                    ; all four sections are required
        ld      a,h
        or      l
        ld      a,12
        jp      z,badPkg
        ld      hl,(pNetplay)
        ld      a,h
        or      l
        ld      a,12
        jp      z,badPkg
        ld      hl,(pLayout)
        ld      a,h
        or      l
        ld      a,12
        jp      z,badPkg
        ld      hl,(pPatch)
        ld      a,h
        or      l
        ld      a,12
        jp      z,badPkg
        ld      hl,(pNetplay)                   ; the fixed part of NETPLAY into np...
        ld      de,np
        ld      bc,17
        ldir
        ld      (pRanges),hl
        ld      hl,(pSource)                    ; SOURCE: size (4), CRC-32 (4), file name (12)
        ld      de,srcSize
        ld      bc,20
        ldir
        ld      hl,(pLayout)                    ; LAYOUT: output size (4), fill, count
        ld      de,outSize
        ld      bc,6
        ldir
        ld      (pLayEnt),hl
        ; -- the image: base 4000h or 8000h, 16 or 32 KB, ending at or below BFFFh (mapper-ram: mParse)
        ld      a,(mHost)
        or      a
        jr      z,.plain
        call    mParse
        jr      .w
.plain: ld      a,(npBase)
        or      a
        ld      a,20
        jp      nz,badPkg
        ld      a,(npBase+1)
        cp      $40
        jr      z,.b1
        cp      $80
        ld      a,20
        jp      nz,badPkg
.b1:    ld      hl,(outSize+2)
        ld      a,h
        or      l
        ld      a,21
        jp      nz,badPkg
        ld      hl,(outSize)
        ld      a,l
        or      a
        ld      a,21
        jp      nz,badPkg
        ld      a,h
        cp      $40
        jr      z,.b2
        cp      $80
        ld      a,21
        jp      nz,badPkg
.b2:    ld      de,(npBase)
        add     hl,de
        ld      (imgEnd),hl                     ; the first address after the image
        ld      de,$C001
        call    cpHLDE
        ld      a,22
        jp      nc,badPkg
        ld      hl,(srcSize+2)
        ld      a,h
        or      l
        ld      a,23
        jp      nz,badPkg
        ; -- input width
.w:     ld      a,(npW)
        dec     a
        cp      4
        ld      a,24
        jp      nc,badPkg
        ; -- the stub asset fits its room
        ld      a,(npStubAsset)
        ld      hl,nAssets
        cp      (hl)
        ld      a,25
        jp      nc,badPkg
        ld      a,(npStubAsset)
        call    assetAt                         ; HL = address, DE = length
        ld      (stubSrc),hl
        ld      (stubLen),de
        ld      hl,(npStubMax)
        call    cpHLDE
        ld      a,26
        jp      c,badPkg                        ; longer than stub.max
        ; -- stub area and transport area in page 3 (C000h-F37Fh), apart from each other
        ld      hl,(npStubLoad)
        ld      de,(npStubMax)
        call    page3
        ld      a,27
        jp      c,badPkg
        ld      (stubHi),hl
        ld      hl,(npTArea)
        ld      de,(npTSize)
        call    page3
        ld      a,28
        jp      c,badPkg
        ld      (tHi),hl
        ld      hl,TR_SIZE-1
        ld      de,(npTSize)
        call    cpHLDE
        ld      a,29
        jp      nc,badPkg                       ; this PLAYNET's transport does not fit the area
        ld      hl,(npStubLoad)
        ld      de,(stubHi)
        ld      (ovLo),hl
        ld      (ovHi),de
        ld      hl,(npTArea)
        ld      de,(tHi)
        call    overlap
        ld      a,30
        jp      c,badPkg
        ld      hl,(npStubLoad)                 ; and apart from this program's start-up code
        ld      de,(stubHi)
        ld      bc,TRAMP
        call    overTramp
        ld      a,31
        jp      c,badPkg
        ld      hl,(npTArea)
        ld      de,(tHi)
        call    overTramp
        ld      a,31
        jp      c,badPkg
        ; -- the game's RAM is apart from both
        ld      hl,(pRanges)
        ld      a,(npRanges)
        or      a
        ld      a,32
        jp      z,badPkg
        ld      a,(npRanges)
        ld      b,a
.rng:   push    bc
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        push    hl
        push    bc
        push    de
        ld      hl,(npStubLoad)
        ld      (ovLo),hl
        ld      hl,(stubHi)
        ld      (ovHi),hl
        pop     hl                              ; HL = low
        pop     de                              ; DE = high
        push    de
        push    hl
        call    overlap
        ld      a,33
        jp      c,badPkg
        ld      hl,(npTArea)
        ld      (ovLo),hl
        ld      hl,(tHi)
        ld      (ovHi),hl
        pop     hl
        pop     de
        call    overlap
        ld      a,34
        jp      c,badPkg
        pop     hl
        pop     bc
        djnz    .rng
        ; -- the interrupt handler and the start address are inside the image
        ld      hl,(npIrq)
        call    inImage
        ld      a,35
        jp      c,badPkg
        ld      hl,(npStart)
        ld      a,h
        or      l
        jr      z,.lay
        call    inImage
        ld      a,36
        jp      c,badPkg
        ; -- layout entries: source (1), offset (4), size (4), destination (4) (mapper-ram: checked by mParse)
.lay:   ld      a,(mHost)
        or      a
        ret     nz
        ld      hl,(pLayEnt)
        ld      a,(outSize+5)                   ; count
        or      a
        ret     z
        ld      b,a
.ent:   push    bc
        push    hl
        ld      de,lyEnt
        ld      bc,13
        ldir
        ld      hl,(lyOff+2)                    ; 32-bit fields: the high words must be zero here
        ld      de,(lySize+2)
        ld      a,h
        or      l
        or      d
        or      e
        ld      hl,(lyDest+2)
        or      h
        or      l
        ld      a,40
        jp      nz,badPkg
        ld      a,(lySrc)                       ; the source holds offset + size bytes
        cp      $FF
        jr      z,.inp
        ld      hl,nAssets
        cp      (hl)
        ld      a,41
        jp      nc,badPkg
        ld      a,(lySrc)
        call    assetAt                         ; DE = asset length
        jr      .src
.inp:   ld      de,(srcSize)
.src:   ld      hl,(lyOff)
        ld      bc,(lySize)
        add     hl,bc
        ld      a,42
        jp      c,badPkg
        inc     de
        call    cpHLDE
        ld      a,42
        jp      nc,badPkg
        ld      hl,(lyDest)                     ; destination + size inside the output
        ld      bc,(lySize)
        add     hl,bc
        ld      a,43
        jp      c,badPkg
        ld      de,(outSize)
        inc     de
        call    cpHLDE
        ld      a,43
        jp      nc,badPkg
        pop     hl
        ld      bc,13
        add     hl,bc
        pop     bc
        djnz    .ent
        ret

