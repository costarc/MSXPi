; Polled byte transfer on the MSXPi link (ports 56h control, 5Ah data), used by the C9 transactions of
; PLAYNET.COM and of its MSXPi transport. Every wait is bounded (about 0.5 s). On a timeout these do not
; return: they jump to c9fail, which the including file defines (it resets the link and unwinds the
; transaction with the stack pointer it saved).

; A = byte to send. Preserves A, BC, DE, HL.
c9txb:  push    af
        call    c9wrdy
        pop     af
        out     ($5A),a
        ret
; A = byte received. Preserves BC, DE, HL.
c9rxb:  call    c9wrdy
        xor     a
        out     ($56),a                 ; request a byte
        call    c9wrdy
        in      a,($5A)
        ret
; spin until port 56h reads 0. Preserves BC, DE, HL.
c9wrdy: push    bc
        ld      bc,0
.l:     in      a,($56)
        or      a
        jr      z,.ok
        dec     bc
        ld      a,b
        or      c
        jr      nz,.l
        jp      c9fail
.ok:    pop     bc
        ret
