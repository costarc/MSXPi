; =============================================================================
; MSXPi Ethernet UNAPI - resident code
; =============================================================================
; This is the part that lives in a mapped RAM segment.  It is assembled as a
; standalone binary at 4000h and INCBIN'd by the installer (ethunapi.asm),
; because sjasm 0.39j has no phase/disp directive.  The installer reads the
; symbol addresses it needs to patch from the export file sjasm writes.
;
; Structure follows examples/unapi-ram.asm from the MSX-UNAPI specification.
;
; Layout: this file holds the EXTBIO hook, the routine dispatch table and
; ETH_GETINFO; ethtrans.asm holds the ISR-safe transport core; ethops.asm holds
; the other eleven ETH_* routines.
; =============================================================================

EXTBIO:     equ     0FFCAh
ARG:        equ     0F847h

; Ethernet UNAPI specification version implemented (1.1)
API_V_P:    equ     1
API_V_S:    equ     1
; This implementation's own version
IMP_V_P:    equ     0
IMP_V_S:    equ     1

; Highest standard routine number.  The Ethernet UNAPI defines routines 0..11
; (ETH_GETINFO through ETH_SET_HWADD).  No implementation-specific routines.
MAX_FN:     equ     11
; One implementation-specific routine, 128: force the transport mode.  Purely a
; diagnostic - it exists so a benchmark can measure polled against hardware
; /WAIT on the same machine in the same run.
MAX_IMPFN:  equ     128

            org     4000h

SEG_CODE_START:

; =============================================================================
; EXTBIO hook execution - MUST be at 4000h
; =============================================================================
; The RAM helper's segment-call routine enters here.  Per MSX-UNAPI 3.3 the
; rules are: not our DE -> chain; A=FFh -> chain (lets the RAM helper install);
; wrong API id -> chain; A=0 -> B=B+1 and chain; A=1 -> answer; A>1 -> A=A-1
; and chain.
DO_EXTBIO:
            push    hl
            push    bc
            push    af

            ld      a,d
            cp      22h
            jr      nz,JUMP_OLD
            cp      e                   ; DE must be 2222h
            jr      nz,JUMP_OLD

            ; --- Compare the identifier at ARG with ours, case-insensitively
            ld      hl,UNAPI_ID
            ld      de,ARG
ID_LOOP:
            ld      a,(de)
            call    TOUPPER
            cp      (hl)
            jr      nz,JUMP_OLD2
            inc     hl
            inc     de
            or      a                   ; both ended at the terminating zero?
            jr      nz,ID_LOOP

            ; --- A=FFh: chain, so the RAM helper can install
            pop     af
            push    af
            inc     a
            jr      z,JUMP_OLD2

            ; --- A=0: count us and chain
            pop     af
            pop     bc
            or      a
            jr      nz,DO_EXTBIO2
            inc     b
            pop     hl
            ld      de,2222h
            jp      OLD_EXTBIO
DO_EXTBIO2:

            ; --- A=1: report slot, segment and entry point.  Do NOT chain.
            dec     a
            jr      nz,DO_EXTBIO3
            pop     hl
            ld      a,(MY_SEG)
            ld      b,a
            ld      a,(MY_SLOT)
            ld      hl,UNAPI_ENTRY
            ld      de,2222h
            ret

            ; --- A>1: decrement (already done) and chain
DO_EXTBIO3:
            pop     hl
            ld      de,2222h
            jp      OLD_EXTBIO

JUMP_OLD2:
            ld      de,2222h
JUMP_OLD:
            pop     af
            pop     bc
            pop     hl
            ; Falls through into the saved hook, patched at install time.

OLD_EXTBIO:
            ds      5

; --- Patched by the installer once the segment is allocated -----------------
MY_SLOT:    db      0
MY_SEG:     db      0

TOUPPER:
            cp      "a"
            ret     c
            cp      "z"+1
            ret     nc
            sub     20h
            ret

