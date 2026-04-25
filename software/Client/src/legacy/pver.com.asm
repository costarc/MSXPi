; MSXPi Interface
; Version 1.3 
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

; Print hw interface version (CPLD logic and pcb)
        LD      HL,HWVER
        CALL    PRINT
        IN      A,(CONTROL_PORT2)
        CALL    DESCHWVER
        call    PRINTNLINE

; Sending Command and Parameters to RPi
GETSWVER:
        ld      de,command
        call    SENDCOMMAND
        jr      c, PRINTPIERR
        ld      de,buf
MAINPROG:
        ld      bc,BLKSIZE
        call    CLEARBUF
        push    de
        call    RECVDATA
        pop     de
        jr      c, PRINTPIERR
        inc     de
        inc     de
        inc     de
        call    PRINTPISTDOUT
        ld      de,buf
        ld      a,(de)
        cp      RC_READY
        jr      z,MAINPROG
        call    PRINTNLINE
        ret
        
PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

PICOMMERR:  DB      "Communication Error",13,10,0
        
DESCHWVER:
		ld		hl,openMSX
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
		cp		$fe				; openMSX extension
		jr		z,PRINTIFVER
        ld      hl,iftable
DESCHWVER0:
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        or      a
        jr      z,PRINTIFVER
        dec     a
        jr      DESCHWVER0

PRINTIFVER:
        ld      h,d
        ld      l,e
        call    PRINT
        ret

iftable:
        dw      ifdummy
        dw      ifv1
        dw      ifv2
        dw      ifv3
        dw      ifv4
        dw      ifv5
        dw      ifv6
        dw      ifv7
        dw      ifv8
        dw      ifv9
        dw      ifvA
        dw      ifvB
		dw      ifv121b
		dw      ifv13PLCC
        dw      ifukn
openMSX:dw      omsx
ifv1:   DB      "(0001) Wired up prototype, EPM3064ALC-44",0
ifv2:   DB      "(0010) Semi-wired up prototype, EPROM 27C256, EPM3064ATC-44",0
ifv3:   DB      "(0011) Limited 10-samples PCB, EPROM 27C256, EPM3064ALC-44",0
ifv4:   DB      "(0100) Limited 1 sample PCB, EPROM 27C256, EPM3064ALC-44, 4 bits mode",0
ifv5:   DB      "(0101) Limited 10 samples PCB Rev.3, EPROM 27C256, EPM3064ALC-44",0
ifv6:   DB      "(0110) Wired up prototype, EPROM 27C256, EPM7128SLC-84",0
ifv7:   DB      "(0111) General Release V0.7 Rev.4, EPROM 27C256, EPM3064ALC-44",0
ifv8:   DB      "(1000) Limited 10 samples, Big v0.8.1 Rev.0, EPM7128SLC-84",0
ifv9:   DB      "(1001) General Release V1.0 Rev 0, EPROM 27C256, EPM3064ALC-44",0
ifvA:   DB      "(1010) General Release V1.1 Rev 0, EEPROM AT28C256, EPM3064ALC-44",0
ifvB:   DB      "(1011) General Release V1.2 Rev 0, EEPROM AT28C256, EPM3064ALC-44",0
ifv121b:DB      "(1100) General Release V1.2.1b, EEPROM AT28C256, EPM3064ALC-44",0
ifv13PLCC:DB    "(1101) General Release V1.3, EEPROM PLCC AT28C256, EPM3064ALC-44",0
ifukn:   DB      "Could not identify. Possibly an earlier version with old CPLD logic",0
ifdummy:DB      "MSXPi not detected - may need firmware update",0
omsx:   DB      " (FE)  General Release V1.2 Rev 0, MSXPi Extension for openMSX",0

HWVER:  DB      "PCB version:"
        DB      0

SRVVER: DB      "MSXPi Server version:"
        DB      0

ROMCER: DB      "MSXPi ROM version:"
        DB      0

PVERHWNFSTR:
        DB      "MSXPi Interface not found",0

command: db "pver",0

INCLUDE "include.asm"
INCLUDE "putchar_clients.asm"
INCLUDE "msxpi_bios.asm"
buf:    equ     $
        ds      BLKSIZE
        db      0