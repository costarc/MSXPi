; MSXPi Interface
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
; msxarch.com Assembly port - Stage 1: menu, keyboard input and MSXARCH.INI
; parsing. No MSXPi network traffic yet - see PORT_STATUS.md for the plan.
; This stage is deliberately self-contained (no asm-common includes) so it
; builds and is testable in openMSX on its own, ahead of stage 2 wiring in
; the protocol layer from asm-common/include/msxpi_bios.asm.
;
; Ports (line-numbers refer to software/Client/src/msxarch.c on this branch):
;   GetValidInput          (C ~115-166)
;   showMenu                (C ~168-187)
;   StartsWith / IsArchiveError / ShowArchiveError (C ~193-223)
;   SetFcbFilename / LoadRepositoryList / iniSetting / iniYes (C ~225-320)
;   main()'s menu portion, up to (not including) SendCommandToMSXPi("msxarchive")
;
; Compile with z80asm:
;   z80asm stage1_menu.asm -o stage1_menu.com
;
        org     $0100

; ===========================================================================
; Constants
; ===========================================================================
BDOS:           EQU     5
F_OPEN:         EQU     $0F
F_CLOSE:        EQU     $10
F_READSEQ:      EQU     $14
F_DTAOFF:       EQU     $1A

; Main-ROM BIOS entries. Under MSX-DOS page 0 is RAM, so these can only be
; reached through CALSLT - a plain CALL lands in whatever DOS keeps there.
B_CHGMOD:       EQU     $005F   ; A = screen mode; re-reads LINL40 for mode 0
B_CLS:          EQU     $00C3
B_POSIT:        EQU     $00C6   ; H = X (col), L = Y (row)
B_CHPUT:        EQU     $00A2   ; A = char to print
B_CHGET:        EQU     $009F   ; blocking key read, no echo, returns A = key
CALSLT:         EQU     $001C   ; IY high = slot, IX = address
EXPTBL:         EQU     $FCC1   ; main-ROM slot
LINL40:         EQU     $F3AE   ; screen-0 width, read by CHGMOD/INITXT

INI_BUFFER_SIZE:EQU     1024
MAX_REPOS:      EQU     8
MAX_URL_LEN:    EQU     100
INPUTLEN:       EQU     4

KEY_UP:         EQU     $1E
KEY_DOWN:       EQU     $1F
KEY_ENTER:      EQU     $0D
KEY_BACKSPACE:  EQU     $08

INPUT_NONE:     EQU     0
INPUT_P:        EQU     1
INPUT_N:        EQU     2
INPUT_Q:        EQU     3
INPUT_UP:       EQU     4
INPUT_DOWN:     EQU     5
INPUT_NUMBER:   EQU     6

; ===========================================================================
; Entry point
; ===========================================================================
MAIN:
        call    InitScreen0Width80
        call    LoadRepositoryList
        ld      a,(REPO_COUNT)
        or      a
        jr      nz,MAIN_HAVE_REPOS

        ld      hl,DEFAULT_URL
        ld      de,Repo0
        ld      bc,DEFAULT_URL_LEN
        ldir
        ld      a,1
        ld      (REPO_COUNT),a

MAIN_HAVE_REPOS:
        call    BuildItems

MAIN_LOOP:
        call    ShowMenu                ; -> HL = selected item string

        push    hl
        ld      de,EXIT_STR
        call    StrCompareEq
        pop     hl
        jr      c,MAIN_EXIT

        push    hl
        ld      de,STR_Q
        call    StrCompareEq
        pop     hl
        jr      c,MAIN_EXIT

        push    hl
        ld      hl,MSG_SELECTED
        call    Print
        pop     hl
        call    Print
        ld      hl,MSG_CONNECTING
        call    Print

        ; Stage 1 stops here - stage 2 wires this into SendCommandToMSXPi.
        ld      hl,MSG_STAGE1_STUB
        call    Print
        call    WaitForKey
        call    Cls
        jr      MAIN_LOOP

MAIN_EXIT:
        ld      hl,MSG_EXIT_SELECTED
        call    Print
        ret

