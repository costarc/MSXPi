;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.8                                                             |
;|                                                                           |
;| Copyright (c) 2015-2016 Ronivon Candido Costa (ronivon@outlook.com)       |
;|                                                                           |
;| All rights reserved                                                       |
;|                                                                           |
;| Redistribution and use in source and compiled forms, with or without      |
;| modification, are permitted under GPL license.                            |
;|                                                                           |
;|===========================================================================|
;|                                                                           |
;| This file is part of MSXPi Interface project.                             |
;|                                                                           |
;| MSX PI Interface is free software: you can redistribute it and/or modify  |
;| it under the terms of the GNU General Public License as published by      |
;| the Free Software Foundation, either version 3 of the License, or         |
;| (at your option) any later version.                                       |
;|                                                                           |
;| MSX PI Interface is distributed in the hope that it will be useful,       |
;| but WITHOUT ANY WARRANTY; without even the implied warranty of            |
;| MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             |
;| GNU General Public License for more details.                              |
;|                                                                           |
;| You should have received a copy of the GNU General Public License         |
;| along with MSX PI Interface.  If not, see <http://www.gnu.org/licenses/>. |
;|===========================================================================|
;
; File history :
; 0.1    : initial version
; Call entries:
;   $D000 - MSXPIRECV
;   $D003 - MSXPISEND
;---------------------------
; ROM installer
;---------------------------

BUFADDR:    EQU     $C000
TEXTTERMINATOR: equ 0
		db	$fe
		dw	inicio
        dw	fim
        dw  RETURNSCP 

        org     $B000
inicio:
        jp      MSXPIRECV
;----------------------------------------
; Call MSXPI BIOS function SENDDATABLOCK|
;----------------------------------------
MSXPISEND:
        LD      HL,BUFADDR
MSXPISEND1:
; Save buffer address to later store return code
        PUSH    HL
; First byte of buffer is saved to store return code
        INC     HL
; Next four bytes in buffer must be size of buffer (ASCII for equivalente HEX value)
; store buffer size in BC
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        INC     HL
        LD      D,H
        LD      E,L
        CALL    SENDDATABLOCK
; Restore buffer address
        POP     HL
; Return return code in 1st buffer position
        LD      (HL),A
RETURN:
        RET

;----------------------------------------
; Call MSXPI BIOS function RECVDATABLOCK|
;----------------------------------------
MSXPIRECV:
        LD      HL,BUFADDR
MSXPIRECV1:
        LD      D,H
        LD      E,L
        PUSH    HL
; Save first buffer address to store return core
        INC     DE
; Save two memory positions to store buffer size
        XOR     A
        LD      (DE),A
        INC     DE
        LD      (DE),A
        INC     DE
        CALL    RECVDATABLOCK
; Restore buffer address
        POP     HL
; Store return code into 1st position in buffer
        LD      (HL),A
        INC     HL
; Return buffer size to BASIC in first two positions of buffer
        LD      (HL),C
        INC     HL
        LD      (HL),B
MSXPIRECV2:
        RET
INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "basic_stdio.asm"
;INCLUDE "debug.asm"

fim:    equ $
