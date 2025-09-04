; MSXPi Interface
; Version 1.1 
; ------------------------------------------------------------------------------
; MIT License
; 
; Copyright (c) 2024 Ronivon Costa
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
; -----------------------------------------------------------------------------
;
; File history :
; 0.2   : Structural changes to support a simplified transfer protocol with error detection
; 0.1    : Initial version.
;
; This is a generic template for MSX-DOS command to interact with MSXPi
; This command must have a equivalent function in the msxpi-server.py program
; The function name must be the same defined in the "command" string in this program
;
        org     $0100
        
; Sending Command and Parameters to RPi
        ld      de,command
        call    localSENDCOMMAND
		call	localRECEIVEDATA
		ret

localSENDCOMMAND:
		; send sync byte
		ld 		a,READY
		out		(DATA_PORT1),a
localSENDCOMMAND1:
		ld		a,(de)
		or		a
		ret		z
		out		(DATA_PORT1),a
		inc		de
		jr		localSENDCOMMAND1	; pick next byte 

localRECEIVEDATA:
		; send sync byte
		ld 		a,READY
		out		(DATA_PORT1),a
		ld		b,8

localRECEIVEDATA1:
		xor 	a
		out		(CONTROL_PORT1),a	; send read command to MSXPi
		push	bc
		call	delay
		in		a,(DATA_PORT1)		; read one byte
		call	PUTCHAR
		pop		bc
		djnz	localRECEIVEDATA1
        ret
 
delay:
		ld		bc,65535
delay1:
		dec		bc
		ld		a,b
		or		c
		jr		nz,delay1
		ret
		
command: db "mycommand",0

; Core MSXPi APIs / BIOS routines.
INCLUDE "include.asm"
INCLUDE "putchar_clients.asm"
INCLUDE "msxpi_bios.asm"

; All MSX-DOS programs must have this buf defined.
; It's used by the MSXPi APIs in several commands.

buf:    equ     $
        ds      BLKSIZE
        db      0


