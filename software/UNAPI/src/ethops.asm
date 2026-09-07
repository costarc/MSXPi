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
; way out: while it is on, port $57 reads $8E, and msxpi_bios.asm:97 decides
; "is this openMSX?" by testing $57 against $FE - so a leaked wait mode would
; silently break every other piece of MSXPi software until the next reset.
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

ETH_RC_OK:      equ     000h
FLAG_MORE:      equ     001h

MAX_FRAME_LEN:  equ     1514
MIN_FRAME_LEN:  equ     16

; =============================================================================
; ETH_OP - one complete fast-op transaction
; =============================================================================
; In:  A = opcode
;      B = argument byte, sent only when C is non-zero
;      C = 0 no argument, non-zero send B
;      D = number of reply bytes to read into ETH_BUF
;      E = 0 accept any reply, 1 require ETH_BUF[0] == ETH_RC_OK
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
; wrong answer into an honest failure.  E=0 is only for ETH_IN_STATUS, whose
; reply has no result-code byte.
ETH_OP:
            ld      (ix+o_ETH_OPC),a
            ld      (ix+o_ETH_ARG),b
            ld      (ix+o_ETH_HASARG),c
            ld      (ix+o_ETH_RLEN),d
            ld      (ix+o_ETH_CHKRC),e

            call    ETH_LOCK
            ret     c                       ; busy or dead - do not unlock

            call    ETH_BEGIN
            jr      c,.fail

            ld      a,(ix+o_ETH_OPC)
            call    ETH_TX
            jr      c,.fail

            ld      a,(ix+o_ETH_HASARG)
            or      a
            jr      z,.noarg
            ld      a,(ix+o_ETH_ARG)
            call    ETH_TX
            jr      c,.fail
.noarg:
            ld      a,(ix+o_ETH_RLEN)
            or      a
            jr      z,.done
            ld      c,a
            ld      b,0
            ld      a,o_ETH_BUF
            call    WRKPTR
            call    ETH_RX_BLOCK
            jr      c,.fail

            ld      a,(ix+o_ETH_CHKRC)
            or      a
            jr      z,.done
            ld      a,(ix+o_ETH_BUF)        ; result code must be ETH_RC_OK
            or      a
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

; =============================================================================
; 1: ETH_RESET
; =============================================================================
; In: A=1.  No output.  Puts the implementation back to its documented initial
; state; ETH_REVIVE clears the "link dead" latch so a previously failed link
; gets another chance.
FN_RESET:
            call    ETH_REVIVE
            ld      (ix+o_ETH_LASTSEND),0        ; "no frames sent since last reset"
            ld      a,OP_RESET
            ld      b,0
            ld      c,0
            ; TWO bytes, not one: every fast op replies with a result code
            ; followed by its payload, and OP_RESET's payload is one byte.
            ; Reading only the result code leaves the payload byte on the wire,
            ; and every later transaction then reads shifted data - a silent
            ; desync rather than a clean failure.
            ld      d,2
            ld      e,1
            call    ETH_OP
            ret

; =============================================================================
; 2: ETH_GET_HWADD
; =============================================================================
; Out: L-H-E-D-C-B = the six address bytes, in that order.  The mapping is
; chosen so the caller can store it with LD (X),HL / LD (X+2),DE / LD (X+4),BC,
; which means L is byte 0 and B is byte 5 - not the other way round.
FN_GET_HWADD:
            ld      a,OP_GET_HWADD
            ld      b,0
            ld      c,0
            ld      d,7                     ; RC + 6 address bytes
            ld      e,1
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
            ld      b,0
            ld      c,0
            ld      d,2                     ; RC + state
            ld      e,1
            call    ETH_OP
            jr      c,.down
            ld      a,(ix+o_ETH_BUF+1)
            ret
.down:
            xor     a
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
            ld      d,2
            ld      e,1
            call    ETH_OP
            jr      c,.unknown
            ld      a,(ix+o_ETH_BUF+1)
            ret
.unknown:
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
            ld      d,2
            ld      e,1
            call    ETH_OP
            jr      c,.unknown
            ld      a,(ix+o_ETH_BUF+1)
            ret
.unknown:
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
; TODO: ETH_GET_FRAME already learns whether another frame is queued behind the
; one it returns.  Caching that would let most calls here answer with no round
; trip at all, which on this link is the single biggest win available.
FN_IN_STATUS:
            ld      a,OP_IN_STATUS
            ld      b,0
            ld      c,0
            ld      d,5                     ; flag, len lo/hi, ethertype hi/lo
            ld      e,0
            call    ETH_OP
            jr      c,.none

            ld      a,(ix+o_ETH_BUF+0)
            or      a
            jr      z,.none
            ld      c,(ix+o_ETH_BUF+1)      ; little-endian length
            ld      b,(ix+o_ETH_BUF+2)
            ld      h,(ix+o_ETH_BUF+3)      ; ethertype, big-endian on the wire
            ld      l,(ix+o_ETH_BUF+4)
            ld      a,1
            ret
.none:
            xor     a
            ret

