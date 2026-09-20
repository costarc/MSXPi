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
; Expected output:
;   Found: 01
;   Slot:  8B  Seg: FF   (FF = in ROM, reached with CALSLT)
;   API:   0101      (Ethernet UNAPI 1.1)
;   Impl:  0001      (this implementation, 0.1)
; =============================================================================

_TERM0:     equ     00h
_STROUT:    equ     09h
BDOS:       equ     0005h
CALSLT:     equ     001Ch
EXTBIO:     equ     0FFCAh
ARG:        equ     0F847h

            org     100h

            ld      de,BANNER_S
            ld      c,_STROUT
            call    BDOS

            ; "ETHTEST T" = transmit self-test.  Kept behind an argument so the
            ; normal run is unchanged; putting a frame on the wire is a side
            ; effect nobody should get by accident.
            ld      a,(0080h)               ; DOS command tail length
            or      a
            jr      z,.no_arg
            ld      a,(0082h)
            and     11011111b               ; crude upper-case
            cp      "T"
            jr      nz,.no_arg
            ld      a,1
            ld      (SENDTEST),a
.no_arg:

; --- Locate the RAM helper -------------------------------------------------
; Not fatal if it is missing: an implementation in ROM reports segment FFh and
; is called with CALSLT, needing no helper at all.  Only a RAM implementation
; does, and that is checked once the segment is known.
            ld      de,2222h
            ld      hl,0
            ld      a,0FFh
            call    EXTBIO
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

; --- Report where it lives -------------------------------------------------
; The segment is the interesting number.  FFh means the implementation is in
; ROM, which is what makes stock clients - InterNestor Lite included - reach
; it with CALSLT instead of the RAM helper's segment call.
            ld      de,SLOT_S
            ld      c,_STROUT
            call    BDOS
            ld      a,(IMP_SLOT)
            call    PRINT_HEX8
            ld      de,SEG_S
            ld      c,_STROUT
            call    BDOS
            ld      a,(IMP_SEG)
            call    PRINT_HEX8
            call    NEWLINE

            ; A mapped segment can only be reached through the RAM helper.
            ld      a,(IMP_SEG)
            inc     a
            jr      z,.callable         ; FFh: CALSLT, no helper needed
            ld      hl,(HELPER_ADD)
            ld      a,h
            or      l
            jr      nz,.callable
            ld      de,NOHELPER_S
            jp      DIE
.callable:

; --- Call routine 0 (ETH_GETINFO) ------------------------------------------
            xor     a                   ; routine 0 = ETH_GETINFO
            call    CALL_UNAPI
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

; --- Which transport backend the driver settled on -------------------------
; Implementation-specific routine 128 with B=0 reports without changing
; anything.  Worth printing before the routines that cross the wire, because
; if those fail this says whether the driver even found a working backend.
            ld      de,MODE_S
            ld      c,_STROUT
            call    BDOS
            ld      b,0                     ; report only
            ld      a,128
            call    CALL_UNAPI
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
            ; BC = size of the oldest queued frame, HL = its bytes 12-13 (the
            ; ethertype).  Printing them matters as much as the flag: it is the
            ; only check that the length and ethertype come off the wire the
            ; right way round.  A Pi-side ping gives ARP - 002A / 0806 - and
            ; anything else there means the framing is wrong even though a
            ; frame did arrive.
            ld      (RET_BC),bc
            ld      (RET_HL),hl
            ld      (HAVEFRAME),a
            push    af
            call    PRINT_HEX8
            pop     af
            or      a
            jr      nz,.havestat
            ; Print something explicit rather than nothing.  Silence here is
            ; indistinguishable from running an older ETHTEST that cannot
            ; report at all, and that ambiguity cost a test cycle.
            ld      de,NOFRAME_S
            ld      c,_STROUT
            call    BDOS
            jr      .nostat
.havestat:
            ld      de,LEN_S
            ld      c,_STROUT
            call    BDOS
            ld      a,(RET_BC+1)
            call    PRINT_HEX8
            ld      a,(RET_BC)
            call    PRINT_HEX8
            ld      de,TYP_S
            ld      c,_STROUT
            call    BDOS
            ld      a,(RET_HL+1)
            call    PRINT_HEX8
            ld      a,(RET_HL)
            call    PRINT_HEX8
.nostat:
            call    NEWLINE

