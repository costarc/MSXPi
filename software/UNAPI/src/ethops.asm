; MSXPi Interface
; Version 1.6.1
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
; MSXPi Ethernet UNAPI - the 12 ETH_* routines  (Phase 5b)
; =============================================================================
; Marshals each UNAPI routine onto the $C0-$CF opcode protocol served by
; msxpi_eth.py.  Register contracts come straight from the Ethernet UNAPI 1.1
; specification; several are easy to get backwards, so they are restated at
; each routine.
;
; Every routine that touches the link goes through ETH_OP or follows the same
; lock/begin/end discipline.  Nothing here may leave wait mode enabled on the
; way out: while it is on, every IN from $5A starts a transfer, so a leaked
; wait mode would silently break every other piece of MSXPi software, which
; reads bytes the polled way, until the next reset.
; =============================================================================

; Opcodes - must match msxpi_eth.py
OP_PROBE:       equ     0C0h
OP_GET_HWADD:   equ     0C1h
OP_GET_NETSTAT: equ     0C2h
OP_NET_ONOFF:   equ     0C3h
OP_FILTERS:     equ     0C4h
OP_IN_STATUS:   equ     0C5h
OP_GET_FRAME:   equ     0C6h
OP_SEND_FRAME:  equ     0C7h
OP_RESET:       equ     0C8h
OP_PROBE3:      equ     0CAh        ; OP_PROBE for protocol 3 (ETH_V3 builds)

            ifdef ETH_V3
ETH_RC_OK:      equ     05Ah        ; protocol 3: an idle link reads 0, so 0 is not "OK"
            else
ETH_RC_OK:      equ     000h
            endif
FLAG_MORE:      equ     001h

; The wire protocol version OP_PROBE must report - PROTO_VERSION in
; msxpi_eth.py.  2: ETH_IN_STATUS carries small frames inline (see
; FN_IN_STATUS), and ETH_SEND_FRAME's payload is received as one RDY-held
; burst so that it can be sent with OTIR.  A mismatch is refused, not worked
; around: see MODE_REFUSED.
            ifdef ETH_V3
; 3: protocol 2, plus the Pi's GO byte at the start of every burst it sends and
; before every burst it takes (LINK2-DESIGN.md 3.4, 4), and RC_OK = 5Ah.
ETH_PROTO:      equ     3
OP_PROBE_USED:  equ     OP_PROBE3
            else
ETH_PROTO:      equ     2
OP_PROBE_USED:  equ     OP_PROBE
            endif

; ETH_IN_STATUS reply flag (o_RXC): 0 no frame, 1 a frame is waiting at the Pi,
; RXF_INLINE the frame came with this reply and is held in the work area.
RXF_INLINE:     equ     2

MAX_FRAME_LEN:  equ     1514
MIN_FRAME_LEN:  equ     16

; =============================================================================
; ETH_OP - one complete fast-op transaction
; =============================================================================
; In:  A = opcode
;      B = argument byte, sent only when C is non-zero
;      C = 0 no argument, non-zero send B
;      D = number of reply bytes to read into ETH_BUF (1 or more)
;      E = 0 accept any reply, 1 require ETH_BUF[0] == ETH_RC_OK,
;          2 the ETH_IN_STATUS reply - see ETH_OPX
; Out: CF=0 success, ETH_BUF holds the reply
;      CF=1 failure (busy, link dead, not ready, timeout, or bad result code)
;
; Always returns with the lock released and wait mode off.  The "busy" exit
; must NOT unlock - the lock belongs to whoever we lost the race to.
;
; THE RESULT-CODE CHECK IS NOT OPTIONAL PARANOIA.  In wait mode ETH_RX cannot
; fail: `in a,($5A)` returns whatever is on the bus, so a dead or
; desynchronised link yields garbage that looks like a perfectly good
; transaction.  On real hardware that produced ETH_GET_NETSTAT returning 4Dh -
; a leftover byte from the previous reply's MAC address - and a benchmark
; reporting 2048 of 2048 calls "successful" in zero elapsed time.  Every fast
; op answers with a result code first, so checking it is what turns a silent
; wrong answer into an honest failure.  E=2 is only for ETH_IN_STATUS, whose
; reply has no result-code byte.
;
; The parameters stay in their registers throughout: ETH_LOCK, ETH_BEGIN and
; ETH_TX only corrupt AF, so only the opcode has to be parked.
ETH_OP:
            ld      h,o_ETH_BUF
