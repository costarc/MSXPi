/*
 * MSXPi Interface
 * Version 1.7.0
 * ------------------------------------------------------------------------------
 * MIT License
 *
 * Copyright (c) 2015-2026 Ronivon Costa
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 * ------------------------------------------------------------------------------
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "../header/fusion.h"
#include "../header/msxpi.h"

// pprintf: print a string followed by a number
void pprintf(char* text, uint16_t value) {
    Print(text);          // print the string
    PrintNumber(value);   // print the number
}

// pprints: print a string followed by a string value
void pprints(char* text, char* value) {
    Print(text);          // print the string
    Print(value);   // print the number
}

// This function prints text at specified (x,y) position faster
// than using Locate + Print, by directly outputting characters to port 0x98
// The first character is printed using PrintChar to set the position,
// then the rest are sent directly to the port.
void FastPrint(char* text) {
    PrintChar(*text); text++;
    while (*text != 0) {
        OutPort(0x98, *text);
        text++;
    }
}

/* -----------------------
   LINK2 (documents/LINK2-DESIGN.md)
   -----------------------
   The routines are asm-common/include/link2.asm, the very code the ROM and the asm
   tools assemble, turned into SDAS by asm-common/transport/generate.py
   (link2_generated.h).  One call moves a whole transfer: the framing, the CRC, the
   retries and the aborts are in there, and CTRL+ESC ends a wait.

   The CRC wants a 512 byte table on a page boundary.  It is built in RAM, on the
   first transfer, rather than carried in every program.  This is built with
   --no-std-crt0 and BSS is not cleared, so "built already" is told by looking at
   the table, not by a flag.
 */
#include "link2_generated.h"

uint8_t l2_table_page;                 /* read by the asm */
static uint8_t l2_table_mem[768];      /* the table needs 512 of them, aligned */

/* The asm calls these two (link2.asm needs STORE_BYTE and PRINT of the BIOS half). */
void l2_print(char* text) __sdcccall(1) { Print(text); }

static void link2_support(void) __naked
{
    __asm
STORE_BYTE:
    ld (de),a
    ret
PRINT:
    push ix
    push iy
    call _l2_print
    pop iy
    pop ix
    ret
    __endasm;
}

static void l2_table_build(uint8_t* hi) {
    uint16_t i, c;
    uint8_t  bit;
    for (i = 0; i < 256; i++) {
        c = i << 8;
        for (bit = 0; bit < 8; bit++)
            c = (c & 0x8000) ? (uint16_t)((c << 1) ^ 0x1021) : (uint16_t)(c << 1);
        hi[i] = c >> 8;
        hi[256 + i] = c & 0xFF;
    }
}

static void l2_table_ensure(void) {
    uint8_t* hi = (uint8_t*)(((uint16_t)l2_table_mem + 255) & 0xFF00);
    /* T[1] = 1021h and T[255] = 1EF0h, both halves */
    if (hi[1] != 0x10 || hi[257] != 0x21 || hi[255] != 0x1E || hi[511] != 0xF0)
        l2_table_build(hi);
    l2_table_page = (uint8_t)((uint16_t)hi >> 8);
}

/* DE = source, BC = length -> A.  __sdcccall(0): arguments on the stack under either convention. */
static uint8_t l2_send(const uint8_t* src, uint16_t size) __sdcccall(0) __naked
{
    src; size;
    __asm
    push ix
    push iy
    ld ix,#6
    add ix,sp
    ld e,0(ix)
    ld d,1(ix)
    ld c,2(ix)
    ld b,3(ix)
    call LINK_SEND
    ld l,a
    pop iy
    pop ix
    ret
    __endasm;
}

