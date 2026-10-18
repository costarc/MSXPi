; SOCCERNET.COM - milestone 1: boot Konami's Soccer from a RAM copy.
;
;   sjasmplus --raw=soccernet.com netplay\soccernet.asm
;
; Reads SOCCER.ROM from the current drive (MSX-DOS 1/2, Nextor), copies it
; into RAM at 4000h-BFFFh, neutralises the ROM's two anti-copy writes, and
; starts it the way the BIOS would. Needs RAM in pages 1 and 2 (any 64K MSX).
;
; Layout while loading:
;   0100h-1FFFh  this program
;   2000h-3FFFh  8K bounce buffer (DOS cannot DMA straight into page 1: the
;                disk ROM lives there)
;   8000h-BFFFh  ROM bytes 4000h-7FFFh, read straight in (page 2 is RAM)
;   C000h-       trampoline, copied there at the end

BDOS:           EQU     $0005
F_PRINT:        EQU     $09
F_OPEN:         EQU     $0F
F_DTAOFF:       EQU     $1A
F_RDRND:        EQU     $27

EXPTBL:         EQU     $FCC1
EXBRSA:         EQU     $FAF8
RAMAD1:         EQU     $F342
CALSLT:         EQU     $001C
ENASLT:         EQU     $0024
INIT32:         EQU     $006F
ROM_SUM_A:      EQU     $40                ; Fletcher-16 (mod 256) of the 32K ROM;
ROM_SUM_B:      EQU     $CE                ; check with netplay/software/Client/src/soccernet/rom_check.py
STUB:           EQU     $F000
        IFDEF NATIVE
        INCLUDE "stub_nat.inc"
        ELSE
        INCLUDE "stub.inc"
        ENDIF             ; pad1t, pad1c, pad2c, rng1, rng2, ROLE
BUF:            EQU     $2000
CHUNK:          EQU     $2000

        org     $0100

start:
        ld      hl,$0081                ; command tail: "C" = client, else host
.arg:   ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,.arg
        and     $DF
        cp      'C'
        ld      a,0
        jr      nz,.roleSet
        inc     a
.roleSet:
        ld      (role),a
        ld      de,msgLoad
        ld      c,F_PRINT
        call    BDOS

        ld      de,fcb
        ld      c,F_OPEN
        call    BDOS
        inc     a
        jp      z,errOpen
        ld      hl,1                    ; record size 1: counts are bytes
        ld      (fcb+14),hl

        call    getSlot1
        ld      (dosSlot1),a

        ; ROM bytes 4000h-7FFFh go to 8000h-BFFFh (page 2) with no copy
        ld      hl,$4000
        ld      de,$8000
        call    readAt
        jp      nz,errRead

        ; ROM bytes 0000h-3FFFh go to page 1 in two 8K bounces
        ld      hl,0
        ld      de,$4000
        call    bounce
        jp      nz,errRead
        ld      hl,CHUNK
        ld      de,$4000+CHUNK
        call    bounce
        jp      nz,errRead

        ld      de,msgGo
        ld      c,F_PRINT
        call    BDOS

        di
        ld      a,(RAMAD1)              ; pages 1 and 2 are both RAM now
        call    enaPage1
        call    checkRom
        jr      z,.romOk
        ld      a,(dosSlot1)            ; wrong dump: give DOS its page back
        call    enaPage1
        ei
        ld      de,msgSum
        jp      fail
.romOk: ld      hl,patches
        call    applyPatches
        ld      hl,stubSrc              ; resident stub into page 3
        ld      de,STUB
        ld      bc,stubEnd-stubSrc
        ldir
        ld      a,(role)
        ld      (ROLE),a
        ld      hl,trampSrc
        ld      de,$C000
        ld      bc,trampEnd-trampSrc
        ldir
        jp      $C000

; HL = file offset, DE = destination (page 2). Reads $4000 bytes.
; Returns Z on success.
readAt:
        push    de
        ld      (fcb+33),hl
        ld      hl,0
        ld      (fcb+35),hl
        ld      c,F_DTAOFF
        call    BDOS                    ; DE = DMA address
        ld      de,fcb
        ld      hl,$4000
        ld      c,F_RDRND
        call    BDOS
        pop     de
        or      a
        ret

; HL = file offset, DE = destination in page 1. Reads CHUNK bytes into BUF,
; then switches page 1 to RAM, copies, and gives page 1 back to DOS.
bounce:
        push    de
        ld      (fcb+33),hl
        ld      hl,0
        ld      (fcb+35),hl
        ld      de,BUF
        ld      c,F_DTAOFF
        call    BDOS
        ld      de,fcb
        ld      hl,CHUNK
        ld      c,F_RDRND
        call    BDOS
        pop     de
        or      a
        ret     nz

        di
        push    de
        ld      a,(RAMAD1)
        call    enaPage1
        pop     de
        push    de
        ld      hl,BUF
        ld      bc,CHUNK
        ldir
        pop     de
        ld      a,(dosSlot1)
        call    enaPage1
        ei
        xor     a
        ret

; Fletcher-16 (mod 256) over 4000h-BFFFh. Z if it is the known dump.
checkRom:
        ld      hl,$4000
        ld      bc,0                    ; B = sum of sums, C = sum
        ld      de,$8000
.sum:   ld      a,c
        add     a,(hl)
        ld      c,a
        add     a,b
        ld      b,a
        inc     hl
        dec     de
        ld      a,d
        or      e
        jr      nz,.sum
        ld      a,c
        cp      ROM_SUM_A
        ret     nz
        ld      a,b
        cp      ROM_SUM_B
        ret