; --- ETH_OPX: ETH_OP with H = the work-area offset the reply is read to.
; E=2 is ETH_IN_STATUS: when its flag says RXF_INLINE the frame and its
; checksum follow the 5-byte reply and are read, in the same transaction,
; into the bytes after it (o_RXC_FRAME).  The length is checked before a byte
; of it is read: in wait mode a desynchronised link returns garbage, and a
; garbage length would write far past the end of the work area.
ETH_OPX:
            ld      (ix+o_ETH_OPC),a
            call    ETH_LOCK
            ret     c                       ; busy or dead - do not unlock

            call    ETH_BEGIN
            jr      c,.fail

            ld      a,(ix+o_ETH_OPC)
            call    ETH_TX
            jr      c,.fail

            ld      a,c
            or      a
            jr      z,.noarg
            ld      a,b
            call    ETH_TX
            jr      c,.fail
.noarg:
            ld      a,h
            ld      c,d
            ld      b,0
            call    WRKPTR
            push    de
            ifdef ETH_V3
            call    ETH_GO                  ; the reply is a burst: GO first
            jr      c,.failpop
            endif
            call    ETH_RX_BLOCK            ; HL ends just past the reply
            pop     de
            jr      c,.fail

            ld      a,e
            or      a
            jr      z,.done
            dec     a
            jr      nz,.inline
            ld      a,(ix+o_ETH_BUF)        ; result code must be ETH_RC_OK
            ifdef ETH_V3
            cp      ETH_RC_OK
            else
            or      a                       ; (ETH_RC_OK is 0)
            endif
            jr      nz,.fail
.done:
            call    ETH_OK                  ; break any run of failures
            call    ETH_END
            call    ETH_UNLOCK
            or      a                       ; CF=0
            ret
.fail:
            call    ETH_FAIL                ; drops wait mode, latches dead
            call    ETH_UNLOCK
            scf
            ret
            ifdef ETH_V3
.failpop:   pop     de
            jr      .fail
            endif
.inline:
            ld      a,(ix+o_RXC)
            cp      RXF_INLINE
            jr      nz,.done                ; no frame, or only announced
            ld      c,(ix+o_RXC+1)
            ld      a,(ix+o_RXC+2)
            or      a
            jr      nz,.fail                ; 256 or more: not a real reply
            ld      b,a
            ld      a,c
            dec     a
            cp      RX_INLINE_MAX
            jr      nc,.fail                ; 0, or larger than the buffer
            inc     bc                      ; and the checksum
            call    ETH_RX_BLOCK
            jr      c,.fail
            jr      .done