; --- Routine 8, ETH_GET_FRAME ----------------------------------------------
; Only when ETH_IN_STATUS said a frame is waiting.  Routine 8 is the last
; untested link in the receive chain: ETHTEST has always stopped at routine 7,
; and nothing else calls 8 except InterNestor Lite's timer ISR - so on the path
; from the wire to the stack, this is the one step that has never run.
;
; Dumping the first 14 bytes is the point.  That is the Ethernet header -
; destination MAC, source MAC, ethertype - so it shows both that the payload
; survived the transfer and that it is not offset by a byte.  For the Pi's ARP
; it should read FFFFFFFFFFFF, the TAP's own MAC, then 0806.
            ld      a,(HAVEFRAME)
            or      a
            jr      z,.noframe

            ld      de,FRAME_S
            ld      c,_STROUT
            call    BDOS
            ld      hl,FRAMEBUF
            ld      a,8                     ; ETH_GET_FRAME
            call    CALL_UNAPI
            ld      (RET_BC),bc
            push    af
            call    PRINT_HEX8              ; 00 = retrieved, 01 = none
            ld      de,LEN_S
            ld      c,_STROUT
            call    BDOS
            ld      a,(RET_BC+1)
            call    PRINT_HEX8
            ld      a,(RET_BC)
            call    PRINT_HEX8
            call    NEWLINE
            pop     af
            or      a
            jr      nz,.noframe             ; nothing actually retrieved

            ; 48 bytes, 16 per row.  Enough to cover the Ethernet header, the
            ; whole IP header and the start of the ICMP payload - so a ping
            ; shows proto 01, the destination address, and ICMP type 08.  A
            ; 42-byte ARP could never expose corruption past its own end; a
            ; 98-byte ICMP can, which is why this goes deeper than the header.
            ld      hl,FRAMEBUF
            ld      b,48
.dumploop:
            ld      a,(hl)
            push    hl
            push    bc
            call    PRINT_HEX8
            pop     bc
            pop     hl
            inc     hl
            ld      a,b
            dec     a
            and     00Fh                    ; newline every 16 bytes
            jr      nz,.nowrap
            push    hl
            push    bc
            call    NEWLINE
            pop     bc
            pop     hl
.nowrap:
            djnz    .dumploop
.noframe:

; --- Routine 1, ETH_RESET, LAST ---------------------------------------------
; Deliberately after ETH_IN_STATUS, and that ordering is load-bearing.
;
; ETH_RESET discards every queued received frame - msxpi_eth._op_reset() does
; `self.link.rx.clear()`, exactly as the specification requires.  This call
; used to sit before the InSt check, which meant the test threw away the very
; frames it was about to look for: with the Pi pinging and ARP demonstrably
; arriving, InSt still reported "none", and it read as a broken receive path
; rather than a broken test.
;
; It stays in the test because routine 1 is the first thing InterNestor Lite
; calls and is worth exercising - just not before anything that inspects
; received state.
            ld      de,RESET_S
            ld      c,_STROUT
            call    BDOS
            ld      a,1                     ; ETH_RESET
            call    CALL_UNAPI
            ld      de,OK_S
            ld      c,_STROUT
            call    BDOS

; --- Routine 10, ETH_OUT_STATUS --------------------------------------------
; What happened to the LAST frame anyone asked us to send.  This is the direct
; answer to "is InterNestor Lite even attempting to transmit?", because the
; value is set by our own FN_SEND_FRAME and by nothing else:
;
;   00  nothing has been sent since the last reset  -> INL has NEVER called
;                                                      ETH_SEND_FRAME
;   02  finished successfully                       -> INL did send
;   03  carrier lost   (we could not get the link)
;   04  excessive collisions (the Pi rejected it)
;
; Read BEFORE the ETH_RESET below, because reset clears it - and note INL also
; resets at install time, so this reflects activity since INL came up.
            ld      de,OUT_S
            ld      c,_STROUT
            call    BDOS
            ld      a,10                    ; ETH_OUT_STATUS
            call    CALL_UNAPI
            call    PRINT_HEX8
            call    NEWLINE

; --- Routine 9, ETH_SEND_FRAME (only with "T") -----------------------------
; The transmit path has never put a byte on the wire.  Everything proven so far
; is receive; the Pi's msxpi0 shows "RX packets 0", meaning the MSX has never
; sent anything at all - so this is the other untested half, and testing it
; through InterNestor Lite would confound our code with INL's.
;
; The frame is a gratuitous ARP REPLY announcing 192.168.99.2 as ours. Any
; valid frame would prove the transfer, but this one may also complete the
; Pi's pending ARP entry and make its ping start working - so the test can
; succeed loudly rather than only in a counter.
            ld      a,(SENDTEST)
            or      a
            jr      z,.nosend

            ld      de,SEND_S
            ld      c,_STROUT
            call    BDOS
            ld      hl,ARPFRAME
            ld      bc,ARPFRAME_LEN
            ld      d,0                     ; synchronous
            ld      a,9                     ; ETH_SEND_FRAME
            call    CALL_UNAPI
            call    PRINT_HEX8              ; 00 sent, 1 bad length,
            call    NEWLINE                 ; 3 carrier, 4 collisions, 5 async
