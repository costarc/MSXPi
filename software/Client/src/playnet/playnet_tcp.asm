; PLAYNET /T: the TCP/IP UNAPI path (documents/PLAYNET-DESIGN.md 5.4, 5.5; PROTOCOLS 10).
; Included by playnet.asm.
;
;   PLAYNET /T                                          the game MCHAT /T launched (PLAYNET.SES, PROTOCOLS 13)
;   PLAYNET /T game role lport ip:port[,ip:port[,ip:port]]      a manual start
;
; A memory mapper is required: one segment holds PLAYNET.OVL (netcore, from the current directory), one is
; the game's page 3 (G3): the trampoline copies MSX-DOS's page 3 into it and switches to it, so the game
; never touches MSX-DOS's (whose work area the TCP/IP stack uses) and nothing has to be saved for the
; return. The overlay is called with its segment in page 2, recorded with PUT_P2: a RAM implementation's
; helper puts back the page-2 segment the mapper routines last recorded.

EXTBIO:         EQU     $FFCA
OVL_INIT:       EQU     $8000
OVL_OPEN:       EQU     $8003
OVL_POLL:       EQU     $8006
OVL_BYE:        EQU     $800C
OVL_CLOSE:      EQU     $800F
OVL_VERSION:    EQU     $8012
BR_DOS:         EQU     $801E                   ; the bridge's variables (netcore/ovl_crt0.s)
BR_GAME3:       EQU     $801F
BR_STACK:       EQU     $8020
BR_PUTP2:       EQU     $8022
BR_POST:        EQU     $8025
BR_OVL:         EQU     $8027
BR_BLK:         EQU     $8028
BR_TICK:        EQU     $802A
BR_TAIL:        EQU     $802C
OVL_IOPTR:      EQU     $8013
OVLTMP:         EQU     CRCT                    ; the overlay passes through here before the CRC table is
OVLMAX:         EQU     $4000-CRCT              ; built and the GPF read: CRCT, GPFBUF and BOUNCE (7 KB)
M_ALL_SEG:      EQU     $00                     ; mapper support routines (MSX-DOS 2 / Nextor / MSR)
M_FRE_SEG:      EQU     $03
M_GET_P1:       EQU     $21
M_PUT_P2:       EQU     $24
M_GET_P2:       EQU     $27
M_GET_P3:       EQU     $2D
IO_TICKS:       EQU     0                       ; the overlay's I/O block (netcore/ovl_main.c)
IO_HZ:          EQU     2
IO_BUF:         EQU     3
IO_PROFILE:     EQU     5
IO_VERSION:     EQU     9
IO_FORCE:       EQU     10
IO_LPORT:       EQU     11
IO_NCAND:       EQU     13
IO_CAND:        EQU     14
IO_STATUS:      EQU     37
IO_DELAY:       EQU     38
IO_REASON:      EQU     39
IO_IRC:         EQU     133
IO_SERVICE:     EQU     134
IO_KWANT:       EQU     135
IO_SWANT:       EQU     136
IO_K:           EQU     137

; ---- the command line (HL at the '/') -----------------------------------------------------------------
tcpArgs:
        inc     hl
        ld      a,(hl)
        call    lower
        cp      't'
        jp      nz,usage
        inc     hl
        ld      a,1
        ld      (tcp),a
        call    skipSp
.opt:   ld      a,(hl)
        cp      '/'
        jr      nz,.noopt
        inc     hl                              ; /S0, /S1: force the stack service off or on (default: by the stack)
        ld      a,(hl)
        call    lower
        ld      c,a
        inc     hl
        ld      a,(hl)
        sub     '0'
        ld      b,a                             ; B = the digit
        ld      a,c
        cp      's'                             ; /S0, /S1: the stack's service
        jr      nz,.nk
        ld      a,b
        cp      2
        jp      nc,usage
        ld      (svcMode),a
        jr      .optEnd
.nk:    cp      'k'                             ; /K1../K3: the send interval to announce
        jr      nz,.nl
        ld      a,b
        dec     a
        cp      3
        jp      nc,usage
        inc     a
        ld      (kMode),a
        jr      .optEnd
