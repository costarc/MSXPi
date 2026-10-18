; UDPTEST.COM - prove the TCP/IP UNAPI UDP path before the game depends on it.
;
;   sjasmplus --raw=udptest.com netplay\udptest.asm
;
;   UDPTEST L <port>            listen, print the datagram, answer WORLD
;   UDPTEST S <a.b.c.d> <port>  send HELLO, wait for the answer
;
; Discovery and the page-1 switching follow the repo's ping.asm (Konamiman):
; an implementation whose entry is below C000h lives in page 1 (a ROM slot, or
; a mapper segment) and is mapped there only for the duration of each call;
; the program's own page 1 (the TPA RAM) is put back afterwards. This is the
; same sequence the game stub will use, so it is proven here first.

BDOS:           EQU     $0005
F_TERM0:        EQU     $00
F_CONOUT:       EQU     $02
F_PRINT:        EQU     $09

ENASLT:         EQU     $0024
TPASLOT1:       EQU     $F342
ARG:            EQU     $F847
EXTBIO:         EQU     $FFCA
JIFFY:          EQU     $FC9E
MAPPER_P1:      EQU     $FD

TCPIP_UDP_OPEN:  EQU    8
TCPIP_UDP_CLOSE: EQU    9
TCPIP_UDP_STATE: EQU    10
TCPIP_UDP_SEND:  EQU    11
TCPIP_UDP_RCV:   EQU    12
TCPIP_WAIT:      EQU    29
ERR_NO_DATA:     EQU    3

        MACRO MARK n
        push    af
        ld      a,n
        ld      (trc),a
        pop     af
        ENDM

        org     $0100

start:  ld      hl,helloSrc
        ld      de,helloTxt
        ld      bc,10
        ldir
        ld      de,msgTitle
        call    print
        ld      hl,$0081
        call    skipsp
        ld      a,(hl)
        and     $DF
        ld      (mode),a
        cp      'L'
        jr      z,.argsOk
        cp      'S'
        jp      nz,usage
.argsOk:
        inc     hl
        ld      a,(mode)
        cp      'S'
        jr      nz,.port
        call    parseIp                 ; dest IP -> params block
        jp      c,usage
.port:  call    parseNum                ; DE = port
        jp      c,usage
        ld      (portArg),de
        ld      de,1200                 ; sender gives up after ~20 s at 60 Hz...
        ld      a,(mode)
        cp      'S'
        jr      z,.tmo
        ld      de,10800                ; ...the listener waits ~3 minutes
.tmo:   ld      (tmo),de

        call    discover
        call    dumpHook
        call    dumpUnapi
        call    mapInl
        call    unapiOpen
        ld      a,(mode)
        cp      'S'
        jp      z,doSend
        jp      doListen

; ---------------------------------------------------------------- discovery
discover:
        ld      hl,tcpipId
        ld      de,ARG
        ld      bc,15
        ldir
        xor     a
        ld      b,0
        ld      de,$2222
        call    EXTBIO
        ld      a,b
        or      a
        jr      nz,.have
        ld      de,msgNoStack
        jp      fail
.have:  ld      a,1
        ld      b,1
        ld      de,$2222
        call    EXTBIO                  ; A = slot, B = segment, HL = entry
        ld      (u_entry),hl
        ld      (u_slot),a
        ld      c,a
        ld      a,b
        ld      (u_seg),a               ; FFh = not in a mapper segment
        in      a,(MAPPER_P1)
        ld      (g_seg),a
        ld      a,(TPASLOT1)
        ld      (g_slot),a
        ld      a,(u_seg)
        cp      $FF
        jr      z,.notmap
        ; RAM-based (mapper segment): the UNAPI RAM helper's CALL_MAP switches page 1
        ; through the mapper-support routines, so they keep their own record
        ld      hl,tcpipId
        ld      de,ARG
        ld      bc,15
        ldir
        ld      a,$FF
        ld      b,0
        ld      de,$2222
        ld      hl,0
        call    EXTBIO
        ld      a,h
        or      l
        jr      nz,.helper
        ld      de,msgNoHelper
        jp      fail
.helper:
        ld      (u_jump+1),hl
        ld      a,(u_slot)
        ld      h,a
        ld      a,(u_seg)
        ld      l,a
        ld      (u_iy),hl               ; IY = slot:segment
        ret
