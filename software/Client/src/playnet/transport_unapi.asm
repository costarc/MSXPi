; PLAYNET transport for the TCP/IP UNAPI path (PLAYNET /T). Specification: documents/PLAYNET-PROTOCOLS.md 10.
;
; The game has a page-3 segment of its own (G3): the trampoline copies MSX-DOS's page 3 (D3) into it and
; switches to it, so the game's RAM, its stack and the hooks it gets never touch MSX-DOS's. A call into the
; network (XCHG, XEND) switches page 3 back to D3, where this transport is also installed at the same
; address: the TCP/IP stack then runs in the MSX-DOS it was installed in (its hooks, its work area in
; F1xxh-F37Fh, RAMAD1-3: all things a game overwrites), with interrupts on, so its timer runs as usual.
; Measured: PLAYNET-DESIGN.md 8a. Only registers cross a page-3 switch: the packets go through the
; overlay's I/O block in page 2 (PLAYNET.OVL, netcore/ovl_main.c), mapped by OUT in G3 and recorded
; with PUT_P2 in D3 (a RAM implementation's helper puts back the page-2 segment PUT_P2 recorded).
;
; Layout (transport_area, 512 bytes): this code and its variables (at most 384 bytes), then (in D3 only)
; 128 bytes of buffers for the UNAPI calls (the overlay's io.buf). The private stack is under MSX-DOS's
; TPA top in D3 (free while the game runs: MSX-DOS is paused, PLAYNET's own stack there is dead).
; XIRQ, in G3 only, counts ticks (netcore's clock; JIFFY is never written) and runs the game's handler.
;
;   sjasmplus -DTORG=0 --raw=transport0.bin transport_unapi.asm

        IFNDEF  TORG
TORG:   EQU     0
        ENDIF
        org     TORG

TU_AREA:        EQU     512             ; transport_area.size it needs
OVL_XCHG:       EQU     $8009           ; PLAYNET.OVL's vector (netcore/ovl_crt0.s)
OVL_BYE:        EQU     $800C
OVL_CLOSE:      EQU     $800F
IO_TICKS:       EQU     0               ; its I/O block (netcore/ovl_main.c)
IO_PKT:         EQU     32
IO_LEN:         EQU     34
IO_RX:          EQU     35
IO_STATUS:      EQU     37
IO_REASON:      EQU     39
IO_TXBUF:       EQU     41
IO_RXBUF:       EQU     87
JIFFY:          EQU     $FC9E
MAPPER_P2:      EQU     $FE
MAPPER_P3:      EQU     $FF

tBase:  jp      xchg                    ; +0  XCHG
        jp      xend                    ; +3  XEND
tIrq:   jp      xirq                    ; +6  XIRQ
        ret                             ; +9  reserved
; the fields the MSXPi transport has at the same offsets (the loader and pnBack use either one)
tLen:   defb    22                      ; +10 game packet length L (the loader)
tImage: defw    $4000                   ; +11 the image's AB header, wiped before a reset (the loader)
tRet:   defw    0                       ; +13 PLAYNET.COM's return routine in page 0, 0 = reset (the loader)
tDosA8: defb    0                       ; +15 MSX-DOS's slot registers (the loader)
tDosSub: defb   0                       ; +16
; this transport's own (the loader; the same in D3 and G3)
tHandler: defw  0                       ; the game's interrupt handler (netplay.irq_handler)
tOvlSeg: defb   0                       ; PLAYNET.OVL's mapper segment
tGameSeg2: defb 0                       ; the game's (the TPA's) segment in page 2
tDosSeg3: defb  0                       ; MSX-DOS's segment in page 3 (D3)
tGameSeg3: defb 0                       ; the game's (G3)
tIo:    defw    0                       ; the overlay's I/O block
tPutP2: jp      0                       ; MSX-DOS's mapper routine PUT_P2
tTicks: defw    0                       ; interrupts since the game started (G3); netcore's clock in a call (D3)
tSp:    defw    0
tRx:    defw    0
tCode:  defb    0
tLost:  defb    0                       ; interrupts MSX-DOS took during the last XCHG (G3)
tStack: defw    0                       ; the private stack's top in D3: MSX-DOS's TPA top (the loader)
tBuf:   EQU     tBase+384               ; 128 bytes for the UNAPI calls (the overlay's io.buf), in D3

; XCHG. In: HL = packet to send, or 0; DE = receive buffer (L bytes). Out: A = 0 nothing received,
; 1 a packet is at DE, 2 the opponent is gone, 3 the opponent left (B = its result code); E = the
; interrupts that MSX-DOS's handler took during the call (the game's did not see them; 0 on the MSXPi path).
xchg:   di
        push    ix
        push    iy
        ld      (tSp),sp
        ld      (tRx),de
        ld      a,(tOvlSeg)             ; the overlay into page 2 (G3: a plain OUT)
        out     (MAPPER_P2),a
        ld      ix,(tIo)
        ld      a,(tLen)
        ld      (ix+IO_LEN),a
        ld      c,a
        ld      b,0
        ld      a,h
        or      l
        jr      z,.none
        push    ix                      ; the packet into io.txbuf
        pop     de
        push    hl
        ld      hl,IO_TXBUF
        add     hl,de
        ex      de,hl
        pop     hl
        push    de
        ldir
        pop     hl
.none:  ld      (ix+IO_PKT),l           ; io.pkt: io.txbuf, or 0
        ld      (ix+IO_PKT+1),h
        push    ix
        pop     hl
        ld      de,IO_RXBUF
        add     hl,de
        ld      (ix+IO_RX),l
        ld      (ix+IO_RX+1),h
        ld      hl,(tTicks)             ; the game's clock, through a register
        ld      a,(tDosSeg3)
        out     (MAPPER_P3),a           ; MSX-DOS's page 3 (this code is here too)
        ld      sp,(tStack)
        ld      (tTicks),hl
        ld      a,(tOvlSeg)
        call    tPutP2
        ld      hl,(JIFFY)              ; MSX-DOS's interrupt count, to see the interrupts taken in the call
        push    hl
        ei                              ; the TCP/IP stack's timer runs from MSX-DOS's hooks
        call    OVL_XCHG
        di
        pop     de                      ; JIFFY before
        ld      hl,(JIFFY)
        or      a
        sbc     hl,de                   ; HL = interrupts the game did not see (MSX-DOS's handler took them)
        ld      a,(tGameSeg3)
        out     (MAPPER_P3),a           ; the game's page 3 again
        ld      sp,(tSp)
        ld      a,h
        or      a
        ld      a,l
        jr      z,.lost
        ld      a,255
.lost:  ld      (tLost),a
        ld      e,a
        ld      d,0
        ld      hl,(tTicks)             ; the game's clock catches up with them
        add     hl,de
        ld      (tTicks),hl
        ld      ix,(tIo)
        ld      c,(ix+IO_STATUS)
        ld      b,(ix+IO_REASON)
        ld      a,c
        dec     a
        jr      nz,.out
        push    bc                      ; a packet: from io.rxbuf to the stub's buffer
        push    ix
        pop     hl
        ld      de,IO_RXBUF
        add     hl,de
        ld      de,(tRx)
        ld      a,(tLen)
        ld      c,a
        ld      b,0
        ldir
        pop     bc
.out:   ld      a,(tGameSeg2)
        out     (MAPPER_P2),a
        ld      a,(tLost)
        ld      e,a                     ; E = the interrupts counted above, for the engine's irqCnt
        ld      a,c
        pop     iy
        pop     ix
        ei
        ret

; XEND. A = result code. BYE to the opponent, close the port, and leave the game for MSX-DOS, whose page 3
; was never touched (PROTOCOLS 14); a reset when there is nothing to go back to. Does not return.
xend:   di
        ld      b,a
        ld      a,(tDosSeg3)
        out     (MAPPER_P3),a           ; MSX-DOS's page 3, for good
        ld      sp,(tStack)
        ld      a,b
        ld      (tCode),a
        ld      a,(tOvlSeg)
        out     (MAPPER_P2),a
        call    tPutP2
        ld      ix,(tIo)
        ld      a,(tCode)
        ld      (ix+IO_REASON),a
        ld      hl,JIFFY                ; netcore's clock: MSX-DOS's, which its interrupts run
        ld      (ix+IO_TICKS),l
        ld      (ix+IO_TICKS+1),h
        ei                              ; the BYEs go 100 ms apart
        call    OVL_BYE
        call    OVL_CLOSE
        di
        ld      a,(tGameSeg2)
        call    tPutP2
        ld      hl,(tRet)
        ld      a,h
        or      l
        jr      z,xReset                ; nothing to go back to
        in      a,($A8)
        ld      b,a                     ; B, C = the game's slot registers, for xBoot
        ld      a,($FFFF)
        cpl
        ld      c,a
        ld      a,(tDosA8)              ; MSX-DOS's slots: page 0 is RAM again, with PLAYNET.COM in it
        out     ($A8),a
        ld      a,(tDosSub)
        ld      ($FFFF),a
        ld      a,(tCode)
        jp      (hl)                    ; A = the result code; the routine does not return
; PLAYNET.COM could not go back to MSX-DOS. B, C = the game's slot registers: back to them (BIOS in page 0)
xBoot:  ld      a,b
        out     ($A8),a
        ld      a,c
        ld      ($FFFF),a
xReset: di
        xor     a                       ; wipe the AB header of the image, or the BIOS
        ld      hl,(tImage)             ; would boot it as a cartridge after the reset
        ld      (hl),a
        inc     hl
        ld      (hl),a
        jp      0

; XIRQ: the game's H.KEYI hook points here (G3 only; the BIOS has saved the registers)
xirq:   ld      hl,(tTicks)
        inc     hl
        ld      (tTicks),hl
        ld      hl,(tHandler)
        jp      (hl)

tEnd:
        ASSERT  tEnd - tBase <= 384