.nl:    cp      'l'                             ; /L0../L9: the service latency to announce, in frames
        jr      z,.isl
        cp      'h'                             ; /H: link 2, the game's packets through this machine's MSXPi
        jp      nz,usage
        ld      (hyb),a                         ; (A = 'h': not zero)
        jr      .optEnd
.isl:   ld      a,b
        cp      10
        jp      nc,usage
        ld      (lMode),a
.optEnd:
        inc     hl
        call    skipSp
        jr      .opt
.noopt: or      a
        ret     z                               ; /T alone: the session in PLAYNET.SES (tcpSession)
        ld      a,1
        ld      (manual),a
        ld      de,gameId
        call    word
        call    skipSp
        ld      de,roleArg
        call    word
        call    skipSp
        ld      a,(hyb)
        or      a
        jr      z,.lp
        ld      a,(roleArg)                     ; /H game role: the Pi has the opponent (MSXPI_NETPLAY or "playnet peers")
        or      a
        jp      z,usage
        ret
.lp:    call    number
        jp      c,usage
        ld      (lport),de
        call    skipSp
        ld      ix,cands
        ld      b,0
.cand:  push    bc
        call    ipPort
        pop     bc
        jp      c,usage
        inc     b
        ld      a,(hl)
        cp      ','
        jr      nz,.done
        ld      a,b
        cp      3
        jr      z,.done
        inc     hl
        ld      de,6
        add     ix,de
        jr      .cand
.done:  ld      a,b
        ld      (ncand),a
        ld      a,(roleArg)
        or      a
        jp      z,usage
        ret

; HL = text: a decimal number into DE (at least one digit). CF if none or too big.
number: ld      de,0
        ld      a,(hl)
        sub     '0'
        cp      10
        ccf
        ret     c
.d:     ld      a,(hl)
        sub     '0'
        cp      10
        jr      nc,.end                         ; not a digit: done
        push    hl
        ld      h,d
        ld      l,e
        add     hl,hl                           ; DE * 10 + digit
        jr      c,.big
        add     hl,hl
        jr      c,.big
        add     hl,de
        jr      c,.big
        add     hl,hl
        jr      c,.big
        ld      e,a
        ld      d,0
        add     hl,de
        jr      c,.big
        ex      de,hl
        pop     hl
        inc     hl
        jr      .d
.big:   pop     hl
        scf
        ret
.end:   or      a
        ret

; HL = "a.b.c.d:port" -> IX+0..3 the address, IX+4,5 the port. CF on a syntax error.
ipPort: ld      b,4
        push    ix
        pop     iy
.oct:   call    number
        ret     c
        ld      a,d
        or      a
        scf
        ret     nz                              ; above 255
        ld      (iy+0),e
        inc     iy
        dec     b
        jr      z,.port
        ld      a,(hl)
        cp      '.'
        scf
        ret     nz
        inc     hl
        jr      .oct
.port:  ld      a,(hl)
        cp      ':'
        scf
        ret     nz
        inc     hl
        call    number
        ret     c
        ld      (ix+4),e
        ld      (ix+5),d
        or      a
        ret

; ---- mapper, segments, the overlay -----------------------------------------------------------------
tcpSetup:
        ld      hl,($F349)                      ; HIMSAV: MSR lowers it for its page 3 block but not HIMEM (FC4Ah). A ROM
        ld      a,h                             ; implementation that allocates on first use, below HIMEM (SM-X WiFi), would
        cp      $C0                             ; land on MSR's table: bring HIMEM down to HIMSAV before the first call
        jr      c,.himem
        ld      de,($FC4A)
        or      a
        sbc     hl,de
        jr      nc,.himem                       ; HIMSAV >= HIMEM: nothing to do
        add     hl,de
        ld      ($FC4A),hl
.himem: xor     a                               ; the mapper support routines
        ld      de,$0402
        ld      hl,0
        call    EXTBIO
        ld      (mapTab),hl
        ld      a,h
        or      l
        ld      hl,msgNoMapper
        ld      a,R_MACHINE
        jp      z,exitResult
        call    allSeg
        ld      (ovlSeg),a
        call    allSeg
        ld      (g3Seg),a
        ld      a,M_GET_P1                      ; the game's pages 1 and 2 are the TPA's (mapper-ram:
        call    mapper                          ; until the trampoline maps the start pairs)
        ld      (gameSeg1),a
        ld      a,M_GET_P2
        call    mapper
        ld      (gameSeg2),a
        ld      a,M_GET_P3                      ; and MSX-DOS's page 3
        call    mapper
        ld      (dosSeg3),a
        ld      a,(EXPTBL)                      ; 50 or 60 Hz: bit 7 of the BIOS ID byte at 002Bh
        ld      hl,$002B
        call    RDSLT
        ei
        ld      b,60
        rlca
        jr      nc,.hz
        ld      b,50
