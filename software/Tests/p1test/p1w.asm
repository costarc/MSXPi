; MSXPi Interface
; Version 1.6
; ------------------------------------------------------------------------------
; MIT License
;
; Copyright (c) 2015-2026 Ronivon Costa
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
; ------------------------------------------------------------------------------

; P1W.COM - page-1 disk WRITE and read test for MSX-DOS 1 (FCB calls).
;
; P1TEST.COM only writes on DOS 2 / Nextor, and Nextor never hands a legacy
; driver a page-1 buffer - so without this nothing makes MSXPi's DSKIO write a
; sector whose buffer is in 4000-7FFF, the case staged through the kernel's
; $SECBUF (DSKIO_WRITE_STAGED / DSKIO_READ_COPY in msxpi-driver.mac).
;
; Ten passes on the current drive:
;   fill 4000-7FFF with the pattern, create P1W.BIN, DTA = 4000h,
;   random block write 16 KB, close, clear 4000-7FFF, open,
;   random block read 16 KB into 4000h, close, verify.
; Prints PASS, or FAIL with the step or the first differing address.
; Pattern byte at address a: low(a) XOR high(a) XOR 0A5h (as P1TEST).
; Build: python3 build.py (also builds P1TEST.COM).

BDOS    equ     5
_OPEN   equ     0Fh
_CLOSE  equ     10h
_DELETE equ     13h
_CREATE equ     16h
_SETDTA equ     1Ah
_WRBLK  equ     26h
_RDBLK  equ     27h
PASSES  equ     10

        org     0100h
start:
        ld      de,m_hello
        call    print
        ld      a,PASSES
        ld      (iter),a
pass:
        ld      hl,4000h        ; fill page 1 with the pattern
        ld      bc,4000h
fill:   ld      a,l
        xor     h
        xor     0A5h
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,fill

        call    fcb_reset
        ld      de,fcb          ; remove any old copy, then create
        ld      c,_DELETE
        call    BDOS
        call    fcb_reset
        ld      de,fcb
        ld      c,_CREATE
        call    BDOS
        or      a
        ld      de,m_fcreate
        jp      nz,fail_msg
        call    fcb_block
        ld      de,4000h        ; write straight from page 1
        ld      c,_SETDTA
        call    BDOS
        ld      de,fcb
        ld      hl,4000h        ; 16384 records of 1 byte
        ld      c,_WRBLK
        call    BDOS
        or      a
        ld      de,m_fwrite
        jp      nz,fail_msg
        ld      de,fcb
        ld      c,_CLOSE
        call    BDOS

        ld      hl,4000h        ; wipe page 1
        ld      de,4001h
        ld      bc,3FFFh
        ld      (hl),0
        ldir

        call    fcb_reset
        ld      de,fcb
        ld      c,_OPEN
        call    BDOS
        or      a
        ld      de,m_fopen
        jp      nz,fail_msg
        call    fcb_block
        ld      de,4000h        ; read straight into page 1
        ld      c,_SETDTA
        call    BDOS
        ld      de,fcb
        ld      hl,4000h
        ld      c,_RDBLK
        call    BDOS
        or      a
        ld      de,m_fread
        jp      nz,fail_msg
        ld      de,fcb
        ld      c,_CLOSE
        call    BDOS

        ld      hl,4000h        ; verify
        ld      bc,4000h
ver:    ld      a,l
        xor     h
        xor     0A5h
        cp      (hl)
        jr      nz,fail_ver
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,ver

        ld      de,m_dot
        call    print
        ld      hl,iter
        dec     (hl)
        jp      nz,pass
        ld      de,m_ok
        call    print
        rst     0

; FCB: drive 0 (current), name P1W.BIN, everything after the name zeroed.
fcb_reset:
        ld      hl,fcbname
        ld      de,fcb
        ld      bc,12
        ldir
        ld      hl,fcb+12
        ld      de,fcb+13
        ld      bc,37-13
        ld      (hl),0
        ldir
        ret

; After open/create: record size 1, random record 0.
fcb_block:
        ld      hl,1
        ld      (fcb+14),hl
        ld      hl,0
        ld      (fcb+33),hl
        ld      (fcb+35),hl
        ret

fail_ver:
        push    hl
        ld      de,m_fver
        call    print
        pop     hl
        ld      a,h
        call    hex8
        ld      a,l
        call    hex8
        ld      de,m_crlf
        call    print
        rst     0
fail_msg:
        call    print
        rst     0

hex8:   push    af
        rrca
        rrca
        rrca
        rrca
        call    hex4
        pop     af
hex4:   and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,hex4p
        add     a,7
hex4p:  push    hl
        ld      e,a
        ld      c,2
        call    BDOS
        pop     hl
        ret

print:  ld      c,9
        jp      BDOS

fcbname: db     0,"P1W     BIN"
fcb:    ds      37
iter:   db      0
m_hello: db     "P1W: page-1 write/read test (DOS1 FCB)",13,10,"$"
m_dot:  db      ".$"
m_ok:   db      13,10,"PASS",13,10,"$"
m_fcreate: db   13,10,"FAIL: create",13,10,"$"
m_fopen: db     13,10,"FAIL: open",13,10,"$"
m_fwrite: db    13,10,"FAIL: block write",13,10,"$"
m_fread: db     13,10,"FAIL: block read",13,10,"$"
m_fver: db      13,10,"FAIL: read-back differs at $"
m_crlf: db      13,10,"$"
codeend:
        if      codeend > 3E00h
        error   "code must stay below page 1"
        endif
