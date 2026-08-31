; =============================================================================
; ETHBENCH.COM - measure the UNAPI transport, polled vs hardware /WAIT
; =============================================================================
; Answers one question: what is hardware /WAIT actually worth on real hardware?
;
; Times the SAME loop under each transport backend on the SAME machine, with
; NOTHING printed inside the timed section - so unlike the `p run cat`
; measurement there is no screen output, no block protocol and no disk in the
; way. Just N UNAPI calls, each one opcode byte out and two bytes back.
;
; ETH_GET_NETSTAT is used rather than ETH_IN_STATUS on purpose: it returns A=1
; when the link answered and A=0 when it did not, so a pass that silently
; failed can be told apart from a fast one. ETH_IN_STATUS returns 0 both for
; "no frames waiting" and for "the transaction failed", which would make a
; completely broken pass look like the best result in the table.
;
; Uses implementation-specific routine 128 to force the backend, which is why
; that routine exists.
;
; Reading the result: each line prints ELAPSED JIFFIES then OK COUNT, both hex.
;
;   The OK count MUST equal ITERATIONS (0800h). Anything less means that pass
;   did not really talk to the Pi and its timing is meaningless.
;
;   jiffies are 1/60 s (1/50 on a PAL machine), and each call moves 3 bytes:
;       us/byte = jiffies * 16667 / (ITERATIONS * 3)
;   With ITERATIONS = 2048 that is 6144 bytes per pass:
;       ~370 jiffies (016Ah) -> ~1000 us/byte, what the legacy path costs today
;       ~17  jiffies (0011h) -> ~46   us/byte, what /WAIT should give
;   A /WAIT figure close to the polled one means /WAIT is NOT the win the
;   profiler implied, and the ~950 us/byte lives somewhere else entirely.
; =============================================================================

_TERM0:     equ     00h
_STROUT:    equ     09h
BDOS:       equ     0005h
EXTBIO:     equ     0FFCAh
ARG:        equ     0F847h
JIFFY:      equ     0FC9Eh

ITERATIONS: equ     2048

FN_RESET:      equ  1
FN_GET_NETSTAT: equ 3
FN_SET_MODE:   equ  128         ; implementation-specific
MODE_REPORT:    equ 0
MODE_POLL_HW:   equ 1
MODE_WAIT:      equ 2
MODE_POLL_OMSX: equ 3

CTRL1:          equ 56h
RESET_MSXPI:    equ 0FFh

            org     100h

            ld      de,BANNER_S
            ld      c,_STROUT
            call    BDOS

; --- Locate the RAM helper and the implementation ---------------------------
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

            ld      hl,UNAPI_ID
            ld      de,ARG
            ld      bc,UNAPI_ID_LEN
            ldir

            ld      de,2222h
            xor     a
            ld      b,0
            call    EXTBIO
            ld      a,b
            or      a
            jr      nz,.have_one
            ld      de,NONE_S
            jp      DIE
.have_one:
            ld      de,2222h
            ld      a,1
            call    EXTBIO
            ld      (IMP_SLOT),a
            ld      a,b
            ld      (IMP_SEG),a
            ld      (IMP_ENTRY),hl

; --- Remember the mode the driver chose, so it can be put back --------------
            ld      b,MODE_REPORT
            ld      a,FN_SET_MODE
            call    CALL_UNAPI
            ld      (ORIG_MODE),a

; --- Control: time a pure delay loop that touches nothing ------------------
; If this reads 0000 then JIFFY is not advancing at all and EVERY figure below
; is void - which is exactly what happened when the driver's lock left
; interrupts disabled: the transfers worked, but the clock had stopped.
; Expect roughly 001A (26) jiffies here.
            ld      de,CTRL_S
            ld      c,_STROUT
            call    BDOS
            ld      hl,(JIFFY)
            ld      (T_START),hl
            ld      bc,0                    ; 65536 iterations, ~0.44 s
.delay:
            dec     bc
            ld      a,b
            or      c
            jr      nz,.delay
            ld      hl,(JIFFY)
            ld      de,(T_START)
            or      a
            sbc     hl,de
            ld      a,h
            call    PRINT_HEX8
            ld      a,l
            call    PRINT_HEX8
            call    NEWLINE

; --- All three backends -----------------------------------------------------
; Only one polled backend can work on any given machine - MODE_POLL_HW on real
; hardware, MODE_POLL_OMSX under openMSX - and there is no reliable way to ask
; from here.  So run all three and let the OK count say which figures are real.
            ld      de,WAIT_S
            ld      c,_STROUT
            call    BDOS
            ld      b,MODE_WAIT
            call    RUN_PASS

            ld      de,POLLED_S
            ld      c,_STROUT
            call    BDOS
            ld      b,MODE_POLL_HW
            call    RUN_PASS

            ld      de,POLLOM_S
            ld      c,_STROUT
            call    BDOS
            ld      b,MODE_POLL_OMSX
            call    RUN_PASS

