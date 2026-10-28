; MSXPi Interface
; Version 1.7.0
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
; ETHBENCH S replaces those passes with ETH_SEND_FRAME: SEND_ITER frames at
; each length in SEND_LENS, under /WAIT (OTIR) and then polled.  The lengths
; straddle the 256-byte runs ETH_TX_BLOCK splits a frame into, and the Pi
; checks every frame's checksum, so ok=SEND_ITER says each length arrived
; byte-exact under both backends.  The frames go out on the real network: an
; unused locally administered destination, ethertype 88B5 (IEEE "local
; experimental"), so nothing on the LAN acts on them.
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
CALSLT:     equ     001Ch
EXTBIO:     equ     0FFCAh
ARG:        equ     0F847h
JIFFY:      equ     0FC9Eh

ITERATIONS: equ     2048

FN_RESET:       equ 1
FN_GET_NETSTAT: equ 3          ; 3 bytes on the wire: opcode + RC + state
FN_GET_HWADD:   equ 2          ; 8 bytes: opcode + RC + six address bytes
FN_SEND_FRAME:  equ 9
SEND_ITER:      equ 32          ; frames per length in ETHBENCH S
MAX_SEND:       equ 1514
FN_SET_MODE:   equ  128         ; implementation-specific
MODE_REPORT:    equ 0
MODE_POLL_HW:   equ 1
MODE_WAIT:      equ 2

CTRL1:          equ 56h
RESET_MSXPI:    equ 0FFh

            org     100h

            ld      de,BANNER_S
            ld      c,_STROUT
            call    BDOS

; --- Locate the RAM helper and the implementation ---------------------------
; A missing helper is not fatal: a ROM implementation reports segment FFh and
; is reached with CALSLT.  Only a RAM one needs the helper, checked below once
; the segment is known.
            ld      de,2222h
            ld      hl,0
            ld      a,0FFh
            call    EXTBIO
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

            inc     a                       ; segment FFh -> in ROM
            jr      z,.callable
            ld      hl,(HELPER_ADD)
            ld      a,h
            or      l
            jr      nz,.callable
            ld      de,NOHELPER_S
            jp      DIE
.callable:

; --- Remember the mode the driver chose, so it can be put back --------------
            ld      b,MODE_REPORT
            ld      a,FN_SET_MODE
            call    CALL_UNAPI
            ld      (ORIG_MODE),a
            ; 2 = refused: the Pi speaks another protocol version.  Forcing a
            ; mode below would override that and benchmark a link the driver
            ; has rightly given up on, so stop here instead.
            cp      2
            ld      de,REFUSED_S
            jp      z,DIE

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

            call    HAS_S_ARG
            jr      z,.sends

; --- Both backends ----------------------------------------------------------
; The OK count says whether a pass's figures are real.  Each backend is measured at TWO payload sizes.  A transaction costs
; fixed + n*b, and with a single size those cannot be separated - which is how
; a 7% difference got mistaken for the whole story.  ETH_GET_NETSTAT moves 3
; bytes and ETH_GET_HWADD moves 8, so:
;
;     b     = (t8 - t3) / 5        per-byte cost
;     fixed = t3 - 3*b             per-transaction overhead
;
; The per-byte figure is what decides frame throughput in Phase 6; the fixed
; cost is Python dispatch on the Pi and is paid once per frame, not per byte.
            ld      a,FN_GET_NETSTAT
            ld      (BENCH_FN),a
            ld      de,WAIT3_S
            ld      c,_STROUT
            call    BDOS
            ld      b,MODE_WAIT
            call    RUN_PASS

            ld      a,FN_GET_HWADD
            ld      (BENCH_FN),a
            ld      de,WAIT8_S
            ld      c,_STROUT
            call    BDOS
            ld      b,MODE_WAIT
            call    RUN_PASS

            ld      a,FN_GET_NETSTAT
            ld      (BENCH_FN),a
            ld      de,POLL3_S
            ld      c,_STROUT
            call    BDOS
            ld      b,MODE_POLL_HW
            call    RUN_PASS

            ld      a,FN_GET_HWADD
            ld      (BENCH_FN),a
            ld      de,POLL8_S
            ld      c,_STROUT
            call    BDOS
            ld      b,MODE_POLL_HW
            call    RUN_PASS
            jr      .restore

; --- ETHBENCH S: ETH_SEND_FRAME at every length in SEND_LENS ----------------
.sends:
            ld      de,SENDHDR_S
            ld      c,_STROUT
            call    BDOS
            ld      hl,SEND_ITER
            ld      (PASS_ITER),hl
            ld      a,FN_SEND_FRAME
            ld      (BENCH_FN),a
            call    FILL_SENDBUF
            ld      b,MODE_WAIT
            call    SEND_TABLE
            ld      b,MODE_POLL_HW
            call    SEND_TABLE

; --- Restore whatever the installer had detected ----------------------------
.restore:
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
            ; existing MSXPi reset: it clears the CPLD transfer state.  It clears wait
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

            ld      bc,(PASS_ITER)
.loop:
            push    bc
            ld      a,(BENCH_FN)
            cp      FN_SEND_FRAME
            jr      nz,.call
            ld      hl,SENDBUF
            ld      bc,(SEND_LEN)
            ld      d,0                     ; synchronous
.call:
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
            ; ETH_GET_NETSTAT reports success in A; ETH_GET_HWADD returns the
            ; address in L-H-E-D-C-B, and L is non-zero only on a real fetch
            ; because the cache is seeded with zeros.  ETH_SEND_FRAME returns
            ; 0 when sent, so that one is turned round: A=0 -> FFh.
            ld      c,a
            ld      a,(BENCH_FN)
            cp      FN_SEND_FRAME
            jr      z,.sent
            cp      FN_GET_HWADD
            ld      a,c
            jr      nz,.checka
            ld      a,l
            jr      .checka
.sent:
            ld      a,c
            sub     1
            sbc     a,a
.checka:
            or      a
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

; --- SEND_TABLE: one RUN_PASS per length in SEND_LENS, under mode B ---------
; Each line is labelled with the backend and the length: "W-05EA: ".
SEND_TABLE:
            ld      a,b
            ld      (SEND_MODE),a
            ld      hl,SEND_LENS
.next:
            ld      e,(hl)
            inc     hl
            ld      d,(hl)
            inc     hl
            ld      a,d
            or      e
            ret     z
            ld      (SEND_LEN),de
            push    hl
            ld      a,(SEND_MODE)
            ld      e,"W"
            cp      MODE_WAIT
            jr      z,.label
            ld      e,"P"
.label:
            ld      c,02h
            call    BDOS
            ld      e,"-"
            ld      c,02h
            call    BDOS
            ld      a,(SEND_LEN+1)
            call    PRINT_HEX8
            ld      a,(SEND_LEN)
            call    PRINT_HEX8
            ld      de,COLON_S
            ld      c,_STROUT
            call    BDOS
            ld      a,(SEND_MODE)
            ld      b,a
            call    RUN_PASS
            pop     hl
            jr      .next

; --- FILL_SENDBUF: a 1514-byte frame - header, then each byte its own address's
; low byte, so a dropped or doubled byte changes the checksum.
FILL_SENDBUF:
            ld      hl,SENDBUF
            ld      bc,MAX_SEND
.fill:
            ld      (hl),l
            inc     hl
            dec     bc
            ld      a,b
            or      c
            jr      nz,.fill
            ld      hl,SEND_HDR
            ld      de,SENDBUF
            ld      bc,SEND_HDR_LEN
            ldir
            ret

; --- HAS_S_ARG: Z if the command line holds an S (either case).
HAS_S_ARG:
            ld      hl,80h
            ld      b,(hl)
            inc     b
.scan:
            dec     b
            jr      z,.none
            inc     hl
            ld      a,(hl)
            and     0DFh
            cp      "S"
            ret     z
            jr      .scan
.none:
            or      1                       ; NZ
            ret

; --- CALL_UNAPI: invoke routine A -------------------------------------------
; Segment FFh means the implementation is in ROM and is reached with a plain
; inter-slot call; anything else is a mapped RAM segment and goes through the
; RAM helper's CALL_MAP.  Which one is in use matters to the numbers this
; program prints: the helper's CALL_MAP costs a segment switch per call and
; returns with interrupts disabled, CALSLT does neither.
;
; The helper is entered through the stack, not `jp (hl)`: HL is an input of
; ETH_SEND_FRAME, and loading the helper's address into it would send the
; frame from wherever the helper lives.
CALL_UNAPI:
            push    af
            ld      a,(IMP_SLOT)
            ld      iyh,a
            ld      ix,(IMP_ENTRY)
            ld      a,(IMP_SEG)
            inc     a
            jr      z,.rom
            dec     a
            ld      iyl,a
            pop     af
            push    hl
            ld      hl,(HELPER_ADD)
            ex      (sp),hl
            ret
.rom:
            pop     af
            call    CALSLT
            ei
            ret

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
BENCH_FN:   db      3
PASS_ITER:  dw      ITERATIONS
SEND_LEN:   dw      0
SEND_MODE:  db      0

; The limits, and both sides of the 256-byte runs ETH_TX_BLOCK's OTIR makes.
SEND_LENS:  dw      16, 64, 255, 256, 257, 512, 513, 1514, 0

SEND_HDR:   db      02h,00h,00h,00h,00h,01h     ; nobody: locally administered
            db      02h,4Dh,53h,58h,50h,69h     ; the driver's MAC
            db      88h,0B5h                    ; IEEE local experimental
SEND_HDR_LEN: equ   $-SEND_HDR

UNAPI_ID:   db      "ETHERNET",0
UNAPI_ID_LEN: equ   $-UNAPI_ID

BANNER_S:   db      "ETHBENCH - 2048 x ETH_GET_NETSTAT",13,10
            db      "jiffies then OK count, hex.",13,10
            db      "OK must be 0800 or timing is void.",13,10,13,10,"$"
CTRL_S:     db      "ctrl:   $"
WAIT3_S:    db      "W-3by:  $"
WAIT8_S:    db      "W-8by:  $"
POLL3_S:    db      "P-3by:  $"
POLL8_S:    db      "P-8by:  $"
POLLED_S:   db      "poll-hw:$"
POLLOM_S:   db      "poll-om:$"
WAIT_S:     db      "/WAIT:  $"
DONE_S:     db      "done.",13,10,"$"
NOHELPER_S: db      "*** No RAM helper installed.",13,10,"$"
REFUSED_S:  db      "*** The Pi's msxpi-server speaks another Ethernet",13,10
            db      "    protocol version than this ROM. Update the Pi",13,10
            db      "    and the ROM together, then run ETHTEST again.",13,10,"$"
NONE_S:     db      "*** No ETHERNET implementation found.",13,10,"$"
OK_S:       db      "  ok=$"
SENDHDR_S:  db      "ETH_SEND_FRAME, 0020 frames a line:",13,10
            db      "W/P-length: jiffies, ok must be 0020.",13,10,"$"
COLON_S:    db      ": $"
CRLF_S:     db      13,10,"$"

; Past the end of the image: the TPA is free from here.
SENDBUF:    equ     $
