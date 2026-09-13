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
; really has hardware /WAIT, asking the server for burst payloads
; (PAYLOAD_RX_BURST).
;
; The test is "did the read-back CHANGE when wait mode was switched on?", not
; "is bit 7 set", so it rejects a pre-v1.6 CPLD, and any future device,
; without having to know what each of them answers:
;   CPLD v1.6   $0E -> $8E   changed  -> burst
;   CPLD v1.5   $0E -> $0E   same     -> polled
; openMSX emulates the v1.6 CPLD, so it answers the same way.
;
; Wait mode is switched straight off again in both paths: it is only ever on
; inside a burst. Corrupts AF; returns CF=0.
DSKIO_RXSIZE:
        in      a,(CONTROL_PORT2)  ; what $57 reads with wait mode off
        ld      b,a                ; BC is loaded below - LD leaves flags alone
        ld      a,1
        out     (CONTROL_PORT2),a  ; wait mode on
        in      a,(CONTROL_PORT2)
        cp      b                  ; did the read-back actually change?
        ld      bc,SECTORSIZE
        jr      z,RXSIZE_OFF       ; no: this device has no wait mode
        set     7,b
RXSIZE_OFF:
        xor     a                  ; also CF=0: PerformHandshake hands the
        out     (CONTROL_PORT2),a  ; caller's flags back, so a carry here
        ret                        ; would read as an error