; --- Restore whatever the installer had detected ----------------------------
            ld      a,(ORIG_MODE)
            inc     a                       ; routine 128 takes mode+1
            ld      b,a
            ld      a,FN_SET_MODE
            call    CALL_UNAPI

            ld      de,DONE_S
            ld      c,_STROUT
            call    BDOS
            ld      c,_TERM0
            jp      BDOS

; --- RUN_PASS: force mode B, time ITERATIONS calls, print the jiffy count ----
; Nothing is printed between the two JIFFY reads.
RUN_PASS:
            push    bc
            ; Resynchronise the device first.  A pass that failed leaves reply
            ; bytes the MSX never collected, and the next pass would read those
            ; stale bytes instead of its own.  Writing $FF to $56 is the
            ; existing MSXPi reset: it clears the CPLD transfer state, and
            ; under openMSX it also empties the receive queue.  It clears wait
            ; mode too, which is harmless - ETH_BEGIN re-enables it per
            ; transaction.
            ld      a,RESET_MSXPI
            out     (CTRL1),a
            pop     bc

            ld      a,FN_SET_MODE
            call    CALL_UNAPI

            ; Clear the dead-link latch first.  One timeout in a previous pass
            ; sets ETH_DEAD, after which every later call returns instantly
            ; without touching the port - which would look like a spectacular
            ; result instead of a total failure.
            ld      a,FN_RESET
            call    CALL_UNAPI

            ld      hl,0
            ld      (OK_COUNT),hl

            ld      hl,(JIFFY)
            ld      (T_START),hl

            ld      bc,ITERATIONS
.loop:
            push    bc
            ld      a,FN_GET_NETSTAT
            call    CALL_UNAPI
            ; Force interrupts back on.  We are unambiguously in foreground
            ; here, so this is safe - and the UNAPI RAM helper has to disable
            ; them while it swaps the mapper segment.  If it restores IFF2 with
            ; `ld a,i` it hits the erratum that clears P/V when an interrupt
            ; lands during the instruction, and after the first occurrence
            ; interrupts stay off: JIFFY stops, and every timing below reads
            ; zero while the transfers themselves keep working.  That is
            ; exactly the signature this benchmark kept producing.
            ei
            or      a                       ; A=1 link answered, 0 it did not
            jr      z,.notok
            ld      hl,(OK_COUNT)
            inc     hl
            ld      (OK_COUNT),hl
.notok:
            pop     bc
            dec     bc
            ld      a,b
            or      c
            jr      nz,.loop

            ld      hl,(JIFFY)
            ld      de,(T_START)
            or      a
            sbc     hl,de                   ; elapsed jiffies
            ld      a,h
            call    PRINT_HEX8
            ld      a,l
            call    PRINT_HEX8

            ld      de,OK_S
            ld      c,_STROUT
            call    BDOS
            ld      hl,(OK_COUNT)
            ld      a,h
            call    PRINT_HEX8
            ld      a,l
            call    PRINT_HEX8
            call    NEWLINE
            ret

; --- CALL_UNAPI: invoke routine A via the RAM helper ------------------------
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
            ld      c,02h
            push    hl
            push    bc
            call    BDOS
            pop     bc
            pop     hl
            ret

NEWLINE:
            ld      de,CRLF_S
            ld      c,_STROUT
            push    bc
            call    BDOS
            pop     bc
            ret

; --- Data -------------------------------------------------------------------
HELPER_ADD: dw      0
IMP_SLOT:   db      0
IMP_SEG:    db      0
IMP_ENTRY:  dw      0
T_START:    dw      0
OK_COUNT:   dw      0
ORIG_MODE:  db      0

UNAPI_ID:   db      "ETHERNET",0
UNAPI_ID_LEN: equ   $-UNAPI_ID

BANNER_S:   db      "ETHBENCH - 2048 x ETH_GET_NETSTAT",13,10
            db      "jiffies then OK count, hex.",13,10
            db      "OK must be 0800 or timing is void.",13,10,13,10,"$"
CTRL_S:     db      "ctrl:   $"
POLLED_S:   db      "poll-hw:$"
POLLOM_S:   db      "poll-om:$"
WAIT_S:     db      "/WAIT:  $"
DONE_S:     db      "done.",13,10,"$"
NOHELPER_S: db      "*** No RAM helper installed.",13,10,"$"
NONE_S:     db      "*** No ETHERNET implementation found.",13,10,"$"
OK_S:       db      "  ok=$"
CRLF_S:     db      13,10,"$"
