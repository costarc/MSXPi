; TPATOP.COM: prints "TPATOP=xxxx" - the word at 0006h, MSX-DOS's TPA top, which PLAYNET's tcpFootprint compares with the
; transport area + 512 (plan C1). Run it after the TCP/IP stack is installed (MSR I / RAMHELPR I, then INL I): the stack lowers the top.
; sjasmplus --raw=tpatop.com tpatop.asm
        org     $100
        ld      hl,($0006)
        ld      de,msg+7
        ld      a,h
        call    hex2
        ld      a,l
        call    hex2
        ld      de,msg
        ld      c,9
        jp      5
hex2:   push    af
        rrca
        rrca
        rrca
        rrca
        call    nib
        pop     af
nib:    and     $0F
        add     a,'0'
        cp      '9'+1
        jr      c,.s
        add     a,7
.s:     ld      (de),a
        inc     de
        ret
msg:    db      "TPATOP=xxxx",13,10,"$"
