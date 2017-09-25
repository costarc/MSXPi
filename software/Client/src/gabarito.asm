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
; 0.1    : Initial version.
; gabarito.asm
; A tempalte for MSXPi development

; Here it is the generic communication flow between MSX and Pi.
; It may change depending on the command being implemented,
; therefore, the flow is designed to represent the functions
; implemented in this sample command.
;
; MSX                           RPi
;   1|--------  command -------->|
;   2|)Wait                      |)Parse Command
;   3|<----------- rc -----------|
;   4|)Parse rc                  |)Wait
;   5|--------- sendnext ------->|
;   6|<--------- rc_wait --------|
;   7|wait forever               |)Process requested data
;   8|<----------- rc -----------|
;   9|)Parse rc                  |)Wait
;  10|-------- sendnext -------->|
;  11|<--------- data -----------|
;  12|terminate                  |terminate
;
; Important points to consider in the above sequence:
; Line 1: command can be any text, any size. Do not exagerate.
; Line 2: Wait state has a short live. It can timeout and induce MSX into error, if it is too long (couple of seconds for example)
; Line 3: rc is a single byte return code (rc). Check file include.asm
; Line 4: Parse on the MSX Side means that, if rc is error code, MSX might have to stop the command. The rc code should tell what to do, for example, it may mean that MSX should ask Pi for a error message, or it may tell MSX to not try to communicate again with Pi, because it has stopped the communication in its side. If you insist and try, Pi won't be prepared to respond, and may result in MSX hanging
; Line 5:If rc was a success return code, then MSX can request (sendnext) next stream of data  as required by the command being implemented.
; Line 6:RPi may need to tell MSX that it will need an extended, undertermined time to process the command and have data ready, In this situation, it should send a "rc_wait" command do MSX.
; Line 7:MSX should loop waiting for a new rc from RPi. In meanwhile, RPi should be preparing the data to send to MSX. It can take as long as necessary, since it has sent rc_wait to MSX
; Line 8:After completing processing the data to send to MSX, RPi should send another rc to MSX: "rc_success" or "rc_failed"
; Line 9: rc is a single byte return code (rc). Check file include.asm
; Line 10:In case the rc allow further communication with RPi, then MSX send a request for the data (sendnext).
; Line 11:MSX enters a loop to receive the data. Usually, this loop should have a termination agreement between MSX and RPi, such as, that both parts terminate teh communication and stays in sync. Pi should finish its function at this point, and return to the "listed for new command" mode. MSX should return to command prompt.


TEXTTERMINATOR: EQU '$'
DSKNUMREGISTERS:   EQU 8192
DSKBLOCKSIZE:   EQU 1

        ORG     $0100

; -------------------------------------------------------------
; This block of code will send your command to Raspberry Pi
; You should not need to change anything here.
; The actual command is defined in "MYCOMMAND:  DB"
; at the end of this template.
; -------------------------------------------------------------
        LD      DE,MYCOMMAND
        LD      BC,MYCOMMANDEND - MYCOMMAND
        CALL    DOSSENDPICMD

; Note that if there is a communication error,
; the command is interruped right away.
; Communication error means: MSX could not talk to Pi, or
; in other words, the command never reached Pi.

        JR      C,PRINTPIERR

A
; SYNC TO RECEIVE FILENAME
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_FAILED
        JR      Z,EXITSTDOUT
        CP      SENDNEXT
        JR      NZ,PRINTPIERR

        CALL    INIFCB

; READ FILENAME
        CALL    READPARMS
        JR      C,PRINTPIERR

; Sync to wait Pi download the file
; Since a network transfer my get delayed, this routine
; will loop waiting RC_SUCCESS until Pi responds
; Loop can be interrupted by ESC

        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_WAIT
        SCF
        RET     NZ
WAITLOOP:
        CALL    CHECK_ESC
        JR      C,PRINTPIERR
        CALL    CHKPIRDY
        JR      C,WAITLOOP
; Loop waiting download on Pi
        LD      A,SENDNEXT
        CALL    PIEXCHANGEBYTE
        CP      RC_FAILED
        JR      Z,EXITSTDOUT
        CP      RC_SUCCESS
        JR      NZ,WAITLOOP

        CALL    PRINTFNAME

        CALL    OPENFILEW

        CALL    SETFILEFCB

        CALL    GETFILE
        JR      C,PRINTPIERR

        CALL    PRINTNLINE
        CALL    PRINTPISTDOUT

        CALL    CLOSEFILE

        JP      0

EXITSTDOUT:
        CALL    PRINTNLINE
        CALL    PRINTPISTDOUT
        jp      0

PRINTPIERR:
        LD      HL,PICOMMERR
        CALL    PRINT
        JP      0

FILEERR:
        LD      A,RC_FAILED
        CALL    PIEXCHANGEBYTE
        LD      HL,PRINTPIERR
        CALL    PRINT
        JP      0

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
; it will use blocks size DSKNUMREGISTERS (because disk block is 1)
; Each block is written to disk after download
GETFILE:
DSKREADBLK:

; SEND COMMAND TO TRANSFER NEXT BLOCK
        LD      BC,5
        LD      DE,PCOPYCMD
        CALL    DOSSENDPICMD
        JR      C,PRINTPIERR

; BLOCK SIZE TO USE
        LD      BC,DSKNUMREGISTERS

; Buffer where data is stored during transfer, and also DMA for disk access
        LD      DE,DMA

; READ ONE BLOCK OF DATA AND STORE IN THE DMA

; A = 1 Tells the download routine to show dots or every 256 bytes transfered
; The routine rturns C set is there was a communication error
        LD      A,1
        CALL    DOWNLOADDATA
        RET     C

; The routine return A = status code,
; ENDTRANSFER means the transfer ended.
; Note that the last block of data was transferd in the previous call,
; which means tht in this call (the last call) there will never be data to save.
        CP      ENDTRANSFER
        RET     Z

; The routine returned SUCCESS, this means the block of data was transferred,
; Also means there may be more data, and another call is needed (fater saving this block)
; If the STATUS code is something else, set flag C and terminate the routine with error
        CP      RC_SUCCESS
        SCF
        RET     NZ

; Set HL with the number of bytes transfered.
; This is needed because the last block may be smaller than DSKNUMREGISTERS,
; And this math below will make sure only the actual number of bytes are written to disk.
; When the DOWNLOADDATA routine ends, DE contain the DMA + number of bytes transfered
; Also, clearing Carry with "OR A" "is required or the math may be incorrect.
        LD      HL,DMA
        EX      DE,HL
        OR      A
        SBC     HL,DE
        CALL    DSKWRITEBLK
        JR      DSKREADBLK

READPARMS:
VERDRIVE:
; READ FILENAME
        LD      DE,DMA
        CALL    RECVDATABLOCK
        PUSH    AF
        XOR     A
        LD      (DE),A
        POP     AF
        RET     C
        LD      HL,DMA+1
        LD      A,(HL)
        DEC     HL
        CP      ":"
        JR      Z,GETDRIVEID
        XOR     A

; This function will fill the FCB with a valid filename
; Longer filenames are truncated yo 8.3 format.

GET_NAME:
READPARMS0:
        LD      DE,FILEFCB
        LD      (DE),A
        INC     DE
        LD      B,8
READPARMS1:
        LD      A,(HL)
        CP      "."
        JR      Z,FILLNAME
        CP      0
        JR      Z,FILLNAMEEXT
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    READPARMS1

GET_EXT:
        LD      B,3
        LD      A,(HL)
        INC     HL
        CP      0
        JR      Z,FILLEXT
        CP      "."
        JR      Z,READPARMS1B
        DEC     HL
READPARMS1B:
        LD      A,(HL)
        CP      0
        JR      Z,FILLEXT
        LD      (DE),A
        INC     HL
        INC     DE
        DJNZ    READPARMS1B
        RET

FILLNAMEEXT:
        INC     B
        INC     B
        INC     B
        JR      FILLEXT

FILLNAME:
        LD      A,$20
FILLNAME0:
        LD      (DE),A
        INC     DE
        DJNZ    FILLNAME0
        JR      GET_EXT

FILLEXT:
        LD      A,$20
FILLEXT0:
        LD      (DE),A
        INC     DE
        DJNZ    FILLEXT0
        RET

GETDRIVEID:
READPARMS3:
        LD      A,(HL)
        LD      B,'A'
        CP      'a'
        JR      C,READPARMS4
        LD      B,'a'
READPARMS4:
        SUB     B
        ADD     1
        INC     HL
        INC     HL
        JR      GET_NAME

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

; -------------------------------------------------------------
; CHECK_ESC
; -------------------------------------------------------------
; This routine is required by the communication
; protocol to allow user to ESCAPE from a blocked state
; when Pi stops responding MSX for some reason.
; Note that this routine must be called by you in your code.
; -------------------------------------------------------------
CHECK_ESC:
	ld	b,7
	in	a,(0AAh)
	and	11110000b
	or	b
	out	(0AAh),a
	in	a,(0A9h)	
	bit	2,a
	jr	nz,CHECK_ESC_END
	scf
CHECK_ESC_END:
	ret

MYCOMMAND:  DB      "GABARITO"
PICOMMERR:  DB      "Communication Error",13,10,"$"
PARMSERR:   DB      "Invalid parameters",13,10,"$"


INCLUDE "debug.asm"

INCLUDE "include.asm"
INCLUDE "msxpi_bios.asm"
INCLUDE "msxpi_io.asm"
INCLUDE "msxdos_stdio.asm"

; Your buffers and other temporary volatile temporary date should go here.
DMA:     EQU    $