/* A = mode, DE = buffer, BC = largest block -> A = result code, BC = bytes received. */
static uint8_t l2_recv(uint16_t mode, uint8_t* buffer, uint16_t maxblock,
                       uint16_t* received) __sdcccall(0) __naked
{
    mode; buffer; maxblock; received;
    __asm
    push ix
    push iy
    ld ix,#6
    add ix,sp
    ld a,0(ix)
    ld e,2(ix)
    ld d,3(ix)
    ld c,4(ix)
    ld b,5(ix)
    call LINK_RECV
    ld l,a
    jr nc,l2_recv_got
    ld bc,#0
l2_recv_got:
    ld ix,#6                    ; LINK_RECV left IX at its frame
    add ix,sp
    ld e,6(ix)
    ld d,7(ix)
    ld a,d
    or e
    jr z,l2_recv_done
    ld a,c
    ld (de),a
    inc de
    ld a,b
    ld (de),a
l2_recv_done:
    pop iy
    pop ix
    ret
    __endasm;
}

uint8_t link_send(const uint8_t* src, uint16_t size) {
    if (size == 0)
        return RC_SUCCESS;
    l2_table_ensure();
    return l2_send(src, size);
}

/*
 * One whole transfer from the Pi (design 5.3).  mode 0: the blocks are read and dropped,
 * 1: each is printed, 2: they follow one another from buffer.  maxblock is the largest
 * block the Pi may send; in modes 0 and 1 the buffer needs one byte more.  *received is
 * the number of bytes.  Returns RC_SUCCESS, the code the Pi ended the transfer with, or
 * RC_PROTOERR / RC_ESCPRESSED.
 */
uint8_t link_recv(uint8_t mode, uint8_t* buffer, uint16_t maxblock, uint16_t* received) {
    l2_table_ensure();
    return l2_recv(mode, buffer, maxblock, received);
}

/*
 * A transfer taken block by block, for the callers that put each block somewhere of their
 * own (a ROM bank, a screen).  The state is the same frame LINK_RECV keeps on the stack:
 * L2_FRAME + L2_ARGS_LEN = 26 bytes at a fixed place, so one such transfer at a time.
 * link_recv_open: first = where the first block goes (it decides whether the Pi may burst
 * into it: page 2 and 3 only), maxblock = the largest block.  link_recv_next: the block
 * goes to dest; *length is its size.  Returns RC_READY for a block with more to follow,
 * RC_SUCCESS (or the code the Pi ended with) for the last one, RC_PROTOERR / RC_ESCPRESSED.
 */
static uint8_t l2_frame[26];

static uint8_t l2_recv_open(uint8_t* first, uint16_t maxblock) __sdcccall(0) __naked
{
    first; maxblock;
    __asm
    push ix
    push iy
    ld ix,#6
    add ix,sp
    ld e,0(ix)
    ld d,1(ix)
    ld c,2(ix)
    ld b,3(ix)
    ld ix,#_l2_frame
    ld hl,#_l2_frame
    ld a,#26
l2_open_clear:
    ld (hl),#0
    inc hl
    dec a
    jr nz,l2_open_clear
    ld 19(ix),#2                ; L2_MODE
    ld 20(ix),c                 ; L2_SIZE
    ld 21(ix),b
    ld 22(ix),e                 ; L2_PTR
    ld 23(ix),d
    call L2_OPEN
    jr c,l2_open_done
    ld a,#0xe0                  ; RC_SUCCESS
l2_open_done:
    ld l,a
    pop iy
    pop ix
    ret
    __endasm;
}

static uint8_t l2_recv_next(uint8_t* dest, uint16_t* length) __sdcccall(0) __naked
{
    dest; length;
    __asm
    push ix
    push iy
    ld iy,#6
    add iy,sp
    ld e,0(iy)
    ld d,1(iy)
    ld ix,#_l2_frame
    ld 22(ix),e                 ; L2_PTR
    ld 23(ix),d
    call L2_RECV_BLOCK
    ld l,a
    ld bc,#0
    jr c,l2_next_store
    ld c,10(ix)                 ; L2_LEN
    ld b,11(ix)
l2_next_store:
    ld e,2(iy)
    ld d,3(iy)
    ld a,d
    or e
    jr z,l2_next_done
    ld a,c
    ld (de),a
    inc de
    ld a,b
    ld (de),a
l2_next_done:
    pop iy
    pop ix
    ret
    __endasm;
}

