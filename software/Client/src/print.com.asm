; Example of String handling in BASIC CALL-instructions
; Made By: NYYRIKKI 16.11.2011
; Edit by: zPasi 13.3.2014: added a call to FRESTR, to free the temporary string in 
;       routine EVALTXTPARAM
 
        ORG     $4000

 
;---------------------------
 
; ROM-file header
 
        DEFW    $4241,0,CALLHAND,0,0,0,0,0
 
 
;---------------------------
 
; General BASIC CALL-instruction handler
 
CALLHAND:
 
	PUSH    HL
	LD	HL,CMDS	        ; Table with "_" instructions
.CHKCMD:
	LD	DE,PROCNM
LOOP:	LD	A,(DE)
	CP	(HL)
	JR	NZ,.TONEXTCMD	; Not equal
	INC	DE
	INC	HL
	AND	A
	JR	NZ,LOOP	; No end of instruction name, go checking
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
 
	DEFB	"UPRINT",0      ; Print upper case string
	DEFW	_UPRINT
 
	DEFB	"LPRINT",0      ; Print lower case string
	DEFW	_LPRINT
 
	DEFB	0               ; No more instructions
 
;---------------------------
_UPRINT:
	CALL	EVALTXTPARAM	; Evaluate text parameter
	PUSH	HL
        CALL    GETSTRPNT
ULOOP:
        LD      A,(HL)
        CALL    .UCASE
        CALL    CHPUT  ;Print
        INC     HL
        DJNZ    ULOOP
 
	POP	HL
	OR      A
	RET
 
.UCASE:
        CP      "a"
        RET     C
        CP      "z"+1
        RET     NC
        AND     %11011111
        RET
;---------------------------
_LPRINT:
	CALL	EVALTXTPARAM	; Evaluate text parameter
	PUSH	HL
        CALL    GETSTRPNT
LPLOOP:
        LD      A,(HL)
        CALL    .LCASE
        CALL    CHPUT  ;Print
        INC     HL
        DJNZ    LPLOOP
 
	POP	HL
	OR      A
	RET
 
.LCASE:
        CP      "A"
        RET     C
        CP      "Z"+1
        RET     NC
        OR      %00100000
        RET
;---------------------------
 
GETSTRPNT:
; OUT:
; HL = String Address
; B  = Lenght
 
        LD      HL,($F7F8)
        LD      B,(HL)
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        RET
 
EVALTXTPARAM:
	CALL	CHKCHAR
	DEFB	"("             ; Check for (
	LD	IX,FRMEVL
	CALL	CALBAS		; Evaluate expression
        LD      A,(VALTYP)
        CP      3               ; Text type?
        JP      NZ,TYPE_MISMATCH
        PUSH	HL
        LD	IX,FRESTR         ; Free the temporary string
        CALL	CALBAS
        POP	HL
	CALL	CHKCHAR
	DEFB	")"             ; Check for )
        RET
 
 
CHKCHAR:
	CALL	GETPREVCHAR	; Get previous basic char
	EX	(SP),HL
	CP	(HL) 	        ; Check if good char
	JR	NZ,SYNTAX_ERROR	; No, Syntax error
	INC	HL
	EX	(SP),HL
	INC	HL		; Get next basic char
 
GETPREVCHAR:
	DEC	HL
	LD	IX,CHRGTR
	JP      CALBAS
 
 
TYPE_MISMATCH:
        LD      E,13
        DB      1
 
SYNTAX_ERROR:
        LD      E,2
	LD	IX,ERRHAND	; Call the Basic error handler
	JP	CALBAS
 
;---------------------------
 
        DS      $8000-$
INCLUDE "include.asm"
