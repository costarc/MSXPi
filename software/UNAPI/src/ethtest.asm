; =============================================================================
; ETHTEST.COM - verify the Ethernet UNAPI implementation is discoverable
; =============================================================================
; Runs the standard MSX-UNAPI discovery procedure for "ETHERNET", then calls
; routine 0 (ETH_GETINFO) through the RAM helper and prints what came back.
;
; A successful run proves the whole Phase 4 chain: the EXTBIO hook is installed
; and chains correctly, the implementation reports its slot/segment/entry, the
; RAM helper can call into the segment, and the routine dispatch table works.
;
; Expected output with the Phase 4 driver:
;   Found: 01
;   API:   0101      (Ethernet UNAPI 1.1)
;   Impl:  0001      (this implementation, 0.1)
; =============================================================================

_TERM0:     equ     00h
_STROUT:    equ     09h
BDOS:       equ     0005h
EXTBIO:     equ     0FFCAh
ARG:        equ     0F847h

            org     100h

            ld      de,BANNER_S
            ld      c,_STROUT
            call    BDOS

; --- Locate the RAM helper (needed to call into the segment) ----------------
            ld      de,2222h
            ld      hl,0
            ld      a,0FFh
            call    EXTBIO
            ld      a,h
            or      l
            jr      nz,.helper_ok
            ld      de,NOHELPER_S
            jp      DIE
.helper_ok:
            ld      (HELPER_ADD),hl

; --- Count installed ETHERNET implementations ------------------------------
            ld      hl,UNAPI_ID
            ld      de,ARG
            ld      bc,UNAPI_ID_LEN
            ldir

            ld      de,2222h
            xor     a
            ld      b,0
            call    EXTBIO
            ld      a,b
            ld      (COUNT),a

            ld      de,FOUND_S
            ld      c,_STROUT
            call    BDOS
            ld      a,(COUNT)
            call    PRINT_HEX8
            call    NEWLINE

            ld      a,(COUNT)
            or      a
            jr      nz,.have_one
            ld      de,NONE_S
            jp      DIE
.have_one:

; --- Ask implementation 1 where it lives -----------------------------------
            ld      de,2222h
            ld      a,1
            call    EXTBIO
            ld      (IMP_SLOT),a
            ld      a,b
            ld      (IMP_SEG),a
            ld      (IMP_ENTRY),hl

; --- Call routine 0 (ETH_GETINFO) through the helper's CALL_MAP ------------
; CALL_MAP is at helper+0: A = routine number, IYh = slot, IYl = segment,
; IX = address to call.
            ld      a,(IMP_SLOT)
            ld      iyh,a
            ld      a,(IMP_SEG)
            ld      iyl,a
            ld      ix,(IMP_ENTRY)
            ld      hl,(HELPER_ADD)
            xor     a                   ; routine 0 = ETH_GETINFO
            call    CALL_HL
            ld      (RET_DE),de
            ld      (RET_BC),bc

            ld      de,API_S
            ld      c,_STROUT
            call    BDOS
            ld      a,(RET_DE+1)
            call    PRINT_HEX8
            ld      a,(RET_DE)
            call    PRINT_HEX8
            call    NEWLINE

            ld      de,IMPL_S
            ld      c,_STROUT
            call    BDOS
            ld      a,(RET_BC+1)
            call    PRINT_HEX8
            ld      a,(RET_BC)
            call    PRINT_HEX8
            call    NEWLINE

; --- Routines that actually cross the wire ---------------------------------
; Everything above is answered from inside the segment.  These two are the
; first traffic on the $C0-$CF opcode protocol, so they are what proves the
; MSX driver and msxpi_eth.py agree.

            ld      de,MAC_S
            ld      c,_STROUT
            call    BDOS
            ld      a,2                     ; ETH_GET_HWADD
            call    CALL_UNAPI
            ; Returns L-H-E-D-C-B = address bytes 0..5, in that order, which is
            ; exactly the layout of three consecutive little-endian words - so
            ; they must be stored into ADJACENT locations (RET_HL, RET_DE2,
            ; RET_BC2), not into the scattered ones used for GETINFO above.
            ld      (RET_HL),hl
            ld      (RET_DE2),de
            ld      (RET_BC2),bc
            ld      hl,RET_HL
            ld      b,6