; ===========================================================================
; Screen / keyboard / print primitives
; ===========================================================================

; BIOS wrappers: AF/BC/DE/HL pass through CALSLT; IX/IY are destroyed.
CHPUT:  ld      ix,B_CHPUT
        jr      BiosCall
CHGET:  ld      ix,B_CHGET
        jr      BiosCall
CLS:    ld      ix,B_CLS
        jr      BiosCall
POSIT:  ld      ix,B_POSIT
        jr      BiosCall
CHGMOD: ld      ix,B_CHGMOD
BiosCall:
        ld      iy,(EXPTBL-1)           ; IYH = main-ROM slot
        jp      CALSLT

; SCREEN 0, WIDTH 80 (the "mode 80" trick: set LINL40 before CHGMOD 0).
InitScreen0Width80:
        ld      a,80
        ld      (LINL40),a
        xor     a
        call    CHGMOD
        ret

Cls:
        call    CLS
        ret

; Locate(col=D, row=E)
Locate:
        ld      h,d
        ld      l,e
        call    POSIT
        ret

PrintChar:
        call    CHPUT
        ret

; Print(HL = 0-terminated string). \n (0Ah) is expanded to CR+LF.
Print:
        ld      a,(hl)
        or      a
        ret     z
        cp      10
        jr      nz,PR_PLAIN
        push    hl
        ld      a,13
        call    PrintChar
        ld      a,10
        call    PrintChar
        pop     hl
        inc     hl
        jr      Print
PR_PLAIN:
        call    PrintChar
        inc     hl
        jr      Print

; PrintNumber(HL = 0-65535), decimal, no leading zeros.
PrintNumber:
        push    af
        push    bc
        push    de
        push    hl
        xor     a
        ld      (PN_STARTED),a
        ld      de,10000
        call    PN_DIGIT
        ld      de,1000
        call    PN_DIGIT
        ld      de,100
        call    PN_DIGIT
        ld      de,10
        call    PN_DIGIT
        ld      a,l
        add     a,'0'
        call    PrintChar
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; HL /= DE (DE a power of ten); prints the quotient digit unless it is a
; leading zero (PN_STARTED still clear). Leaves the remainder in HL.
PN_DIGIT:
        ld      b,0
PND_LOOP:
        or      a
        sbc     hl,de
        jr      c,PND_DONE
        inc     b
        jr      PND_LOOP
PND_DONE:
        add     hl,de
        ld      a,b
        or      a
        jr      nz,PND_PRINT
        ld      a,(PN_STARTED)
        or      a
        ret     z
PND_PRINT:
        ld      c,a
        ld      a,1
        ld      (PN_STARTED),a
        ld      a,c
        add     a,'0'
        call    PrintChar
        ret

; WaitForKey() -> A = key, blocking, no echo.
WaitForKey:
        call    CHGET
        ret

; InputChar() -> A = key, blocking, echoed.
InputChar:
        call    CHGET
        push    af
        call    PrintChar
        pop     af
        ret

; IsDigit(A) -> carry set if '0'..'9'.
IsDigit:
        cp      '0'
        jr      c,ISD_NO
        cp      '9'+1
        jr      nc,ISD_NO
        scf
        ret
ISD_NO:
        or      a
        ret

; LowerChar(A) -> A lowercased if 'A'..'Z'.
LowerChar:
        cp      'A'
        jr      c,LC_NO
        cp      'Z'+1
        jr      nc,LC_NO
        add     a,32
LC_NO:
        ret

; StrCompareEq(HL=s1, DE=s2) -> carry set if the two 0-terminated strings
; are equal. (Only equality is needed anywhere msxarch.c calls StrCompare.)
StrCompareEq:
        ld      a,(de)
        ld      c,a
        ld      a,(hl)
        cp      c
        jr      nz,SCE_NE
        or      a
        jr      z,SCE_EQ
        inc     hl
        inc     de
        jr      StrCompareEq
SCE_NE:
        or      a
        ret
