; =============================================================================
; MSXPi Ethernet UNAPI - resident code, ROM (MSX-DOS driver ROM) build
; =============================================================================
; Assembled at a fixed address in the free tail of msxpibios.rom and INCBIN'd
; by ROM/src/MSX-DOS/msxpi-driver.mac, which asserts that neither the MSXPi
; code below nor this image above has run into the other.
;
; WHY THIS BUILD EXISTS
; ---------------------
; A ROM implementation reports segment $FF, so InterNestor Lite takes its
; CALSLT path - the one ObsoNET and every other field implementation uses.
; INL's RAM-segment path has four defects (two patched in software/UNAPI/inl/,
; plus "INL S" reporting not-installed and "INL I" hanging), and forcing our
; transport to the bounded polled path changed none of them, so the fault is
; in INL code nobody has exercised.  Going ROM sidesteps all of it and means
; users run stock INL.
;
; Everything below the "Shared" line is byte-for-byte the same code as the RAM
; build in ethseg.asm.  What differs is only what has to: how the EXTBIO hook
; is entered, where the work area is, and that the segment reported is $FF.
; =============================================================================

EXTBIO:     equ     0FFCAh
ARG:        equ     0F847h

; --- Entry points borrowed from the MSX-DOS kernel in the same ROM ----------
; Both live in the kernel half of ROM/src/MSX-DOS/msx-dos.mac, which sits
; entirely below this image, so adding or removing MSXPi code cannot move
; them.  They are hardcoded because zmac and sjasm cannot share a symbol
; table; msxpi-driver.mac ASSERTs both values against the real labels, so a
; kernel edit that did move them fails the build instead of jumping into
; whatever landed at the old address.
;
;   GETSLT  A = this ROM's slot id (expanded-slot bits included)
;           corrupts AF, BC, HL; DE preserved
;   GETWRK  HL = IX = this disk driver's work area (MYSIZE bytes)
;           corrupts AF, BC, HL, IX; DE preserved
GETSLT:     equ     06016h
GETWRK:     equ     06025h

            include "../../asm-common/include/unapi_wrk.inc"

            org     UNAPI_ORG

; =============================================================================
; Initialisation - called from the disk ROM's INIENV
; =============================================================================
; INIENV is the right hook: by the time the kernel calls it, it has allocated
; the MYSIZE work area and stored it in SLTWRK (so GETWRK works), and it has
; already initialised the EXTBIO hook to five RETs and set HOKVLD - either
; here or in whichever disk ROM started the disk system first.  That is why
; there is no HOKVLD check below; both paths through A576F reach INIENV only
; after the hook is valid.
;
; This must be the FIRST byte of the image: msxpi-driver.mac's INIENV is a
; plain jump to UNAPI_ORG and knows nothing else about the layout.
UNAPI_ROM_INIT:
            ; The disk ROM's INIT can run more than once - INIHRD is written
            ; to expect it.  Installing the hook a second time would chain it
            ; to itself and hang the first discovery call, so recognise our
            ; own handler and stop.
            ;
            ; This assumes a repeat INIT reuses the same work area.  It would
            ; not, if the kernel reached A580C again - it allocates a fresh
            ; MYSIZE block there - and the saved hook below would then be lost
            ; while EXTBIO still pointed here.  On the machines tested it does
            ; not happen: EXTBIO chaining works, and a lost hook would crash
            ; the first discovery call rather than degrade.  Konamiman's
            ; unapi-rom.asm does not guard against a repeat INIT at all.
            ld      hl,(EXTBIO+2)
            ld      de,DO_EXTBIO
            or      a
            sbc     hl,de
            ret     z

            ; Clear our slice of the work area.  The kernel allocates it below
            ; HIMEM and does not zero it, and MACADDR in particular must start
            ; as zeros: ETH_GET_HWADD falls back to that cache when a fetch
            ; fails, so a non-zero address there has to be proof that a real
            ; fetch succeeded.
            call    GETWRK
            ld      de,UNAPI_WRK
            add     hl,de
            ld      d,h
            ld      e,l
            inc     de
            ld      (hl),0
            ld      bc,UNAPI_WRKEND-UNAPI_WRK-1
            ldir

            ; Keep the hook we are displacing, then take it over.
            call    OLDHOOK
            ex      de,hl
            ld      hl,EXTBIO
            ld      bc,5
            ldir

            ; DI but NO EI.  unapi-rom.asm's INIT does both, but it is a
            ; plain ROM entered from the BIOS slot scan; INIENV is called from
            ; INSIDE the disk kernel's own critical section - A576F disables
            ; interrupts right after INIHRD and nothing re-enables them before
            ; here - so an EI would switch them back on underneath the kernel
            ; and leave it running with interrupts it expects to be off.  The
            ; DI stays because it costs nothing and is correct if this is ever
            ; reached with them on; leaving them off afterwards is exactly the
            ; state the kernel had.
            di
            ld      a,0F7h              ; RST 30h: inter-slot call with the
            ld      (EXTBIO),a          ; slot and address inline after it
            call    GETSLT
            ld      (EXTBIO+1),a
            ld      hl,DO_EXTBIO
            ld      (EXTBIO+2),hl
            ld      a,0C9h              ; RET - exactly fills the 5 bytes
            ld      (EXTBIO+4),a

            ; Nothing is probed here.  On real hardware the Pi is usually
            ; still booting when the disk system initialises, so a probe would
            ; fail and pin the driver to the slow polled backend for the rest
            ; of the session.  The first UNAPI call detects the transport
            ; instead, by which time the machine has booted off the Pi and the
            ; link is known good.
            call    ETH_WRK
            ld      (ix+o_ETH_MODE),MODE_UNKNOWN
            ret

