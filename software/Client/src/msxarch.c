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
#include "../../../../../MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../../../../MSX-C/WorkingFolder/fusion-c/header/rammapper.h"
#include "../../C-common/header/msxpi.h"

#define PAGESIZE (22 * 80)
#define INPUTLEN 4

// Repository list config file
#define INI_FILENAME     "MSXARCH.INI"
#define INI_BUFFER_SIZE  1024
#define MAX_REPOS        8
#define MAX_URL_LEN      100

#define KEY_UP    0x1E   // Fusion-C scancode for Up arrow
#define KEY_DOWN  0x1F   // Fusion-C scancode for Down arrow
#define KEY_ENTER 0x0D   // ASCII code for Enter/Return

// Return codes
#define INPUT_NONE   0
#define INPUT_P      1
#define INPUT_N      2
#define INPUT_Q      3      
#define INPUT_UP     4
#define INPUT_DOWN   5
#define INPUT_NUMBER 6

#define ROM_BASE   0x4000
#define BANK_SIZE  0x2000   // 8K

// ROM header definitions
#define ROM_HEADER_MAGIC    0x52   // 'R'
#define ROM_HEADER_SIZE     16
#define ROM_REASON_MAX      144    // max reject-reason text length, incl. null terminator
#define ROM_MSG_MAX         (ROM_HEADER_SIZE + ROM_REASON_MAX)
#define MAPPER_PLAIN        0      // linear ROM, loaded exactly as today
#define MAPPER_KONAMI       1      // 8K banks
#define MAPPER_ASCII8       2      // 8K banks
#define MAPPER_ASCII16      3      // 16K banks
#define MAPPER_REJECTED     0xFF   // selection rejected

typedef struct {
    uint8_t  mapperType;
    uint8_t  bankSizeKB;
    uint16_t bankCount;
    uint32_t totalSize;
} RomHeader;

// Reads the fixed-size ROM header sent by the server
uint8_t readRomHeader(RomHeader* hdr, char* reason, uint16_t reasonBufSize) {
    uint8_t  buf[ROM_MSG_MAX];
    uint16_t replySize = 0;
    uint16_t maxbuf = ROM_MSG_MAX;
    uint8_t  rc = RECVDATA(buf, &replySize, &maxbuf);

    if (rc != RC_SUCCESS || replySize < ROM_HEADER_SIZE || buf[0] != ROM_HEADER_MAGIC)
        return RC_FAILED;

    hdr->mapperType = buf[2];
    hdr->bankSizeKB = buf[3];
    hdr->bankCount  = (uint16_t)buf[4] | ((uint16_t)buf[5] << 8);
    hdr->totalSize  = (uint32_t)buf[6] | ((uint32_t)buf[7] << 8) |
                       ((uint32_t)buf[8] << 16) | ((uint32_t)buf[9] << 24);

    if (reason && reasonBufSize > 0) {
        uint16_t reasonLen = replySize - ROM_HEADER_SIZE;
        if (reasonLen >= reasonBufSize)
            reasonLen = reasonBufSize - 1;
        for (uint16_t i = 0; i < reasonLen; i++)
            reason[i] = (char)buf[ROM_HEADER_SIZE + i];
        reason[reasonLen] = '\0';
    }

    return RC_SUCCESS;
}

int GetValidInput(char* outNumber) {
    outNumber[0] = '\0';

    while (1) {
        unsigned char key = WaitForKey();
        Locate(0, 0);
        if (key == 'P' || key == 'p') {
            return INPUT_P;
        }
        else if (key == 'N' || key == 'n') {
            return INPUT_N;
        }
        else if (key == 'Q' || key == 'q') {
            return INPUT_Q;
        }
        else if (key == KEY_UP) {
            return INPUT_UP;
        }
        else if (key == KEY_DOWN) {
            return INPUT_DOWN;
        }
        else if (IsDigit(key)) {
            int count = 0;
            while (count < 3) {
                outNumber[count++] = key;
                PrintChar(key);

                key = WaitForKey();
                if (key == KEY_ENTER) break;
                if (!IsDigit(key)) break;
            }
            outNumber[count] = '\0';
            return INPUT_NUMBER;
        }
    }
}

const unsigned char* showMenu(const unsigned char* options[], int count) {
    char choice;

    Print("=== MENU ===\n");
    Print("!! msxarch loader !!\n\n");
    for (int i = 0; i < count; i++) {
        PrintNumber(i + 1);
        Print(". "); Print(options[i]); Print("\n");
    }

    choice = InputChar();
    int choiceNum = choice - '0';

    if (choiceNum < 1 || choiceNum > count) {
        Print("Choice out of range.\n");
        return "Q";
    }

    return options[choiceNum - 1];
}

void sendQuit() {
    uint8_t rc = SendCommandToMSXPi("Q", false);
}

static FCB iniFcb;
static char iniBuffer[INI_BUFFER_SIZE];
static char repoList[MAX_REPOS][MAX_URL_LEN];

static void SetFcbFilename(FCB* fcb, const char* filename) {
    uint16_t i;
    uint8_t j;
    uint8_t* raw = (uint8_t*)fcb;

    for (i = 0; i < sizeof(FCB); i++) raw[i] = 0;
    for (i = 0; i < 8; i++) fcb->name[i] = ' ';
    for (i = 0; i < 3; i++) fcb->ext[i] = ' ';

    i = 0;
    while (filename[i] != '\0' && filename[i] != '.' && i < 8) {
        fcb->name[i] = filename[i];
        i++;
    }
    if (filename[i] == '.') {
        i++;
        for (j = 0; filename[i] != '\0' && j < 3; i++, j++) {
            fcb->ext[j] = filename[i];
        }
    }
}

static int LoadRepositoryList(void) {
    int count = 0;
    int col = 0;
    unsigned int bytesRead;
    unsigned int pos;

    SetFcbFilename(&iniFcb, INI_FILENAME);

    if (fcb_open(&iniFcb) != FCB_SUCCESS) {
        return 0;
    }

    bytesRead = fcb_read(&iniFcb, iniBuffer, INI_BUFFER_SIZE - 1);
    fcb_close(&iniFcb);

    for (pos = 0; pos <= bytesRead && count < MAX_REPOS; pos++) {
        char c = (pos < bytesRead) ? iniBuffer[pos] : '\n';

        if (c == '\r') continue;

        if (c == '\n') {
            repoList[count][col] = '\0';
            if (col > 0 && repoList[count][0] != ';' && repoList[count][0] != '#') {
                count++;
            }
            col = 0;
            continue;
        }

        if (col < MAX_URL_LEN - 1) {
            repoList[count][col++] = c;
        }
    }

    return count;
}

