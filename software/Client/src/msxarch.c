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
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/rammapper.h"
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

static bool StartsWith(const char* text, const char* prefix) {
    while (*prefix) {
        if (*text != *prefix)
            return false;
        text++;
        prefix++;
    }
    return true;
}

static bool IsArchiveError(const char* message) {
    return StartsWith(message, "Pi:Error - ") ||
           StartsWith(message, "Failed to list directory:");
}

static void ShowArchiveError(const char* message) {
    Cls();
    Print("MSX Archive error\n");
    Print("=================\n\n");
    if (StartsWith(message, "Pi:Error - ")) {
        Print(message + 11);
    } else if (StartsWith(message, "Failed to list directory:")) {
        Print("Cannot open archive directory.\n");
        Print("File or directory does not exist.");
    } else {
        Print(message);
    }
    Print("\n\nPress any key to return to the URL list.");
    WaitForKey();
    Cls();
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

// msxarch.ini may also hold settings, one per line as name=value. They are
// not repositories and are left out of the menu.
//     rebootAfterRomLoad=yes   ask the Pi to shut down once a game is loaded
static bool rebootAfterRomLoad;

static char lowerChar(char c) {
    return (c >= 'A' && c <= 'Z') ? (char)(c + ('a' - 'A')) : c;
}

// If line is "name=value" for the given lower-case name, return the value,
// else NULL. Case-insensitive; spaces around '=' are allowed.
static const char* iniSetting(const char* line, const char* name) {
    while (*name) {
        if (lowerChar(*line) != *name) return NULL;
        line++; name++;
    }
    while (*line == ' ') line++;
    if (*line != '=') return NULL;
    line++;
    while (*line == ' ') line++;
    return line;
}

static bool iniYes(const char* value) {
    return lowerChar(value[0]) == 'y' && lowerChar(value[1]) == 'e' &&
           lowerChar(value[2]) == 's' &&
           (value[3] == '\0' || value[3] == ' ' || value[3] == '\t');
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
            const char* value;
            repoList[count][col] = '\0';
            value = iniSetting(repoList[count], "rebootafterromload");
            if (value != NULL) {
                rebootAfterRomLoad = iniYes(value);
            }
            else if (col > 0 && repoList[count][0] != ';' && repoList[count][0] != '#') {
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

// Transfer progress bar, on the cursor line:
//     [##########..........................]
// The block count is known before the transfer from the ROM header, so the
// bar has a fixed width whatever the ROM size. It is drawn once through the
// BIOS; each fill cell then sets the text VRAM address directly and writes
// one '#' through port 98h. That avoids BIOS calls in the transfer loop and
// does not rely on the VDP address surviving interrupts or transfer code.
#define CSRY    0xF3DC      // cursor row, 1-based
#define LINLEN  0xF3B0      // current text width

static uint16_t progTotal;      // blocks expected
static uint16_t progDone;       // blocks received
static uint8_t  progRow;
static uint8_t  progWidth;      // bar cells
static uint8_t  progCells;      // cells filled

static void progressPut(uint8_t col, char ch) {
    uint16_t addr = (uint16_t)progRow * (*(uint8_t*)LINLEN) + col;

    __critical {
        OutPort(0x99, (uint8_t)(addr & 0xFF));
        OutPort(0x99, (uint8_t)(((addr >> 8) & 0x3F) | 0x40));
        OutPort(0x98, ch);
    }
}

static void progressStart(uint16_t totalBlocks) {
    uint8_t i;
    progTotal = totalBlocks ? totalBlocks : 1;
    progDone  = 0;
    progCells = 0;
    progWidth = (*(uint8_t*)LINLEN > 40) ? 60 : 28;
    progRow   = *(uint8_t*)CSRY - 1;
    PrintChar('[');
    for (i = 0; i < progWidth; i++)
        PrintChar('.');
    PrintChar(']');
    Locate(0, progRow);
    PrintChar('[');
}

static void progressDot(void) {
    uint8_t cells;
    if (progDone < progTotal)
        progDone++;
    // progDone * 60 stays within 16 bits up to 1092 blocks (8.7MB).
    cells = (uint8_t)((progDone * progWidth) / progTotal);
    while (progCells < cells) {
        progressPut(progCells + 1, '#');
        progCells++;
    }
}

// Put the cursor on the line below the bar, so later messages do not
// overwrite it.
static void progressEnd(void) {
    Locate(0, progRow + 1);
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
            rc = RECVDATA_ONEBLOCK(romaddress, &block_size, block_size);
            progressDot();
            romaddress += block_size;
            if (rc != RC_READY)
                break;
        }
    }
    progressEnd();

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
#define PAIR_CACHE0_ENTRIES  8    // page 1 cache entries, see ascii8Handlers
#define PAIR_CACHE1_ENTRIES  16   // page 2 cache entries, ends at RESIDENT_8K_DISPATCH_ADDR
#define PAIR_CACHE_MAX_ENTRIES PAIR_CACHE1_ENTRIES
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
static uint8_t pairCacheCounts[2];
static uint8_t pairCacheSegments[2][PAIR_CACHE_MAX_ENTRIES];

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

    // Pair caches for the 8K handlers: the exec segment is entry 0. Page 2 gets
    // the larger cache because Konami games commonly keep music/code in one
    // 8K half while screen transitions swap the other.
    pairCacheCounts[0] = 1;
    pairCacheCounts[1] = 1;
    pairCacheSegments[0][0] = execSegment1;
    pairCacheSegments[1][0] = execSegment2;
    while (pairCacheCounts[1] < PAIR_CACHE1_ENTRIES) {
        uint8_t s;
        if (takeSegment(&s) != RC_SUCCESS) break;
        pairCacheSegments[1][pairCacheCounts[1]++] = s;
    }
    while (pairCacheCounts[0] < PAIR_CACHE0_ENTRIES) {
        uint8_t s;
        if (takeSegment(&s) != RC_SUCCESS) break;
        pairCacheSegments[0][pairCacheCounts[0]++] = s;
    }
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
        progressDot();

        if (mapperLoadRc != RC_READY && mapperLoadRc != RC_SUCCESS) return RC_FAILED;
        if (mapperReceivedSize == 0) return RC_FAILED;
    }

    PutPN_direct(2, execSegment2);
    return RC_SUCCESS;
}

