;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.6d                                                            |
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
; 0.6d   :   Changed header of ROM to: <size><exec address><rom binary>
;            Size and exec address are two bytes long each.
;            Size is inserted by the MSXPi Server App.
; 0.6c   :   Initial version commited to git
;

MSXLOADERADDR:  equ     $C000

MODEL4b:        EQU     0

CHPUT:          EQU     00A2H

                ORG     MSXLOADERADDR

        LD      A,2
        CALL    TRANSFBYTE
        JR      C,LOADERERR

; Start reading data from Pi
; First two bytes is the ROM size

; Read MSB of ROM size and store in D

        CALL    READBYTE
        LD      E,A

;       Read LSB of ROM size, and store in E
        CALL    READBYTE
        LD      D,A

; Read MSB of ROM EXEC Address and store in H

        CALL    READBYTE
        LD      L,A

;       Read LSB of ROM EXEC Address and store in L
        CALL    READBYTE
        LD      H,A

;       Now have DE set to the number of bytes to transfer,
;       And HL set to the execution address.

        LD      (MSXPICLIADDR),HL

;       This is the main loop to load the ROM

LOADER:

;       Read one byte

        CALL    READBYTE
        JR      C,LOADERERR

;       Store in memory

        LD      (HL),A
        INC     HL
        DEC     DE
        LD      A,D
        OR      E

;       Verify if all bytes has been read, otherwise read one more

        JR      NZ,LOADER
;       Execute the ROM file that was just loaded

        LD      HL,(MSXPICLIADDR)
        JP      (HL)

;       This routine will send READBYTE command (0) to port 6
;       and waity until Pi respond with a Ready signal
;       Then the MSX will read port 7, which contains the byte

LOADERERR:
        LD      HL,PIOFFLINESTR_B
        CALL    PRINT_B
        RET
; ================================================================
; Functions to support the commands
; ================================================================

PRINT_B:
        LD	A,(HL)		;get a character to print
        OR	A
        RET	Z
        CALL	CHPUT		;put a character
        INC	HL
        JR	PRINT_B

; ==================================================================
; BASIC I/O FUNCTIONS STARTS HERE.
; These are the lower level I/O routines available, and must match
; the I/O functions implemented in the CPLD.
; Other than using these functions you will have to create your
; own commands, using OUT/IN directly to the I/O ports.
; ==================================================================

IF MODEL4b
    INCLUDE    "msxpi_io_4bits.asm"
ELSE
    INCLUDE    "msxpi_io.asm"
ENDIF

; ================================================================
; END of BASIC I/O FUNCTIONS
; ================================================================

PIOFFLINESTR_B:

        DB      "Raspberry PI not responding",13,10
        DB      "Verify if server App is running",13,10
        DB      00

MSXPICLIADDR:
        DW      $0000