uint8_t loadrom(uint16_t totalSize) {
    uint8_t  rc;
    uint8_t  index = 1;
    // MAXBUFSIZE (msxpi.h) is 8192 - the block size negotiated here must
    // not exceed it. Asking for 16384 left the MSX waiting for payload
    // bytes the transfer never delivered, deadlocking against the server,
    // which believed it had sent the whole block and was waiting for the
    // MSX checksum. 8KB ROMs worked; 16KB and larger always hung.
    uint16_t block_size = MAXBUFSIZE;
    rc = PerformHandshake(block_size);
    if (rc == RC_SUCCESS) {
        uint8_t* romaddress = PAGE1ADDRESS;
        while (1) {
            pprintf("Reading game block ", index++); pprintf(" (", block_size); pprints(")", "\n");
            rc = RECVDATA_ONEBLOCK(romaddress, &block_size, block_size);
            romaddress += block_size;
            if (rc != RC_READY)
                break;
        }
    }

    // Stores into the ROM's own window (no-ops on a cartridge, corruption in
    // RAM) are neutralised by msxpi-server before sending - see
    // neutralise_rom_writes in mapper_detect.py. The linear scan that used to
    // run here also NOPed data that looked like a store and hung GALAGA.
    (void)totalSize;

    Print("Game loaded\n");
    return rc;
}

// ===========================================================================
// Mapper-aware ROM loading (Konami / ASCII8 / ASCII16)
// ===========================================================================

#define MAX_STORAGE_SEGMENTS 64   // 64 x 16K = 1MB
#define BANK_HALF_SIZE       0x2000

static uint8_t __at(0x3800) storageSegments[MAX_STORAGE_SEGMENTS];
static uint8_t __at(0x3840) execSegment1;
static uint8_t __at(0x3841) execSegment2;

static uint16_t __at(0x3843) mapperBlockSize;
static uint16_t __at(0x3845) mapperReceivedSize;
static uint16_t __at(0x3847) mapperBankIndex;
static uint8_t  __at(0x3849) mapperLoadRc;
static uint8_t  __at(0x384A) mapperCurrentSegment;
static uint16_t __at(0x384B) mapperCurrentOffset;
static uint16_t __at(0x384D) mapperBankCount;
static uint8_t  __at(0x384F) mapperBankSizeKB;
static uint8_t  __at(0x3850) mapperType;
static uint8_t  __at(0x3851) safeZoneSegment;

// ---------------------------------------------------------------------------
// Memory-mapper segment management WITHOUT MSX-DOS 2.
//
// This used to call Fusion-C's AllocateSegment()/FreeSegment(), which wrap the
// MSX-DOS 2 mapper support routines (ALL_SEG/FRE_SEG) - see the header comment
// in fusion-c/header/rammapper.h, "Use MSXDOS2 Memory mapper functions".
// MSXPi boots MSX-DOS 1, where those routines do not exist, so the call
// vectored into unmapped memory and the program ran away (observed: PC=0x77DC,
// with the "alloc rc=" trace never reached). That is why EVERY mapped ROM
// failed while plain ROMs worked - plain loading needs no segments at all.
//
// MSX-DOS 1 is not mapper-aware: it only ever uses the four segments currently
// selected in pages 0-3, and nothing arbitrates the rest. So we detect how many
// segments the mapper really has and hand them out ourselves, top down, never
// touching the four DOS is living in.
// ---------------------------------------------------------------------------
#define SEGPORT_PAGE2   0xFE

// Deliberately NOT __at() fixed addresses. The msxarch browse buffer is
// get_buffer_ptr()+100 and runs 22*80 bytes from there - with the current
// binary that is 0x35C8..0x3CA8, straight through the 0x3800 block these
// used to live in, so the menu text silently overwrote them (segTotal read
// back as 0 no matter what detection returned). Let the linker place them.
static uint8_t segInUse0;
static uint8_t segInUse1;
static uint8_t segInUse2;
static uint8_t segInUse3;
static uint8_t segTotal;
static uint8_t segNext;

static uint8_t segmentIsReserved(uint8_t seg) {
    return (seg == segInUse0 || seg == segInUse1 ||
            seg == segInUse2 || seg == segInUse3);
}

// Find how many segments the mapper really has, by locating the point at
// which selecting a higher segment number wraps back onto segment 0.
//
// The obvious "write a marker into all 256, then read them all back" does NOT
// work: on a mapper with N segments the writes above N-1 alias downwards and
// clobber the very markers being verified, so segment 0 reads back as 252 and
// the count comes out 0. That was the "have 0, need 8" failure.
//
// Instead keep segment 0 as a sentinel and step upwards: the first n whose
// write disturbs segment 0's sentinel is the wrap point, so the mapper has n
// segments.
static uint8_t detectMapperSegments(void) {
    uint8_t  saved = InPort(SEGPORT_PAGE2);
    uint16_t n;
    uint16_t count = 1;                  // NOT uint8_t: a 4MB mapper has 256
    volatile uint8_t* probe = PAGE2ADDRESS;
    uint8_t  keep0, keepN;

    // Save/restore every byte touched. The probe address maps to the same
    // offset in whichever segment is selected, including the segments DOS is
    // running from, so writing without restoring corrupts the running system.
    OutPort(SEGPORT_PAGE2, 0);
    keep0 = *probe;
    *probe = 0xA5;

    for (n = 1; n < 256; n++) {
        OutPort(SEGPORT_PAGE2, (uint8_t)n);
        keepN = *probe;
        *probe = (uint8_t)n;

        OutPort(SEGPORT_PAGE2, 0);
        if (*probe != 0xA5) {                    // wrapped onto segment 0
            OutPort(SEGPORT_PAGE2, (uint8_t)n);
            *probe = keepN;
            break;
        }

        OutPort(SEGPORT_PAGE2, (uint8_t)n);
        if (*probe != (uint8_t)n) { *probe = keepN; break; }
        *probe = keepN;
        count = n + 1;
    }

    OutPort(SEGPORT_PAGE2, 0);
    *probe = keep0;
    OutPort(SEGPORT_PAGE2, saved);

    // 256 segments (4MB) does not fit a uint8_t segment number; the highest
    // addressable segment is 255. Returning the count as uint8_t is what made
    // a fully populated mapper report "0 segments".
    if (count > 255) count = 255;
    return (uint8_t)count;
}