SCE_EQ:
        scf
        ret

; ===========================================================================
; GetValidInput  (msxarch.c ~115-166)
; Returns: A = INPUT_* code. OUT_NUMBER holds the digits (0-terminated) when
; A = INPUT_NUMBER.
; ===========================================================================
GetValidInput:
        xor     a
        ld      (OUT_NUMBER),a

GVI_LOOP:
        call    WaitForKey
        push    af
        ld      d,0
        ld      e,0
        call    Locate
        pop     af

        cp      'P'
        jr      z,GVI_P
        cp      'p'
        jr      z,GVI_P
        cp      'N'
        jr      z,GVI_N
        cp      'n'
        jr      z,GVI_N
        cp      'Q'
        jr      z,GVI_Q
        cp      'q'
        jr      z,GVI_Q
        cp      KEY_UP
        jr      z,GVI_UP
        cp      KEY_DOWN
        jr      z,GVI_DOWN
        call    IsDigit
        jr      c,GVI_NUMBER
        jr      GVI_LOOP

GVI_P:
        ld      a,INPUT_P
        ret
GVI_N:
        ld      a,INPUT_N
        ret
GVI_Q:
        ld      a,INPUT_Q
        ret
GVI_UP:
        ld      a,INPUT_UP
        ret
GVI_DOWN:
        ld      a,INPUT_DOWN
        ret

; Only Enter ends the number; Backspace erases the last digit; anything
; else is ignored (matches the comment at msxarch.c:137-140).
GVI_NUMBER:
        ld      (GVI_CUR_KEY),a
        xor     a
        ld      (OUT_COUNT),a

GVI_NUM_LOOP:
        ld      a,(GVI_CUR_KEY)
        call    IsDigit
        jr      nc,GVI_NUM_TRY_BS
        ld      a,(GVI_CUR_KEY)
        ld      c,a
        ld      a,(OUT_COUNT)
        cp      3
        jr      nc,GVI_NUM_NEXT         ; already have 3 digits, drop it
        push    hl
        ld      hl,OUT_NUMBER
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (hl),c
        pop     hl
        ld      a,(OUT_COUNT)
        inc     a
        ld      (OUT_COUNT),a
        ld      a,c
        call    PrintChar
        jr      GVI_NUM_NEXT

GVI_NUM_TRY_BS:
        ld      a,(GVI_CUR_KEY)
        cp      KEY_BACKSPACE
        jr      nz,GVI_NUM_TRY_ENTER
        ld      a,(OUT_COUNT)
        or      a
        jr      z,GVI_NUM_NEXT
        dec     a
        ld      (OUT_COUNT),a
        ld      a,KEY_BACKSPACE
        call    PrintChar
        ld      a,' '
        call    PrintChar
        ld      a,KEY_BACKSPACE
        call    PrintChar
        jr      GVI_NUM_NEXT

GVI_NUM_TRY_ENTER:
        ld      a,(GVI_CUR_KEY)
        cp      KEY_ENTER
        jr      nz,GVI_NUM_NEXT
        ld      a,(OUT_COUNT)
        or      a
        jr      z,GVI_NUM_NEXT
        jr      GVI_NUM_DONE

GVI_NUM_NEXT:
        call    WaitForKey
        ld      (GVI_CUR_KEY),a
        jr      GVI_NUM_LOOP

GVI_NUM_DONE:
        ld      a,(OUT_COUNT)
        ld      hl,OUT_NUMBER
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (hl),0
        ld      a,INPUT_NUMBER
        ret

; ===========================================================================
; showMenu  (msxarch.c ~168-187)
; Caller sets MENU_TABLE (word, item pointer table) and MENU_COUNT (byte)
; first, e.g. via BuildItems. Returns HL = pointer to the selected string.
; ===========================================================================
ShowMenu:
        ld      hl,MSG_MENU_HDR
        call    Print
        ld      hl,MSG_MENU_TITLE
        call    Print

        xor     a
        ld      (SM_INDEX),a
