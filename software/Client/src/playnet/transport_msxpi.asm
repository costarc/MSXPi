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
xchg:   di
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
        jr      xDone
.ended: cpl                             ; FE -> 1, FF -> 0
        add     a,2                     ; FE -> 3 (left), FF -> 2 (gone)
        ld      c,a
        call    c9rxb                   ; the reason, or 00
        ld      b,a
        ld      a,c
        jr      xDone
.none:  call    c9rxb
xZero:  xor     a
xDone:  ld      e,0                     ; E = interrupts lost to the call: none (transport_unapi.asm)
        ei
        ret

; a link timeout inside a transaction: unwind to the stack pointer saved at its start
c9fail: ld      a,$FF
        out     ($56),a                 ; reset the link: the next transaction starts clean
        ld      sp,(tSp)
        jr      xZero                   ; XCHG returns 0; XEND's saved stack returns into xReset

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
tEnd:
