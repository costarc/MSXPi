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
        .module ovl_crt0
        .globl  _ovl_open, _ovl_poll, _ovl_xchg, _ovl_bye, _ovl_close, _ovl_io
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

        .area   _CODE
; memcpy(dst, src, n) with LDIR, in place of the library's byte loop (SDCC z80 calling convention: arguments on
; the stack, the caller pops them; returns dst in DE). The arguments are read in place, not popped, so an
; interrupt cannot overwrite them.
___memcpy::
        ld      hl,#2
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                      ; DE = dst
        inc     hl
        ld      c,(hl)
        inc     hl
        ld      b,(hl)                      ; BC = src
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a                         ; HL = n
        push    de
        ld      a,h
        or      l
        jr      z,3$
        push    bc
        ld      b,h
        ld      c,l                         ; BC = n
        pop     hl                          ; HL = src
        ldir
3$:     pop     de
        ret

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
