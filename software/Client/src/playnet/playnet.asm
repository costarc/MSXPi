; PLAYNET.COM - online two-player games for MSX, MSXPi path.
; Specification: documents/PLAYNET-PROTOCOLS.md (5.4 the loader, 8 GPF, 9 stub, 10 transport, 13 session,
; 15 the "playnet" commands). Build: python build.py (needs sjasmplus and the asm-common includes).
;
;   PLAYNET                  start the game MCHAT prepared (the session comes from the MSXPi)
;   PLAYNET <game> <role>    start without the chat: the MSXPi's netplay session is set up by other means
;                            (the test rigs, a LAN set-up); <role> is one of the game's role words
;
; Steps, all under MSX-DOS: session -> game package (GPF) from the MSXPi, checked -> the player's ROM, its
; CRC-32 checked, copied to RAM through the package's layout -> patches, every expected byte checked ->
; connect to the opponent (opcode C9, the MSXPi does the network) -> install the stub and the transport
; in page 3 and start the game the way the BIOS starts a cartridge.
;
; Memory (any MSX with 64 KB RAM and MSX-DOS):
;   0100h-17FFh  this program          1800h-1BFFh  CRC-32 tables (4 x 256)
;   1C00h-2FFFh  the GPF (5 KB)        3000h-3FFFh  disk bounce buffer (DOS cannot read into page 1)
;   4000h-BFFFh  the game image        C000h-       the start-up trampoline, copied there at the end

PLAYNET_VERSION: EQU    1

F_TERM0:        EQU     $00
F_DIRIN:        EQU     $08                     ; console input, no echo
F_CONST:        EQU     $0B
F_OPEN:         EQU     $0F
F_SETDTA:       EQU     $1A
F_RDRND:        EQU     $27
INIT32:         EQU     $006F
EXBRSA:         EQU     $FAF8
JIFFY:          EQU     $FC9E

CRCT:           EQU     $1800
GPFBUF:         EQU     $1C00
GPFMAX:         EQU     $1400
BOUNCE:         EQU     $3000
CHUNK:          EQU     $1000
TRAMP:          EQU     $C000

R_LEFT:         EQU     2                       ; result codes (13.2)
R_CONNECT:      EQU     5
R_INCOMPAT:     EQU     6
R_CANCEL:       EQU     7
R_ROM:          EQU     8
R_MACHINE:      EQU     9

        org     $0100

start:  ld      hl,msgBanner
        call    PRINT
        call    resetMSXPI
        call    crcInit
        call    getSlot1
        ld      (dosSlot1),a
        call    parseArgs
        ld      a,(manual)
        or      a
        call    z,getSession
        call    getProfile
        call    parseGpf
        ld      a,(manual)
        or      a
        call    nz,seatFromRole
        call    loadRom
        call    patchImage
        call    connect
        jp      install

; ---- command line ---------------------------------------------------------------------------
parseArgs:
        ld      hl,$80                          ; the command tail: length, characters
        ld      c,(hl)
        ld      b,0
        inc     hl
        ld      de,argBuf
        ld      a,c
        cp      40
        jr      nc,.usage
        or      a
        jr      z,.end
        ldir
.end:   xor     a
        ld      (de),a
        ld      hl,argBuf
        call    skipSp
        ld      a,(hl)
        or      a
        ret     z                               ; no arguments: the session comes from the MSXPi
        cp      '/'
        jr      z,.tcp
        ld      a,1
        ld      (manual),a
        ld      de,gameId
        call    word
        call    skipSp
        ld      de,roleArg
        call    word
        ld      a,(roleArg)
        or      a
        ret     nz
.usage: ld      hl,msgUsage
        jp      exitQuiet
.tcp:   ld      hl,msgNoTcp
        jp      exitQuiet

skipSp: ld      a,(hl)
        cp      ' '
        ret     nz
        inc     hl
        jr      skipSp

; copy a word (at most 8 characters) from HL to DE, lower case, zero-terminated
word:   ld      b,8
.l:     ld      a,(hl)
        or      a
        jr      z,.e
        cp      ' '
        jr      z,.e
        call    lower
        ld      (de),a
        inc     de
        inc     hl
        djnz    .l
.e:     xor     a
        ld      (de),a
        ret

lower:  cp      'A'
        ret     c
        cp      'Z'+1
        ret     nc
        add     a,32
        ret

