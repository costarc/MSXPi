/*
 * MSXPi Interface
 * Version 1.6
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
#include <string.h>
#include "../../../../../MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../C-common/header/msxpi.h"

// Static buffers to prevent Z80 stack overflow
static char cmdTail[128];
static char src[64];
static char tgt[64];
static char full_cmd[128];
static FCB file;

// Safely copy raw MSX-DOS command line tail from PSP (0x0080)
static void get_dos_cmdline(char *buf) {
    uint8_t *psp_tail = (uint8_t *)0x0080;
    uint8_t len = psp_tail[0];
    uint8_t i;

    for (i = 0; i < len; i++) {
        char c = (char)psp_tail[1 + i];
        if (c == '\r' || c == '\n' || c == '\0') break;
        buf[i] = c;
    }
    buf[i] = '\0';
}

static bool is_delim(char c) {
    return (c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\0');
}

static void parse_args(char *cmd, char *src_buf, char *tgt_buf) {
    uint8_t i = 0;

    // Skip leading whitespace
    while (*cmd != '\0' && (*cmd == ' ' || *cmd == '\t')) cmd++;

    // Extract source parameter
    while (*cmd != '\0' && !is_delim(*cmd)) {
        src_buf[i++] = *cmd++;
    }
    src_buf[i] = '\0';

    // Skip whitespace between arguments
    while (*cmd != '\0' && (*cmd == ' ' || *cmd == '\t')) cmd++;

    // Extract target parameter
    i = 0;
    while (*cmd != '\0' && !is_delim(*cmd)) {
        tgt_buf[i++] = *cmd++;
    }
    tgt_buf[i] = '\0';

    // If target is omitted, default to the source filename - but WITHOUT any
    // drive letter.  For an upload (pcopy A:GAME.ROM) the source carries one,
    // and copying it verbatim asked the Pi to create a file literally named
    // "A:GAME.ROM".
    if (tgt_buf[0] == '\0') {
        if (src_buf[0] != '\0' && src_buf[1] == ':') {
            strcpy(tgt_buf, src_buf + 2);
        } else {
            strcpy(tgt_buf, src_buf);
        }
    } 
    // Handle drive specifier targets (e.g., "B:")
    else if (tgt_buf[1] == ':' && tgt_buf[2] == '\0') {
        strcat(tgt_buf, src_buf);
    }
}

static void init_fcb(FCB *fcb_ptr, const char *path) {
    uint8_t *p = (uint8_t *)fcb_ptr;
    memset(p, 0, sizeof(FCB));

    if (path[1] == ':') {
        char drv = path[0];
        if (drv >= 'a' && drv <= 'z') drv -= 32;
        p[0] = (drv - 'A') + 1;
        path += 2;
    } else {
        p[0] = 0;
    }

    memset(&p[1], ' ', 11);

    uint8_t i = 0;
    while (*path != '\0' && *path != '.' && i < 8) {
        char c = *path++;
        if (c >= 'a' && c <= 'z') c -= 32;
        p[1 + i] = c;
        i++;
    }

    while (*path != '\0' && *path != '.') path++;

    if (*path == '.') {
        path++;
        i = 0;
        while (*path != '\0' && i < 3) {
            char c = *path++;
            if (c >= 'a' && c <= 'z') c -= 32;
            p[9 + i] = c;
            i++;
        }
    }

    p[14] = 1;
    p[15] = 0;
}

// ---------------------------------------------------------------------------
// Upload: MSX drive -> Pi.   pcopy A:game.rom game.rom
// ---------------------------------------------------------------------------
// Three server subcommands mirroring the download side: "put" names the
// destination and reports whether it could be created, "writeblock" carries one
// block, and "putclose" ends the transfer.
//
// A separate close rather than a last-block flag, because the block protocol
// carries no header byte in this direction and inventing one would change a
// path the disk driver also uses.
// Keep download/upload comparable. Change this one value for both directions.
#define PCOPY_BLOCK_SIZE 8192

static uint8_t pcopy_upload(void) {
    uint8_t rc;
    uint16_t block_size;
    uint16_t n;
    const char *dest;
    uint8_t *buffer = get_buffer_ptr();
    uint16_t maxbufsize = PCOPY_BLOCK_SIZE;

    init_fcb(&file, src);
    if (fcb_open(&file) != 0) {
    Print("Error: cannot open source file on MSX drive.\r\n");
        return RC_FILENOTFOUND;
    }

    // The Pi has no drive letters, so strip one if it reached here - from
    // the default (pcopy A:GAME.ROM, target omitted) or typed outright.
    // Without this the Pi was asked to create a file literally named
    // "A:GAME.ROM".  Done here as well as in parse_args because this is
    // the only place that knows the name is bound for the Pi.
    dest = tgt;
    if (dest[0] != '\0' && dest[1] == ':') {
        dest += 2;
    }

    strcpy(full_cmd, "pcopy put ");
    strcat(full_cmd, dest);
    rc = SendCommandToMSXPi(full_cmd, false);
    if (rc != RC_SUCCESS) { fcb_close(&file); return parseConnError(rc); }

    rc = PerformHandshake(maxbufsize);
    if (rc != RC_SUCCESS) { fcb_close(&file); return parseConnError(rc); }

    // The server explains itself in the payload - no such directory,
    // read-only, and so on - so print it rather than a generic code.
    rc = RECVDATA_ONEBLOCK(buffer, &block_size, maxbufsize);
    if (rc != RC_SUCCESS) {
        if (block_size < maxbufsize) buffer[block_size] = 0;
        else buffer[maxbufsize - 1] = 0;
        Print((char*)buffer);
    Print("\r\n");
        fcb_close(&file);
        return rc;
    }

    pprintf("Copying (block size:", maxbufsize);
    pprints(" bytes) to Pi:", (char*)dest);
    Print("\r\n");

    while (1) {
        n = fcb_read(&file, buffer, maxbufsize);
        if (n == 0) break;                  // end of file

        rc = SendCommandToMSXPi("pcopy writeblock", false);
        if (rc != RC_SUCCESS) {
    Print("Connection error during write.\r\n");
            fcb_close(&file);
            return parseConnError(rc);
        }

        Print(".");
        rc = SENDDATA2(buffer, n, &maxbufsize);
        if (rc != RC_SUCCESS) {
    Print("Transfer aborted.\r\n");
            fcb_close(&file);
            return parseConnError(rc);
        }

        // No "short read means EOF" shortcut here: fcb_read returning less
        // than asked for is not a promise the file ended, and treating it as
        // one would truncate the copy silently.  The n == 0 test above ends
        // the loop correctly, at the cost of one extra call.
    }

    fcb_close(&file);

    // Close on the Pi even if nothing was sent, so no half-open file is left
    // for the next transfer to trip over.
    rc = SendCommandToMSXPi("pcopy putclose", false);
    if (rc != RC_SUCCESS) return parseConnError(rc);
    rc = PerformHandshake(maxbufsize);
    if (rc != RC_SUCCESS) return parseConnError(rc);
    rc = RECVDATA_ONEBLOCK(buffer, &block_size, maxbufsize);
    if (rc != RC_SUCCESS) {
        // Do NOT print the buffer here.  On a failed receive block_size is
        // whatever it was last left as, and the buffer still holds the last
        // 16 KB of the FILE - terminating it at a meaningless offset and
        // printing that dumped a screenful of binary to the VDP, burying the
        // actual error under a minute of scrolling.
        pprintf("Error closing file on MSXPi, rc=", rc);
        Print("\r\n");
        return rc;
    }

    Print("File copied to MSXPi successfully.\r\n");
    return RC_SUCCESS;
}

static uint8_t pcopy_body(void) {
    uint8_t rc;
    uint16_t block_size;
    uint8_t *buffer = get_buffer_ptr();
    uint16_t maxbufsize = PCOPY_BLOCK_SIZE;

    // 1. Read command tail directly from MSX-DOS PSP memory
    get_dos_cmdline(cmdTail);

    // 2. Parse arguments
    parse_args(cmdTail, src, tgt);

    if (src[0] == '\0') {
        Print("Usage:\r\n");
        Print("  pcopy <pi file> [drive:][target]   Pi  -> MSX\r\n");
        Print("  pcopy <drive>:<file> <pi file>     MSX -> Pi\r\n");
        return RC_INVALIDCOMMAND;
    }

    // A drive letter on the SOURCE means the file is on the MSX: upload.
    // The download form never has one there - its drive, if any, is on the
    // target - so the two syntaxes cannot be confused.
    if (src[1] == ':' &&
        ((src[0] >= 'A' && src[0] <= 'Z') || (src[0] >= 'a' && src[0] <= 'z'))) {
        return pcopy_upload();
    }

    // 3. PHASE 1: Send 'pcopy init' command to prepare session on Pi
    strcpy(full_cmd, "pcopy init ");
    strcat(full_cmd, src);
    if (tgt[0] != '\0') {
        strcat(full_cmd, " ");
        strcat(full_cmd, tgt);
    }

    rc = SendCommandToMSXPi(full_cmd, false);
    if (rc != RC_SUCCESS) return parseConnError(rc);

    rc = PerformHandshake(maxbufsize);
    if (rc != RC_SUCCESS) return parseConnError(rc);

    // Receive initialization result payload
    rc = RECVDATA_ONEBLOCK(buffer, &block_size, maxbufsize);

    // If init returned an error (e.g. RC_FILENOTFOUND), print error payload and abort
    if (rc != RC_SUCCESS) {
        if (block_size < maxbufsize) {
            buffer[block_size] = '\0';
        } else {
            buffer[maxbufsize - 1] = '\0';
        }

        Print((char*)buffer);
        Print("\r\n");
        return rc;
    }

    // 4. Initialization succeeded: Create target file on MSX disk
    init_fcb(&file, tgt);
    if (fcb_create(&file) != 0) {
        Print("Error: Cannot create target file on disk.\r\n");
        return RC_FAILED;
    }

    pprintf("Copying (block size:", maxbufsize);pprints(" bytes) to:", tgt);
    Print("\r\n");

    // 5. PHASE 2: Fetch and write blocks iteratively
    while (1) {
        // Request next block from server
        rc = SendCommandToMSXPi("pcopy readblock", false);
        if (rc != RC_SUCCESS) {
            Print("\r\nConnection error during read.\r\n");
            fcb_close(&file);
            return parseConnError(rc);
        }

        rc = PerformHandshake(maxbufsize);
        if (rc != RC_SUCCESS) {
            Print("\r\nHandshake error during read.\r\n");
            fcb_close(&file);
            return parseConnError(rc);
        }

        Print(".");
        rc = RECVDATA_ONEBLOCK(buffer, &block_size, maxbufsize);

        // A failed receive can leave block_size and the buffer partially filled.
        // Never commit that data to disk.
        if (rc != RC_SUCCESS && rc != RC_READY) {
            Print("\r\nTransfer aborted by server.\r\n");
            fcb_close(&file);
            return rc;
        }

        // Write chunk to MSX disk (Pi server is now back in main loop and able to serve disk sectors)
        if (block_size > 0) {
            if (fcb_write(&file, buffer, block_size) != 0) {
                Print("\r\nDisk write error.\r\n");
                fcb_close(&file);
                return RC_FAILED;
            }
        }

        if (rc == RC_SUCCESS) {
            break; // Final block received
        }
    }

    fcb_close(&file);
    Print("\r\nFile copied successfully.\r\n");
    return RC_SUCCESS;
}

// Hold the MSXPi link for the whole copy.
//
// A trampoline rather than a claim/release pair inside pcopy_body(): that
// function has nine return points once the transfer starts, and a release
// missed at any one of them would leave the link marked busy after the program
// exits, silently stopping the Ethernet UNAPI ISR from polling for the rest of
// the session.  One entry and one exit here make that impossible.
//
// The claim spans the ENTIRE copy, which for a megarom is minutes.  That is
// correct rather than merely tolerated: the link is one wire and pcopy is
// using it throughout, so InterNestor Lite could not have used it anyway.
// Frames queue on the Pi and are collected afterwards.  The case that would be
// wrong is holding the link while IDLE, which never happens here.
//
// Without this, INL's 50/60 Hz timer interrupt transmits into the middle of
// the transfer.  On a `p cd` that shows up as a hang; here it would corrupt
// the file being written to disk, which looks like a bad download rather than
// an interrupt problem.
uint8_t pcopy(void) {
    uint8_t rc;
    msxpi_link_claim();
    rc = pcopy_body();
    msxpi_link_release();
    return rc;
}

void main(void) {
    pcopy();
}