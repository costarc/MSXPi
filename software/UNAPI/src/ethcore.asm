; =============================================================================
; MSXPi Ethernet UNAPI - entry point, dispatch table and transport detection
; =============================================================================
; Everything in this file is identical in the RAM (mapped segment) and ROM
; (MSX-DOS driver ROM) builds.  What differs between them lives in the two
; top-level files that include this one:
;
;   ethseg.asm   RAM build - org 4000h, EXTBIO hook entered by the RAM helper,
;                state block inside the segment, reports its own slot/segment
;   ethrom.asm   ROM build - org UNAPI_ORG inside msxpibios.rom, EXTBIO hook
;                entered by RST 30h, state in the disk driver work area,
;                reports segment FFh
;
; Each of them must define:
;   ETH_WRK   set IX to the base of the work area (may corrupt AF, BC, HL)
;   APIINFO   the implementation's zero-terminated description string
; =============================================================================

; Ethernet UNAPI specification version implemented (1.1)
API_V_P:    equ     1
API_V_S:    equ     1
; This implementation's own version
IMP_V_P:    equ     0
IMP_V_S:    equ     1

; Highest standard routine number.  The Ethernet UNAPI defines routines 0..11
; (ETH_GETINFO through ETH_SET_HWADD).
MAX_FN:     equ     11
; Two implementation-specific routines:
;   128  force/report the transport mode.  Purely a diagnostic: it exists so a
;        benchmark can measure polled against hardware /WAIT on the same
;        machine in the same run.
;   129  claim/release the shared MSXPi link, so that a .COM using the link for
;        its own traffic is not cut across by this driver's ISR polling.  See
;        FN_LINK_CLAIM in ethops.asm for why that is needed.
MAX_IMPFN:  equ     129

; =============================================================================
; UNAPI entry point
; =============================================================================
; A = routine number.  Dispatches through FN_TABLE, leaving every other
; register untouched so each routine sees exactly what the caller passed.
; An out-of-range routine number returns with all registers unmodified, as the
; specification requires.
;
; IX is set here, once, and every routine reads and writes its state through
; it.  That is allowed: MSX-UNAPI 2.3 says IX and IY "must not be used for
; input parameters" and are corrupted on return, precisely so that inter-slot
; and inter-segment calls can use them.
;
; The transport probe also happens here rather than at installation time.  In
; the ROM build the driver is initialised from the disk ROM's INIENV, which
; runs while the Pi is usually still booting - a probe there would fail and
; pin us to the slow backend for the whole session.  By the first UNAPI call
; the machine has booted from the Pi, so the link is known good.
UNAPI_ENTRY:
            push    af
            push    bc
            push    de
            push    hl
            call    ETH_WRK                 ; IX = work area
            ld      a,(ix+o_ETH_MODE)
            inc     a                       ; MODE_UNKNOWN ($FF) -> 0
            call    z,ETH_DETECT
            pop     hl
            pop     de
            pop     bc
            pop     af

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

; --- WRKPTR: HL = IX + A, for the few places that need the address of a work
; area field rather than its contents.  A is an unsigned offset.
; Corrupts AF and HL; everything else, IX included, is preserved.
WRKPTR:
            push    ix
            pop     hl
            add     a,l
            ld      l,a
            ret     nc
            inc     h
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
            dw      FN_LINK_CLAIM       ; 129 claim/release the shared link

; --- 0: ETH_GETINFO --------------------------------------------------------
; Mandatory and implemented from the very first phase: the installer's
; already-installed check calls it, and so does every discovery client.
FN_GETINFO:
            ld      hl,APIINFO
            ld      de,API_V_P*256+API_V_S
            ld      bc,IMP_V_P*256+IMP_V_S
            ret

; =============================================================================
; Transport detection
; =============================================================================
; In: IX = work area.  Out: (ix+o_ETH_MODE) set, wait mode off, failure
; counters cleared.  Corrupts AF, BC, DE, HL.
;
; ORDER MATTERS, AND NOT FOR TIDINESS.
;
; Wait mode must NEVER be enabled until a POLLED transaction has already
; succeeded, because the polled path is bounded and the wait path is not.
;
; The CPLD has no /WAIT timeout - `wait_assert <= wait_mode and SPI_RDY and
; spi_en and ...` - so /WAIT is held for exactly as long as the Pi holds
; RPI_READY high.  RPI_READY is a GPIO and KEEPS ITS LAST LEVEL when the
; server exits.  If it happens to be left high with nothing clocking, one
; IN ($5A) in wait mode stalls the Z80 for ever and the machine is dead until
; a power cycle.  Probing $57 does not protect against this: it proves the
; CPLD implements the mode register, not that anything is alive on the other
; end.
;
; A polled transaction cannot hang - every wait in it is counted - and it
; fails cleanly in exactly the case that matters: with RPI_READY stuck high
; and no clocking, $56 reads ready, the OUT starts a transfer, and the
; following bounded wait times out.
;
; So: work out which polled backend this device needs, prove the link with it,
; and only then try to upgrade to /WAIT - and prove that too, because on real
; hardware "the CPLD supports /WAIT" turned out not to mean "/WAIT works".
VER_WAIT_ON_OMSX: equ 0FFh      ; openMSX's wait-mode read-back (see ethtrans)

; Out: CF=0 a working backend was found, CF=1 nothing answered at all.  Every
; exit sets a usable mode either way, so a caller that does not care about the
; distinction can ignore the flag.
ETH_DETECT:
            call    .probe
            ; Back to the normal per-byte budget.  Until now it was whatever
            ; the zeroed work area gave us, which ETH_WAIT_READY reads as the
            ; longest possible wait - see ETH_TIMEOUT in ethtrans.asm for why
            ; the first transaction needs it.  Neither this nor ETH_REVIVE
            ; disturbs the carry flag .probe returned.
            ld      (ix+o_ETH_TMO),ETH_TIMEOUT/256
            jp      ETH_REVIVE          ; start clean: the probing itself
                                        ; counted as failures otherwise
.probe:
            call    ETH_POLLMODE
            call    ETH_VERIFY
            ret     c                   ; nothing answers at all

            ld      a,WAITMODE_ON
            out     (CTRL2),a
            in      a,(CTRL2)
            ld      b,a
            xor     a
            out     (CTRL2),a           ; never leave it on outside a
            ld      a,b                 ; transaction - see ethops.asm
            cp      VER_WAIT_ON         ; $8E - real CPLD v1.6
            jr      z,.trywait
            cp      VER_WAIT_ON_OMSX    ; $FF - openMSX
            jr      z,.trywait
            or      a                   ; CF=0: polled, and it works
            ret

.trywait:
            ld      (ix+o_ETH_MODE),MODE_WAIT
            call    ETH_VERIFY
            ret     nc                  ; /WAIT works, keep it
            ; It does not.  Back to the polled backend we already proved.

; --- ETH_POLLMODE: select the polled backend this device needs.
; Real hardware reads below $FE on $57; openMSX reads exactly $FE and needs
; the other polled backend, because there $56 = 2 (not 0) means "a byte is
; waiting".  Corrupts AF; always returns CF=0, which is what lets ETH_DETECT
; fall into it as its "/WAIT is not usable" exit.
ETH_POLLMODE:
            in      a,(CTRL2)
            cp      VER_OPENMSX
            ld      a,MODE_POLL_HW
            jr      c,.set
            ld      a,MODE_POLL_OMSX
.set:
            ld      (ix+o_ETH_MODE),a
            or      a                   ; CF=0
            ret
