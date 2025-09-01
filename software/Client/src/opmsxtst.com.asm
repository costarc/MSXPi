
	org		$100
	call	myCHKPIRDY
	jr		c,PRINTPIERR
	call	PRINTNUMBER
	ret
	
	
PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT	

;-----------------------
; CHKPIRDY             |
;-----------------------
myCHKPIRDY:
        ld      a,7
        out    ($AA),a
        in      a,($A9)
        bit     2,a                         ; Test ESC key 
        scf
        ret     z
		ld		a,CONTROL_PORT1
		call	PRINTNUMBER
        in      a,(CONTROL_PORT1)  ; verify spirdy register on the msxinterface
		push	af
		call	PRINTNUMBER
		pop		af
        or      a
		ret		z
		cp		2
		ret		z
        jr      myCHKPIRDY
		
PICOMMERR:  DB      "Communication Error",13,10,0

; Core MSXPi APIs / BIOS routines.
INCLUDE "include.asm"
INCLUDE "putchar_clients.asm"
INCLUDE "msxpi_bios.asm"

; All MSX-DOS programs must have this buf defined.
; It's used by the MSXPi APIs in several commands.

buf:    equ     $
        ds      BLKSIZE
        db      0