; HL = table of (addr.w, len.b, bytes...) ending with addr 0.
applyPatches:
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,d
        or      e
        ret     z
        ld      b,0
        ld      c,(hl)
        inc     hl
        ldir
        jr      applyPatches

; A = slot code. Select it in page 1 through the BIOS ENASLT, reached with
; CALSLT because page 0 is DOS RAM here. Interrupts stay off.
enaPage1:
        ld      h,$40
        ld      iy,(EXPTBL-1)
        ld      ix,ENASLT
        call    CALSLT
        di
        ret

; The slot code (ENASLT format) now in page 1. The BIOS keeps a copy of each
; expanded slot's sub-slot register in SLTTBL (EXPTBL+4).
getSlot1:
        in      a,($A8)
        rrca
        rrca
        and     3
        ld      c,a
        ld      b,0
        ld      hl,EXPTBL
        add     hl,bc
        or      (hl)
        ret     p
        ld      c,a
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)
        and     $0C
        or      c
        ret

errOpen:
        ld      de,msgOpen
        jp      fail
errRead:
        ld      de,msgRead
fail:
        ld      c,F_PRINT
        call    BDOS
        rst     0

; Patches to the RAM copy. 00 00 00 = NOPs over the ROM's self-modifying
; anti-copy writes (they hit ROM on a cartridge and so do nothing there).
patches:
        defw    $4028 : defb 3 : defb 0,0,0     ; ld (410Ah),hl
        defw    $4056 : defb 3 : defb 0,0,0     ; ld (4116h),hl
        defw    $40C3 : defb 2 : defb 0,0       ; res 6,(hl) on the R1 template
        ; pad reads: call lee_el_mando_1 / _2 -> stub (4 call sites)
        defw    $4565 : defb 2 : defw pad1c     ; cached P1
        defw    $456A : defb 2 : defw pad2c     ; cached P2
        defw    $4897 : defb 2 : defw pad1t     ; once per frame: network tick
        defw    $48AD : defb 2 : defw pad2c     ; cached P2
        ; sound: latido ticks the driver once per interrupt and once more when
        ; an interrupt is pending after the frame, so its state follows timing,
        ; not game frames - and step 4 of the match set-up waits on it. Both
        ; calls become NOPs and the stub ticks once per frame instead.
        defw    $4032 : defb 3 : defb 0,0,0
        defw    $404E : defb 3 : defb 0,0,0
        ; The game zero-fills E000-F37F at INIT (ld bc,137Fh at 40A4h) and again
        ; at every match reset (ld bc,119Fh at 45A8h, from E0E0). A write watch
        ; over a run through the title, demo, set-up and match found no other
        ; writer in ED30-F2FF, so both clears stop at EFFF and the stub lives at
        ; F000-F27F. Operands: 137Fh -> 0FFFh and 119Fh -> 0F1Fh (E0E0+0F1F=EFFF).
        defw    $40A5 : defb 2 : defw $0FFF
        defw    $45A9 : defb 2 : defw $0F1F
        IFNDEF NORNG
        ; R-register coin flips -> frame counter
        defw    $B006 : defb 3 : defb $CD : defw rng1
        defw    $B028 : defb 4 : defb $CD : defw rng2 : defb 0
        ENDIF
        defw    0

stubSrc:
        IFDEF NATIVE
        INCBIN  "stub_nat.bin"
        ELSE
        INCBIN  "stub.bin"
        ENDIF
stubEnd:

fcb:    defb    0
        defb    'SOCCER  '
        defb    'ROM'
        defs    28, 0
dosSlot1: defb  0
role:   defb    0

msgLoad: defb   "Loading SOCCER.ROM into RAM...",13,10,"$"
msgGo:   defb   "Starting.",13,10,"$"
msgOpen: defb   "Cannot open SOCCER.ROM",13,10,"$"
msgSum:  defb   "SOCCER.ROM is not the supported dump (see software/Client/src/soccernet/rom_check.py)",13,10,"$"
msgRead: defb   "Read error on SOCCER.ROM",13,10,"$"

; ---------------------------------------------------------------------------
; Runs from C000h with page 0 = main ROM and page 1 = RAM holding the game.
; ---------------------------------------------------------------------------
trampSrc:
        PHASE   $C000
        ld      a,$C9                   ; no MSX-DOS timer hook
        ld      ($FD9F),a
        ld      a,(EXPTBL)              ; main BIOS slot into page 0
        and     3
        ld      c,a
        in      a,($A8)
        and     $FC
        or      c
        out     ($A8),a

        ld      a,(RAMAD1)              ; RAM, holding the game, into page 1
        ld      h,$40
        call    ENASLT
        di

        ; Hooks left by DOS that point outside the BIOS become RET, as a
        ; bare cartridge would see them (same trick as msxarch).
        ld      hl,$FD9A
.hook:  ld      a,(hl)
        cp      $F7
        jr      nz,.next
        inc     hl
        ld      b,(hl)
        dec     hl
        ld      a,(EXPTBL)
        cp      b
        jr      z,.next
        ld      a,(EXBRSA)
        cp      b
        jr      z,.next
        ld      (hl),$C9
.next:  ld      de,5
        add     hl,de
        ld      a,h
        cp      $FF
        jr      nz,.hook
        ld      a,l
        cp      $CF
        jr      c,.hook

        call    INIT32                  ; SCREEN 1, as before a cartridge INIT
        ld      hl,($4002)              ; INIT (4070h); it never returns
        jp      (hl)
        DEPHASE
trampEnd:
