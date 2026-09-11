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
; 1.2   : Updated to support msxpi_bios.asm v1.2 protocol and API routines
; 0.2   : Structural changes to support a simplified transfer protocol with error detection
; 0.1   : Initial version.
;
; This is a generic template for MSX-DOS command to interact with MSXPi
; This command must have an equivalent function in the msxpi-server.py program
; The function name must be the same defined in the "command" string in this program
;
        org     $0100

MAIN:
        call    resetMSXPI          ; Clear queue / reset MSXPi port state



; Send parameters passed via DOS CLI - mandatory for the template.com
		ld		hl,0x80		; address of the buffer containing DOS parameters
		ld		a,(hl)
		or		a
		jr		z,sendCmd
		ld		c,a
		ld		b,0
		inc		hl
		ld		de,parms
		ldir
		xor		a
		ld		(de),a
		
; Send Command to RPi
sendCmd:
        ld      de,command
        call    SendCommandToMSXPi
        jr      c, PRINTPIERR

; Read and display output from MSXPi
        ld      de,buf
        ld      bc,BLKSIZE
        call    CLEARBUF
        ld      de,buf
        ld      bc,BLKSIZE
        call    PRINTPISTDOUT
        call    PRINTNLINE
        ret
		
PRINTPIERR:
        ld      hl,PICOMMERR
        jp      PRINT

PICOMMERR:  db      "Communication Error",13,10,0

; Command maximum length is 8 characters. 
; Always terminate the command with a trailing zero

; Core MSXPi APIs / BIOS routines.
	INCLUDE "include.asm"
	INCLUDE "putchar_clients.asm"
	INCLUDE "msxpi_bios.asm"

; Buffer area used by MSXPi routines
command: db "template "
parms:
		db	0
		ds 255
buf:    equ     $
        ds      BLKSIZE
        db      0