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
;   0100h-24FFh  this program          2500h-28FFh  CRC-32 tables (4 x 256)
;   2900h-34FFh  the GPF (3 KB)        3500h-3FFFh  disk bounce buffer (DOS cannot read into page 1),
;                                                   then the relocated transport at 3D00h
;   (PLAYNET /T: PLAYNET.OVL passes through 2500h-3FFFh on its way to its segment)
;   4000h-       the mapper-ram loader and other start-up code (in the file after programEnd, copied there
;                at the start), until the image is in
;   4000h-BFFFh  the game image        C000h-       the start-up trampoline, copied there at the end
; The game never maps page 0's RAM: this program is still here when the game ends, and pnBack brings
; MSX-DOS back (PROTOCOLS 14), using 4000h-BFFFh (the dead image) for the restore buffer and its stack.

PLAYNET_VERSION: EQU    3                     ; 3: image host mapper-ram (MegaROMs)
CAPS_KNOWN:      EQU    $01                   ; GPF header byte 99: bit 0 mapper-ram

F_TERM0:        EQU     $00
F_DIRIN:        EQU     $08                     ; console input, no echo
F_CONST:        EQU     $0B
F_OPEN:         EQU     $0F
F_CLOSE:        EQU     $10
F_WRRND:        EQU     $26
F_SETDTA:       EQU     $1A
F_RDRND:        EQU     $27
INIT32:         EQU     $006F
EXBRSA:         EQU     $FAF8
JIFFY:          EQU     $FC9E
SCRMOD:         EQU     $FCAF
KEYBUF:         EQU     $FBF0
PUTPNT:         EQU     $F3F8
GETPNT:         EQU     $F3FA

CRCT:           EQU     $2500
GPFBUF:         EQU     $2900
GPFMAX:         EQU     $0C00
BOUNCE:         EQU     $3500
CHUNK:          EQU     $0B00
TRAMP:          EQU     $C000
TRAMP_SP:       EQU     TRAMP+$100              ; the trampoline's stack (Soccer's stub starts at C100h)
        ASSERT  trLateEnd+128 <= TRAMP_SP        ; room under it: 86 bytes used with Soccer
        ASSERT  TRAMP+trampEnd-trampSrc+32 <= TRAMP_SP  ; and ENASLT's 32 above the copy part's variables
SV_HDR:         EQU     8                       ; the saved area (14): 'PNSV', start, length, then start-FFFEh
SV_MAX:         EQU     $4000-8                 ; under 16 KB (start >= C008h): a segment, or RBUF to C000h
RBUF:           EQU     $8000                   ; the MSXPi restore buffer: page 2, the game image's RAM
        ASSERT  RBUF+SV_HDR+SV_MAX <= $C000

R_LEFT:         EQU     2                       ; result codes (13.2)
R_CONNECT:      EQU     5
R_INCOMPAT:     EQU     6
R_CANCEL:       EQU     7
R_ROM:          EQU     8
R_MACHINE:      EQU     9

        org     $0100

start:  ld      hl,hiImage                      ; the page-1 part into place, before CRCT and the GPF
        ld      de,hiStart                      ; buffer (where it is in the file) are used
        ld      bc,hiEnd-hiStart
        ldir
        ld      hl,msgBanner
        call    PRINT
        call    resetMSXPI
        call    getSlot1
        ld      (dosSlot1),a
        call    parseArgs
        ld      a,(tcp)
        or      a
        call    nz,tcpSetup
        call    crcInit                         ; after tcpSetup: PLAYNET.OVL passes through the table's room
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
        cp      127
        jr      nc,usage
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
        jp      z,tcpArgs                       ; PLAYNET /T (playnet_tcp.asm)
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
usage:  ld      hl,msgUsage
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
        ld      a,(tcp)
        or      a
        jp      nz,tcpSession                   ; PLAYNET /T: from MCHAT /T's file
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
sesFields:
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

; HL = low, DE = high: CF if [low, high] overlaps the trampoline and its stack (TRAMP .. TRAMP_SP - 1)
overTramp:
        push    hl
        push    de
        ld      hl,TRAMP
        ld      (ovLo),hl
        ld      hl,TRAMP_SP-1
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

