; PLAYNET.OVL header: the entry vector at 8000h (the start of its mapper segment, mapped in page 2).
; Every entry takes and returns its values in the I/O block (ovl_main.c, ovl_io), whose address is at +19.
; The caller provides the stack, in page 3 (see ovl_main.c), and keeps interrupts as it likes.
;
;   +0  INIT   once, first: clears the C data (the I/O block too: fill it in after this)
;   +3  OPEN   finds the TCP/IP UNAPI, opens the UDP port, starts connecting
;   +6  POLL   status, delay, leader
;   +9  XCHG   send a game packet and/or take one (PROTOCOLS 10)
;   +12 BYE    end here: BYE 3 times (interrupts must be on: it waits about 300 ms)
;   +15 CLOSE  close the UDP port
;   +18 version of this vector (1)
;   +19 address of the I/O block
;   +21 KEEP  one service of the stack and the IRC connection (the hybrid transport, transport_hybrid.asm)
;   +24 BRXCHG the bridged transport's XCHG (transport_unapi_br.asm): page 3 switched from here, in page 2
;   +27 BRXEND its XEND
;   +30 the bridge's variables, written by PLAYNET.COM (playnet_tcp.asm, BR_*)
        .module ovl_crt0
        .globl  _ovl_open, _ovl_poll, _ovl_xchg, _ovl_bye, _ovl_close, _ovl_io, _ovl_keep
        .globl  l__DATA, s__DATA, l__INITIALIZER, s__INITIALIZER, s__INITIALIZED

        .area   _HEADER (ABS)
        .org    0x8000
        jp      init
        jp      _ovl_open
        jp      _ovl_poll
        jp      _ovl_xchg
        jp      _ovl_bye
        jp      _ovl_close
        .db     1
        .dw     _ovl_io
        jp      _ovl_keep
        jp      brxchg
        jp      brxend
brdos:  .db     0                           ; +30 MSX-DOS's page-3 segment
brgame3:.db     0                           ; +31 the game's
brstack:.dw     0                           ; +32 the private stack's top in MSX-DOS's page 3
brputp2:.db     0xC3                        ; +34 jp PUT_P2
        .dw     0
brpost: .dw     0                           ; +37 where XCHG goes on in the game's page 3
brovl:  .db     0                           ; +39 this segment, for PUT_P2
brblk:  .dw     0                           ; +40 the block in MSX-DOS's page 3
brtick: .dw     0                           ; +42 the block's tick counter (netcore's clock)
brtail: .dw     0                           ; +44 xtail in the block

; The page-3 switch of a bridged game (transport_unapi_br.asm): interrupts off, this segment in page 2. HL = the
; game's clock; back at brpost with HL = the interrupts MSX-DOS took during the call, the game's page 3 in place.
brxchg: ld      a,(brdos)
        out     (0xFF),a                    ; MSX-DOS's page 3
        ld      sp,(brstack)
        ex      de,hl
        ld      hl,(brtick)
        ld      (hl),e                      ; netcore's clock goes on from the game's
        inc     hl
        ld      (hl),d
        ld      a,(brovl)
        call    brputp2
        ld      hl,(0xFC9E)                 ; MSX-DOS's interrupt count, to see the interrupts taken in the call
        push    hl
        ei                                  ; the TCP/IP stack's timer runs from MSX-DOS's hooks
        call    _ovl_xchg
        di
        pop     de
        ld      hl,(0xFC9E)
        or      a
        sbc     hl,de
        ld      ix,(brpost)
        ld      a,(brgame3)
        out     (0xFF),a                    ; the game's page 3 again
        jp      (ix)

; A = the result code. BYE, CLOSE in MSX-DOS's page 3, then xtail (in the block) puts the TPA back: B = code, IX = block.
brxend: ld      b,a
        ld      a,(brdos)
        out     (0xFF),a
        ld      sp,(brstack)
        push    bc
        ld      a,(brovl)
        call    brputp2
        ld      ix,#_ovl_io
        ld      (ix+39),b                   ; io.reason: ours
        ld      hl,#0xFC9E                  ; netcore's clock: MSX-DOS's, which its interrupts run
        ld      (ix+0),l
        ld      (ix+1),h
        ei                                  ; the BYEs go 100 ms apart
        call    _ovl_bye
        call    _ovl_close
        di
        pop     bc
        ld      ix,(brblk)
        ld      hl,(brtail)
        jp      (hl)

init:   ld      hl,#s__DATA                 ; the C globals start at zero
        ld      bc,#l__DATA
        ld      a,b
        or      c
        jr      z,1$
        ld      (hl),#0
        dec     bc
        ld      a,b
        or      c
        jr      z,1$
        ld      e,l
        ld      d,h
        inc     de
        ldir
1$:     ld      bc,#l__INITIALIZER          ; and the initialised ones get their values
        ld      a,b
        or      c
        jr      z,2$
        ld      de,#s__INITIALIZED
        ld      hl,#s__INITIALIZER
        ldir
2$:     jp      gsinit

; NOTE (SDCC 4.6 port, stage 1): this file used to define ___memcpy, an LDIR copy that replaced SDCC 4.0's
; byte loop (performance). It read its arguments from the stack (SDCC 4.0 convention), which is wrong under
; SDCC 4.6 (dst in HL, src in DE, count pushed and popped by the callee), so it was removed and 4.6's own
; memcpy, which also ends in LDIR, is linked. If the copy turns out too slow or the overlay too big, put an
; override back in the 4.6 convention: see "Stage 1 note" in documents/SDCC46-PORT-HANDOVER.md.
        .area   _HOME
        .area   _CODE
        .area   _INITIALIZER
        .area   _GSINIT
gsinit::
        .area   _GSFINAL
        ret
        .area   _DATA
        .area   _INITIALIZED
        .area   _BSEG
        .area   _BSS
        .area   _HEAP
