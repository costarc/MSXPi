#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "../../../../../MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
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
   CHKPIRDY
   ----------------------- */
/*
 * Counted across calls on purpose - see CHKPIRDY below.
 *
 * No initialiser is relied on here. This is built with --no-std-crt0 against a
 * custom MSX-DOS crt0, and a crt0 that does not clear BSS would leave this as
 * garbage. That is harmless for this variable: any starting value only shifts
 * where in the 256-pass cycle ESC first gets sampled. Do NOT add statics here
 * whose correctness depends on their initial value without first confirming
 * the crt0 clears BSS.
 */
static uint8_t chk_spins;

uint8_t CHKPIRDY(void) {
    uint8_t state;

    /*
     * OPTIMISATION: Inkey() no longer runs on every pass.
     *
     * Inkey() is a Fusion-C BIOS call - an inter-slot call into the MSX
     * keyboard routine, which scans the whole matrix and debounces. Measured
     * on real hardware it was costing ~830 us of the ~975 us the MSX spent
     * per transferred byte: about 85% of the total, and roughly 6.7x
     * everything else in the receive path put together. The Pi-side transfer
     * is only 40 us/byte, so this loop - not the transport - was the
     * bottleneck for the whole protocol.
     *
     * The counter is deliberately static rather than local. A local one would
     * reset on every call, and on a fast link CHKPIRDY returns on its first
     * pass - so ESC would never be sampled at all. Counting across calls
     * samples it roughly every 128 bytes, a few tens of ms, which is well
     * inside human reaction time.
     *
     * This also matters for correctness, not just speed: calling the BIOS
     * keyboard routine from inside a timer-interrupt hook is exactly the
     * reentrancy the UNAPI/InterNestor work has to avoid.
     */
    while (true) {
        /*
         * Inkey() ends with EI, because the CALSLT it uses to reach the BIOS
         * does DI internally and leaves re-enabling to the caller. Calling it
         * every pass therefore re-enabled interrupts thousands of times per
         * transfer - a side effect nothing here asked for but which the code
         * had come to depend on. Now that Inkey() only runs 1 pass in 256,
         * that no longer happens, so do it explicitly. Four T-states.
         */
        __asm
            ei
        __endasm;

        if (++chk_spins == 0) {
            if (Inkey() == 0x1B) {
                return RC_ESCPRESSED;
            }
        }
        state = InPort(CONTROL_PORT1);
        if (state == 0)
            return CHK_STATE_0;
        if (state == 2)
            return CHK_STATE_2;
    }
}

uint8_t PIREADBYTE(uint8_t* byte) {
    uint8_t rc;
    uint8_t version = InPort(CONTROL_PORT2);

    rc = CHKPIRDY();

    // ESC Pressed - Pi not ready
    if (rc == RC_ESCPRESSED) {
        *byte = 0xFF;
        return rc;
    }

    OutPort(CONTROL_PORT1, 0x00);

    rc = CHKPIRDY();
    if (rc == RC_ESCPRESSED) {
        *byte = 0xFF;
        return rc;
    }

    if (version < 0xFE) {
        *byte = InPort(DATA_PORT1);
        return RC_SUCCESS;
    }

    while (1) {
        rc = CHKPIRDY();
        if (rc == RC_ESCPRESSED) {
            *byte = 0xFF;
            return rc;
        }
        if (rc == CHK_STATE_2) {
            *byte = InPort(DATA_PORT1);
            return RC_SUCCESS;
        }
    }
}

/* -----------------------
   PIWRITEBYTE
   ----------------------- */
uint8_t PIWRITEBYTE(uint8_t byte) {
    uint8_t rc = CHKPIRDY();
    OutPort(DATA_PORT1, byte);
    if (rc == CHK_STATE_0 || rc == CHK_STATE_2)
		return RC_SUCCESS;
    return rc;
}

