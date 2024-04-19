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

DSKBLOCKSIZE:   EQU 1

        org     $0100
        call    TESTRAM
        ld      hl,$4000
        ld      (currptx),hl
; Sending Command and Parameters to RPi
        ld      de,command
        call    SENDCOMMAND
        jr      c, PRINTPIERR
        ld      de,buf
        ld      bc,BLKSIZE
        call    CLEARBUF
        call    SENDPARMS
        jr      c, PRINTPIERR
        ld      de,buf
MAINPROG:
        ld      bc,BLKSIZE
        call    CLEARBUF
        push    de
        call    RECVDATA
        pop     hl
        jr      c, PRINTPIERR
        ld      a,(hl)          ; return code
        inc     hl
        ld      c,(hl)          ; lsb of data size
        inc     hl
        ld      b,(hl)          ; msb of data size
        inc     hl
        ld      d,h
        ld      e,l
        cp      RC_FAILED
        jp      z,PRINTPISTDOUT            ; if RPi sent Error, print message to screen
        cp      RC_TERMINATE
        jp      z,PRINTPISTDOUT

; UpdateFCB with the data received from RPi
        LD      DE,FILEFCB
        LD      BC,12
        LDIR
        CALL    PRINTFNAME
        CALL    GETFILE
        JR      C,PRINTPIERR
        LD      HL,0
        LD      A,($FCC1)
        CALL    ENASLT
        LD      HL,($4002)    ;ROM exec address
        JP      (HL)
        
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
        LD      A,' '
        CALL    PUTCHAR
        LD      A,10
        LD      (buf),a             ; counter for cosmetic   feature
        LD      BC,(buf + 1)        ; Read the number of bytes to transfer
DSKREADBLK:
        LD      A,(buf)
        OR      A
        JR      Z,DSKREADBLK1
        DEC     A
        LD      (buf),a
        CP      9
        JR      Z,DSKREADBLK2
        LD      A,'.'
        OUT     ($98),A
        JR      DSKREADBLK2
DSKREADBLK1:
        LD      A,'.'
        CALL    PUTCHAR
        LD      A,10
        LD      (buf),A
 DSKREADBLK2:
        LD      DE,DMA              ; Disk drive buffer for temporary data
        LD      BC,SECTORSIZE       ; block size to transfer
        CALL    RECVDATA
        RET     C
        LD      A,(DMA)
        CP      RC_READY
        JR      NZ,LASTBLOCK
        LD      BC,SECTORSIZE - 3   ; actual data size (minus header)
        CALL    WRITEROM
        JR      DSKREADBLK          ; data read less than buffer - finished transfer
LASTBLOCK:
        LD      A,(DMA + 1)
        LD      C,A
        LD      A,(DMA + 2)
        LD      B,A
        CALL    WRITEROM
        OR      A
        RET
        
; Move each block to its dinal position
; Needed because each block comes with a 3 bytes header - need to strip it
; Return C reseted, and A = filetype
; Input:
; BC = BLOCKSIZE
; (currptx) = Next address to store the data
WRITEROM:
        LD      HL,(currptx)
        LD      D,H
        LD      E,L
        LD      HL,DMA + 3
        LDIR
        LD      A,E
        LD      (currptx),A
        LD      A,D
        LD      (currptx + 1),A
        RET

TESTRAM:
        LD      A,1
        LD      ($4000),A
        LD      A,($4000)
        CP      1
        JR      NZ,NOTRAMPG1
        LD      A,255
        LD      ($4000),A
        LD      A,($4000)
        CP      255
        JR      NZ,NOTRAMPG1
        LD      A,1
        LD      ($9000),A
        LD      A,($9000)
        CP      1
        JR      NZ,NOTRAMPG2
        LD      A,255
        LD      ($9000),A
        LD      A,($9000)
        CP      255
        JR      NZ,NOTRAMPG2
        LD      HL,ISRAMMSG
        JP      PRINT
NOTRAMPG1:
        LD      HL,NOTRAMMSG1
        JP      PRINT
NOTRAMPG2:
        LD      HL,NOTRAMMS2
        JP      PRINT


ISRAMMSG: DB "RAM OK in pages 1 & 2",13,10,0
NOTRAMMSG1: DB "CANNOT WRITE TO PAGE 1",0
NOTRAMMS2: DB "CANNOT WRITE TO PAGE 2",0

command:    DB      "ploadr",0
msg_success: db "Checksum match",13,10,0
msg_error: db "Checksum did not match",13,10,0
msg_cmd: db "Sending command...",0
msg_parms: db "Sending parameters... ",0
msg_recv: db "Now reading MSXPi response... ",0
FNTITLE:    DB      13,10,"Loading rom:",0
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

INCLUDE "include.asm"
INCLUDE "putchar-clients.asm"
INCLUDE "msxpi_bios.asm"

currptx: DB     0,0
FILEFCB:    ds  40
        db      0,0,0,0,0,0,0,0,0,0
buf:    ds      BLKSIZE + 3
DMA:    equ     $
