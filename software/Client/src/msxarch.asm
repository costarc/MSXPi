; MSXPi Interface
; Version 1.6
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
; msxarch.com - MSX Archive browser and ROM loader, in Z80 assembly.
; Assembly port of msxarch.c; behaviour and the wire protocol are unchanged.
;
;   sjasmplus -DMSXPI_RAM_STASH --inc=./asm-common/include \
;             --raw=./target/msxarch.com ./Client/src/msxarch.asm
;
; Everything (code, data, work RAM) stays below 4000h: the mapper loader
; switches pages 1 and 2 to other segments while it runs.

        org     $0100

; ===========================================================================
; Constants
; ===========================================================================
F_OPEN:         EQU     $0F
F_CLOSE:        EQU     $10
F_READSEQ:      EQU     $14
F_DTAOFF:       EQU     $1A

; Main-ROM BIOS. Under MSX-DOS page 0 is RAM, so these are reached through
; CALSLT - a plain CALL lands in whatever DOS keeps there.
B_CHGMOD:       EQU     $005F
B_CHGET:        EQU     $009F
B_CHPUT:        EQU     $00A2
B_CLS:          EQU     $00C3
B_POSIT:        EQU     $00C6   ; H = column, L = row, both 1-based
LINL40:         EQU     $F3AE
LINLEN:         EQU     $F3B0

MAX_REPOS:      EQU     8
MAX_URL_LEN:    EQU     100
INI_BUFFER_SIZE:EQU     1024
LIST_PAGE_SIZE: EQU     22*80

KEY_UP:         EQU     $1E
KEY_DOWN:       EQU     $1F
KEY_ENTER:      EQU     $0D
KEY_BACKSPACE:  EQU     $08

INPUT_P:        EQU     1
INPUT_N:        EQU     2
INPUT_Q:        EQU     3
INPUT_UP:       EQU     4
INPUT_DOWN:     EQU     5
INPUT_NUMBER:   EQU     6

; ROM header sent by the server
ROM_HEADER_MAGIC: EQU   'R'
ROM_HEADER_SIZE:  EQU   16
ROM_MSG_MAX:      EQU   ROM_HEADER_SIZE+144
MAPPER_PLAIN:     EQU   0
MAPPER_KONAMI:    EQU   1
MAPPER_ASCII8:    EQU   2
MAPPER_ASCII16:   EQU   3
MAPPER_REJECTED:  EQU   $FF

; Transfer buffer for the archive list and the drained body of a refused
; ROM: page 2, free TPA while nothing is loaded there.
XFERBUF:        EQU     $8000

; ---------------------------------------------------------------------------
; Loader state in the page-3 gap below the resident table. None of it is
; needed once the game runs.
; ---------------------------------------------------------------------------
MAX_STORAGE_SEGMENTS: EQU 64
PAIR_CACHE0_ENTRIES:  EQU 8
PAIR_CACHE1_ENTRIES:  EQU 16
BANK_HALF_SIZE:       EQU $2000

storageSegments:    EQU $F900
execSegment1:       EQU $F940
execSegment2:       EQU $F941
safeZoneSegment:    EQU $F950
segInUse0:          EQU $F951   ; F951-F954: segments DOS runs in, pages 0-3
segInUse2:          EQU $F953
segTotal:           EQU $F955
segNext:            EQU $F956
pairCacheCounts:    EQU $F957   ; [page 1, page 2]
pairCacheSegments:  EQU $F959   ; 8 page-1 entries, then 16 page-2 entries

; ---------------------------------------------------------------------------
; Resident bank-switch handlers. They must survive the game, which owns all
; user RAM: BILLIARD.ROM zeroes C000h-F37Fh first thing. F975h upwards is
; above that and below the hook area (the region SofaRun uses too); the 16K
; handlers must end below FAF5h, where the MSX2 system variables start.
; msxpi-server patches the ROM's bank writes into CALLs to these addresses,
; which buildSelection sends it.
; ---------------------------------------------------------------------------
RESIDENT_TABLE_ADDR:    EQU $F975   ; 64 segments, indexed by bank AND 3Fh
RESIDENT_CUR_ADDR:      EQU $F9B5   ; 8K: bank in each window W1..W4
RESIDENT_PG0_ADDR:      EQU $F9B9   ; 8K page 1: segment, next victim, entries
RESIDENT_PG1_ADDR:      EQU $F9BC   ; 8K page 2: likewise
RESIDENT_8K_BASE:       EQU $F9C0   ; 4 x 5-byte entries + switch routine
RESIDENT_8K_WIN1_ADDR:  EQU $F9C0
RESIDENT_8K_WIN2_ADDR:  EQU $F9C5
RESIDENT_8K_WIN3_ADDR:  EQU $F9CA
RESIDENT_8K_WIN4_ADDR:  EQU $F9CF
RESIDENT_8K_SIZE:       EQU $D0
RESIDENT_CACHE0_ADDR:   EQU $FA90   ; (lo, hi, segment) x 8
RESIDENT_CACHE1_ADDR:   EQU $FAA8   ; (lo, hi, segment) x 16
RESIDENT_8K_DISPATCH_ADDR: EQU $FAD8
RESIDENT_PAGE1_ADDR:    EQU $FAC0   ; 16K handlers (an 8K game never loads them)
RESIDENT_PAGE2_ADDR:    EQU $FAD8
RESIDENT_16K_END:       EQU $FAF5
; ASCII16 page-2 slot emulation, in the 8K handlers' space.
RESIDENT_P2_MODE:       EQU $F9B5   ; 0 = cartridge bank at 8000h, 1 = work RAM
RESIDENT_P2_CARTSEG:    EQU $F9B6
RESIDENT_P2_WORKSEG:    EQU $F9B7
RESIDENT_P2_SELECT:     EQU $F9C0
RESIDENT_P2_RAM:        EQU $F9E0
RESIDENT_P2_CART:       EQU $F9F0

; ===========================================================================
; Entry point
; ===========================================================================
MAIN:
        call    resetMSXPI
        ld      a,80                    ; SCREEN 0 : WIDTH 80
        ld      (LINL40),a
        xor     a
        ld      ix,B_CHGMOD
        call    BiosCall

        call    LoadRepositoryList
        ld      a,(REPO_COUNT)
        or      a
        jr      nz,.haveRepos
        ld      hl,DEFAULT_URL
        ld      de,REPO_LIST
        ld      bc,DEFAULT_URL_LEN
        ldir
        ld      a,1
        ld      (REPO_COUNT),a
.haveRepos:
        ld      hl,RepoEntryTable       ; items = repos + "Exit"
        ld      de,ITEMS
        ld      a,(REPO_COUNT)
        add     a,a
        ld      c,a
        ld      b,0
        ldir
        ld      hl,EXIT_STR
        ex      de,hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      a,(REPO_COUNT)
        inc     a
        ld      (MENU_COUNT),a

MenuLoop:
        call    ShowMenu                ; HL = selection
        ld      (PARAMS),hl
        ld      de,EXIT_STR
        call    StrEq
        jr      c,.exit
        ld      hl,(PARAMS)
        ld      de,STR_Q
        call    StrEq
        jr      c,.exit
        ld      hl,MSG_SELECTED
        call    PrintStr
        ld      hl,(PARAMS)
        call    PrintStr
        ld      hl,MSG_CONNECTING
        call    PrintStr
        ld      hl,0
        ld      (PAGE_OFFSET),hl
        jp      OpenList
.exit:
        ld      hl,MSG_EXIT_SELECTED
        call    PrintStr
        jp      Exit

; ---------------------------------------------------------------------------
; Archive list browsing. A rejected game ends the server session, so the
; list is opened again and paged back to where the user was (PAGE_OFFSET).
; ---------------------------------------------------------------------------
OpenList:
        ld      de,CMD_MSXARCHIVE
        call    SendCommandToMSXPi
        jr      nc,.cmdOk
        ld      hl,MSG_SEND_ERR
        call    PrintStr
        jp      QuitExit
.cmdOk:
        ld      hl,MSG_SENDING_PARMS
        call    PrintStr
        ld      hl,(PARAMS)
        call    PrintStr
        ld      de,(PARAMS)
        call    SendCommandToMSXPi
        jp      c,QuitExit
        ld      hl,(PAGE_OFFSET)
        ld      (REPLAY),hl
        xor     a
        ld      (RETURN_TO_MENU),a
        ld      (REOPEN),a

ListLoop:
        ld      de,XFERBUF
        ld      bc,MAXBUFSIZE
        call    RecvAll                 ; A = rc, HL = size
        jr      nc,.received
        ld      hl,0                    ; transfer failed: nothing usable
.received:
        push    af
        call    TerminateList
        pop     af
        jr      c,.recvErr
        cp      RC_SUCCESS
        jr      z,.recvOk
.recvErr:
        ld      hl,XFERBUF
        call    IsArchiveError
        ld      hl,XFERBUF
        jr      c,.showErr
        ld      hl,MSG_LIST_UNREADABLE
.showErr:
        call    ShowArchiveError
        jr      .toMenu
.recvOk:
        ld      hl,XFERBUF
        call    IsArchiveError
        jr      nc,.replay
        ld      hl,XFERBUF
        call    ShowArchiveError
.toMenu:
        ld      a,1
        ld      (RETURN_TO_MENU),a
        jp      EndList