; ---- session (13.1) ---------------------------------------------------------------------------
getSession:
        ld      de,cmdSession
        ld      hl,sesBuf
        ld      bc,64
        call    piCommand
        jp      c,linkErr
        cp      RC_SUCCESS
        jp      nz,piRefused
        ld      hl,sesBuf
        ld      de,magicPNS
        call    cmp4
        ld      hl,msgBadSession
        jp      nz,exitQuiet
        ld      a,(sesBuf+8)
        ld      (seat),a
        ld      hl,sesBuf+16                    ; game id, upper case, padded with spaces
        ld      de,gameId
        call    word
        ld      hl,sesBuf+24                    ; the opponent's nick, 8 bytes
        ld      de,peer
        ld      bc,8
        ldir
        ret

; ---- game package (8) -------------------------------------------------------------------------
getProfile:
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
        ld      bc,GPFMAX
        call    piCommand
        jp      c,linkErr
        cp      RC_SUCCESS
        jp      nz,piRefused
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
        cp      1
        ld      hl,msgOwnProgram
        jp      nz,exitResult
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
        jr      nz,.next
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
        ; -- the image: base 4000h or 8000h, 16 or 32 KB, ending at or below BFFFh
        ld      a,(npBase)
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
        ld      a,(npW)
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
        ; -- layout entries: source (1), offset (4), size (4), destination (4)
.lay:   ld      hl,(pLayEnt)
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

; HL = start, DE = length: CF if not inside page 3 (C000h-F37Fh) or empty; else HL = last address
page3:  ld      a,d
        or      e
        scf
        ret     z
        push    hl
        push    de
        ld      de,$C000
        call    cpHLDE
        pop     de
        pop     hl
        ret     c
        dec     de
        add     hl,de
        ret     c                               ; wraps past FFFFh
        ex      de,hl
        ld      hl,$F37F
        call    cpHLDE                          ; F37Fh < last?
        ex      de,hl
        ret

; HL = low, DE = high: CF if [low, high] overlaps [ovLo, ovHi], that is low <= ovHi and ovLo <= high.
; HL and DE are kept.
overlap:
        push    hl
        push    de
        ex      de,hl                           ; HL = high
        ld      de,(ovLo)
        call    cpHLDE                          ; CF: high < ovLo, apart
        pop     de
        pop     hl
        ccf
        ret     nc
        push    hl
        push    de
        ex      de,hl                           ; DE = low
        ld      hl,(ovHi)
        call    cpHLDE                          ; CF: ovHi < low, apart
        pop     de
        pop     hl
        ccf
        ret

; HL = low, DE = high: CF if [low, high] overlaps the trampoline (TRAMP .. TRAMP + its size - 1)
overTramp:
        push    hl
        push    de
        ld      hl,TRAMP
        ld      (ovLo),hl
        ld      hl,TRAMP+trampEnd-trampSrc-1
        ld      (ovHi),hl
        pop     de
        pop     hl
        jp      overlap

; HL = address: CF if outside [npBase, imgEnd)
inImage:
        ld      de,(npBase)
        call    cpHLDE
        ret     c
        ld      de,(imgEnd)
        call    cpHLDE
        ccf
        ret

; CF if HL < DE (unsigned); HL and DE are kept
cpHLDE: or      a
        sbc     hl,de
        add     hl,de
        ret

; A = asset index -> HL = address, DE = length
assetAt:
        add     a,a
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,assetTab
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        pop     hl
        ret

; manual start: the role word picks the seat
seatFromRole:
        ld      hl,GPFBUF+44                    ; role of seat 0
        call    sameRole
        ld      a,0
        jr      z,.set
        ld      hl,GPFBUF+52                    ; role of seat 1
        call    sameRole
        ld      a,1
        jr      z,.set
        ld      hl,msgRole
        jp      exitQuiet
.set:   ld      (seat),a
        ret
; Z if the role at HL (zero-padded) is roleArg, ignoring case
sameRole:
        ld      de,roleArg
        ld      b,8
.l:     ld      a,(hl)
        call    lower
        ld      c,a
        ld      a,(de)
        cp      c
        ret     nz
        or      a
        ret     z
        inc     hl
        inc     de
        djnz    .l
        ret

