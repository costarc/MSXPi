; =============================================================================
; MSXPi Ethernet UNAPI - installer  (ETHUNAPI.COM)
; =============================================================================
; Allocates a mapped RAM segment, copies the resident driver (ethseg.bin) into
; it, and hooks EXTBIO so that the UNAPI discovery procedure finds us.
;
; Requires the UNAPI RAM helper to be installed already - same requirement as
; examples/unapi-ram.asm in the specification repo.  On MSX-DOS 1 the mapper
; support routines come from the helper's own mappers table; on DOS 2 they come
; from the standard mapper support routines.
;
; Build (see ../build.sh):
;   sjasm ethseg.asm   ethseg.bin ethseg.lst ethseg.exp
;   sjasm ethunapi.asm ETHUNAPI.COM
; =============================================================================

_TERM0:     equ     00h
_STROUT:    equ     09h
BDOS:       equ     0005h
ENASLT:     equ     0024h
EXTBIO:     equ     0FFCAh
ARG:        equ     0F847h

            include "ethseg.exp"        ; symbol addresses inside the segment

SEG_SIZE:   equ     SEG_CODE_END-SEG_CODE_START

CTRL2:          equ   57h
WAITMODE_ON:    equ   01h
; Wait mode confirmed.  Real hardware answers $8E; openMSX answers $FF, because
; it must stay at or above $FE for msxpi_bios.asm:97's per-byte "am I openMSX?"
; test to keep working while the mode is on.
VER_WAIT_ON:      equ 8Eh
VER_WAIT_ON_OMSX: equ 0FFh
VER_OPENMSX:      equ 0FEh
MODE_POLL_HW:   equ   0
MODE_WAIT:      equ   1
MODE_POLL_OMSX: equ   2

            org     100h

            ld      de,WELCOME_S
            ld      c,_STROUT
            call    BDOS

; -----------------------------------------------------------------------------
; 1. Locate the RAM helper
; -----------------------------------------------------------------------------
; EXTBIO with A=FFh, DE=2222h, HL=0 returns HL = helper jump table address and
; BC = mappers table.  Every UNAPI implementation is required to chain rather
; than answer A=FFh, which is what makes this work.
            ld      de,2222h
            ld      hl,0
            ld      a,0FFh
            call    EXTBIO
            ld      a,h
            or      l
            jr      nz,HELPER_OK

            ld      de,NOHELPER_S
            jp      DIE
HELPER_OK:
            ld      (HELPER_ADD),hl
            ld      (MAPTAB_ADD),bc

; -----------------------------------------------------------------------------
; 2. Refuse to install twice
; -----------------------------------------------------------------------------
; The specification's own example walks every installed implementation and
; compares names through the helper's RD_MAP routine.  This does the cheap
; version: if ANY "ETHERNET" implementation is already present, stop.  On this
; machine there is only ever one, and a double install would chain the EXTBIO
; hook to itself and report two implementations.
;
; TODO: compare implementation names so that a second, different Ethernet UNAPI
;       (ObsoNET, an ESP8266 board) can coexist with this one.
            ld      hl,UNAPI_ID_STR
            ld      de,ARG
            ld      bc,UNAPI_ID_LEN
            ldir

            ld      de,2222h
            xor     a
            ld      b,0
            call    EXTBIO
            ld      a,b
            or      a
            jr      z,NOT_INSTALLED

            ld      de,ALINST_S
            jp      DIE
NOT_INSTALLED:

; -----------------------------------------------------------------------------
; 3. Obtain mapper support routines and allocate a segment
; -----------------------------------------------------------------------------
            xor     a
            ld      de,0402h
            call    EXTBIO
            or      a
            jr      nz,ALLOC_DOS2

            ; --- DOS 1: take the last segment of the primary mapper, as
            ;     reported by the helper's own two-byte-per-entry table.
            ld      a,2
            ld      (MAPTAB_ENTRY_SIZE),a
            ld      hl,(MAPTAB_ADD)
            ld      b,(hl)
            inc     hl
            ld      a,(hl)
            jr      ALLOC_OK

