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
; MSXPi Ethernet UNAPI - ISR-safe transport core
; =============================================================================
; Everything here may be entered from InterNestor Lite's 50/60 Hz timer
; interrupt handler.  That imposes four hard rules, and every one of them is a
; deliberate departure from the stock msxpi_bios.asm primitives:
;
;   1. NO KEYBOARD ACCESS.  CHKPIRDY does `ld a,7 / out ($AA),a / in a,($A9)`
;      once per call and is called twice per byte.  Port $AA is the PPI
;      keyboard row-select register; writing it 60 times a second from inside
;      the interrupt corrupts the BIOS keyboard scan, which is exactly what a
;      telnet client depends on.
;
;   2. BOUNDED SPINS.  CHKPIRDY_POLL loops forever if the Pi never answers.
;      Inside an ISR that is a dead machine.  Every wait here is counted, and
;      a timeout latches ETH_DEAD so that subsequent calls fail immediately
;      instead of spending the whole interrupt slot spinning again.
;
;   3. RE-ENTRANCY.  A client calling ETH_SEND_FRAME from the foreground can be
;      interrupted by INL calling ETH_IN_STATUS.  ETH_LOCK is a DI-protected
;      test-and-set; the loser returns "nothing to do" rather than interleaving
;      bytes into the middle of someone else's transaction.
;
;   4. WAIT MODE IS PER-TRANSACTION.  It is turned on inside the lock and
;      always turned off before returning, so the rest of the system always
;      finds the device in legacy mode.
;
; -----------------------------------------------------------------------------
; Two backends
; -----------------------------------------------------------------------------
; ETH_MODE selects how a byte moves.  The installer detects it and patches it
; here before the hook goes live.
;
;   ETH_MODE = 1  WAIT   real MSXPi v1.6+ with hardware /WAIT.
;                        `out ($5A),a` and `in a,($5A)` each start a transfer
;                        AND stall the Z80 until it completes, so OTIR/INIR
;                        work and cost 21 T-states per byte.
;
;   ETH_MODE = 0  POLLED MSXPi before v1.6, or /WAIT not usable.
;                        A read must be requested by writing $56, then the
;                        status port polled, then $5A read.
;
; openMSX emulates the CPLD at port level, so both paths run there unchanged.
; =============================================================================

CTRL1:      equ     56h             ; status / read-request / reset
CTRL2:      equ     57h             ; version + wait-mode register
DATA1:      equ     5Ah             ; data

WAITMODE_ON:  equ   01h

; $57 read value with wait mode on ($0E with it off).
VER_WAIT_ON:  equ   8Eh

; Polled-mode spin limit, in iterations of an ~30 T-state loop.  2048 is about
; 17 ms at 3.58 MHz: comfortably longer than the Pi's worst observed per-byte
; latency, and short enough that a single failure does not eat several
; interrupt slots.  It only ever runs to completion when something is broken.
;
; The live value is (ix+o_ETH_TMO), counted in units of 256 iterations, and
; NOT because anyone wanted it adjustable: the very first transaction after a
; cold boot is much slower than every later one, because the other end builds
; its Ethernet shuttle lazily - importing the module and opening the TAP
; device - when the first opcode arrives.  With a fixed 17 ms budget that
; first transaction times out, and then the reply lands in a queue nobody is
; reading: every later transaction reads the previous one's answer.  That is
; not a lost call, it is permanent desync, and it is what made ETHTEST report
; the probe's "ETH" signature as the MAC address.
;
; So the work area starts at zero, which this loop reads as the LONGEST
; budget (65536 iterations, about half a second), and ETH_DETECT drops it to
; the normal value once the link has answered once.
ETH_TIMEOUT:  equ   2048

; ETH_MODE values.
MODE_POLL_HW:   equ   0     ; polled ($56 = 0 when done)
MODE_WAIT:      equ   1     ; hardware /WAIT, INIR/OTIR

; =============================================================================
; State
; =============================================================================
; Every mutable byte lives in the work area IX points at - see
; asm-common/include/unapi_wrk.inc for the offsets and for why.  The ROM build
; cannot write to itself, and keeping a separate ROM copy of this file was not
; an option, so BOTH builds reach their state through IX.
;
; MODE_UNKNOWN is what the ROM build starts with.  The transport cannot be
; probed at INIENV time, because on real hardware the Pi is usually still
; booting then and a probe would fail and lock us into the slow backend for
; the rest of the session; detection is deferred to the first UNAPI call.
MODE_UNKNOWN:   equ   0FFh

; How many consecutive failures before declaring the link dead.
;
; Latching on the FIRST failure was wrong.  On real hardware a transaction
; fails roughly once every 1400-2000 calls, and latching immediately turned
; that single glitch into permanent loss of networking: ETHBENCH reported 2032
; of 2048, meaning it worked 2032 times and then every remaining call was
; refused.  For InterNestor Lite, polling ETH_IN_STATUS sixty times a second,
; that would mean the network dies within the first minute and never returns.
;
; A transient deserves a retry; a genuinely absent Pi still gets given up on
; quickly, since eight consecutive timeouts cost well under a second.
ETH_MAXFAIL:  equ   8

; Drain limits for ETH_RESYNC.  ETH_DRAINTMO is the HIGH byte of the spin
; counter (see ETH_WAIT_READY), so 1 is ~256 iterations, a couple of
; milliseconds - long enough for a byte the other end has already queued to
; appear, short enough that a clean link is not punished.  ETH_DRAINMAX is
; sized for a whole stranded reply: a maximum Ethernet frame plus its header,
; not merely a few stray bytes.
; How many refused calls to sit out before a dead link gets another chance.
; 128 is about 2.5 s at INL's polling rate.
ETH_RETRYAFTER: equ 128

ETH_DRAINTMO: equ   1
ETH_DRAINMAX: equ   1600

; =============================================================================
; Locking
; =============================================================================

; --- ETH_LOCK: try to take the transaction lock.
; Out: CF=0 acquired, CF=1 busy or link dead.  Corrupts AF.
;
; NO `di` HERE, AND THAT IS DELIBERATE.
;
; The obvious implementation captures IFF2 with `ld a,i`, disables interrupts
; around the test-and-set, and restores them from P/V.  That is actively
; harmful on a Z80: `ld a,i` CLEARS P/V if an interrupt arrives while it is
; executing.  The restore then concludes "interrupts were off", skips the EI,
; and they stay off FOR EVER.  It cost a whole hardware debugging round - every
; ETHBENCH timing came back as zero jiffies because JIFFY had stopped being
; updated, while the transfers themselves were working perfectly.
;
; The lock does not need interrupts disabled, because the two contexts are
; asymmetric: the MSX timer interrupt runs to completion and cannot be
; preempted by the foreground.
;
;   - Foreground interrupted between the read and the write: the ISR sees 0,
;     takes the lock, finishes, releases, and only THEN does the foreground
;     resume and store 1.  Sequential, never overlapping.
;   - Foreground already stored 1: the ISR reads 1 and backs off.
;
; `ld (ETH_BUSY),a` is a single instruction, so there is no torn write. That is
; the whole argument.
ETH_LOCK:
            ; The disk owns the link right now - back off.  Reporting "nothing
            ; to do" is the right answer for the ISR: it simply tries again on
            ; the next tick, and the frame is still waiting in the Pi's queue.
            ld      a,(ix+o_LINK_BUSY)
            or      a
            jr      nz,.refuse
            ; A dead link is no longer a one-way door.  ETH_DEAD used to be
            ; cleared only by ETH_RESET or ETH_DETECT, and InterNestor Lite
            ; calls neither once installed - so a single burst of eight
            ; failures killed networking for the rest of the session, and the
            ; only cure was running ETHTEST to force a reset.  That is a very
            ; poor answer to what is usually a transient glitch, especially now
            ; that ETH_RESYNC drains the stranded reply that caused it.
            ;
            ; So count refusals while dead and let one attempt through every
            ; ETH_RETRYAFTER of them.  o_ETH_FAILCNT is reused rather than
            ; spending another byte of the DOS work area: it is only meaningful
            ; while the link is alive, and ETH_REVIVE zeroes it on the way out.
            ; At INL's 50/60 Hz polling that is a retry every ~2.5 seconds - it
            ; recovers on its own, without hammering a link that is genuinely
            ; down.
            ld      a,(ix+o_ETH_DEAD)
            or      a
            jr      z,.alive
            inc     (ix+o_ETH_FAILCNT)
            ld      a,(ix+o_ETH_FAILCNT)
            cp      ETH_RETRYAFTER
            jr      c,.refuse
            call    ETH_REVIVE              ; clears DEAD and FAILCNT; keeps
                                            ; every register and the flags
.alive:
            ld      a,(ix+o_ETH_BUSY)
            or      a
            jr      nz,.refuse

            ld      (ix+o_ETH_BUSY),1       ; single instruction: atomic enough
            or      a                       ; A is still 0 here: CF=0, acquired
            ret
.refuse:
            scf
            ret

; --- ETH_UNLOCK: release the lock.  Preserves every register and the flags.
ETH_UNLOCK:
            ld      (ix+o_ETH_BUSY),0
            ret

; =============================================================================
; Transaction framing
; =============================================================================

; --- ETH_BEGIN: check the Pi is there and switch the device into wait mode.
; Out: CF=0 ready, CF=1 not ready.  Corrupts AF.
;
; $56 bit 0 is `SPI_en_s or (not SPI_RDY)`, so a non-zero read means either a
; transfer is in flight or the Pi is not asserting RDY.  Checking it once here
; is what stops a wait-mode burst from silently reading stale bytes: with
; SPI_RDY low the CPLD does not start a transfer and does not stall, so an
; INIR would run at full speed and return garbage.
ETH_BEGIN:
            ld      a,(ix+o_ETH_MODE)
            cp      MODE_WAIT
            jr      nz,.polled_ok           ; polled modes check per byte

            in      a,(CTRL1)
            or      a
            jr      nz,.notready
            ld      a,WAITMODE_ON
            out     (CTRL2),a
.polled_ok:
            or      a                       ; CF=0
            ret
.notready:
            scf
            ret

; --- ETH_END: leave the device exactly as we found it.  Preserves all regs.
ETH_END:
            push    af
            ld      a,(ix+o_ETH_MODE)
            cp      MODE_WAIT
            jr      nz,.done
            xor     a                       ; wait mode off
            out     (CTRL2),a
.done:
            pop     af
            ret

; --- ETH_FAIL: one failed transaction.  Counts it, and only gives up on the
; link once ETH_MAXFAIL of them happen back to back.  Drops wait mode and
; returns CF=1.  Corrupts AF.
ETH_FAIL:
            call    ETH_RESYNC
            inc     (ix+o_ETH_FAILCNT)
            ld      a,(ix+o_ETH_FAILCNT)
            cp      ETH_MAXFAIL
            jr      c,.notdead
            ld      (ix+o_ETH_DEAD),1
.notdead:
            call    ETH_END
            scf
            ret

; --- ETH_OK: one successful transaction.  Clears the consecutive-failure run.
; Preserves every register and the flags.
ETH_OK:
            ld      (ix+o_ETH_FAILCNT),0
            ret

; --- ETH_RESYNC: put the device back to a known state after a failure.
;
; A failed transaction is NOT self-contained.  Whatever bytes of the reply the
; MSX did not collect stay queued, so the next transaction reads them instead
; of its own, fails in turn, and the run cascades - one glitch becomes total
; loss.  Injecting a stale read once per 500 in emulation showed exactly that:
; roughly eight isolated faults, spread far apart, still killed the link inside
; 250 calls because each one poisoned its successors.
;
; Writing $FF to $56 is the existing MSXPi reset - resetMSXPI does the same at
; the start of every command - and clears the CPLD transfer state and any byte
; waiting to be read.  It also clears wait mode, which ETH_END does anyway.
;
; This is why tolerating consecutive failures is not on its own enough: without
; the resync the failures are never independent.
;
; It is not a complete answer either.  It resets OUR side; a reply the other
; end had already produced is still waiting to be clocked out, which is why
; the drain below follows.
ETH_RESYNC:
            push    af
            push    bc
            push    de
            ld      a,0FFh
            out     (CTRL1),a           ; clear OUR side first, as before

            ; Then drain THEIR side.  Writing $FF resets the CPLD but says
            ; nothing to msxpi-server.py, which is a separate process with its
            ; own state machine: a reply it has already produced is still
            ; queued, and the next command - very often a DSKIO, since the disk
            ; shares this link - reads that instead of its own answer.  On real
            ; hardware that surfaced as MSX-DOS asking to "Insert a DOS disk in
            ; the default drive" right after quitting a network program, with
            ; the Ethernet side still perfectly healthy.
            ;
            ; There is no status bit for "bytes are waiting" that is meaningful
            ; before a read is requested - $56 reads 0 both when idle and when
            ; a byte is ready - so the only way to ask is to request one and
            ; see.  The loop therefore ends the moment a request times out,
            ; which on an already-clean link costs a single short spin.
            ld      e,(ix+o_ETH_TMO)    ; save the normal timeout
            ld      (ix+o_ETH_TMO),ETH_DRAINTMO
            ld      bc,ETH_DRAINMAX
.drain:
            push    bc
            call    ETH_RX
            pop     bc
            jr      c,.drained          ; nothing came - both ends in step
            dec     bc
            ld      a,b
            or      c
            jr      nz,.drain
.drained:
            ld      (ix+o_ETH_TMO),e    ; restore
            ld      a,0FFh
            out     (CTRL1),a           ; the losing ETH_RX left a read
                                        ; request outstanding; clear it
            pop     de
            pop     bc
            pop     af
            ret

; --- ETH_REVIVE: clear the dead flag and the failure run.  ETH_RESET uses
; this, and so does ETH_DETECT as its last act - which is why it must preserve
; every register AND the flags: ETH_DETECT's carry, saying whether anything
; answered at all, has to survive it.
ETH_REVIVE:
            ld      (ix+o_ETH_DEAD),0
            ld      (ix+o_ETH_FAILCNT),0
            ret

; =============================================================================
; Single byte transfers
; =============================================================================

; --- ETH_TX: send A.
; Out: CF=1 on timeout.  Corrupts AF.  BC/DE/HL preserved.
;
; There is no mode test here, and there does not need to be: sending is the
; same instruction sequence either way.  The only difference is invisible to
; this code - in wait mode the OUT itself stalls the Z80 until the transfer
; completes, in polled mode it returns at once and the NEXT ETH_WAIT_READY
; is what waits.  (An earlier version branched on the mode into two literally
; identical blocks.)
;
; The byte is parked in E, not C: ETH_WAIT_READY corrupts BC, so keeping it
; there would destroy the very byte being sent.
ETH_TX:
            push    bc
            push    de
            ld      e,a
            call    ETH_WAIT_READY          ; see the note in ETH_RX_BLOCK
            jr      c,.timeout
            ld      a,e
            out     (DATA1),a
            pop     de
            pop     bc
            or      a                       ; CF=0
            ret
.timeout:
            pop     de
            pop     bc
            scf
            ret

; --- ETH_RX: receive into A.
; Out: CF=1 on timeout.  Corrupts AF.  BC/DE/HL preserved.
;
; Receiving DOES differ by mode, but only by the middle step: in wait mode the
; IN both starts the transfer and stalls us, while a polled backend has to ask
; for the byte first and then wait for it to arrive.
ETH_RX:
            push    bc
            call    ETH_WAIT_READY          ; device must be idle first
            jr      c,.timeout
            ld      a,(ix+o_ETH_MODE)
            cp      MODE_WAIT
            jr      z,.get
            xor     a
            out     (CTRL1),a               ; request a byte
            call    ETH_WAIT_DATA
            jr      c,.timeout
.get:
            in      a,(DATA1)
            pop     bc
            or      a                       ; preserves A, clears CF
            ret