; ---- the ROM ---------------------------------------------------------------------------------
loadRom:
        ld      hl,srcName                      ; "NAME.EXT" -> FCB "NAME    EXT"
        ld      de,fcb+1
        ld      b,8
.nm:    ld      a,(hl)
        cp      '.'
        jr      z,.pad
        or      a
        jr      z,.pad
        ld      (de),a
        inc     hl
        inc     de
        djnz    .nm
        jr      .ext
.pad:   ld      a,' '
.p:     ld      (de),a
        inc     de
        djnz    .p
.ext:   ld      a,(hl)
        cp      '.'
        jr      nz,.e0
        inc     hl
.e0:    ld      b,3
.ex:    ld      a,(hl)
        or      a
        jr      nz,.e1
        ld      a,' '
        dec     hl
.e1:    ld      (de),a
        inc     hl
        inc     de
        djnz    .ex
        ld      de,fcb
        ld      c,F_OPEN
        call    BDOS
        inc     a
        jr      nz,.open
        ld      hl,msgNoRom                     ; "Cannot open SOCCER.ROM"
        call    PRINT
        ld      hl,srcName
        jp      romErr
.open:  ld      hl,1                            ; record size 1: counts are bytes
        ld      (fcb+14),hl
        ld      hl,(fcb+16)                     ; the file size must be the package's
        ld      de,(srcSize)
        or      a
        sbc     hl,de
        ld      hl,msgWrongRom
        jp      nz,romErr
        ld      hl,(fcb+18)
        ld      a,h
        or      l
        ld      hl,msgWrongRom
        jp      nz,romErr
        ld      hl,msgLoading
        call    PRINT
        call    crcStart
        call    ram1                            ; the image starts as the fill byte
        ld      hl,(npBase)
        ld      bc,(outSize)
        ld      a,(outSize+4)
        ld      (hl),a
        ld      d,h
        ld      e,l
        inc     de
        dec     bc
        ldir
        call    dos1
        ld      hl,0
        ld      (chunkAt),hl
.chunk: ld      hl,(srcSize)                    ; this chunk: min(CHUNK, size - offset)
        ld      de,(chunkAt)
        or      a
        sbc     hl,de
        jr      z,.read
        ld      de,CHUNK
        call    cpHLDE
        jr      c,.n
        ex      de,hl
.n:     ld      (chunkLen),hl
        ld      hl,(chunkAt)
        ld      (fcb+33),hl
        ld      hl,0
        ld      (fcb+35),hl
        ld      de,BOUNCE
        ld      c,F_SETDTA
        call    BDOS
        ld      de,fcb
        ld      hl,(chunkLen)
        ld      c,F_RDRND
        call    BDOS
        or      a
        ld      hl,msgReadErr
        jp      nz,romErr
        ld      hl,BOUNCE
        ld      bc,(chunkLen)
        call    crcUpdate
        call    copyPieces
        ld      hl,(chunkAt)
        ld      de,(chunkLen)
        add     hl,de
        ld      (chunkAt),hl
        jr      .chunk
.read:  call    crcFinish
        ld      hl,crcVal
        ld      de,srcCrc
        call    cmp4
        ld      hl,msgWrongRom
        jp      nz,romErr
        jp      copyAssets

; copy the parts of this chunk ([chunkAt, chunkAt + chunkLen) of the ROM) that the layout places
copyPieces:
        ld      hl,(pLayEnt)
        ld      a,(outSize+5)
        or      a
        ret     z
        ld      b,a
.ent:   push    bc
        push    hl
        ld      de,lyEnt
        ld      bc,13
        ldir
        ld      a,(lySrc)
        inc     a
        jr      nz,.skip                        ; an asset: copyAssets does it
        ld      hl,(lyOff)                      ; lo = max(offset, chunkAt)
        ld      de,(chunkAt)
        call    cpHLDE
        jr      nc,.lo
        ex      de,hl
.lo:    ld      (pieceLo),hl
        ld      hl,(lyOff)                      ; hi = min(offset + size, chunkAt + chunkLen)
        ld      de,(lySize)
        add     hl,de
        push    hl
        ld      hl,(chunkAt)
        ld      de,(chunkLen)
        add     hl,de
        pop     de
        call    cpHLDE
        jr      c,.hi
        ex      de,hl