; =============================================================================
; 1: ETH_RESET
; =============================================================================
; In: A=1.  No output.  Puts the implementation back to its documented initial
; state; ETH_REVIVE clears the "link dead" latch so a previously failed link
; gets another chance.
FN_RESET:
            ; Also release a leaked link claim.  Routine 129 hands the link to
            ; a .COM, and a program that dies before releasing would otherwise
            ; block this driver's ISR polling for ever, with no way back short
            ; of a reboot.  A reset that left a stale claim held would not be
            ; putting the implementation back to its initial state.
            ;
            ; Deliberately here rather than in ETH_REVIVE: ETH_DETECT calls
            ; that too, and probing the device must not tear down a claim some
            ; program is legitimately holding.  It must also stay ahead of
            ; ETH_OP below, which takes ETH_LOCK - a lock this very flag would
            ; otherwise refuse, leaving reset unable to clear it.
            ld      (ix+o_LINK_BUSY),0
            ; A refused Pi gets probed again, so updating the server is
            ; enough - ETHTEST and INL's installer both reset first.
            ld      a,(ix+o_ETH_MODE)
            cp      MODE_REFUSED
            call    z,ETH_DETECT
            call    ETH_REVIVE
            ld      (ix+o_ETH_LASTSEND),0        ; "no frames sent since last reset"
            ld      (ix+o_RXC),0                 ; and none held: the Pi's
                                                 ; queue is emptied below
            ld      a,OP_RESET
            ld      c,0
            ; ETH_OP1 reads TWO bytes, not one: every fast op replies with a
            ; result code followed by its payload, and OP_RESET's payload is
            ; one byte.  Reading only the result code leaves the payload byte
            ; on the wire, and every later transaction then reads shifted data
            ; - a silent desync rather than a clean failure.
            jp      ETH_OP1

; --- ETH_OP1: a fast op whose reply is a result code and ONE byte.
; In: A = opcode, B = argument, C = 0 none / non-zero send B (as ETH_OP).
; Out: CF=0 A = the byte, or CF=1 failure.  Corrupts BC, DE, HL.
ETH_OP1:
            ld      de,2*256+1              ; RC + 1 byte, RC must be ok
            call    ETH_OP
            ret     c
            ld      a,(ix+o_ETH_BUF+1)
            ret

; =============================================================================
; 2: ETH_GET_HWADD
; =============================================================================
; Out: L-H-E-D-C-B = the six address bytes, in that order.  The mapping is
; chosen so the caller can store it with LD (X),HL / LD (X+2),DE / LD (X+4),BC,
; which means L is byte 0 and B is byte 5 - not the other way round.
FN_GET_HWADD:
            ld      a,OP_GET_HWADD
            ld      c,0                     ; no argument
            ld      de,7*256+1              ; RC + 6 address bytes, RC ok
            call    ETH_OP
            jr      c,.cached               ; on failure report what we know

            ; Refresh the cache, then fall into the reporting path: success and
            ; failure differ only in whether the cache was just updated, so
            ; there is no reason to build the same answer twice.
            ld      a,o_ETH_BUF+1
            call    WRKPTR
            ex      de,hl                   ; DE = source
            ld      a,o_MACADDR
            call    WRKPTR                  ; HL = destination
            ex      de,hl
            ld      bc,6
            ldir
.cached:
            ld      l,(ix+o_MACADDR+0)
            ld      h,(ix+o_MACADDR+1)
            ld      e,(ix+o_MACADDR+2)
            ld      d,(ix+o_MACADDR+3)
            ld      c,(ix+o_MACADDR+4)
            ld      b,(ix+o_MACADDR+5)
            ret

; =============================================================================
; 3: ETH_GET_NETSTAT
; =============================================================================
; Out: A = 0 not connected, 1 connected.
FN_GET_NETSTAT:
            ld      a,OP_GET_NETSTAT
            ld      c,0
            call    ETH_OP1
            ret     nc
            xor     a                       ; cannot reach the link: down
            ret

; =============================================================================
; 4: ETH_NET_ONOFF
; =============================================================================
; In:  B = 0 query, 1 enable, 2 disable
; Out: A = 1 enabled, 2 disabled
; The encoding goes to the Pi untranslated; note that 2 means "disable" on the
; way in and "disabled" on the way out.
FN_NET_ONOFF:
            ld      a,OP_NET_ONOFF
            ld      c,1                     ; B already holds the argument
            call    ETH_OP1
            ret     nc
            ld      a,2                     ; cannot reach the link: disabled
            ret

; =============================================================================
; 5: ETH_DUPLEX
; =============================================================================
; Out: A = 3, "unknown or does not apply".  Answered locally: there is no real
; Ethernet PHY here, and the specification provides this code precisely for
; implementations that do not act on real hardware.
FN_DUPLEX:
            ld      a,3
            ret

