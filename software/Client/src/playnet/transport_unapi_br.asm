; PLAYNET transport for the TCP/IP UNAPI path, bridged (PLAYNET /T), for a game whose transport area is not TPA in
; MSX-DOS's page 3 (the game owns the addresses the TCP/IP stack's TPA top leaves free: 1942, PROTOCOLS 10.2).
; The plain transport (transport_unapi.asm) switches page 3 from code that sits at the same address in both pages 3;
; this one switches it from PLAYNET.OVL, which is in page 2 for the call (netcore/ovl_crt0.s, BR_XCHG, BR_XEND), so
; MSX-DOS's page 3 holds no code of its own but xtail: only a 512-byte block (this image, for its fields, its tail and
; the UNAPI buffer; the loader puts it below the TPA top, whatever the game's area) and the private stack.
; This image goes to two places: the game's transport area (G3 only: the shim, XCHG/XEND/XIRQ) and the block
; (D3 only: its fields, and xtail/xBoot, written position independent).
; The fields are at the same offsets as transport_unapi.asm (build.py checks).
;
;   sjasmplus -DTORG=0 --raw=transport0.bin transport_unapi_br.asm

        IFNDEF  TORG
TORG:   EQU     0
        ENDIF
        org     TORG

TU_AREA:        EQU     512             ; transport_area.size it needs (the shim is at most 384 of it, MSX-DOS's block 512)
BR_XCHG:        EQU     $8018           ; PLAYNET.OVL's bridge entries (netcore/ovl_crt0.s)
BR_XEND:        EQU     $801B
IO_PKT:         EQU     32
IO_LEN:         EQU     34
IO_RX:          EQU     35
IO_STATUS:      EQU     37
IO_REASON:      EQU     39
IO_TXBUF:       EQU     41
IO_RXBUF:       EQU     87
MAPPER_P1:      EQU     $FD
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
; this transport's own (the loader; the same in the shim and in the block)
tHandler: defw  0                       ; the game's interrupt handler (netplay.irq_handler)
tOvlSeg: defb   0                       ; PLAYNET.OVL's mapper segment
tGameSeg1: defb 0                       ; the TPA's segments in pages 1 and 2
tGameSeg2: defb 0
tSegs:  defw    0                       ; the game's segments in pages 1 and 2 now: tGameSeg1, or the
                                        ; mapper-ram bank engine's (MK_BLOCK+8), which changes them by OUT
tDosSeg3: defb  0                       ; (unused here: the overlay keeps MSX-DOS's and the game's page-3 segments)
tGameSeg3: defb 0
tIo:    defw    0                       ; the overlay's I/O block
tPutP2: jp      0                       ; MSX-DOS's mapper routine PUT_P2
tTicks: defw    0                       ; interrupts since the game started (shim); netcore's clock in a call (block)
tSp:    defw    0
tRx:    defw    0
tCode:  defb    0
tLost:  defb    0                       ; interrupts MSX-DOS took during the last XCHG (shim)
tStack: defw    0
tBuf:   EQU     tBase+384               ; 128 bytes for the UNAPI calls (the overlay's io.buf), in the block
tBnc:   EQU     tBase+384               ; the same 128 bytes in the shim's area (the game's page 3): the packets'
                                        ; bounce buffer (L <= 46 bytes), only used while the game's page 3 is in place
tSegV:  EQU     tBnc+126                ; and, at its end, the segments tSegs pointed to at the start of the XCHG

; XCHG. In: HL = packet to send, or 0; DE = receive buffer (L bytes). Out: as transport_unapi.asm.
xchg:   di
        push    ix
        push    iy
        ld      (tSp),sp
        ld      (tRx),de
        ld      bc,(tLen)               ; C = L, B = tImage's low byte: 0 (4000h or 8000h)
        ld      a,h                     ; the packet into the bounce buffer while page 2 is still the game's
        or      l                       ; (a mapper-ram game's stub, and so its buffers, may be in page 2)
        jr      z,.nob
        ld      de,tBnc
        push    bc
        ldir
        pop     bc
        ld      hl,tBnc
.nob:   push    hl                      ; the game's segments of pages 1 and 2, read while page 2 is the game's
        ld      hl,(tSegs)              ; (tSegs may point into a mapper-ram game's stub in page 2)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (tSegV),de
        pop     hl
        ld      a,(tOvlSeg)             ; the overlay into page 2 (a plain OUT)
        out     (MAPPER_P2),a
        ld      ix,(tIo)
        ld      (ix+IO_LEN),c
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
        jp      BR_XCHG                 ; the overlay switches page 3, makes the call and comes back to post
                                        ; with HL = the interrupts MSX-DOS took, the game's page 3 in place
post:   ld      sp,(tSp)
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
        push    bc                      ; a packet: from io.rxbuf to the bounce buffer
        push    ix
        pop     hl
        ld      de,IO_RXBUF
        add     hl,de
        ld      de,tBnc
        ld      bc,(tLen)
        ldir
        pop     bc
.out:   ld      hl,(tSegV)              ; the game's pages 1 and 2 (see transport_unapi.asm)
        ld      a,l
        out     (MAPPER_P1),a
        ld      a,h
        out     (MAPPER_P2),a
        ld      a,c
        dec     a
        jr      nz,.done
        push    bc                      ; then into the stub's buffer, with the game's page 2 back
        ld      hl,tBnc
        ld      de,(tRx)
        ld      bc,(tLen)
        ldir
        pop     bc
.done:
        ld      a,(tLost)
        ld      e,a                     ; E = the interrupts counted above, for the engine's irqCnt
        ld      a,c
        pop     iy
        pop     ix
        ei
        ret

; XEND. A = result code. The overlay does the BYEs and the CLOSE in MSX-DOS's page 3, then runs xtail there.
xend:   di
        ld      b,a
        ld      a,(tOvlSeg)
        out     (MAPPER_P2),a
        ld      a,b
        jp      BR_XEND

; XIRQ: the game's H.KEYI hook points here (G3 only; the BIOS has saved the registers)
xirq:   ld      hl,(tTicks)
        inc     hl
        ld      (tTicks),hl
        ld      hl,(tHandler)
        jp      (hl)

; The end of XEND, in the block in MSX-DOS's page 3 (the overlay gets here with page 3 = MSX-DOS's, IX = the block,
; B = the result code, interrupts off, page 2 = the overlay, the private stack). Nothing absolute: the block is not
; relocated for its address.
xtail:  push    bc
        ld      a,(ix+tGameSeg2-tBase)
        push    ix
        pop     hl
        ld      de,.back-tBase
        add     hl,de
        push    hl                      ; PUT_P2 returns to .back (page 2 is the TPA's from there on)
        ld      l,(ix+tPutP2+1-tBase)
        ld      h,(ix+tPutP2+2-tBase)
        jp      (hl)
.back:  pop     bc
        ld      d,b                     ; D = the result code
        ld      l,(ix+tRet-tBase)
        ld      h,(ix+tRet+1-tBase)
        ld      a,h
        or      l
        jr      z,xReset                ; nothing to go back to
        in      a,($A8)
        ld      b,a                     ; B, C = the game's slot registers, for xBoot
        ld      a,($FFFF)
        cpl
        ld      c,a
        ld      a,(ix+tDosA8-tBase)     ; MSX-DOS's slots: page 0 is RAM again, with PLAYNET.COM in it
        out     ($A8),a
        ld      a,(ix+tDosSub-tBase)
        ld      ($FFFF),a
        ld      a,d
        jp      (hl)                    ; A = the result code; the routine does not return
; PLAYNET.COM could not go back to MSX-DOS. B, C = the game's slot registers: back to them (BIOS in page 0)
xBoot:  ld      ix,0                    ; the loader: the block's address (xBoot is called from PLAYNET.COM)
        ld      a,b
        out     ($A8),a
        ld      a,c
        ld      ($FFFF),a
xReset: di
        xor     a                       ; wipe the AB header of the image, or the BIOS
        ld      l,(ix+tImage-tBase)     ; would boot it as a cartridge after the reset
        ld      h,(ix+tImage+1-tBase)
        ld      (hl),a
        inc     hl
        ld      (hl),a
        jp      0

tEnd:
        ASSERT  tEnd - tBase <= 384