uint8_t RECVDATA(uint8_t* dest, uint16_t* size, uint16_t* maxbufsize) {
    uint8_t  rc;
    uint8_t  header_rc;
    uint8_t  byte;
    uint8_t  block_index;
    uint8_t  expected_block_index = 0;
    uint16_t checksum;
    uint8_t  localChecksum, remoteChecksum;
    uint16_t length;
    uint16_t offset = 0;      // committed bytes in dest[]
    uint8_t  status_for_next; // what we'll tell Python on next handshake

    // -------------------------
    // 1. Initial handshake
    // MSX -> READY
    // Python -> READY_ACK
    // MSX -> msxmaxbuf_low, msxmaxbuf_high
    // -------------------------
    while (1) {
        rc = PIWRITEBYTE(READY);
        if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;

        rc = PIREADBYTE(&byte);
        if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;

        if (byte == READY_ACK) {
            break;  // sync achieved
        }
        // Ignore garbage and retry
    }

    // 3) Send msxmaxbuf (max payload bytes per block)
    uint16_t msxmaxbuf = *maxbufsize;
    if (PIWRITEBYTE(msxmaxbuf & 0xFF) != RC_SUCCESS) return RC_CONNERR;
    if (PIWRITEBYTE((msxmaxbuf >> 8) & 0xFF) != RC_SUCCESS) return RC_CONNERR;

    // -------------------------
    // 2. Block receive loop
    // -------------------------
    for (;;) {
        // --- Header_rc ---
        rc = PIREADBYTE(&header_rc);
        if (rc != RC_SUCCESS) return RC_CONNERR;

        // --- Length low ---
        rc = PIREADBYTE(&byte);
        if (rc != RC_SUCCESS) return RC_CONNERR;
        length = byte;

        // --- Length high ---
        rc = PIREADBYTE(&byte);
        if (rc != RC_SUCCESS) return RC_CONNERR;
        length |= ((uint16_t)byte << 8);

        // --- Block index ---
        rc = PIREADBYTE(&block_index);
        if (rc != RC_SUCCESS) return RC_CONNERR;

        if (block_index != expected_block_index) {
            // Protocol drift
            return RC_CONNERR;
        }

        if ((uint32_t)offset + (uint32_t)length > (uint32_t)(*maxbufsize)) {
            return RC_CONNERR;
        }

        *size = length;  // size of the last block received (optional)

        // --- Payload ---
        checksum = 0;
        for (uint16_t i = 0; i < length; i++) {
            rc = PIREADBYTE(&byte);
            if (rc != RC_SUCCESS) return RC_CONNERR;
            dest[offset + i] = byte;
            checksum += byte;
        }

        // --- Local checksum ---
        localChecksum = (uint8_t)((checksum & 0xFF) + ((checksum >> 8) & 0xFF));

        // --- Receive remote checksum ---
        rc = PIREADBYTE(&remoteChecksum);
        if (rc != RC_SUCCESS) return RC_CONNERR;

        // --- Send local checksum back ---
        if (PIWRITEBYTE(localChecksum) != RC_SUCCESS) return RC_CONNERR;

        // --- Decide based on checksum compare ---
        if (remoteChecksum != localChecksum) {
            // Checksums don't match:
            // - DO NOT advance offset or expected_block_index
            // - DO NOT do status handshake
            // Python will detect mismatch and resend this block.
            continue;
        }

        // From MSX point of view, block is good:
        offset += length;
        expected_block_index++;
        status_for_next = RC_SUCCESS;  // we currently have no extra reasons to reject

        // -------------------------
        // 3. Status handshake for next step (always after a GOOD block)
        //
        // Python's senddata2 now expects this after every good block:
        //   MSX -> READY
        //   MSX -> status_for_next (RC_SUCCESS / RC_CHKSUM_ERR)
        //   Python -> READY_ACK
        // -------------------------
        rc = PIWRITEBYTE(READY);
        if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;

        rc = PIWRITEBYTE(status_for_next);
        if (rc != RC_SUCCESS) return RC_CONNERR;

        rc = PIREADBYTE(&byte);
        if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;
        if (byte != READY_ACK) {
            return RC_HANDSHAKEERR;
        }

        // After this handshake, Python may:
        //  - send another block (if header_rc == RC_READY), or
        //  - be done (if header_rc == RC_SUCCESS and this was the last block).

        if (header_rc == RC_SUCCESS) {
            // Last block, and it was accepted.
            *size = offset;  // total bytes successfully received
            return RC_SUCCESS;
        }

        // Otherwise header_rc == RC_READY, loop to receive next block.
    }
}

uint8_t PerformHandshake(uint16_t msx_blocksize) {
    //Print("[MSX] Handshake: sending READY\n");
    uint8_t  rc;
    uint8_t  byte;
    while (1) {
        rc = PIWRITEBYTE(READY);
        if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;

        rc = PIREADBYTE(&byte);
        if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;

        if (byte == READY_ACK) {
            break;  // sync achieved
        }
        // Ignore garbage and retry
    }
    //Print("[MSX] Handshake: Finished\n");

    // Send msx_blocksize (max payload bytes per block)
    if (PIWRITEBYTE(msx_blocksize & 0xFF) != RC_SUCCESS) return RC_CONNERR;
    if (PIWRITEBYTE((msx_blocksize >> 8) & 0xFF) != RC_SUCCESS) return RC_CONNERR;

    return RC_SUCCESS;

}