; =============================================================================
; 6: ETH_FILTERS
; =============================================================================
; In:  B = filter bitmask; bit 7 set means "report only, change nothing".
;      bit 4 promiscuous, bit 2 accept broadcast, bit 1 accept small frames.
; Out: A = configuration after execution.
FN_FILTERS:
            ld      a,OP_FILTERS
            ld      c,1
            call    ETH_OP1
            ret     nc
            xor     a
            ret

; =============================================================================
; 7: ETH_IN_STATUS
; =============================================================================
; Out: A = 0 no frames, 1 a frame is available
;      BC = size of the oldest frame, HL = its bytes 12-13
;
; This is the hot path: InterNestor Lite calls it from the timer interrupt, so
; it must be cheap and must never block.  ETH_LOCK failing (someone else is
; mid-transaction, or the link is latched dead) reports "no frames", which is
; exactly the right answer - INL simply does nothing this tick and tries again
; on the next one.
;
; The reply has no RC byte: the first byte IS the availability flag.
;
; Wire (protocol 2): [C5] -> [flag][len lo][len hi][ethertype hi][ethertype lo]
; and, when flag is RXF_INLINE, the frame and its checksum straight after.
;
; The Pi sends a waiting frame inline when it is at most RX_INLINE_MAX bytes,
; and takes it off its queue as it does.  It is kept in the work area (o_RXC)
; until ETH_GET_FRAME collects it, so a small frame - every PLAYNET packet, ARP,
; a TCP ACK - costs ONE transaction instead of two.  Larger frames are only
; announced (flag 1) and come over in ETH_GET_FRAME's own transaction, as
; before.  While a frame is held, calls here answer from it with no round trip.
;
; ETH_OPX does the reading, and checks the length before anything is read
; into the work area: in wait mode a desynchronised link returns garbage, and a
; garbage length would otherwise write far past the end of the work area.
;
; Any failure drops the held frame (o_RXC = 0).  The Pi has already let go of
; it, so it is lost - the same as a frame lost on the wire, which the stack
; above recovers from.
FN_IN_STATUS:
            ld      a,(ix+o_RXC)
            cp      RXF_INLINE
            jr      z,.report               ; holding one: answer locally
            ld      a,OP_IN_STATUS
            ld      c,0
            ld      de,5*256+2              ; 5 reply bytes, a frame may follow
            ld      h,o_RXC
            call    ETH_OPX
            jr      nc,.report
            ld      (ix+o_RXC),0            ; whatever arrived is not a reply
.report:
            ld      a,(ix+o_RXC)
            or      a
            ret     z                       ; A=0: none
            ld      c,(ix+o_RXC+1)          ; little-endian length
            ld      b,(ix+o_RXC+2)
            ld      h,(ix+o_RXC+3)          ; ethertype, big-endian on the wire
            ld      l,(ix+o_RXC+4)
            ld      a,1
            ret

; =============================================================================
; 8: ETH_GET_FRAME
; =============================================================================
; In:  HL = destination, or 0 to discard the frame
; Out: A = 0 retrieved or discarded, 1 none available
;      BC = size of the retrieved frame (when A=0)
;
; Wire: [C6][maxlen lo][maxlen hi] -> [len lo][len hi][flags] and, when len is
; non-zero, the frame followed by a one-byte checksum.  maxlen 0 is "discard":
; the Pi drops the frame and answers with its length and flags only, so HL=0
; costs three bytes on the wire instead of the whole frame.
;
; A frame ETH_IN_STATUS already brought in is the oldest one - the Pi took it
; off its queue - so it is handed over first, from the work area, with no link
; traffic.  That is still done under the lock: an ETH_IN_STATUS interrupting
; the copy must not refill the buffer underneath it, and with the lock held it
; can only report "no frame" until we are done.
FN_GET_FRAME:
            ld      (ix+o_ETH_DEST),l
            ld      (ix+o_ETH_DEST+1),h

            call    ETH_LOCK
            jr      c,.none
            ld      a,(ix+o_RXC)
            cp      RXF_INLINE
            jr      z,.held
            call    ETH_BEGIN
            jr      c,.fail

            ld      de,MAX_FRAME_LEN
            ld      a,h
            or      l
            jr      nz,.keep
            ld      d,a                     ; discard: maxlen 0
            ld      e,a
