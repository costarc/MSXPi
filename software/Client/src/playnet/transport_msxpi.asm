; PLAYNET transport for the MSXPi link (opcode C9). Specification: documents/PLAYNET-PROTOCOLS.md 10, 10.1.
;
; PLAYNET.COM copies this to the game's netplay.transport_area and relocates it there: build.py assembles
; it twice (TORG = 0 and 100h) and the bytes that differ are the high bytes of the addresses to fix.
; The loader also fills in the fields after the vector (T_IRQ, T_LEN, T_IMAGE in the generated include):
; the jump target of XIRQ (the game's interrupt handler), the packet length L and the image's AB header.
;
;   sjasmplus -DTORG=0 --raw=transport0.bin transport_msxpi.asm

        IFNDEF  TORG
TORG:   EQU     0
        ENDIF
        org     TORG

tBase:  jp      xchg                    ; +0  XCHG
        jp      xend                    ; +3  XEND
tIrq:   jp      0                       ; +6  XIRQ: the loader writes the game's interrupt handler at +7
        ret                             ; +9  reserved
tLen:   defb    22                      ; game packet length L = 14 + 8W (the loader)
tImage: defw    $4000                   ; the image's AB header, wiped before a reset (the loader)
tRet:   defw    0                       ; PLAYNET.COM's return routine in page 0, 0 = reset (the loader)
tDosA8: defb    0                       ; the primary slot register under MSX-DOS (the loader)
tDosSub: defb   0                       ; what MSX-DOS had at FFFFh: its sub-slot register, or the RAM byte

; XCHG. In: HL = packet to send, or 0; DE = receive buffer (L bytes). Out: A = 0 nothing received,
; 1 a packet is at DE, 2 the opponent is gone, 3 the opponent left (B = its result code).
; One C9 transaction:  MSX -> C9, FLAGS, L, P[L], SUM      Pi -> L, P[L], SUM | 00,00 | FF,00 | FE,reason
; A timeout resets the link and counts as a lost transaction, which the protocol tolerates.
; Interrupts are off during the transaction and on afterwards.
; DELTAs (10.1): a packet that follows the last one in its direction (F d = 1-3 frames on: a packet every K
; frames) travels as seq, F, its d new records and the check (d(W + 1) + 4 bytes) instead of L. Replies: when DE
; still holds the last packet received (FLAGS bit 3), the Pi may send one, which is applied there. Ours: once the
; Pi sent a DELTA (an older Pi never does), a packet 1-3 frames after the last one sent goes as a DELTA. The
; engine builds every packet from one ring of frame records, so it repeats the last one's other records.
xchg:   di
        ld      (tSp),sp
        push    de                      ; the receive buffer
        ld      (tPkt),hl
        push    hl
        ld      hl,(tRxAt)
        or      a
        sbc     hl,de
        pop     hl
        ld      a,(tRxOk)               ; C = FLAGS: bit 1 return a packet, bit 3 as a DELTA (DE holds its base)
        jr      z,.base
        xor     a
.base:  or      2
        ld      c,a
        ld      b,0                     ; B = L = 0: nothing to send
        ld      a,h
        or      l
        jr      z,.hdr
        inc     c                       ; bit 0 as well: send P
        ld      a,(tLen)
        ld      b,a
        ld      a,(tTxD)
        or      a
        jr      z,.hdr                  ; the Pi has not shown it takes DELTAs
        inc     hl
        inc     hl
        ld      a,(tTxF)
        cpl
        add     a,(hl)                  ; d - 1 (d = F - the last F sent, the frames since: K)
        inc     hl
        ld      e,(hl)                  ; W
        dec     hl
        dec     hl                      ; HL = seq
        cp      3
        jr      nc,.full                ; not 1-3 frames on (a resend, or the first): in full
        inc     a
        ld      d,a
        inc     e                       ; E = R
        xor     a
.mul:   add     a,e
        dec     d
        jr      nz,.mul
        ld      d,a                     ; D = dR, the new records
        add     a,4                     ; a DELTA: seq, F, then the d new records and the check
        ld      b,a
        set     2,c
        call    c9head
        ld      bc,$0200                ; seq, F (C = the sum)
        call    txBody
        ld      a,(tLen)                ; past W and the records the Pi has: 1 + 8R - dR
        sub     5
        sub     d
        ld      e,a
        ld      a,d
        add     a,2
        ld      b,a
        ld      d,0
        add     hl,de
        call    txBody                  ; the new records and the check
        ld      a,c
        call    c9txb                   ; SUM
        jr      .sent
.full:  dec     hl
.hdr:   call    c9send
.sent:  pop     hl                      ; HL = the receive buffer
        call    c9rxb
        or      a
        jr      z,.none                 ; 00, 00: nothing
        cp      $FE
        jr      nc,.ended               ; FE, reason: left / FF, 00: gone
        ld      b,a                     ; L
        ld      c,0                     ; the sum
        cp      22                      ; shorter than any full packet: a DELTA
        jr      c,.delta
        ld      (tRxAt),hl              ; in full: the base of the next DELTA reply
        call    rxBody
        jr      .sum
.delta: push    bc                      ; B = L
        inc     hl
        inc     hl
        ld      a,(hl)                  ; the last packet's F
        dec     hl
        push    af
        ld      bc,$0200                ; seq, F first (C = the sum)
        call    rxBody                  ; HL = W
        pop     af
        dec     hl
        sub     (hl)
        neg                             ; A = d, the frames since the last packet
        inc     hl
        ld      d,a
        ld      a,(hl)                  ; W
        inc     hl
        inc     a
        ld      e,a                     ; E = R
        xor     a
.mulR:  add     a,e
        dec     d
        jr      nz,.mulR                ; A = dR
        push    bc                      ; C = the sum
        ld      c,a
        ld      b,0
        push    hl
        add     hl,bc
        pop     de                      ; its last 8 - d records move back to its first
        ld      a,(tLen)
        sub     6
        sub     c
        ld      c,a                     ; (8 - d)R
        ldir
        ex      de,hl                   ; where the new records go
        pop     bc
        pop     de                      ; D = L
        ld      a,d
        sub     2
        ld      b,a                     ; the new records and the check
        call    rxBody
        ld      a,4
        ld      (tTxD),a                ; the Pi knows DELTAs: ours may be sent as DELTAs as well
.sum:   call    c9rxb                   ; the sum
        sub     c
        jr      nz,.bad                 ; corrupted: as if nothing came
        ld      a,8
        ld      (tRxOk),a
        call    txDone
        ld      a,1                     ; 1: a packet
        jr      xDone
.bad:   xor     a                       ; the Pi took it as delivered: the next one in full
        ld      (tRxOk),a
        jr      .zero
.ended: cpl                             ; FE -> 1, FF -> 0
        add     a,2                     ; FE -> 3 (left), FF -> 2 (gone)
        ld      c,a
        call    c9rxb                   ; the reason, or 00
        ld      b,a
        ld      a,c
        jr      xDone
.none:  call    c9rxb
.zero:  call    txDone
xZero:  xor     a
xDone:  ld      e,0                     ; E = interrupts lost to the call: none (transport_unapi.asm)
        ei
        ret

; a link timeout inside a transaction: unwind to the stack pointer saved at its start. Neither side's DELTA base
; can be trusted now: the next packets go in full.
c9fail: ld      a,$FF
        out     ($56),a                 ; reset the link: the next transaction starts clean
        xor     a
        ld      (tTxD),a
        ld      (tRxOk),a
        ld      sp,(tSp)
        jr      xZero                   ; XCHG returns 0; XEND's saved stack returns into xReset

; a transaction is complete: the packet it sent (if any) is the base of our next DELTA
txDone: ld      hl,(tPkt)
        ld      a,h
        or      l
        ret     z
        inc     hl
        inc     hl
        ld      a,(hl)
        ld      (tTxF),a
        ret

; B bytes (1-255) into HL, their sum added to C
rxBody: call    c9rxb
        ld      (hl),a
        inc     hl
        add     a,c
        ld      c,a
        djnz    rxBody
        ret

; B bytes (1-255) from HL, their sum added to C
txBody: ld      a,(hl)
        inc     hl
        call    c9txb
        add     a,c
        ld      c,a
        djnz    txBody
        ret

; C = FLAGS, B = L: C9, FLAGS, L
c9head: ld      a,$C9
        call    c9txb
        ld      a,c
        call    c9txb
        ld      a,b
        jp      c9txb

; C = FLAGS, B = L, HL = payload: C9, FLAGS, L, P[L], SUM
c9send: call    c9head
        ld      c,0
        ld      a,b
        or      a
        call    nz,txBody
        ld      a,c
        jp      c9txb                   ; SUM

; XEND. A = result code. Tells the opponent (BYE, through the Pi) and leaves the game: back to MSX-DOS
; when the loader saved it (PROTOCOLS 14), else by a reset. Does not return.
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
        ld      hl,(tRet)
        ld      a,h
        or      l
        jr      z,xReset                ; nothing saved
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
; PLAYNET.COM could not restore MSX-DOS. B, C = the game's slot registers: back to them (BIOS in page 0)
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

        INCLUDE "c9link.asm"

tSp:    defw    0
tCode:  defb    0
tPkt:   defw    0                       ; the packet this transaction sends, or 0
tRxAt:  defw    0                       ; where the last packet received in full or rebuilt is
tRxOk:  defb    0                       ; 8: it is there (a DELTA reply may follow)
tTxD:   defb    0                       ; 4: the Pi sent a DELTA, so it takes ours
tTxF:   defb    0                       ; the F of the last packet sent
tEnd:
