; MSXPi Interface
; Version 1.6

; ------------------------------------------------------------------------------
; The BASIC "CALL MSXPI" handler: statement dispatch, parameter parsing, and the
; three output modes.  Shared, because two things answer CALL MSXPI and they
; have to behave identically:
;
;   ROM/src/MSX-DOS/msxpi-driver.mac   the MSX-DOS driver ROM    (zmac)
;   ROM/src/BIOS/msxpiext.asm          the BASIC-only extension  (sjasmplus)
;
; They were separate copies until v1.6, by which time the extension's had
; drifted so far it no longer assembled: it still called SENDPICMD, RECVDATA,
; PARMSEVAL and PIEXCHANGEBYTE, none of which have existed since the block
; protocol landed.  Two copies of a 400-line parser is how that happens.
;
; Written in the subset both assemblers accept - the same discipline
; msxpi_bios.asm already follows, since both builds include that as well.
;
; The host file supplies, after this include:
;   MSXPIVERSION   the banner _MSXPIVER prints (and its BuildId, which the
;                  build script rewrites in the host file by name)
;   CALL_TABLE     the commands it exposes, ending with ENDOFCMDS/DB 0
; and, through msxpi_bios.asm: PRINT, PRINTPISTDOUT, SendCommandToMSXPi,
; PerformHandshake, RECVDATA_ONEBLOCK.
; ------------------------------------------------------------------------------

CALLHAND:
 
    PUSH    HL
    LD      HL,CALL_TABLE     ; Table with "_" instructions
.CHKCMD:
    LD      DE,PROCNM
.LOOP       LD  A,(DE)
    CP      (HL)
    JR      NZ,.TONEXTCMD   ; Not equal
    INC     DE
    INC     HL
    AND     A
    JR      NZ,.LOOP        ; No end of instruction name, go checking
    LD      E,(HL)
    INC     HL
    LD      D,(HL)          
    POP     HL              ; routine address
    CALL    GETPREVCHAR
    CALL    .CALLDE         ; Call routine
    AND     A
    RET
 
.TONEXTCMD:
    LD      C,0FFH
    XOR     A
    CPIR            ; Skip to end of instruction name
    INC     HL
    INC     HL      ; Skip address
    CP      (HL)
    JR      NZ,.CHKCMD  ; Not end of table, go checking
    POP     HL
    SCF
    RET
 
.CALLDE:
    PUSH    DE
    RET

; ---------------------
; Supporting functions|
;----------------------
GETSTRPNT:
; OUT:
; HL = String Address
; B  = Length
 
        LD      HL,($F7F8)
        LD      B,(HL)
        INC     HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        RET
 
EVALTXTPARAM:
        CALL    CHKCHAR
        DEFB    "("             ; Check for (
        LD      IX,FRMEVL
        CALL    CALBAS      ; Evaluate expression
        LD      A,(VALTYP)
        CP      3               ; Text type?
        JP      NZ,TYPE_MISMATCH
        PUSH    HL
        LD      IX,FRESTR         ; Free the temporary string
        CALL    CALBAS
        POP HL
        CALL    CHKCHAR
        DEFB    ")"             ; Check for )
        RET
 
 
CHKCHAR:
        CALL    GETPREVCHAR ; Get previous basic char
        EX      (SP),HL
        CP      (HL)            ; Check if good char
        JR      NZ,SYNTAX_ERROR ; No, Syntax error
        INC     HL
        EX      (SP),HL
        INC     HL      ; Get next basic char
 
GETPREVCHAR:
        DEC     HL
        LD      IX,CHRGTR
        JP      CALBAS
 
 
TYPE_MISMATCH:
        LD      E,13
        DB      1
 
SYNTAX_ERROR:
        LD      E,2
        LD      IX,ERRHAND  ; Call the Basic error handler
        JP      CALBAS
 
;================================================================
; call Commands start here
; ================================================================
;-----------------------
; call HELP OR MSXPIHELP
;-----------------------
;-----------------------
; call MSXPIVER 
;-----------------------
_MSXPIVER:
        push    hl
        ld      hl,MSXPIVERSION
        call    PRINT
        ld      de,vercommand
        call    SendCommandToMSXPi
        ld		bc,128
		ld		HL,(HIMEM)
        or      a
        sbc     hl,bc
        ld      d,h
        ld      e,l
		call    PRINTPISTDOUT
        pop     hl
        ret
vercommand:
        db      'ver',0
;--------------------------------------------------------------------
; Call MSXPI BIOS function                                          |
;--------------------------------------------------------------------
; Verify if command has STD parameters specified
; Examples:
; call mspxi("0,xxxx,pdir")  -> ignores the response
; call msxpi("1,xxxx,pdir")  -> print the respinse to screen
; call msxpi("2,E000,pdir")  -> store response data in memmory address passed
_MSXPI:
        CALL    EVALTXTPARAM    ; Evaluate text parameter
        PUSH    HL              ; Save for BASIC
        CALL    GETSTRPNT       ; Get the address of the paramaters
        EX      DE,HL           ; Switch to DE as required by next routines
        CALL    PARSE_CALL_PARAMETERS
                                ; Validate and get all paremeters in the call command
        JP      C,CALL_SYNTAX_ERROR ; Return to BASIC with ERROR
; Registers at this point:
; A  = contain the output required for the command
; DE = contain string address of command to send to RPi
; HL = contain buffer address to store data from RPi (if provided by user, otherwise 0)
;
; Routine explanation:
; MSX Send the command to RPi
; RPi reply with data block (BLKSIZE) with the following structure:
; | RC | LSB | MSB | INDEX | DATA |
; RC = RC_FAILED: Pi error. Message available to print
; RC = RC_READY: Pi processing succeed - data available and there is another block
; RC = RC_SUCCESS : Pi processing succeed - data available and this is last block
; RC = RC_CONNERR : Error in the connection with RPi
;
; Send commands (in CALL parameters) to RPi

        PUSH    HL
        PUSH    AF
        PUSH    DE
        POP     HL
        CALL    SendCommandToMSXPi
        JR      NC,CALL_SUCCESS
        POP     AF
        POP     HL
        LD      A,RC_CONNERR
        LD      (HL),A              ; [0] = error code, for callers checking
        INC     HL                  ; PEEK(B) without also checking carry
        XOR     A
        LD      (HL),A              ; [1] = size low = 0, so a caller that
        INC     HL                  ; skips the carry check too (like a
        LD      (HL),A              ; bare PEEK(B+1)+256*PEEK(B+2)) gets a
                                    ; safe empty-size loop instead of
                                    ; whatever command text ExtractCommand
                                    ; left sitting in the buffer
        POP     HL                  ; BASIC Pointer
        AND     A
        RET
CALL_SUCCESS:
        pop     af
        pop     de
        cp      '0'
        jr      z,CALL_DiscardResponse
        CP      '2'
        JR      Z,CALL_MSXPISAVEDATA

; ---------------------------------
; Print response to screen
; ---------------------------------
        ld      bc,MAXBUFSIZE
        xor     a               ; block = 0
        call	PRINTPISTDOUT
        pop     hl              ; BASIC pointer
        and     a
        ret
; ---------------------------------
; Consume response discarding it
; ---------------------------------
CALL_DiscardResponse:
        ld      bc,MAXBUFSIZE
        xor     a               ; block = 0
        call	STDOUTTONULL
        pop     hl              ; BASIC pointer
        and     a
        ret

; ============================================================
; CALL_MSXPISAVEDATA
; Receive data blocks into buffer at DE.
; First 3 bytes reserved for header:
;   [0] = final return code
;   [1..2] = total size (low/high)
; ============================================================

CALL_MSXPISAVEDATA:
        PUSH    DE              ; save base buffer address
        INC     DE              ; skip header space
        INC     DE
        INC     DE
        LD      BC,MAXBUFSIZE   ; request max block size
        call    PerformHandshake    ; Required before calling RECVDATA_ONEBLOCK
        XOR     A               ; block index = 0
        LD      HL,0            ; clear total size accumulator
RECV_LOOP:
        PUSH    AF
        PUSH    HL              ; keep total size on stack
        CALL    RECVDATA_ONEBLOCK
        JR      NC,RECV_OK
        POP     HL              ; discard total size - match RECV_ERROR's
                                ; expected stack depth (BlockIdx,BufAddr,BasicPtr)
        JR      RECV_ERROR      ; carry set = error, stop
RECV_OK:
        ; HL not used here, DE updated by RECVDATA_ONEBLOCK
        ; BC = size of block just read
        POP     HL              ; HL = current total size
        ADD     HL,BC           ; add block size
        ; check return code in A - matches PRINTPISTDOUT's own check
        ; (cp RC_READY / ret nz): RC_READY means another block follows,
        ; anything else means this was the last block. RECVDATA_ONEBLOCK
        ; already caught real transport failures via carry, so the RC
        ; value itself doesn't need to match a specific terminal code.
        CP      RC_READY
        JR      Z,RECV_NEXT     ; another block, continue
        JR      RECV_DONE       ; transfer complete

RECV_NEXT:
        POP     AF
        INC     A               ; next block index
        JR      RECV_LOOP

; ------------------------------------------------------------
; Successful completion: write header
; ------------------------------------------------------------
RECV_DONE:
        POP     BC              ; Discard index
                                ; HL = total size
        POP     DE              ; DE = base buffer address

        LD      (DE),A          ; [0] = RC_SUCCESS
        INC     DE
        LD      A,L
        LD      (DE),A          ; [1] = total size low
        INC     DE
        LD      A,H
        LD      (DE),A          ; [2] = total size high

        POP     HL              ; BASIC pointer

        AND     A
        ret

; ------------------------------------------------------------
; Error exit
; ------------------------------------------------------------
RECV_ERROR:
        LD      C,A             ; preserve error/status code - about to be
                                ; clobbered by the POP AF below
        POP     AF              ; discard block index
        POP     DE              ; restore buffer base
        LD      A,C
        LD      (DE),A          ; [0] = error code, so a caller reading the
        INC     DE              ; header after a failed transfer sees a
        XOR     A               ; real error instead of whatever was left in
        LD      (DE),A          ; the buffer (this call's own command text,
        INC     DE              ; copied in by ExtractCommand, or a previous
        LD      (DE),A          ; call's real data at the same address)
        POP     HL              ; restore BASIC pointer, matching RECV_DONE
        SCF                     ; set carry = error
        RET

CALL_SYNTAX_ERROR:
        ; The help text used to be printed here.  Dropped to reclaim ROM
        ; space: BASIC's own "Syntax error" already says the call was wrong,
        ; and the same information is available from P VER, the boot splash
        ; and CALL MSXPI("1,C000,ver").
        POP     HL
        LD      E,2
        LD      IX,ERRHAND  ; Call the Basic error handler
        JP      CALBAS

; Evaluate CALL Commands to check for optional parameters
; Returns Buffer address in HL (or HL=0000 if parameter not found)
; Input:
;  DE = Call full command (after the ")
; Output:
;  A = Output type (as below cases)
;  DE = Point to start of command to send to RPi (pdir in the case below)
;  HL = Address of buffer to store data if stdout = 2
;
; Cases:
; call MSXPI("0,C000,pdir")  -> ignores the response
; call MSXPI("1,C000,pdir")  -> print the response to screen
; call MSXPI("2,C000,pdir")  -> store response data in given memory address+3
; 
PARSE_CALL_PARAMETERS:
        LD      A,(DE)
        ; First parameters must be 0,1 or 2 - otherwise return error.
        CP      '0' 
        RET     C
        CP      '3'
        JR      C,STDOUT_OK
        SCF                 ; STDOUT > 2 -> error
        RET
STDOUT_OK:
        LD      H,A
        INC     DE
        DEC     B
        SCF
        RET     Z
        LD      A,(DE)
        CP      ','         ;Check for comma after stdout parameter
        SCF
        RET     NZ          ; Syntax error - missing comma
        INC     DE          ; Point to Address provided in call command
        DEC     B
        SCF
        RET     Z
; Convert ascii chars pointed by DE to hex. Return value in BC
; Flag C is set if there was an error
        PUSH    BC          ; Save B = number of characters remaing in command
        CALL    STRTOHEX    ; Return with DE pointing to next char in string
                            ; BC = Address converted from String
                            ; Flag C: set if error
        POP     IY          ; Temporaryly save B in IY
        RET     C           ; Conversion error - Exit
        PUSH    BC
        POP     IX          ; IX = = Address converted from String
        PUSH    IY
        POP     BC          ; B = number of characters remaing in command
        DEC     B
        DEC     B
        DEC     B
        DEC     B
        DEC     B
        SCF
        RET     Z           ; Syntax error
        PUSH    HL          ; Save parameters
        PUSH    IX
        POP     HL          ; User buffer in HL - Will be used in ExtractCommand
        CALL    ExtractCommand  ; Copy the command from DE to HL
                                ; Return new buffer address in DE
                                ; Add zero to end of command
                                ; Return address in DE
        POP     HL          ; Restore parameters
        LD      A,H         ; A = stdout value
        PUSH    IX
        POP     HL          ; HL = Buffer address passed in call command
                            ; DE = Addres of command terminated in zero
        AND     A
        RET

; Extract command from CALL
; DE = Address of string passed in CALL (after "0,xxxx,")
ExtractCommand:
        PUSH    HL
EC_Loop:
        LD      A,(DE)
        CP      '"'         ; End of parameters
        JR      Z,EC_Success
        LD      (HL),A
        INC     HL
        INC     DE
        DEC     B
        JR      NZ,EC_Loop
EC_Success:
        LD      (HL),0      ; Termination for the command
        POP     HL          ; Restore base address of command
        LD      D,H
        LD      E,L
        AND     A           ; Success
        RET
EC_ExitError:
        LD      (HL),0      ; Termination for the command
        POP     HL
        LD      D,H
        LD      E,L
        SCF                 ; Error
        RET