.keep:
            ld      a,OP_GET_FRAME
            call    ETH_TX3
            jr      c,.fail

            ld      a,o_ETH_BUF             ; len lo, len hi, flags
            call    WRKPTR
            ld      bc,3
            ifdef ETH_V3
            call    ETH_GO                  ; the reply is a burst: GO first
            jr      c,.fail
            endif
            call    ETH_RX_BLOCK
            jr      c,.fail

            ld      c,(ix+o_ETH_BUF+0)
            ld      b,(ix+o_ETH_BUF+1)
            ld      (ix+o_ETH_FLEN),c
            ld      (ix+o_ETH_FLEN+1),b
            ld      a,b
            or      c
            jr      z,.empty                ; length 0: nothing was waiting

            ld      l,(ix+o_ETH_DEST)
            ld      h,(ix+o_ETH_DEST+1)
            ld      a,h
            or      l
            jr      z,.got                  ; discarded: no frame follows
            call    ETH_RX_BLOCK
            jr      c,.fail
            call    ETH_RX                  ; trailing checksum
            jr      c,.fail
.got:
            call    ETH_END                 ; harmless after .held: no
            call    ETH_UNLOCK              ; ETH_BEGIN, wait mode already off
            ld      c,(ix+o_ETH_FLEN)
            ld      b,(ix+o_ETH_FLEN+1)
            xor     a                       ; A=0: retrieved
            ret

.empty:
            call    ETH_END
            call    ETH_UNLOCK
            jr      .none
.fail:
            call    ETH_FAIL
            call    ETH_UNLOCK
.none:
            ld      a,1
            ret

; The frame ETH_IN_STATUS brought in.  HL is still the caller's destination
; (ETH_LOCK only touches AF); 0 discards it, exactly as on the wire.
.held:
            ld      (ix+o_RXC),0            ; collected - the lock covers this
            ld      c,(ix+o_RXC+1)
            ld      b,(ix+o_RXC+2)
            ld      (ix+o_ETH_FLEN),c
            ld      (ix+o_ETH_FLEN+1),b
            ld      a,h
            or      l
            jr      z,.got
            ex      de,hl
            ld      a,o_RXC_FRAME
            call    WRKPTR
            ldir
            jr      .got

; --- ETH_TX3: send A, then E, then D - an opcode and its 16-bit argument.
; Out: CF=1 on timeout.  Corrupts AF; BC/DE/HL preserved.
ETH_TX3:
            call    ETH_TX
            ret     c
            ld      a,e
            call    ETH_TX
            ret     c
            ld      a,d
            jp      ETH_TX

; =============================================================================
; 9: ETH_SEND_FRAME
; =============================================================================
; In:  HL = frame address, BC = length, D = 0 synchronous / 1 asynchronous
; Out: A = 0 sent, 1 invalid length, 3 carrier lost, 4 excessive collisions,
;      5 asynchronous mode not supported
;
; D=1 (asynchronous) IS accepted, and doing anything else would be useless in
; practice: InterNestor Lite ALWAYS asks for async - both of its send sites do
; a plain `ld d,1` - so returning 5, "asynchronous mode not supported", meant
; INL could never transmit a single frame. It received frames correctly,
; parsed them correctly, decided to reply, and was refused here every time.
; The symptom was a stack that answered nothing at all while every layer below
; it demonstrably worked.
;
; So the frame is sent synchronously whatever D says, and 0 is returned.  That
; is safe rather than a fudge: async only promises that transmission has
; STARTED, and completing it first is a stronger guarantee than the caller
; asked for.  A caller that then polls ETH_OUT_STATUS gets 2, "transmission
; finished successfully", which is exactly what it is waiting for.
;
; Note the specification's own probe for async support - send a dummy 16-byte
; frame with D=1 and look for 0 or 5 - therefore reports async as supported
; here, which is the honest answer: an async send does complete.
;
; Wire: [C7][len lo][len hi][frame...][checksum] -> [RC]
FN_SEND_FRAME:
            ; Length check first: an invalid length is not a failed
            ; transmission, so ETH_OUT_STATUS must not record it.  Both
            ; boundaries are inclusive: 16 and 1514 are legal lengths.  ADD
            ; sets carry exactly when BC reaches the negated bound, so no flag
            ; left over from earlier can leak into the result.
            push    hl
            ld      hl,-MIN_FRAME_LEN
            add     hl,bc
            jr      nc,.badlen              ; BC < 16
            ld      hl,-(MAX_FRAME_LEN+1)
            add     hl,bc
            jr      c,.badlen               ; BC > 1514
            pop     hl

            ; ETH_LOCK, ETH_BEGIN and ETH_TX3 only corrupt AF, so the frame's
            ; address and length stay in HL and BC throughout.
            call    ETH_LOCK
            jr      c,.carrier
            call    ETH_BEGIN
            jr      c,.fail

            ld      a,OP_SEND_FRAME
            ld      d,b
            ld      e,c
            call    ETH_TX3                 ; opcode, length
            jr      c,.fail

            ; Payload and its checksum: OTIR in wait mode.  The Pi receives
            ; them as one RDY-held burst.
            call    ETH_TX_BLOCK
            jr      c,.fail

            call    ETH_RX                  ; the Pi's result code, with Z set
            jr      c,.fail                 ; from it - ETH_END and ETH_UNLOCK
            ifdef ETH_V3
            cp      ETH_RC_OK
            endif
            call    ETH_END                 ; both preserve the flags
            call    ETH_UNLOCK
            jr      nz,.rejected
            ld      (ix+o_ETH_LASTSEND),2   ; OUT_STATUS: finished successfully
            xor     a                       ; A=0: sent
            ret
.rejected:
            ld      (ix+o_ETH_LASTSEND),4   ; a Pi-side reject is reported as
            ld      a,4                     ; "excessive collisions"
            ret
.fail:
            call    ETH_FAIL
            call    ETH_UNLOCK
.carrier:
            ld      (ix+o_ETH_LASTSEND),3
            ld      a,3
            ret
.badlen:
            pop     hl
            ld      a,1                     ; not recorded in ETH_LASTSEND
            ret

; =============================================================================
; 10: ETH_OUT_STATUS
; =============================================================================
; Out: A = 0 nothing sent since reset, 1 transmitting, 2 finished successfully,
;      3 carrier lost, 4 excessive collisions.  Persistent until the next send
;      or reset, so it is simply the value the last send recorded.
FN_OUT_STATUS:
            ld      a,(ix+o_ETH_LASTSEND)
            ret

; =============================================================================
; 11: ETH_SET_HWADD
; =============================================================================
; Changing the address is not supported, so the specification says to do
; nothing and return the current address exactly as ETH_GET_HWADD would.
FN_SET_HWADD:
            jp      FN_GET_HWADD