SM_LOOP:
        ld      a,(SM_INDEX)
        ld      b,a
        ld      a,(MENU_COUNT)
        cp      b
        jr      z,SM_LOOP_DONE
        jr      c,SM_LOOP_DONE

        ld      a,(SM_INDEX)
        ld      l,a
        ld      h,0
        inc     hl
        call    PrintNumber
        ld      hl,MSG_DOT_SPACE
        call    Print

        ld      a,(SM_INDEX)
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,(MENU_TABLE)
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        call    Print
        ld      hl,MSG_NL
        call    Print

        ld      a,(SM_INDEX)
        inc     a
        ld      (SM_INDEX),a
        jr      SM_LOOP

SM_LOOP_DONE:
        call    InputChar
        sub     '0'
        ld      (SM_CHOICE_NUM),a

        or      a
        jp      m,SM_OUT_OF_RANGE
        cp      1
        jr      c,SM_OUT_OF_RANGE
        ld      b,a
        ld      a,(MENU_COUNT)
        cp      b
        jr      c,SM_OUT_OF_RANGE

        ld      a,(SM_CHOICE_NUM)
        dec     a
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,(MENU_TABLE)
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ret

SM_OUT_OF_RANGE:
        ld      hl,MSG_OUT_OF_RANGE
        call    Print
        ld      hl,STR_Q
        ret

; BuildItems: fill ITEMS_TABLE with pointers to Repo0..Repo(count-1) then
; "Exit"; sets MENU_TABLE/MENU_COUNT for ShowMenu.
BuildItems:
        ld      a,(REPO_COUNT)
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      b,h
        ld      c,l
        ld      hl,RepoEntryTable
        ld      de,ITEMS_TABLE
        ldir

        ld      a,(REPO_COUNT)
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,ITEMS_TABLE
        add     hl,de
        ld      de,EXIT_STR
        ld      (hl),e
        inc     hl
        ld      (hl),d

        ld      a,(REPO_COUNT)
        inc     a
        ld      (MENU_COUNT),a
        ld      hl,ITEMS_TABLE
        ld      (MENU_TABLE),hl
        ret

; ===========================================================================
; StartsWith / IsArchiveError / ShowArchiveError  (msxarch.c ~193-223)
; ===========================================================================

; StartsWith(HL=text, DE=prefix) -> carry set if text starts with prefix.
StartsWith:
        ld      a,(de)
        or      a
        jr      z,STW_YES
        ld      c,a
        ld      a,(hl)
        cp      c
        jr      nz,STW_NO
        inc     hl
        inc     de
        jr      StartsWith
STW_YES:
        scf
        ret
STW_NO:
        or      a
        ret

; IsArchiveError(HL=text) -> carry set if it is one of the two prefixes
; msxpi-server's reject() replies with.
IsArchiveError:
        push    hl
        ld      de,STR_PI_ERROR
        call    StartsWith
        pop     hl
        ret     c
        push    hl
        ld      de,STR_FAILED_LIST
        call    StartsWith
        pop     hl
        ret

; ShowArchiveError(HL=message)
ShowArchiveError:
        push    hl
        call    Cls
        ld      hl,MSG_ARCH_ERROR_HDR
        call    Print
        pop     hl

        push    hl
        ld      de,STR_PI_ERROR
        call    StartsWith
        pop     hl
        jr      nc,SAE_CHECK_FAILED
        push    hl
        ld      de,11
        add     hl,de
        call    Print
        pop     hl
        jr      SAE_FOOTER

SAE_CHECK_FAILED:
        push    hl
        ld      de,STR_FAILED_LIST
        call    StartsWith
        pop     hl
        jr      nc,SAE_GENERIC
        ld      hl,MSG_CANNOT_OPEN
        call    Print
        jr      SAE_FOOTER

SAE_GENERIC:
        call    Print

SAE_FOOTER:
        ld      hl,MSG_PRESS_KEY
        call    Print
        call    WaitForKey
        call    Cls
        ret

; ===========================================================================
; MSXARCH.INI loading  (msxarch.c ~225-320: SetFcbFilename, LoadRepositoryList,
; iniSetting, iniYes)
; ===========================================================================

; Zero the FCB, pad name/ext with spaces, then fill "MSXARCH"/"INI".
BuildIniFcb:
        ld      hl,iniFcb
        ld      (hl),0
        ld      de,iniFcb+1
        ld      bc,35
        ldir

        ld      hl,iniFcb+1
        ld      b,11
        ld      a,' '
BIF_SP:
        ld      (hl),a
        inc     hl
        djnz    BIF_SP

        ld      hl,INI_NAME_STR
        ld      de,iniFcb+1
        ld      bc,7
        ldir
        ld      hl,INI_EXT_STR
        ld      de,iniFcb+9
        ld      bc,3
        ldir
        ret

; Reads MSXARCH.INI (already open) into iniBuffer, 128-byte records via
; F_READSEQ, stopping at EOF or the first Ctrl-Z (26 / 1Ah) padding byte.
; Sets BYTES_READ.
ReadIniFile:
        ld      hl,0
        ld      (BYTES_READ),hl

RIF_LOOP:
        ld      hl,(BYTES_READ)
        ld      de,128
        add     hl,de
        ld      de,INI_BUFFER_SIZE-1
        or      a
        sbc     hl,de
        jr      nc,RIF_DONE             ; would overflow iniBuffer, stop

        ld      hl,(BYTES_READ)
        ld      de,iniBuffer
        add     hl,de
        ex      de,hl                   ; de = DTA address
        ld      c,F_DTAOFF
        call    BDOS

        ld      de,iniFcb
        ld      c,F_READSEQ
        call    BDOS
        or      a
        jr      z,RIF_GOT_RECORD
        cp      3
        jr      z,RIF_GOT_PARTIAL
        jr      RIF_DONE                ; EOF (A=1) or DTA overflow (A=2)

RIF_GOT_RECORD:
        call    RIF_SCAN_CTRLZ
        jr      c,RIF_DONE
        jr      RIF_LOOP

RIF_GOT_PARTIAL:
        call    RIF_SCAN_CTRLZ
        jr      RIF_DONE

RIF_DONE:
        ret

; Scans the 128-byte record just read (at iniBuffer+BYTES_READ) for a
; Ctrl-Z. If found, sets BYTES_READ to the offset of that byte and returns
; carry set (stop reading). Otherwise advances BYTES_READ by 128 and
; returns carry reset (keep reading).
RIF_SCAN_CTRLZ:
        ld      hl,(BYTES_READ)
        ld      de,iniBuffer
        add     hl,de
        ld      b,128
        ld      c,0
RSC_LOOP:
        ld      a,(hl)
        cp      $1A
        jr      z,RSC_FOUND
        inc     hl
        inc     c
        djnz    RSC_LOOP

        ld      hl,(BYTES_READ)
        ld      de,128
        add     hl,de
        ld      (BYTES_READ),hl
        or      a
        ret

RSC_FOUND:
        ld      a,(BYTES_READ)
        add     a,c
        ld      (BYTES_READ),a
        ld      a,(BYTES_READ+1)
        adc     a,0
        ld      (BYTES_READ+1),a
        scf
        ret

CloseIniFile:
        ld      de,iniFcb
        ld      c,F_CLOSE
        call    BDOS
        ret

; LoadRepositoryList() -> sets REPO_COUNT (and REBOOT_AFTER_ROM_LOAD from
; any "rebootAfterRomLoad=yes" line). REPO_COUNT is also returned in A.
LoadRepositoryList:
        call    BuildIniFcb
        ld      de,iniFcb
        ld      c,F_OPEN
        call    BDOS
        or      a
        jp      nz,LRL_ZERO

        call    ReadIniFile
        call    CloseIniFile

        xor     a
        ld      (REPO_COUNT),a
        ld      (INI_COL),a
        ld      hl,0
        ld      (INI_POS),hl