.hi:    ld      de,(pieceLo)                    ; nothing if hi <= lo
        call    cpHLDE
        jr      c,.skip
        jr      z,.skip
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l                             ; BC = hi - lo
        ld      hl,(pieceLo)                    ; to: base + dest + lo - offset
        ld      de,(lyOff)
        or      a
        sbc     hl,de
        ld      de,(lyDest)
        add     hl,de
        ld      de,(npBase)
        add     hl,de
        push    hl
        ld      hl,(pieceLo)                    ; from: BOUNCE + lo - chunkAt
        ld      de,(chunkAt)
        or      a
        sbc     hl,de
        ld      de,BOUNCE
        add     hl,de
        pop     de
        call    ram1
        ldir
        call    dos1
.skip:  pop     hl
        ld      bc,13
        add     hl,bc
        pop     bc
        djnz    .ent
        ret

; layout entries whose source is an asset
copyAssets:
        ld      hl,(pLayEnt)
        ld      a,(outSize+5)
        or      a
        ret     z
        ld      b,a
.ent:   push    bc
        push    hl
        ld      de,lyEnt
        ld      bc,13
        ldir
        ld      a,(lySrc)
        cp      $FF
        jr      z,.skip
        call    assetAt                         ; HL = asset
        ld      de,(lyOff)
        add     hl,de
        push    hl
        ld      hl,(lyDest)
        ld      de,(npBase)
        add     hl,de
        ex      de,hl
        pop     hl
        ld      bc,(lySize)
        call    ram1
        ldir
        call    dos1
.skip:  pop     hl
        ld      bc,13
        add     hl,bc
        pop     bc
        djnz    .ent
        ret

; ---- patches: every expected byte must be there --------------------------------------------
patchImage:
        call    ram1
        ld      hl,(pPatch)
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                          ; count (16-bit)
        inc     hl
.next:  ld      a,b
        or      c
        jp      z,dos1
        push    bc
        ld      e,(hl)                          ; offset (4): the high word must be zero
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        inc     hl
        or      (hl)
        inc     hl
        jr      nz,.bad
        ld      b,(hl)                          ; length
        inc     hl
        push    hl
        ex      de,hl                           ; HL = offset
        ld      d,0
        ld      e,b
        add     hl,de                           ; offset + length <= output size
        ld      de,(outSize)
        inc     de
        call    cpHLDE
        pop     hl
        jr      nc,.bad
        push    hl                              ; target = base + offset
        dec     hl
        dec     hl
        dec     hl
        dec     hl
        dec     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      hl,(npBase)
        add     hl,de
        ex      de,hl                           ; DE = target
        pop     hl                              ; HL = expected bytes
        push    de
        push    bc
.cmp:   ld      a,(de)                          ; compare the expected bytes
        cp      (hl)
        jr      nz,.differ
        inc     hl
        inc     de
        djnz    .cmp
        pop     bc                              ; HL = replacement bytes
        pop     de
.put:   ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        djnz    .put
        pop     bc
        dec     bc
        jr      .next
.differ:
        call    dos1
        ld      hl,msgWrongRom
        jp      romErr
.bad:   call    dos1
        ld      a,44
        jp      badPkg

; ---- connect (MSXPi: the Pi does the network; status polls with opcode C9) -------------------
connect:
        ld      hl,msgConnect
        call    PRINT
        ld      a,(manual)
        or      a
        jr      nz,.go
        ld      hl,msgTo
        call    PRINT
        ld      hl,peer
        call    PRINT
.go:    ld      hl,(JIFFY)
        ld      (t0),hl
        ld      (tDot),hl
        ld      a,$C0                           ; (re)start the session, and the status
.poll:  call    c9status
        jr      c,.wait                         ; the link failed: try again
        cp      1
        jr      z,.ready
        cp      2
        ld      hl,msgIncompat
        ld      b,R_INCOMPAT
        jr      z,.end
        cp      3
        ld      hl,msgNoAnswer
        ld      b,R_CONNECT
        jr      z,.end
        cp      4
        ld      hl,msgLeft
        ld      b,R_LEFT
        jr      z,.end
.wait:  ld      c,F_CONST                       ; Esc gives up
        call    BDOS
        or      a
        jr      z,.dot
        ld      c,F_DIRIN
        call    BDOS
        cp      27
        jr      nz,.dot
        ld      a,R_CANCEL
        call    c9bye
        ld      hl,msgCancel
        ld      a,R_CANCEL
        jp      exitResult
.dot:   ld      hl,(JIFFY)                      ; a dot a second
        ld      de,(tDot)
        or      a
        sbc     hl,de
        ld      de,60
        call    cpHLDE
        jr      c,.t
        ld      hl,(JIFFY)
        ld      (tDot),hl
        ld      a,'.'
        call    PUTCHAR
.t:     ld      hl,(JIFFY)                      ; the Pi gives up after 120 s; this, if the Pi is silent
        ld      de,(t0)
        or      a
        sbc     hl,de
        ld      de,140*60
        call    cpHLDE
        ld      hl,msgNoAnswer
        ld      b,R_CONNECT
        jr      nc,.end
        ei
        halt
        halt
        ld      a,$80                           ; the status only, from now on
        jr      .poll
.end:   ld      a,b
        jp      exitResult
.ready: ld      a,(stDelay)
        ld      (delay),a
        ld      hl,msgReady
        call    PRINT
        ld      a,(delay)
        add     a,'0'
        call    PUTCHAR
        jp      PRINTNLINE

; A = FLAGS (bit 7 set). C9, FLAGS, L = 0, SUM = 0 -> A0+state, delay, delay. Out: A = state,
; (stDelay); CF when the link failed.
c9status:
        di
        ld      (c9sp),sp
        call    c9txb0                          ; C9 then A
        xor     a
        call    c9txb
        call    c9txb                           ; L = 0, SUM = 0
        call    c9rxb
        ld      b,a
        call    c9rxb
        ld      (stDelay),a
        call    c9rxb
        ei
        ld      a,b
        and     $0F
        or      a
        ret
; A = result code: BYE. C9, 20h, 1, code, code -> 00, 00
c9bye:  di
        ld      (c9sp),sp
        ld      b,a
        ld      a,$20
        call    c9txb0
        ld      a,1
        call    c9txb
        ld      a,b
        call    c9txb
        call    c9txb
        call    c9rxb
        call    c9rxb
        ei
        or      a
        ret
c9txb0: push    af
        ld      a,$C9
        call    c9txb
        pop     af
        jp      c9txb
; a link timeout: back to the caller of c9status / c9bye with CF
c9fail: ld      a,$FF
        out     ($56),a
        ld      sp,(c9sp)
        ei
        scf
        ret

        INCLUDE "c9link.asm"

; ---- start the game ----------------------------------------------------------------------------
install:
        ld      hl,msgStart
        call    PRINT
        ld      hl,GPFBUF+20                    ; the title
        ld      de,title
        ld      bc,24
        ldir
        ld      hl,title
        call    PRINT
        call    PRINTNLINE
        ld      hl,(stubSrc)                    ; the stub's header: seat and delay
        inc     hl
        ld      a,(seat)
        ld      (hl),a
        inc     hl
        ld      a,(delay)
        ld      (hl),a
        ld      hl,trImage                      ; the transport, relocated to its area
        ld      de,tBuf
        ld      bc,TR_SIZE
        ldir
        ld      hl,trRelocs
.rel:   ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,d
        and     e
        inc     a
        jr      z,.relDone                      ; FFFFh ends the list
        push    hl
        ld      hl,tBuf
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        push    hl
        ld      hl,(npTArea)
        add     hl,de
        ex      de,hl
        pop     hl
        ld      (hl),d
        dec     hl
        ld      (hl),e
        pop     hl
        jr      .rel
.relDone:
        ld      hl,(npIrq)
        ld      (tBuf+TR_IRQ),hl
        ld      a,(npW)                         ; L = 14 + 8W: 8 records of W inputs and a count
        add     a,a
        add     a,a
        add     a,a
        add     a,14
        ld      (tBuf+TR_LEN),a
        ld      hl,trampSrc                     ; the trampoline first, then its variables (they live in it)
        ld      de,TRAMP
        ld      bc,trampEnd-trampSrc
        ldir
        ld      hl,(npBase)
        ld      (tBuf+TR_IMAGE),hl
        ld      (vBase),hl
        ld      hl,(stubSrc)
        ld      (vStubSrc),hl
        ld      hl,(npStubLoad)
        ld      (vStubDst),hl
        ld      hl,(stubLen)
        ld      (vStubLen),hl
        ld      hl,(npTArea)
        ld      (vTDst),hl
        ld      hl,(npStart)
        ld      (vStart),hl
        ld      a,(RAMAD1)
        ld      (vRam1),a
        di
        jp      TRAMP

; Runs from C000h. Copies the stub and the transport into page 3 (MSX-DOS is gone from here on),
; then starts the game with page 0 = main BIOS and page 1 = the RAM holding it.
trampSrc:
        PHASE   TRAMP
        ld      hl,(vStubSrc)
        ld      de,(vStubDst)
        ld      bc,(vStubLen)
        ldir
        ld      hl,tBuf
        ld      de,(vTDst)
        ld      bc,TR_SIZE
        ldir
        ld      a,$C9                           ; no MSX-DOS timer hook
        ld      ($FD9F),a
        ld      a,(EXPTBL)                      ; main BIOS slot into page 0
        and     3
        ld      c,a
        in      a,($A8)
        and     $FC
        or      c
        out     ($A8),a
        ld      a,(vRam1)                       ; RAM, holding the game, into page 1
        ld      h,$40
        call    ENASLT
        di
        ld      hl,$FD9A                        ; hooks left by DOS that point outside the BIOS become
.hook:  ld      a,(hl)                          ; RET, as a bare cartridge would see them
        cp      $F7
        jr      nz,.next
        inc     hl
        ld      b,(hl)
        dec     hl
        ld      a,(EXPTBL)
        cp      b
        jr      z,.next
        ld      a,(EXBRSA)
        cp      b
        jr      z,.next
        ld      (hl),$C9
.next:  ld      de,5
        add     hl,de
        ld      a,h
        cp      $FF
        jr      nz,.hook
        ld      a,l
        cp      $CF
        jr      c,.hook
        call    INIT32                          ; SCREEN 1, as before a cartridge INIT
        ld      hl,(vStart)
        ld      a,h
        or      l
        jr      nz,.go
        ld      hl,(vBase)                      ; INIT from the image's AB header
        inc     hl
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
.go:    jp      (hl)
vStubSrc:       defw    0
vStubDst:       defw    0
vStubLen:       defw    0
vTDst:          defw    0
vStart:         defw    0
vBase:          defw    0
vRam1:          defb    0
        DEPHASE
trampEnd:

; ---- MSXPi commands --------------------------------------------------------------------------
; DE = command (zero-terminated), HL = destination, BC = room. Receives every block of the reply.
; Out: CF on a link error; else A = the last block's header code, BC = bytes received, the reply
; zero-terminated (text replies).
piCommand:
        ld      (pcCmd),de
        ld      (pcDst),hl
        dec     bc                              ; one byte for the terminator
        add     hl,bc
        ld      (pcLim),hl
        ld      h,b                             ; the block size asked for: min(room, BLKSIZE)
        ld      l,c
        ld      de,BLKSIZE
        call    cpHLDE
        jr      c,.bsz
        ex      de,hl
.bsz:   ld      (pcBsz),hl
        ld      de,(pcCmd)
        call    SendCommandToMSXPi
        ret     c
        ld      de,(pcDst)
        ld      bc,(pcBsz)
        xor     a
        ld      (pcIdx),a
        call    PerformHandshake
        ret     c
.blk:   ld      hl,(pcLim)                      ; room for another whole block?
        or      a
        sbc     hl,de
        push    de
        ld      de,(pcBsz)
        call    cpHLDE
        pop     de
        ld      hl,msgTooBig
        jp      c,exitQuiet
        ld      a,(pcIdx)
        ld      bc,(pcBsz)
        call    RECVDATA_ONEBLOCK
        ret     c
        cp      RC_READY
        jr      nz,.last
        ld      hl,pcIdx
        inc     (hl)
        jr      .blk
.last:  ld      b,a
        xor     a
        ld      (de),a
        ld      hl,(pcDst)
        ex      de,hl
        or      a
        sbc     hl,de
        ld      a,b
        ld      b,h
        ld      c,l
        or      a                               ; CF = 0
        ret

; ---- CRC-32 (IEEE, as zlib) with four 256-byte tables -----------------------------------------
crcInit:
        ld      c,0
.n:     ld      e,c                             ; crc = n, in H L D E (H high)
        ld      d,0
        ld      hl,0
        ld      b,8
