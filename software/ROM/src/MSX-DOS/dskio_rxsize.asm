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

; BC = sector size for PerformHandshake, with bit 15 set when the interface
; has hardware /WAIT, asking the server for burst payloads (PAYLOAD_RX_BURST).
; Every supported interface reads port $57 below $80 (msxpi_bios.asm relies
; on that on every byte); with wait mode switched on, a CPLD v1.6 reads $8E
; and openMSX $FF. Wait mode is switched straight off again: it is only ever
; on inside a burst. Corrupts AF; returns CF=0.
DSKIO_RXSIZE:
        ld      bc,SECTORSIZE
        ld      a,1
        out     (CONTROL_PORT2),a
        in      a,(CONTROL_PORT2)
        rla                        ; CF = bit 7
        ld      a,0                ; (keeps CF)
        out     (CONTROL_PORT2),a
        ret     nc
        set     7,b
        or      a                  ; CF=0: PerformHandshake hands the caller's
        ret                        ; flags back, so a carry here reads as an error