.timeout:
            pop     bc
            scf
            ret

; --- ETH_WAIT_READY: spin until $56 reads 0, bounded.
; Out: CF=1 on timeout.  Corrupts AF, BC.
; $56 = 0: no transfer running and the Pi is holding READY.
ETH_WAIT_READY:
            ld      c,0
            ld      b,(ix+o_ETH_TMO)
.loop:
            in      a,(CTRL1)
            or      a
            ret     z                       ; ready, CF=0
            dec     bc
            ld      a,b
            or      c
            jr      nz,.loop
            scf
            ret

; --- ETH_WAIT_DATA: spin until the requested byte is actually available.
; Out: CF=1 on timeout.  Corrupts AF, BC.
; After the request, $56 = 0 means the transfer has completed and the byte is
; in the shift register.
ETH_WAIT_DATA:
            ld      c,0
            ld      b,(ix+o_ETH_TMO)
.loop:
            in      a,(CTRL1)
            or      a
            ret     z                       ; byte available, CF=0
            dec     bc
            ld      a,b
            or      c
            jr      nz,.loop
            scf
            ret

; =============================================================================
; Block transfers
; =============================================================================
; The mode test happens once per block, not once per byte: in wait mode the
; inner loop is a plain INIR/OTIR at 21 T-states per byte, which is the entire
; point of the CPLD /WAIT work.
;
; The 256-byte chunking below is deliberately written so that a length which is
; an exact multiple of 256 does NOT transfer an extra block - the obvious
; formulation (test the high byte, else send C bytes) sends 256 spurious bytes
; when C is zero.

; WHY THE READY WAIT BEFORE A BURST
;
; The CPLD only starts a transfer, and therefore only asserts /WAIT, while
; SPI_RDY is high - and the Pi raises RPI_READY only once it is actually inside
; a transfer routine.  After receiving our opcode byte it DROPS RDY, runs the
; Python dispatch (recvdata2 -> eth_handle_opcode -> shuttle -> _write_many),
; and only then does SPI_BurstOut raise RDY again for the reply.
;
; An INIR issued the instant the opcode OUT completes races that dispatch. If
; RDY is still low the reads neither stall nor transfer, and the burst returns
; garbage at full speed.  That is why hardware /WAIT measured as intermittent -
; 2028 of 2048 on one run, 369 on the next.
;
; Waiting once per burst, not per byte, keeps INIR at 21 T-states inside the
; run: SPI_BurstOut holds RDY high for the whole reply, so only the boundary
; needs guarding.

; There is no ETH_TX_BLOCK.  One existed and was never called: every send
; goes through ETH_TX_SUM, which has to see each byte to accumulate the
; checksum the Pi verifies.  Sending a frame therefore costs a CALL per byte
; instead of OTIR's 21 T-states - the obvious fix is to sum the buffer in one
; pass and then OTIR it in a second, but that is a change to a path that has
; never carried a real frame, so it is left for when one does.

; --- ETH_RX_BLOCK: receive BC bytes into HL.
; Out: CF=1 on timeout.  Corrupts AF, BC, DE, HL.
ETH_RX_BLOCK:
            ld      a,b
            or      c
            ret     z

            ld      a,(ix+o_ETH_MODE)
            cp      MODE_WAIT
            jr      nz,.polled

            push    bc                      ; ETH_WAIT_READY corrupts BC
            push    hl
            call    ETH_WAIT_READY
            pop     hl
            pop     bc
            ret     c

.wloop:
            ld      a,b
            or      a
            jr      z,.wlast
            push    bc
            ld      b,0
            ld      c,DATA1
            inir
            pop     bc
            dec     b
            jr      .wloop
.wlast:
            ld      a,c
            or      a
            ret     z
            ld      b,c
            ld      c,DATA1
            inir
            or      a
            ret

.polled:
            push    bc
            call    ETH_RX
            pop     bc
            ret     c
            ld      (hl),a
            inc     hl
            dec     bc
            ld      a,b
            or      c
            jr      nz,.polled
            or      a
            ret