.macloop:
            ld      a,(hl)
            push    hl
            push    bc
            call    PRINT_HEX8
            pop     bc
            pop     hl
            inc     hl
            djnz    .macloop
            call    NEWLINE

            ld      de,NETSTAT_S
            ld      c,_STROUT
            call    BDOS
            ld      a,3                     ; ETH_GET_NETSTAT
            call    CALL_UNAPI
            call    PRINT_HEX8
            call    NEWLINE

            ld      de,INSTAT_S
            ld      c,_STROUT
            call    BDOS
            ld      a,7                     ; ETH_IN_STATUS
            call    CALL_UNAPI
            call    PRINT_HEX8
            call    NEWLINE

; --- The device must be left out of wait mode ------------------------------
; While wait mode is on, $57 reads $8E, and msxpi_bios.asm:97 decides "is this
; openMSX?" by testing $57 against $FE.  A driver that leaked wait mode would
; silently break every other piece of MSXPi software, so check it explicitly.
            ld      de,PORT57_S
            ld      c,_STROUT
            call    BDOS
            in      a,(057h)
            call    PRINT_HEX8
            call    NEWLINE

            ld      c,_TERM0
            jp      BDOS

; --- CALL_UNAPI: invoke routine A in the implementation, via the RAM helper.
; Preserves nothing in particular; returns whatever the routine returns.
CALL_UNAPI:
            push    af
            ld      a,(IMP_SLOT)
            ld      iyh,a
            ld      a,(IMP_SEG)
            ld      iyl,a
            ld      ix,(IMP_ENTRY)
            ld      hl,(HELPER_ADD)
            pop     af
            jp      (hl)

DIE:
            ld      c,_STROUT
            call    BDOS
            ld      c,_TERM0
            jp      BDOS

CALL_HL:    jp      (hl)

; --- Print A as two hex digits ---------------------------------------------
PRINT_HEX8:
            push    af
            rrca
            rrca
            rrca
            rrca
            call    .nibble
            pop     af
.nibble:
            and     0Fh
            add     a,"0"
            cp      "9"+1
            jr      c,.emit
            add     a,7
.emit:
            ld      e,a
            ld      c,02h               ; BDOS console output
            push    hl
            call    BDOS
            pop     hl
            ret

NEWLINE:
            ld      de,CRLF_S
            ld      c,_STROUT
            jp      BDOS

; --- Data -------------------------------------------------------------------
HELPER_ADD: dw      0
COUNT:      db      0
IMP_SLOT:   db      0
IMP_SEG:    db      0
IMP_ENTRY:  dw      0
RET_DE:     dw      0
RET_BC:     dw      0
RET_HL:     dw      0
RET_DE2:    dw      0
RET_BC2:    dw      0

UNAPI_ID:   db      "ETHERNET",0
UNAPI_ID_LEN: equ   $-UNAPI_ID

BANNER_S:   db      "ETHTEST - Ethernet UNAPI discovery",13,10,13,10,"$"
FOUND_S:    db      "Found: $"
API_S:      db      "API:   $"
IMPL_S:     db      "Impl:  $"
NOHELPER_S: db      "*** No RAM helper installed.",13,10,"$"
NONE_S:     db      "*** No ETHERNET implementation found.",13,10,"$"
MAC_S:      db      "MAC:   $"
NETSTAT_S:  db      "Net:   $"
INSTAT_S:   db      "InSt:  $"
PORT57_S:   db      "P57:   $"
CRLF_S:     db      13,10,"$"