static uint8_t takeSegment(uint8_t* out) {
    while (segNext > 0) {
        uint8_t seg = segNext--;
        if (!segmentIsReserved(seg)) { *out = seg; return RC_SUCCESS; }
    }
    return RC_FAILED;
}

static uint8_t allocateMapperSegments(uint8_t storageCount) {
    uint8_t i;

    segInUse0 = InPort(0xFC);
    segInUse1 = InPort(0xFD);
    segInUse2 = InPort(0xFE);
    segInUse3 = InPort(0xFF);

    segTotal = detectMapperSegments();
    if (segTotal < (uint8_t)(storageCount + 4)) {
        pprintf("Not enough mapper segments: have ", segTotal);
        pprintf(", need ", (uint16_t)storageCount + 4); pprints("", "\n");
        return RC_FAILED;
    }
    segNext = (uint8_t)(segTotal - 1);

    if (takeSegment(&execSegment1) != RC_SUCCESS) return RC_FAILED;
    if (takeSegment(&execSegment2) != RC_SUCCESS) return RC_FAILED;
    for (i = 0; i < storageCount; i++) {
        if (takeSegment(&storageSegments[i]) != RC_SUCCESS) return RC_FAILED;
    }
    if (takeSegment(&safeZoneSegment) != RC_SUCCESS) return RC_FAILED;

    return RC_SUCCESS;
}

static void freeMapperSegments(uint16_t storageCount) {
    // Nothing to hand back: without MSX-DOS 2 there is no allocator holding a
    // claim. Just put page 2 back where DOS had it, since the loader moves it
    // around while filling the storage segments.
    (void)storageCount;
    OutPort(SEGPORT_PAGE2, segInUse2);
}


static void PutPN_direct(uint8_t page, uint8_t segment) {
    OutPort(0xFC + page, segment);
}

static void enterSafeZone(void) {
    PutPN_direct(2, safeZoneSegment);
}

static uint8_t loadBanksIntoStorage(uint16_t bankCount, uint8_t bankSizeKB) {
    uint16_t chunks;
    uint16_t c;
    uint8_t  rc;

    mapperBankCount  = bankCount;
    mapperBankSizeKB = bankSizeKB;

    // Always transfer in MAXBUFSIZE (8KB) units, never 16KB. A 16KB block
    // negotiation leaves the MSX waiting for payload bytes that never arrive
    // and deadlocks against the server - the same bug that stopped every
    // plain ROM >= 16KB from loading (see loadrom).
    //
    // The chunk -> (segment, offset) mapping is the same either way: a 16KB
    // bank fills one 16KB segment as two 8KB halves, and two 8KB banks fill
    // one segment as two halves. So chunk c always lands at segment c/2,
    // offset (c & 1) * 8KB.
    mapperBlockSize = MAXBUFSIZE;
    chunks = bankCount * (uint16_t)(bankSizeKB / 8);

    // The server sends the whole ROM as one multi-block stream, and
    // sendmultiblock() opens it with a handshake. Without this the server sat
    // waiting for a READY the MSX never sent, and the transfer never started.
    rc = PerformHandshake(mapperBlockSize);
    if (rc != RC_SUCCESS) return RC_FAILED;

    for (c = 0; c < chunks; c++) {
        mapperCurrentSegment = storageSegments[c >> 1];
        mapperCurrentOffset  = (c & 1) ? BANK_HALF_SIZE : 0;
        mapperReceivedSize   = mapperBlockSize;

        PutPN_direct(2, mapperCurrentSegment);
        mapperLoadRc = RECVDATA_ONEBLOCK(PAGE2ADDRESS + mapperCurrentOffset,
                                         &mapperReceivedSize, mapperBlockSize);

        if (mapperLoadRc != RC_READY && mapperLoadRc != RC_SUCCESS) return RC_FAILED;
        if (mapperReceivedSize == 0) return RC_FAILED;
    }

    PutPN_direct(2, execSegment2);
    return RC_SUCCESS;
}

// A cartridge mapper decodes an address RANGE, not one address. Ranges taken
// from EXECROM.MAC's own MegaROM table (git 173f41c2), which this project
// already ships a working loader for:
//     ASCII16 : 6000h-6FFFh (bank at 4000h), 7000h-7FFFh (bank at 8000h)
//     ASCII8  : 6000h-67FFh, 6800h-6FFFh, 7000h-77FFh, 7800h-7FFFh
//     Konami4 : 6000h, 8000h, A000h (single addresses)
// Matching only the exact address misses most real switches on ASCII16:
// ARCTIC.ROM switches via 6002h and was never patched at all; XEVIOUS.ROM
// uses 18 different addresses of which only one is 7000h.
static void patchWindow(uint8_t* base, uint16_t rangeLo, uint16_t rangeHi,
                        void (*handler)(void)) {
    uint16_t i;
    uint16_t handlerAddr = (uint16_t)handler;
    for (i = 0; i < 0x4000 - 2; i++) {
        if (base[i] == 0x32) {
            uint16_t addr = (uint16_t)base[i + 1] | ((uint16_t)base[i + 2] << 8);
            if (addr >= rangeLo && addr <= rangeHi) {
                base[i] = 0xCD;  // CALL nn
                base[i + 1] = handlerAddr & 0xFF;
                base[i + 2] = (handlerAddr >> 8) & 0xFF;
            }
        }
    }
}

static void mapperCopyBank(uint8_t bank, uint16_t targetOffset, uint8_t sourcePage, uint8_t targetPage) {
    uint8_t storageSegment = storageSegments[bank >> 1];
    uint16_t sourceOffset = (bank & 1) ? BANK_HALF_SIZE : 0;
    uint8_t* src;
    uint8_t* dst;
    uint16_t i;

    __asm
        di
    __endasm;

    PutPN_direct(sourcePage, storageSegment);
    src = (sourcePage == 1 ? PAGE1ADDRESS : PAGE2ADDRESS) + sourceOffset;
    dst = (targetPage == 1 ? PAGE1ADDRESS : PAGE2ADDRESS) + targetOffset;
    for (i = 0; i < BANK_HALF_SIZE; i++) {
        dst[i] = src[i];
    }
    PutPN_direct(sourcePage, sourcePage == 1 ? execSegment1 : execSegment2);

    __asm
        ei
    __endasm;
}

