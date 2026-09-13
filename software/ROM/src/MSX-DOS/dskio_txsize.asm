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

; BC = sector size for SENDDATA. Lives in a kernel gap because the driver has
; no room; DSKIO_RXSIZE took its place there.
;
; TEMPORARY: disk writes never burst. This used to set bit 15 - send the
; sector as a /WAIT burst (OTIR) - whenever the last block received had
; arrived as one (work area +7, see RECVDATA_ONEBLOCK). On a Canon V-25 with
; real v1.6 hardware that lost the first bytes of a sector: the MSX started
; its OTIR before the Pi raised READY for the burst, and a write OUT arms a
; CPLD transfer whether READY is up or not while /WAIT holds the Z80 only
; when it is, so the leading OUTs overwrote each other. A captured directory
; sector arrived shifted by ten bytes, and every COPY or pcopy to an MSXPi
; drive ended in "Disk error writing". Burst reads are unaffected - the CPLD
; will not start a read while READY is low - so only the write side is
; switched off, back to the polled writes of the previous builds. Restore
; the burst once READY and the start of an OTIR are sequenced safely.
DSKIO_TXSIZE:
        ld      bc,SECTORSIZE
        ret