.nosend:

; --- The device must be left out of wait mode ------------------------------
; While wait mode is on, $57 reads $8E and every IN from $5A starts a transfer.
; A driver that leaked wait mode would silently break every other piece of
; MSXPi software, so check it explicitly: $57 must read $0E here.
            ld      de,PORT57_S
            ld      c,_STROUT
            call    BDOS
            in      a,(057h)
            call    PRINT_HEX8
            call    NEWLINE

            ld      c,_TERM0
            jp      BDOS

; --- CALL_UNAPI: invoke routine A in the implementation.
; Preserves nothing in particular; returns whatever the routine returns.
;
; Two ways in, and which one applies is much of what this test exists to show:
;
;   segment FFh  the implementation is in ROM, so a plain inter-slot call
;                reaches it.  This is the path every stock client takes, and
;                the reason the driver was moved into the ROM at all.
;   otherwise    it lives in a mapped RAM segment and has to go through the
;                UNAPI RAM helper's CALL_MAP at helper+0.
;
; CALSLT is reachable from MSX-DOS because the kernel puts the inter-slot call
; routines in page-0 RAM, the same way ENASLT is used by ETHUNAPI.COM.
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
            ld      hl,(HELPER_ADD)
            pop     af
            jp      (hl)
.rom:
            pop     af
            call    CALSLT
            ; The RAM helper's CALL_MAP is known to return with interrupts
            ; disabled - it has to turn them off to switch the segment, and its
            ; restore hits the `ld a,i` P/V erratum.  CALSLT should not, but a
            ; foreground program that loses JIFFY and the keyboard is a
            ; miserable thing to debug, so make sure either way.
            ei
            ret

DIE:
            ld      c,_STROUT
            call    BDOS
            ld      c,_TERM0
            jp      BDOS

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
HAVEFRAME:  db      0
SENDTEST:   db      0
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

BANNER_S:   db      "ETHTEST 0.8 - Ethernet UNAPI",13,10,13,10,"$"
FOUND_S:    db      "Found: $"
SLOT_S:     db      "Slot:  $"
SEG_S:      db      "  Seg: $"
API_S:      db      "API:   $"
IMPL_S:     db      "Impl:  $"
NOHELPER_S: db      "*** No RAM helper installed.",13,10,"$"
NONE_S:     db      "*** No ETHERNET implementation found.",13,10,"$"
RESET_S:    db      "Rst:   $"
FRAME_S:    db      "Frm:   $"
SEND_S:     db      "Snd:   $"
OUT_S:      db      "Out:   $"
OK_S:       db      "ok",13,10,"$"
MODE_S:     db      "Mode:  $"
MAC_S:      db      "MAC:   $"
NETSTAT_S:  db      "Net:   $"
INSTAT_S:   db      "InSt:  $"
LEN_S:      db      " len=$"
NOFRAME_S:  db      " none$"
TYP_S:      db      " typ=$"
PORT57_S:   db      "P57:   $"
CRLF_S:     db      13,10,"$"

; Gratuitous ARP reply announcing 192.168.99.2 with the MSX's own MAC, the one
; msxpi_eth reports (02:4D:53:58:50:69).  42 bytes: 14 of Ethernet header plus
; 28 of ARP - above MIN_FRAME_LEN (16) and far below MAX_FRAME_LEN.
ARPFRAME:
            db      0FFh,0FFh,0FFh,0FFh,0FFh,0FFh   ; dst: broadcast
            db      002h,04Dh,053h,058h,050h,069h   ; src: our MAC
            db      008h,006h                       ; ethertype ARP
            db      000h,001h                       ; htype: Ethernet
            db      008h,000h                       ; ptype: IPv4
            db      006h,004h                       ; hlen, plen
            db      000h,002h                       ; oper: reply
            db      002h,04Dh,053h,058h,050h,069h   ; sender MAC
            db      192,168,99,2                    ; sender IP
            db      0FFh,0FFh,0FFh,0FFh,0FFh,0FFh   ; target MAC
            db      192,168,99,2                    ; target IP
ARPFRAME_LEN: equ   $-ARPFRAME

; Receive buffer for ETH_GET_FRAME.  Past the end of the emitted image on
; purpose - it is uninitialised scratch, and everything above the loaded .COM
; up to HIMEM belongs to this program anyway.
FRAMEBUF:   ds      1600
