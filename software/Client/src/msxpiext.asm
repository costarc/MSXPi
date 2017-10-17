

TEXTTERMINATOR: EQU     0

Target_address: equ 04000H
Target_slot: equ 001H
Slot_register: equ 0A8H

		db	$fe
		dw	inicio
        dw	fim-romprog+rotina+1
        dw  inicio

        org     $b000

inicio:
        ld      hl,msgstart
        call    localprint

        ld      c,040H
        call    PG1RAMSEARCH

        ei

        ld      hl,msgramnf
        jr      c,printmsg

instcall:

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
setcall1:   add     hl,de
        djnz    setcall1
setcall2:   xor     a
        set     5,a
        inc     hl
        ld      (hl),a
        ret

printmsg:
        call    localprint
        ret



relocprog:
        ld de, rotina
        ld hl, romprog
        ld bc, fim-romprog+1

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

msgstart:   db      "Starting search for ram $4000",13,10,0
msgramf:    db      "found ram",13,10,0
msgramnf:   db      "ram not found",13,10,0
msgdoing:   db      "relocating code",13,10,0
msgdone:    db      "relocate completed",13,10,0

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
		call	CHPUT
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

rotina:
        org	$4000

romprog:
        db	$41,$42
		dw	$0000
		dw	iniromprog
		ds	10

iniromprog:
		push    hl
		ld      de,comandos
CALL_CHECK:
		ld      hl,PROCNM
CHECKCMD:
        ld      a,(de)
        or      a
        jr      z,FOUNDCMD
		cp      (hl)
		jr		nz,CHECKIFFOUND
        inc     de
		inc     hl
        jr      CHECKCMD

CHECKIFFOUND:
        ld      a,(hl)
        cp      13
        jr      z,FOUNDCMD
        cp      10
		jr		z,FOUNDCMD
        cp      32
		jr		nz,CHECKNEXT

FOUNDCMD:
        inc     de
		ld		a,(de)
        ld      l,a
		inc     de
		ld		a,(de)
        ld      h,a
		call	MYCOMMAND
		pop     hl
        call	GETPREVCHAR
		or		a
		ret

; Find entry address of next command to test
CHECKNEXT:
		ld      a,(de)
        call    CHPUT
		inc		de
        or      a
        jr      nz,CHECKNEXT
        ld      a,(de)
        or      a
        jr		nz,CALL_CHECK	;Check next command
		pop		hl
        scf
		ret
 
MYCOMMAND:
		push	hl
		ret

CALL_PCD:
        LD      BC,3
        LD      DE,PCDCMD
        CALL    DOSSENDPICMD
        JR      C,PRINTPIERR
        CALL    PRINTPISTDOUT
        JP      0

PRINTPIERR:
        LD      HL,PICOMMERR
        CALL    PRINT
        JP      0

PCDCMD: DB      "PCD"

command1:
        ld      hl,msgcallworked1
        call 	printb
        ret

command2:
        ld      hl,msgcallworked2
		call 	printb
		ret

CALL_DEBUG:
        ld      a,(hl)
        or      a
        jr      z,foundzero
        cp      13
        jr      z,found13
        cp      10
        jr      z,found10
        call    CHPUT
        inc     hl
        jr      CALL_DEBUG
foundzero:
        ld      hl,msgfoundzero
        jr      printb
found13:
        ld      hl,msgfound13
        jr      printb
found10:
        ld      hl,msgfound10

printb:
        ld      a,(hl)
		or      a
		ret     z
		call	PUTCHAR
		inc     hl
		jr      printb

msgfoundzero:
        db      "found zero",13,10,0
msgfound10:
        db      "found 10",13,10,0
msgfound13:
        db      "found 13",13,10,0

GETPREVCHAR:
        dec     hl
        ld      IX,CHRGTR
        jp      CALBAS

DOSSENDPICMD:

comandos:
        db      "PCD",0
        dw      command1

        db      "COMMAND2",0
        dw      command2

        db      "CALL_DEBUG",0
        dw      CALL_DEBUG

        db      0

PICOMMERR:
        db      "Communication Error",13,10,0

msgcallworked1:
        db      "command1 executed in $4000",13,10,0
msgcallworked2:
        db      "command2 executed in $4000",13,10,0
msgcallworked3:
        db  "   command3 executed in $4000",13,10,0

sltrampg1:
        db      $00
ptrbasic:
        dw      $0000

        db      00
        db      00

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "basic_stdio.asm"

fim:    equ	$