.bit:   srl     h
        rr      l
        rr      d
        rr      e
        jr      nc,.nx
        ld      a,e
        xor     $20                             ; EDB88320h
        ld      e,a
        ld      a,d
        xor     $83
        ld      d,a
        ld      a,l
        xor     $B8
        ld      l,a
        ld      a,h
        xor     $ED
        ld      h,a
.nx:    djnz    .bit
        ld      a,h
        push    af
        ld      a,l
        ld      h,CRCT>>8
        ld      l,c
        ld      (hl),e
        inc     h
        ld      (hl),d
        inc     h
        ld      (hl),a
        inc     h
        pop     af
        ld      (hl),a
        inc     c
        jr      nz,.n
        ret
crcStart:
        ld      hl,$FFFF
        ld      (crcVal),hl
        ld      (crcVal+2),hl
        ret
crcFinish:
        ld      hl,crcVal
        ld      b,4
.l:     ld      a,(hl)
        cpl
        ld      (hl),a
        inc     hl
        djnz    .l
        ret
; HL = data, BC = count
crcUpdate:
        exx
        ld      de,(crcVal)
        ld      bc,(crcVal+2)                   ; E D C B = crc, low byte first
        exx
.l:     ld      a,b
        or      c
        jr      z,.done
        ld      a,(hl)
        inc     hl
        dec     bc
        exx
        xor     e
        ld      l,a
        ld      h,CRCT>>8
        ld      a,(hl)
        xor     d
        ld      e,a
        inc     h
        ld      a,(hl)
        xor     c
        ld      d,a
        inc     h
        ld      a,(hl)
        xor     b
        ld      c,a
        inc     h
        ld      b,(hl)
        exx
        jr      .l
.done:  exx
        ld      (crcVal),de
        ld      (crcVal+2),bc
        exx
        ret

; Z if the 4 bytes at HL and DE are equal
cmp4:   ld      b,4
.l:     ld      a,(de)
        cp      (hl)
        ret     nz
        inc     hl
        inc     de
        djnz    .l
        ret

; ---- slots: page 1 = RAM (the image) or MSX-DOS's own (disk ROM) --------------------------------
getSlot1:
        in      a,($A8)
        rrca
        rrca
        and     3
        ld      c,a
        ld      b,0
        ld      hl,EXPTBL
        add     hl,bc
        or      (hl)
        ret     p
        ld      c,a
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)
        and     $0C
        or      c
        ret
ram1:   push    af
        push    bc
        push    de
        push    hl
        ld      a,(RAMAD1)
        call    enaP1
        jr      slotDone
dos1:   push    af
        push    bc
        push    de
        push    hl
        ld      a,(dosSlot1)
        call    enaP1
        ei
slotDone:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
; A = slot: select it in page 1 through ENASLT, reached with CALSLT (page 0 is DOS RAM). Interrupts off.
enaP1:  di
        ld      h,$40
        ld      iy,(EXPTBL-1)
        ld      ix,ENASLT
        call    CALSLT
        di
        ret

; ---- leaving -----------------------------------------------------------------------------------
linkErr:
        ld      hl,msgLink
        jp      exitQuiet
piRefused:                                      ; the MSXPi's own message ("Pi:Er:..."), where the
        ld      hl,(pcDst)                      ; reply arrived
        jr      exitQuiet
romErr: ld      a,R_ROM
        jr      exitResult
; A = check number: a package this PLAYNET cannot use
badPkg: push    af
        ld      hl,msgBadPkg
        call    PRINT
        pop     af
        call    printHex
        ld      hl,msgParen
        ld      a,R_INCOMPAT
        jr      exitResult
; HL = message, A = result code: print, tell the MSXPi (session mode), back to MSX-DOS
exitResult:
        push    af
        call    PRINT
        call    PRINTNLINE
        pop     af
        ld      b,a
        ld      a,(manual)
        or      a
        jr      nz,toDos
        ld      a,b
        add     a,'0'
        ld      (cmdResultN),a
        ld      de,cmdResult
        ld      hl,BOUNCE
        ld      bc,256
        call    piCommand                       ; the chat says how it ended; failures do not matter here
        jr      toDos
exitQuiet:
        call    PRINT
        call    PRINTNLINE
toDos:  ld      c,F_TERM0
        jp      BDOS

printHex:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    .d
        pop     af
.d:     and     15
        add     a,'0'
        cp      '9'+1
        jr      c,.p
        add     a,7