; =============================================================================
; UNAPI entry point
; =============================================================================
; A = routine number.  Dispatches through FN_TABLE, leaving every other
; register untouched so each routine sees exactly what the caller passed.
; An out-of-range routine number returns with all registers unmodified, as the
; specification requires.
UNAPI_ENTRY:
            push    hl
            push    af
            ld      hl,FN_TABLE
            bit     7,a
            jr      z,.standard
            ld      hl,IMPFN_TABLE      ; 128.. : implementation-specific
            and     01111111b
            cp      MAX_IMPFN-128
            jr      z,OK_FNUM
            jr      nc,UNDEFINED
            jr      OK_FNUM
.standard:
            cp      MAX_FN
            jr      z,OK_FNUM
            jr      nc,UNDEFINED
OK_FNUM:
            add     a,a
            push    de
            ld      e,a
            ld      d,0
            add     hl,de
            pop     de
            ld      a,(hl)
            inc     hl
            ld      h,(hl)
            ld      l,a
            pop     af
            ex      (sp),hl
            ret

UNDEFINED:
            pop     af
            pop     hl
            ret

; =============================================================================
; Routine table
; =============================================================================
FN_TABLE:
            dw      FN_GETINFO          ; 0  ETH_GETINFO
            dw      FN_RESET            ; 1  ETH_RESET
            dw      FN_GET_HWADD        ; 2  ETH_GET_HWADD
            dw      FN_GET_NETSTAT      ; 3  ETH_GET_NETSTAT
            dw      FN_NET_ONOFF        ; 4  ETH_NET_ONOFF
            dw      FN_DUPLEX           ; 5  ETH_DUPLEX
            dw      FN_FILTERS          ; 6  ETH_FILTERS
            dw      FN_IN_STATUS        ; 7  ETH_IN_STATUS
            dw      FN_GET_FRAME        ; 8  ETH_GET_FRAME
            dw      FN_SEND_FRAME       ; 9  ETH_SEND_FRAME
            dw      FN_OUT_STATUS       ; 10 ETH_OUT_STATUS
            dw      FN_SET_HWADD        ; 11 ETH_SET_HWADD

; --- Implementation-specific ------------------------------------------------
IMPFN_TABLE:
            dw      FN_SET_MODE         ; 128 force/report the transport mode

; =============================================================================
; Routines
; =============================================================================

; --- 0: ETH_GETINFO --------------------------------------------------------
; Mandatory and fully implemented even in Phase 4: the installer's
; already-installed check calls it, and so does every discovery client.
FN_GETINFO:
            ld      hl,APIINFO
            ld      de,API_V_P*256+API_V_S
            ld      bc,IMP_V_P*256+IMP_V_S
            ret

; The remaining routines live in ethops.asm, included after the transport
; core below - they need ETH_TX/ETH_RX and the lock, which are defined there.

; =============================================================================
; Data
; =============================================================================

; Cache for the address fetched from the Pi via OP_GET_HWADD.
;
; Deliberately all zeros, NOT msxpi_eth.BaseLink's 02:4D:53:58:50:69 default.
; ETH_GET_HWADD falls back to this cache when the transaction fails, so seeding
; it with the value the Pi would have sent made a dead link indistinguishable
; from a live one - a diagnostic printed the "correct" MAC either way. With
; zeros here, a non-zero address is proof that a real fetch succeeded.
MACADDR:    db      000h,000h,000h,000h,000h,000h

; The identifier must be zero-terminated and is compared case-insensitively.
UNAPI_ID:
            db      "ETHERNET",0
UNAPI_ID_END:

; At most 63 characters plus the terminating zero, printable only, and it must
; live in the same segment as the code (MSX-UNAPI rule 5).
APIINFO:
            db      "MSXPi Ethernet UNAPI",0

; =============================================================================
; Transport core (Phase 5a)
; =============================================================================
            include "ethtrans.asm"
            include "ethops.asm"

SEG_CODE_END:

            export  DO_EXTBIO
            export  OLD_EXTBIO
            export  MY_SLOT
            export  MY_SEG
            export  UNAPI_ENTRY
            export  APIINFO
            export  UNAPI_ID
            export  UNAPI_ID_END
            export  SEG_CODE_START
            export  SEG_CODE_END
            export  ETH_MODE
            export  ETH_VERIFY