; =============================================================================
; ETH_VERIFY - prove the selected transport actually works
; =============================================================================
; Out: CF=0 the link answered correctly, CF=1 it did not.  Corrupts AF.
;
; Runs one OP_PROBE and checks for the 'E','T','H' signature.  Port $57 saying
; "wait mode supported" only means the CPLD implements the register - on real
; hardware /WAIT then turned out to be intermittent, because the Pi drops
; RPI_READY between bytes and an IN ($5A) landing in that gap neither stalls
; nor transfers.  Detection that believes $57 selected a backend that does not
; work; this is what makes it check.
;
; The signature matters: a stale or floating bus can produce a zero result code
; by luck, but not three specific ASCII bytes in order.
;
; A good signature with the wrong protocol version is a Pi that answers but
; speaks another wire format.  That sets MODE_REFUSED, which ETH_LOCK honours,
; so every later call fails cleanly instead of desynchronising - and since
; ETH_DETECT only runs once, it stays refused until ETH_RESET probes again.
ETH_VERIFY:
            call    ETH_REVIVE              ; clear any latched failure first
            ld      a,OP_PROBE_USED
            ld      c,0                     ; no argument
            ld      de,5*256+1              ; RC + 'E','T','H',version, RC ok
            call    ETH_OP
            ret     c
            ld      a,(ix+o_ETH_BUF+1)
            cp      "E"
            jr      nz,.bad
            ld      a,(ix+o_ETH_BUF+2)
            cp      "T"
            jr      nz,.bad
            ld      a,(ix+o_ETH_BUF+3)
            cp      "H"
            jr      nz,.bad
            ld      a,(ix+o_ETH_BUF+4)
            cp      ETH_PROTO
            ret     z                       ; CF=0
            ld      (ix+o_ETH_MODE),MODE_REFUSED
.bad:
            scf
            ret

; =============================================================================
; 129: implementation-specific - claim or release the MSXPi link
; =============================================================================
; In:  B = 1 claim the link, 0 release it
; Out: A = 0 the link is yours (or has been released), 1 refused - retry
;
; The MSXPi link carries BOTH the disk and this Ethernet driver, and once
; InterNestor Lite is resident it polls ETH_IN_STATUS from the 50/60 Hz timer
; interrupt.  DSKIO protects itself by raising o_LINK_BUSY, which ETH_LOCK
; honours - but every OTHER user of the link (P.COM, PCOPY, PDIR, CALL MSXPI)
; is a .COM that cannot reach the driver work area, so the ISR had no way to
; know they were mid-transaction.
;
; Seen on hardware: `p cd` printed its answer and then hung, with the server
; reporting a stray 0xC5 - which is OP_IN_STATUS, the ISR's opcode injected
; into the middle of the command's byte stream.
;
; This is that same guard, made reachable from outside.  A client claims the
; link, does its transactions with interrupts still enabled, and releases it.
; Nothing is published about the work area's layout, so clients cannot rot
; when unapi_wrk.inc changes.
;
; Claiming publishes the flag FIRST and only then looks for a transaction
; already in flight: the other order leaves a window where the ISR passes its
; own ETH_LOCK check, and we would hand out a link that is already in use.
FN_LINK_CLAIM:
            ld      a,b
            or      a
            jr      z,.release
            ld      (ix+o_LINK_BUSY),1
            ld      a,(ix+o_ETH_BUSY)
            or      a
            jr      z,.ok
            ld      (ix+o_LINK_BUSY),0      ; lost the race; caller retries
            ld      a,1
            ret
.release:
            ld      (ix+o_LINK_BUSY),0
.ok:
            xor     a
            ret

; =============================================================================
; 128: implementation-specific - force the transport mode
; =============================================================================
; In:  B = 0 report only, 1 force polled, 2 force /WAIT; anything else reports
; Out: A = the mode in effect BEFORE this call
;
; Diagnostic only.  It exists so ETHBENCH can time the same transfer loop under
; each backend on one machine, which is the only way to know what hardware
; /WAIT is actually worth rather than inferring it.
FN_SET_MODE:
            ld      a,(ix+o_ETH_MODE)
            push    af
            ld      a,b
            or      a
            jr      z,.report
            cp      3
            jr      nc,.report          ; no such mode
            dec     a                   ; 1 -> 0 polled, 2 -> 1 wait
            ld      (ix+o_ETH_MODE),a
.report:
            pop     af
            ret