uint8_t RECVDATA_ONEBLOCK(uint8_t* dest, uint16_t* size, uint16_t msx_blocksize)
{
    uint8_t  rc;
    uint8_t  header_rc;
    uint8_t  byte;
    uint8_t  block_index;
    static uint8_t  expected_block_index = 0;
    uint16_t checksum;
    uint8_t  localChecksum, remoteChecksum;
    uint16_t this_blocksize;
    uint8_t  status_for_next;

    // -------------------------
    // 1. Initial handshake must be have done before calling this functtion
    // MSX -> READY
    // Python -> READY_ACK
    // MSX -> msxmaxbuf_low, msxmaxbuf_high
    // -------------------------
    /* // Call like this:
    rc = PerformHandshake(msx_blocksize);
    if (rc != RC_SUCCESS)
        return rc;
    */
    
    // -------------------------
    // 2. Read exactly one block
    // -------------------------
    //Print("[MSX] Waiting for header_rc\n");

    // --- header_rc ---
    rc = PIREADBYTE(&header_rc);
    if (rc != RC_SUCCESS) return RC_CONNERR;

    // --- this_blocksize low/high ---
    rc = PIREADBYTE(&byte);
    if (rc != RC_SUCCESS) return RC_CONNERR;
    this_blocksize = byte;

    rc = PIREADBYTE(&byte);
    if (rc != RC_SUCCESS) return RC_CONNERR;
    this_blocksize |= ((uint16_t)byte << 8);

    // --- block_index ---
    rc = PIREADBYTE(&block_index);
    if (rc != RC_SUCCESS) return RC_CONNERR;

    if (block_index != expected_block_index) {
        // Protocol drift (for one‑block variant we still enforce index = 0)
        return RC_CONNERR;
    }

    if (this_blocksize > msx_blocksize) {
        return RC_BUFOVFLW;
    }

    *size = this_blocksize;  // size of this block

    // --- Payload ---
    checksum = 0;
    for (uint16_t i = 0; i < this_blocksize; i++) {
        rc = PIREADBYTE(&byte);
        if (rc != RC_SUCCESS) return RC_CONNERR;
        dest[i] = byte;
        checksum += byte;
    }

    // Local checksum (folded 16-bit sum → 8-bit)
    uint8_t right = (uint8_t)(checksum & 0xFF);
    uint8_t left = (uint8_t)((checksum >> 8) & 0xFF);
    localChecksum = (uint8_t)((right + left) & 0xFF);

    // --- Receive remote checksum (from Python) ---
    rc = PIREADBYTE(&remoteChecksum);
    if (rc != RC_SUCCESS) return RC_CONNERR;

    // --- Send local checksum back ---
    rc = PIWRITEBYTE(localChecksum);
    if (rc != RC_SUCCESS) return RC_CONNERR;

    if (remoteChecksum != localChecksum) {
        // Single attempt failed; Python may decide to resend the block
        // in a new call / new transaction. This one returns error.
        return RC_CHKSUM_ERR;
    }

    // Block accepted
    status_for_next = RC_SUCCESS;
    expected_block_index++;

    // -------------------------
    // 3. Status handshake after GOOD block
    //
    // MSX -> READY
    // MSX -> status_for_next
    // Python -> READY_ACK
    // -------------------------
    rc = PIWRITEBYTE(READY);
    if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;

    rc = PIWRITEBYTE(status_for_next);
    if (rc != RC_SUCCESS) return RC_CONNERR;

    rc = PIREADBYTE(&byte);
    if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;
    if (byte != READY_ACK) {
        return RC_HANDSHAKEERR;
    }

    // Interpret header_rc for the caller:
    //   RC_SUCCESS → this was the last block
    //   RC_READY   → more blocks will follow
    if (header_rc == RC_SUCCESS) {
        expected_block_index = 0;  // reset for next transfer
        return RC_SUCCESS;
    }
    else if (header_rc == RC_READY) {
        return RC_READY;
    }
    else {
		expected_block_index = 0;  // In case of an error, the block index is 0
        return header_rc;  // returns the server return code
    }
}

