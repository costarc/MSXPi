;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 1.1                                                             |
;|                                                                           |
;| Copyright (c) 2015-2023 Ronivon Candido Costa (ronivon@outlook.com)       |
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
; 0.2   : Structural changes to support a simplified transfer protocol with error detection
; 0.1    : Initial version.
;
; This is a generic template for MSX-DOS command to interact with MSXPi
; This command must have a equivalent function in the msxpi-server.py program
; The function name must be the same defined in the "command" string in this program
;

DSKBLOCKSIZE:   EQU 1

        org     $0100
        
; Sending Command and Parameters to RPi
        ld      de,command  
        call    SENDCOMMAND
        jr      c, PRINTPIERR 
        call    SENDPARMS
        jr      c, PRINTPIERR 
        
MAINPROG:
        call    CLEARBUF
        ld      de,buf
        ld      bc,MSGSIZE
        call    RECVDATA        ; Receive RC and FCB data if successful
        jr      c, PRINTPIERR        
        
        ld      hl,buf
        ld      a,(hl)
        inc     hl
        cp      RC_FAILED   
        ld      bc,MSGSIZE
        jp      z,PRINTPISTDOUT            ; if received data correctly, display in screen
        cp      RC_TERMINATE
        ret     z
        INC         HL
        INC         HL
        INC         HL
        INC         HL              ; Point to the start of the data to fill the FCB

; UpdateFCB with the data received from RPi
        LD      DE,FILEFCB
        LD      BC,12
        LDIR

        CALL    PRINTFNAME

        CALL    OPENFILEW

        CALL    SETFILEFCB

        CALL    GETFILE
        JR      C,PRINTPIERR

        CALL    CLOSEFILE

        JP      0
        
PRINTPIERR:
        LD      HL,PICOMMERR
        JP      PRINT

PRINTFNAME:
        LD      HL,FNTITLE
        CALL    PRINT
        LD      HL,FILEFCB
        ld      a,(HL)
        INC     HL
        OR      A
        JR      Z,PRINTFNAME2
        CP      1
        LD      A,'A'
        JR      Z,PRINTFNAME1
        LD      A,'B'
PRINTFNAME1:
        CALL    PUTCHAR
        LD      A,':'
        CALL    PUTCHAR
PRINTFNAME2:
        LD      B,8
        CALL    PLOOP
        LD      A,'.'
        CALL    PUTCHAR
        LD      B,3
        CALL    PLOOP
        CALL    PRINTNLINE
        RET
PLOOP:
        LD      A,(HL)
        CALL    PUTCHAR
        INC     HL
        DJNZ    PLOOP
        RET

; This routime will read the whole file from Pi
; it will use blocks size SECTORSIZE (because disk block is 1)
; Each block is written to disk after download
GETFILE:
        LD          A,'.'
        CALL    PUTCHAR
        LD      A,10
        LD      (buf),a                                     ; counter for cosmetic feature
        LD      BC,(buf + 1)                            ; Read the number of blocks to transfer     
DSKREADBLK:
        LD          A,(buf)
        OR          A
        JR          Z,DSKREADBLK1
        DEC     A
        LD          (buf),a
        CP          9
        JR          Z,DSKREADBLK2
        LD          A,'.'
        OUT     ($98),A
        JR          DSKREADBLK2
DSKREADBLK1:
        LD          A,'.'
        CALL    PUTCHAR
        LD      A,10
        LD      (buf),A        
 DSKREADBLK2:
         PUSH    BC
; Buffer where data is stored during transfer, and also DMA for disk access

        LD      DE,DMA                              ; Disk drive buffer for temporary data
        LD      BC,SECTORSIZE  ; block size to transfer
; READ ONE BLOCK OF DATA AND STORE IN THE DMA
        CALL    RECVDATA
        POP     BC
        RET     C
               
        PUSH    BC
        ; Set HL with the number of bytes received
        ; If its last sector, get the actual size that was sent by RPi in the ini_fcb 
        LD      HL,SECTORSIZE 
        LD      A,B
        CP      1
        JR      NC,DSKREADBLK3
        LD      A,C
        CP      1
        JR      NZ,DSKREADBLK3
        LD      HL,(buf + 3)            ; get actual block size
DSKREADBLK3:
        LD      DE,FILEFCB
        LD      C,$26
        CALL    BDOS
        POP     BC
        DEC     BC
        LD        A,B
        OR      C
        JR      NZ, DSKREADBLK       ; data read less than buffer - finished transfer
        OR      A
        RET

OPENFILEW:
        LD      DE,FILEFCB
        LD      C,$16
        CALL    BDOS
        OR      A
        RET     Z
; Error opening file
        SCF
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

command:    DB      "pcopy   ",0
msg_success: db "Checksum match",13,10,0
msg_error: db "Checksum did not match",13,10,0
msg_cmd: db "Sending command...",0
msg_parms: db "Sending parameters... ",0
msg_recv: db "Now reading MSXPi response... ",0
FNTITLE:    DB      "Saving file:",0
PICOMMERR:  DB      "Communication Error",13,10,0
PIUNKNERR:  DB      "Unknown error",13,10,0
PICRCERR:   DB      "CRC Error",13,10,0
DSKERR:     DB      "DISK IO ERROR",13,10,0
LOADPROGERRMSG: DB  "Error download file from network",13,10,10
FOPENERR:   DB      "Error opening file",13,10,0
PARMSERR:   DB      "Invalid parameters",13,10,0
USERESCAPE: DB      "Cancelled",13,10,0
RUNOPTION:  db  0
SAVEOPTION: db  0
REGINDEX:   dw  0
FILEFCB:    ds     40


INCLUDE "include.asm"
INCLUDE "putchar-clients.asm"
INCLUDE "msxpi_bios.asm"

buf:     equ     $
           DB       0,0,0,0,0,0
DMA:  ds      SECTORSIZE
           db      0

