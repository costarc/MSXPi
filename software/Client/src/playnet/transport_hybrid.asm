; PLAYNET transport for a TCP/IP player who has an MSXPi (PLAYNET /T, link 2): the game packets go through the
; Pi (opcode C9, PROTOCOLS 10.1: the cost of the MSXPi path), the chat stays on TCP/IP. PLAYNET-TCPIP-PERFORMANCE.md 5.5.
;
; The game has a page-3 segment of its own (G3) exactly as in transport_unapi.asm (the TCP/IP stack's state is in
; MSX-DOS's page 3, D3), and the fields the loader fills in sit at the same offsets, so PLAYNET.COM installs it
; with the same code. XCHG is the C9 transaction, run in G3 with no page switch (it is only I/O ports). Every
; KEEP_EVERY calls it also switches to D3 and runs PLAYNET.OVL's keep entry: one service of the stack and the IRC
; connection MCHAT /T left open (PROTOCOLS 14), with interrupts on. XEND tells the Pi (BYE) and goes back to
; MSX-DOS the TCP/IP way: its page 3 was never touched.
;
;   sjasmplus -DTORG=0 --raw=transport0.bin transport_hybrid.asm

        IFNDEF  TORG
TORG:   EQU     0
        ENDIF
        org     TORG

TU_AREA:        EQU     512             ; transport_area.size it needs
KEEP_EVERY:     EQU     8
OVL_KEEP:       EQU     $8015           ; PLAYNET.OVL's keep entry (netcore/ovl_crt0.s)
JIFFY:          EQU     $FC9E
MAPPER_P1:      EQU     $FD
MAPPER_P2:      EQU     $FE
MAPPER_P3:      EQU     $FF

tBase:  jp      xchg                    ; +0  XCHG
        jp      xend                    ; +3  XEND
tIrq:   jp      xirq                    ; +6  XIRQ
        ret                             ; +9  reserved
; the fields the other transports have at the same offsets (the loader and pnBack use any of them)
tLen:   defb    22                      ; +10 game packet length L (the loader)
tImage: defw    $4000                   ; +11 the image's AB header, wiped before a reset (the loader)
tRet:   defw    0                       ; +13 PLAYNET.COM's return routine in page 0, 0 = reset (the loader)
tDosA8: defb    0                       ; +15 MSX-DOS's slot registers (the loader)
tDosSub: defb   0                       ; +16
; as transport_unapi.asm (the loader; the same in D3 and G3)
tHandler: defw  0                       ; the game's interrupt handler (netplay.irq_handler)
tOvlSeg: defb   0                       ; PLAYNET.OVL's mapper segment
tGameSeg1: defb 0                       ; the TPA's segments in pages 1 and 2
tGameSeg2: defb 0
tSegs:  defw    0                       ; the game's segments in pages 1 and 2 now: tGameSeg1, or the
                                        ; mapper-ram bank engine's (MK_BLOCK+8), which changes them by OUT
tDosSeg3: defb  0                       ; MSX-DOS's segment in page 3 (D3)
tGameSeg3: defb 0                       ; the game's (G3)
tIo:    defw    0                       ; the overlay's I/O block
tPutP2: jp      0                       ; MSX-DOS's mapper routine PUT_P2
tTicks: defw    0                       ; interrupts since the game started (G3); netcore's clock in a call (D3)
tSp:    defw    0
tCnt:   defb    1                       ; calls until the next keep (G3; the UNAPI transport's tRx: same offsets)
        defb    0
tCode:  defb    0
tLost:  defb    0                       ; interrupts MSX-DOS took during the last keep call (G3)
tStack: defw    0                       ; the private stack's top in D3: MSX-DOS's TPA top (the loader)
tBuf:   EQU     tBase+384               ; 128 bytes for the UNAPI calls (the overlay's io.buf), in D3

; XCHG. In: HL = packet to send, or 0; DE = receive buffer (L bytes). Out: A = 0 nothing received,
; 1 a packet is at DE, 2 the opponent is gone, 3 the opponent left (B = its result code); E = the
; interrupts that MSX-DOS's handler took during a keep call (the game's did not see them).
xchg:   di
        push    ix
        push    iy
        ld      bc,xback
        push    bc                      ; where the transaction returns, and where a failed one is unwound to
        ld      (tSp),sp
        push    de                      ; the receive buffer
        ld      bc,2                    ; B = L = 0 (nothing to send), C = FLAGS: bit 1 return a packet
        ld      a,h
        or      l
        jr      z,.hdr
        ld      a,(tLen)
        ld      b,a
        inc     c                       ; bit 0 as well: send P
.hdr:   call    c9send
        pop     hl                      ; HL = the receive buffer
        call    c9rxb
        or      a
        jr      z,.none                 ; 00, 00: nothing
        cp      $FE
        jr      nc,.ended               ; FE, reason: left / FF, 00: gone
        ld      b,a                     ; L
        ld      c,0
.recv:  call    c9rxb
        ld      (hl),a
        inc     hl
        add     a,c
        ld      c,a
        djnz    .recv
        call    c9rxb                   ; the sum
        sub     c
        jr      nz,xZero                ; corrupted: as if nothing came
        inc     a                       ; 1: a packet
        ret
.ended: cpl                             ; FE -> 1, FF -> 0
        add     a,2                     ; FE -> 3 (left), FF -> 2 (gone)
        ld      c,a
        call    c9rxb                   ; the reason, or 00
        ld      b,a
        ld      a,c
        ret
.none:  call    c9rxb
xZero:  xor     a
        ret

; back from the transaction (A, B = its result), or from a failed one (c9fail: A = 0)
xback:  ld      hl,tCnt
        dec     (hl)
        ld      e,0                     ; E = interrupts lost: none unless keep runs
        jr      nz,.out
        ld      (hl),KEEP_EVERY
        push    af                      ; the result
        push    bc
        call    keep
        pop     bc
        pop     af
.out:   pop     iy
        pop     ix
        ei
        ret

; One service of the stack and the IRC connection, in MSX-DOS's page 3 with interrupts on (transport_unapi.asm's
; XCHG, with the overlay's keep entry). Out: E = the interrupts that MSX-DOS's handler took meanwhile.
keep:   ld      (tSp),sp
        ld      hl,(tTicks)             ; the game's clock, through a register
        ld      a,(tDosSeg3)
        out     (MAPPER_P3),a           ; MSX-DOS's page 3 (this code is here too)
        ld      sp,(tStack)
        ld      (tTicks),hl
        ld      a,(tOvlSeg)             ; the overlay into page 2, recorded for MSX-DOS
        out     (MAPPER_P2),a
        call    tPutP2
        ld      hl,(JIFFY)
        push    hl
        ei
        call    OVL_KEEP
        di
        pop     de                      ; JIFFY before
        ld      hl,(JIFFY)
        or      a
        sbc     hl,de                   ; HL = interrupts the game did not see
        ex      de,hl                   ; DE: E is the count handed back (a call takes milliseconds: below 256)
        ld      a,(tGameSeg3)
        out     (MAPPER_P3),a           ; the game's page 3 again
        ld      sp,(tSp)
        ld      hl,(tTicks)             ; the game's clock catches up with them
        add     hl,de
        ld      (tTicks),hl
        ld      hl,(tSegs)              ; the game's pages 1 and 2: a RAM implementation of the UNAPI
        ld      a,(hl)                  ; may have put back the segments PUT_P1/PUT_P2 recorded instead
        out     (MAPPER_P1),a
        inc     hl
        ld      a,(hl)
        out     (MAPPER_P2),a
        ret

; a link timeout inside a transaction: unwind to the stack pointer saved at its start; the caller of
; the transaction gets A = 0 (as if nothing came)
c9fail: ld      a,$FF
        out     ($56),a                 ; reset the link: the next transaction starts clean
        ld      sp,(tSp)
        xor     a
        ld      b,a
        ret

; C = FLAGS, B = L, HL = payload: C9, FLAGS, L, P[L], SUM
c9send: ld      a,$C9
        call    c9txb
        ld      a,c
        call    c9txb
        ld      a,b
        call    c9txb
        ld      c,0                     ; the sum
        inc     b
        jr      .next
.send:  ld      a,(hl)
        inc     hl
        call    c9txb
        add     a,c
        ld      c,a
.next:  djnz    .send
        ld      a,c
        jp      c9txb                   ; SUM

; XEND. A = result code. BYE to the opponent through the Pi, then back to MSX-DOS, whose page 3 was never
; touched (PROTOCOLS 14); a reset when there is nothing to go back to. Does not return.
xend:   di
        ld      (tCode),a
        ld      hl,xBack
        push    hl                      ; where a failed transaction goes
        ld      (tSp),sp
        ld      bc,$0120                ; L = 1, FLAGS bit 5: BYE
        ld      hl,tCode
        call    c9send
        call    c9rxb                   ; 00, 00
        call    c9rxb
xBack:  di
        ld      a,(tDosSeg3)
        out     (MAPPER_P3),a           ; MSX-DOS's page 3, for good
        ld      sp,(tStack)
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
; (no xBoot: the room is needed; nothing in this path asks for it)
xBoot:
xReset: di
        ld      hl,(tImage)             ; wipe the A of the image's AB header, or the BIOS would boot it
        ld      (hl),0                  ; as a cartridge after the reset
        jp      0

; XIRQ: the game's H.KEYI hook points here (G3 only; the BIOS has saved the registers)
xirq:   ld      hl,(tTicks)
        inc     hl
        ld      (tTicks),hl
        ld      hl,(tHandler)
        jp      (hl)

        INCLUDE "c9link.asm"

tEnd:
        ASSERT  tEnd - tBase <= 384