.notmap:
        ld      hl,(u_entry)
        ld      a,h
        cp      $C0
        jr      c,.calslt
        ld      (u_jump+1),hl           ; entry in page 3: call it directly
        ld      a,$FF
        ld      (u_page3),a
        ret
.calslt:
        ld      hl,ENASLT-8             ; CALSLT = 001Ch
        ld      (u_jump+1),hl
        ld      a,(u_slot)
        ld      h,a
        ld      l,0
        ld      (u_iy),hl
        ret

; page 1 is switched by the helper / CALSLT around each call; nothing stays mapped
mapInl:
unmapInl:
        ret

; FD9F is H.TIMI: five bytes. INL's timer work is driven from it.
dumpHook:
        ld      de,msgHook
        call    print
        ld      hl,$FD9F
        ld      b,5
.h:     ld      a,(hl)
        push    hl
        push    bc
        call    printHex
        ld      a,' '
        call    putc
        pop     bc
        pop     hl
        inc     hl
        djnz    .h
        jp      crlf
; give INL time to process the network before the first send: TCPIP_WAIT halts
; until the next interrupt, which is when INL does its work
settle: ld      b,40
.w:     push    bc
        ld      a,TCPIP_WAIT
        call    unapiCall
        pop     bc
        djnz    .w
        ld      de,msgSettled
        jp      print

; NET_STATE (3) and UDP_STATE (10): print the error code and the answers
probeState:
        ld      a,3
        call    unapiCall
        push    af
        push    bc
        ld      de,msgNet
        call    print
        pop     bc
        ld      a,b
        call    printByte               ; B = 0 closed, 1 opening, 2 open, 3 closing
        pop     af
        call    crlf
        ld      a,(conn)
        ld      b,a
        ld      a,TCPIP_UDP_STATE
        call    unapiCall
        push    af
        push    bc
        ld      de,msgUState
        call    print
        pop     bc
        ld      a,b
        call    printByte               ; B = pending datagrams
        pop     af
        call    printByte               ; the error code
        call    crlf
        ld      de,msgCalling
        jp      print

; the discovery results: where the implementation is and how page 1 is switched
dumpUnapi:
        ld      de,msgUnapi
        call    print
        ld      a,(u_slot)
        call    printHex
        ld      a,' '
        call    putc
        ld      a,(u_seg)
        call    printHex
        ld      a,' '
        call    putc
        ld      a,(u_entry+1)
        call    printHex
        ld      a,(u_entry)
        call    printHex
        ld      de,msgGame
        call    print
        ld      a,(g_slot)
        call    printHex
        ld      a,' '
        call    putc
        ld      a,(g_seg)
        call    printHex
        ld      de,msgP3
        call    print
        ld      a,(u_page3)
        call    printHex
        jp      crlf
printHex:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    .nib
        pop     af
.nib:   and     $0F
        add     a,'0'
        cp      '9'+1
        jr      c,.d
        add     a,7
.d:     jp      putc

; ------------------------------------------------------- one UNAPI call
; A = function; B, HL, DE per the function. Results come back untouched.
; Standard dispatch (pchess_tcp.c): helper CALL_MAP for a mapper segment, CALSLT for a
; ROM below C000h, a direct call otherwise. IX = entry, IY = slot:segment. Buffers
; handed over must be outside page 1 (they are at 9000h). CALSLT returns with DI.
unapiCall:
        ld      ix,(u_entry)
        ld      iy,(u_iy)
        call    u_jump
        ei
        ret
u_jump: defb    $C3
        defw    0

; ------------------------------------------------------------------- UDP
unapiOpen:
        ld      a,(mode)
        ld      hl,$FFFF                ; sender: random port
        cp      'S'
        jr      z,.open
        ld      hl,(portArg)            ; listener: the port asked for
.open:  ld      b,0                     ; transient
        ld      a,TCPIP_UDP_OPEN
        call    unapiCall
        or      a
        jr      z,.ok
        ld      de,msgOpenFail
        jp      fail
.ok:    ld      a,b
        ld      (conn),a
        ld      de,msgOpened
        call    print
        ld      a,(conn)
        call    printByte
        call    crlf
        ret

