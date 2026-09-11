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
    uint16_t block_size = 16384;
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

static uint8_t allocateMapperSegments(uint8_t storageCount) {
    SEGMENTSTATUS* status;
    uint8_t i;

    // Allocate Page 1 Exec Segment
    status = AllocateSegment(0, 0);
    if (status->carryFlag) return RC_FAILED;
    execSegment1 = status->allocatedSegmentNumber;

    // Allocate Page 2 Exec Segment
    status = AllocateSegment(0, 0);
    if (status->carryFlag) {
        FreeSegment(execSegment1, 0);
        return RC_FAILED;
    }
    execSegment2 = status->allocatedSegmentNumber;

    // Allocate ROM Storage Segments
    for (i = 0; i < storageCount; i++) {
        status = AllocateSegment(0, 0);
        if (status->carryFlag) {
            uint8_t j;
            for (j = 0; j < i; j++) FreeSegment(storageSegments[j], 0);
            FreeSegment(execSegment1, 0);
            FreeSegment(execSegment2, 0);
            return RC_FAILED;
        }
        storageSegments[i] = status->allocatedSegmentNumber;
    }

    // Allocate Safe-Zone Segment
    status = AllocateSegment(0, 0);
    if (status->carryFlag) {
        for (i = 0; i < storageCount; i++) FreeSegment(storageSegments[i], 0);
        FreeSegment(execSegment1, 0);
        FreeSegment(execSegment2, 0);
        return RC_FAILED;
    }
    safeZoneSegment = status->allocatedSegmentNumber;

    return RC_SUCCESS;
}

static void freeMapperSegments(uint16_t storageCount) {
    uint16_t i;
    for (i = 0; i < storageCount; i++) FreeSegment(storageSegments[i], 0);
    FreeSegment(execSegment1, 0);
    FreeSegment(execSegment2, 0);
    FreeSegment(safeZoneSegment, 0);
}

static void PutPN_direct(uint8_t page, uint8_t segment) {
    OutPort(0xFC + page, segment);
}

static void enterSafeZone(void) {
    PutPN_direct(2, safeZoneSegment);
}

static uint8_t loadBanksIntoStorage(uint16_t bankCount, uint8_t bankSizeKB) {
    mapperBankCount = bankCount;
    mapperBankSizeKB = bankSizeKB;
    mapperBlockSize = (mapperBankSizeKB == 16) ? 16384 : 8192;

    for (mapperBankIndex = 0; mapperBankIndex < mapperBankCount; mapperBankIndex++) {
        mapperCurrentSegment = storageSegments[mapperBankSizeKB == 8 ? (mapperBankIndex >> 1) : mapperBankIndex];
        mapperCurrentOffset = (mapperBankSizeKB == 8 && (mapperBankIndex & 1)) ? BANK_HALF_SIZE : 0;
        mapperReceivedSize = mapperBlockSize;

        // Signal server to send next bank if server requires per-bank trigger
        // SendCommandToMSXPi("R", false); 

        PutPN_direct(2, mapperCurrentSegment);
        mapperLoadRc = RECVDATA_ONEBLOCK(PAGE2ADDRESS + mapperCurrentOffset, &mapperReceivedSize, mapperBlockSize);

        // Fail if no data was returned by MSXPi
        if (mapperLoadRc != RC_READY && mapperLoadRc != RC_SUCCESS) return RC_FAILED;
        if (mapperReceivedSize == 0) return RC_FAILED;
    }

    PutPN_direct(2, execSegment2);
    return RC_SUCCESS;
}