.p:     jp      PUTCHAR

; ---- text ----------------------------------------------------------------------------------------
msgBanner:      defb    "PLAYNET 1 - online games for MSX",13,10,0
msgUsage:       defb    "Usage: PLAYNET  (started by MCHAT), or PLAYNET game role",0
msgNoTcp:       defb    "This PLAYNET works over the MSXPi only; TCP/IP is not built yet",0
msgLink:        defb    "Cannot talk to the MSXPi",0
msgTooBig:      defb    "The MSXPi sent more than PLAYNET can hold",0
msgBadSession:  defb    "The MSXPi sent no valid game session",0
msgNewer:       defb    "This game needs a newer PLAYNET",0
msgOwnProgram:  defb    "This game is not started by PLAYNET",0
msgChanged:     defb    "The game on the MSXPi changed since the invitation: invite again",0
msgBadPkg:      defb    "The game package cannot be used (check ",0
msgParen:       defb    ")",0
msgRole:        defb    "Unknown role for this game",0
msgNoRom:       defb    "Cannot open ",0
msgWrongRom:    defb    "The ROM file is not the dump this game was made for",0
msgReadErr:     defb    "Read error on the ROM file",0
msgLoading:     defb    "Loading the ROM...",13,10,0
msgConnect:     defb    "Connecting",0
msgTo:          defb    " to ",0
msgReady:       defb    13,10,"Connected, input delay ",0
msgIncompat:    defb    13,10,"The other player has a different version of the game",0
msgNoAnswer:    defb    13,10,"Could not connect to the other player",0
msgLeft:        defb    13,10,"The other player cancelled",0
msgCancel:      defb    13,10,"Cancelled",0
msgStart:       defb    "Starting ",0
magicPNS:       defb    "PNS1"
magicGPF:       defb    "GPF1"
zero4:          defb    0,0,0,0
cmdSession:     defb    "playnet session",0
cmdResult:      defb    "playnet result "
cmdResultN:     defb    "0",0
cmdProfile:     defb    "playnet profile "
cmdProfileId:   defs    10

        INCLUDE "include.asm"
        INCLUDE "putchar_clients.asm"
        INCLUDE "msxpi_bios.asm"
        INCLUDE "transport_msxpi.inc"

; ---- variables ------------------------------------------------------------------------------------
manual:         defb    0
seat:           defb    0
delay:          defb    0
stDelay:        defb    0
dosSlot1:       defb    0
gameId:         defs    9
roleArg:        defs    9
peer:           defs    9                       ; 8 bytes + a terminator
title:          defs    25
argBuf:         defs    41
sesBuf:         defs    64
fcb:            defs    37
gpfLen:         defw    0
secEnd:         defw    0
pSource:        defw    0
pNetplay:       defw    0
pLayout:        defw    0
pPatch:         defw    0
pRanges:        defw    0
pLayEnt:        defw    0
nAssets:        defb    0
assetTab:       defs    32                      ; 8 x (address, length)
np:                                             ; the fixed part of NETPLAY (17 bytes)
npBase:         defw    0
npW:            defb    0
npStubAsset:    defb    0
npStubLoad:     defw    0
npStubMax:      defw    0
npTArea:        defw    0
npTSize:        defw    0
npIrq:          defw    0
npStart:        defw    0
npRanges:       defb    0
srcSize:        defs    4                       ; SOURCE (20 bytes)
srcCrc:         defs    4
srcName:        defs    12
                defb    0
outSize:        defs    4                       ; LAYOUT header: size (4), fill, count
                defs    2
lyEnt:                                          ; one layout entry (13 bytes)
lySrc:          defb    0
lyOff:          defs    4
lySize:         defs    4
lyDest:         defs    4
imgEnd:         defw    0
stubSrc:        defw    0
stubLen:        defw    0
stubHi:         defw    0
tHi:            defw    0
ovLo:           defw    0
ovHi:           defw    0
chunkAt:        defw    0
chunkLen:       defw    0
pieceLo:        defw    0
t0:             defw    0
tDot:           defw    0
c9sp:           defw    0
pcDst:          defw    0
pcLim:          defw    0
pcIdx:          defb    0
pcBsz:          defw    0
pcCmd:          defw    0
crcVal:         defs    4
tBuf:           defs    TR_SIZE
programEnd:
        ASSERT  programEnd <= CRCT
