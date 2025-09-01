PUTCHAR:
        push    bc
        push    de
        push    hl
        ld      e,a
        ld      c,2
        call    $A2
        pop     hl
        pop     de
        pop     bc
        ret
