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

    // If target is omitted, default to source filename
    if (tgt_buf[0] == '\0') {
        strcpy(tgt_buf, src_buf);
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

static uint8_t pcopy_body(void) {
    uint8_t rc;
    uint16_t block_size;
    uint8_t *buffer = get_buffer_ptr();
	uint16_t maxbufsize = 16384;

    // 1. Read command tail directly from MSX-DOS PSP memory
    get_dos_cmdline(cmdTail);

    // 2. Parse arguments
    parse_args(cmdTail, src, tgt);

    if (src[0] == '\0') {
        Print("Usage: pcopy <source file> [drive:][target file]\r\n");
        return RC_INVALIDCOMMAND;
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

    pprintf("Copying (block size:", maxbufsize/1024);pprints(" KB) to:", tgt);
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
        } else if (rc != RC_READY) {
            Print("\r\nTransfer aborted by server.\r\n");
            fcb_close(&file);
            return rc;
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