static uint8_t drainMappedRomBody(uint16_t bankCount, uint8_t bankSizeKB) {
    uint16_t chunks = bankCount * (uint16_t)(bankSizeKB / 8);
    uint16_t received;
    uint8_t rc;
    uint16_t c;

    rc = PerformHandshake(MAXBUFSIZE);
    if (rc != RC_SUCCESS) return RC_FAILED;

    for (c = 0; c < chunks; c++) {
        received = MAXBUFSIZE;
        rc = RECVDATA_ONEBLOCK((uint8_t*)BUFADDRESS, &received, MAXBUFSIZE);
        progressDot();
        if (rc != RC_READY && rc != RC_SUCCESS) return RC_FAILED;
        if (received == 0) return RC_FAILED;
    }
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
#define RESIDENT_TABLE_ENTRIES 0x40   // F975-F9B4, indexed by AND 3Fh
// 8K windows: the bank currently in each window (W1..W4), then one record per
// 16K page: current segment, next cache victim, cache entries in use.
#define RESIDENT_CUR_ADDR     0xF9B5
#define RESIDENT_PG0_ADDR     0xF9B9  // page 1 (4000h-7FFFh), port FDh
#define RESIDENT_PG1_ADDR     0xF9BC  // page 2 (8000h-BFFFh), port FEh
// Four 5-byte entry stubs followed by the shared switch routine. The code is
// D0h bytes and only that much is copied, because the pair caches follow it:
// grow RESIDENT_8K_SIZE (and move the caches) if ascii8Handlers grows.
#define RESIDENT_8K_BASE      0xF9C0
#define RESIDENT_8K_WIN1_ADDR 0xF9C0
#define RESIDENT_8K_WIN2_ADDR 0xF9C5
#define RESIDENT_8K_WIN3_ADDR 0xF9CA
#define RESIDENT_8K_WIN4_ADDR 0xF9CF
#define RESIDENT_8K_SIZE      0xD0
// Pair caches, (bank lo, bank hi, segment). Page 1 uses FA90-FAA7, page 2 uses
// FAA8-FAD7. That reaches into the 16K handlers' space, which an 8K game never
// uses, and ends below the MSX2 system variables at FAF5h.
#define RESIDENT_CACHE0_ADDR  0xFA90
#define RESIDENT_CACHE1_ADDR  0xFAA8
// Window dispatcher for games that pick the register at run time, after the
// page-2 cache (FAA8h + 16 x 3 = FAD8h). The 16K handlers also start at FAD8h,
// but a game loads either those or the 8K ones, never both.
#define RESIDENT_8K_DISPATCH_ADDR 0xFAD8
#define RESIDENT_8K_DISPATCH_SIZE 16

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
    // The seventh address is new: a server that knows only six ignores it.
    static const uint16_t addr[7] = {
        RESIDENT_8K_WIN1_ADDR, RESIDENT_8K_WIN2_ADDR,
        RESIDENT_8K_WIN3_ADDR, RESIDENT_8K_WIN4_ADDR,
        RESIDENT_PAGE1_ADDR,   RESIDENT_PAGE2_ADDR,
        RESIDENT_8K_DISPATCH_ADDR
    };
    uint8_t i = 0, j;
    while (number[i]) { out[i] = number[i]; i++; }
    for (j = 0; j < 7; j++) {
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
// A cartridge switches an 8K window with one latch write. These handlers used
// to copy 8KB (~45ms) on every switch, which is harmless for a game that
// switches rarely and ruinous for one that switches all the time: NEMESIS's
// interrupt music driver pages its banks in and out of 8000h/A000h 18 times a
// second, so the title music and everything else crawled.
//
// A 16K page is fully determined by the pair of banks in its two windows, and
// games reuse very few pairs. So each page keeps a small cache of mapper
// segments already holding a (lo, hi) pair: the first use of a pair costs two
// 8KB copies, and every later switch to it is a single OUT, as on the
// cartridge. Victims rotate; with a pool of one segment this degrades to the
// old copy-on-every-switch behaviour.
//
// The cache must hold a game's whole working set, or rotation evicts pairs
// that are needed again at once and every switch copies. NEMESIS cycles through
// 10 page-2 pairs, transients included - (02,06) (02,03) (07,03) (02,08)
// (0B,03) (0B,0C) (02,0C) (07,08) (05,03) (05,06) - so 8 entries missed on
// every pass and the music still ran at 2.7 steps a second against the
// cartridge's 60. Hence PAIR_CACHE_ENTRIES 12.
//
// Entry: D = window 0-3, E = bank. Jumps to that window's handler entry
// (RESIDENT_8K_BASE + 5 x window, each entry being push hl / ld l,n / jr) with
// A = bank and HL restored, so the handler returns straight to the game.
// HYDLIDE3.ROM selects windows through one routine,
//     ld a,d / add a,a / add a,a / add a,a / add a,60h / ld h,a / di / ld (hl),e
// which no LD (nn),A patch can reach; msxpi-server turns its first nine bytes
// into di / call here. A and flags are not preserved - that routine reloads
// both. COPIED to RESIDENT_8K_DISPATCH_ADDR: no absolute jumps.
void ascii8Dispatch(void) __naked {
    __asm
        push hl
        ld a, d
        and #3
        ld l, a
        add a, a
        add a, a
        add a, l                ; 5 x window
        add a, #0xC0            ; low byte of RESIDENT_8K_BASE
        ld l, a
        ld h, #0xF9             ; high byte of RESIDENT_8K_BASE
        ld a, e
        ex (sp), hl             ; restore HL, push the handler entry
        ret
    __endasm;
}

// Entry: A = bank, return address on the stack; all registers preserved.
// This block is COPIED to RESIDENT_8K_BASE, so every jump must be relative.
void ascii8Handlers(void) __naked {
    __asm
        push hl                 ; W1
        ld l, #0
        jr 1$
        push hl                 ; W2
        ld l, #1
        jr 1$
        push hl                 ; W3
        ld l, #2
        jr 1$
        push hl                 ; W4
        ld l, #3
    1$:
        push af
        push bc
        push de
        push ix
        ld c, l                 ; C = window 0-3
        ld e, a                 ; E = bank
        ld b, #0
        ld hl, #RESIDENT_CUR_ADDR
        add hl, bc
        ld a, (hl)
        cp e
        jr nz, 10$
        ; Same bank again - a mapper ignores that. Exits here rather than
        ; at 99$, which is out of JR range from this point.
        pop ix
        pop de
        pop bc
        pop af
        pop hl
        ret
    10$:
        ld (hl), e
        ld a, i                 ; P/V = IFF2, interrupt state of the caller
        push af
        di
        ld a, c
        and #2
        ld c, a                 ; C = 0 (page 1) or 2 (page 2)
        ld hl, #RESIDENT_CUR_ADDR
        add hl, bc
        ld d, (hl)              ; D = bank in the low window of the page
        inc hl
        ld e, (hl)              ; E = bank in the high window of the page
        ld ix, #RESIDENT_PG0_ADDR
        ld hl, #RESIDENT_CACHE0_ADDR
        bit 1, c
        jr z, 2$
        ld ix, #RESIDENT_PG1_ADDR
        ld hl, #RESIDENT_CACHE1_ADDR
    2$:
        ld b, 2 (ix)            ; entries in the cache of this page
    3$:
        ld a, (hl)
        cp d
        jr nz, 4$
        inc hl
        ld a, (hl)
        dec hl
        cp e
        jr nz, 4$
        inc hl
        inc hl
        ld a, (hl)              ; segment already holding (lo, hi)
        ld 0 (ix), a
        jr 7$
    4$:
        inc hl
        inc hl
        inc hl
        djnz 3$
        ; Miss: take the next victim entry and fill its segment.
        ld a, 1 (ix)
        ld l, a
        add a, a
        add a, l                ; A = victim * 3
        ld hl, #RESIDENT_CACHE0_ADDR
        bit 1, c
        jr z, 5$
        ld hl, #RESIDENT_CACHE1_ADDR
    5$:
        ld c, a
        add hl, bc              ; B is 0 after the djnz
        ld a, 1 (ix)
        inc a
        cp 2 (ix)
        jr c, 6$
        xor a
    6$:
        ld 1 (ix), a
        ld (hl), d
        inc hl
        ld (hl), e
        inc hl
        ld a, (hl)              ; segment of the victim entry
        ld 0 (ix), a
        out (#0xFE), a          ; build it at 8000h
        push de
        ld hl, #0x8000
        ld a, d
    8$:
        push hl                 ; destination half
        rrca                    ; carry = half of the storage segment
        ld de, #0x4000
        jr nc, 9$
        ld d, #0x60
    9$:
        ; RRCA above made A the segment index (bank >> 1) and carry the half.
        ; AND 3Fh bounds it to the 64-entry table: unmasked, a bank number
        ; larger than the ROM indexed past the table into whatever DOS left
        ; there - NEMESIS does this on its first switch, ld a,(F0F2h) with
        ; F0F2h uninitialised. The table is 64 bytes at F975, so the low byte
        ; 75h + 3Fh = B4h cannot carry.
        and #0x3F
        add a, #(RESIDENT_TABLE_ADDR & 0xFF)
        ld l, a
        ld h, #(RESIDENT_TABLE_ADDR >> 8)
        ld a, (hl)
        out (#0xFD), a          ; storage segment at 4000h
        ex de, hl
        pop de
        ld bc, #0x2000
        ldir
        ex de, hl               ; HL = A000h after the low half, C000h after both
        pop de
        push de
        ld a, e
        bit 6, h
        jr z, 8$
        pop de
        ; Acknowledge the VDP interrupt that went pending during the copies,
        ; or a switch made from the interrupt routine nests the next one.
        in a, (#0x99)
    7$:
        ld a, (#RESIDENT_PG0_ADDR)
        out (#0xFD), a
        ld a, (#RESIDENT_PG1_ADDR)
        out (#0xFE), a
        ; This code is COPIED into RAM, so every jump must be relative: a jp po
        ; assembles to the link-time address inside the msxarch.com image,
        ; which the BIOS covers once the game runs. JR has no P/O condition,
        ; so test bit 2 (P/V) of the F saved by ld a,i instead.
        pop hl                  ; H = A, L = F from the ld a,i snapshot
        bit 2, l
        jr z, 99$
        ei
    99$:
        pop ix
        pop de
        pop bc
        pop af
        pop hl
        ret
    __endasm;
}

static void relocateResidentHandlers8K(uint16_t storageCount) {
    uint16_t i;
    uint8_t p, e;
    uint8_t* table = (uint8_t*)RESIDENT_TABLE_ADDR;
    uint8_t* cur = (uint8_t*)RESIDENT_CUR_ADDR;
    uint8_t* pg[2];
    uint8_t* cache[2];
    uint8_t* src = (uint8_t*)ascii8Handlers;
    uint8_t* dst = (uint8_t*)RESIDENT_8K_BASE;

    pg[0] = (uint8_t*)RESIDENT_PG0_ADDR;
    pg[1] = (uint8_t*)RESIDENT_PG1_ADDR;
    cache[0] = (uint8_t*)RESIDENT_CACHE0_ADDR;
    cache[1] = (uint8_t*)RESIDENT_CACHE1_ADDR;

    // Fill all 64 entries, mirroring the ROM the way the cartridge hardware
    // does, instead of only the first storageCount. Combined with the AND 3Fh
    // in the handlers this makes every reachable index resolve to a real
    // segment: for a power-of-two ROM, table[(bank & 3Fh) % storageCount] is
    // exactly the segment the mapper would have selected.
    for (i = 0; i < RESIDENT_TABLE_ENTRIES; i++)
        table[i] = storageSegments[i % storageCount];

    // konamiInitialSetup/ascii8InitialSetup load banks 0..3 into windows 1..4
    // of the exec segments, so those are the current banks and each page's
    // first cache entry; the other entries hold no pair yet.
    for (i = 0; i < 4; i++) cur[i] = (uint8_t)i;
    for (p = 0; p < 2; p++) {
        uint8_t count = pairCacheCounts[p];
        uint8_t maxEntries = p ? PAIR_CACHE1_ENTRIES : PAIR_CACHE0_ENTRIES;
        pg[p][0] = pairCacheSegments[p][0];
        pg[p][1] = count > 1 ? 1 : 0;
        pg[p][2] = count;
        cache[p][0] = (uint8_t)(p * 2);
        cache[p][1] = (uint8_t)(p * 2 + 1);
        cache[p][2] = pairCacheSegments[p][0];
        for (e = 1; e < maxEntries; e++) {
            cache[p][e * 3]     = 0xFF;
            cache[p][e * 3 + 1] = 0xFF;
            cache[p][e * 3 + 2] = pairCacheSegments[p][e];
        }
    }

    for (i = 0; i < RESIDENT_8K_SIZE; i++) dst[i] = src[i];

    src = (uint8_t*)ascii8Dispatch;
    dst = (uint8_t*)RESIDENT_8K_DISPATCH_ADDR;
    for (i = 0; i < RESIDENT_8K_DISPATCH_SIZE; i++) dst[i] = src[i];
}

static void prewarmKonami16PairCache(void) {
    uint8_t e, b;
    uint8_t* cache;

    cache = (uint8_t*)RESIDENT_CACHE1_ADDR;
    for (e = 1, b = 0; e < pairCacheCounts[1]; b++) {
        if (b == 2) b = 4;
        if (b == 16) b = 3;
        if (b >= 16 && b != 3) break;
        PutPN_direct(2, pairCacheSegments[1][e]);
        mapperCopyBank(b, 0, 1, 2);
        mapperCopyBank(3, BANK_HALF_SIZE, 1, 2);
        cache[e * 3] = b;
        cache[e * 3 + 1] = 3;
        cache[e * 3 + 2] = pairCacheSegments[1][e];
        e++;
        if (b == 3) break;
    }
    ((uint8_t*)RESIDENT_PG1_ADDR)[1] = e < pairCacheCounts[1] ? e : 1;

    PutPN_direct(1, execSegment1);
    PutPN_direct(2, execSegment2);
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
        pprintf("Too large: ", storageCount); Print(" seg\n");
        drainMappedRomBody(hdr->bankCount, hdr->bankSizeKB);
        progressEnd();
        return RC_FAILED;
    }

    rc = allocateMapperSegments((uint8_t)storageCount);
    if (rc != RC_SUCCESS) {
        drainMappedRomBody(hdr->bankCount, hdr->bankSizeKB);
        progressEnd();
        return rc;
    }

    rc = loadBanksIntoStorage(hdr->bankCount, hdr->bankSizeKB);
    progressEnd();
    if (rc != RC_SUCCESS) {
        Print("Error loading ROM banks\n");
        freeMapperSegments(storageCount);
        return rc;
    }
    Print("Cache...\n");

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
        if (hdr->bankCount == 16) prewarmKonami16PairCache();
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

        ; Some cartridges only install a hook in INIT and return to the BIOS,
        ; which starts them later through H.STKE once BASIC has initialised.
        ; PENNANT.ROM does ld (0FEDAh),F7h slot / ld (0FEDCh),4102h / ret, and
        ; VALLEY2.ROM the same with 40B5h. With nothing to return to, INIT
        ; returned into garbage: PENNANT rebooted to DOS, VALLEY2 hung in the
        ; BIOS. So INIT returns to 5$ below, inside this copied block at C000h.
        ld hl, #(0xC000 + 5$ - 1$)
        push hl

        ; Read entry vector from Page 1 (0x4002) and jump with DI
        ld hl, (#0x4002)
        jp (hl)

    5$:
        ; INIT returned. Start the game the way the BIOS would, through the
        ; H.STKE hook it installed; its slot is the one already selected, so
        ; jump straight to the address in the hook.
        di
        ld a, (#0xFEDA)
        cp #0xF7
        jr nz, 6$
        ld hl, (#0xFEDC)
        jp (hl)
    6$:
        ; No H.STKE hook: nothing to start. Idle with interrupts on rather than
        ; running into whatever follows.
        ei
        jr 6$

    2$:
    __endasm;
}

int main(void) {
	Screen(0);
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

    while (1) {
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
        bool returnToMenu = false;

        while (1) {
            rc = RECVDATA(buffer, &replySize, &maxbuf);

            if (rc != RC_SUCCESS) {
                buffer[(replySize < size) ? replySize : size - 1] = '\0';
                if (IsArchiveError((const char*)buffer)) {
                    ShowArchiveError((const char*)buffer);
                } else {
                    ShowArchiveError("Unable to read the archive list.");
                }
                sendQuit();
                returnToMenu = true;
                break;
            }
            buffer[size - 1] = '\0';
            if (IsArchiveError((const char*)buffer)) {
                ShowArchiveError((const char*)buffer);
                sendQuit();
                returnToMenu = true;
                break;
            }

            Locate(0, 1);
            Print("================================================================================");
            Locate(0, 2);
            FastPrint(buffer);
            Locate(0, 0);
            Print("     Q = Quit  N/Down = Next Page  P/Up = Previous Page or Game Number to load");

            Locate(0, 0);
            cmd = GetValidInput(userNumber);
            if (cmd == INPUT_Q) {
                returnToMenu = true;
                break;
            }
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
                // For an accepted ROM the text after the header is the game's
                // name (an older server sends none, which prints just "Loading").
                Print("Loading ");
                Print(romRejectReason);
                pprintf("  (", (uint16_t)((romHeader.totalSize + 1023) >> 10));
                Print("K)\n");
                // Blocks are always 8KB - see loadrom and loadBanksIntoStorage.
                if (romHeader.mapperType == MAPPER_PLAIN)
                    progressStart((uint16_t)((romHeader.totalSize + 8191) >> 13));
                else
                    progressStart(romHeader.bankCount *
                                  (uint16_t)(romHeader.bankSizeKB / 8));
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
                    // msxarch.ini rebootAfterRomLoad=yes. The game is fully in RAM
                    // and needs nothing more from the Pi. Use the no-reply form so
                    // the launch path does not perform another receive/print after
                    // the ROM image has already been staged.
                    if (rebootAfterRomLoad) {
                        SendCommandToMSXPi("shut nowait", false);
                    }
                    launchGame();
                }
            }

            if (rc != RC_SUCCESS)
                break;
        }
        sendQuit();
        if (!returnToMenu)
            return 0;
        Cls();
    }
}