doSend: call    settle
        call    probeState
        ld      hl,(portArg)
        ld      (dest+4),hl
        ld      hl,5
        ld      (dest+6),hl
        ld      a,(conn)
        ld      b,a
        ld      hl,helloTxt
        ld      de,dest
        ld      a,TCPIP_UDP_SEND
        call    unapiCall
        or      a
        jr      z,.sent
        ld      de,msgSendFail
        push    af
        call    print
        pop     af
        call    printByte
        call    crlf
        jp      done
.sent:  ld      de,msgSent
        call    print
        call    waitReply
        jp      done

doListen:
        ld      de,msgListening
        call    print
        call    waitReply
        jp      done

; wait up to ~20 s for a datagram; print it; the listener answers it
waitReply:
        ld      hl,(JIFFY)
        ld      (t0),hl
.poll:  ld      a,(conn)
        ld      b,a
        ld      hl,rxbuf
        ld      de,32
        ld      a,TCPIP_UDP_RCV
        call    unapiCall
        cp      ERR_NO_DATA
        jr      z,.idle
        or      a
        jr      nz,.idle                ; any other error: keep trying until timeout
        ld      (srcIp),hl              ; L.H.E.D = source IP
        ld      (srcIp+2),de
        ld      (srcPort),ix
        ld      (rxlen),bc
        ld      de,msgGot
        call    print
        ld      hl,rxbuf
        ld      bc,(rxlen)
        call    printText
        ld      de,msgFrom
        call    print
        call    printSrc
        ld      a,(mode)
        cp      'L'
        ret     nz
        ; answer the sender
        ld      hl,(srcIp)
        ld      (dest),hl
        ld      hl,(srcIp+2)
        ld      (dest+2),hl
        ld      hl,(srcPort)
        ld      (dest+4),hl
        ld      hl,5
        ld      (dest+6),hl
        ld      a,(conn)
        ld      b,a
        ld      hl,worldTxt
        ld      de,dest
        ld      a,TCPIP_UDP_SEND
        call    unapiCall
        ld      de,msgAnswered
        jp      print
.idle:  ld      a,TCPIP_WAIT
        call    unapiCall
        ld      hl,(JIFFY)
        ld      de,(t0)
        or      a
        sbc     hl,de
        ld      de,(tmo)
        or      a
        sbc     hl,de
        jp      c,.poll
        ld      de,msgTimeout
        jp      print

done:   call    closeAll
        jp      BDOS-5
closeAll:
        ld      a,(conn)
        ld      b,a
        ld      a,TCPIP_UDP_CLOSE
        call    unapiCall
        jp      unmapInl

fail:   call    print
        call    unmapInl
        jp      BDOS-5
usage:  ld      de,msgUsage
        jp      fail

; ---------------------------------------------------------------- helpers
print:  ld      c,F_PRINT
        jp      BDOS
crlf:   ld      de,msgCrlf
        jp      print
putc:   ld      e,a
        ld      c,F_CONOUT
        jp      BDOS
skipsp: ld      a,(hl)
        cp      ' '
        ret     nz
        inc     hl
        jr      skipsp
; HL = text, BC = length: printable characters only
printText:
        ld      a,b
        or      c
        jr      z,.end
        ld      a,(hl)
        cp      32
        jr      c,.skip
        push    hl
        push    bc
        call    putc
        pop     bc
        pop     hl
.skip:  inc     hl
        dec     bc
        jr      printText
.end:   ret
; A = byte, or HL = word, printed in decimal without leading zeros
printByte:
        ld      l,a
        ld      h,0
printWord:
        ld      c,0                     ; C = "a digit has been printed"
        ld      de,10000
        call    .pd
        ld      de,1000
        call    .pd
        ld      de,100
        call    .pd
        ld      de,10
        call    .pd
        ld      a,l
        add     a,'0'
        jp      putc
.pd:    ld      b,'0'
.ps:    or      a
        sbc     hl,de
        jr      c,.po
        inc     b
        jr      .ps
.po:    add     hl,de
        ld      a,b
        cp      '0'
        jr      nz,.pe
        ld      a,c
        or      a
        ret     z                       ; leading zero