.replay:
        ld      hl,(REPLAY)             ; reopened: page back first
        ld      a,h
        or      l
        jr      z,.show
        ld      de,CMD_N
        dec     hl
        bit     7,h
        jr      z,.stepped              ; was > 0: next page, one fewer to go
        inc     hl
        inc     hl
        ld      de,CMD_P
.stepped:
        ld      (REPLAY),hl
        call    SendCommandToMSXPi
        jp      c,EndList
        jr      ListLoop

.show:
        ld      de,$0001
        call    Locate
        ld      b,80
.rule:  ld      a,'='
        call    PrintChar
        djnz    .rule
        ld      de,$0002
        call    Locate
        ld      hl,XFERBUF
        call    FastPrint
        ld      de,0
        call    Locate
        ld      hl,MSG_LIST_KEYS
        call    PrintStr
        ld      de,0
        call    Locate
        call    GetValidInput
        cp      INPUT_Q
        jr      nz,.notQuit
        ld      a,1
        ld      (RETURN_TO_MENU),a
        jp      EndList
.notQuit:
        ld      de,CMD_N
        ld      bc,1
        cp      INPUT_N
        jr      z,.page
        cp      INPUT_DOWN
        jr      z,.page
        ld      de,CMD_P
        ld      bc,-1
        cp      INPUT_P
        jr      z,.page
        cp      INPUT_UP
        jr      z,.page
        jr      SelectGame
.page:
        ld      hl,(PAGE_OFFSET)
        add     hl,bc
        ld      (PAGE_OFFSET),hl
        call    SendCommandToMSXPi
        jp      c,EndList
        jp      ListLoop

; Null-terminate the received list text at min(HL, LIST_PAGE_SIZE-1).
TerminateList:
        ld      de,LIST_PAGE_SIZE-1
        or      a
        sbc     hl,de
        add     hl,de
        jr      c,.fits
        ex      de,hl
.fits:
        ld      de,XFERBUF
        add     hl,de
        ld      (hl),0
        ret

SelectGame:
        call    BuildSelection
        ld      de,SELBUF
        call    SendCommandToMSXPi
        jp      c,EndList
        call    Cls
        call    ReadRomHeader
        jr      nc,.hdrOk
        ld      hl,MSG_HDR_ERR
        call    PrintStr
        jp      QuitExit
.hdrOk:
        ; Rejected (not enough RAM, unsupported mapper, missing file...):
        ; the server has ended the session, so show why and reopen the list.
        ld      a,(HDR_MAPPER)
        cp      MAPPER_REJECTED
        jr      nz,.accepted
        ld      hl,HDR_REASON
        call    PrintStr
        ld      hl,MSG_CHOOSE_ANOTHER
        call    PrintStr
        call    WaitForKey
        ld      a,1
        ld      (REOPEN),a
        jp      EndList
.accepted:
        ; For an accepted ROM the text after the header is the game's name.
        ld      hl,MSG_LOADING
        call    PrintStr
        ld      hl,HDR_REASON
        call    PrintStr
        ld      hl,MSG_OPEN_PAREN
        call    PrintStr
        ld      de,1023                 ; (totalSize + 1023) >> 10
        ld      b,2
        call    TotalRoundShift
        call    PrintDec
        ld      hl,MSG_KB
        call    PrintStr

        ; Blocks are always 8KB.
        ld      a,(HDR_MAPPER)
        or      a
        jr      nz,.mappedBar
        ld      de,8191                 ; (totalSize + 8191) >> 13
        ld      b,5
        call    TotalRoundShift
        jr      .bar
.mappedBar:
        call    FullChunks
.bar:
        call    ProgressStart

        ld      a,(HDR_MAPPER)
        or      a
        jr      nz,.mapped
        ld      a,(HDR_TOTAL+3)         ; plain ROM: at most 32KB
        ld      hl,(HDR_TOTAL+1)
        or      h
        jr      nz,.tooLarge
        ld      a,l
        cp      $80
        jr      c,.plainOk
        jr      nz,.tooLarge
        ld      a,(HDR_TOTAL)
        or      a
        jr      z,.plainOk
.tooLarge:
        ld      hl,MSG_PLAIN_TOO_LARGE
        call    PrintStr
        jp      QuitExit
.plainOk:
        call    LoadPlainRom
        jr      .loaded
.mapped:
        cp      MAPPER_ASCII16+1
        jr      c,.mapperOk
        ld      hl,MSG_MAPPER_UNSUPPORTED
        call    PrintStr
        ld      a,(HDR_MAPPER)
        ld      l,a
        ld      h,0
        call    PrintDec
        jp      QuitExit
.mapperOk:
        call    LoadMappedRom
.loaded:
        jr      nc,.launch
        push    af
        ld      hl,MSG_LOAD_ERR
        call    PrintStr
        pop     af
        ld      l,a
        ld      h,0
        call    PrintDec
        jp      Exit
.launch:
        ; rebootAfterRomLoad=yes: the game needs nothing more from the Pi.
        ld      a,(REBOOT_AFTER_ROM_LOAD)
        or      a
        ld      de,CMD_SHUTDOWN
        call    nz,SendCommandToMSXPi
        jp      LaunchGame

EndList:
        call    SendQuit
        ld      a,(REOPEN)
        or      a
        jr      z,.noReopen
        call    Cls
        jp      OpenList
.noReopen:
        ld      a,(RETURN_TO_MENU)
        or      a
        jp      z,Exit
        call    Cls
        jp      MenuLoop

QuitExit:
        call    SendQuit
Exit:
        ld      c,0
        jp      BDOS

SendQuit:
        ld      de,STR_Q
        jp      SendCommandToMSXPi

; ===========================================================================
; Protocol helpers
; ===========================================================================

; RecvAll: a whole multi-block transfer into one buffer (msxpi.h RECVDATA).
;   DE = destination, BC = block size to negotiate
; Out: NC, A = rc of the last block, HL = bytes received
;      C  on a transfer error (A = error code)
RecvAll:
        push    de
        call    PerformHandshake
        jr      c,.fail
        xor     a                       ; block index
.block:
        push    af
        push    bc
        call    RECVDATA_ONEBLOCK       ; A = header rc, DE advanced
        pop     bc
        jr      c,.failIdx
        cp      RC_READY
        jr      nz,.done
        pop     af
        inc     a
        jr      .block
.done:
        pop     hl                      ; drop the index
        ex      de,hl                   ; HL = end
        pop     de                      ; DE = start
        or      a
        sbc     hl,de
        ret                             ; NC, A = rc
.failIdx:
        pop     hl
.fail:
        pop     de
        scf
        ret

; ReadRomHeader: receive the fixed header plus the reason / game name.
; Out: NC = valid header in HDRBUF (HDR_MAPPER = FFh if rejected),
;      HDR_REASON 0-terminated. C = failed.
ReadRomHeader:
        ld      de,HDRBUF
        ld      bc,ROM_MSG_MAX
        call    RecvAll
        ret     c
        ; RC_TERMINATE on the header is a fatal rejection: the server has
        ; ended the conversation. It carries a header and the reason, like
        ; any rejection.
        cp      RC_SUCCESS
        jr      z,.rcOk
        cp      RC_TERMINATE
        scf
        ret     nz
        ld      b,a
        ld      a,MAPPER_REJECTED
        ld      (HDR_MAPPER),a          ; overwritten below if too short anyway
        ld      a,b
.rcOk:
        ld      de,ROM_HEADER_SIZE
        or      a
        sbc     hl,de
        ret     c                       ; shorter than a header
        ld      de,HDR_REASON
        add     hl,de
        ld      (hl),0                  ; terminate the reason text
        ld      b,a
        ld      a,(HDRBUF)
        cp      ROM_HEADER_MAGIC
        scf
        ret     nz
        ld      a,b
        cp      RC_TERMINATE
        ld      a,(HDRBUF+2)
        jr      nz,.type
        ld      a,MAPPER_REJECTED
.type:
        ld      (HDR_MAPPER),a
        or      a
        ret

; HL = ((totalSize + DE) >> 8) >> B, from HDR_TOTAL.
TotalRoundShift:
        ld      hl,(HDR_TOTAL)
        add     hl,de
        ld      a,(HDR_TOTAL+2)
        adc     a,0
        ld      c,a
        ld      a,(HDR_TOTAL+3)
        adc     a,0
        ld      l,h                     ; A:C:L = bits 8-31
        ld      h,c
.shift: srl     a
        rr      h
        rr      l
        djnz    .shift
        ret

; HL = bankCount * (bankSizeKB / 8): 8KB chunks in the whole image.
FullChunks:
        ld      hl,(HDR_BANKCOUNT)
        ld      a,(HDR_BANKKB)
        cp      16
        ret     nz
        add     hl,hl
        ret

; ===========================================================================
; Plain ROM loading
; ===========================================================================
; MAXBUFSIZE (8KB) blocks, never 16KB: a 16KB negotiation deadlocks the
; transfer. Writes into the ROM's own window are neutralised by the server.
LoadPlainRom:
        ld      bc,MAXBUFSIZE
        call    PerformHandshake
        jr      c,.end
        ld      de,$4000
        xor     a
