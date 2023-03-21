BDOS:   EQU     5
PUTCHAR:
        push    bc
        push    de
        push    hl
        ld      e,a
        ld      c,2
        call    5
        pop     hl
        pop     de
        pop     bc
        ret
