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

;|===========================================================================|
;| MSXPi Ethernet UNAPI - work area layout and ROM placement                 |
;|===========================================================================|
;
; Shared by BOTH assemblers, so every line here has to stay inside the syntax
; they both accept - plain "NAME<tab>EQU<tab>expression" and ; comments:
;
;   zmac   builds the MSX-DOS driver ROM   (ROM/src/MSX-DOS/msx-dos.mac)
;   sjasm  builds the UNAPI driver itself  (software/UNAPI/src)
;
; The driver keeps every mutable byte in a work area rather than in its own
; image, because the ROM build cannot write to itself.  Both builds use the
; SAME offsets and reach them through IX, so ethtrans.asm and ethops.asm have
; exactly one code path instead of a ROM copy and a RAM copy that drift apart.
;
; In the ROM build IX comes from the MSX-DOS kernel's GETWRK, i.e. the disk
; driver work area whose size MYSIZE declares.  Offsets 0..7 there already
; belong to the disk driver - 0..4 to DSKIO_SECTINFO, 5..7 to
; MSXPI_GETSTASH - so ours start at 8.  The RAM build simply reserves the
; same 8 bytes, which is cheaper than carrying two sets of offsets.

UNAPI_WRK	EQU	8	; first byte that belongs to the UNAPI driver

o_OLD_EXTBIO	EQU	UNAPI_WRK+0	; 5 - the hook we chain to
o_ETH_MODE	EQU	UNAPI_WRK+5	; MODE_*, or 0FFH = not detected yet
o_ETH_BUSY	EQU	UNAPI_WRK+6
o_ETH_DEAD	EQU	UNAPI_WRK+7
o_ETH_FAILCNT	EQU	UNAPI_WRK+8
o_ETH_LASTSEND	EQU	UNAPI_WRK+9
o_ETH_OPC	EQU	UNAPI_WRK+10
o_ETH_ARG	EQU	UNAPI_WRK+11
o_ETH_HASARG	EQU	UNAPI_WRK+12
o_ETH_RLEN	EQU	UNAPI_WRK+13
o_ETH_CHKRC	EQU	UNAPI_WRK+14
o_ETH_SUM	EQU	UNAPI_WRK+15
o_ETH_TMO	EQU	UNAPI_WRK+16	; per-byte spin budget, in units of 256
o_ETH_DEST	EQU	UNAPI_WRK+17	; 2
o_ETH_SRC	EQU	UNAPI_WRK+19	; 2
o_ETH_FLEN	EQU	UNAPI_WRK+21	; 2
o_MACADDR	EQU	UNAPI_WRK+23	; 6
o_ETH_BUF	EQU	UNAPI_WRK+29	; 7 - see below

; The disk driver's in-use flag: non-zero while a block transfer owns the link.
;
; MSXPi is ONE channel and the disk and the network both use ports 56/57/5A.
; InterNestor Lite polls from the 50/60Hz timer interrupt, so without this a
; disk read part-way through a block is interrupted, our ISR issues its own
; IN ($5A), and the two byte streams desynchronise permanently - silently, and
; onto a filesystem.  ETH_LOCK refuses while this is set; the ISR then reports
; "no frames" and tries again on the next tick, which costs nothing because
; TCP retransmits and frames wait in the Pi's queue meanwhile.
;
; It costs NO extra work area.  ETH_BUF was 8 bytes but the largest reply ever
; read into it is 7 (ETH_GET_HWADD: result code plus six address bytes), so
; this is the byte that was already there and unused.  That matters: MYSIZE is
; allocated by the disk kernel TWICE per initialisation, and on a machine with
; a built-in drive the memory below HIMEM is genuinely tight.
o_LINK_BUSY	EQU	UNAPI_WRK+36
o_LINK_SAVE	EQU	UNAPI_WRK+37	; DSKIO's saved copy of o_LINK_BUSY - see
				; LINK_BUSY_SET.  One slot is enough because
				; DSKIO is not reentrant.
o_SEND_P1	EQU	UNAPI_WRK+38	; reserved former page-1 source flag.
                                ; DSKIO stages sectors in its private buffer.
UNAPI_WRKEND	EQU	UNAPI_WRK+39	; UNAPI size; ROM MYSIZE adds its disk buffer

; Where the assembled driver is placed inside the MSX-DOS driver ROM.
;
; Fixed on purpose.  msxpi-driver.mac pads up to this address and asserts it
; has not already been passed, and asserts again that the driver image ends
; below 8000H - so MSXPi code growing into the driver, or the driver growing
; past the end of the ROM, fails the build loudly instead of silently
; producing a corrupt ROM.
UNAPI_ORG	EQU	07AB8H	; Boundary between the DOS driver below and the UNAPI
				; image above, chosen to split the free space evenly
				; between them (about 25 bytes each).  Both are tight;
				; the ASSERTs around UNAPI_ROM_IMAGE in msxpi-driver.mac
				; catch an overrun on either side, so move this only in
				; response to one of them, and re-measure afterwards.