.hz:    ld      a,b
        ld      (hz),a
        ld      hl,nameOvl                      ; PLAYNET.OVL, through OVLTMP into its segment
        ld      de,OVLTMP
        ld      bc,OVLMAX
        call    readFile
        ld      hl,msgNoOvl
        jp      c,exitQuiet
        ld      (ovlLen),bc
        ld      a,(ovlSeg)
        call    putP2
        ld      hl,OVLTMP
        ld      de,OVL_INIT
        ld      bc,(ovlLen)
        ldir
        ld      a,(OVL_VERSION)
        dec     a
        jr      nz,.bad
        ld      hl,(OVL_IOPTR)
        ld      (ovlIo),hl
        call    OVL_INIT
        call    unmapOvl
        ret
.bad:   call    unmapOvl
        ld      hl,msgNoOvl
        jp      exitQuiet

allSeg: xor     a                               ; a user segment of the primary mapper
        ld      b,a
        ld      hl,(mapTab)
        call    jpHL
        jr      c,.none
        ld      hl,segsHeld
        inc     (hl)
        ret
.none:  ld      hl,msgNoSeg
        ld      a,R_MACHINE
        jp      exitResult

; A = offset in the mapper routine table: call it (A, BC, DE, HL as the routine wants are lost: for
; GET_P2 and friends only)
mapper: ld      hl,(mapTab)
        add     a,l
        ld      l,a
        jr      nc,jpHL
        inc     h
jpHL:   jp      (hl)

; A = segment into page 2, through PUT_P2. Keeps BC, DE, HL.
putP2:  push    hl
        push    de
        push    bc
        ld      hl,.ret
        push    hl
        ld      hl,(mapTab)
        ld      de,M_PUT_P2
        add     hl,de
        jp      (hl)
.ret:   pop     bc
        pop     de
        pop     hl
        ret
mapOvl: ld      a,(ovlSeg)
        jp      putP2
unmapOvl:
        ld      a,(gameSeg2)
        jp      putP2

; HL = 11-character FCB name, DE = destination, BC = room. Reads the whole file. Out: BC = its size; CF
; if it cannot be opened, is empty or too big, or a read fails. Uses fcb.
readFile:
        push    bc
        push    de
        ld      de,fcb+1
        ld      bc,11
        ldir
        ld      hl,fcb                          ; the rest of the FCB zero, drive 0
        ld      (hl),0
        ld      hl,fcb+12
        ld      b,37-12
.z:     ld      (hl),0
        inc     hl
        djnz    .z
        ld      de,fcb
        ld      c,F_OPEN
        call    BDOS
        pop     de
        pop     bc
        inc     a
        scf
        ret     z
        ld      hl,(fcb+18)                     ; above 64 KB
        ld      a,h
        or      l
        scf
        ret     nz
        ld      hl,(fcb+16)
        ld      a,h
        or      l
        scf
        ret     z
        push    hl
        or      a
        sbc     hl,bc
        pop     hl
        ccf
        ret     c                               ; bigger than the room
        ld      (rfLen),hl
        push    de
        ld      hl,1
        ld      (fcb+14),hl
        ld      hl,0
        ld      (fcb+33),hl
        ld      (fcb+35),hl
        pop     de
        ld      c,F_SETDTA
        call    BDOS
        ld      de,fcb
        ld      hl,(rfLen)
        ld      c,F_RDRND
        call    BDOS
        or      a
        scf
        ret     nz
        ld      bc,(rfLen)
        or      a                               ; CF clear: read
        ret

; ---- the session MCHAT /T wrote (PROTOCOLS 13.1): PLAYNET.SES, 256 bytes; the first 64 are PLAYNET's ----
tcpSession:
        ld      hl,nameSes
        ld      de,BOUNCE
        ld      bc,257
        call    readFile
        jr      c,.bad
        ld      hl,BOUNCE
        ld      de,sesBuf
        ld      bc,64
        ldir
        ld      hl,sesBuf
        ld      de,magicPNS
        call    cmp4
        jr      nz,.bad
        ld      a,(sesBuf+9)                    ; link: 1 TCP/IP, 2 TCP/IP chat with the game through the MSXPi
        cp      2
        jr      nz,.l1
        ld      (hyb),a
        jr      .l2
.l1:    dec     a
        jr      nz,.bad
.l2:    ld      a,(sesBuf+32)                   ; state: launched, not ended yet
        or      a
        jr      nz,.bad
        ld      a,(hyb)
        or      a
        jp      nz,sesFields                    ; link 2: no addresses, the Pi has them
        ld      a,(sesBuf+40)                   ; 1 to 3 addresses
        or      a
        jr      z,.bad
        cp      4
        jr      nc,.bad
        ld      (ncand),a
        ld      hl,(sesBuf+10)
        ld      (lport),hl
        ld      hl,sesBuf+41
        ld      de,cands
        ld      bc,18
        ldir
        jp      sesFields                       ; seat, game id, peer: as from the MSXPi
.bad:   ld      hl,msgNoSes
        jp      exitQuiet

; A = the result code: PLAYNET.SES gets state 2 (ended) and the code (13.1, bytes 32-33), for MCHAT /T.
; Failures do not matter here (MCHAT then says the game finished).
sesResult:
        ld      (sesEnd+1),a
        ld      hl,nameSes
        ld      de,BOUNCE
        ld      bc,257
        call    readFile                        ; opens it (fcb, records of 1 byte)
        ret     c
        ld      de,sesEnd
        ld      c,F_SETDTA
        call    BDOS
        ld      hl,32
        ld      (fcb+33),hl
        ld      hl,0
        ld      (fcb+35),hl
        ld      de,fcb
        ld      hl,2
        ld      c,F_WRRND
        call    BDOS
        ld      de,fcb
        ld      c,F_CLOSE
        jp      BDOS

; ---- the game package from the disk: "<ID>.GPF" ------------------------------------------------------
tcpGpf:
        ld      hl,gameId                       ; the FCB name: ID upper case, padded, then GPF
        ld      de,nameGpf
        ld      b,8
.n:     ld      a,(hl)
        or      a
        jr      z,.pad
        cp      'a'
        jr      c,.up
        cp      'z'+1
        jr      nc,.up
        sub     32
.up:    ld      (de),a
        inc     hl
        inc     de
        djnz    .n
        jr      .ext
.pad:   ld      a,' '
.p:     ld      (de),a
        inc     de
        djnz    .p
.ext:   ld      hl,nameGpf
        ld      de,GPFBUF
        ld      bc,GPFMAX
        call    readFile
        ld      hl,msgNoGpf
        ld      a,R_INCOMPAT
        jp      c,exitResult
        jp      gpfCheck

; ---- footprint (5.4): the TCP/IP stack's own page 3 is MSX-DOS's, which the game never sees; the
; transport area is written into it too, so it must be TPA there ------------------------------------
tcpFootprint:
        ld      hl,(npTSize)
        ld      de,TU_AREA
        call    cpHLDE
        ld      a,40
        jp      c,badPkg                        ; the transport area is too small for this transport
        ld      hl,(npTArea)                    ; it goes into MSX-DOS's page 3 as well: it must be TPA
        ld      (dBlk),hl
        xor     a
        ld      (bridge),a
        ld      de,TU_AREA
        add     hl,de
        ex      de,hl
        ld      hl,($0006)
        call    cpHLDE
        ret     nc
        ld      a,(hyb)                         ; it is not: the bridged transport (transport_unapi_br.asm) keeps
        or      a                               ; only a 512-byte block in MSX-DOS's page 3, under the private stack
        jr      nz,.no                          ; (link 2's hybrid transport has none)
        inc     a
        ld      (bridge),a
        ld      hl,($0006)
        ld      de,$400
        or      a
        sbc     hl,de
        ld      (dBlk),hl
        ret
.no:    ld      hl,msgFootprint
        ld      a,R_MACHINE
        jp      exitResult
; ---- connect (11.3) through the overlay ------------------------------------------------------------
tcpConnect:
        call    tcpFootprint
        ld      hl,msgConnect
        call    PRINT
        call    mapOvl
        ld      ix,(ovlIo)
        ld      hl,JIFFY
        ld      (ix+IO_TICKS),l
        ld      (ix+IO_TICKS+1),h
        ld      a,(hz)
        ld      (ix+IO_HZ),a
        ld      hl,(dBlk)                       ; io.buf: the transport area's last 128 bytes (page 3)
        ld      de,384
        add     hl,de
        ld      (ix+IO_BUF),l
        ld      (ix+IO_BUF+1),h
        push    ix
        pop     hl
        ld      de,IO_PROFILE
        add     hl,de
        ex      de,hl
        ld      hl,GPFBUF+8                     ; the profile hash
        ld      bc,4
        ldir
        ld      (ix+IO_VERSION),2
        ld      (ix+IO_FORCE),0
        ld      a,(manual)                      ; MCHAT /T's IRC connection, answered during the game (14)
        or      a
        ld      a,$FF
        jr      nz,.irc
        ld      a,(sesBuf+59)
.irc:   push    ix                              ; (beyond IX's reach)
        pop     hl
        ld      de,IO_IRC
        add     hl,de
        ld      (hl),a
        push    ix                              ; (beyond IX's reach)
        pop     hl
        ld      de,IO_SERVICE
        add     hl,de
        ld      a,(svcMode)
        ld      (hl),a
        inc     hl
        ld      a,(kMode)
        ld      (hl),a                          ; IO_KWANT
        inc     hl
        ld      a,(lMode)
        ld      (hl),a                          ; IO_SWANT
        ld      hl,(lport)
        ld      (ix+IO_LPORT),l
        ld      (ix+IO_LPORT+1),h
        ld      a,(hyb)                         ; link 2: no UDP port here (the overlay: ncand = FFh)
        or      a
        ld      a,(ncand)
        jr      z,.nc
        ld      a,$FF
.nc:    ld      (ix+IO_NCAND),a
        push    ix
        pop     hl
        ld      de,IO_CAND
        add     hl,de
        ex      de,hl
        ld      hl,cands
        ld      bc,18
        ldir
        call    OVL_OPEN
        ld      b,(ix+IO_STATUS)
        call    unmapOvl                        ; (it changes A)
        ld      a,b
        or      a
        jr      z,.open
        dec     a
        ld      hl,msgNoTcpip
        jr      z,.err
        ld      hl,msgNoPort
.err:   ld      a,R_MACHINE
        jp      exitResult
.open:  ld      a,(hyb)
        or      a
        jp      nz,mpConnect                    ; link 2: the Pi connects (playnet.asm), the overlay only keeps the chat alive
        ld      a,1
        ld      (ovlOpen),a
        ld      hl,(JIFFY)
        ld      (t0),hl
        ld      (tDot),hl
.poll:  call    mapOvl
        call    OVL_POLL
        ld      ix,(ovlIo)
        ld      a,(ix+IO_DELAY)
        ld      (delay),a
        push    ix                              ; the agreed K (beyond IX's reach)
        pop     hl
        ld      de,IO_K
        add     hl,de
        ld      a,(hl)
        ld      (kAgreed),a
        ld      b,(ix+IO_STATUS)
        call    unmapOvl
        ld      a,b
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
        ld      c,F_CONST                       ; Esc gives up
        call    BDOS
        or      a
        jr      z,.dot
        ld      c,F_DIRIN
        call    BDOS
        cp      27
        jr      nz,.dot
        ld      a,R_CANCEL
        call    tcpBye
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
.t:     ld      hl,(JIFFY)                      ; netcore gives up after 120 s; this, as a backstop
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
        jp      .poll
.end:   ld      a,b
        jp      exitResult
.ready: ld      hl,msgReady
        call    PRINT
        ld      a,(delay)
        add     a,'0'
        call    PUTCHAR
        jp      PRINTNLINE

; A = result code: BYE to the opponent (in MSX-DOS, interrupts on)
tcpBye: push    af
        call    mapOvl
        pop     af
        ld      ix,(ovlIo)
        ld      (ix+IO_REASON),a
        ei
        call    OVL_BYE
        jp      unmapOvl

; leaving to MSX-DOS before the game: close the port, give the segments back
tcpCleanup:
        ld      a,(ovlOpen)
        or      a
        jr      z,.segs
        xor     a
        ld      (ovlOpen),a
        call    mapOvl
        call    OVL_CLOSE
        call    unmapOvl
.segs:  ld      a,(segsHeld)
        or      a
        ret     z
        xor     a
        ld      (segsHeld),a
freeSegs:
        ld      a,(ovlSeg)
        call    freeSeg
        ld      a,(g3Seg)
freeSeg:
        ld      b,0
        ld      hl,(mapTab)
        ld      de,M_FRE_SEG
        add     hl,de
        jp      (hl)

; ---- the saved MSX-DOS area into its segment (saveDos) --------------------------------------------
tcpSave:
        ld      a,2                             ; nothing to save: the game never touches
        ld      (svMode),a                      ; MSX-DOS's page 3
        ret

; ---- the transport (install): the UNAPI one, relocated into tBuf ----------------------------------
tcpTransport:
        ld      hl,tuImage
        ld      bc,TU_SIZE
        ld      de,tuRelocs
        ld      a,(hyb)
        or      a
        jr      z,.nh
        ld      hl,thImage                      ; link 2: the C9 transaction, in the game's page 3
        ld      bc,TH_SIZE
        ld      de,thRelocs
        jr      .sel
.nh:    ld      a,(bridge)
        or      a
        jr      z,.sel
        ld      hl,tbImage                      ; the page-3 switch in the overlay: no code in MSX-DOS's page 3
        ld      bc,TB_SIZE
        ld      de,tbRelocs
.sel:   push    de
        ld      de,tBuf
        ldir
        pop     hl
        call    relocate
        ld      hl,(npIrq)
        ld      (tBuf+TU_HANDLER),hl
        ld      a,(ovlSeg)
        ld      (tBuf+TU_OVLSEG),a
        ld      hl,(gameSeg1)                   ; and gameSeg2
        ld      (tBuf+TU_GAMESEG1),hl
        ld      hl,(npTArea)                    ; where the game's pages 1 and 2 are: those two, or the
        ld      de,TU_GAMESEG1                  ; bank engine's record (MK_BLOCK+8)
        add     hl,de
        ld      a,(mHost)
        or      a
        jr      z,.segs
        ld      hl,(mBlock)
        ld      de,8
        add     hl,de
.segs:  ld      (tBuf+TU_SEGS),hl
        ld      hl,(ovlIo)
        ld      (tBuf+TU_IO),hl
        ld      hl,(mapTab)
        ld      de,M_PUT_P2
        add     hl,de
        ld      (tBuf+TU_PUTP2),hl
        ld      a,(dosSeg3)
        ld      (tBuf+TU_DOSSEG3),a
        ld      hl,($0006)                      ; the private stack: under MSX-DOS's TPA top
        ld      (tBuf+TU_STACK),hl
        ld      a,(g3Seg)
        ld      (tBuf+TU_GAMESEG3),a
        call    mapOvl                          ; netcore's clock, from now on: the transport's counter
        ld      ix,(ovlIo)
        ld      hl,(dBlk)
        ld      de,TU_TICKS
        add     hl,de
        ld      (ix+IO_TICKS),l
        ld      (ix+IO_TICKS+1),h
        ld      a,(bridge)
        or      a
        jp      z,unmapOvl
        ld      (BR_TICK),hl                    ; the bridge's variables (netcore/ovl_crt0.s)
        ld      a,(dosSeg3)
        ld      (BR_DOS),a
        ld      a,(g3Seg)
        ld      (BR_GAME3),a
        ld      hl,($0006)
        ld      (BR_STACK),hl
        ld      hl,(mapTab)
        ld      de,M_PUT_P2
        add     hl,de
        ld      (BR_PUTP2+1),hl
        ld      hl,(npTArea)
        ld      de,TB_POST
        add     hl,de
        ld      (BR_POST),hl
        ld      a,(ovlSeg)
        ld      (BR_OVL),a
        ld      hl,(dBlk)
        ld      (BR_BLK),hl
        ld      (tBuf+TB_BOOTIX),hl             ; xBoot's IX
        ld      de,TB_TAIL
        add     hl,de
        ld      (BR_TAIL),hl
        jp      unmapOvl
