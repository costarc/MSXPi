; P1TEST.COM - exercise disk transfers whose buffer is in page 1 (4000-7FFF).
;
; While a disk driver runs, its ROM occupies page 1, so a sector read into or
; written from 4000-7FFF needs special handling (XFER / slot switching). This
; program makes DOS do exactly that, on the current drive:
;
;   1. It is padded to 40 KB with a known pattern, so loading it fills page 1.
;      The whole pattern (0400-A0FF) is verified before anything else runs.
;   2. Ten times: write 16 KB from 4000 to P1TEST.BIN, clear 4000-7FFF, read
;      the file back into 4000 and verify it.
;
; Pattern byte at address a: low(a) XOR high(a) XOR 0A5h.
; Needs MSX-DOS 2 / Nextor (file handle calls). Build: see build.sh.

BDOS    equ     5
_OPEN   equ     43h
_CREATE equ     44h
_CLOSE  equ     45h
_READ   equ     48h
_WRITE  equ     49h
PADSTART equ    0400h           ; pattern from here...
PADEND  equ     0A100h          ; ...to here (exclusive); file is 40 KB
PASSES  equ     10

        org     0100h
start:
        ld      de,m_hello
        call    print
        ld      hl,PADSTART
        ld      bc,PADEND-PADSTART
        call    verify
        jp      nz,fail_load
        ld      de,m_loadok
        call    print

        ld      b,0             ; _DOSVER: DOS1 has no handle calls
        ld      c,6Fh
        call    BDOS
        or      a
        jr      nz,dos1
        ld      a,b
        cp      2
        jr      nc,dos2
dos1:
        ld      de,m_dos1
        call    print
        rst     0
dos2:
        ld      de,m_rw
        call    print
        ld      a,PASSES
        ld      (iter),a
pass:
        ld      de,fname        ; create/truncate
        xor     a
        ld      b,0
        ld      c,_CREATE
        call    BDOS
        or      a
        jp      nz,fail_dos
        ld      a,b
        ld      (fh),a
        ld      de,4000h        ; write 16 KB straight from page 1
        ld      hl,4000h
        ld      c,_WRITE
        call    BDOS
        or      a
        jp      nz,fail_dos
        call    close

        ld      hl,4000h        ; wipe page 1
        ld      de,4001h
        ld      bc,3FFFh
        ld      (hl),0
        ldir

        ld      de,fname        ; read it back into page 1
        xor     a
        ld      c,_OPEN
        call    BDOS
        or      a
        jp      nz,fail_dos
        ld      a,b
        ld      (fh),a
        ld      de,4000h
        ld      hl,4000h
        ld      c,_READ
        call    BDOS
        or      a
        jp      nz,fail_dos
        call    close

        ld      hl,4000h
        ld      bc,4000h
        call    verify
        jp      nz,fail_rw
        ld      de,m_dot
        call    print
        ld      hl,iter
        dec     (hl)
        jr      nz,pass

        ld      de,m_ok
        call    print
        rst     0

close:
        ld      a,(fh)
        ld      b,a
        ld      c,_CLOSE
        jp      BDOS

; HL = start, BC = count. Z = all match, NZ = mismatch at HL.
verify:
        ld      a,l
        xor     h
        xor     0A5h
        cp      (hl)
        ret     nz
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,verify
        ret

fail_load:
        ld      de,m_fload
        jr      fail_at
fail_rw:
        ld      de,m_frw
fail_at:
        push    hl
        call    print
        pop     hl
        ld      a,h
        call    hex8
        ld      a,l
        call    hex8
        ld      de,m_crlf
        call    print
        rst     0
fail_dos:
        push    af
        ld      de,m_fdos
        call    print
        pop     af
        call    hex8
        ld      de,m_crlf
        call    print
        rst     0

hex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    hex4
        pop     af
hex4:
        and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,hex4p
        add     a,7
hex4p:
        push    hl
        ld      e,a
        ld      c,2
        call    BDOS
        pop     hl
        ret

print:
        ld      c,9
        jp      BDOS

fname:  db      "P1TEST.BIN",0
m_hello: db     "P1TEST: page-1 disk transfer test",13,10,"$"
m_loadok: db    "Load check OK (0400-A0FF)",13,10,"$"
m_dos1: db      "MSX-DOS 1: write/read test needs DOS 2, skipped",13,10,"PASS (load only)",13,10,"$"
m_rw:   db      "Write/read 16K at 4000: $"
m_dot:  db      ".$"
m_ok:   db      13,10,"PASS",13,10,"$"
m_fload: db     13,10,"FAIL: loaded image differs at $"
m_frw:  db      13,10,"FAIL: read-back differs at $"
m_fdos: db      13,10,"FAIL: DOS error $"
m_crlf: db      13,10,"$"
fh:     db      0
iter:   db      0
codeend:
        if      codeend > PADSTART
        error   "code overlaps the pattern area"
        endif