ALLOC_DOS2:
            ld      a,b
            ld      (PRIM_SLOT),a
            ld      de,ALL_SEG
            ld      bc,15*3
            ldir                        ; copy the mapper jump table locally

            ld      de,0401h
            call    EXTBIO
            ld      (MAPTAB_ADD),hl
            ld      a,8
            ld      (MAPTAB_ENTRY_SIZE),a

            ld      a,(PRIM_SLOT)
            or      00100000b           ; primary mapper first, then any other
            ld      b,a
            ld      a,1                 ; system segment
            call    ALL_SEG
            jr      nc,ALLOC_OK

            ld      de,NOFREE_S
            jp      DIE

ALLOC_OK:
            ld      (ALLOC_SEG),a
            ld      a,b
            ld      (ALLOC_SLOT),a

; -----------------------------------------------------------------------------
; 4. Page the segment in, clear it, and copy the resident code
; -----------------------------------------------------------------------------
            call    GET_P1
            ld      (P1_SEG),a          ; remember the TPA segment on page 1

            ld      a,(ALLOC_SLOT)
            ld      h,40h
            call    ENASLT
            ld      a,(ALLOC_SEG)
            call    PUT_P1

            ld      hl,4000h            ; clear first, so unused space is not
            ld      de,4001h            ; whatever the previous owner left
            ld      bc,4000h-1
            ld      (hl),0
            ldir

            ld      hl,SEG_IMAGE
            ld      de,4000h
            ld      bc,SEG_SIZE
            ldir

            ld      hl,(ALLOC_SLOT)     ; ALLOC_SLOT/ALLOC_SEG are adjacent, so
            ld      (MY_SLOT),hl        ; this writes both in one go

; -----------------------------------------------------------------------------
; 4b. Detect the transport backend and patch ETH_MODE in the segment
; -----------------------------------------------------------------------------
; Ask the device to turn hardware /WAIT on and see whether it admits to it.
; Real CPLD v1.6 answers $8E; older hardware ignores the write and still reads
; $0D/$0E; stock openMSX ignores it and always reads $FE.  Only an exact $8E
; counts, so there is no way to mistake one for another.
;
; Wait mode is ALWAYS switched back off before returning.  Legacy software -
; including msxpi_bios.asm:97, which decides "is this openMSX?" by testing $57
; against $FE - must never find the device in a state it does not expect.  The
; driver turns it on again per transaction, inside its own lock.
; The probe must come FIRST, before any attempt to identify the device by its
; $57 value: an openMSX with wait-mode support still reads $FE until software
; opts in, so testing for $FE up front would misclassify it as polled.
            ld      a,WAITMODE_ON
            out     (CTRL2),a
            in      a,(CTRL2)
            cp      VER_WAIT_ON         ; $8E - real CPLD v1.6 confirms the mode
            jr      z,.mode_wait
            cp      VER_WAIT_ON_OMSX    ; $FF - openMSX confirms it
            jr      z,.mode_wait

            xor     a                   ; not supported; put it back and look again
            out     (CTRL2),a
            in      a,(CTRL2)
            cp      VER_OPENMSX         ; $FE - stock openMSX
            jr      z,.mode_omsx
            ld      a,MODE_POLL_HW
            jr      .mode_store
.mode_omsx:
            ld      a,MODE_POLL_OMSX
            jr      .mode_store
.mode_wait:
            ld      a,MODE_WAIT
.mode_store:
            ld      (ETH_MODE),a
            ld      (DETECTED_MODE),a
            xor     a                   ; and leave it off
            out     (CTRL2),a

; -----------------------------------------------------------------------------
; 5. Chain and install the EXTBIO hook
; -----------------------------------------------------------------------------
; The old hook contents move into the segment (still paged in on page 1), and
; EXTBIO becomes a call to the helper's inline-identified segment call routine
; at helper+6, whose two inline bytes are the mapper index and the segment.
            ld      hl,EXTBIO
            ld      de,OLD_EXTBIO
            ld      bc,5
            ldir

            di
            ld      a,0CDh              ; CALL nn
            ld      (EXTBIO),a
            ld      hl,(HELPER_ADD)
            ld      bc,6
            add     hl,bc
            ld      (EXTBIO+1),hl

            ; Find our slot in the mappers table; its index becomes the top two
            ; bits of the inline argument (entry point 4010h = index 0).
            ld      hl,(MAPTAB_ADD)
            ld      a,(ALLOC_SLOT)
            ld      bc,(MAPTAB_ENTRY_SIZE)
            ld      b,0
            ld      d,a
            ld      e,0
