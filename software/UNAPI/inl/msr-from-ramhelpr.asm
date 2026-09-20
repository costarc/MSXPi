;--- MSX-UNAPI standalone RAM helper/mapper support routines installer
;    By Konamiman
;
;    See USAGE_S for usage instructions.
;
;    You can compile it with Nestor80 (https://github.com/Konamiman/Nestor80):
;
;    N80 ramhelpr.asm ramhelpr.com --define-symbols INSTALL_MSR=0
;    N80 ramhelpr.asm msr.com --define-symbols INSTALL_MSR=1
;
;    Use INSTALL_MSR=1 to build an installer for the DOS 2 mapper support routines and the UNAPI RAM helper,
;    In that case the installer will fail if these routines are already present.
;
;    Use INSTALL_MSR=0 to build an installer for the UNAPI RAM helper only.
;
;    The resulting file is a MSX-DOS .COM program that installs the routines or the helper.
;
;    Optional improvements (up to you):
;
;    - Add code for uninstallation.
;
;    * Version 1.1 copies the contents of the SHELL environment item
;      to the PROGRAM environment item.
;      This is needed because the SHELL item value becomes RAMHELPR.COM,
;      and this leads to "Wrong version of COMMAND" errors.
;
;    * Version 1.2:
;      - Doesn't read from the mapped RAM ports anymore.
;      - The routine to read a byte from a slot+segment doesn't corrupt BC, DE and HL,
;        being then compliant with the UNAPI specification.
;      - Installs also the DOS 2 mapper support routines if compiled with INSTALL_MSR=1
;
; NOTE: MSR = Standard mapper support routines,
;             as defined in MSX-DOS 2 Program Interface Specification


;*******************
;***  CONSTANTS  ***
;*******************

INSTALL_MSR: equ 1      ; patched: sjasm has no -D, and .fatal/.print1 are N80-only


;--- System variables and routines

_TERM0: equ     00h
_STROUT: equ    09h
_GENV:  equ     6Bh
_SENV:  equ     6Ch

ENDTPA: equ     0006h
RDSLT:  equ     000Ch
CALSLT: equ     001Ch
ENASLT: equ     0024h
RAMSLOT0: equ   0F341h
RAMSLOT1: equ   0F342h
RAMSLOT3: equ   0F344h
HIMSAV: equ     0F349h
EXPTBL: equ     0FCC1h
EXTBIO: equ     0FFCAh


;*****************************
;***  INITIALIZATION CODE  ***
;*****************************

        org     100h

        ;--- Show welcome message

        ld      de,WELCOME_S
        ld      c,_STROUT
        call    5

        ;--- Copy SHELL environment item to PROGRAM
        ;    (in DOS 2 only, nothing happens in DOS 1)

        ld      hl,SHELL_S
        ld      de,8000h
        ld      b,255
        ld      c,_GENV
        call    5

        ld      hl,PROGRAM_S
        ld      de,8000h
        ld      c,_SENV
        call    5

        ;--- Put a 0 at the end of the command line
        ;    (needed when running DOS 1)

        ld      hl,(0080h)
        ld      h,0
        ld      bc,0081h
        add     hl,bc
        ld      (hl),0

        ;--- Search the parameter

        ld      hl,80h
SRCHPAR:
        inc     hl
        ld      a,(hl)
        cp      " "
        jr      z,SRCHPAR
        or      a
        jr      z,SHOWINFO

        or      32

        if      INSTALL_MSR
        cp      "c"
        jp      z,DO_CLEANUP
        endif

        cp      "f"
        jr      z,PARAM_OK
        cp      "i"
        jr      nz,SHOWINFO

        ;Parameter is "i": check if already installed

        push    hl
        ld      a,0FFh
        ld      de,2222h
        ld      hl,0
        call    EXTBIO
        ld      a,h
        or      l
        pop     hl
        jr      z,PARAM_OK

        ld      de,RH_ALINST_S
        ld      c,_STROUT
        call    5
        ld      c,_TERM0
        jp      5

        ;--- No parameters or invalid parameter:
        ;    show usage information and terminate

SHOWINFO:
        ld      de,USAGE_S
        ld      c,_STROUT
        call    5
        ld      c,_TERM0
        jp      5

        ;--- Parameters OK: Do install

PARAM_OK:
        inc     hl
NEXT_PARAM:
        ld      a,(hl)
        or      a
        jr      z,DO_INSTALL
        cp      " "
        jr      nz,DO_INSTALL
        inc     hl
        jr      NEXT_PARAM

DO_INSTALL:
        ld      (CMDLINE_PNT),hl

        if      INSTALL_MSR

        xor     a       ;Get mapper support routines
        ld      de,0402h
        call    EXTBIO
        or      a
        jp      z,INST_HELPER
    
        ld      de,MSR_ALINST_S
        ld      c,_STROUT
        call    5
        ld      c,_TERM0
        jp      5


;************************************
;***  CLEANUP USER MODE SEGMENTS  ***
;************************************

DO_CLEANUP:
        xor     a
        ld      de,0402h
        call    EXTBIO

        or      a
        ld      de,NOMSR_S
        jp      z,PRINT_END

        inc     hl
        inc     hl
        inc     hl      ;Point HL to FREE_SEG
        ld      a,0FFh
        ld      b,00Fh
        ld      de,DO_CLEANUP_NEXT
        push    de
        jp      (hl)
DO_CLEANUP_NEXT:

        ld      de,NOMYMSR_S
        jp      c,PRINT_END

        ld      a,b
        or      c
        ld      de,IHAVENTFREED_S
        jp      z,PRINT_END

        push    bc
        ld      de,IHAVEFREED_S
        ld      c,_STROUT
        call    5
        pop     hl
        ld      de,FREEDSEGCOUNT_S
        push    de
        call    NUMTOASC
        pop     de
        ld      c,_STROUT
        call    5
        ld      de,USERSEGMENTS_S

PRINT_END:
        ld      c,_STROUT
        call    5
        ld      c,_TERM0
        jp      5

NOMSR_S:
        db      "*** No mapper support routines are installed.",13,10,"$"

NOMYMSR_S:
        db      "*** I haven't installed the mapper support routines myself,",13,10
        db      "    therefore I can't free user segments.",13,10,"$"

IHAVENTFREED_S:
        db      "I haven't found any segment allocated in user mode.",13,10,"$"

IHAVEFREED_S:
        db      "I have freed $"

USERSEGMENTS_S:
        db      " segments allocated in user mode.",13,10,"$"

FREEDSEGCOUNT_S:
        ds      6

        endif


;******************************************
;***  MSR+RAM HELPER INSTALLATION CODE  ***
;******************************************

INST_HELPER:
        ;--- Check that TPA end address is at least 0C2000h

        ld      a,(ENDTPA+1)
        cp      0C2h
        jr      nc,OK_TPA

        ld      de,NOTPA_S
        ld      c,_STROUT
        call    5
        ld      c,_TERM0
        jp      5
OK_TPA:

        if INSTALL_MSR

        ;--- If TPA is spread across multiple slots, unify them

        ld      a,(RAMSLOT0)
        ld      hl,RAMSLOT3
        cp      (hl)
        jr      z,OKTPASLOTS

        di

        ld      a,(RAMSLOT3)
        ld      h,40h
        call    ENASLT
        ld      a,3
        out     (0FDh),a

        ld      hl,0
        ld      de,4000h
        ld      bc,4000h
        ldir

        ld      a,2
        out     (0FDh),a

        ld      h,0
        ld      a,(RAMSLOT3)
        call    ENASLT

        ld      a,(RAMSLOT3)
        ld      (RAMSLOT0),a
        ld      (RAMSLOT1),a

        ei

        ld      de,IHAVESETSLOTS_S
        ld      c,_STROUT
        call    5
OKTPASLOTS:

        endif

        ;--- Prepare the two copies of the page 3 code

        ;>>> Get a copy of old EXTBIO hook

        ld      hl,EXTBIO
        ld      de,HOLDEXT__1
        ld      bc,5
        ldir
        ld      hl,EXTBIO
        ld      de,HOLDEXT__2
        ld      bc,5
        ldir

        ;>>> Build the mappers table

        if      INSTALL_MSR = 0

        xor     a       ;Get mappers table
        ld      de,0401h
        call    EXTBIO

        or      a
        jp      nz,BUILDP3_DOS2

        endif

        ;>>> Build the mappers table when no MSR are present:
        ;    - If we are going to install MSR, build a MSR compatible
        ;      table where each entry is 8 bytes long.
        ;    - If not, build a reduced table where each entry is 2 bytes long.

BUILDP3_DOS1:
        ld      ix,MAPTAB__1
        ld      iy,MAPTAB__2

        ;Setup mappers entry for the primary mapper

        if      INSTALL_MSR
        ld      a,8
        else
        ld      a,2
        endif
        ld      (MAPTAB_SIZE),a

        ld      a,(RAMSLOT3)
        ld      h,40h
        call    ENASLT
        ld      de,3000h
        call    MEMTEST1
        cp      5
        jr      nc,OK_PRIMAP

        ld      a,(RAMSLOT1)
        ld      h,40h
        call    ENASLT
        ld      de,NOMAPPER_S
        ld      c,_STROUT
        call    5
        ld      c,_TERM0
        jp      5
OK_PRIMAP:

        if      INSTALL_MSR

        ld      ix,MAPTAB__1+8
        ld      iy,MAPTAB__2+8
        ld      (ix-7),a    ;Total segments
        ld      (iy-7),a
        sub     5
        ld      (ix-6),a    ;Free segments
        ld      (iy-6),a
        ld      a,5
        ld      (ix-5),a    ;Segments allocated for system: our own code + TPA
        ld      (iy-5),a
        xor     a
        ld      (ix-4),a    ;Segments allocated for user
        ld      (iy-4),a
        ld      (ix-3),a    ;Unused
        ld      (iy-3),a
        ld      (ix-2),a    ;Unused
        ld      (iy-2),a
        ld      (ix-1),a    ;Unused
        ld      (iy-1),a
        ld      a,(RAMSLOT3)
        ld      (ix-8),a
        ld      (iy-8),a

        else

        ld      ix,MAPTAB__1+2
        ld      iy,MAPTAB__2+2
        dec     a
        ld      (ix-1),a
        ld      (iy-1),a
        ld      a,(RAMSLOT3)
        ld      (ix-2),a
        ld      (iy-2),a

        endif

        ;Setup mappers entry for other mappers, if any

        ld      b,3
BUILDP3_DOS1_L:
        push    bc
        call    NEXTSLOT
        pop     bc
        cp      0FFh
        jp      z,END_BUILD_MAPTAB      ;No more mappers

        push    ix
        push    iy
        ld      hl,RAMSLOT3
        cp      (hl)
        jr      z,BUILDP3_DOS1_N

        ld      c,a
        push    bc
        ld      h,40h
        call    ENASLT
        ld      de,3000h
        call    MEMTEST1
        pop     bc
        cp      2
        jr      c,BUILDP3_DOS1_N
        if      INSTALL_MSR = 0   ;For MSR it's "segments count", for RH it's "number of last segment"
        dec     a
        endif

        pop     iy
        pop     ix
        ld      (ix),c
        ld      (iy),c
        ld      (ix+1),a
        ld      (iy+1),a

        if      INSTALL_MSR

        ld      (ix+2),a    ;Free segments
        ld      (iy+2),a
        xor     a
        ld      (ix+3),a    ;Segments allocated to system
        ld      (iy+3),a
        ld      (ix+4),a    ;Segments allocated to system
        ld      (iy+4),a
        ld      (ix+5),a    ;Unused
        ld      (iy+5),a
        ld      (ix+6),a
        ld      (iy+6),a
        ld      (ix+7),a
        ld      (iy+7),a

        push    bc
        ld      bc,8
        add     ix,bc
        add     iy,bc
        ld      a,(MAPTAB_SIZE)
        ld      b,8
        add     a,b
        ld      (MAPTAB_SIZE),a
        pop     bc

        else

        inc     ix
        inc     ix
        inc     iy
        inc     iy
    
        ld      hl,MAPTAB_SIZE
        inc     (hl)
        inc     (hl)

        endif

        djnz    BUILDP3_DOS1_L

END_BUILD_MAPTAB:
        ld      (ix),0      ;End of the table
        ld      (iy),0
        ld      hl,MAPTAB_SIZE
        inc     (hl)
        jr      END_BUILDP3

BUILDP3_DOS1_N:
        pop     iy
        pop     ix
        jp      BUILDP3_DOS1_L

        if      INSTALL_MSR = 0

        ;>>> Build the mappers table when MSR are already present

BUILDP3_DOS2:
        ld      (_CALLRAM_MAPTAB__1+1),hl
        ld      (_CALLRAM_MAPTAB__2+1),hl
        ld      a,7     ;Opcode for RLCA
        ld      (_CALLRAM_RLCAS__1),a
        ld      (_CALLRAM_RLCAS__1+1),a
        ld      (_CALLRAM_RLCAS__2),a
        ld      (_CALLRAM_RLCAS__2+1),a

        xor     a       ;Get mapper support routines
        ld      de,0402h
        call    EXTBIO
        ld      bc,1Eh
        add     hl,bc
        push    hl
        ld      de,PUT_P1__1
        ld      bc,6
        ldir
        pop     hl
        ld      de,PUT_P1__2
        ld      bc,6
        ldir

        ld      hl,0
        ld      (LDBC__1+1),hl
        ld      (LDBC__2+1),hl

        endif

END_BUILDP3:

        if      INSTALL_MSR

        ld      hl,0            ;We don't provide reduced mappers table,
        ld      (LDBC__1+1),hl  ;we've generated a standard table
        ld      (LDBC__2+1),hl

        endif

        ;--- Calculate final size of page 3 area

        ld      bc,(MAPTAB_SIZE)
        ld      b,0
        ld      hl,P3_CODE_END__1-P3_CODE__1
        add     hl,bc
        ld      (0B002h),hl

        ;--- Allocate space on system work area on page 3

        ld      hl,(HIMSAV)
        ld      bc,(0B002h)
        or      a
        sbc     hl,bc
        ld      (HIMSAV),hl

        ld      a,(RAMSLOT1)
        ld      h,40h
        call    ENASLT

        ;--- Generate the page 3 code for the appropriate address,
        ;    but generate it at 0B004h temporarily
        ;    (we cannot use the allocated page 3 space yet)

        ld      hl,P3_CODE__1
        ld      de,P3_CODE__2
        ld      ix,(HIMSAV)
        ld      iy,0B004h
        ld      bc,(0B002h)
        call    REALLOC

        ld      hl,(HIMSAV)
        ld      (0B000h),hl

        ;--- Install code in segment

        if      INSTALL_MSR

        ld      a,(MAPTAB__1)
        ld      h,40h
        call    ENASLT
        ld      a,(MAPTAB__1+1)
        dec     a
        out     (0FDh),a

        ld      hl,SEGMENT_CODE
        ld      de,4000h
        ld      bc,SEGMENT_CODE_END-SEGMENT_CODE_START
        ldir

        ;>>> Initialize the segments usage table, marking non-existing segments

        ld      hl,SEG_USE_TABLE
        ld      de,SEG_USE_TABLE+1
        ld      bc,256*4-1
        ld      (hl),0
        ldir

        ld      ix,MAPTAB__1
        ld      hl,SEG_USE_TABLE+255
INI_SEG_TABLE_LOOP:
        ld      a,(ix)
        or      a
        jr      z,INI_SEG_TABLE_END

        push    ix
        push    hl

        ld      c,(ix+1)  ;Segments count
        ld      b,0
        ld      hl,256
        or      a
        sbc     hl,bc
        ld      b,l     ;Number of non-existing segments
        ld      a,0FFh
        pop     hl
        push    hl
MARK_NON_EX_LOOP:
        ld      (hl),a
        dec     hl
        djnz    MARK_NON_EX_LOOP

        pop     hl
        pop     ix

        inc     h   ;Next entry in SEG_USE_TABLE
        ld      bc,8
        add     ix,bc
        jr      INI_SEG_TABLE_LOOP

        ;>>> Also mark TPA segments and our own segment as system

INI_SEG_TABLE_END:
        ld      ix,SEG_USE_TABLE
        ld      a,2
        ld      (ix),a
        ld      (ix+1),a
        ld      (ix+2),a
        ld      (ix+3),a
        ld      bc,(MAPTAB__1+1)
        dec     c
        ld      b,0
        add     ix,bc
        ld      (ix),a

        ld      a,2
        out     (0FDh),a
        ld      a,(0F342h)
        ld      h,40h
        call    ENASLT

        endif

        ;--- All done, now we need to jump to BASIC and do _SYSTEM

        ld      de,OK_S
        ld      c,_STROUT
        call    5

        ld      ix,ComLine+2

        ld      hl,(CMDLINE_PNT)    ;No commands to copy?
        ld      a,(hl)
        or      a
        jr      z,OKBSC

        ld      a,(0F313h)       ;DOS 1 and there are commands to copy:
        or      a                ;print warning and ignore them
        jr      nz,DO_GET_CMD
        
        ld      de,CMDWARNING_S
        ld      c,_STROUT
        call    5
        jr      OKBSC

DO_GET_CMD:
        ld      (ix-2),"("
        ld      (ix-1),34
        ld      a,(hl)

BUCSYS2:
        ld      (ix),a  ;Copy characters until finding 0
        inc     ix
        inc     hl
        ld      a,(hl)
        cp      "&"
        jr      nz,NOAMP
        ld      a,"^"
NOAMP:  or      a
        jr      nz,BUCSYS2

        ld      (ix),34
        ld      (ix+1),")"
        ld      (ix+2),0
OKBSC:

        ld      hl,SystemProg
        ld      de,08000h
        ld      bc,0400h
        ldir
        jp      08000h

SystemProg:
        ld      a,(0FCC1h)
        push    af
        ld      h,0
        call    024h
        pop     af
        ld      h,040h
        call    024h
        xor     a
        ld      hl,0F41Fh
        ld      (0F860h),hl
        ld      hl,0F423h
        ld      (0F41Fh),hl
        ld      (hl),a
        ld      hl,0F52Ch
        ld      (0F421h),hl
        ld      (hl),a
        ld      hl,0F42Ch
        ld      (0F862h),hl
        ld      hl,8030h
        jp      04601h

        ;The following is copied to address 8030h

SysTxT2:
        db      3Ah     ;:
        db      97h,0DDh,0EFh     ;DEF USR =
        db      0Ch
SigueDir:
        dw      UsrCode-SystemProg+8000h        ;Address of "UsrCode"
        db      3Ah,91h,0DDh,"(",34,34,")"       ;:? USR("")
        db      03Ah,0CAh       ;:CALL
        db      "SYSTEM"
ComLine:
        db      0
        ds      128     ;Space for extra commands

        ;>>> This is the code that will be executed by the USR instruction

UsrCode:

        ;--- Copy page 3 code to its definitive address

        ld      hl,0B004h
        ld      de,(0B000h)
        ld      bc,(0B002h)
        ldir

        ;--- Setup new EXTBIO hook

        di
        ld      a,0C3h
        ld      (EXTBIO),a
        ld      hl,(0B000h)
        ld      bc,NEWEXT__1-P3_CODE__1
        add     hl,bc
        ld      (EXTBIO+1),hl
        ei

        ret


;--- This routine reallocates a piece of code
;    based on two different copies assembled in different locations.
;    Input: HL = Address of first copy
;           DE = Address of second copy
;           IX = Target reallocation address
;           IY = Address where the patched code will be placed
;           BC = Length of code

REALLOC:
        push    iy
        push    bc
        push    de
        push    hl      ;First copy code "as is"
        push    iy      ;(HL to IY, length BC)
        pop     de
        ldir
        pop     hl
        pop     de

        push    de
        pop     iy      ;IY = Second copy
        ld      b,h
        ld      c,l
        push    ix
        pop     hl
        or      a
        sbc     hl,bc
        ld      b,h
        ld      c,l     ;BC = Distance to sum (IX - HL)

        exx
        pop     bc
        exx
        pop     ix      ;Originally IY

        ;At this point: IX = Destination
        ;               IY = Second copy
        ;               BC = Distance to sum (new dir - 1st copy)
        ;               BC'= Length

REALOOP:
        ld      a,(ix)
        cp      (iy)
        jr      z,NEXT  ;If no differences, go to next byte

        ld      l,a
        ld      h,(ix+1)        ;HL = Data to be changed
        add     hl,bc   ;HL = Data changed
        ld      (ix),l  ;IX = Address of the data to be changed
        ld      (ix+1),h

        call    CHKCOMP
        jr      z,ENDREALL

        inc     ix
        inc     iy
NEXT:   inc     ix      ;Next byte to compare
        inc     iy      ;(if we have done substitution, we need to increase twice)
        call    CHKCOMP
        jr      nz,REALOOP

ENDREALL:
        ret

CHKCOMP:
        exx
        dec     bc      ;Decrease counter, if it reaches 0,
        ld      a,b     ;return with Z=1
        or      c
        exx
        ret


;--- NEXTSLOT:
;    Returns in A the next slot available on the system every time it is called.
;    When no more slots are available it returns 0FFh.
;    To initialize it, 0FFh must be written in NEXTSL.
;    Modifies: AF, BC, HL

NEXTSLOT:
        ld      a,(NEXTSL)
        cp      0FFh
        jr      nz,NXTSL1
        ld      a,(EXPTBL)      ;First slot
        and     10000000b
        ld      (NEXTSL),a
        ret

NXTSL1:
        ld      a,(NEXTSL)
        cp      10001111b
        jr      z,NOMORESLT     ;No more slots?
        cp      00000011b
        jr      z,NOMORESLT
        bit     7,a
        jr      nz,SLTEXP

SLTSIMP:
        and     00000011b       ;Simple slot
        inc     a
        ld      c,a
        ld      b,0
        ld      hl,EXPTBL
        add     hl,bc
        ld      a,(hl)
        and     10000000b
        or      c
        ld      (NEXTSL),a
        ret

SLTEXP:
        ld      c,a     ;Expanded slot
        and     00001100b
        cp      00001100b
        ld      a,c
        jr      z,SLTSIMP
        add     00000100b
        ld      (NEXTSL),a
        ret

NOMORESLT:
        ld      a,0FFh
        ret

NEXTSL:
        db      0FFh     ;Last returned slot


;--- Direct memory test (for DOS 1)
;    INPUT:   DE = 256 byte buffer, it must NOT be in page 1
;             The slot to be tested must be switched on page 1
;    OUTPUT:  A  = Number of available segments, or:
;                  0 -> Error: not a RAM slot
;                  1 -> Error: not mapped RAM
;    MODIFIES: F, HL, BC, DE

MEMTEST1:
        ld      a,(5001h)       ;Check if it is actually RAM
        ld      h,a
        cpl
        ld      (5001h),a
        ld      a,(5001h)
        cpl
        ld      (5001h),a
        cpl
        cp      h
        ld      a,0
        ret     z

        ld      hl,4001h        ;Test address
        in      a,(0FDh)
        push    af      ;A  = Current page 2 segment
        push    de      ;DE = Buffer
        ld      b,0

        ;* Loop for all segment numbers from 0 to 255

MT1BUC1:
        ld      a,b     ;Switch segment on page 1
        out     (0FDh),a

        ld      a,(hl)
        ld      (de),a  ;Save data on the test address...
        ld      a,b
        ld      (hl),a  ;...then write the supposed segment number on test address
        inc     de
        inc     b
        ld      a,b
        cp      0
        jr      nz,MT1BUC1

        ;* Negate the value of test address for segment 0:
        ;  this is the number of segments found (0 for 256)

        out     (0FDh),a
        ld      a,(hl)
        neg
        ld      (NUMSGS),a
        ld      b,0
        ld      c,a
        pop     de

        ;* Restore original value of test address for all segments

MT1BUC2:
        ld      a,b
        out     (0FDh),a
        ld      a,(de)
        ld      (hl),a
        inc     de
        inc     b
        ld      a,b
        cp      c
        jr      nz,MT1BUC2

        ;* Restore original segment on page 1 and return number of segments

        pop     af
        out     (0FDh),a
        ld      a,(NUMSGS)
        cp      1       ;No mapped RAM?
        jr      z,NOMAP1
        or      a
        ret     nz
        ld      a,0FFh   ;If 256 segments, return 255
        ret
NOMAP1: xor     a
        ret

NUMSGS: db      0


;--- NUMTOASC: Converts a 16 bit unsigned value to an ASCII string,
;    terminating it with a "$" character
;    Input: HL = Number to convert
;           DE = Destination address for the string
;
;    This routine is a modification of one borrowed from:
;    http://map.tni.nl/sources/external/z80bits.html
;    (this one skips dummy zeros and adds "$" at the end)

NUMTOASC:
	;* HL=0 is a special case
	ld	a,h
	or	l
	jr	nz,n2anozero
	ex	de,hl
	ld	(hl),"0"
	inc	hl
	ld	(hl),"$"
	ret

n2anozero:
	;* Generate string
	push	de
	ld	de,n2abuf

	ld	bc,-10000
	call	Num1
	ld	bc,-1000
	call	Num1
	ld	bc,-100
	call	Num1
	ld	c,-10
	call	Num1
	ld	c,-1
	call	Num1

	;* Copy string to destination, skipping initial zeros
	pop	de
	ld	hl,n2abuf-1
n2acopy1:
	inc	hl
	ld	a,(hl)
	cp	"0"
	jr	z,n2acopy1
n2acopy2:
	ld	(de),a
	cp	"$"
	ret	z
	inc	de
	inc	hl
	ld	a,(hl)
	jr	n2acopy2

	;* Generate a single digit
Num1:	ld	a,'0'-1
Num2:	inc	a
	add	hl,bc
	jr	c,Num2
	sbc	hl,bc

	ld	(de),a
	inc	de
	ret

n2abuf:	db	"00000$"


;*********************
;***  PAGE 3 CODE  ***
;*********************

;It needs to be duplicated so that it can be reallocated. Sorry.

;***>>>  First copy  <<<***

P3_CODE__1:

        ;--- Hook and jump table area

HOLDEXT__1:    ds      5     ;Old EXTBIO hook

        if INSTALL_MSR = 0

PUT_P1__1:
        jp  _PUTP1__1 ;To be filled with routine PUT_P1 in DOS 2
GET_P1__1:
        ld  a,2       ;To be filled with routine GET_P1 in DOS 2
        ret

_PUTP1__1:
        out (0FDh),a
        ld  (GET_P1__1+1),a
        ret

        endif

        if INSTALL_MSR

MSR_JUMP__1:
        jp  ALL_SEG__1
        jp  FRE_SEG__1
        jp  RD_SEG__1
        jp  WR_SEG__1
        jp  CAL_SEG__1
        jp  CALLS__1
        jp  PUT_PH__1
        jp  GET_PH__1
        jp  PUT_P0__1
        jp  GET_P0__1
        jp  PUT_P1__1
        jp  GET_P1__1
        jp  PUT_P2__1
        jp  GET_P2__1
        jp  PUT_P3__1
        jp  GET_P3__1

        endif

RH_JUMP__1:
        jp      CALLRAM__1
        jp      READRAM__1
        jp      CALLRAM2__1

        ;--- New destination of the EXTBIO hook

NEWEXT__1:
        push    af

        if      INSTALL_MSR

        ld      a,d
        cp      4
        jr      nz,RHEXT__1
        ld      a,e
        dec     a
        jr      nz,NOMSRTAB__1

        ;Get mapper variable table

        pop     af
        ld      a,(MAPTAB__1)
        ld      hl,MAPTAB__1
        ret
NOMSRTAB__1:

        dec     a
        jr      nz,IGNORE__1

        ;Get mapper support routine address

        pop     af
        ld      a,(MAPTAB__1)
        ld      b,a     ;Slot number of primary mapper
        ld      a,(MAPTAB__1+2)
        ld      c,a     ;Free segments in primary mapper
        ld      a,(MAPTAB__1+1)  ;Total segments in primary mapper
        ld      hl,MSR_JUMP__1

        ret

RHEXT__1:
        pop     af
        push    af

        else

RHEXT__1:    

        endif

        inc     a
        jr      nz,IGNORE__1
        ld      a,d
        cp      22h
        jr      nz,IGNORE__1
        ld      a,e
        cp      22h
        jr      nz,IGNORE__1

        ld      hl,RH_JUMP__1  ;Address of the jump table
LDBC__1:
        ld      bc,MAPTAB__1   ;Address of mappers table
        pop     af
        ld      a,3             ;Num entries in jump table
        ret

IGNORE__1:
        pop     af
        jr      HOLDEXT__1

        ;Note: all routines corrupt the alternate register set.


        ;--- Routine to call code in a RAM segment
        ;    Input:
        ;    IYh = Slot number
        ;    IYl = Segment number
        ;    IX = Target routine address (must be a page 1 address)
        ;    AF, BC, DE, HL = Parameters for the target routine
        ;Output:
        ;    AF, BC, DE, HL, IX, IY = Parameters returned from the target
        ;    routine

CALLRAM__1:
        ex      af,af
        call    GET_P1__1
        push    af
        ld      a,iyl
        call    PUT_P1__1
        ex      af,af
        call    CALSLT
        ex      af,af
        pop     af
        call    PUT_P1__1
        ex      af,af
        ret


        ;--- Routine to read a byte from a RAM segment
        ;Input:
        ;    A = Slot number
        ;    B = Segment number
        ;    HL = Address to be read from
        ;       (higher two bits will be ignored)
        ;Output:
        ;    A = Data readed from the specified address
        ;    BC, DE, HL preserved

READRAM__1:
        push bc
        push de
        push hl
        ex      af,af
        call    GET_P1__1
        push    af
        ld      a,b
        call    PUT_P1__1
        res     7,h
        set     6,h
        ex      af,af
        call    RDSLT
        ex      af,af
        pop     af
        call    PUT_P1__1
        ex      af,af
        pop hl
        pop de
        pop bc
        ret


        ;--- Routine to call code in a RAM segment
        ;    (code location specified in the stack)
        ;Input:
        ;    AF, BC, DE, HL = Parameters for the target routine
        ;Output:
        ;    AF, BC, DE, HL, IX, IY = Parameters returned from the target
        ;    routine
        ;Call as:
        ;    CALL CALLRAM2
        ;
        ;CALLRAM2:
        ;    CALL <routine address>
        ;    DB bMMAAAAAA
        ;    DB <segment number>
        ;
        ;    MM = Slot as the index of the entry in the mapper table.
        ;    AAAAAA = Routine address index:
        ;             0=4000h, 1=4003h, ..., 63=40BDh

CALLRAM2__1:
        exx
        ex      af,af'

        pop     ix
        ld      e,(ix+1)        ;Segment number
        ld      d,(ix)  ;Slot and entry point number
        dec     ix
        dec     ix
        push    ix
        ld      iyl,e

        ld      a,d
        and     00111111b
        ld      b,a
        add     a,a
        add     b       ;A = Address index * 3
        ld      l,a
        ld      h,40h
        push    hl
        pop     ix      ;IX = Address to call

        ld      a,d
        and     11000000b
        rlca
        rlca
        rlca            ;A = Mapper table index * 2
_CALLRAM_RLCAS__1:
        nop             ;Will be two more RLCAs (so *8) if MSR are present
        nop
        ld      l,a
        ld      h,0
_CALLRAM_MAPTAB__1:
        ld      bc,MAPTAB__1    ;Will be the address of the MSR table if present
        add     hl,bc
        ld      a,(hl)  ;A = Slot to call
        ld      iyh,a

        ex      af,af'
        exx
        inc     sp
        inc     sp
        jr      CALLRAM__1

CALLIX__1:     jp      (ix)

        if      INSTALL_MSR

        ;--- ALL_SEG and FRE_SEG

ALL_SEG__1:
        push    ix
        ld ix,ALL_SEG__SEG
        jr ALLFRE__1
FRE_SEG__1:
        push    ix
        ld ix,FRE_SEG__SEG

ALLFRE__1:
        push    iy
        push    hl
        push    de
        ex	af,af'
		exx
		push	af
		push	bc
		push	de
		push	hl
		exx
		ex	af,af'

        push af
        ld  a,(MAPTAB__1)   ;Slot number of primary mapper
        ld  iyh,a
        ld  a,(MAPTAB__1+1) ;Last segment number (seg count - 1)
        dec a
        ld  iyl,a
        pop af
        call    CALLRAM__1

        ex	af,af'
		exx
		pop	hl
		pop	de
		pop	bc
		pop	af
		exx
		ex	af,af'
        pop     de
        pop     hl
        pop     iy
        pop     ix
        di
        ret

        ;--- RD_SEG

RD_SEG__1:
        di
        push    hl
        push    bc
        ld      b,a
        call    GET_P2__1  ;Get current page-2 segment
        ld      c,a            ; number and save it in C.
        ld      a,b
        call    PUT_P2__1   ;Put required segment into
        res     6,h         ; page-2 and force address
        set     7,h         ; to page-2.
        ld      b,(hl)      ;Get the byte.
        ld      a,c
        call    PUT_P2__1   ;Restore original page-2
        ld      a,b         ;A := byte value read
        pop     bc
        pop     hl
        ret

        ;--- WR_SEG

WR_SEG__1:
        di
        push    hl
        push    bc
        ld      b,a
        call    GET_P2__1   ;Get the current page-2
        ld      c,a         ; segment & save it in C.
        ld      a,b
        call    PUT_P2__1   ;Put the required segment
        res     6,h         ; in page-2 and force the
        set     7,h         ; address into page-2.
        ld      (hl),e      ;Store the byte.
        ld      a,c
        call    PUT_P2__1   ;Restore original segment
        pop     bc          ; to page-2.
        pop     hl
        ret

        ;--- CALLS and CALL_SEG

CALLS__1:
        exx
        ex      (sp),hl
        ld      d,(hl)
        inc     hl                      ;Extract parameters from in-
        push    de                      ; line after the "CALL CALLS"
        pop     iy                      ; instruction, and adjust
        ld      e,(hl)                  ; the return address.
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        pop     ix
        ex      (sp),hl
        exx

CAL_SEG__1:
        exx                             ;Preserve main register set.
        ex      af,af'
        push    ix
        pop     hl                      ;HL := address to call and get
        call    GET_PH__1               ; current segment for this page
        push    af                      ; and save it for return.
        push    hl
        push    iy
        pop     af                      ;Enable required segment for
        call    PUT_PH__1           ; this address.
        ex      af,af'
        exx
        call    CALLIX__1               ;Call the routine via IX
        exx
        ex      af,af'
        pop     hl                      ;Restore the original
        pop     af                      ; segment to the appropriate
        call    PUT_PH__1               ; page.
        ex      af,af'
        exx
        ret

        ;--- GET_Pn and PUT_Pn

PUT_PH__1:
        bit     7,h                     ;Jump to appropriate "PUT_Pn"
        jr      nz,_put_p2_or_p3__1     ; routine, depending on the
        bit     6,h                     ; top two bits of H.
        jr      z,PUT_P0__1
        jr      PUT_P1__1
_put_p2_or_p3__1: 
        bit     6,h
        jr      z,PUT_P2__1
        ret     ;jr     _put_p3

GET_PH__1:
        bit     7,h                     ;Jump to appropriate "GET_Pn"
        jr      nz,_get_p2_or_p3__1     ; routine, depending on the
        bit     6,h                     ; top two bits of H.
        jr      z,GET_P0__1
        jr      GET_P1__1
_get_p2_or_p3__1:  
        bit     6,h
        jr      z,GET_P2__1
        xor     a   ;jr _get_p3
        ret

PUT_P0__1:
        ld      (CURSEGS__1),a
        out     (0FCh),a
        ret
GET_P0__1:      
        ld a,(CURSEGS__1)
        ret

PUT_P1__1:
        ld      (CURSEGS__1+1),a
        out     (0FDh),a
        ret
GET_P1__1:      
        ld a,(CURSEGS__1+1)
        ret

PUT_P2__1:
        ld      (CURSEGS__1+2),a
        out     (0FEh),a
        ret
GET_P2__1:      
        ld      a,(CURSEGS__1+2)
        ret

GET_P3__1:
        ld      a,(CURSEGS__1+3)
PUT_P3__1:
        ret

CURSEGS__1:     db 3,2,1,0

        endif

;Mappers table.
;
;If we install the MSR, we also generate a standard table where
;each entry is 8 bytes.
;
;If not, and if no MSR is already present, we generate
;a reduced table where each entry is just two bytes:
;slot + maximum segment number
;
;In both cases, first entry is for the primary mapper,
;and there's always a 0 after the last entry.
MAPTAB__1:

P3_CODE_END__1:
    if  INSTALL_MSR
    ds (8*2)+1
    else
    ds (4*2)+1       ;Space for building the table
    endif

;***>>>  Second copy  <<<***

P3_CODE__2:

        ;--- Hook and jump table area

HOLDEXT__2:    ds      5     ;Old EXTBIO hook

        if INSTALL_MSR = 0

PUT_P1__2:
        jp  _PUTP1__2 ;To be filled with routine PUT_P1 in DOS 2
GET_P1__2:
        ld  a,2       ;To be filled with routine GET_P1 in DOS 2
        ret

_PUTP1__2:
        out (0FDh),a
        ld  (GET_P1__2+1),a
        ret

        endif

        if INSTALL_MSR

MSR_JUMP__2:
        jp  ALL_SEG__2
        jp  FRE_SEG__2
        jp  RD_SEG__2
        jp  WR_SEG__2
        jp  CAL_SEG__2
        jp  CALLS__2
        jp  PUT_PH__2
        jp  GET_PH__2
        jp  PUT_P0__2
        jp  GET_P0__2
        jp  PUT_P1__2
        jp  GET_P1__2
        jp  PUT_P2__2
        jp  GET_P2__2
        jp  PUT_P3__2
        jp  GET_P3__2

        endif

RH_JUMP__2:
        jp      CALLRAM__2
        jp      READRAM__2
        jp      CALLRAM2__2

        ;--- New destination of the EXTBIO hook

NEWEXT__2:
        push    af

        if      INSTALL_MSR

        ld      a,d
        cp      4
        jr      nz,RHEXT__2
        ld      a,e
        dec     a
        jr      nz,NOMSRTAB__2

        ;Get mapper variable table

        pop     af
        ld      a,(MAPTAB__2)
        ld      hl,MAPTAB__2
        ret
NOMSRTAB__2:

        dec     a
        jr      nz,IGNORE__2

        ;Get mapper support routine address

        pop     af
        ld      a,(MAPTAB__2)
        ld      b,a     ;Slot number of primary mapper
        ld      a,(MAPTAB__2+2)
        ld      c,a     ;Free segments in primary mapper
        ld      a,(MAPTAB__2+1)  ;Total segments in primary mapper
        ld      hl,MSR_JUMP__2

        ret

RHEXT__2:
        pop     af
        push    af

        else

RHEXT__2:    

        endif

        inc     a
        jr      nz,IGNORE__2
        ld      a,d
        cp      22h
        jr      nz,IGNORE__2
        ld      a,e
        cp      22h
        jr      nz,IGNORE__2

        ld      hl,RH_JUMP__2  ;Address of the jump table
LDBC__2:
        ld      bc,MAPTAB__2   ;Address of mappers table
        pop     af
        ld      a,3             ;Num entries in jump table
        ret

IGNORE__2:
        pop     af
        jr      HOLDEXT__2

        ;Note: all routines corrupt the alternate register set.


        ;--- Routine to call code in a RAM segment
        ;    Input:
        ;    IYh = Slot number
        ;    IYl = Segment number
        ;    IX = Target routine address (must be a page 1 address)
        ;    AF, BC, DE, HL = Parameters for the target routine
        ;Output:
        ;    AF, BC, DE, HL, IX, IY = Parameters returned from the target
        ;    routine

CALLRAM__2:
        ex      af,af
        call    GET_P1__2
        push    af
        ld      a,iyl
        call    PUT_P1__2
        ex      af,af
        call    CALSLT
        ex      af,af
        pop     af
        call    PUT_P1__2
        ex      af,af
        ret


        ;--- Routine to read a byte from a RAM segment
        ;Input:
        ;    A = Slot number
        ;    B = Segment number
        ;    HL = Address to be read from
        ;       (higher two bits will be ignored)
        ;Output:
        ;    A = Data readed from the specified address
        ;    BC, DE, HL preserved

READRAM__2:
        push bc
        push de
        push hl
        ex      af,af
        call    GET_P1__2
        push    af
        ld      a,b
        call    PUT_P1__2
        res     7,h
        set     6,h
        ex      af,af
        call    RDSLT
        ex      af,af
        pop     af
        call    PUT_P1__2
        ex      af,af
        pop hl
        pop de
        pop bc
        ret


        ;--- Routine to call code in a RAM segment
        ;    (code location specified in the stack)
        ;Input:
        ;    AF, BC, DE, HL = Parameters for the target routine
        ;Output:
        ;    AF, BC, DE, HL, IX, IY = Parameters returned from the target
        ;    routine
        ;Call as:
        ;    CALL CALLRAM2
        ;
        ;CALLRAM2:
        ;    CALL <routine address>
        ;    DB bMMAAAAAA
        ;    DB <segment number>
        ;
        ;    MM = Slot as the index of the entry in the mapper table.
        ;    AAAAAA = Routine address index:
        ;             0=4000h, 1=4003h, ..., 63=40BDh

CALLRAM2__2:
        exx
        ex      af,af'

        pop     ix
        ld      e,(ix+1)        ;Segment number
        ld      d,(ix)  ;Slot and entry point number
        dec     ix
        dec     ix
        push    ix
        ld      iyl,e

        ld      a,d
        and     00111111b
        ld      b,a
        add     a,a
        add     b       ;A = Address index * 3
        ld      l,a
        ld      h,40h
        push    hl
        pop     ix      ;IX = Address to call

        ld      a,d
        and     11000000b
        rlca
        rlca
        rlca            ;A = Mapper table index * 2
_CALLRAM_RLCAS__2:
        nop             ;Will be two more RLCAs (so *8) if MSR are present
        nop
        ld      l,a
        ld      h,0
_CALLRAM_MAPTAB__2:
        ld      bc,MAPTAB__2    ;Will be the address of the MSR table if present
        add     hl,bc
        ld      a,(hl)  ;A = Slot to call
        ld      iyh,a

        ex      af,af'
        exx
        inc     sp
        inc     sp
        jr      CALLRAM__2

CALLIX__2:     jp      (ix)

        if      INSTALL_MSR

        ;--- ALL_SEG and FRE_SEG

ALL_SEG__2:
        push    ix
        ld ix,ALL_SEG__SEG
        jr ALLFRE__2
FRE_SEG__2:
        push    ix
        ld ix,FRE_SEG__SEG

ALLFRE__2:
        push    iy
        push    hl
        push    de
        ex	af,af'
		exx
		push	af
		push	bc
		push	de
		push	hl
		exx
		ex	af,af'

        push af
        ld  a,(MAPTAB__2)   ;Slot number of primary mapper
        ld  iyh,a
        ld  a,(MAPTAB__2+1) ;Last segment number (seg count - 1)
        dec a
        ld  iyl,a
        pop af
        call    CALLRAM__2

        ex	af,af'
		exx
		pop	hl
		pop	de
		pop	bc
		pop	af
		exx
		ex	af,af'
        pop     de
        pop     hl
        pop     iy
        pop     ix
        di
        ret

        ;--- RD_SEG

RD_SEG__2:
        di
        push    hl
        push    bc
        ld      b,a
        call    GET_P2__2  ;Get current page-2 segment
        ld      c,a            ; number and save it in C.
        ld      a,b
        call    PUT_P2__2   ;Put required segment into
        res     6,h         ; page-2 and force address
        set     7,h         ; to page-2.
        ld      b,(hl)      ;Get the byte.
        ld      a,c
        call    PUT_P2__2   ;Restore original page-2
        ld      a,b         ;A := byte value read
        pop     bc
        pop     hl
        ret

        ;--- WR_SEG

WR_SEG__2:
        di
        push    hl
        push    bc
        ld      b,a
        call    GET_P2__2   ;Get the current page-2
        ld      c,a         ; segment & save it in C.
        ld      a,b
        call    PUT_P2__2   ;Put the required segment
        res     6,h         ; in page-2 and force the
        set     7,h         ; address into page-2.
        ld      (hl),e      ;Store the byte.
        ld      a,c
        call    PUT_P2__2   ;Restore original segment
        pop     bc          ; to page-2.
        pop     hl
        ret

        ;--- CALLS and CALL_SEG

CALLS__2:
        exx
        ex      (sp),hl
        ld      d,(hl)
        inc     hl                      ;Extract parameters from in-
        push    de                      ; line after the "CALL CALLS"
        pop     iy                      ; instruction, and adjust
        ld      e,(hl)                  ; the return address.
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        pop     ix
        ex      (sp),hl
        exx

CAL_SEG__2:
        exx                             ;Preserve main register set.
        ex      af,af'
        push    ix
        pop     hl                      ;HL := address to call and get
        call    GET_PH__2               ; current segment for this page
        push    af                      ; and save it for return.
        push    hl
        push    iy
        pop     af                      ;Enable required segment for
        call    PUT_PH__2           ; this address.
        ex      af,af'
        exx
        call    CALLIX__2               ;Call the routine via IX
        exx
        ex      af,af'
        pop     hl                      ;Restore the original
        pop     af                      ; segment to the appropriate
        call    PUT_PH__2               ; page.
        ex      af,af'
        exx
        ret

        ;--- GET_Pn and PUT_Pn

PUT_PH__2:
        bit     7,h                     ;Jump to appropriate "PUT_Pn"
        jr      nz,_put_p2_or_p3__2     ; routine, depending on the
        bit     6,h                     ; top two bits of H.
        jr      z,PUT_P0__2
        jr      PUT_P1__2
_put_p2_or_p3__2: 
        bit     6,h
        jr      z,PUT_P2__2
        ret     ;jr     _put_p3

GET_PH__2:
        bit     7,h                     ;Jump to appropriate "GET_Pn"
        jr      nz,_get_p2_or_p3__2     ; routine, depending on the
        bit     6,h                     ; top two bits of H.
        jr      z,GET_P0__2
        jr      GET_P1__2
_get_p2_or_p3__2:  
        bit     6,h
        jr      z,GET_P2__2
        xor     a   ;jr _get_p3
        ret

PUT_P0__2:
        ld      (CURSEGS__2),a
        out     (0FCh),a
        ret
GET_P0__2:      
        ld a,(CURSEGS__2)
        ret

PUT_P1__2:
        ld      (CURSEGS__2+1),a
        out     (0FDh),a
        ret
GET_P1__2:      
        ld a,(CURSEGS__2+1)
        ret

PUT_P2__2:
        ld      (CURSEGS__2+2),a
        out     (0FEh),a
        ret
GET_P2__2:      
        ld      a,(CURSEGS__2+2)
        ret

GET_P3__2:
        ld      a,(CURSEGS__2+3)
PUT_P3__2:
        ret

CURSEGS__2:     db 3,2,1,0

        endif

;Mappers table.
;
;If we install the MSR, we also generate a standard table where
;each entry is 8 bytes.
;
;If not, and if no MSR is already present, we generate
;a reduced table where each entry is just two bytes:
;slot + maximum segment number
;
;In both cases, first entry is for the primary mapper,
;and there's always a 0 after the last entry.
MAPTAB__2:


P3_CODE_END__2:
    if  INSTALL_MSR
    ds (8*2)+1
    else
    ds (4*2)+1       ;Space for building the table
    endif


;*******************************
;***  VARIABLES AND STRINGS  ***
;*******************************

CMDLINE_PNT:    dw      0       ;Pointer to command line after the first parameter
MAPTAB_SIZE:    db      0       ;Size of reduced mappers table (if we build it)

SHELL_S:        db      "SHELL",0
PROGRAM_S:      db      "PROGRAM",0

WELCOME_S:

        if INSTALL_MSR

        db      "Standalone mapper support routines + UNAPI RAM helper installer 1.2",13,10

        else

        db      "Standalone UNAPI RAM helper installer 1.2",13,10

        endif

        db      "(c) 2019 by Konamiman",13,10
        db      13,10
        db      "$"

USAGE_S:
        ;        --------------------------------------------------------------------------------

        if INSTALL_MSR

        db      "Usage: msr [i|f] [command[&command[&...]]]",13,10
        db      "       msr c",13,10

        else

        db      "Usage: ramhelpr [i|f] [command[&command[&...]]]",13,10

        endif

        db      13,10
        db      "i: Install only if no RAM helper is already installed.",13,10
        db      "f: Force install, even if the same or other helper is already installed.",13,10
        db      "command: DOS command to be invoked after the install process (DOS 2 only).",13,10
        db      "         Under COMMAND 2.4x multiple commands can be specified, separated by &.",13,10

        if INSTALL_MSR

        db      13,10
        db      "c: Cleanup: free all segments allocated in user mode.",13,10
        db      "   This is necessary because in MSX-DOS 1 those segments won't be freed",13,10
        db      "   automatically when the application allocating them terminates."

        endif

        db      13,10,"$"

        if INSTALL_MSR

MSR_ALINST_S:
        db      "*** Mapper support routines are already installed.",13,10
        db      "    If you want to install the RAM helper only, use RAMHELPR.COM instead."
        db      13,10,"$"

IHAVESETSLOTS_S:
        db      "- I have set the same slot for all pages of TPA",13,10,13,10,"$"

        endif

RH_ALINST_S:
        db      "*** An UNAPI RAM helper is already installed",13,10,"$"

NOMAPPER_S:
        db      "*** ERROR: No mapped RAM found.",13,10,"$"

NOTPA_S:
        db      "*** ERROR: Not enough TPA space",13,10,"$"

CMDWARNING_S:
        db      13,10,"* WARNING: The extra DOS command isn't invoked in MSX-DOS 1",13,10,"$"

OK_S:   db      "Installed. Have fun!",13,10,"$"

        if INSTALL_MSR

;****************************************
;***  CODE TO BE COPIED IN A SEGMENT  ***
;****************************************

SEGMENT_CODE:
    org     4000h

SEGMENT_CODE_START:
ALL_SEG__SEG:
    jp  _ALL_SEG__SEG
FRE_SEG__SEG:
    jp  _FRE_SEG__SEG


;ALL_SEG - Parameters: A=0  => allocate user segment
;                      A=1  => allocate system segment
;                      B=0  => allocate primary mapper
;                      B!=0 => allocate FxxxSSPP slot address
;                              (primary mapper, if 0)
;                              xxx=000 allocate specified slot only
;                              xxx=001 allocate other slots than
;                                      specified
;                              xxx=010 try to allocate specified slot
;                                      and, if it failed, try another slot
;                                      (if any)
;                              xxx=011 try to allocate other slots
;                                      than specified and, if it failed,
;                                      try specified slot
;
;          Results:    Carry set   => no free segments
;                      Carry clear => segment allocated
;                      A=new segment number
;                      B=slot address of
;                        mapper slot (0 if called as B=0)

_ALL_SEG__SEG:
        and 1
		inc a   ;Type of segment to allocate
    	ex	af,af'
;
		ld	c,b
		ld	a,c			;If requested slot number is
		and	10001111b		; zero then use the primary
		jr	nz,not_primary_all	; mapper slot number.  Leave
		ld	a,(RAMSLOT3)		; the zero in B for now in
		or	c			; case of a type 000 return.
		ld	c,a			;C := slot number & type
not_primary_all:
;
;    *****  ONLY TRY SPECIFIED SLOT IF TYPE 000  *****
;
		ld	a,c			;If "type" is 000 then
		and	01110000b		; just try to allocate from
		jr	nz,not_type_000		; the requested slot and
		jr	ALL_SEG_SLOT_C		; then jump immediately with
						; the result.
not_type_000:
;
;
;    *****  TRY SPECIFIED SLOT FIRST FOR TYPE 010  *****
;
		ld	b,c			;B := real slot & type
		cp	00100000b		;For type 010 allocate in
		jr	nz,not_type_010		; specified slot if possible.
		call	ALL_SEG_SLOT_C
		jr	nc,all_seg_ret
not_type_010:
;
;
;    *****  TRY EVERY SLOT EXCEPT SPECIFIED ONE FOR ALL TYPES  *****
;
		xor	a
		ld	hl,EXPTBL
all_pri_loop:	bit	7,(hl)			;Set expanded slot flag in A
		jr	z,all_not_exp		; if this slot is expanded.
		set	7,a
all_not_exp:
all_sec_loop:	ld	c,a			;Try to allocate a segment
		xor	b			; from this slot unless it
		and	10001111b		; is the specified slot
		jr	z,skip_slot		; number.
		push	hl
		call	ALL_SEG_SLOT_C
		pop	hl
		jr	nc,all_seg_ret		;Exit if got segment
skip_slot:	ld	a,c
;
		bit	7,a
		jr	z,all_not_exp_2		;If it is an expanded slot
		add	a,4			; then step on to next
		bit	4,a			; secondary slot and loop
		jr	z,all_sec_loop		; back if not last one.
all_not_exp_2:	inc	hl
		inc	a			;Step onto next primary slot
		and	03h			; and loop back if not done
		jr	nz,all_pri_loop		; the last one.
;
;
;    *****  FINALLY TRY SPECIFIED SLOT FOR TYPE 011  *****
;
		ld	a,b			;Couldn't find segment so if
		and	01110000b		; try the specified segment as
		cp	00110000b		; a "last resort" if it is
		scf				; allocation type 011.
		jr	nz,all_seg_ret
		ld	c,b
		call	ALL_SEG_SLOT_C
;
all_seg_ret:	push	af			;For all returns other than
		ld	a,c			; for type 000, return the
		and	10001111b		; actual slot number in
		ld	b,a			; register B, preserving
		pop	af			; carry flag.
		ret
;
;
;	--------------------------------------------------
;
;
ALL_SEG_SLOT_C:	push	bc
;
		ld	a,c
        call    GET_MAPPER_POINTERS
        jr  c,no_seg_ret
;
		ld	a,(de)
		inc	de
		ld	c,a			;C := total segments in mapper
		ex	af,af'
		ld	b,a
		ex	af,af'			;Skip if we are allocating
		dec b			; a system segment.
        dec b
		jr	z,all_system
;
;
		ld	b,0
all_user_loop:	ld	a,(hl)			;For a user segment look
		or	a			; through the segment list
		jr	z,got_user_seg		; forwards until we find a
		inc	b			; free segment.
		inc	hl			;C = loop counter
		dec	c			;B = segment number
		jr	nz,all_user_loop
		jr	no_seg_ret		;Error if no free segments
;
got_user_seg:	ex	de,hl
		dec	(hl)			;One fewer free segments
		inc	hl
		inc	hl
		inc	(hl)			;One more user segment
		jr	got_seg_ret		;Jump with B=segment
;
;
all_system:	add	hl,bc			;For a system segment look
all_sys_loop:	dec	hl			; through the segment list
		ld	a,(hl)			; from the end backwards to
		or	a			; find the highest numbered
		jr	z,got_sys_seg		; free segment
		dec	c
		jr	nz,all_sys_loop
		jr	no_seg_ret		;Error if no free segments
;
got_sys_seg:	ld	b,c
		dec	b			;B = segment number
		ex	de,hl
		dec	(hl)			;One fewer free segments
		inc	hl
		inc	(hl)			;One more system segments
;
;
got_seg_ret:	ex	af,af'			;Record the owning process id
		ld	(de),a			; in the segment list (FFh if
		ex	af,af'			; it is a system segment).
;
		ld	a,b			;A := allocated segment number
		pop	bc
		or	a			;Return with carry clear
		ret				; to indicate success.
;
;
no_seg_ret:	pop	bc			;If no free segments then
		scf				; return with carry set to
		ret				; indicate error.



;FRE_SEG - Parameters: A=segment number to free
;                      B =0 primary mapper
;                      B!=0 mapper other than primary
;
;          Returns:    Carry set   => error
;                      Carry clear => segment freed OK
;
;If A=FFh and B=0Fh: Free all segmenst allocated in user mode,
;                    returns Cy=0 and BC=hoy many segments have been freed


_FRE_SEG__SEG:
		ld	c,a			;C = segment number

        cp  0FFh
        jr  nz,no_free_all_user
        ld  a,b
        cp  0Fh
        jr  nz,no_free_all_user

        call FREE_USER__SEG
        or a
        ret
no_free_all_user:
		ld	a,b
		and	10001111b		;If slot number is zero then
		jr	nz,fre_not_prim		; use the primary mapper slot
		ld	a,(RAMSLOT3)
fre_not_prim:	
        call    GET_MAPPER_POINTERS
        jr      c,fre_bad_seg

		ld	a,(de)			;Check that segment number is
		cp	c			; smaller than the total
		jr	c,fre_bad_seg		; segments for this mapper and
		jr	z,fre_bad_seg		; error if not.
		ld	b,0
		add	hl,bc			;HL -> this segment in list
		ld	a,(hl)			;Error if this segment is
		or	a			; already free.
		jr	z,fre_bad_seg
		ld	(hl),b			;Mark it as free now.
;
		ex	de,hl
		inc	hl
		inc	(hl)			;One more free segment
		inc	hl
		cp  2			    ;One fewer user or system segment
		jr	z,fre_system
		inc	hl
fre_system:	dec	(hl)
		or	a			;Clear carry => success
		ret
;
fre_bad_seg:	scf				;Set carry to indicate error
		ret


;Free all user segments
;Output: BC = How many segments have I freed

FREE_USER__SEG:
    ld      de,0401h
    call    EXTBIO
    push    hl
    pop     ix      ;IX = Mappers table
    ld      de,SEG_USE_TABLE
    ld      hl,0    ;HL = How many segments have I freed

FREE_USER_LOOP:
    ld      a,(ix)
    or      a
    jr      z,FREE_USER_END

    push    de
    ld      b,(ix+1)    ;Total segments in mapper
FREE_USER_LOOP_2:
    ld      a,(de)
    cp      1
    jr      nz,no_user_segment

    xor     a
    ld      (de),a
    inc     (ix+2)      ;One more free segment in mapper
    inc     hl          ;One more segment freed
no_user_segment:
    inc     de
    djnz    FREE_USER_LOOP_2

    ld      (ix+4),b    ;Number of segments allocated to user in mapper = 0
    ld      bc,8
    add     ix,bc       ;Next mappers table entry
    pop     de
    inc     d           ;Next entry in SEG_USE_TABLE
    jr      FREE_USER_LOOP

FREE_USER_END:
    push    hl
    pop     bc
    ret


    ;This routine gets the pointers for a mapper slot.
    ;Input:  A = Slot number
    ;Output: DE = Pointer to 2nd byte (total segments) in mappers table for the slot
    ;        HL = Pointer to start of table in SEG_USE_TABLE for the slot
    ;        Cy = 1 on error (not a valid mapper slot number)

GET_MAPPER_POINTERS:
    push    bc
    call    _GMP
    pop     bc
    ret
_GMP:

    and     10001111b
    push    af
    ld      de,0401h
    call    EXTBIO
    pop     bc
    ex      de,hl
    ld      hl,SEG_USE_TABLE

GMPLOOP:
    ld      a,(de)
    inc     de
    or      a
    scf
    ret     z

    cp      b
    ret     z

    inc     h
    inc     de
    inc     de
    inc     de
    inc     de
    inc     de
    inc     de
    inc     de
    jr      GMPLOOP

    ;This is a four entries table with 256 bytes for each mapper slot.
    ;Each entry has: 0 = free segment, 1 = allocated to user, 2 = allocated to system, FFh = doesn't exist.
SEG_USE_TABLE:

SEGMENT_CODE_END:

    endif