// ---------------------------------------------------------------------------
// Page 3 Resident Handlers & Addresses (0xE000 - 0xE1FF)
// ---------------------------------------------------------------------------
// Resident bank-switch handlers + segment table.
// These MUST survive the launched game, and a cartridge game owns all user
// RAM: BILLIARD.ROM's first instructions are
//     ld sp,0F380h / ld hl,0C000h / ld de,0C001h / ld bc,337Fh
//     ld (hl),0 / ldir
// which zeroes 0xC000-0xF37F. Both 0xE000 and 0xF100 were wiped by that,
// taking storageSegments[0] in the table with them, after which every bank
// switch selected segment 0 and the CPU ran through garbage.
// 0xF975 upwards is above the clear and below the BIOS hook area at 0xFD9A -
// the same region SofaRun relocates its own resident stub into
// (ld hl,7255h / ld de,0F975h / ld bc,0160h / ldir).
// Layout: table 0xF975-0xF9B4, exec 0xF9B5-0xF9B6, 8K handlers 0xF9C0-0xFABF,
// 16K handlers 0xFAC0-0xFAEF (MSX2 system variables start at 0xFAF5).
// The 16K handlers are 13h bytes each and must stay below FAF5h, where the
// MSX2 system variables start (DPPAGE, ACPAGE, EXBRSA at FAF8h...). At FB00h
// with a 40h copy they overwrote EXBRSA, so every SUB-ROM call hung and all
// ASCII16 ROMs died right after "Starting game...".
#define RESIDENT_PAGE1_ADDR   0xFAC0
#define RESIDENT_PAGE2_ADDR   0xFAD8
#define RESIDENT_16K_SLOT     0x18
#define RESIDENT_TABLE_ADDR   0xF975
#define RESIDENT_EXEC1_ADDR   0xF9B5
#define RESIDENT_EXEC2_ADDR   0xF9B6
// Do NOT spread these out. Widening the slots to 0x50 pushed WIN4's slot to
// FAB0-FAFF, past the end of the usable window at FAD5, and every 8K game
// died right after "Starting game...". Four 0x40 slots from F9C0 end at FABF,
// which fits; the handlers below are sized to match.
#define RESIDENT_8K_WIN1_ADDR 0xF9C0
#define RESIDENT_8K_WIN2_ADDR 0xFA00
#define RESIDENT_8K_WIN3_ADDR 0xFA40
#define RESIDENT_8K_WIN4_ADDR 0xFA80
#define RESIDENT_SLOT_SIZE    0x40
// Four bytes (one per 8K window) holding the bank number currently resident in
// that window, living in the gap between EXEC2 (F9B6) and WIN1 (F9C0).
#define RESIDENT_CACHE_ADDR   0xF9B7
#define RESIDENT_TABLE_ENTRIES 0x40   // F975-F9B4, indexed by AND 3Fh

// The server patches the ROM's bank-switch writes into CALLs to our resident
// handlers, so it has to know where they ended up. Derive the addresses from
// the RESIDENT_ defines rather than hardcoding them anywhere else - if these
// and the server's idea of them ever diverge, every patched CALL lands in the
// wrong place.
static void appendHex4(char* dst, uint16_t v) {
    const char* h = "0123456789ABCDEF";
    dst[0] = h[(v >> 12) & 15];
    dst[1] = h[(v >> 8) & 15];
    dst[2] = h[(v >> 4) & 15];
    dst[3] = h[v & 15];
}

static void buildSelection(char* out, const char* number) {
    static const uint16_t addr[6] = {
        RESIDENT_8K_WIN1_ADDR, RESIDENT_8K_WIN2_ADDR,
        RESIDENT_8K_WIN3_ADDR, RESIDENT_8K_WIN4_ADDR,
        RESIDENT_PAGE1_ADDR,   RESIDENT_PAGE2_ADDR
    };
    uint8_t i = 0, j;
    while (number[i]) { out[i] = number[i]; i++; }
    for (j = 0; j < 6; j++) {
        out[i++] = ' ';
        appendHex4(out + i, addr[j]);
        i += 4;
    }
    out[i] = 0;
}