uint8_t link_recv_open(uint8_t* first, uint16_t maxblock) {
    l2_table_ensure();
    return l2_recv_open(first, maxblock);
}

uint8_t link_recv_next(uint8_t* dest, uint16_t* length) {
    return l2_recv_next(dest, length);
}


char* GetCmdLineParameters(void) {
    unsigned char len = *((unsigned char*)0x80);   // length at 0x80
    char* cmdTail = (char*)0x81;                   // tail starts at 0x81

    // Ensure null termination
    cmdTail[len] = '\0';

    // Skip leading spaces
    while (*cmdTail == ' ') {
        cmdTail++;
    }

    return cmdTail;  // return pointer to trimmed command
}

uint8_t link_command(const char* cmd, bool appendTail) {
    const char* tail = GetCmdLineParameters();   // Fusion‑C: already zero‑terminated
    const char* primary = cmd;
    uint16_t lenPrimary = 0;
    uint16_t lenTail = 0;

    // ---------------------------------------------------------
    // 1. Determine primary source
    // ---------------------------------------------------------
    if (primary == NULL || primary[0] == 0) {
        // Case 1 and Case 2: empty cmd → use only DOS tail
        primary = tail;

        if (primary == NULL || primary[0] == 0) {
            return RC_INVALIDCOMMAND;
        }

        appendTail = false;   // prevent tail+tail duplication
    }

    // Count primary length
    while (primary[lenPrimary] != 0) {
        lenPrimary++;
    }

    // Count tail length only if needed
    if (appendTail && tail != NULL) {
        while (tail[lenTail] != 0) {
            lenTail++;
        }
    }

    // ---------------------------------------------------------
    // 2. Build final buffer
    // ---------------------------------------------------------
    // This used to be pinned at BUFADDRESS (0xC000, page 3) - the same fixed
    // address msxarch.c uses for its 8 KB ROM-landing buffer - to save RAM by
    // time-sharing one physical scratch region. But BUFADDRESS is a
    // compile-time guess at "free RAM", not a checked one: a resident TSR
    // sitting at/near 0xC000 (observed with a TSR left loaded on real
    // hardware) silently aliases with it. The command string is short - a
    // DOS command tail plus a command word is at most CMDBUFSIZE bytes - so
    // it never needed 8 KB or a fixed address in the first place. Ordinary
    // _DATA is safely inside THIS program's own TPA allocation, which DOS
    // does not hand to any properly-behaved resident program, so a small
    // unpinned buffer here cannot collide with one.  msxarch.c's own
    // BUFADDRESS use for the large ROM payload is untouched - that one does
    // need a fixed page-3 address to survive its Put_PN bank switching.
    static char buffer[CMDBUFSIZE];
    uint16_t total = 0;

    // Copy primary
    for (uint16_t i = 0; i < lenPrimary && total < CMDBUFSIZE - 1; i++) {
        buffer[total++] = primary[i];
    }

    // Append tail if requested
    if (appendTail && lenTail > 0) {
        // Insert a space only if primary is non-empty
        if (total > 0 && total < CMDBUFSIZE - 1) {
            buffer[total++] = ' ';
        }

        for (uint16_t i = 0; i < lenTail && total < CMDBUFSIZE - 1; i++) {
            buffer[total++] = tail[i];
        }
    }

    // Null-terminate (not sent, but safe)
    buffer[total] = 0;

    if (total == 0) {
        return RC_FAILED;
    }

    // ---------------------------------------------------------
    // 3. Send to MSX‑Pi
    // ---------------------------------------------------------
    return link_send((uint8_t*)buffer, total);
}

