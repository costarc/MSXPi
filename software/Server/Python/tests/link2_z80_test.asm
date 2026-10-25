; Wrapper for the Z80 tests of link2.asm (z80_msx.py): the routines under test plus
; the little the BIOS would provide around them.  Assembled with sjasmplus.
    DEFINE MSXPI_LINK2
    DEFINE MSXPI_RAM_STASH
    INCLUDE "include.asm"
    ORG 0x0100
STORE_BYTE:                     ; the BIOS one writes through WRSLT in page 1; flat memory here
    ld   (de),a
    ret
PRINT:                          ; trapped by the test
    ret
    INCLUDE "payload_generated.asm"
    INCLUDE "link2.asm"

; The legacy checksum pass of PAYLOAD_RX_BURST (msxpi_bios.asm PRB_SUM), for the T-state baseline.
; In: DE = buffer, BC = count, HL = 0
BENCH_SUM:
    ld   a,(de)
    call PAYLOAD_ADVANCE
    jr   nz,BENCH_SUM
    ret