; =============================================================================
; EXTBIO hook execution
; =============================================================================
; Entered by the RST 30h planted above, so page 1 already holds this ROM.
; Per MSX-UNAPI 3.3: not our DE -> chain; A=FFh -> chain (so the RAM helper
; can install); wrong API id -> chain; A=0 -> B=B+1 and chain; A=1 -> answer;
; A>1 -> A=A-1 and chain.  Structure follows examples/unapi-rom.asm.
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
            call    OLDHOOK             ; HL = saved hook; DE, and the pushed
            pop     af                  ; AF/BC/HL, are all untouched
            pop     bc
            or      a
            jr      nz,DO_EXTBIO2
            inc     b
            ex      (sp),hl             ; HL = caller's, hook address on top
            ld      de,2222h
            ret
DO_EXTBIO2:

            ; --- A=1: report slot, segment and entry point.  Do NOT chain.
            ; B=FFh is what makes this worth doing: it tells the caller the
            ; implementation is not in a mapped segment, so it uses CALSLT.
            dec     a
            jr      nz,DO_EXTBIO3
            pop     hl
            call    GETSLT
            ld      b,0FFh
            ld      hl,UNAPI_ENTRY
            ld      de,2222h
            ret

            ; --- A>1: decrement (already done) and chain
DO_EXTBIO3:
            ex      (sp),hl
            ld      de,2222h
            ret

JUMP_OLD2:
            ld      de,2222h
JUMP_OLD:                               ; assumes hl, bc, af pushed
            call    OLDHOOK             ; DE survives this - see GETWRK above
            pop     af
            pop     bc
            ex      (sp),hl
            ret

; --- OLDHOOK: HL = where the displaced EXTBIO hook is kept.
; Corrupts AF, BC, HL and IX; DE is preserved.
OLDHOOK:
            call    GETWRK
            ld      bc,o_OLD_EXTBIO
            add     hl,bc
            ret

TOUPPER:
            cp      "a"
            ret     c
            cp      "z"+1
            ret     nc
            sub     20h
            ret

; --- ETH_WRK: point IX at the work area.
; In this build that is exactly what the kernel's GETWRK does, so the shared
; code can call it directly and the indirection costs nothing.
ETH_WRK:    equ     GETWRK

; =============================================================================
; Data
; =============================================================================

; The identifier must be zero-terminated and is compared case-insensitively.
UNAPI_ID:
            db      "ETHERNET",0

; At most 63 characters plus the terminating zero, printable only, and it must
; live in the same slot as the code (MSX-UNAPI rule 5).
APIINFO:
            db      "MSXPi Ethernet UNAPI",0

; =============================================================================
; Shared with the RAM build (ethseg.asm)
; =============================================================================
            include "ethtrans.asm"
            include "ethops.asm"
            include "ethcore.asm"

ROM_CODE_END:
