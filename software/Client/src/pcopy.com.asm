;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 1.0                                                             |
;|                                                                           |
;| Copyright (c) 2015-2020 Ronivon Candido Costa (ronivon@outlook.com)       |
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
; 0.1    : Initial version.
; 1.0    : For MSXPi interface with /wait support

DSKBLOCKSIZE:   EQU 1

; Send command to RPi
        org     $0100
        ld      bc,COMMAND_END - COMMAND
        ld      hl,COMMAND
        call    DOSSENDPICMD
        call    PIREADBYTE    ; read return code
        cp      RC_WAIT
        call    z,CHKPIRDY
        call    PIREADBYTE 
        cp      RC_SUCCESS
        jp      nz,PRINTPISTDOUT

COPYFILE:
        call    PREP_FCB
        call    OPENFILEW
        jr      c,FOPENERR
        call    SETFILEFCB
        call    FILE_DOWNLOAD
        ld      hl,txt_commerr
        call    c,PRINT
        call    CLOSEFILE
        ret

FOPENERR:
        ld      a,RC_FAILED
        call    PIWRITEBYTE
        ld      hl,txt_fopenerr
        jp      PRINT

PREP_FCB:
        call    INIFCB
        ld      b,12
        ld      hl,FILEFCB
PREP_FCB1:
        call    PIREADBYTE
        ld      (hl),a
        inc     hl
        djnz    PREP_FCB1
        ret

; This routime will read the whole file from Pi
; it will use blocks size fixed on the RPi side
; Each block is written to disk after download
FILE_DOWNLOAD:

        LD      A,'.'
        CALL    PUTCHAR
        call    PIREADBYTE
        cp      ENDTRANSFER
        scf
        ccf
        ret     z
        cp     STARTTRANSFER
        jr     z,GETFILEWRITE
        call   PRINTNUMBER
        scf
        ret 

GETFILEWRITE:
; Buffer where data is stored during transfer, and also DMA for disk access

        ld      hl,DMA
        call    RECVDATABLOCK
        CALL    DBGAF
        jr      c,GETFILESENDRCERR

; Set HL with the number of bytes transfered, DE with the DMA adress
; When the RECVATABLOCK routine ends, BC number of bytes transfered

GETFILESAVE:
        ld      a,b
        or      c
        ret     z       ; file transfer completed
        ld      h,b
        ld      l,c
        call    DSKWRITEBLK
        ld      a,SENDNEXT
        call    PIWRITEBYTE
        jr      FILE_DOWNLOAD 

GETFILESENDRCERR:
        ld      a,'!'
        call    PUTCHAR
        ld      a,RESEND
        call    PIWRITEBYTE
        jr      FILE_DOWNLOAD 

OPENFILEW:
        LD      DE,FILEFCB
        LD      C,$16
        CALL    BDOS
        OR      A
        RET     Z
; Error opening file
        SCF
        RET


DSKWRITEBLK:
        LD      DE,FILEFCB
        LD      C,$26
        CALL    BDOS
        RET

INIFCB:
        EX      AF,AF'
        EXX
        LD      HL,FILEFCB
        LD      (HL),0
        LD      DE,FILEFCB+1
        LD      BC,$0023
        LDIR
        LD      HL,FILEFCB+1
        LD      (HL),$20
        LD      HL,FILEFCB+2
        LD      BC,$000A
        LDIR
        EXX
        EX AF,AF'
        RET

SETFILEFCB:
        LD      DE,DMA
        LD      C,$1A
        CALL    BDOS
        LD      HL,DSKBLOCKSIZE
        LD      (FILEFCB+$0E),HL
        LD      HL,0
        LD      (FILEFCB+$20),HL
        LD      (FILEFCB+$22),HL
        LD      (FILEFCB+$24),HL
        RET

CLOSEFILE:
        LD      DE,FILEFCB
        LD      C,$10
        CALL    BDOS
        RET

txt_fopenerr:  DB      "Error opening file",13,10,"$"

txt_savingfile:    DB "Saving file:$"
txt_diskerror:     DB "DISK IO ERROR",13,10,"$"
txt_commerr:       DB "Communication Error with Raspberry Pi",13,10,"$"

RUNOPTION:  db  0
SAVEOPTION: db  0
REGINDEX:   dw  0            

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

COMMAND:     DB      "pcopy"
COMMAND_SPC: DB " " ; Do not remove this space, do not add code or data after this buffer.
COMMAND_END: EQU $
             DS  128
FILEFCB:    ds     40

DMA:     EQU    $