.block:
        push    af
        ld      bc,MAXBUFSIZE
        call    RECVDATA_ONEBLOCK
        push    af
        push    de
        call    ProgressDot
        pop     de
        pop     af
        jr      c,.fail
        cp      RC_READY
        jr      nz,.last
        pop     af
        inc     a
        jr      .block
.last:
        pop     hl
        cp      RC_SUCCESS
        jr      z,.ok
        scf
        jr      .end
.fail:
        pop     hl
.end:
        push    af
        call    ProgressEnd
        pop     af
        ret     c
.ok:
        call    ProgressEnd
        ld      hl,MSG_GAME_LOADED
        call    PrintStr
        or      a
        ret

; ===========================================================================
; Mapper-aware ROM loading (Konami / ASCII8 / ASCII16)
; ===========================================================================
; MSXPi boots MSX-DOS 1, which has no mapper support routines and only uses
; the four segments selected in pages 0-3. So the mapper size is detected
; here and segments are handed out top down, never the four DOS lives in.
; ---------------------------------------------------------------------------

; A = segments in the mapper (max 255). Keeps segment 0 as a sentinel and
; steps upwards: the first n whose write disturbs it is the wrap point.
; Every byte touched is restored - the probe address is live in whichever
; segment is selected, including DOS's own.
DetectMapperSegments:
        in      a,($FE)
        ld      (DMS_SAVED),a
        xor     a
        out     ($FE),a
        ld      a,($8000)
        ld      (DMS_KEEP0),a
        ld      a,$A5
        ld      ($8000),a
        ld      b,1                     ; count
        ld      c,1                     ; n
.probe:
        ld      a,c
        out     ($FE),a
        ld      a,($8000)
        ld      e,a                     ; keepN
        ld      a,c
        ld      ($8000),a
        xor     a
        out     ($FE),a
        ld      a,($8000)
        cp      $A5
        ld      a,c
        out     ($FE),a
        jr      nz,.restoreN            ; wrapped onto segment 0
        ld      a,($8000)
        cp      c
        jr      nz,.restoreN
        ld      a,e
        ld      ($8000),a
        ld      a,c
        inc     a
        jr      nz,.count
        dec     a                       ; 256 segments: 255 is the highest
.count: ld      b,a
        inc     c
        jr      nz,.probe
        jr      .done
.restoreN:
        ld      a,e
        ld      ($8000),a
.done:
        xor     a
        out     ($FE),a
        ld      a,(DMS_KEEP0)
        ld      ($8000),a
        ld      a,(DMS_SAVED)
        out     ($FE),a
        ld      a,b
        ret

; Z if segment A is one DOS is using. Keeps A.
SegmentIsReserved:
        ld      hl,segInUse0
        ld      b,4
.cmp:   cp      (hl)
        ret     z
        inc     hl
        djnz    .cmp
        ret                             ; NZ (the last cp was not equal)

; A = next free segment, top down. C if none left.
TakeSegment:
        ld      a,(segNext)
        or      a
        scf
        ret     z
        ld      c,a
        dec     a
        ld      (segNext),a
        ld      a,c
        call    SegmentIsReserved
        jr      z,TakeSegment
        ld      a,c
        or      a
        ret