.pe:    ld      c,1
        push    hl
        push    bc
        ld      a,b
        call    putc
        pop     bc
        pop     hl
        ret
printSrc:
        ld      hl,srcIp
        ld      b,4
.l:     ld      a,(hl)
        push    hl
        push    bc
        call    printByte
        pop     bc
        pop     hl
        inc     hl
        dec     b
        jr      z,.p
        push    hl
        push    bc
        ld      a,'.'
        call    putc
        pop     bc
        pop     hl
        jr      .l
.p:     ld      a,':'
        call    putc
        ld      hl,(srcPort)
        call    printWord
        jp      crlf
; HL = text -> DE = value, carry set if no digit
parseNum:
        call    skipsp
        ld      de,0
        ld      b,0
.n:     ld      a,(hl)
        sub     '0'
        cp      10
        jr      nc,.end
        push    hl
        ld      h,d
        ld      l,e
        add     hl,hl
        add     hl,hl
        add     hl,de
        add     hl,hl                   ; x10
        ld      e,a
        ld      d,0
        add     hl,de
        ex      de,hl
        pop     hl
        inc     hl
        inc     b
        jr      .n
.end:   ld      a,b
        or      a
        scf
        ret     z
        or      a
        ret
; a.b.c.d -> dest(0..3)
parseIp:
        ld      ix,dest
        ld      b,4
.o:     push    bc
        call    parseNum
        pop     bc
        ret     c
        ld      (ix+0),e
        inc     ix
        dec     b
        jr      z,.done
        ld      a,(hl)
        cp      '.'
        scf
        ret     nz
        inc     hl
        jr      .o
.done:  or      a
        ret

; ------------------------------------------------------------------ data
tcpipId:  defb  "TCP/IP",0,0,0,0,0,0,0,0,0
mode:     defb  0
conn:     defb  0
u_slot:   defb  0
u_seg:    defb  $FF
u_page3:  defb  0
trc:      defb  0                ; last step reached inside unapiCall (for the harness)
u_persist: defb 0               ; 1 = INL stays mapped in page 1 (ping.asm style): starves the program on this rig
u_fn:     defb  0
u_ei:     defb  1                ; 1 = interrupts on during the call (DOS phase)
u_ix:     defw  0
; buffers given to the stack: page 2, never page 1
dest:     EQU   $9000
srcIp:    EQU   $9008
rxbuf:    EQU   $900C
helloTxt: EQU   $902E
worldTxt: EQU   $9033
g_slot:   defb  0
g_seg:    defb  0
portArg:  defw  0
srcPort:  defw  0
rxlen:    defw  0
t0:       defw  0
tmo:      defw  1200
helloSrc: defb  "HELLO"
worldSrc: defb  "WORLD"
u_iy:     defw  0
u_entry:  defw  0

msgTitle:     defb "UDPTEST - UNAPI UDP check",13,10,"$"
msgUsage:     defb "usage: UDPTEST L <port>  |  UDPTEST S <a.b.c.d> <port>",13,10,"$"
msgNoStack:   defb "No TCP/IP UNAPI found (run MSR I and INL I first)",13,10,"$"
msgNoHelper:  defb "No UNAPI RAM helper",13,10,"$"
msgOpenFail:  defb "UDP_OPEN failed",13,10,"$"
msgHook:      defb "H.TIMI FD9F: $"
msgSettled:   defb "waited 40 interrupts",13,10,"$"
msgNet:       defb "NET_STATE (0 closed,2 open): $"
msgUState:    defb "UDP_STATE pending, err: $"
msgCalling:   defb "calling UDP_SEND...",13,10,"$"
msgUnapi:     defb "U slot/seg/entry: $"
msgGame:      defb "  G slot/seg: $"
msgP3:        defb "  p3: $"
msgOpened:    defb "UDP open, connection $"
msgSendFail:  defb "UDP_SEND failed, error $"
msgSent:      defb "sent HELLO",13,10,"$"
msgListening: defb "listening...",13,10,"$"
msgGot:       defb "GOT: $"
msgFrom:      defb "  from $"
msgAnswered:  defb "answered WORLD",13,10,"$"
msgTimeout:   defb "TIMEOUT: nothing received",13,10,"$"
msgCrlf:      defb 13,10,"$"