static void patchWindow(uint8_t* base, uint16_t targetAddr, void (*handler)(void)) {
    uint16_t i;
    uint16_t handlerAddr = (uint16_t)handler;
    for (i = 0; i < 0x4000 - 2; i++) {
        if (base[i] == 0x32) {
            uint16_t addr = (uint16_t)base[i + 1] | ((uint16_t)base[i + 2] << 8);
            if (addr == targetAddr) {
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
#define RESIDENT_PAGE1_ADDR   0xE000
#define RESIDENT_PAGE2_ADDR   0xE040
#define RESIDENT_TABLE_ADDR   0xE080
#define RESIDENT_EXEC1_ADDR   0xE0F0
#define RESIDENT_EXEC2_ADDR   0xE0F1
#define RESIDENT_8K_WIN1_ADDR 0xE100
#define RESIDENT_8K_WIN2_ADDR 0xE140
#define RESIDENT_8K_WIN3_ADDR 0xE180
#define RESIDENT_8K_WIN4_ADDR 0xE1C0
#define RESIDENT_SLOT_SIZE    0x40

// --- ASCII16 Resident Handlers ---
void ascii16Page1Handler(void) __naked {
    __asm
        push af
        push hl
        push bc
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

    for (i = 0; i < storageCount; i++) table[i] = storageSegments[i];
    for (i = 0; i < RESIDENT_SLOT_SIZE; i++) dst1[i] = src1[i];
    for (i = 0; i < RESIDENT_SLOT_SIZE; i++) dst2[i] = src2[i];
}

static void patchAllStorageSegmentsAscii16(uint16_t segmentCount) {
    uint16_t s;
    for (s = 0; s < segmentCount; s++) {
        PutPN_direct(1, storageSegments[s]);
        patchWindow(PAGE1ADDRESS, 0x6000, (void (*)(void))RESIDENT_PAGE1_ADDR);
        patchWindow(PAGE1ADDRESS, 0x7000, (void (*)(void))RESIDENT_PAGE2_ADDR);
    }
}

// --- Konami & ASCII8 8K Resident Handlers ---
void ascii8Win1Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        di
        ld c, a
        srl a
        ld e, a
        ld d, #0
        ld hl, #RESIDENT_TABLE_ADDR
        add hl, de
        ld a, (hl)
        out (#0xFE), a
        bit 0, c
        jr z, 1$
        ld hl, #0xA000
        jr 2$
    1$:
        ld hl, #0x8000
    2$:
        ld de, #0x4000
        ld bc, #0x2000
        ldir
        ld a, (#RESIDENT_EXEC2_ADDR)
        out (#0xFE), a
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

void ascii8Win2Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        di
        ld c, a
        srl a
        ld e, a
        ld d, #0
        ld hl, #RESIDENT_TABLE_ADDR
        add hl, de
        ld a, (hl)
        out (#0xFE), a
        bit 0, c
        jr z, 1$
        ld hl, #0xA000
        jr 2$
    1$:
        ld hl, #0x8000
    2$:
        ld de, #0x6000
        ld bc, #0x2000
        ldir
        ld a, (#RESIDENT_EXEC2_ADDR)
        out (#0xFE), a
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

void ascii8Win3Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        di
        ld c, a
        srl a
        ld e, a
        ld d, #0
        ld hl, #RESIDENT_TABLE_ADDR
        add hl, de
        ld a, (hl)
        out (#0xFD), a
        bit 0, c
        jr z, 1$
        ld hl, #0x6000
        jr 2$
    1$:
        ld hl, #0x4000
    2$:
        ld de, #0x8000
        ld bc, #0x2000
        ldir
        ld a, (#RESIDENT_EXEC1_ADDR)
        out (#0xFD), a
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

void ascii8Win4Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        di
        ld c, a
        srl a
        ld e, a
        ld d, #0
        ld hl, #RESIDENT_TABLE_ADDR
        add hl, de
        ld a, (hl)
        out (#0xFD), a
        bit 0, c
        jr z, 1$
        ld hl, #0x6000
        jr 2$
    1$:
        ld hl, #0x4000
    2$:
        ld de, #0xA000
        ld bc, #0x2000
        ldir
        ld a, (#RESIDENT_EXEC1_ADDR)
        out (#0xFD), a
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

static void relocateResidentHandlers8K(uint16_t storageCount) {
    uint16_t i;
    uint8_t* table = (uint8_t*)RESIDENT_TABLE_ADDR;
    uint8_t* exec1 = (uint8_t*)RESIDENT_EXEC1_ADDR;
    uint8_t* exec2 = (uint8_t*)RESIDENT_EXEC2_ADDR;

    for (i = 0; i < storageCount; i++) table[i] = storageSegments[i];
    *exec1 = execSegment1;
    *exec2 = execSegment2;

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
        patchWindow(PAGE1ADDRESS, 0x6000, (void (*)(void))RESIDENT_8K_WIN2_ADDR);
        patchWindow(PAGE1ADDRESS, 0x8000, (void (*)(void))RESIDENT_8K_WIN3_ADDR);
        patchWindow(PAGE1ADDRESS, 0xA000, (void (*)(void))RESIDENT_8K_WIN4_ADDR);
    }
}

static void patchAllStorageSegmentsAscii8(uint16_t segmentCount) {
    uint16_t s;
    for (s = 0; s < segmentCount; s++) {
        PutPN_direct(1, storageSegments[s]);
        patchWindow(PAGE1ADDRESS, 0x6000, (void (*)(void))RESIDENT_8K_WIN1_ADDR);
        patchWindow(PAGE1ADDRESS, 0x6800, (void (*)(void))RESIDENT_8K_WIN2_ADDR);
        patchWindow(PAGE1ADDRESS, 0x7000, (void (*)(void))RESIDENT_8K_WIN3_ADDR);
        patchWindow(PAGE1ADDRESS, 0x7800, (void (*)(void))RESIDENT_8K_WIN4_ADDR);
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

    if (hdr->mapperType == MAPPER_ASCII16) {
        relocateResidentHandlers16K(storageCount);
        patchAllStorageSegmentsAscii16(storageCount);
        PutPN_direct(1, storageSegments[0]);
        PutPN_direct(2, storageSegments[hdr->bankCount > 1 ? 1 : 0]);
    } else if (hdr->mapperType == MAPPER_KONAMI) {
        relocateResidentHandlers8K(storageCount);
        patchAllStorageSegmentsKonami(storageCount);
        konamiInitialSetup(hdr->bankCount);
    } else if (hdr->mapperType == MAPPER_ASCII8) {
        relocateResidentHandlers8K(storageCount);
        patchAllStorageSegmentsAscii8(storageCount);
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
            rc = SendCommandToMSXPi(userNumber, false);
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