; A = segments TakeSegment can hand out (1..segTotal-1 minus DOS's four).
; Sent with every selection, so the server refuses a ROM that cannot fit
; before sending it.
UsableMapperSegments:
        ld      hl,segInUse0
        ld      c,$FC
.save:  in      a,(c)
        ld      (hl),a
        inc     hl
        inc     c
        jr      nz,.save
        call    DetectMapperSegments
        ld      (segTotal),a
        ld      d,0
.count: dec     a
        jr      z,.done
        ld      e,a
        call    SegmentIsReserved
        ld      a,e
        jr      z,.count
        inc     d
        jr      .count
.done:  ld      a,d
        ret

; A = storage segments needed. C on failure.
; A mapped ROM takes its storage plus two exec segments and the safe zone;
; the pair caches get what is left.
AllocateMapperSegments:
        ld      (STORAGE_COUNT),a
        call    UsableMapperSegments
        ld      l,a
        ld      a,(STORAGE_COUNT)
        add     a,3
        ld      b,a
        ld      a,l
        cp      b
        jr      nc,.enough
        push    bc                      ; normally caught by the server first
        ld      h,0
        push    hl
        ld      hl,MSG_NOT_ENOUGH
        call    PrintStr
        pop     hl
        call    PrintDec
        ld      hl,MSG_NEED
        call    PrintStr
        pop     bc
        ld      l,b
        ld      h,0
        call    PrintDec
        ld      hl,MSG_NL
        call    PrintStr
        scf
        ret
.enough:
        ld      a,(segTotal)
        dec     a
        ld      (segNext),a
        call    TakeSegment
        ret     c
        ld      (execSegment1),a
        call    TakeSegment
        ret     c
        ld      (execSegment2),a
        ld      hl,storageSegments
        ld      a,(STORAGE_COUNT)
        ld      b,a
.storage:
        push    bc
        push    hl
        call    TakeSegment
        pop     hl
        pop     bc
        ret     c
        ld      (hl),a
        inc     hl
        djnz    .storage
        call    TakeSegment
        ret     c
        ld      (safeZoneSegment),a

        ; Pair caches for the 8K handlers, the exec segment being entry 0.
        ; Page 2 gets the larger cache: Konami games keep music/code in one
        ; 8K half while screen transitions swap the other.
        ld      a,(execSegment1)
        ld      (pairCacheSegments),a
        ld      a,(execSegment2)
        ld      (pairCacheSegments+PAIR_CACHE0_ENTRIES),a
        ld      hl,pairCacheSegments+PAIR_CACHE0_ENTRIES+1
        ld      b,PAIR_CACHE1_ENTRIES
        call    .fill
        ld      (pairCacheCounts+1),a
        ld      hl,pairCacheSegments+1
        ld      b,PAIR_CACHE0_ENTRIES
        call    .fill
        ld      (pairCacheCounts),a
        or      a
        ret
; Fill up to B-1 more entries at HL; A = entries in use (1..B).
.fill:
        ld      e,1
.next:  ld      a,e
        cp      b
        ret     nc
        push    bc
        push    de
        push    hl
        call    TakeSegment
        pop     hl
        pop     de
        pop     bc
        jr      c,.full
        ld      (hl),a
        inc     hl
        inc     e
        jr      .next
.full:  ld      a,e
        ret

; storageCount = bankSizeKB == 16 ? bankCount : (bankCount + 1) / 2
; C on failure.
LoadMappedRom:
        ; 8KB chunks the server actually sends: a patched ROM may stop part
        ; way into its last bank instead of being padded (ARCTIC_MSXPI.ROM,
        ; 136KB in 9 banks). The bank count sizes the storage, totalSize the
        ; transfer; the unsent tail of the last segment is never selected.
        ld      de,8191
        ld      b,5
        call    TotalRoundShift
        push    hl
        call    FullChunks
        pop     de                      ; DE = sent, HL = full
        ld      a,d
        or      e
        jr      z,.chunks
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      c,.chunks
        jr      z,.chunks
        ex      de,hl                   ; 0 < sent < full: use sent
.chunks:
        ld      (CHUNKS),hl

        ld      hl,(HDR_BANKCOUNT)
        ld      a,(HDR_BANKKB)
        cp      16
        jr      z,.count
        inc     hl
        srl     h
        rr      l
.count:
        ld      (STORAGE_COUNT16),hl
        ld      de,MAX_STORAGE_SEGMENTS+1
        or      a
        sbc     hl,de
        jr      c,.fits
        ld      hl,MSG_TOO_LARGE
        call    PrintStr
        ld      hl,(STORAGE_COUNT16)
        call    PrintDec
        ld      hl,MSG_SEG
        call    PrintStr
        jr      .drain
.fits:
        ld      a,(STORAGE_COUNT16)
        call    AllocateMapperSegments
        jr      nc,.load
.drain:
        call    DrainMappedRomBody
        call    ProgressEnd
        ld      a,RC_FAILED
        scf
        ret
.load:
        call    LoadBanksIntoStorage
        push    af
        call    ProgressEnd
        pop     af
        jr      nc,.loaded
        ld      hl,MSG_BANKS_ERR
        call    PrintStr
        ld      a,(segInUse2)           ; put page 2 back where DOS had it
        out     ($FE),a
        ld      a,RC_FAILED
        scf
        ret
.loaded:
        ld      hl,MSG_CACHE
        call    PrintStr
        ; The bank writes are already CALLs to the resident handlers - the
        ; server patched the image. The handlers themselves must be copied.
        ld      a,(HDR_MAPPER)
        cp      MAPPER_ASCII16
        jr      nz,.eightK
        call    RelocateResidentHandlers16K
        ld      a,(storageSegments)
        out     ($FD),a
        ld      hl,(HDR_BANKCOUNT)
        ld      de,2
        or      a
        sbc     hl,de
        ld      a,(storageSegments)
        jr      c,.p2
        ld      a,(storageSegments+1)
.p2:    out     ($FE),a
        jr      .done
.eightK:
        call    RelocateResidentHandlers8K
        call    InitialSetup8K
        ld      a,(HDR_MAPPER)
        cp      MAPPER_KONAMI
        jr      nz,.done
        ld      hl,(HDR_BANKCOUNT)
        ld      de,16
        or      a
        sbc     hl,de
        call    z,PrewarmKonami16PairCache
.done:
        ld      hl,MSG_GAME_LOADED
        call    PrintStr
        or      a
        ret

; Chunk c goes to storageSegments[c/2], offset (c AND 1) * 8KB, through
; page 2. C on failure.
LoadBanksIntoStorage:
        ld      bc,MAXBUFSIZE
        call    PerformHandshake
        ret     c
        ld      hl,0
        ld      (CHUNK),hl
.chunk:
        ld      hl,(CHUNK)
        ld      de,(CHUNKS)
        or      a
        sbc     hl,de
        jr      nc,.all
        ld      hl,(CHUNK)
        ld      a,l
        srl     h
        rr      l
        ld      de,storageSegments
        add     hl,de
        ld      c,a                     ; C = chunk index (low byte)
        ld      a,(hl)
        out     ($FE),a
        ld      de,$8000
        bit     0,c
        jr      z,.even
        ld      d,$A0
.even:  ld      a,c
        ld      bc,MAXBUFSIZE
        call    RECVDATA_ONEBLOCK       ; BC = received size
        push    af
        push    bc
        call    ProgressDot
        pop     bc
        pop     af
        ret     c
        cp      RC_READY
        jr      z,.good
        cp      RC_SUCCESS
        scf
        ret     nz
.good:  ld      a,b
        or      c
        scf
        ret     z                       ; empty block
        ld      hl,(CHUNK)
        inc     hl
        ld      (CHUNK),hl
        jr      .chunk
.all:
        ld      a,(execSegment2)
        out     ($FE),a
        or      a
        ret

; Consume the body of a ROM that could not be placed, so both sides stay
; in step.
DrainMappedRomBody:
        ld      bc,MAXBUFSIZE
        call    PerformHandshake
        ret     c
        ld      hl,(CHUNKS)
        xor     a
.chunk:
        ld      d,a
        ld      a,h
        or      l
        ret     z
        ld      a,d
        push    hl
        push    af
        ld      de,XFERBUF
        ld      bc,MAXBUFSIZE
        call    RECVDATA_ONEBLOCK
        push    af
        call    ProgressDot
        pop     af
        pop     de                      ; D = index
        pop     hl
        ret     c
        cp      RC_READY
        jr      z,.good
        cp      RC_SUCCESS
        scf
        ret     nz
.good:  dec     hl
        ld      a,d
        inc     a
        jr      .chunk

; Copy 8K bank A into page TGT_PAGE at offset HL, reading it through page
; SRC_PAGE (1 or 2). The source page is given its exec segment back. Keeps
; the caller's interrupt state: the Konami prewarm runs with page 2 on a
; cache segment.
MapperCopyBank:
        ld      c,a
        ld      a,i                     ; P/V = IFF2
        di
        push    af
        push    hl                      ; target offset
        ld      a,c
        srl     a
        ld      e,a
        ld      d,0
        ld      hl,storageSegments
        add     hl,de
        ld      e,(hl)                  ; E = storage segment
        ld      a,(SRC_PAGE)
        add     a,$FC
        ld      b,c
        ld      c,a                     ; C = source page port
        out     (c),e
        ld      hl,$4000
        cp      $FD
        jr      z,.src1
        ld      h,$80
.src1:  bit     0,b
        jr      z,.srcEven
        set     5,h                     ; + 2000h
.srcEven:
        pop     de                      ; target offset
        push    bc
        ld      a,(TGT_PAGE)
        ld      bc,$4000
        cp      1
        jr      z,.tgt1
        ld      b,$80
.tgt1:  ex      de,hl
        add     hl,bc
        ex      de,hl
        ld      bc,BANK_HALF_SIZE
        ldir
        pop     bc
        ld      a,c
        cp      $FD
        ld      a,(execSegment1)
        jr      z,.back
        ld      a,(execSegment2)
.back:  out     (c),a
        pop     af
        ret     po
        ei
        ret

; MapperCopyBank with the pages given in B (source) and C (target).
CopyBank:
        push    af
        ld      a,b
        ld      (SRC_PAGE),a
        ld      a,c
        ld      (TGT_PAGE),a
        pop     af
        jr      MapperCopyBank

; Konami and ASCII8 both start with banks 0..3 in windows 1..4.
InitialSetup8K:
        ld      a,(execSegment1)
        out     ($FD),a
        ld      a,(execSegment2)
        out     ($FE),a
        ld      hl,(HDR_BANKCOUNT)
        ld      a,h
        or      a
        ld      a,l
        jr      z,.small
        ld      a,4                     ; >= 256 banks: all four
.small: ld      (SETUP_BANKS),a
        ld      ix,SetupCopies
        xor     a
.copy:  ld      hl,SETUP_BANKS
        cp      (hl)
        ret     nc
        push    af
        ld      l,(ix+0)
        ld      h,(ix+1)
        ld      b,(ix+2)
        ld      c,(ix+3)
        call    CopyBank
        ld      de,4
        add     ix,de
        pop     af
        inc     a
        cp      4
        jr      c,.copy
        ret
; target offset, source page, target page - one line per bank 0..3
SetupCopies:
        dw      0
        db      2,1
        dw      BANK_HALF_SIZE
        db      2,1
        dw      0
        db      1,2
        dw      BANK_HALF_SIZE
        db      1,2

; Fill all 64 table entries, mirroring the ROM as the cartridge does: with
; the AND 3Fh in the handlers every reachable index is a real segment.
FillResidentTable:
        ld      hl,RESIDENT_TABLE_ADDR
        ld      a,(STORAGE_COUNT16)
        ld      c,a
        ld      de,storageSegments
        ld      b,64
        ld      a,c                     ; A = entries left before wrapping
.fill:  push    af
        ld      a,(de)
        ld      (hl),a
        inc     hl
        inc     de
        pop     af
        dec     a
        jr      nz,.next
        ld      de,storageSegments
        ld      a,c
.next:  djnz    .fill
        ret

RelocateResidentHandlers16K:
        call    FillResidentTable
        ld      hl,Ascii16Page1Src
        ld      de,RESIDENT_PAGE1_ADDR
        ld      bc,Ascii16Page1End-Ascii16Page1Src
        ldir
        ld      hl,Ascii16Page2Src
        ld      de,RESIDENT_PAGE2_ADDR
        ld      bc,Ascii16Page2End-Ascii16Page2Src
        ldir
        xor     a
        ld      (RESIDENT_P2_MODE),a
        ld      a,(STORAGE_COUNT16)
        dec     a
        ld      a,(storageSegments)
        jr      z,.one
        ld      a,(storageSegments+1)
.one:   ld      (RESIDENT_P2_CARTSEG),a
        ld      a,(execSegment2)        ; unused by ASCII16 otherwise
        ld      (RESIDENT_P2_WORKSEG),a
        ld      hl,Ascii16P2Src
        ld      de,RESIDENT_P2_SELECT
        ld      bc,Ascii16P2End-Ascii16P2Src
        ldir
        ret

RelocateResidentHandlers8K:
        call    FillResidentTable
        ld      hl,RESIDENT_CUR_ADDR    ; banks 0..3 are in windows 1..4
        xor     a
.cur:   ld      (hl),a
        inc     hl
        inc     a
        cp      4
        jr      nz,.cur
        ; page 1
        ld      ix,RESIDENT_PG0_ADDR
        ld      hl,RESIDENT_CACHE0_ADDR
        ld      de,pairCacheSegments
        ld      a,(pairCacheCounts)
        ld      bc,PAIR_CACHE0_ENTRIES*256+0
        call    .page
        ; page 2
        ld      ix,RESIDENT_PG1_ADDR
        ld      hl,RESIDENT_CACHE1_ADDR
        ld      de,pairCacheSegments+PAIR_CACHE0_ENTRIES
        ld      a,(pairCacheCounts+1)
        ld      bc,PAIR_CACHE1_ENTRIES*256+2
        call    .page
        ld      hl,Ascii8HandlersSrc
        ld      de,RESIDENT_8K_BASE
        ld      bc,Ascii8HandlersEnd-Ascii8HandlersSrc
        ldir
        ld      hl,Ascii8DispatchSrc
        ld      de,RESIDENT_8K_DISPATCH_ADDR
        ld      bc,Ascii8DispatchEnd-Ascii8DispatchSrc
        ldir
        ret
; IX = page record, HL = cache, DE = its segments, A = entries in use,
; B = cache size, C = first bank of the page (0 or 2).
.page:
        ld      (ix+2),a
        cp      2
        ld      a,0
        jr      c,.victim
        inc     a
.victim:
        ld      (ix+1),a
        ld      a,(de)
        ld      (ix+0),a
        ld      (hl),c                  ; entry 0 holds (c, c+1)
        inc     hl
        inc     c
        ld      (hl),c
        inc     hl
        dec     b
.entry: ld      a,(de)
        ld      (hl),a
        inc     hl
        inc     de
        ld      a,b
        or      a
        ret     z
        ld      (hl),$FF                ; no pair yet
        inc     hl
        ld      (hl),$FF
        inc     hl
        dec     b
        jr      .entry

; NEMESIS-style 16-bank Konami games switch page 2 between bank 3 and most
; of the others all the time: fill the page-2 cache with (b, 3) pairs up
; front instead of copying on the first switch.
PrewarmKonami16PairCache:
        ld      a,i
        di
        push    af
        ld      a,1
        ld      (PW_ENTRY),a
        xor     a
        ld      (PW_BANK),a
.loop:
        ld      a,(pairCacheCounts+1)
        ld      b,a
        ld      a,(PW_ENTRY)
        cp      b
        jr      nc,.end
        ld      a,(PW_BANK)
        cp      2
        jr      nz,.not2
        ld      a,4
.not2:  cp      16
        jr      nz,.not16
        ld      a,3
.not16: ld      (PW_BANK),a
        ld      hl,pairCacheSegments+PAIR_CACHE0_ENTRIES
        ld      a,(PW_ENTRY)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      a,(hl)
        ld      (PW_SEG),a
        out     ($FE),a
        ld      a,(PW_BANK)
        ld      hl,0
        ld      bc,$0102
        call    CopyBank
        ld      a,3
        ld      hl,BANK_HALF_SIZE
        ld      bc,$0102
        call    CopyBank
        ld      a,(PW_ENTRY)            ; cache[e*3] = (b, 3, segment)
        ld      l,a
        add     a,a
        add     a,l
        ld      e,a
        ld      d,0
        ld      hl,RESIDENT_CACHE1_ADDR
        add     hl,de
        ld      a,(PW_BANK)
        ld      (hl),a
        inc     hl
        ld      (hl),3
        inc     hl
        ld      a,(PW_SEG)
        ld      (hl),a
        ld      hl,PW_ENTRY
        inc     (hl)
        ld      a,(PW_BANK)
        cp      3
        jr      z,.end
        inc     a
        ld      (PW_BANK),a
        jr      .loop
.end:
        ld      a,(pairCacheCounts+1)
        ld      b,a
        ld      a,(PW_ENTRY)
        cp      b
        jr      c,.victim
        ld      a,1
.victim:
        ld      (RESIDENT_PG1_ADDR+1),a
        ld      a,(execSegment1)
        out     ($FD),a
        ld      a,(execSegment2)
        out     ($FE),a
        pop     af
        ret     po
        ei
        ret

; ---------------------------------------------------------------------------
; buildSelection: "<number> W1 W2 W3 W4 P1 P2 DISPATCH SEGS P2RAM P2CART",
; hex. The server patches the ROM's bank writes into CALLs to these
; addresses; a server that knows fewer values ignores the rest. SEGS lets it
; refuse a ROM that cannot fit instead of sending it.
; ---------------------------------------------------------------------------
BuildSelection:
        ld      hl,OUT_NUMBER
        ld      de,SELBUF
.num:   ld      a,(hl)
        or      a
        jr      z,.addrs
        ld      (de),a
        inc     hl
        inc     de
        jr      .num
.addrs:
        ld      hl,SelectionAddrs
        ld      b,7
.addr:  push    bc
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        push    hl
        ld      h,b
        ld      l,c
        call    AppendHex4
        pop     hl
        pop     bc
        djnz    .addr
        push    de
        call    UsableMapperSegments
        pop     de
        ld      l,a
        ld      h,0
        call    AppendHex4
        ld      hl,RESIDENT_P2_RAM
        call    AppendHex4
        ld      hl,RESIDENT_P2_CART
        call    AppendHex4
        xor     a
        ld      (de),a
        ret
SelectionAddrs:
        dw      RESIDENT_8K_WIN1_ADDR, RESIDENT_8K_WIN2_ADDR
        dw      RESIDENT_8K_WIN3_ADDR, RESIDENT_8K_WIN4_ADDR
        dw      RESIDENT_PAGE1_ADDR,   RESIDENT_PAGE2_ADDR
        dw      RESIDENT_8K_DISPATCH_ADDR

; Append " XXXX" (HL in hex) at DE.
AppendHex4:
        ld      a,' '
        ld      (de),a
        inc     de
        ld      a,h
        call    .byte
        ld      a,l
.byte:  push    af
        rrca
        rrca
        rrca
        rrca
        call    .nib
        pop     af
.nib:   and     $0F
        add     a,'0'
        cp      '9'+1
        jr      c,.put
        add     a,'A'-'9'-1
.put:   ld      (de),a
        inc     de
        ret

; ===========================================================================
; Resident handlers. Assembled for the address they run at and copied there;
; they must survive in RAM after msxarch.com is gone.
; ===========================================================================

; --- ASCII16 ---
Ascii16Page1Src:
        PHASE   RESIDENT_PAGE1_ADDR
        push    af
        push    hl
        push    bc
        and     $3F                     ; bound to the 64-entry table
        ld      l,a
        ld      h,0
        ld      bc,RESIDENT_TABLE_ADDR
        add     hl,bc
        ld      a,(hl)
        out     ($FD),a
        pop     bc
        pop     hl
        pop     af
        ret
        DEPHASE
Ascii16Page1End:
        ASSERT  RESIDENT_PAGE1_ADDR + (Ascii16Page1End-Ascii16Page1Src) <= RESIDENT_PAGE2_ADDR

Ascii16Page2Src:
        PHASE   RESIDENT_PAGE2_ADDR
        jp      RESIDENT_P2_SELECT
        DEPHASE
Ascii16Page2End:
        ASSERT  RESIDENT_PAGE2_ADDR + (Ascii16Page2End-Ascii16Page2Src) <= RESIDENT_16K_END

; ARCTIC.ROM pages its work RAM into 8000h with ENASLT. Its cartridge and
; RAM slots are the same slot here, so the server turns those ENASLTs into
; CALLs to the RAM and cartridge selects below; the bank select only records
; the bank while work RAM is mapped. With MODE 0 (every other game) nothing
; changes.
Ascii16P2Src:
        PHASE   RESIDENT_P2_SELECT
        push    af
        push    hl
        push    bc
        and     $3F
        ld      l,a
        ld      h,0
        ld      bc,RESIDENT_TABLE_ADDR
        add     hl,bc
        ld      a,(hl)
        ld      (RESIDENT_P2_CARTSEG),a
        ld      b,a
        ld      a,(RESIDENT_P2_MODE)
        or      a
        ld      a,b
        jr      nz,.ram                 ; work RAM at 8000h: shows on next cart select
        out     ($FE),a
.ram:   pop     bc
        pop     hl
        pop     af
        ret
        ASSERT  $ <= RESIDENT_P2_RAM
        ds      RESIDENT_P2_RAM-$, 0
        ; replaces ENASLT(RAM slot, 8000h)
        push    af
        ld      a,1
        ld      (RESIDENT_P2_MODE),a
        ld      a,(RESIDENT_P2_WORKSEG)
        out     ($FE),a
        pop     af
        ret
        ASSERT  $ <= RESIDENT_P2_CART
        ds      RESIDENT_P2_CART-$, 0
        ; replaces ENASLT(own slot, 8000h)
        push    af
        xor     a
        ld      (RESIDENT_P2_MODE),a
        ld      a,(RESIDENT_P2_CARTSEG)
        out     ($FE),a
        pop     af
        ret
        ASSERT  $ <= RESIDENT_P2_CART+$10
        DEPHASE
Ascii16P2End:

; --- Konami & ASCII8 ---
; A cartridge switches an 8K window with one latch write; copying 8KB on
; every switch made NEMESIS's music crawl. A 16K page is fully determined by
; the pair of banks in its two windows and games reuse few pairs, so each
; page keeps a cache of segments already holding a (lo, hi) pair: the first
; use of a pair costs two 8KB copies, every later switch is one OUT.
;
; Entry: A = bank, return address on the stack; all registers preserved.
; Copied into RAM, so every jump is relative.
Ascii8HandlersSrc:
        PHASE   RESIDENT_8K_BASE
        push    hl                      ; W1
        ld      l,0
        jr      .switch
        push    hl                      ; W2
        ld      l,1
        jr      .switch
        push    hl                      ; W3
        ld      l,2
        jr      .switch
        push    hl                      ; W4
        ld      l,3
.switch:
        push    af
        push    bc
        push    de
        push    ix
        ld      c,l                     ; C = window 0-3
        ld      e,a                     ; E = bank
        ld      b,0
        ld      hl,RESIDENT_CUR_ADDR
        add     hl,bc
        ld      a,(hl)
        cp      e
        jr      nz,.changed
        pop     ix                      ; same bank again - a mapper ignores it
        pop     de
        pop     bc
        pop     af
        pop     hl
        ret
.changed:
        ld      (hl),e
        ld      a,i                     ; P/V = IFF2 of the caller
        push    af
        di
        ld      a,c
        and     2
        ld      c,a                     ; C = 0 (page 1) or 2 (page 2)
        ld      hl,RESIDENT_CUR_ADDR
        add     hl,bc
        ld      d,(hl)                  ; D = bank in the page's low window
        inc     hl
        ld      e,(hl)                  ; E = bank in its high window
        ld      ix,RESIDENT_PG0_ADDR
        ld      hl,RESIDENT_CACHE0_ADDR
        bit     1,c
        jr      z,.lookup
        ld      ix,RESIDENT_PG1_ADDR
        ld      hl,RESIDENT_CACHE1_ADDR
.lookup:
        ld      b,(ix+2)                ; entries in this page's cache
.scan:  ld      a,(hl)
        cp      d
        jr      nz,.miss1
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      e
        jr      nz,.miss1
        inc     hl
        inc     hl
        ld      a,(hl)                  ; segment already holding (lo, hi)
        ld      (ix+0),a
        jr      .select
.miss1: inc     hl
        inc     hl
        inc     hl
        djnz    .scan
        ; Miss: take the next victim entry and build its segment.
        ld      a,(ix+1)
        ld      l,a
        add     a,a
        add     a,l                     ; A = victim * 3
        ld      hl,RESIDENT_CACHE0_ADDR
        bit     1,c
        jr      z,.victim
        ld      hl,RESIDENT_CACHE1_ADDR
.victim:
        ld      c,a
        add     hl,bc                   ; B is 0 after the djnz
        ld      a,(ix+1)
        inc     a
        cp      (ix+2)
        jr      c,.rotate
        xor     a
.rotate:
        ld      (ix+1),a
        ld      (hl),d
        inc     hl
        ld      (hl),e
        inc     hl
        ld      a,(hl)                  ; segment of the victim entry
        ld      (ix+0),a
        out     ($FE),a                 ; build it at 8000h
        push    de
        ld      hl,$8000
        ld      a,d
.half:  push    hl                      ; destination half
        rrca                            ; carry = half of the storage segment
        ld      de,$4000
        jr      nc,.lowHalf
        ld      d,$60
.lowHalf:
        ; A is now the segment index (bank >> 1). AND 3Fh bounds it to the
        ; table: NEMESIS switches to an uninitialised bank number first.
        and     $3F
        add     a,RESIDENT_TABLE_ADDR & $FF
        ld      l,a
        ld      h,RESIDENT_TABLE_ADDR >> 8
        ld      a,(hl)
        out     ($FD),a                 ; storage segment at 4000h
        ex      de,hl
        pop     de
        ld      bc,BANK_HALF_SIZE
        ldir
        ex      de,hl                   ; HL = A000h after the low half, C000h after both
        pop     de
        push    de
        ld      a,e
        bit     6,h
        jr      z,.half
        pop     de
        ; Acknowledge the VDP interrupt that went pending during the copies,
        ; or a switch made from the interrupt routine nests the next one.
        in      a,($99)
.select:
        ld      a,(RESIDENT_PG0_ADDR)
        out     ($FD),a
        ld      a,(RESIDENT_PG1_ADDR)
        out     ($FE),a
        pop     hl                      ; L = F from the ld a,i snapshot
        bit     2,l                     ; P/V: JR has no P/O condition
        jr      z,.di
        ei
.di:    pop     ix
        pop     de
        pop     bc
        pop     af
        pop     hl
        ret
        DEPHASE
Ascii8HandlersEnd:
        ASSERT  Ascii8HandlersEnd-Ascii8HandlersSrc <= RESIDENT_8K_SIZE

; HYDLIDE3.ROM selects windows through one routine no LD (nn),A patch can
; reach; the server turns it into DI / CALL here.
; Entry: D = window 0-3, E = bank. Enters that window's handler with A =
; bank and HL restored. A and flags are not preserved.
Ascii8DispatchSrc:
        PHASE   RESIDENT_8K_DISPATCH_ADDR
        push    hl
        ld      a,d
        and     3
        ld      l,a
        add     a,a
        add     a,a
        add     a,l                     ; 5 x window
        add     a,RESIDENT_8K_BASE & $FF
        ld      l,a
        ld      h,RESIDENT_8K_BASE >> 8
        ld      a,e
        ex      (sp),hl                 ; restore HL, push the handler entry
        ret
        DEPHASE
Ascii8DispatchEnd:
        ASSERT  Ascii8DispatchEnd-Ascii8DispatchSrc <= 16

; ===========================================================================
; Game launch
; ===========================================================================
LaunchGame:
        ld      hl,MSG_STARTING
        call    PrintStr
        di
        ld      hl,TrampolineSrc
        ld      de,$C000
        ld      bc,TrampolineEnd-TrampolineSrc
        ldir
        jp      $C000

TrampolineSrc:
        PHASE   $C000
        ld      a,$C9                   ; disable the MSX-DOS timer hook
        ld      ($FD9F),a
        ld      a,(EXPTBL)              ; main BIOS slot into page 0
        and     3
        ld      c,a
        in      a,($A8)
        and     $FC
        or      c
        out     ($A8),a

        ; Give the game the hook table a cartridge sees: every RST 30h hook
        ; whose slot is neither the main BIOS (EXPTBL) nor the SUB-ROM
        ; (EXBRSA) becomes RET. MSX-DOS and MSXPi leave ~34 of them pointing
        ; into their ROMs - FROGGER stayed black, VALLEY stuck on its logo.
        ld      hl,$FD9A
.hook:  ld      a,(hl)
        cp      $F7
        jr      nz,.nextHook
        inc     hl
        ld      b,(hl)
        dec     hl
        ld      a,(EXPTBL)
        cp      b
        jr      z,.nextHook
        ld      a,($FAF8)               ; EXBRSA (0 on MSX1)
        cp      b
        jr      z,.nextHook
        ld      (hl),$C9
.nextHook:
        ld      de,5
        add     hl,de
        ld      a,h
        cp      $FF
        jr      nz,.hook
        ld      a,l
        cp      $CF                     ; up to and including EXTBIO
        jr      c,.hook

        ; SCREEN 1 / INIT32, as the BIOS does before a cartridge INIT. MSX-DOS
        ; "mode 80" left the MSX2 BIOS writing to VRAM page R#14=1.
        call    $006F

        ; Cartridges that only install H.STKE in INIT return; give them
        ; somewhere to return to (PENNANT, VALLEY2).
        ld      hl,.initDone
        push    hl
        ld      hl,($4002)              ; INIT
        jp      (hl)
.initDone:
        ; Start the game as the BIOS would, through the H.STKE hook it
        ; installed; its slot is the one already selected.
        di
        ld      a,($FEDA)
        cp      $F7
        jr      nz,.idle
        ld      hl,($FEDC)
        jp      (hl)
.idle:  ei                              ; nothing to start
        jr      .idle
        DEPHASE
TrampolineEnd:

; ===========================================================================
; Transfer progress bar on the cursor line:  [#####.......................]
; Drawn once through the BIOS; each fill cell is then written straight to
; VRAM, with no BIOS call in the transfer loop.
; ===========================================================================

; HL = blocks expected
ProgressStart:
        ld      a,h
        or      l
        jr      nz,.total
        inc     hl
.total: ld      (PROG_TOTAL),hl
        ld      hl,0
        ld      (PROG_DONE),hl
        xor     a
        ld      (PROG_CELLS),a
        ld      a,(LINLEN)
        cp      41
        ld      a,28
        jr      c,.width
        ld      a,60
.width: ld      (PROG_WIDTH),a
        ld      a,(CSRY)                ; 1-based
        dec     a
        ld      (PROG_ROW),a
        ld      a,'['
        call    PrintChar
        ld      a,(PROG_WIDTH)
        ld      b,a
.dots:  ld      a,'.'
        call    PrintChar
        djnz    .dots
        ld      a,']'
        call    PrintChar
        ld      a,(PROG_ROW)
        ld      e,a
        ld      d,0
        call    Locate
        ld      a,'['
        jp      PrintChar

; One more block received. Preserves nothing.
ProgressDot:
        ld      hl,(PROG_DONE)
        ld      de,(PROG_TOTAL)
        or      a
        sbc     hl,de
        jr      nc,.full
        ld      hl,(PROG_DONE)
        inc     hl
        ld      (PROG_DONE),hl
.full:
        ld      hl,(PROG_DONE)          ; cells = done * width / total
        ld      a,(PROG_WIDTH)
        ld      b,a
        ld      de,0
        ex      de,hl
.mul:   add     hl,de
        djnz    .mul
        ld      b,h
        ld      c,l
        ld      de,(PROG_TOTAL)
        call    Div16                   ; BC = cells
.fill:  ld      a,(PROG_CELLS)
        cp      c
        ret     nc
        inc     a
        ld      (PROG_CELLS),a
        push    bc
        call    ProgressPut
        pop     bc
        jr      .fill

; '#' at column A of the bar row, straight into VRAM.
ProgressPut:
        ld      e,a
        ld      d,0
        ld      a,(LINLEN)
        ld      c,a
        ld      b,0
        ld      hl,0
        ld      a,(PROG_ROW)            ; HL = row * width + column
.row:   or      a
        jr      z,.addr
        add     hl,bc
        dec     a
        jr      .row
.addr:  add     hl,de
        ld      a,i
        di
        push    af
        ld      a,l
        out     ($99),a
        ld      a,h
        and     $3F
        or      $40
        out     ($99),a
        ld      a,'#'
        out     ($98),a
        pop     af
        ret     po
        ei
        ret

; Cursor on the line below the bar, so later text does not overwrite it.
ProgressEnd:
        ld      a,(PROG_ROW)
        inc     a
        ld      e,a
        ld      d,0
        jp      Locate

; BC = BC / DE (HL = remainder)
Div16:
        ld      hl,0
        ld      a,16
.bit:   sla     c
        rl      b
        adc     hl,hl
        or      a
        sbc     hl,de
        jr      nc,.one
        add     hl,de
        jr      .next
.one:   inc     c
.next:  dec     a
        jr      nz,.bit
        ret

; ===========================================================================
; Screen / keyboard primitives
; ===========================================================================
PrintChar:
        ld      ix,B_CHPUT
        jr      BiosCall
WaitForKey:
        ld      ix,B_CHGET
        jr      BiosCall
Cls:
        xor     a                       ; BIOS CLS only clears with Z set
        ld      ix,B_CLS
        jr      BiosCall
; D = column, E = row, both 0-based
Locate:
        ld      h,d
        ld      l,e
        inc     h
        inc     l
        ld      ix,B_POSIT
; IX = BIOS routine. AF/BC/DE/HL pass through; IX/IY are destroyed. CALSLT
; leaves interrupts off, so they are turned back on here.
BiosCall:
        ld      iy,(EXPTBL-1)
        call    CALSLT
        ei
        ret

; HL = 0-terminated string; \n becomes CR+LF. Keeps DE/BC.
PrintStr:
        ld      a,(hl)
        or      a
        ret     z
        cp      10
        jr      nz,.char
        ld      a,13
        call    PrintChar
        ld      a,10
.char:  call    PrintChar
        inc     hl
        jr      PrintStr

; HL = 0-terminated text. The first character goes through the BIOS, which
; sets the VRAM address; the rest go straight to the VDP.
FastPrint:
        ld      a,(hl)
        or      a
        ret     z
        call    PrintChar
.out:   inc     hl
        ld      a,(hl)
        or      a
        ret     z
        out     ($98),a
        jr      .out

; HL = 0..65535 in decimal, no leading zeros.
PrintDec:
        ld      b,0                     ; B = 1 once a digit is printed
        ld      de,10000
        call    .digit
        ld      de,1000
        call    .digit
        ld      de,100
        call    .digit
        ld      de,10
        call    .digit
        ld      a,l
        jr      .print
.digit: ld      a,-1
.sub:   inc     a
        or      a
        sbc     hl,de
        jr      nc,.sub
        add     hl,de
        or      a
        jr      nz,.print
        cp      b
        ret     z                       ; leading zero
.print: ld      b,1
        add     a,'0'
        push    hl
        push    de
        push    bc
        call    PrintChar
        pop     bc
        pop     de
        pop     hl
        ret

; Carry if A is '0'..'9'.
IsDigit:
        cp      '0'
        ccf
        ret     nc
        cp      '9'+1
        ret

LowerChar:
        cp      'A'
        ret     c
        cp      'Z'+1
        ret     nc
        add     a,32
        ret

; Carry if the 0-terminated strings at HL and DE are equal.
StrEq:
        ld      a,(de)
        cp      (hl)
        jr      nz,.ne
        or      a
        jr      z,.eq
        inc     hl
        inc     de
        jr      StrEq
.eq:    scf
        ret
.ne:    or      a
        ret

; Carry if the text at HL starts with the 0-terminated prefix at DE.
StartsWith:
        ld      a,(de)
        or      a
        scf
        ret     z
        cp      (hl)
        jr      nz,.no
        inc     hl
        inc     de
        jr      StartsWith
.no:    or      a
        ret

; Carry if HL is one of the errors msxpi-server replies with.
IsArchiveError:
        push    hl
        ld      de,STR_PI_ERROR
        call    StartsWith
        pop     hl
        ret     c
        ld      de,STR_FAILED_LIST
        push    hl
        call    StartsWith
        pop     hl
        ret

; HL = message
ShowArchiveError:
        push    hl
        call    Cls
        ld      hl,MSG_ARCH_ERROR_HDR
        call    PrintStr
        pop     hl
        push    hl
        ld      de,STR_PI_ERROR
        call    StartsWith              ; HL now past the prefix
        pop     de
        jr      c,.print
        ex      de,hl
        push    hl
        ld      de,STR_FAILED_LIST
        call    StartsWith
        pop     hl
        jr      nc,.print
        ld      hl,MSG_CANNOT_OPEN
.print: call    PrintStr
        ld      hl,MSG_PRESS_KEY
        call    PrintStr
        call    WaitForKey
        jp      Cls

; ---------------------------------------------------------------------------
; Menu of repositories. Returns HL = the chosen item, or "Q" when out of
; range.
; ---------------------------------------------------------------------------
ShowMenu:
        ld      hl,MSG_MENU_HDR
        call    PrintStr
        ld      hl,ITEMS
        ld      bc,(MENU_COUNT)         ; C = count
        ld      b,0
.item:  inc     b
        push    bc
        push    hl
        ld      l,b
        ld      h,0
        call    PrintDec
        ld      hl,MSG_DOT_SPACE
        call    PrintStr
        pop     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    hl
        ex      de,hl
        call    PrintStr
        ld      hl,MSG_NL
        call    PrintStr
        pop     hl
        pop     bc
        ld      a,b
        cp      c
        jr      c,.item

        call    WaitForKey
        push    af
        call    PrintChar
        ld      hl,MSG_NL
        call    PrintStr
        pop     af
        sub     '1'                     ; 0-based choice
        ld      hl,MENU_COUNT
        cp      (hl)
        jr      c,.valid                ; unsigned: also rejects < '1'
        ld      hl,MSG_OUT_OF_RANGE
        call    PrintStr
        ld      hl,STR_Q
        ret
.valid: add     a,a
        ld      e,a
        ld      d,0
        ld      hl,ITEMS
        add     hl,de
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ret

; ---------------------------------------------------------------------------
; Keys on the list page. Returns A = INPUT_*; for INPUT_NUMBER the digits
; are in OUT_NUMBER. Only Enter ends a number, Backspace erases a digit and
; anything else is ignored.
; ---------------------------------------------------------------------------
GetValidInput:
        call    WaitForKey
        push    af
        ld      de,0
        call    Locate
        pop     af
        cp      'a'
        jr      c,.upper
        sub     32                      ; p/n/q -> P/N/Q (other lower case is ignored anyway)
.upper: ld      b,INPUT_P
        cp      'P'
        jr      z,.ret
        ld      b,INPUT_N
        cp      'N'
        jr      z,.ret
        ld      b,INPUT_Q
        cp      'Q'
        jr      z,.ret
        ld      b,INPUT_UP
        cp      KEY_UP
        jr      z,.ret
        ld      b,INPUT_DOWN
        cp      KEY_DOWN
        jr      z,.ret
        call    IsDigit
        jr      nc,GetValidInput
        ld      hl,OUT_NUMBER
        ld      c,0                     ; digits typed
.key:   call    IsDigit
        jr      nc,.notDigit
        ld      e,a
        ld      a,c
        cp      3
        jr      nc,.next                ; three digits at most
        ld      a,e
        ld      (hl),a
        inc     hl
        inc     c
        call    PrintChar
        jr      .next
.notDigit:
        cp      KEY_BACKSPACE
        jr      nz,.enter
        ld      a,c
        or      a
        jr      z,.next
        dec     c
        dec     hl
        ld      a,KEY_BACKSPACE
        call    PrintChar
        ld      a,' '
        call    PrintChar
        ld      a,KEY_BACKSPACE
        call    PrintChar
        jr      .next
.enter: cp      KEY_ENTER
        jr      nz,.next
        ld      a,c
        or      a
        jr      nz,.done                ; never send an empty number
.next:  call    WaitForKey
        jr      .key
.done:  ld      (hl),0
        ld      b,INPUT_NUMBER
.ret:   ld      a,b
        ret

; ===========================================================================
; MSXARCH.INI: one repository URL per line; ';' and '#' lines are comments.
; It may also hold settings, name=value, which are not repositories:
;     rebootAfterRomLoad=yes   ask the Pi to shut down once a game is loaded
; ===========================================================================
LoadRepositoryList:
        ld      hl,INI_FCB
        ld      b,37
        xor     a
.zero:  ld      (hl),a
        inc     hl
        djnz    .zero
        ld      hl,INI_NAME
        ld      de,INI_FCB+1
        ld      bc,11
        ldir
        ld      de,INI_FCB
        ld      c,F_OPEN
        call    BDOS
        or      a
        ret     nz                      ; no file: no repositories
        ld      hl,XFERBUF
.record:
        push    hl
        ex      de,hl
        ld      c,F_DTAOFF
        call    BDOS
        ld      de,INI_FCB
        ld      c,F_READSEQ
        call    BDOS
        pop     hl
        ld      de,128
        add     hl,de
        or      a
        jr      nz,.read                ; EOF or a partial last record
        ld      a,h
        cp      (XFERBUF+INI_BUFFER_SIZE)>>8
        jr      c,.record
.read:
        ld      de,INI_FCB
        ld      c,F_CLOSE
        call    BDOS
        ld      hl,(INI_FCB+16)         ; file size; 1023 bytes at most
        ld      a,(INI_FCB+18)
        ld      de,INI_BUFFER_SIZE-1
        or      a
        jr      nz,.cap
        sbc     hl,de
        add     hl,de
        jr      c,.sized
.cap:   ex      de,hl
.sized: ld      de,XFERBUF
        add     hl,de
        ld      (hl),0

        ld      hl,XFERBUF
        ld      de,REPO_LIST            ; DE = current entry
        ld      c,0                     ; C = column
.char:  ld      a,(hl)
        inc     hl
        or      a
        jr      z,.last
        cp      $1A
        jr      z,.last
        cp      13
        jr      z,.char
        cp      10
        jr      z,.line
        ld      b,a
        ld      a,c
        cp      MAX_URL_LEN-1
        jr      nc,.char                ; entry full, drop the rest
        ld      a,b
        ld      (de),a
        inc     de
        inc     c
        jr      .char
.last:  ld      a,1
        ld      (INI_END),a
.line:
        xor     a
        ld      (de),a
        push    hl                      ; source position
        ex      de,hl
        ld      b,0
        sbc     hl,bc                   ; HL = start of this entry (CF=0 from xor)
        push    hl
        ld      de,STR_REBOOT_SETTING
        call    IniSetting
        jr      nc,.notSetting
        call    IniYes
        ld      (REBOOT_AFTER_ROM_LOAD),a
        pop     de                      ; reuse the entry
        jr      .next
.notSetting:
        pop     de
        ld      a,c
        or      a
        jr      z,.next                 ; blank line
        ld      a,(de)
        cp      ';'
        jr      z,.next
        cp      '#'
        jr      z,.next
        ld      hl,MAX_URL_LEN
        add     hl,de
        ex      de,hl
        ld      a,(REPO_COUNT)
        inc     a
        ld      (REPO_COUNT),a
        cp      MAX_REPOS
        jr      nc,.full
.next:  pop     hl
        ld      c,0
        ld      a,(INI_END)
        or      a
        jr      z,.char
        ret
.full:  pop     hl
        ret

; HL = line, DE = lower-case name. Carry and HL = the value if the line is
; "name=value" (name case-insensitive, spaces allowed around '=').
IniSetting:
        ld      a,(de)
        or      a
        jr      z,.spaces
        ld      a,(hl)
        call    LowerChar
        ex      de,hl
        cp      (hl)
        ex      de,hl
        jr      nz,.no
        inc     hl
        inc     de
        jr      IniSetting
.spaces:
        ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,.spaces
        cp      '='
        jr      nz,.no
.value: ld      a,(hl)
        cp      ' '
        scf
        ret     nz
        inc     hl
        jr      .value
.no:    or      a
        ret

; A = 1 if HL is "yes" (any case) followed by the end, a space or a tab.
IniYes:
        ld      de,STR_YES
.cmp:   ld      a,(de)
        or      a
        jr      z,.end
        ld      a,(hl)
        call    LowerChar
        ex      de,hl
        cp      (hl)
        ex      de,hl
        jr      nz,.no
        inc     hl
        inc     de
        jr      .cmp
.end:   ld      a,(hl)
        or      a
        jr      z,.yes
        cp      ' '
        jr      z,.yes
        cp      9
        jr      nz,.no
.yes:   ld      a,1
        ret
.no:    xor     a
        ret

; ===========================================================================
; Protocol layer (asm-common)
; ===========================================================================
        INCLUDE "include.asm"
        INCLUDE "putchar_clients.asm"
        INCLUDE "msxpi_bios.asm"

; ===========================================================================
; Strings
; ===========================================================================
INI_NAME:           db  "MSXARCH INI"
STR_REBOOT_SETTING: db  "rebootafterromload",0
STR_YES:            db  "yes",0
STR_PI_ERROR:       db  "Pi:Error - ",0
STR_FAILED_LIST:    db  "Failed to list directory:",0
STR_Q:              db  "Q",0
EXIT_STR:           db  "Exit",0
CMD_MSXARCHIVE:     db  "msxarchive",0
CMD_N:              db  "N",0
CMD_P:              db  "P",0
CMD_SHUTDOWN:       db  "shut nowait",0

MSG_MENU_HDR:       db  "=== MENU ===\n!! msxarch loader !!\n\n",0
MSG_DOT_SPACE:      db  ". ",0
MSG_NL:             db  "\n",0
MSG_OUT_OF_RANGE:   db  "Choice out of range.\n",0
MSG_SELECTED:       db  "You selected: ",0
MSG_CONNECTING:     db  "\nConnecting...\n",0
MSG_EXIT_SELECTED:  db  "Exit selected.\n",0
MSG_SEND_ERR:       db  "Error sending command to MSXPi!\n",0
MSG_SENDING_PARMS:  db  "Sending parameters: ",0
MSG_LIST_UNREADABLE: db "Unable to read the archive list.",0
MSG_LIST_KEYS:      db  "     Q = Quit  N/Down = Next Page  P/Up = Previous Page or Game Number to load",0
MSG_HDR_ERR:        db  "Error reading ROM header\n",0
MSG_CHOOSE_ANOTHER: db  "\n\nPress any key to choose another game\n",0
MSG_LOADING:        db  "Loading ",0
MSG_OPEN_PAREN:     db  "  (",0
MSG_KB:             db  "K)\n",0
MSG_PLAIN_TOO_LARGE: db "ROM too large for plain loading\n",0
MSG_MAPPER_UNSUPPORTED: db "Mapper type not yet supported: ",0
MSG_LOAD_ERR:       db  "Error loading the rom: ",0
MSG_GAME_LOADED:    db  "Game loaded\n",0
MSG_STARTING:       db  "Starting game...\n",0
MSG_NOT_ENOUGH:     db  "Not enough mapper segments: have ",0
MSG_NEED:           db  ", need ",0
MSG_TOO_LARGE:      db  "Too large: ",0
MSG_SEG:            db  " seg\n",0
MSG_BANKS_ERR:      db  "Error loading ROM banks\n",0
MSG_CACHE:          db  "Cache...\n",0
MSG_ARCH_ERROR_HDR: db  "MSX Archive error\n=================\n\n",0
MSG_CANNOT_OPEN:    db  "Cannot open archive directory.\nFile or directory does not exist.",0
MSG_PRESS_KEY:      db  "\n\nPress any key to return to the URL list.",0

DEFAULT_URL:
        db      "https://web.archive.org/web/20241204120811/https://www.msxarchive.nl/pub/msx/games/roms/msx1",0
DEFAULT_URL_LEN:    EQU $-DEFAULT_URL

RepoEntryTable:
        dw      REPO_LIST+0*MAX_URL_LEN, REPO_LIST+1*MAX_URL_LEN
        dw      REPO_LIST+2*MAX_URL_LEN, REPO_LIST+3*MAX_URL_LEN
        dw      REPO_LIST+4*MAX_URL_LEN, REPO_LIST+5*MAX_URL_LEN
        dw      REPO_LIST+6*MAX_URL_LEN, REPO_LIST+7*MAX_URL_LEN

; ===========================================================================
; Variables that need an initial value
; ===========================================================================
REPO_COUNT:             db  0
REBOOT_AFTER_ROM_LOAD:  db  0
INI_END:                db  0

IMAGE_END:
; ===========================================================================
; Work RAM past the end of the image (not in the .com file)
; ===========================================================================
MENU_COUNT:     EQU IMAGE_END           ; 1
PARAMS:         EQU MENU_COUNT+1        ; 2
PAGE_OFFSET:    EQU PARAMS+2            ; 2, signed
REPLAY:         EQU PAGE_OFFSET+2       ; 2, signed
RETURN_TO_MENU: EQU REPLAY+2            ; 1
REOPEN:         EQU RETURN_TO_MENU+1    ; 1
STORAGE_COUNT:  EQU REOPEN+1            ; 1
STORAGE_COUNT16: EQU STORAGE_COUNT+1    ; 2
CHUNKS:         EQU STORAGE_COUNT16+2   ; 2
CHUNK:          EQU CHUNKS+2            ; 2
SETUP_BANKS:    EQU CHUNK+2             ; 1
SRC_PAGE:       EQU SETUP_BANKS+1       ; 1
TGT_PAGE:       EQU SRC_PAGE+1          ; 1
PW_ENTRY:       EQU TGT_PAGE+1          ; 1
PW_BANK:        EQU PW_ENTRY+1          ; 1
PW_SEG:         EQU PW_BANK+1           ; 1
DMS_SAVED:      EQU PW_SEG+1            ; 1
DMS_KEEP0:      EQU DMS_SAVED+1         ; 1
PROG_TOTAL:     EQU DMS_KEEP0+1         ; 2
PROG_DONE:      EQU PROG_TOTAL+2        ; 2
PROG_WIDTH:     EQU PROG_DONE+2         ; 1
PROG_CELLS:     EQU PROG_WIDTH+1        ; 1
PROG_ROW:       EQU PROG_CELLS+1        ; 1
OUT_NUMBER:     EQU PROG_ROW+1          ; 4
SELBUF:         EQU OUT_NUMBER+4        ; 3 + 10 x 5 + 1
ITEMS:          EQU SELBUF+64           ; (MAX_REPOS + 1) x 2
INI_FCB:        EQU ITEMS+2*(MAX_REPOS+1) ; 37
HDRBUF:         EQU INI_FCB+37          ; ROM_MSG_MAX + 1
HDR_MAPPER:     EQU HDRBUF+2
HDR_BANKKB:     EQU HDRBUF+3
HDR_BANKCOUNT:  EQU HDRBUF+4
HDR_TOTAL:      EQU HDRBUF+6
HDR_REASON:     EQU HDRBUF+ROM_HEADER_SIZE
REPO_LIST:      EQU HDRBUF+ROM_MSG_MAX+1 ; MAX_REPOS x MAX_URL_LEN
WORK_END:       EQU REPO_LIST+MAX_REPOS*MAX_URL_LEN

        ASSERT  WORK_END <= $4000       ; pages 1 and 2 are switched while loading