uint8_t parseConnError(const uint8_t rc) {
    if (rc == RC_CHKSUM_ERR) {
        Print("Checksum mismatch.");
    }
    else if (rc == RC_INVALIDCOMMAND) {
        Print("Invalid or missing parameters.");
    }
    else if (rc == RC_CONNERR) {
        Print("Error connecting to MSXPi server.");
    }
    else if (rc == RC_BUFOVFLW) {
        Print("Data size too large - truncated.");
    }
    else if (rc == RC_PROTOERR) {
        Print("Link error.");
    }
    else if (rc == RC_HANDSHAKEERR) {
        Print("Handshake error.");
    }
    else if (rc == RC_FILENOTFOUND) {
        Print("File not found on Pi server.");
    }
    else if (rc != RC_SUCCESS && rc != RC_FAILED) {
        pprintf("Unknown error code: 0x", rc);
    }
    return rc;
}

uint16_t get_sp(void) __sdcccall(0) __naked {   /* returns SP in HL */
    __asm
    ld hl, #0
    add hl, sp
    ret
    __endasm;
}

uint16_t get_max_buffer_size(void) {
    uint16_t start = heap_top;
    uint16_t sp = get_sp();
    return (sp - start - 32);
}

uint8_t* get_buffer_ptr(void) {
    return (uint8_t*)heap_top;
}

//
// Converts a 16-bit integer (0–65535) to ASCII.
// Writes the result into 'buf' and returns buf.
// buf must be at least 6 bytes long.
//
char* u16_to_ascii(uint16_t value, char* buf)
{
    char temp[6];      // enough for "65535\0"
    uint8_t i = 0;
    uint8_t j = 0;

    // Special case: zero
    if (value == 0) {
        buf[0] = '0';
        buf[1] = 0;
        return buf;
    }

    // Extract digits in reverse order
    while (value > 0) {
        temp[i++] = '0' + (value % 10);
        value /= 10;
    }

    // Reverse digits into output buffer
    while (i > 0) {
        buf[j++] = temp[--i];
    }

    buf[j] = 0;   // null terminate
    return buf;
}


// ============================================================================
// Shared-link claim  (UNAPI implementation-specific routine 129)
// ============================================================================
// The MSXPi link carries the disk, these commands, AND the Ethernet UNAPI
// driver.  Once InterNestor Lite is resident it polls ETH_IN_STATUS from the
// 50/60 Hz timer interrupt, and that ISR will happily transmit in the middle
// of one of our exchanges.  Observed on hardware: `p cd` printed its answer
// and then hung, the server reporting a stray 0xC5 - OP_IN_STATUS - discarded
// while it waited for READY.
//
// The window that has to be protected is the whole EXCHANGE, command through
// response, not a block and not a handshake.  The failure above landed in the
// turnaround: the MSX had sent `cd` and was idle waiting for the server to
// execute it, so any per-operation claim would have been released right where
// the damage happened.  Idle on the MSX does not mean the link is free.
//
// Discovery is the standard MSX-UNAPI procedure and is done once, then cached.
// If no Ethernet UNAPI is installed there is no ISR to collide with, so these
// become no-ops and tools keep working on machines without networking.

// Discovery is repeated on every call, deliberately.
//
// The first version cached slot/segment/entry in statics and used a
// "not looked yet" flag to discover once.  SDCC puts such statics in _DATA as
// .ds, and with --no-std-crt0 that memory is NOT zeroed - so the flag started
// as whatever the TPA happened to contain.  On real hardware that meant either
// "already discovered", sending CALSLT to a garbage address and REBOOTING the
// machine, or "no implementation", silently skipping the guard.  Both were
// observed in the same session.
//
// Two EXTBIO calls per exchange cost microseconds against a Pi round trip
// measured in milliseconds, so there is nothing to buy back by caching, and
// nothing here now depends on startup zeroing.

static uint16_t un_iy;         // low = segment, high = slot; loaded into IY
static uint16_t un_entry;
static uint16_t un_helper;
static uint8_t  un_seg;
static const char un_id[9] = "ETHERNET";

