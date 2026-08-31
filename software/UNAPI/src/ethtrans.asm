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
;   ETH_MODE = 0  POLLED openMSX, and real hardware older than v1.6.
;                        A read must be requested by writing $56, then the
;                        status port polled, then $5A read.
;
; NOTE: openMSX only ever exercises the POLLED path - MSXPiDevice::readIO does
; not start anything on an `in ($5A)`, and $57 is read-only there.  The WAIT
; path therefore CANNOT be validated in emulation; it needs real hardware.
; =============================================================================

CTRL1:      equ     56h             ; status / read-request / reset
CTRL2:      equ     57h             ; version + wait-mode register
DATA1:      equ     5Ah             ; data

WAITMODE_ON:  equ   01h

; $57 read values.  Real hardware is $0E with wait mode off and $8E with it on;
; openMSX always returns $FE and ignores writes.
VER_WAIT_ON:  equ   8Eh
VER_OPENMSX:  equ   0FEh

; Polled-mode spin limit, in iterations of an ~30 T-state loop.  2048 is about
; 17 ms at 3.58 MHz: comfortably longer than the Pi's worst observed per-byte
; latency, and short enough that a single failure does not eat several
; interrupt slots.  It only ever runs to completion when something is broken,
; and the first timeout latches ETH_DEAD so it does not run again.
ETH_TIMEOUT:  equ   2048

; ETH_MODE values.
MODE_POLL_HW:   equ   0     ; polled, real hardware ($56 = 0 when done)
MODE_WAIT:      equ   1     ; hardware /WAIT, INIR/OTIR
MODE_POLL_OMSX: equ   2     ; polled, openMSX ($56 = 2 when a byte is queued)

; =============================================================================
; State
; =============================================================================
ETH_MODE:   db      0               ; one of MODE_* above
ETH_BUSY:   db      0               ; re-entrancy flag
ETH_DEAD:   db      0               ; link declared dead after a timeout

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
            ld      a,(ETH_DEAD)
            or      a
            jr      nz,.refuse
            ld      a,(ETH_BUSY)
            or      a
            jr      nz,.refuse

            ld      a,1
            ld      (ETH_BUSY),a            ; single instruction: atomic enough
            or      a                       ; CF=0: acquired
            ret
.refuse:
            scf
            ret

; --- ETH_UNLOCK: release the lock.  Preserves every register and the flags.
ETH_UNLOCK:
            push    af
            xor     a
            ld      (ETH_BUSY),a
            pop     af
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
            ld      a,(ETH_MODE)
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
            ld      a,(ETH_MODE)
            cp      MODE_WAIT
            jr      nz,.done
            xor     a                       ; wait mode off
            out     (CTRL2),a
.done:
            pop     af
            ret

; --- ETH_FAIL: called on any timeout.  Latches the link dead so the next ISR
; entry costs nothing, drops wait mode, and returns CF=1.  Corrupts AF.
ETH_FAIL:
            ld      a,1
            ld      (ETH_DEAD),a
            call    ETH_END
            scf
            ret

; --- ETH_REVIVE: clear the dead flag.  ETH_RESET uses this.  Corrupts AF.
ETH_REVIVE:
            xor     a
            ld      (ETH_DEAD),a
            ret

; =============================================================================
; Single byte transfers
; =============================================================================

; --- ETH_TX: send A.
; Out: CF=1 on timeout.  Corrupts AF.  BC/DE/HL preserved.
;
; The byte is parked in E, not C: ETH_WAIT_READY corrupts BC, so keeping it
; there would destroy the very byte being sent.
ETH_TX:
            push    bc
            push    de
            ld      e,a

            ld      a,(ETH_MODE)
            cp      MODE_WAIT
            jr      nz,.polled

            call    ETH_WAIT_READY          ; see the note in ETH_RX_BLOCK
            jr      c,.timeout
            ld      a,e                     ; wait mode: the OUT stalls us
            out     (DATA1),a
            jr      .ok

.polled:
            call    ETH_WAIT_READY
            jr      c,.timeout
            ld      a,e
            out     (DATA1),a
.ok:
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
ETH_RX:
            ld      a,(ETH_MODE)
            cp      MODE_WAIT
            jr      nz,.polled

            push    bc
            call    ETH_WAIT_READY          ; see the note in ETH_RX_BLOCK
            pop     bc
            jr      c,.rxfail
            in      a,(DATA1)               ; wait mode: the IN stalls us
            or      a                       ; preserves A, clears CF
            ret
.rxfail:
            scf
            ret

.polled:
            push    bc
            call    ETH_WAIT_READY          ; device must be idle first
            jr      c,.timeout
            xor     a
            out     (CTRL1),a               ; request a byte
            call    ETH_WAIT_DATA
            jr      c,.timeout
            in      a,(DATA1)
            pop     bc
            or      a
            ret
.timeout:
            pop     bc
            scf
            ret

; --- ETH_WAIT_READY: spin until $56 reads 0, bounded.
; Out: CF=1 on timeout.  Corrupts AF, BC.
; Accepts 0 (idle) and 2 (openMSX: a byte is already queued) as "not busy",
; matching the stock CHKPIRDY.  Waiting for 0 alone would deadlock under
; openMSX whenever a byte was still sitting in the queue.
ETH_WAIT_READY:
            ld      bc,ETH_TIMEOUT
.loop:
            in      a,(CTRL1)
            or      a
            ret     z                       ; ready, CF=0
            cp      2
            jr      nz,.next
            or      a                       ; CF=0
            ret
.next:
            dec     bc
            ld      a,b
            or      c
            jr      nz,.loop
            scf
            ret

; --- ETH_WAIT_DATA: spin until the requested byte is actually available.
; Out: CF=1 on timeout.  Corrupts AF, BC.
;
; The two polled backends report this DIFFERENTLY, and conflating them is a
; silent data-corruption bug rather than a hang:
;
;   real hardware  $56 = 0 means the SPI transfer has completed
;   openMSX        $56 = 0 means "connected, nothing queued"
;                  $56 = 2 means a byte is waiting
;
; An earlier version accepted 0 from either, so under openMSX it returned
; immediately and read $FF - MSXPiDevice::readIO's "no data ready" filler -
; producing a perfectly successful transaction full of garbage.  That is why
; ETH_MODE distinguishes polled-openMSX (2) from polled-hardware (0).
ETH_WAIT_DATA:
            ld      a,(ETH_MODE)
            cp      MODE_POLL_OMSX
            jr      z,.openmsx

            ld      bc,ETH_TIMEOUT
.hwloop:
            in      a,(CTRL1)
            or      a
            ret     z                       ; transfer done, CF=0
            dec     bc
            ld      a,b
            or      c
            jr      nz,.hwloop
            scf
            ret

.openmsx:
            ld      bc,ETH_TIMEOUT
.omloop:
            in      a,(CTRL1)
            cp      2
            jr      z,.omok
            dec     bc
            ld      a,b
            or      c
            jr      nz,.omloop
            scf
            ret
.omok:
            or      a                       ; CF=0
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

; --- ETH_TX_BLOCK: send BC bytes from HL.
; Out: CF=1 on timeout.  Corrupts AF, BC, DE, HL.
ETH_TX_BLOCK:
            ld      a,b
            or      c
            ret     z                       ; nothing to do, CF=0

            ld      a,(ETH_MODE)
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
            jr      z,.wlast                ; fewer than 256 bytes left
            push    bc
            ld      b,0                     ; B=0 means 256 iterations
            ld      c,DATA1
            otir
            pop     bc
            dec     b
            jr      .wloop
.wlast:
            ld      a,c
            or      a
            ret     z                       ; exact multiple of 256: done
            ld      b,c
            ld      c,DATA1
            otir
            or      a
            ret

.polled:
            push    bc
            ld      a,(hl)
            call    ETH_TX
            pop     bc
            ret     c
            inc     hl
            dec     bc
            ld      a,b
            or      c
            jr      nz,.polled
            or      a
            ret

; --- ETH_RX_BLOCK: receive BC bytes into HL.
; Out: CF=1 on timeout.  Corrupts AF, BC, DE, HL.
ETH_RX_BLOCK:
            ld      a,b
            or      c
            ret     z

            ld      a,(ETH_MODE)
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
