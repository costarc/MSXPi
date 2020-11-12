;|===========================================================================|
;|                                                                           |
;| MSX Command Line Parser for MSX-DOS 32K EEPROM                            |
;|                                                                           |
;| Version : 1.1                                                             |
;|                                                                           |
;| Copyright (c) 2020 Ronivon Candido Costa (ronivon@outlook.com)            |
;|                                                                           |
;| All rights reserved                                                       |
;|                                                                           |
;| Redistribution and use in source and compiled forms, with or without      |
;| modification, are permitted under GPL license.                            |
;|                                                                           |
;|===========================================================================|
;|                                                                           |
;| This file is part of msx_parms_parser project.                            |
;|                                                                           |
;| msx_parms_parser is free software: you can redistribute it and/or modify  |
;| it under the terms of the GNU General Public License as published by      |
;| the Free Software Foundation, either version 3 of the License, or         |
;| (at your option) any later version.                                       |
;|                                                                           |
;| MSX msx_parms_parser is distributed in the hope that it will be useful,   |
;| but WITHOUT ANY WARRANTY; without even the implied warranty of            |
;| MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             |
;| GNU General Public License for more details.                              |
;|                                                                           |
;| You should have received a copy of the GNU General Public License         |
;| along with msx_parms_parser.  If not, see <http://www.gnu.org/licenses/>. |
;|===========================================================================|
;
; Compile this file with z80asm:
;  z80asm parser.asm -o parser.com
; File history :
; 1.0  - 10/08/2020 : initial version
; 1.1  - 24/08/2020 : Improved parsing of file name
;
; How to use:
; 1. Define you options in the parms_table
; 2. Add your data / flags requirements in table data_option_<function name>
; 3. Each option must have a "dw nnnn" entry, which is a label to the routine
;    that will implement the logic for that option
; 4. Code the routine for that optin, as a regular sub-routine, terminating 
;    with "ret"
; 5. If that routine is self-contained and don't need any further processing,
;    add this code before the "ret" instruction: "xor a; ld (ignorerc),a" 
; 6. Inside a routine for each argument, you can establish the order of 
;    processing as you wish. For example, in the /file routine, you can check
;    if the another mandatory option was passed, as for example:
;    "/e" to encode or "d" to decode -> these needs a flag set in the table
;    data_option_<fucntion name>. If the value is $ff than the parameters was
;    not passed.
;=============================================================================

TESTCOUNTER: EQU 10

    org   $100
  
PTEST:
        LD      BC,5
        LD      DE,COMMAND
        CALL    DOSSENDPICMD

WAIT_LOOP:
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_WAIT
        JR      NZ,WAIT_RELEASED
        CALL    CHKPIRDY
        JR      WAIT_LOOP

WAIT_RELEASED:

        CP      RC_FAILED
        JP      Z,PRINTPISTDOUT
        CP      RC_SUCCESS
        JP      Z,MAINPROGRAM

PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

MAINPROGRAM:
        di
        ld     a,TESTCOUNTER
        call   PIEXCHANGEBYTE
        ld     c,TESTCOUNTER
loop:
        ld     b,0
        push   bc
        call   PRINTNLINE
        pop    bc
loop_internal:
        push   bc
        ld     a,b
        call   PIEXCHANGEBYTE
        call   PRINTNUMBER
        pop    bc
        inc    b
        ld     a,b
        or     a
        jr     nz,loop_internal
        dec    c
        ld     a,c
        or     a
        jr     nz,loop
        ei
        ret

PICOMMERR:
        DB      "Communication Error",13,10,"$"

COMMAND:  DB      "PTEST"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"
