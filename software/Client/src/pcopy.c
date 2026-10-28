/*
 * MSXPi Interface
 * Version 1.6.1
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
#include "../../C-common/header/fusion.h"
#include "../../C-common/header/msxpi.h"

// Longest source or target argument kept, terminator included.
#define PCOPY_ARG_MAX 64

// Static buffers to prevent Z80 stack overflow
static char cmdTail[128];
static char src[PCOPY_ARG_MAX];
// Room for a drive, a file name taken from the source, and ".ROM".
static char tgt[PCOPY_ARG_MAX + 8];
// "pcopy init /z " + source + " " + target
static char full_cmd[160];
static FCB file;
// /z on the command line: the Pi unpacks the archive and sends the ROM in it.
static bool expand;

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

// The file name inside a path: the text after the last '/', '\\' or ':'.
// That covers Pi paths, URLs and the m:, r1: and r2: remote drives alike.
static const char *base_name(const char *path) {
    const char *name = path;

    for (; *path != '\0'; path++) {
        if (*path == '/' || *path == '\\' || *path == ':') name = path + 1;
    }
    return name;
}

// Split the command tail into the source, the optional target and the /z
// option.  /z is an option wherever it stands - before, between or after the
// two names - but only as a whole argument, so /zanac.rom is still a path.
// It used to be read as the source, which made the archive's name the target.
// Anything after the target is ignored.
static void parse_args(char *cmd, char *src_buf, char *tgt_buf) {
    uint8_t nargs = 0;

    expand = false;
    src_buf[0] = '\0';
    tgt_buf[0] = '\0';

    while (1) {
        char *dst;
        uint8_t i = 0;

        while (*cmd == ' ' || *cmd == '\t') cmd++;
        if (is_delim(*cmd)) break;

        if (cmd[0] == '/' && (cmd[1] == 'z' || cmd[1] == 'Z') && is_delim(cmd[2])) {
            expand = true;
            cmd += 2;
            continue;
        }

        dst = (nargs == 0) ? src_buf : (nargs == 1) ? tgt_buf : NULL;
        while (!is_delim(*cmd)) {
            if (dst != NULL && i < PCOPY_ARG_MAX - 1) dst[i++] = *cmd;
            cmd++;
        }
        if (dst != NULL) dst[i] = '\0';
        nargs++;
    }
}

// Name the target when the command line did not: no target at all, or only a
// drive ("B:").  It gets the source's file name and nothing else of the
// source - "B:" + "/tmp/game.rom" is not a name the MSX can create, and
// neither is "r1:frogger.zip".  For an upload this is also what drops the
// drive letter: the Pi must not be asked for a file named "A:GAME.ROM".
//
// With rom_ext the name ends in .ROM instead of the archive's extension: under
// /z the Pi sends the .rom it found inside the archive, not the archive.  The
// cut is at the FIRST dot, which is where init_fcb ends the name, so
// frogger.tar.gz becomes frogger.ROM.
static void default_target(bool rom_ext) {
    char *dot;

    if (tgt[0] != '\0' && !(tgt[1] == ':' && tgt[2] == '\0')) return;

    strcat(tgt, base_name(src));
    if (rom_ext) {
        dot = strchr(tgt, '.');
        if (dot != NULL) *dot = '\0';
        strcat(tgt, ".ROM");
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

// One block from the Pi, asked for again when it fails its checksum.
//
// RECVDATA_ONEBLOCK makes a single attempt and returns RC_CHKSUM_ERR, while
// the server's senddata_oneblock() goes straight on to resend the same block,
// up to MAX_BLOCK_RETRIES times.  Calling it once therefore turned one bad
// byte into an aborted copy, and left the server part way through a resend
// that nobody was reading.  Each attempt refills the buffer from its start, so
// nothing of a rejected block survives into the next one.
static uint8_t recv_block(uint8_t *buffer, uint16_t *block_size,
                          uint16_t maxbufsize) {
    uint8_t rc;
    uint8_t attempts = 0;

    do {
        rc = RECVDATA_ONEBLOCK(buffer, block_size, maxbufsize);
    } while (rc == RC_CHKSUM_ERR && ++attempts < MAX_BLOCK_RETRIES);
    return rc;
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
    // "A:GAME.ROM".  Done here as well as in default_target because this
    // is the only place that knows the name is bound for the Pi.
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
    rc = recv_block(buffer, &block_size, maxbufsize);
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
    Print("\r\nConnection error during write.\r\n");
            fcb_close(&file);
            return parseConnError(rc);
        }

        Print(".");
        rc = SENDDATA2(buffer, n, &maxbufsize);
        if (rc != RC_SUCCESS) {
    Print("\r\nTransfer aborted.\r\n");
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
    rc = recv_block(buffer, &block_size, maxbufsize);
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

    Print("\r\nFile copied to MSXPi successfully.\r\n");
    return RC_SUCCESS;
}

static uint8_t pcopy_body(void) {
    uint8_t rc;
    uint16_t block_size;
    uint8_t *buffer = get_buffer_ptr();
    uint16_t maxbufsize = PCOPY_BLOCK_SIZE;
    bool typed;

    // 1. Command tail was already copied by pcopy(), before the link claim.

    // 2. Parse arguments
    parse_args(cmdTail, src, tgt);

    if (src[0] == '\0') {
        Print("Usage:\r\n");
        Print("  pcopy [/z] <pi file> [drive:][target]   Pi  -> MSX\r\n");
        Print("  pcopy <drive>:<file> <pi file>          MSX -> Pi\r\n");
        Print("  /z: unpack an archive, copy its ROM\r\n");
        Print("  No target: the source's file name,\r\n");
        Print("  with .ROM when /z is used\r\n");
        return RC_INVALIDCOMMAND;
    }

    // A drive letter on the SOURCE means the file is on the MSX: upload.
    // The download form never has one there - its drive, if any, is on the
    // target - so the two syntaxes cannot be confused.  Only A: to H:, the
    // drives MSX-DOS has: M: is the Pi's remote drive (pcopy m:file, which
    // msxpiupd.bat and msxpirfh.bat depend on) and must stay a download.
    if (src[1] == ':' &&
        ((src[0] >= 'A' && src[0] <= 'H') || (src[0] >= 'a' && src[0] <= 'h'))) {
        default_target(false);      // /z means nothing to an upload
        return pcopy_upload();
    }

    // The server gets the target only when one was typed: a defaulted one
    // would hand its "is the target really the source?" fallback a file name
    // the user never gave.
    typed = (tgt[0] != '\0');
    default_target(expand);

    if (*base_name(tgt) == '\0') {
        Print("Error: no file name in the source; give a target.\r\n");
        return RC_INVALIDCOMMAND;
    }

    // 3. PHASE 1: Send 'pcopy init' command to prepare session on Pi
    strcpy(full_cmd, "pcopy init ");
    if (expand) strcat(full_cmd, "/z ");
    strcat(full_cmd, src);
    if (typed) {
        strcat(full_cmd, " ");
        strcat(full_cmd, tgt);
    }

    rc = SendCommandToMSXPi(full_cmd, false);
    if (rc != RC_SUCCESS) return parseConnError(rc);

    rc = PerformHandshake(maxbufsize);
    if (rc != RC_SUCCESS) return parseConnError(rc);

    // Receive initialization result payload
    rc = recv_block(buffer, &block_size, maxbufsize);

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
        rc = recv_block(buffer, &block_size, maxbufsize);

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
    // Copy the tail FIRST: the claim makes an EXTBIO/UNAPI call that can
    // overwrite 0x0080, leaving the server "pcopy init m<garbage>".
    get_dos_cmdline(cmdTail);
    msxpi_link_claim();
    rc = pcopy_body();
    msxpi_link_release();
    return rc;
}

void main(void) {
    pcopy();
}