SRCHMAP:
            ld      a,(hl)
            cp      d
            jr      z,MAPFND
            add     hl,bc
            inc     e
            jr      SRCHMAP
MAPFND:
            ld      a,e
            rrca
            rrca
            and     11000000b
            ld      (EXTBIO+3),a
            ld      a,(ALLOC_SEG)
            ld      (EXTBIO+4),a
            ei

; -----------------------------------------------------------------------------
; 6. Put page 1 back and report
; -----------------------------------------------------------------------------
            ld      a,(PRIM_SLOT)
            ld      h,40h
            call    ENASLT
            ld      a,(P1_SEG)
            call    PUT_P1

            ld      de,OK_S
            ld      c,_STROUT
            call    BDOS

            ld      a,(DETECTED_MODE)
            cp      MODE_WAIT
            ld      de,MODE_WAIT_S
            jr      z,.report
            cp      MODE_POLL_OMSX
            ld      de,MODE_OMSX_S
            jr      z,.report
            ld      de,MODE_POLLED_S
.report:
            ld      c,_STROUT
            call    BDOS

            ld      c,_TERM0
            jp      BDOS

DIE:
            ld      c,_STROUT
            call    BDOS
            ld      c,_TERM0
            jp      BDOS

; =============================================================================
; Variables
; =============================================================================
PRIM_SLOT:          db      0
P1_SEG:             db      0
; ALLOC_SLOT and ALLOC_SEG must stay adjacent and in this order - step 4 copies
; both into MY_SLOT/MY_SEG with a single 16-bit load.
ALLOC_SLOT:         db      0
ALLOC_SEG:          db      0
HELPER_ADD:         dw      0
MAPTAB_ADD:         dw      0
MAPTAB_ENTRY_SIZE:  db      0
DETECTED_MODE:      db      0

; --- Mapper support routine jump table, filled in at run time ---------------
ALL_SEG:    ds      3
FRE_SEG:    ds      3
RD_SEG:     ds      3
WR_SEG:     ds      3
CAL_SEG:    ds      3
CALLS:      ds      3
PUT_PH:     ds      3
GET_PH:     ds      3
PUT_P0:     ds      3
GET_P0:     ds      3
; PUT_P1/GET_P1 are supplied locally rather than taken from the table: the
; table's versions would page the segment out from under this very code.
PUT_P1:     jp      _PUT_P1
GET_P1:     ld      a,2
            ret
PUT_P2:     ds      3
GET_P2:     ds      3
PUT_P3:     ds      3
_PUT_P1:
            ld      (GET_P1+1),a
            out     (0FDh),a
            ret

; =============================================================================
; Strings
; =============================================================================
WELCOME_S:
            db      "MSXPi Ethernet UNAPI installer 0.1",13,10
            db      "(c) 2026 Ronivon Costa - GPL",13,10,13,10,"$"
NOHELPER_S: db      "*** ERROR: No UNAPI RAM helper installed.",13,10
            db      "    Run RAMHELPR.COM first.",13,10,"$"
NOFREE_S:   db      "*** ERROR: Could not allocate a RAM segment.",13,10,"$"
ALINST_S:   db      "*** An ETHERNET UNAPI is already installed.",13,10,"$"
OK_S:       db      "Installed.",13,10,"$"
MODE_WAIT_S:   db   "Transport: hardware /WAIT",13,10,"$"
MODE_POLLED_S: db   "Transport: polled",13,10,"$"
MODE_OMSX_S:   db   "Transport: polled (openMSX)",13,10,"$"

UNAPI_ID_STR:
            db      "ETHERNET",0
UNAPI_ID_LEN: equ   $-UNAPI_ID_STR

; =============================================================================
; Resident code image, copied into the allocated segment
; =============================================================================
SEG_IMAGE:
            incbin  "ethseg.bin"
