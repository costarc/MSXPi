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
;
; File history :
; 0.1    : initial version
; 0.2    : Changed the tansfer routines for v1.1 interface
;
; TEXTTERMINATOR: EQU     0
; BDOS:           EQU     $F37D

;---------------------------
; ROM installer
;---------------------------
; BLOAD header: magic, start, LAST byte, entry.
;
; The image is two pieces - the installer at B000 and, right behind it in the
; file, the block it relocates to 4000 - so the last loaded byte is
;   rotina + (fim-romprog) - 1
; The old expression added 1 instead of subtracting it and so claimed two bytes
; more than the file holds. BLOAD stops at end of file either way, which is why
; it never showed.
        db    $fe
        dw    inicio
        dw    rotina+(fim-romprog)-1
        dw    inicio

        org     $b000

inicio:
        jr      inicio0
returncode:
        db      0
inicio0:
        ld      hl,msgstart
        call    localprint

        ld      c,040H
        call    PG1RAMSEARCH

        ei

        ld      hl,msgramnf
        jr      c,printmsg


        push    af
        call    ramcheck
        pop     af

        ld      hl,msgramnf
        jr      nz,printmsg

        push    af
        ld      hl,msgdoing
        call    localprint
        pop     af

        push    af
        call    relocprog
        pop     af

        and     %00000011
        ld      hl,SLTATR
        ld      de,16
        or      a
        jr      z,setcall2
        ld      b,a

setcall1:
        add     hl,de
        djnz    setcall1

setcall2:
        xor     a
        set     5,a
        inc     hl
        ld      (hl),a

        ld      hl,msgcallhlp
        call    localprint

; Reserve RAM for MSXPI commands
        ld      hl,MSXPICALLBUF
        ld      (HIMEM),hl
        ret

printmsg:
        call    localprint
        ret


relocprog:
        ld de, rotina
        ld hl, romprog
        ld bc, fim-romprog       ; exact size; the +1 here copied a stray byte

relocprog1:
        push    af
        push    bc
        push    de
        push    hl
        ld      c,a
        ld      a,(de)
        ld      e,a
        ld      a,c
        call    WRSLT
        pop     hl
        pop     de
        pop     bc
        pop     af
        inc     hl
        inc     de
        dec     bc
        push    af
        ld      a,b
        or      c
        jr      z,relocfinish
        pop     af
        jr      relocprog1

relocfinish:
        pop     af
        ret

msgstart:   db      "Search for ram in $4000",13,10,0
msgramnf:   db      "ram not found",13,10,0
msgdoing:   db      "Installing MSXPi extension...",13,10,0
msgcallhlp: db      "Installed. Use ",13,10
            db      "CALL MSXPI(",$22,"<option,><buffer,><commmand>",$22,") to run MSXPi Commands",13,10
            db      "CALL MSXPISEND(",$22,"<buffer>",$22,") to send data to RPi",13,10
            db      "CALL MSXPIRECV(",$22,"<buffer>",$22,") to read data from RPi",13,10
            db      "flag: 0=no screen output, 1=screen output(default), 2=store output in buffer", 13,10
            db      "buffer = valid hexadecimal number (4 digits)"
            db      13,10,0

ramcheck:
        push    af
        ld      e,$aa
        ld      hl,$4000
        call    WRSLT
        pop     af
        ld      hl,$4000
        call    RDSLT
        cp      $aa     ;set Z flag if found ram
        ret

localprint:
        ld      a,(hl)
        or      a
        ret     z
        call    CHPUT
        inc     hl
        jr      localprint


PG1RAMSEARCH:
        LD      HL,EXPTBL
        LD      B,4
        XOR     A
PG1RAMSEARCH1:
        AND     03H
        OR      (HL)
PG1RAMSEARCH2:
        PUSH    BC
        PUSH    HL
        LD      H,C
PG1RAMSEARCH3:
        LD      L,10H
PG1RAMSEARCH4:
        PUSH    AF
        CALL    RDSLT
        CPL
        LD      E,A
        POP     AF
        PUSH    DE
        PUSH    AF
        CALL    WRSLT
        POP     AF
        POP     DE
        PUSH    AF
        PUSH    DE
        CALL    RDSLT
        POP     BC
        LD      B,A
        LD      A,C
        CPL
        LD      E,A
        POP     AF
        PUSH    AF
        PUSH    BC
        CALL    WRSLT
        POP     BC
        LD      A,C
        CP      B
        JR      NZ,PG1RAMSEARCH6
        POP     AF
        DEC     L
        JR      NZ,PG1RAMSEARCH4
        INC     H
        INC     H
        INC     H
        INC     H
        LD      C,A
        LD      A,H
        CP      40H
        JR      Z,PG1RAMSEARCH5
        CP      80H
        LD      A,C
        JR      NZ,PG1RAMSEARCH3
PG1RAMSEARCH5:
        LD      A,C
        POP     HL
        POP     HL
        RET
    
PG1RAMSEARCH6:
        POP     AF
        POP     HL
        POP     BC
        AND     A
        JP      P,PG1RAMSEARCH7
        ADD     A,4
        CP      90H
        JR      C,PG1RAMSEARCH2
PG1RAMSEARCH7:
        INC     HL
        INC     A
        DJNZ    PG1RAMSEARCH1
        SCF
        RET

;---------------------------

rotina:

        org    $4000

romprog:

; ROM-file header
 
        DEFW    $4241,0,CALLHAND,0,0,0,0,0
 
 
;---------------------------
 
; General BASIC CALL-instruction handler
; The CALL MSXPI handler is shared with the MSX-DOS driver ROM: see
; asm-common/include/msxpi_call.asm.  Everything this file had of its own
; stopped assembling somewhere around v1.4 - it still called SENDPICMD,
; RECVDATA, PARMSEVAL and PIEXCHANGEBYTE.
        INCLUDE "msxpi_call.asm"

BIOSENTRYADDR:  EQU     $
; Entry vectors for programs that want the transport directly.  Renamed to
; the v1.6 routines; MSXPISEND, MSXPIRECV and PIEXCHANGEBYTE are gone with
; the byte-at-a-time protocol they belonged to, and nothing in the tree
; referenced this table, so the slots were not kept as stubs.
        DW      _MSXPIVER
        DW      _MSXPI
        DW      PerformHandshake
        DW      RECVDATA_ONEBLOCK
        DW      SENDDATA
        DW      SendCommandToMSXPi
        DW      CHKPIRDY
        DW      PIREADBYTE
        DW      PIWRITEBYTE
        DW      PRINT
        DW      PRINTNLINE
        DW      PRINTNUMBER
        DW      PRINTDIGIT
        DW      PRINTPISTDOUT

; ================================================================
; Text messages used in the loader
; ================================================================

MSXPIVERSION:
        DB      13,10,"MSXPi BIOS v1.6"
BuildId: DB ".20260912.048"
        DB      13,10
        DB      "    RCC (c) 2015-2026",0
        DB      "Commands available:",13,10
        DB      "MSXPI MSXPIVER",13,10,0


; ================================================================
; Table of Commands available/implemented
; ================================================================

CALL_TABLE:

        DB      "MSXPIVER",0
        DW      _MSXPIVER

        DB      "MSXPI",0
        DW      _MSXPI

ENDOFCMDS:
        DB      00

        INCLUDE "include.asm"
; msxpi_bios.asm needs MSXPI_RAM_STASH: this code runs from RAM after
; relocprog, so its local stash buffer is writable, and GETWRK - what the
; driver build uses instead - is DOS-only.  It comes from the build as
; -DMSXPI_RAM_STASH, not an equ here: sjasmplus IFDEF tests defines, not
; labels, so an equ would assemble and then silently do nothing.
        INCLUDE "msxpi_bios.asm"
        INCLUDE "putchar_msxdos.asm"
fim:    equ $
