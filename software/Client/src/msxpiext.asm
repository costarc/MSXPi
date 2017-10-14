
chput:    equ	$00a2
txttab:   equ	$f676
vartab:   equ	$f6c2
arytab:   equ	$f6c4
strend:   equ	$f6c6
SLTATR:   equ	$fcc9
PROCNM:   equ	$fd89
EXPTBL:   equ $fcc1
RDSLT:    equ $000c
WRSLT:    equ $0014
CALSLT:   equ $001C
ENASLT:   equ $0024
CALBAS:   equ $0159
CHRGTR:   equ $4666


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
            call    print

;-----------------------------------

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
            call    print
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
            call    print
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

print:
        ld	a,(hl)
		or	a
		ret	z
		call	chput
		inc	hl
		jr	print


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
		ld      hl,comandos
CALL_CHECK:
		ld      de,PROCNM
CHECKCMD:
        ld      a,(de)
		cp      (hl)
		jr		nz,CHECKNEXT
		inc     de
		inc     hl
		or		a
		jr		nz,CHECKCMD
		ld		e,(hl)
		inc     hl
		ld		d,(hl)
		call	MYCOMMAND
		pop     hl
        call	GETPREVCHAR
		or		a
		ret

; Find entry address of next command to test
CHECKNEXT:
		ld		c,0FFH
		xor		a
		cpir
		inc		hl
		inc		hl
        cp		(hl)
		jr		nz,CALL_CHECK	;Check next command
		pop		hl
        scf
		ret
 
MYCOMMAND:
		push	de
		ret

command1:
        ld	hl,msgcallworked1
		call 	printb
		ret

command2:
        ld	hl,msgcallworked2
		call 	printb
		ret

command3:
        ld	hl,msgcallworked3
		call 	printb
		ret

printb:
        ld	a,(hl)
		or	a
		ret	z
		call	chput
		inc	hl
		jr	printb


GETPREVCHAR:
        dec     hl
        ld      IX,CHRGTR
        jp      CALBAS


comandos:	db	"COMMAND1",0
            dw  command1

            db	"COMMAND2",0
            dw  command2

            db	"COMMAND3",0
            dw  command3

            db  0

msgcallworked1:
            db  "command1 executed in $4000",13,10,0
msgcallworked2:
            db  "command2 executed in $4000",13,10,0
msgcallworked3:
            db  "command3 executed in $4000",13,10,0

sltrampg1:  db  $00
ptrbasic:	dw	$0000

            db  00
            db  00
fim:        equ	$

