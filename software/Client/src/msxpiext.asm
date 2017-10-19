; External variables & routines
ERRHAND: EQU     $406F
FRMEVL:  EQU     $4C64
FRESTR:  EQU	 $67D0
VALTYP:  EQU     $F663
USR:     EQU     $F7F8
RAMAD3:  EQU     $F344

TEXTTERMINATOR: EQU '0'

;---------------------------
; ROM installer
;---------------------------
		db	$fe
		dw	inicio
        dw	fim-romprog+rotina+1
        dw  inicio

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

msgstart:   db      "Search for ram in $4000",13,10,0
msgramf:    db      "found ram",13,10,0
msgramnf:   db      "ram not found",13,10,0
msgdoing:   db      "Installing MSXPi extension...",13,10,0
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

;---------------------------

rotina:

        org	$4000

romprog:

; ROM-file header
 
        DEFW    $4241,0,CALLHAND,0,0,0,0,0
 
 
;---------------------------
 
; General BASIC CALL-instruction handler
 
CALLHAND:
 
	PUSH    HL
	LD	HL,CMDS	        ; Table with "_" instructions
.CHKCMD:
	LD	DE,PROCNM
.LOOP1:
LD	A,(DE)
	CP	(HL)
	JR	NZ,.TONEXTCMD	; Not equal
	INC	DE
	INC	HL
	AND	A
	JR	NZ,.LOOP1	; No end of instruction name, go checking
	LD	E,(HL)
	INC	HL
	LD	D,(HL)
	POP	HL		; routine address
	CALL	GETPREVCHAR
	CALL	.CALLDE		; Call routine
	AND	A
	RET
 
.TONEXTCMD:
	LD	C,0FFH
	XOR	A
	CPIR			; Skip to end of instruction name
	INC	HL
	INC	HL		; Skip address
	CP	(HL)
	JR	NZ,.CHKCMD	; Not end of table, go checking
	POP	HL
        SCF
	RET
 
.CALLDE:
	PUSH	DE
	RET
 
;---------------------------
CMDS:
 
; List of available instructions (as ASCIIZ) and execute address (as word)
 
	DEFB	"MSXPI",0      ; Print upper case string
	DEFW	CALL_MSXPI
 
	DEFB	"LPRINT",0      ; Print lower case string
	DEFW	_LPRINT
 
	DEFB	0               ; No more instructions
 
;---------------------------
CALL_MSXPI:
        CALL	EVALTXTPARAM	; Evaluate text parameter
        PUSH	HL
        CALL    GETSTRPNT

; DEBUG
        PUSH    DE
        PUSH    BC
        INC     DE
        DEC     BC
        CALL    _LPRINT
        POP     BC
        POP     DE
; END DEBUG

        LD      A,(DE)
        CP      '?'
        JR      Z,CALL_MSXPI0
        EX      DE,HL
        LD      E,'1'
        JR      CALL_MSXPI1

CALL_MSXPI0:
        PUSH    DE
        INC     DE
        CALL    SENDPICMD
        POP     HL
        LD      E,'1'
        JR      C,CALL_MSXPI1
        PUSH    HL
        CALL    PRINTPISTDOUT
        POP     HL
        LD      E,0

; return to BASIC
CALL_MSXPI1:
        LD      A,(RAMAD3)
        CALL    WRSLT
        POP     HL
        OR      A
        RET

_LPRINT:
        LD      A,(DE)
        CALL    CHPUT
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,_LPRINT
        RET

GETSTRPNT:
; OUT:
; HL = String Address
; BC = Length
 
        LD      HL,(USR)
        LD      C,(HL)
        LD      B,0
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        RET
 
EVALTXTPARAM:
        CALL	CHKCHAR
        DEFB	"("             ; Check for (
        LD      IX,FRMEVL
        CALL	CALBAS		; Evaluate expression
        LD      A,(VALTYP)
        CP      3               ; Text type?
        JP      NZ,TYPE_MISMATCH
        PUSH	HL
        LD      IX,FRESTR         ; Free the temporary string
        CALL	CALBAS
        POP     HL
        CALL	CHKCHAR
        DEFB	")"             ; Check for )
        RET
 
 
CHKCHAR:
        CALL	GETPREVCHAR	; Get previous basic char
        EX      (SP),HL
        CP      (HL) 	        ; Check if good char
        JR      NZ,SYNTAX_ERROR	; No, Syntax error
        INC     HL
        EX      (SP),HL
        INC     HL		; Get next basic char
     
GETPREVCHAR:
        DEC     HL
        LD      IX,CHRGTR
        JP      CALBAS
 
 
TYPE_MISMATCH:
        LD      E,13
        DB      1
 
SYNTAX_ERROR:
        LD      E,2
        LD      IX,ERRHAND	; Call the Basic error handler
        JP      CALBAS

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "basic_stdio.asm"

fim:    equ $