void msxpi_link_claim(void) __naked
{
    __asm
        ; EXTBIO and the UNAPI entry use IX/IY. Preserve the C caller
        ; frame pointer even when discovery finds no implementation.
        push    ix
        push    iy
        ld      a,i                 ; P/V = interrupt state on entry
        push    af
        ld      b,#1
        call    un_call
        pop     af                  ; EXTBIO handlers and CALSLT can return
        jp      po,1$               ; with interrupts off (a Nextor/MFR slot
        ei                          ; chain does): give back what the caller had
    1$:
        pop     iy
        pop     ix
        ret
    __endasm;
}

void msxpi_link_release(void) __naked
{
    __asm
        push    ix
        push    iy
        ld      a,i                 ; as in msxpi_link_claim
        push    af
        ld      b,#0
        call    un_call
        pop     af
        jp      po,2$
        ei
    2$:
        pop     iy
        pop     ix
        ret
    un_call:
        push    bc                  ; EXTBIO clobbers B

        ; RAM helper address.  Absent is not fatal: an implementation in ROM
        ; reports segment 0xFF and is reached with CALSLT, needing no helper.
        ld      de,#0x2222
        ld      hl,#0
        ld      a,#0xFF
        call    0xFFCA
        ld      (_un_helper),hl

        ; The identifier has to sit at ARG for the discovery call.
        ld      hl,#_un_id
        ld      de,#0xF847
        ld      bc,#9
        ldir

        ld      de,#0x2222
        xor     a
        ld      b,#0
        call    0xFFCA
        ld      a,b
        or      a
        jr      z,un_call_none      ; no ETHERNET UNAPI: no ISR to collide with

        ld      de,#0x2222
        ld      a,#1
        call    0xFFCA
        ld      (_un_iy+1),a        ; slot -> IY high
        ld      a,b
        ld      (_un_seg),a
        ld      (_un_iy),a          ; segment -> IY low (the helper wants it
        ld      (_un_entry),hl      ; there; CALSLT ignores it)

        ; Refuse to call into nothing.  Cheap, and the difference between a
        ; no-op and a reset.
        ld      a,h
        or      l
        jr      z,un_call_none

        ld      iy,(_un_iy)
        ld      ix,(_un_entry)
        pop     bc                  ; B = claim flag again
        ld      a,(_un_seg)
        inc     a
        jr      nz,un_call_ram
        ld      a,#129
        call    0x001C              ; CALSLT - the DOS kernel keeps the
        ei                          ; inter-slot routines live in page-0 RAM
        ret
    un_call_ram:
        ld      hl,(_un_helper)
        ld      a,h
        or      l
        ret     z                   ; RAM implementation and no helper: the
                                    ; call is impossible, so do nothing
        ld      a,#129
        jp      (hl)
    un_call_none:
        pop     bc
        ret
    __endasm;
}

// ----------------------------------------------------------------------------
// msxpi_exchange: one command and its response, with the link held throughout.
//
// A wrapper rather than a claim/release pair sprinkled through the transport:
// link_send and link_recv are single calls now, but a client still has several return points,
// and a release missed at any one of them would leak the claim and silently
// stop the ISR polling for the rest of the session.  Here there is one entry
// and one exit, so the release cannot be skipped.
// ----------------------------------------------------------------------------
uint8_t msxpi_exchange(const char* cmd, bool appendTail,
                       uint8_t* buffer, uint16_t maxbufsize)
{
    uint8_t rc;
    msxpi_link_claim();
    rc = link_command(cmd, appendTail);
    if (buffer != NULL) {
        uint8_t rcFinal = parseConnError(rc);
        if (rcFinal == RC_SUCCESS || rcFinal == RC_FAILED || rc == RC_BUFOVFLW)
            printstdout(buffer, maxbufsize);
    }
    msxpi_link_release();
    return rc;
}

uint8_t printstdout(uint8_t* buffer, uint16_t maxbufsize)
{
    /* Each block is printed as it arrives (mode 1); the buffer holds the largest block and its end mark. */
    return link_recv(1, buffer, maxbufsize - 1, NULL);
}