LRL_LOOP:
        ld      a,(REPO_COUNT)
        cp      MAX_REPOS
        jp      nc,LRL_DONE

        ld      hl,(INI_POS)
        ld      de,(BYTES_READ)
        or      a
        sbc     hl,de
        jr      z,LRL_GET_CHAR          ; pos == bytesRead: one last (synthetic \n) pass
        jr      c,LRL_GET_CHAR          ; pos < bytesRead
        jp      LRL_DONE                ; pos > bytesRead

LRL_GET_CHAR:
        ld      hl,(INI_POS)
        ld      de,(BYTES_READ)
        or      a
        sbc     hl,de
        jr      nz,LRL_REAL_CHAR
        ld      a,10                    ; synthetic trailing newline
        jr      LRL_GOT_CHAR
LRL_REAL_CHAR:
        ld      hl,(INI_POS)
        ld      de,iniBuffer
        add     hl,de
        ld      a,(hl)

LRL_GOT_CHAR:
        ld      b,a                     ; B = current char, kept across calls below
        cp      13
        jr      z,LRL_NEXT_POS
        ld      a,b
        cp      10
        jr      z,LRL_HANDLE_NEWLINE

        ld      a,(INI_COL)
        cp      MAX_URL_LEN-1
        jr      nc,LRL_NEXT_POS         ; entry full, drop the char

        call    LRL_CUR_ENTRY_ADDR
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (hl),b
        ld      a,(INI_COL)
        inc     a
        ld      (INI_COL),a
        jr      LRL_NEXT_POS

LRL_HANDLE_NEWLINE:
        call    LRL_CUR_ENTRY_ADDR
        ld      a,(INI_COL)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (hl),0

        call    LRL_CUR_ENTRY_ADDR
        ld      de,STR_REBOOT_SETTING
        call    IniSetting
        jr      nc,LRL_NOT_SETTING
        call    IniYes
        ld      (REBOOT_AFTER_ROM_LOAD),a
        jr      LRL_NEWLINE_RESET

LRL_NOT_SETTING:
        ld      a,(INI_COL)
        or      a
        jr      z,LRL_NEWLINE_RESET
        call    LRL_CUR_ENTRY_ADDR
        ld      a,(hl)
        cp      ';'
        jr      z,LRL_NEWLINE_RESET
        cp      '#'
        jr      z,LRL_NEWLINE_RESET
        ld      a,(REPO_COUNT)
        inc     a
        ld      (REPO_COUNT),a

LRL_NEWLINE_RESET:
        xor     a
        ld      (INI_COL),a

LRL_NEXT_POS:
        ld      hl,(INI_POS)
        inc     hl
        ld      (INI_POS),hl
        jp      LRL_LOOP

LRL_DONE:
        ld      a,(REPO_COUNT)
        ld      l,a
        ld      h,0
        ret

LRL_ZERO:
        xor     a
        ld      (REPO_COUNT),a
        ld      hl,0
        ret

; HL = repoList[REPO_COUNT] (i.e. RepoEntryTable[REPO_COUNT]).
LRL_CUR_ENTRY_ADDR:
        push    af
        ld      a,(REPO_COUNT)
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,RepoEntryTable
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        pop     af
        ret

; IniSetting(HL=line, DE=lower-case name incl. trailing 0) -> carry set and
; HL = value start if the line is "name=value" (case-insensitive name,
; spaces allowed around '='), else carry reset.
IniSetting:
        push    hl
        push    de
IS_LOOP:
        ld      a,(de)
        or      a
        jr      z,IS_NAME_DONE
        ld      c,a
        ld      a,(hl)
        call    LowerChar
        cp      c
        jr      nz,IS_FAIL
        inc     hl
        inc     de
        jr      IS_LOOP
IS_NAME_DONE:
IS_SKIP1:
        ld      a,(hl)
        cp      ' '
        jr      nz,IS_CHECK_EQ
        inc     hl
        jr      IS_SKIP1
IS_CHECK_EQ:
        ld      a,(hl)
        cp      '='
        jr      nz,IS_FAIL
        inc     hl
IS_SKIP2:
        ld      a,(hl)
        cp      ' '
        jr      nz,IS_SUCCESS
        inc     hl
        jr      IS_SKIP2
IS_SUCCESS:
        pop     af
        pop     af
        scf
        ret
IS_FAIL:
        pop     de
        pop     hl
        or      a
        ret

; IniYes(HL=value) -> A=1 if "yes" (case-insensitive) followed by NUL/space/
; tab, else A=0.
IniYes:
        ld      a,(hl)
        call    LowerChar
        cp      'y'
        jr      nz,IY_NO
        inc     hl
        ld      a,(hl)
        call    LowerChar
        cp      'e'
        jr      nz,IY_NO
        inc     hl
        ld      a,(hl)
        call    LowerChar
        cp      's'
        jr      nz,IY_NO
        inc     hl
        ld      a,(hl)
        or      a
        jr      z,IY_YES
        cp      ' '
        jr      z,IY_YES
        cp      9
        jr      z,IY_YES
        jr      IY_NO
IY_YES:
        ld      a,1
        ret
IY_NO:
        xor     a
        ret

; ===========================================================================
; Strings
; ===========================================================================
INI_NAME_STR:           db      "MSXARCH"
INI_EXT_STR:             db      "INI"
STR_REBOOT_SETTING:      db      "rebootafterromload",0
STR_PI_ERROR:            db      "Pi:Error - ",0
STR_FAILED_LIST:         db      "Failed to list directory:",0
STR_Q:                   db      "Q",0
EXIT_STR:                db      "Exit",0

MSG_MENU_HDR:            db      "=== MENU ===",10,0
MSG_MENU_TITLE:          db      "!! msxarch loader !!",10,10,0
MSG_DOT_SPACE:           db      ". ",0
MSG_NL:                  db      10,0
MSG_OUT_OF_RANGE:        db      "Choice out of range.",10,0
MSG_SELECTED:            db      "You selected: ",0
MSG_CONNECTING:          db      10,"Connecting...",10,0
MSG_STAGE1_STUB:         db      "(stage 1 preview - networking arrives in stage 2)",10,"Press any key to return to the menu.",10,0
MSG_EXIT_SELECTED:       db      "Exit selected.",10,0

MSG_ARCH_ERROR_HDR:      db      "MSX Archive error",10,"=================",10,10,0
MSG_CANNOT_OPEN:         db      "Cannot open archive directory.",10,"File or directory does not exist.",0
MSG_PRESS_KEY:           db      10,10,"Press any key to return to the URL list.",0

DEFAULT_URL:
        db      "https://web.archive.org/web/20241204120811/https://www.msxarchive.nl/pub/msx/games/roms/msx1",0
DEFAULT_URL_LEN:        EQU     $-DEFAULT_URL

; ===========================================================================
; Variables
; ===========================================================================
REPO_COUNT:              db      0
REBOOT_AFTER_ROM_LOAD:   db      0
INI_COL:                  db      0
INI_POS:                  dw      0
BYTES_READ:                dw      0

SM_INDEX:                  db      0
SM_CHOICE_NUM:              db      0
MENU_TABLE:                  dw      0
MENU_COUNT:                   db      0

OUT_NUMBER:                    ds      INPUTLEN
OUT_COUNT:                      db      0
GVI_CUR_KEY:                     db      0
PN_STARTED:                       db      0

iniFcb:                              ds      36
iniBuffer:                             ds      INI_BUFFER_SIZE

Repo0:                                   ds      MAX_URL_LEN
Repo1:                                     ds      MAX_URL_LEN
Repo2:                                       ds      MAX_URL_LEN
Repo3:                                         ds      MAX_URL_LEN
Repo4:                                           ds      MAX_URL_LEN
Repo5:                                             ds      MAX_URL_LEN
Repo6:                                               ds      MAX_URL_LEN
Repo7:                                                 ds      MAX_URL_LEN

RepoEntryTable:
        dw      Repo0,Repo1,Repo2,Repo3,Repo4,Repo5,Repo6,Repo7

ITEMS_TABLE:
        ds      2*(MAX_REPOS+1)