// SENDDATA2
// MSX is the SENDER, Python is the RECEIVER.
//
// Protocol (mirrors RECVDATA / Python SENDDATA2):
//
// Initial handshake:
//   MSX   -> READY
//   Python-> READY_ACK
//   MSX   -> msxmaxbuf_low, msxmaxbuf_high  (max payload bytes per block)
//
// Then per block:
//   MSX   -> header_rc           (RC_READY or RC_SUCCESS)
//   MSX   -> this_blocksize_low
//   MSX   -> this_blocksize_high
//   MSX   -> block_index
//   MSX   -> payload[this_blocksize]
//   MSX   -> localChecksum       (from MSX checksum calculation)
//   Python-> remoteChecksum      (Python's view of checksum)
//   (If remoteChecksum != localChecksum, MSX resends same block)
//
// After a GOOD block (checksums match):
//   Python-> READY
//   Python-> status_for_next     (RC_SUCCESS or error code)
//   MSX   -> READY_ACK
//
// If header_rc == RC_SUCCESS and block was good, transfer ends with RC_SUCCESS.
//

uint8_t SENDDATA2(uint8_t* src, uint16_t size, uint16_t* maxbufsize)
{
    uint8_t  rc;
    uint8_t  byte;
    uint8_t  header_rc;
    uint8_t  block_index = 0;
    uint16_t offset = 0;          // committed bytes sent from src[]
    uint16_t msxmaxbuf;
    uint16_t remaining;
    uint16_t this_blocksize;
    uint16_t checksum;
    uint8_t  localChecksum, remoteChecksum;
    uint8_t  status_from_python;

    // -------------------------
    // 1. Initial handshake
    // MSX -> READY
    // Python -> READY_ACK
    // MSX -> msxmaxbuf_low, msxmaxbuf_high
    // -------------------------
    while (1) {
        rc = PIWRITEBYTE(READY);
        if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;

        rc = PIREADBYTE(&byte);
        if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;

        if (byte == READY_ACK) {
            break;  // sync achieved
        }
        // Ignore garbage and retry
    }

    msxmaxbuf = *maxbufsize;

    // Send msxmaxbuf (max payload bytes per block)
    if (PIWRITEBYTE(msxmaxbuf & 0xFF) != RC_SUCCESS) return RC_CONNERR;
    if (PIWRITEBYTE((msxmaxbuf >> 8) & 0xFF) != RC_SUCCESS) return RC_CONNERR;

    // -------------------------
    // 2. Block send loop
    // -------------------------
    while (offset < size) {
        // Compute this_blocksize for this block (max msxmaxbuf or remaining bytes)
        remaining = size - offset;
        if (remaining > msxmaxbuf) {
            this_blocksize = msxmaxbuf;
            header_rc = RC_READY;   // more blocks will follow
        }
        else {
            this_blocksize = remaining;
            header_rc = RC_SUCCESS; // this is the last block
        }

        // We'll stay in this inner loop if checksum mismatches and we must resend.
        while (1) {
            // --- Header_rc ---
            rc = PIWRITEBYTE(header_rc);
            if (rc != RC_SUCCESS) return RC_CONNERR;

            // --- this_blocksize low ---
            rc = PIWRITEBYTE((uint8_t)(this_blocksize & 0xFF));
            if (rc != RC_SUCCESS) return RC_CONNERR;

            // --- this_blocksize high ---
            rc = PIWRITEBYTE((uint8_t)((this_blocksize >> 8) & 0xFF));
            if (rc != RC_SUCCESS) return RC_CONNERR;

            // --- Block index ---
            rc = PIWRITEBYTE(block_index);
            if (rc != RC_SUCCESS) return RC_CONNERR;

            // --- Payload + checksum accumulation ---
            checksum = 0;
            for (uint16_t i = 0; i < this_blocksize; i++) {
                uint8_t b = src[offset + i];
                rc = PIWRITEBYTE(b);
                if (rc != RC_SUCCESS) return RC_CONNERR;
                checksum += b;
            }

            // --- Local checksum (MSX sender) ---
            localChecksum = (uint8_t)((checksum & 0xFF) + ((checksum >> 8) & 0xFF));

            // --- Send local checksum ---
            rc = PIWRITEBYTE(localChecksum);
            if (rc != RC_SUCCESS) return RC_CONNERR;

            // --- Receive remote checksum (Python receiver) ---
            rc = PIREADBYTE(&remoteChecksum);
            if (rc != RC_SUCCESS) return RC_CONNERR;

            // --- Decide based on checksum compare ---
            if (remoteChecksum != localChecksum) {
                // Checksums don't match:
                // - DO NOT advance offset or block_index
                // - DO NOT do status handshake
                // Python will detect mismatch and request resend by simply
                // not advancing its own block index and expecting this same block again.
                //
                // We just loop and resend this block.
                continue;
            }

            // Checksums match: good block from both sides' perspective.
            break;
        }

        // Commit this block
        offset += this_blocksize;
        block_index++;

        // -------------------------
        // 3. Status handshake after each GOOD block
        //
        // Mirror of MSX RECVDATA (where MSX sends status_for_next):
        // Here, Python is the receiver, so Python sends status_for_next:
        //
        //   Python -> READY
        //   Python -> status_for_next (RC_SUCCESS / error)
        //   MSX    -> READY_ACK
        // -------------------------

        // --- Expect READY from Python ---
        rc = PIREADBYTE(&byte);
        if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;
        if (byte != READY) {
            return RC_HANDSHAKEERR;
        }

        // --- Receive status_from_python ---
        rc = PIREADBYTE(&status_from_python);
        if (rc != RC_SUCCESS) return RC_CONNERR;

        // For now we treat anything other than RC_SUCCESS as fatal.
        if (status_from_python != RC_SUCCESS) {
            return RC_CONNERR;
        }

        // --- Send READY_ACK back ---
        rc = PIWRITEBYTE(READY_ACK);
        if (rc != RC_SUCCESS) return RC_HANDSHAKEERR;

        // If this was the last block (header_rc == RC_SUCCESS), we're done.
        if (header_rc == RC_SUCCESS) {
            return RC_SUCCESS;
        }

        // Otherwise loop to send the next block.
    }

    // If we ever get here logically something went off, but
    // we should have returned from within the loop on last block.
    return RC_CONNERR;
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

uint8_t SendCommandToMSXPi(const char* cmd, bool appendTail) {
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
    // Pinned to a fixed address rather than left to normal _DATA packing:
    // callers doing mapper-aware ROM loading (msxarch.c) Put_PN a
    // dedicated segment into page 2 (0x8000-0xBFFF) for the duration of
    // that work, specifically to relocate this 8K buffer (the single
    // largest consumer of _DATA) out of the way, since the linker's
    // normal packing pushed it - and everything after it - past 0x4000,
    // into memory that mapper-loading's own Put_PN(1,...) calls corrupt.
    static __at(BUFADDRESS) char buffer[MAXBUFSIZE];
    uint16_t total = 0;

    // Copy primary
    for (uint16_t i = 0; i < lenPrimary && total < MAXBUFSIZE; i++) {
        buffer[total++] = primary[i];
    }

    // Append tail if requested
    if (appendTail && lenTail > 0) {
        // Insert a space only if primary is non-empty
        if (total > 0 && total < MAXBUFSIZE) {
            buffer[total++] = ' ';
        }

        for (uint16_t i = 0; i < lenTail && total < MAXBUFSIZE; i++) {
            buffer[total++] = tail[i];
        }
    }

    // Null-terminate (not sent, but safe)
    if (total < MAXBUFSIZE) {
        buffer[total] = 0;
    }

    if (total == 0) {
        return RC_FAILED;
    }

    // ---------------------------------------------------------
    // 3. Send to MSX‑Pi
    // ---------------------------------------------------------
    uint16_t maxbuf = MAXBUFSIZE;
    return SENDDATA2((uint8_t*)buffer, total, &maxbuf);
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

uint16_t get_sp(void) __naked {
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
        ld      b,#1
        jr      un_call
    __endasm;
}

void msxpi_link_release(void) __naked
{
    __asm
        ld      b,#0
        ; falls through
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
// RECVDATA, RECVDATA_ONEBLOCK and SENDDATA2 have eighteen return points each,
// and a release missed at any one of them would leak the claim and silently
// stop the ISR polling for the rest of the session.  Here there is one entry
// and one exit, so the release cannot be skipped.
// ----------------------------------------------------------------------------
uint8_t msxpi_exchange(const char* cmd, bool appendTail,
                       uint8_t* buffer, uint16_t maxbufsize)
{
    uint8_t rc;
    msxpi_link_claim();
    rc = SendCommandToMSXPi(cmd, appendTail);
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
    uint8_t  rc;
    uint16_t block_size;

    rc = PerformHandshake(maxbufsize);
    if (rc != RC_SUCCESS)
        return rc;

    while (1) {

        rc = RECVDATA_ONEBLOCK(buffer, &block_size, maxbufsize);

        if (block_size < maxbufsize)
            buffer[block_size] = '\0';
        else
            buffer[maxbufsize - 1] = '\0';

        Print(buffer);

        if (rc != RC_READY)
            break;
    }

    return RC_SUCCESS;
}