; =============================================================================
; 8: ETH_GET_FRAME
; =============================================================================
; In:  HL = destination, or 0 to discard the frame
; Out: A = 0 retrieved or discarded, 1 none available
;      BC = size of the retrieved frame (when A=0)
;
; Wire: [C6][maxlen lo][maxlen hi] -> [len lo][len hi][flags] and, when len is
; non-zero, the frame followed by a one-byte checksum.
FN_GET_FRAME:
            ld      (ix+o_ETH_DEST),l
            ld      (ix+o_ETH_DEST+1),h

            call    ETH_LOCK
            jr      c,.none
            call    ETH_BEGIN
            jr      c,.fail

            ld      a,OP_GET_FRAME
            call    ETH_TX
            jr      c,.fail
            ld      a,MAX_FRAME_LEN & 0FFh
            call    ETH_TX
            jr      c,.fail
            ld      a,(MAX_FRAME_LEN >> 8) & 0FFh
            call    ETH_TX
            jr      c,.fail

            ld      a,o_ETH_BUF             ; len lo, len hi, flags
            call    WRKPTR
            ld      bc,3
            call    ETH_RX_BLOCK
            jr      c,.fail

            ld      c,(ix+o_ETH_BUF+0)
            ld      b,(ix+o_ETH_BUF+1)
            ld      a,b
            or      c
            jr      z,.empty                ; length 0: nothing was waiting

            ld      (ix+o_ETH_FLEN),c
            ld      (ix+o_ETH_FLEN+1),b
            ld      l,(ix+o_ETH_DEST)
            ld      h,(ix+o_ETH_DEST+1)
            ld      a,h
            or      l
            jr      nz,.into_buffer

            ; HL=0 means discard: the bytes still have to be pulled off the
            ; wire, so read and drop them.
            call    ETH_RX_SINK
            jr      c,.fail
            jr      .checksum
.into_buffer:
            call    ETH_RX_BLOCK
            jr      c,.fail
.checksum:
            call    ETH_RX                  ; trailing checksum
            jr      c,.fail

            call    ETH_END
            call    ETH_UNLOCK
            ld      c,(ix+o_ETH_FLEN)
            ld      b,(ix+o_ETH_FLEN+1)
            xor     a                       ; A=0: retrieved
            ret

.empty:
            call    ETH_END
            call    ETH_UNLOCK
            ld      a,1
            ret
.fail:
            call    ETH_FAIL
            call    ETH_UNLOCK
.none:
            ld      a,1
            ret

; --- ETH_RX_SINK: read BC bytes and throw them away.
; Used by the discard path so the wire stays in step.  Nothing is stored, so
; unlike ETH_RX_BLOCK it needs no destination - HL is neither read nor
; written.
ETH_RX_SINK:
.loop:
            push    bc
            call    ETH_RX
            pop     bc
            ret     c
            dec     bc
            ld      a,b
            or      c
            jr      nz,.loop
            or      a
            ret

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
            ld      (ix+o_ETH_SRC),l
            ld      (ix+o_ETH_SRC+1),h
            ld      (ix+o_ETH_FLEN),c
            ld      (ix+o_ETH_FLEN+1),b

            ; Length check first: an invalid length is not a failed
            ; transmission, so ETH_OUT_STATUS must not record it.
            ;
            ; Both comparisons clear carry before SBC - without that the result
            ; depends on whatever set the flag last - and both boundaries are
            ; inclusive: 16 and 1514 are legal lengths.
            ld      h,b
            ld      l,c
            ld      de,MIN_FRAME_LEN
            or      a
            sbc     hl,de                   ; BC - 16
            jr      c,.badlen               ; BC < 16

            ld      h,b
            ld      l,c
            ld      de,MAX_FRAME_LEN
            or      a
            sbc     hl,de                   ; BC - 1514
            jr      c,.lenok                ; BC < 1514
            jr      nz,.badlen              ; BC > 1514
.lenok:

            call    ETH_LOCK
            jr      c,.carrier
            call    ETH_BEGIN
            jr      c,.fail

            ld      a,OP_SEND_FRAME
            call    ETH_TX
            jr      c,.fail
            ld      a,(ix+o_ETH_FLEN)
            call    ETH_TX
            jr      c,.fail
            ld      a,(ix+o_ETH_FLEN+1)
            call    ETH_TX
            jr      c,.fail

            ; Payload, accumulating the checksum as we go.
            ld      l,(ix+o_ETH_SRC)
            ld      h,(ix+o_ETH_SRC+1)
            ld      c,(ix+o_ETH_FLEN)
            ld      b,(ix+o_ETH_FLEN+1)
            call    ETH_TX_SUM
            jr      c,.fail
            ld      a,(ix+o_ETH_SUM)
            call    ETH_TX
            jr      c,.fail

            call    ETH_RX
            jr      c,.fail
            ld      (ix+o_ETH_BUF),a

            call    ETH_END
            call    ETH_UNLOCK

            ld      a,(ix+o_ETH_BUF)
            or      a
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
            ld      a,1                     ; not recorded in ETH_LASTSEND
            ret

; --- ETH_TX_SUM: send BC bytes from HL, leaving the 8-bit sum in ETH_SUM.
; The checksum has to be computed here rather than reusing ETH_TX_BLOCK,
; because the Pi verifies the same simple additive sum msxpi_eth.py computes.
ETH_TX_SUM:
            ld      (ix+o_ETH_SUM),0
.loop:
            ld      a,b
            or      c
            jr      z,.done
            ld      a,(hl)
            add     a,(ix+o_ETH_SUM)
            ld      (ix+o_ETH_SUM),a
            push    bc
            ld      a,(hl)
            call    ETH_TX
            pop     bc
            ret     c
            inc     hl
            dec     bc
            jr      .loop
.done:
            or      a
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
ETH_VERIFY:
            call    ETH_REVIVE              ; clear any latched failure first
            ld      a,OP_PROBE
            ld      b,0
            ld      c,0
            ld      d,5                     ; RC + 'E','T','H',version
            ld      e,1
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
            or      a                       ; CF=0
            ret
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
; In:  B = 0 report only, 1 force polled-hardware, 2 force /WAIT,
;          3 force polled-openMSX
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
            dec     a                   ; 1 -> 0 polled hw, 2 -> 1 wait,
            ld      (ix+o_ETH_MODE),a   ; 3 -> 2 polled openMSX
.report:
            pop     af
            ret