; CF if HL < BC (unsigned); HL, DE and BC are kept
cpHLDE.bc:
        push    de
        ld      d,b
        ld      e,c
        call    cpHLDE
        pop     de
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
        ld      hl,(fcb+18)                     ; (above 64 KB only with mapper-ram)
        ld      de,(srcSize+2)
        or      a
        sbc     hl,de
        ld      hl,msgWrongRom
        jp      nz,romErr
        ld      hl,msgLoading
        call    PRINT
        ld      a,(mHost)
        or      a
        jp      nz,mLoad
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
        ld      a,(mHost)
        or      a
        jp      nz,mPatch
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
        ld      a,(tcp)
        or      a
        jp      nz,tcpConnect
        ld      hl,msgConnect
        call    PRINT
mpConnect:                                      ; (link 2 joins here: tcpConnect has printed it)
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
        ld      a,(stK)
        ld      (kAgreed),a
        ld      hl,msgReady
        call    PRINT
        ld      a,(delay)
        add     a,'0'
        call    PUTCHAR
        jp      PRINTNLINE

; A = FLAGS (bit 7 set). C9, FLAGS, L = 0, SUM = 0 -> A0+state, delay, K. Out: A = state,
; (stDelay), (stK); CF when the link failed.
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
        ld      (stK),a
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
        ld      a,(hl)
        ld      (stubAbi),a
        inc     hl
        ld      a,(seat)
        ld      (hl),a
        inc     hl
        ld      a,(delay)
        ld      (hl),a
        inc     hl                              ; pnFlags: the build's
        inc     hl                              ; pnK
        ld      a,(kAgreed)
        ld      b,a
        ld      a,(stubAbi)
        cp      2
        jr      c,.noK                          ; an ABI 1 stub has no pnK (that byte is PN_TICK's code)
        ld      (hl),b                          ; pnK
.noK:
        ld      a,(tcp)                         ; the transport, relocated to its area
        or      a
        jr      z,.pi
        call    tcpTransport                    ; TCP/IP UNAPI (playnet_tcp.asm)
        jr      .len
.pi:    ld      hl,trImage                      ; the MSXPi's
        ld      de,tBuf
        ld      bc,TR_SIZE
        ldir
        ld      hl,trRelocs
        call    relocate
        ld      hl,(npIrq)
        ld      (tBuf+TR_IRQ),hl
.len:   ld      a,(npW)                         ; L = 14 + 8W: 8 records of W inputs and a count
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
        ld      a,(mHost)                       ; mapper-ram: the start pairs into pages 1 and 2
        ld      (vMap),a
        or      a
        jr      z,.nm
        ld      ix,(mBlk)
        ld      a,(ix+8)
        ld      (vSeg1),a
        ld      a,(ix+9)
        ld      (vSeg2),a
.nm:
        ld      hl,TR_SIZE
        ld      a,(tcp)
        or      a
        jr      z,.tl
        ld      hl,TU_SIZE
        ld      a,(hyb)
        or      a
        jr      z,.hs
        ld      hl,TH_SIZE
.hs:    ld      a,(g3Seg)                       ; and the game's own page 3
        ld      (vG3),a
        ld      a,(gameSeg2)
        ld      (vGame2),a
        push    hl
        ld      hl,(mapTab)
        ld      de,M_PUT_P2
        add     hl,de
        ld      (vPut),hl
        pop     hl
.tl:    ld      (vTLen),hl
        call    saveDos
        ld      a,(tcp)
        or      a
        jr      z,.go
        ld      hl,(JIFFY)                      ; netcore's clock goes on from JIFFY's value
        ld      (tBuf+TU_TICKS),hl
.go:    di
        jp      TRAMP

; HL = a relocation list: the words in tBuf to move by npTArea, each as its distance from the last one (from
; tBuf-1 at first), one byte each, 0 at the end (build.py)
relocate:
        ld      de,tBuf-1
.next:  ld      a,(hl)
        or      a
        ret     z
        inc     hl
        add     a,e
        ld      e,a
        jr      nc,.w
        inc     d
.w:     push    hl
        push    de
        ex      de,hl
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
        pop     de
        pop     hl
        jr      .next

; Runs from C000h. Copies the stub and the transport into page 3 (MSX-DOS is gone from here on),
; then starts the game with page 0 = main BIOS and page 1 = the RAM holding it.
; Its own stack ends at TRAMP_SP: MSX-DOS's can be in the stub's area (D53Fh under MSX-DOS 1 on the V-25), where
; ENASLT, INIT32 and their interrupts would push. That stack goes down to about C0AAh (Soccer), over the copy part
; (.early, run first and placed last); what runs after INIT32 is at the start. The game starts on MSX-DOS's stack, as before.
trampSrc:
        PHASE   TRAMP
        ld      (vDosSp),sp
        ld      sp,TRAMP_SP
        jp      trEarly
trLate: ld      hl,$FD9A                        ; hooks left by DOS that point outside the BIOS become
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
.go:    push    hl
        call    INIT32                          ; SCREEN 1, as before a cartridge INIT
        pop     hl
        ld      sp,(vDosSp)
        jp      (hl)
vStart:         defw    0
vBase:          defw    0
vDosSp:         defw    0
trLateEnd:
trEarly:
        ld      hl,tBuf
        ld      de,(vTDst)
        ld      bc,(vTLen)
        ldir
        ld      a,(vG3)                         ; TCP/IP: the game gets a page 3 of its own, a copy of
        or      a                               ; MSX-DOS's (this code and the transport are in it)
        jr      z,.p3
        call    .put
        ld      hl,$C000
        ld      de,$8000
        ld      bc,$3FFF                        ; not FFFFh: the sub-slot register
        ldir
        ld      a,(vGame2)
        call    .put
        ld      a,(vG3)
        out     ($FF),a
.p3:    ld      hl,(vStubSrc)                   ; the stub: TCP/IP, in G3 only (MSX-DOS's page 3 keeps what
        ld      de,(vStubDst)                   ; it has there, above its TPA top)
        ld      bc,(vStubLen)
        ldir
        ld      a,$C9                           ; no MSX-DOS timer hook (in G3 only, on the TCP/IP path)
        ld      ($FD9F),a
        ld      a,(EXPTBL)                      ; main BIOS slot into page 0
        and     3
        ld      c,a
        in      a,($A8)
        and     $FC
        or      c
        out     ($A8),a
        ld      a,(vMap)                        ; mapper-ram: the segments of the start pairs
        or      a
        jr      z,.ram
        ld      a,(vSeg1)
        out     ($FD),a
        ld      a,(vSeg2)
        out     ($FE),a
.ram:   ld      a,(vRam1)                       ; RAM, holding the game, into page 1
        ld      h,$40
        call    ENASLT
        di
        jp      trLate
.put:   ld      hl,(vPut)                       ; A = segment: MSX-DOS's PUT_P2
        jp      (hl)
vStubSrc:       defw    0
vStubDst:       defw    0
vStubLen:       defw    0
vTDst:          defw    0
vRam1:          defb    0
vTLen:          defw    0                       ; the transport's length
vG3:            defb    0                       ; TCP/IP: the game's page-3 segment, else 0
vGame2:         defb    0                       ; TCP/IP: the TPA's page-2 segment
vMap:           defb    0                       ; mapper-ram: 1, and the start pairs' segments
vSeg1:          defb    0
vSeg2:          defb    0
vPut:           defw    0                       ; TCP/IP: MSX-DOS's PUT_P2
        DEPHASE
trampEnd:

; ---- the return to MSX-DOS (PROTOCOLS 14) ---------------------------------------------------------
; Before the game: MSX-DOS's area up to FFFEh goes to the MSXPi ("playnet save"); the slot registers stay here and in the
; transport. The game never maps page 0's RAM, so this program is still there when XEND comes back to pnBack.
saveDos:
        ld      hl,(HIMEM)                      ; the area starts at HIMEM, or lower where the game's RAM
        ld      (svStart),hl                    ; reaches below it: MSX-DOS 2 keeps code and data between
        ld      a,(npRanges)                    ; the TPA top and HIMEM (Nextor: DC06h-E6FDh; MSX-DOS 1: its
        ld      b,a                             ; code), and Soccer uses E000h-F37Fh. The TPA is not kept.
        ld      hl,(pRanges)
.rng:   ld      e,(hl)
        inc     hl
        ld      d,(hl)                          ; DE = low
        inc     hl
        ld      a,(hl)
        inc     hl
        push    hl
        ld      h,(hl)
        ld      l,a                             ; HL = high
        call    svLow
        pop     hl
        inc     hl
        djnz    .rng
        ld      de,(npStubLoad)                 ; the stub and the transport are written there too
        ld      hl,(npStubMax)
        call    svArea
        ld      de,(npTArea)
        ld      hl,(npTSize)
        call    svArea
        ld      hl,(svStart)
        ld      de,$10000-SV_MAX
        call    cpHLDE
        jr      c,.no                           ; below C000h: more than the MSXPi keeps
        ex      de,hl
        ld      hl,$FFFF                        ; start-FFFEh: FFFFh - start bytes
        or      a
        sbc     hl,de
        ld      (svLen),hl
        in      a,($A8)
        ld      (tBuf+TR_DOSA8),a
        rlca                                    ; page 3's primary slot: is it expanded?
        rlca
        and     3
        ld      e,a
        ld      d,0
        ld      hl,EXPTBL
        add     hl,de
        ld      a,(hl)
        and     $80
        ld      a,($FFFF)
        jr      z,.flat                         ; no: FFFFh is RAM, kept as it is
        cpl                                     ; yes: the sub-slot register
.flat:  ld      (svFFFF),a
        ld      (tBuf+TR_DOSSUB),a
        ld      a,(tcp)
        or      a
        jr      z,.pi
        call    tcpSave                         ; TCP/IP: into the save segment
        jr      .saved
.pi:    ld      a,1
        ld      (pcUp),a
        ld      de,cmdSave
        ld      hl,BOUNCE
        ld      bc,256
        call    piCommand
        ld      hl,pcUp
        ld      (hl),0
        jr      c,.lost
        cp      RC_SUCCESS
        jr      nz,.no
.saved: ld      hl,pnBack
        ld      (tBuf+TR_RET),hl
        ret
.lost:  call    resetMSXPI
.no:    ld      hl,msgNoSave                    ; the game still runs, and ends with a reset
        call    PRINT
        jp      PRINTNLINE

; DE = the start of an area the game writes, HL = its size
svArea: dec     hl
        add     hl,de
; DE = low, HL = high (inclusive) of an area the game writes: the saved area starts at its part above the TPA top
; (all of it, or from the TPA top when it straddles it: a stub low in page 3 may run over MSX-DOS 1's code) when
; that is below the start so far. Keeps B.
svLow:  push    de
        ld      de,($0006)
        call    cpHLDE
        pop     hl                              ; HL = low
        ret     c                               ; all in the TPA
        call    cpHLDE
        jr      nc,.above
        ex      de,hl                           ; from the TPA top
.above: ld      de,(svStart)
        call    cpHLDE
        ret     nc
        ld      (svStart),hl                    ; below the start so far
        ret

; "playnet save", after the command: the header and the area as one transfer that the MSXPi's recvdata2
; takes (one handshake, blocks of at most MAXBUFSIZE, RC_READY on all but the last). CF on a link error.
sendSave:
.hs:    ld      a,READY
        call    PIWRITEBYTE
        ret     c
        call    PIREADBYTE
        ret     c
        cp      READY_ACK
        jr      nz,.hs
        ld      a,MAXBUFSIZE_LO
        call    PIWRITEBYTE
        ret     c
        ld      a,MAXBUFSIZE_HI
        call    PIWRITEBYTE
        ret     c
        xor     a
        ld      (sbIdx),a
        ld      hl,svHdr
        ld      bc,SV_HDR
        ld      a,RC_READY
        call    sendBlk
        ret     c
        ld      hl,(svStart)
        ld      (sbSrc),hl
        ld      hl,(svLen)
        ld      (sbLeft),hl
.next:  ld      hl,(sbLeft)
        ld      de,MAXBUFSIZE+1
        call    cpHLDE
        ld      b,h
        ld      c,l
        ld      a,RC_SUCCESS
        jr      c,.size                         ; the rest fits one block: the last one
        ld      bc,MAXBUFSIZE
        ld      a,RC_READY
.size:  push    af
        ld      hl,(sbLeft)
        or      a
        sbc     hl,bc
        ld      (sbLeft),hl
        ld      hl,(sbSrc)
        push    hl
        add     hl,bc
        ld      (sbSrc),hl
        pop     hl
        pop     af
        push    af
        call    sendBlk
        pop     de                              ; D = this block's header code
        ret     c
        ld      a,d
        cp      RC_READY
        jr      z,.next
        or      a
        ret

; one block: HL = data, BC = length, A = header code (RC_READY / RC_SUCCESS). Resent on a checksum
; mismatch, as SENDDATA does. CF on an error.
sendBlk:
        ld      (sbRc),a
        ld      (sbPtr),hl
        ld      (sbLen),bc
        ld      a,SENDRETRIES
        ld      (sbTry),a
.try:   ld      a,(sbRc)
        call    PIWRITEBYTE
        ret     c
        ld      a,(sbLen)
        call    PIWRITEBYTE
        ret     c
        ld      a,(sbLen+1)
        call    PIWRITEBYTE
        ret     c
        ld      a,(sbIdx)
        call    PIWRITEBYTE
        ret     c
        ld      de,(sbPtr)
        ld      bc,(sbLen)
        ld      hl,0
        call    PAYLOAD_TX
        ret     c
        ld      a,l
        add     a,h
        ld      (sbSum),a
        call    PIWRITEBYTE                     ; our checksum, then the MSXPi's
        ret     c
        call    PIREADBYTE
        ret     c
        ld      hl,sbSum
        cp      (hl)
        jr      z,.ok
        ld      hl,sbTry
        dec     (hl)
        jr      nz,.try
        scf
        ret
.ok:    call    PIREADBYTE                      ; READY, its status, then our READY_ACK
        ret     c
        cp      READY
        scf
        ret     nz
        call    PIREADBYTE
        ret     c
        cp      RC_SUCCESS
        scf
        ret     nz
        ld      a,READY_ACK
        call    PIWRITEBYTE
        ret     c
        ld      hl,sbIdx
        inc     (hl)
        or      a
        ret

; XEND comes here (the transport's xBack) with MSX-DOS's slots, interrupts off, A = the result code and
; B, C = the game's slot registers. Fetch the saved area, put it back, set up the screen MSX-DOS had and
; leave to it with MCHAT typed. If any of that fails: the transport's reset (xBoot, with B and C).
pnBack:
        ld      sp,($0006)                      ; under MSX-DOS's TPA top (page 0 is its RAM again): not page 0
                                                ; (CALSLT), 1 (MSR's routines map it), 2 (RBUF, segments)
        ld      (bkSlots),bc
        ld      (bkCode),a
        ld      a,(mHost)                       ; mapper-ram: MSX-DOS's own segments in pages 1 and 2
        or      a
        call    nz,mUnmap
        ld      a,8                             ; the PSG's three channels silent
        ld      b,3
.psg:   out     ($A0),a
        ld      c,a
        xor     a
        out     ($A1),a
        ld      a,c
        inc     a
        djnz    .psg
        ld      a,(svMode)
        or      a
        jr      z,.pi
        call    freeSegs                        ; TCP/IP: MSX-DOS's page 3 is as it was: nothing to restore
        jr      .screen
.pi:    call    resetMSXPI
        ld      de,cmdRestore
        ld      hl,RBUF
        ld      bc,SV_HDR+SV_MAX+1
        call    piCommand
        jr      c,.fail
        cp      RC_SUCCESS
        jr      nz,.fail
        ld      hl,(svLen)                      ; all of it, and with our header
        ld      de,SV_HDR
        add     hl,de
        or      a
        sbc     hl,bc
        jr      nz,.fail
        ld      hl,RBUF
        ld      de,svHdr
        ld      b,SV_HDR
.chk:   ld      a,(de)
        cp      (hl)
        jr      nz,.fail
        inc     hl
        inc     de
        djnz    .chk
        ld      de,(svStart)                    ; HL = RBUF + SV_HDR
        ld      bc,(svLen)
        ldir
.back:  ld      a,(svFFFF)
        ld      ($FFFF),a                       ; MSX-DOS's sub-slot register, or its RAM byte
.screen:
        ei                                      ; MSX-DOS's page 3 and hooks are back; the MSX2 BIOS
        ld      ix,INITXT                       ; waits for interrupts while it sets the screen up
        ld      a,(SCRMOD)
        or      a
        jr      z,.scr
        ld      ix,INIT32
.scr:   ld      iy,(EXPTBL-1)
        call    CALSLT
        ld      a,(bkCode)
        call    tcpResult                       ; MCHAT /T's game: the result into PLAYNET.SES
        di
        call    typeMchat
.dos:   jp      0                               ; MSX-DOS warm start
.fail:  ld      hl,(npTArea)
        ld      de,TR_BOOT
        add     hl,de
        ld      bc,(bkSlots)
        jp      (hl)

; ---- MSXPi commands --------------------------------------------------------------------------
; DE = command (zero-terminated), HL = destination, BC = room. Receives every block of the reply.
; With pcUp set, "playnet save" sends the saved area right after the command (sendSave).
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
        ld      a,(pcUp)
        or      a
        call    nz,sendSave
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
        ld      a,(tcp)
        or      a
        jr      z,.pi
        ld      a,b
        call    tcpResult
        call    typeMchat                       ; and back to the chat, which says why
        jr      toDos
.pi:    ld      a,b
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
toDos:  ld      a,(tcp)
        or      a
        call    nz,tcpCleanup
        ld      c,F_TERM0
        jp      BDOS

; A = result code: into PLAYNET.SES when this is MCHAT /T's game (PLAYNET /T alone)
tcpResult:
        ld      b,a
        ld      a,(manual)
        or      a
        ret     nz
        ld      a,(tcp)
        or      a
        ret     z
        ld      a,b
        jp      sesResult

; MCHAT and Enter in the keyboard buffer, for MSX-DOS: MCHAT /T after a TCP/IP game
typeMchat:
        ld      hl,keysMchat
        ld      bc,6
        ld      a,(tcp)
        or      a
        jr      z,.keys
        ld      hl,keysMchatT
        ld      bc,9
.keys:  ld      de,KEYBUF
        ldir
        ld      (PUTPNT),de
        ld      hl,KEYBUF
        ld      (GETPNT),hl
        ret

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
msgBanner:      defb    "PLAYNET 3 - online games for MSX",13,10,0
msgUsage:       defb    "Usage: PLAYNET  (started by MCHAT), PLAYNET game role,",13,10
                defb    "       PLAYNET /T [/S0|/S1] [/K1..3] [/L0..9] (started by MCHAT /T), or",13,10
                defb    "       PLAYNET /T [options] game role port ip:port[,ip:port]",0
msgNoSes:       defb    "No game waiting in PLAYNET.SES (start it from MCHAT /T)",0
nameSes:        defb    "PLAYNET SES"
sesEnd:         defb    2,0                     ; state ended, result code
bkCode:         defb    0
msgNoMapper:    defb    "TCP/IP needs a memory mapper and its routines (MSX-DOS 2, or MSR I on MSX-DOS 1)",0
msgNoSeg:       defb    "No free memory mapper segment",0
msgNoOvl:       defb    "Cannot load PLAYNET.OVL (it must be in the current directory)",0
msgNoGpf:       defb    "Cannot read the game package (ID.GPF in the current directory)",0
msgFootprint:   defb    "The TCP/IP driver uses memory this game overwrites. Restart the MSX holding CTRL (frees 1.5 KB), or use Nextor",0
msgNoTcpip:     defb    "No TCP/IP UNAPI found: run INL I first",0
msgNoPort:      defb    "Cannot open the UDP port",0
nameOvl:        defb    "PLAYNET OVL"
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
cmdSave:        defb    "playnet save",0
cmdRestore:     defb    "playnet restore",0
keysMchat:      defb    "MCHAT",13
keysMchatT:     defb    "MCHAT /T",13
msgNoSave:      defb    "MSX-DOS could not be saved: the game will end with a reset",0
cmdResult:      defb    "playnet result "
cmdResultN:     defb    "0",0
cmdProfile:     defb    "playnet profile "
cmdProfileId:   defs    10

        INCLUDE "include.asm"
        INCLUDE "putchar_clients.asm"
        INCLUDE "msxpi_bios.asm"
        INCLUDE "transport_msxpi.inc"
        INCLUDE "transport_unapi.inc"
        INCLUDE "transport_hybrid.inc"
        INCLUDE "playnet_tcp.asm"

; ---- variables ------------------------------------------------------------------------------------
manual:         defb    0
seat:           defb    0
delay:          defb    0
stDelay:        defb    0
stK:            defb    1                       ; the Pi's send interval K (status reply)
stubAbi:        defb    0                       ; the stub's ABI version (its header byte 0)
kAgreed:        defb    1                       ; the agreed K, for the stub's header
dosSlot1:       defb    0
gameId:         defs    9
roleArg:        defs    9
peer:           defs    9                       ; 8 bytes + a terminator
title:          defs    25
argBuf:         EQU     GPFBUF                  ; the command line, 128 bytes: parsed (and copied out) before
                                                ; anything comes into GPFBUF
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
tBuf:           EQU     BOUNCE+$800             ; the relocated transport, until the trampoline copies it
        ASSERT  tBuf+TR_SIZE <= BOUNCE+CHUNK
        ASSERT  tBuf+TU_SIZE <= BOUNCE+CHUNK
        ASSERT  tBuf+TH_SIZE <= BOUNCE+CHUNK
        ASSERT  GPFBUF+GPFMAX+BLKSIZE <= BOUNCE+$800  ; a GPF's last block from the MSXPi may run into BOUNCE
tcp:            defb    0                       ; 1: PLAYNET /T (playnet_tcp.asm)
lport:          defw    0
ncand:          defb    0
cands:          defs    18                      ; 3 x (ip 4, port 2)
mapTab:         defw    0                       ; the mapper support routines
ovlSeg:         defb    0
g3Seg:          defb    0                       ; the game's page 3 (TCP/IP)
gameSeg1:       defb    0                       ; the TPA's pages 1 and 2 (TCP/IP; this order)
gameSeg2:       defb    0
dosSeg3:        defb    0
segsHeld:       defb    0
hz:             defb    60
kMode:          defb    0                       ; PLAYNET /T /K1../K3: the send interval to announce (0: by the stack)
lMode:          defb    $FF                     ; /L0../L9: the service latency to announce, in frames ($FF: by the stack)
svcMode:        defb    2                       ; PLAYNET /T /S0, /S1: the TCP/IP stack's service (2: by the stack found)
hyb:            defb    0                       ; link 2 (/H, or the session's): the game's packets through the MSXPi
ovlLen:         defw    0
ovlIo:          defw    0
ovlOpen:        defb    0
svMode:         defb    0                       ; 2: nothing saved (TCP/IP: the game has its own page 3)
rfLen:          defw    0
nameGpf:        defs    8
                defb    "GPF"
pcUp:           defb    0                       ; 1: piCommand uploads the saved area (sendSave)
svHdr:          defb    "PNSV"                  ; the saved area's header (SV_HDR bytes)
svStart:        defw    0                       ; where the area starts: HIMEM, or lower (saveDos)
svLen:          defw    0                       ; bytes from the start to FFFEh
svFFFF:         defb    0                       ; what to write back at FFFFh
bkSlots:        defw    0                       ; the game's slot registers, for the fallback reset
sbIdx:          defb    0
sbSrc:          defw    0
sbLeft:         defw    0
sbRc:           defb    0
sbPtr:          defw    0
sbLen:          defw    0
sbTry:          defb    0
sbSum:          defb    0
crcVal:         defs    4
mHost:          defb    0                       ; image host: 0 plain, 1 mapper-ram
        INCLUDE "mapper_low.asm"                ; the mapper-ram loader's page-0 part
programEnd:
        ASSERT  programEnd <= CRCT               ; PLAYNET /T loads PLAYNET.OVL through CRCT-3FFFh
; Page 1: code that runs only before the image is in RAM. start copies it to 4000h; a plain game's image lands
; over it later, and a mapper-ram game never maps an image there.
hiImage:
        DISP    $4000
hiStart:
        INCLUDE "playnet_gpf.asm"               ; the game package: fetched, checked, parsed
        INCLUDE "mapper_host.asm"               ; the mapper-ram loader
hiEnd:
        ENT