// --- ASCII16 Resident Handlers ---
void ascii16Page1Handler(void) __naked {
    __asm
        push af
        push hl
        push bc
        and #0x3F        ; bound to the 64-entry table (see the 8K handlers)
        ld l, a
        ld h, #0
        ld bc, #RESIDENT_TABLE_ADDR
        add hl, bc
        ld a, (hl)
        out (#0xFD), a
        pop bc
        pop hl
        pop af
        ret
    __endasm;
}

void ascii16Page2Handler(void) __naked {
    __asm
        push af
        push hl
        push bc
        and #0x3F        ; bound to the 64-entry table (see the 8K handlers)
        ld l, a
        ld h, #0
        ld bc, #RESIDENT_TABLE_ADDR
        add hl, bc
        ld a, (hl)
        out (#0xFE), a
        pop bc
        pop hl
        pop af
        ret
    __endasm;
}

static void relocateResidentHandlers16K(uint16_t storageCount) {
    uint16_t i;
    uint8_t* table = (uint8_t*)RESIDENT_TABLE_ADDR;
    uint8_t* dst1 = (uint8_t*)RESIDENT_PAGE1_ADDR;
    uint8_t* dst2 = (uint8_t*)RESIDENT_PAGE2_ADDR;
    uint8_t* src1 = (uint8_t*)ascii16Page1Handler;
    uint8_t* src2 = (uint8_t*)ascii16Page2Handler;

    // Fill all 64 entries, mirroring the ROM the way the cartridge hardware
    // does, instead of only the first storageCount. Combined with the AND 3Fh
    // in the handlers this makes every reachable index resolve to a real
    // segment: for a power-of-two ROM, table[(bank & 3Fh) % storageCount] is
    // exactly the segment the mapper would have selected.
    for (i = 0; i < RESIDENT_TABLE_ENTRIES; i++)
        table[i] = storageSegments[i % storageCount];
    for (i = 0; i < RESIDENT_16K_SLOT; i++) dst1[i] = src1[i];
    for (i = 0; i < RESIDENT_16K_SLOT; i++) dst2[i] = src2[i];
}

static void patchAllStorageSegmentsAscii16(uint16_t segmentCount) {
    uint16_t s;
    for (s = 0; s < segmentCount; s++) {
        PutPN_direct(1, storageSegments[s]);
        patchWindow(PAGE1ADDRESS, 0x6000, 0x6FFF, (void (*)(void))RESIDENT_PAGE1_ADDR);
        patchWindow(PAGE1ADDRESS, 0x7000, 0x7FFF, (void (*)(void))RESIDENT_PAGE2_ADDR);
    }
}

// --- Konami & ASCII8 8K Resident Handlers ---
void ascii8Win1Handler(void) __naked {
    __asm
        ; Fast path first: a mapper ignores a write re-selecting the bank the
        ; window already holds, but this used to re-copy 8KB regardless - ~48ms
        ; of LDIR. Games rewrite bank registers constantly, so PC sampling
        ; found 20/20 samples inside this LDIR. Bail out before touching
        ; interrupts when the bank has not changed.
        push af
        push hl
        ld hl, #(RESIDENT_CACHE_ADDR + 0)
        cp (hl)
        jr nz, 3$
        pop hl
        pop af
        ret
    3$:
        ld (hl), a
        push bc
        push de
        ld a, i          ; P/V = IFF2, the interrupt state of the caller
        push af
        di
        ; RRCA does double duty: carry becomes bank bit 0 (which half of the
        ; 16K segment) and A becomes bank>>1, the segment index. The AND 3Fh
        ; masks it to the 64-entry table AND clears the bit RRCA rotated in.
        ; Masking matters: unmasked, a bank number larger than the ROM indexed
        ; past the table into whatever DOS left there and selected a garbage
        ; segment - NEMESIS does this on its first switch, ld a,(F0F2h) with
        ; F0F2h uninitialised.
        ld a, (hl)
        rrca
        ld de, #0x8000
        jr nc, 2$
        ld d, #0xA0
    2$:
        and #0x3F
        ; Table is 64 bytes at F975, so low byte 75h+3Fh = B4h cannot carry.
        add a, #(RESIDENT_TABLE_ADDR & 0xFF)
        ld l, a
        ld h, #(RESIDENT_TABLE_ADDR >> 8)
        ld a, (hl)
        out (#0xFE), a
        ex de, hl
        ld de, #0x4000
        ld bc, #0x2000
        ldir
        ld a, (#RESIDENT_EXEC2_ADDR)
        out (#0xFE), a
        ; This code is COPIED into RAM, so every jump must be RELATIVE: a
        ; `jp po` assembled to the link-time address inside the msxarch.com
        ; page-0 image, and launchGame() maps the BIOS over page 0 before the
        ; game runs. JR has no P/O condition, so test bit 2 (P/V) of saved F.
        pop hl           ; H = A, L = F from the `ld a,i` snapshot
        ; Acknowledge the VDP interrupt that went pending during the LDIR.
        ; A copy takes ~45ms, longer than a frame; BILLIARD switches two
        ; windows from its interrupt routine and then does EI, so the pending
        ; interrupt nested every frame until the stack reached C000h.
        in a, (#0x99)
        bit 2, l
        jr z, 9$         ; caller had interrupts off - leave them off
        ei
    9$:
        pop de
        pop bc
        pop hl
        pop af
        ret
    __endasm;
}

void ascii8Win2Handler(void) __naked {
    __asm
        ; Fast path first: a mapper ignores a write re-selecting the bank the
        ; window already holds, but this used to re-copy 8KB regardless - ~48ms
        ; of LDIR. Games rewrite bank registers constantly, so PC sampling
        ; found 20/20 samples inside this LDIR. Bail out before touching
        ; interrupts when the bank has not changed.
        push af
        push hl
        ld hl, #(RESIDENT_CACHE_ADDR + 1)
        cp (hl)
        jr nz, 3$
        pop hl
        pop af
        ret
    3$:
        ld (hl), a
        push bc
        push de
        ld a, i          ; P/V = IFF2, the interrupt state of the caller
        push af
        di
        ; RRCA does double duty: carry becomes bank bit 0 (which half of the
        ; 16K segment) and A becomes bank>>1, the segment index. The AND 3Fh
        ; masks it to the 64-entry table AND clears the bit RRCA rotated in.
        ; Masking matters: unmasked, a bank number larger than the ROM indexed
        ; past the table into whatever DOS left there and selected a garbage
        ; segment - NEMESIS does this on its first switch, ld a,(F0F2h) with
        ; F0F2h uninitialised.
        ld a, (hl)
        rrca
        ld de, #0x8000
        jr nc, 2$
        ld d, #0xA0
    2$:
        and #0x3F
        ; Table is 64 bytes at F975, so low byte 75h+3Fh = B4h cannot carry.
        add a, #(RESIDENT_TABLE_ADDR & 0xFF)
        ld l, a
        ld h, #(RESIDENT_TABLE_ADDR >> 8)
        ld a, (hl)
        out (#0xFE), a
        ex de, hl
        ld de, #0x6000
        ld bc, #0x2000
        ldir
        ld a, (#RESIDENT_EXEC2_ADDR)
        out (#0xFE), a
        ; This code is COPIED into RAM, so every jump must be RELATIVE: a
        ; `jp po` assembled to the link-time address inside the msxarch.com
        ; page-0 image, and launchGame() maps the BIOS over page 0 before the
        ; game runs. JR has no P/O condition, so test bit 2 (P/V) of saved F.
        pop hl           ; H = A, L = F from the `ld a,i` snapshot
        ; Acknowledge the VDP interrupt that went pending during the LDIR.
        ; A copy takes ~45ms, longer than a frame; BILLIARD switches two
        ; windows from its interrupt routine and then does EI, so the pending
        ; interrupt nested every frame until the stack reached C000h.
        in a, (#0x99)
        bit 2, l
        jr z, 9$         ; caller had interrupts off - leave them off
        ei
    9$:
        pop de
        pop bc
        pop hl
        pop af
        ret
    __endasm;
}

void ascii8Win3Handler(void) __naked {
    __asm
        ; Fast path first: a mapper ignores a write re-selecting the bank the
        ; window already holds, but this used to re-copy 8KB regardless - ~48ms
        ; of LDIR. Games rewrite bank registers constantly, so PC sampling
        ; found 20/20 samples inside this LDIR. Bail out before touching
        ; interrupts when the bank has not changed.
        push af
        push hl
        ld hl, #(RESIDENT_CACHE_ADDR + 2)
        cp (hl)
        jr nz, 3$
        pop hl
        pop af
        ret
    3$:
        ld (hl), a
        push bc
        push de
        ld a, i          ; P/V = IFF2, the interrupt state of the caller
        push af
        di
        ; RRCA does double duty: carry becomes bank bit 0 (which half of the
        ; 16K segment) and A becomes bank>>1, the segment index. The AND 3Fh
        ; masks it to the 64-entry table AND clears the bit RRCA rotated in.
        ; Masking matters: unmasked, a bank number larger than the ROM indexed
        ; past the table into whatever DOS left there and selected a garbage
        ; segment - NEMESIS does this on its first switch, ld a,(F0F2h) with
        ; F0F2h uninitialised.
        ld a, (hl)
        rrca
        ld de, #0x4000
        jr nc, 2$
        ld d, #0x60
    2$:
        and #0x3F
        ; Table is 64 bytes at F975, so low byte 75h+3Fh = B4h cannot carry.
        add a, #(RESIDENT_TABLE_ADDR & 0xFF)
        ld l, a
        ld h, #(RESIDENT_TABLE_ADDR >> 8)
        ld a, (hl)
        out (#0xFD), a
        ex de, hl
        ld de, #0x8000
        ld bc, #0x2000
        ldir
        ld a, (#RESIDENT_EXEC1_ADDR)
        out (#0xFD), a
        ; This code is COPIED into RAM, so every jump must be RELATIVE: a
        ; `jp po` assembled to the link-time address inside the msxarch.com
        ; page-0 image, and launchGame() maps the BIOS over page 0 before the
        ; game runs. JR has no P/O condition, so test bit 2 (P/V) of saved F.
        pop hl           ; H = A, L = F from the `ld a,i` snapshot
        ; Acknowledge the VDP interrupt that went pending during the LDIR.
        ; A copy takes ~45ms, longer than a frame; BILLIARD switches two
        ; windows from its interrupt routine and then does EI, so the pending
        ; interrupt nested every frame until the stack reached C000h.
        in a, (#0x99)
        bit 2, l
        jr z, 9$         ; caller had interrupts off - leave them off
        ei
    9$:
        pop de
        pop bc
        pop hl
        pop af
        ret
    __endasm;
}

void ascii8Win4Handler(void) __naked {
    __asm
        ; Fast path first: a mapper ignores a write re-selecting the bank the
        ; window already holds, but this used to re-copy 8KB regardless - ~48ms
        ; of LDIR. Games rewrite bank registers constantly, so PC sampling
        ; found 20/20 samples inside this LDIR. Bail out before touching
        ; interrupts when the bank has not changed.
        push af
        push hl
        ld hl, #(RESIDENT_CACHE_ADDR + 3)
        cp (hl)
        jr nz, 3$
        pop hl
        pop af
        ret
    3$:
        ld (hl), a
        push bc
        push de
        ld a, i          ; P/V = IFF2, the interrupt state of the caller
        push af
        di
        ; RRCA does double duty: carry becomes bank bit 0 (which half of the
        ; 16K segment) and A becomes bank>>1, the segment index. The AND 3Fh
        ; masks it to the 64-entry table AND clears the bit RRCA rotated in.
        ; Masking matters: unmasked, a bank number larger than the ROM indexed
        ; past the table into whatever DOS left there and selected a garbage
        ; segment - NEMESIS does this on its first switch, ld a,(F0F2h) with
        ; F0F2h uninitialised.
        ld a, (hl)
        rrca
        ld de, #0x4000
        jr nc, 2$
        ld d, #0x60
    2$:
        and #0x3F
        ; Table is 64 bytes at F975, so low byte 75h+3Fh = B4h cannot carry.
        add a, #(RESIDENT_TABLE_ADDR & 0xFF)
        ld l, a
        ld h, #(RESIDENT_TABLE_ADDR >> 8)
        ld a, (hl)
        out (#0xFD), a
        ex de, hl
        ld de, #0xA000
        ld bc, #0x2000
        ldir
        ld a, (#RESIDENT_EXEC1_ADDR)
        out (#0xFD), a
        ; This code is COPIED into RAM, so every jump must be RELATIVE: a
        ; `jp po` assembled to the link-time address inside the msxarch.com
        ; page-0 image, and launchGame() maps the BIOS over page 0 before the
        ; game runs. JR has no P/O condition, so test bit 2 (P/V) of saved F.
        pop hl           ; H = A, L = F from the `ld a,i` snapshot
        ; Acknowledge the VDP interrupt that went pending during the LDIR.
        ; A copy takes ~45ms, longer than a frame; BILLIARD switches two
        ; windows from its interrupt routine and then does EI, so the pending
        ; interrupt nested every frame until the stack reached C000h.
        in a, (#0x99)
        bit 2, l
        jr z, 9$         ; caller had interrupts off - leave them off
        ei
    9$:
        pop de
        pop bc
        pop hl
        pop af
        ret
    __endasm;
}

static void relocateResidentHandlers8K(uint16_t storageCount) {
    uint16_t i;
    uint8_t* table = (uint8_t*)RESIDENT_TABLE_ADDR;
    uint8_t* exec1 = (uint8_t*)RESIDENT_EXEC1_ADDR;
    uint8_t* exec2 = (uint8_t*)RESIDENT_EXEC2_ADDR;

    // Fill all 64 entries, mirroring the ROM the way the cartridge hardware
    // does, instead of only the first storageCount. Combined with the AND 3Fh
    // in the handlers this makes every reachable index resolve to a real
    // segment: for a power-of-two ROM, table[(bank & 3Fh) % storageCount] is
    // exactly the segment the mapper would have selected.
    for (i = 0; i < RESIDENT_TABLE_ENTRIES; i++)
        table[i] = storageSegments[i % storageCount];
    *exec1 = execSegment1;
    *exec2 = execSegment2;

    // konamiInitialSetup/ascii8InitialSetup load banks 0..3 into windows 1..4,
    // so seed the cache with those - otherwise the first genuine switch to one
    // of them would be skipped as a no-op.
    for (i = 0; i < 4; i++) ((uint8_t*)RESIDENT_CACHE_ADDR)[i] = (uint8_t)i;

    uint8_t* src1 = (uint8_t*)ascii8Win1Handler;
    uint8_t* src2 = (uint8_t*)ascii8Win2Handler;
    uint8_t* src3 = (uint8_t*)ascii8Win3Handler;
    uint8_t* src4 = (uint8_t*)ascii8Win4Handler;

    uint8_t* dst1 = (uint8_t*)RESIDENT_8K_WIN1_ADDR;
    uint8_t* dst2 = (uint8_t*)RESIDENT_8K_WIN2_ADDR;
    uint8_t* dst3 = (uint8_t*)RESIDENT_8K_WIN3_ADDR;
    uint8_t* dst4 = (uint8_t*)RESIDENT_8K_WIN4_ADDR;

    for (i = 0; i < RESIDENT_SLOT_SIZE; i++) {
        dst1[i] = src1[i];
        dst2[i] = src2[i];
        dst3[i] = src3[i];
        dst4[i] = src4[i];
    }
}

static void patchAllStorageSegmentsKonami(uint16_t segmentCount) {
    uint16_t s;
    for (s = 0; s < segmentCount; s++) {
        PutPN_direct(1, storageSegments[s]);
        patchWindow(PAGE1ADDRESS, 0x6000, 0x6000, (void (*)(void))RESIDENT_8K_WIN2_ADDR);
        patchWindow(PAGE1ADDRESS, 0x8000, 0x8000, (void (*)(void))RESIDENT_8K_WIN3_ADDR);
        patchWindow(PAGE1ADDRESS, 0xA000, 0xA000, (void (*)(void))RESIDENT_8K_WIN4_ADDR);
    }
}

static void patchAllStorageSegmentsAscii8(uint16_t segmentCount) {
    uint16_t s;
    for (s = 0; s < segmentCount; s++) {
        PutPN_direct(1, storageSegments[s]);
        patchWindow(PAGE1ADDRESS, 0x6000, 0x6000, (void (*)(void))RESIDENT_8K_WIN1_ADDR);
        patchWindow(PAGE1ADDRESS, 0x6800, 0x6800, (void (*)(void))RESIDENT_8K_WIN2_ADDR);
        patchWindow(PAGE1ADDRESS, 0x7000, 0x7000, (void (*)(void))RESIDENT_8K_WIN3_ADDR);
        patchWindow(PAGE1ADDRESS, 0x7800, 0x7800, (void (*)(void))RESIDENT_8K_WIN4_ADDR);
    }
}

static void konamiInitialSetup(uint16_t bankCount) {
    PutPN_direct(1, execSegment1);
    PutPN_direct(2, execSegment2);
    mapperCopyBank(0, 0, 2, 1);
    if (bankCount > 1) mapperCopyBank(1, BANK_HALF_SIZE, 2, 1);
    if (bankCount > 2) mapperCopyBank(2, 0, 1, 2);
    if (bankCount > 3) mapperCopyBank(3, BANK_HALF_SIZE, 1, 2);
}

static void ascii8InitialSetup(uint16_t bankCount) {
    PutPN_direct(1, execSegment1);
    PutPN_direct(2, execSegment2);
    mapperCopyBank(0, 0, 2, 1);
    if (bankCount > 1) mapperCopyBank(1, BANK_HALF_SIZE, 2, 1);
    if (bankCount > 2) mapperCopyBank(2, 0, 1, 2);
    if (bankCount > 3) mapperCopyBank(3, BANK_HALF_SIZE, 1, 2);
}

uint8_t loadMappedRom(RomHeader* hdr) {
    uint16_t storageCount;
    uint8_t rc;

    storageCount = (hdr->bankSizeKB == 16) ? hdr->bankCount : (hdr->bankCount + 1) / 2;
    if (storageCount > MAX_STORAGE_SEGMENTS) {
        pprintf("ROM too large: needs ", storageCount); Print(" segments\n");
        return RC_FAILED;
    }

    rc = allocateMapperSegments((uint8_t)storageCount);
    if (rc != RC_SUCCESS) return rc;

    rc = loadBanksIntoStorage(hdr->bankCount, hdr->bankSizeKB);
    if (rc != RC_SUCCESS) {
        Print("Error loading ROM banks\n");
        freeMapperSegments(storageCount);
        return rc;
    }

    // The bank-switch writes are already CALLs to our resident handlers -
    // msxpi-server patches the image before sending it, using the handler
    // addresses buildSelection() supplied. Scanning here as well cost 16KB
    // per storage segment on the Z80 (128KB of scanning for a 128KB ROM)
    // before the game could start. relocateResidentHandlers* still runs:
    // the handlers themselves must be copied into RAM.
    if (hdr->mapperType == MAPPER_ASCII16) {
        relocateResidentHandlers16K(storageCount);
        PutPN_direct(1, storageSegments[0]);
        PutPN_direct(2, storageSegments[hdr->bankCount > 1 ? 1 : 0]);
    } else if (hdr->mapperType == MAPPER_KONAMI) {
        relocateResidentHandlers8K(storageCount);
        konamiInitialSetup(hdr->bankCount);
    } else if (hdr->mapperType == MAPPER_ASCII8) {
        relocateResidentHandlers8K(storageCount);
        ascii8InitialSetup(hdr->bankCount);
    }

    Print("Game loaded\n");
    return RC_SUCCESS;
}

void launchGame(void) {
    Print("Starting game...\n");

    __asm
        di

        ; Copy trampoline routine to Page 3 RAM (0xC000)
        ld hl, #1$
        ld de, #0xC000
        ld bc, #2$ - #1$
        ldir

        ; Jump to Page 3 RAM to safely execute the slot switch
        jp 0xC000

    1$:
        ; Disable MSX-DOS timer hook (H.TIMI)
        ld a, #0xC9
        ld (#0xFD9F), a

        ; Read Main BIOS primary slot from EXPTBL[0] (0xFCC1)
        ld a, (#0xFCC1)
        and #0x03
        ld c, a

        ; Set Page 0 Primary Slot to Main BIOS (unmaps Page 0 RAM)
        in a, (#0xA8)
        and #0xFC
        or c
        out (#0xA8), a

        ; Give the game the hook table a cartridge sees. MSX-DOS and the MSXPi
        ; driver leave ~34 hooks as RST 30h inter-slot calls into their own
        ; ROM (F7 01 xx here); a cold cartridge boot has only the BIOS and
        ; SUB-ROM ones. Games calling BIOS routines that pass through those
        ; hooks detoured into the MSXPi ROM - FROGGER stayed black, VALLEY
        ; stuck on its logo. Every RST 30h hook whose slot is neither the main
        ; BIOS slot (EXPTBL) nor the SUB-ROM slot (EXBRSA) becomes RET.
        ld hl, #0xFD9A
    3$:
        ld a, (hl)
        cp #0xF7
        jr nz, 4$
        inc hl
        ld a, (hl)
        dec hl
        ld b, a
        ld a, (#0xFCC1)          ; EXPTBL: main BIOS slot
        cp b
        jr z, 4$
        ld a, (#0xFAF8)          ; EXBRSA: SUB-ROM slot (0 on MSX1)
        cp b
        jr z, 4$
        ld (hl), #0xC9
    4$:
        ld de, #5
        add hl, de
        ld a, h
        cp #0xFF
        jr nz, 3$
        ld a, l
        cp #0xCF                 ; up to and including EXTBIO at FFCAh
        jr c, 3$

        ; Put the screen into the state a cartridge boots in: SCREEN 1, 32
        ; columns (INIT32), as the BIOS does before calling a cartridge INIT.
        ; MSX-DOS "mode 80" leaves SCREEN 0 at 80 columns, and the MSX2 BIOS
        ; VRAM routines then keep selecting VRAM page R#14=1 - every write
        ; the game made through them landed above 4000h and was never shown,
        ; so FROGGER.ROM ran with a black screen. Page 0 is the BIOS by now
        ; and the hooks INIT32 passes through have been cleared above.
        call #0x006F

        ; Read entry vector from Page 1 (0x4002) and jump with DI
        ld hl, (#0x4002)
        jp (hl)

    2$:
    __endasm;
}

int main(void) {
    Width(80);

    const unsigned char* items[MAX_REPOS + 1];
    int repoCount = LoadRepositoryList();
    int i;

    if (repoCount == 0) {
        StrCopy(repoList[0], "https://web.archive.org/web/20241204120811/https://www.msxarchive.nl/pub/msx/games/roms/msx1");
        repoCount = 1;
    }

    for (i = 0; i < repoCount; i++) {
        items[i] = (const unsigned char*)repoList[i];
    }
    items[repoCount] = "Exit";

    int itemCount = repoCount + 1;
    char parameters[BLKSIZE + 1];
    const unsigned char* selected = showMenu(items, itemCount);

    if (StrCompare(selected, "Exit") == 0 || StrCompare(selected, "Q") == 0) {
        Print("Exit selected.\n");
        return 0;
    }

    if (selected != NULL) {
        for (int i = 0; i < BLKSIZE + 1; i++) {
            parameters[i] = 0;
        }

        int pos = 0;
        int j = 0;
        while (selected[j] != '\0' && pos < BLKSIZE) {
            parameters[pos] = selected[j];
            pos++;
            j++;
        }

        parameters[BLKSIZE] = 0;

        Print("You selected: ");
        Print(parameters);
        Print("\nConnecting...\n");
    }

    uint8_t rc;
    int cmd;

    rc = SendCommandToMSXPi("msxarchive", false);
    if (rc != RC_SUCCESS) {
        Print("Error sending command to MSXPi!\n");
        sendQuit();
        return 1;
    }

    pprints("Sending parameters: ", parameters);
    rc = SendCommandToMSXPi(parameters, false);
    if (rc != RC_SUCCESS) {
        sendQuit();
        return 1;
    }

    uint8_t* buffer = (uint8_t*)(get_buffer_ptr() + 100);
    uint16_t size = 22 * 80;
    char userNumber[INPUTLEN];
    uint16_t replySize = 0;
    uint16_t maxbuf = MAXBUFSIZE;

    while (1) {
        rc = RECVDATA(buffer, &replySize, &maxbuf);

        if (rc != RC_SUCCESS) {
            sendQuit();
            break;
        }
        buffer[size - 1] = '\0';

        Locate(0, 1);
        Print("================================================================================");
        Locate(0, 2);
        FastPrint(buffer);
        Locate(0, 0);
        Print("     Q = Quit  N/Down = Next Page  P/Up = Previous Page or Game Number to load");

        Locate(0, 0);
        cmd = GetValidInput(userNumber);
        if (cmd == INPUT_Q)
            break;
        else if (cmd == INPUT_N || cmd == INPUT_DOWN) {
            rc = SendCommandToMSXPi("N", false);
        }
        else if (cmd == INPUT_P || cmd == INPUT_UP) {
            rc = SendCommandToMSXPi("P", false);
        }
        else {
            {
                char selcmd[48];
                buildSelection(selcmd, userNumber);
                rc = SendCommandToMSXPi(selcmd, false);
            }
            if (rc != RC_SUCCESS)
                break;

            Cls();

            RomHeader romHeader;
            char romRejectReason[ROM_REASON_MAX];
            rc = readRomHeader(&romHeader, romRejectReason, sizeof(romRejectReason));
            if (rc != RC_SUCCESS) {
                Print("Error reading ROM header\n");
                sendQuit();
                return 1;
            }
            if (romHeader.mapperType == MAPPER_REJECTED) {
                Print(romRejectReason);
                Print("\n");
                sendQuit();
                return 1;
            }
            if (romHeader.mapperType == MAPPER_PLAIN) {
                if (romHeader.totalSize > 0x8000) {
                    Print("ROM too large for plain loading\n");
                    sendQuit();
                    return 1;
                }
                rc = loadrom((uint16_t)romHeader.totalSize);
            }
            else if (romHeader.mapperType == MAPPER_KONAMI ||
                     romHeader.mapperType == MAPPER_ASCII8 ||
                     romHeader.mapperType == MAPPER_ASCII16) {
                rc = loadMappedRom(&romHeader);
            }
            else {
                pprintf("Mapper type not yet supported: ", romHeader.mapperType);
                sendQuit();
                return 1;
            }

            if (rc != RC_SUCCESS) {
                pprintf("Error loading the rom: ", rc);
                return 1;
            }
            else {
                launchGame();
            }
        }

        if (rc != RC_SUCCESS)
            break;
    }
    sendQuit();
    return 0;
}