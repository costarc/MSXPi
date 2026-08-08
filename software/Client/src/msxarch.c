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
#define KEY_ENTER 0x0D    // ASCII code for Enter/Return

// Return codes
#define INPUT_NONE   0
#define INPUT_P      1
#define INPUT_N      2
#define INPUT_Q      3      
#define INPUT_UP     4
#define INPUT_DOWN   5
#define INPUT_NUMBER 6

// Galaga
#define ROM_BASE   0x4000
#define BANK_SIZE  0x2000   // 8K
#define NUM_BANKS  4        // Galaga = 32K

// ROM header sent by the server immediately before the ROM image, so the
// client knows how to load it. Mirrors build_rom_header() in msxpi-server.py.
#define ROM_HEADER_MAGIC    0x52   // 'R'
#define ROM_HEADER_SIZE     16
#define ROM_REASON_MAX      144    // max reject-reason text length, incl. null terminator
#define ROM_MSG_MAX         (ROM_HEADER_SIZE + ROM_REASON_MAX)
#define MAPPER_PLAIN        0      // linear ROM, loaded exactly as today
#define MAPPER_KONAMI       1      // 8K banks (not yet implemented)
#define MAPPER_ASCII8       2      // 8K banks (not yet implemented)
#define MAPPER_ASCII16      3      // 16K banks (not yet implemented)
#define MAPPER_REJECTED     0xFF   // selection rejected; reason text follows the header, no ROM body

typedef struct {
    uint8_t  mapperType;
    uint8_t  bankSizeKB;
    uint16_t bankCount;
    uint32_t totalSize;
} RomHeader;

// Reads the fixed-size ROM header the server sends immediately after a ROM
// selection. For MAPPER_REJECTED, the header is followed by a short reason
// string instead of a ROM body; it's copied into reason (if given).
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

/*
// Konami-8 Bank Switcher
void konami8k_setbank(uint8_t bank)
{
    if (bank >= NUM_BANKS)
        bank &= (NUM_BANKS - 1);   // safety wrap

    uint8_t* dst = (uint8_t*)ROM_BASE;
    uint8_t* src = rom_buffer + (bank * BANK_SIZE);

    memcpy(dst, src, BANK_SIZE);
}

// HHandle the Bank Swith calls
void konami8k_handler(void) __naked
{
    __asm
    ; A contains the bank number
        push af

        ; Save registers we touch
        push hl
        push de
        push bc

        ; Convert A to index and call C function
        ld l, a
        ld h, 0
        push hl
        call _konami8k_setbank
        pop hl

        ; Restore registers
        pop bc
        pop de
        pop hl
        pop af

        ret
        __endasm;
}

// Patch routine - 
// void patch_konami8k(uint8_t* rom, uint16_t size)
{
    for (uint16_t i = 0; i < size - 3; i++)
    {
        // Look for: ld (6000h),a  →  32 00 60
        if (rom[i] == 0x32 && rom[i + 1] == 0x00 && rom[i + 2] == 0x60)
        {
            // Replace with: call konami8k_handler
            rom[i] = 0xCD;                     // CALL nn
            rom[i + 1] = (uint16_t)konami8k_handler & 0xFF;
            rom[i + 2] = (uint16_t)konami8k_handler >> 8;

            // Optional: log it
            // pprintf("Patched mapper write at %u\n", i);
        }
    }
}

void start_galaga(void)
{
    // Patch ROM in buffer
    patch_konami8k(rom_buffer, 32768);

    // Load bank 0 into 0x4000
    konami8k_setbank(0);

    // Jump to entry point at 4002h
    __asm
    ld hl, (0x4002)
        jp(hl)
        __endasm;
}
*/
// outNumber will hold the 3-digit number if INPUT_NUMBER is returned
int GetValidInput(char* outNumber) {
    outNumber[0] = '\0';

    while (1) {
        unsigned char key = WaitForKey();
        Locate(0, 0);
        // PrintNumber(key);
        // Normalize to uppercase
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
            // Reads up to 3 digits, exits early if Enter pressed
            int count = 0;

            while (count < 3) {
                int count = 0;
                while (count < 3) {
                    outNumber[count++] = key;
                    PrintChar(key);

                    key = WaitForKey();
                    if (key == KEY_ENTER) break;
                    if (!IsDigit(key)) break;
                }
                outNumber[count] = '\0';  // null-terminate string

                return '0';   // signal that a number was entered

                // ignore non-digit keys
            }
        }
    }
}

// Function to display a menu and return the selected string
const unsigned char* showMenu(const unsigned char* options[], int count) {
    char choice;

    // Display menu
    Print("=== MENU ===\n");
    Print("!! msxarch is only a proof of concept, and can only load linear ROMs up to 32KB. Will not work with any memory-mapped game !!\n\n");
    for (int i = 0; i < count; i++) {
        PrintNumber(i + 1);
        Print(". "); Print(options[i]); Print("\n");   // print option text
    }

    // Read user choice
    choice = InputChar();
    int choiceNum = choice - '0';        // convert ASCII digit to int

    // Validate choice
    if (choiceNum < 1 || choiceNum > count) {
        Print("Choice out of range.\n");
        return "Q";
    }

    // Return selected string
    return options[choiceNum - 1];  // return string pointer
}

void sendQuit() {
    uint8_t rc = SendCommandToMSXPi("Q", false);
}

static FCB iniFcb;
static char iniBuffer[INI_BUFFER_SIZE];
static char repoList[MAX_REPOS][MAX_URL_LEN];

// Fills an FCB's name/ext fields (8.3 format) from a plain filename string
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

// Reads INI_FILENAME (one repository URL per line, blank lines and lines
// starting with ';' or '#' ignored) into repoList[]. Returns the number of
// URLs found, or 0 if the file is missing/empty so the caller can fall back
// to a built-in default.
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
        // Synthesize a trailing newline so the last line flushes even
        // when the file doesn't end with one.
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
        uint8_t* romaddress = PAGE0ADDRESS; // MSX address to load ROM
        while (1) {
            pprintf("Reading game block ", index++); pprintf(" (", block_size); pprints(")", "\n");
            rc = RECVDATA_ONEBLOCK(romaddress, &block_size, block_size);
            romaddress += block_size;
            if (rc != RC_READY)
                break;
        }
    }

    // Mirroring the loaded image across 0x8000-0xBFFF was tried here (some
    // 8K/16K cartridges do rely on that hardware mirroring behavior), but
    // it regressed Kung-Fu, which uses that window as its own working RAM.
    // Whether a given ROM wants mirroring is per-ROM metadata, not
    // something safe to assume for every sub-32K file - belongs in the
    // server-side mapper/metadata detection, not a blanket client rule.
    (void)totalSize;

    Print("Game loaded\n");
    return rc;
}

// ===========================================================================
// Mapper-aware ROM loading (Konami / ASCII8 / ASCII16)
// ===========================================================================
//
// Plain ROMs (<=32KB) are loaded directly into the fixed 0x4000-0xBFFF
// window by loadrom() above. Mapper ROMs are too big for that, so instead:
//   - All banks are streamed into dedicated 16K mapper RAM "storage"
//     segments (rammapper.h): 1 segment per bank for ASCII16 (16K banks),
//     2 banks packed per segment for Konami/ASCII8 (8K banks).
//   - Two further "exec" segments are Put_PN'd into CPU pages 1 and 2 for
//     the whole game session and hold the *visible* cartridge memory. For
//     ASCII16, a bank switch is a pure Put_PN of a storage segment into an
//     exec page - no copying, since 1 bank = 1 full 16K page.
//   - Konami/ASCII8 switch at 8K granularity, which a 16K Put_PN can't
//     represent (an exec page's two 8K halves generally belong to
//     unrelated banks). Those switches instead do a direct 8K memcpy: the
//     *other* exec page (not the switch's target) is briefly Put_PN'd to
//     the source storage segment to read from, then restored to its own
//     exec segment. Interrupts are disabled for that short window, since
//     the borrowed page briefly shows the wrong content.

#define MAX_STORAGE_SEGMENTS 64   // 64 x 16K = 1MB, matches the server's ROM_MAX_SIZE cap
#define BANK_HALF_SIZE 0x2000     // 8K

// Pinned to a fixed low address rather than left to normal _DATA placement:
// these are the only globals actively read/written *during* Put_PN calls
// (to pick the next segment, remember the exec segments, pass the bank
// number into the asm handler stubs), so they must never land at or past
// 0x4000 - the linker's automatic _DATA packing (which includes large,
// unrelated static buffers from other modules, e.g. msxpi-bios.c's 8K
// stdout buffer) was pushing them well past that boundary, corrupting
// them on the very first bank-select Put_PN. 0x3800 sits safely below
// 0x4000 with margin on both sides regardless of how the rest of the
// program grows.
static uint8_t __at(0x3800) storageSegments[MAX_STORAGE_SEGMENTS];
static uint8_t __at(0x3840) execSegment1;
static uint8_t __at(0x3841) execSegment2;
static uint8_t __at(0x3842) mapperBankParam;   // bank number the asm handler stubs pass in via A

// SDCC's non-reentrant model statically allocates *all* locals and
// parameters the same way it allocates globals - so a function's own
// locals (e.g. loadBanksIntoStorage's blockSize/receivedSize/loop
// variables) are just as exposed to landing past 0x4000 as the globals
// above were. Anything read or written during or after a Put_PN(1/2,...)
// call needs to live here instead of as an ordinary local/parameter.
static uint16_t __at(0x3843) mapperBlockSize;
static uint16_t __at(0x3845) mapperReceivedSize;
static uint16_t __at(0x3847) mapperBankIndex;
static uint8_t  __at(0x3849) mapperLoadRc;
static uint8_t  __at(0x384A) mapperCurrentSegment;
static uint16_t __at(0x384B) mapperCurrentOffset;
static uint16_t __at(0x384D) mapperBankCount;
static uint8_t  __at(0x384F) mapperBankSizeKB;
static uint8_t  __at(0x3850) mapperType;

// Dedicated mapper segment Put_PN'd into page 2 (0x8000-0xBFFF) for the
// whole bank-loading phase. Page 2 is genuinely unused by the receive
// loop (only page 1 is touched there for every mapper type), so it's
// safe to relocate anything into it that would otherwise land in the
// linker's normal, unsafe-past-0x4000 _DATA packing - e.g. the 8K
// SendCommandToMSXPi buffer in msxpi-bios.c (see its own __at pin). Page
// 2 is reclaimed for the game's own data later, once bank loading (and
// anything that might still need that buffer) is done.
static uint8_t __at(0x3851) safeZoneSegment;

// How many entries of storageSegments[] are actually valid for this ROM,
// set once by loadMappedRom(). Used by the runtime bank-switch handlers
// (e.g. ascii16Page1Handler) to bounds-check the bank number the running
// game writes before indexing storageSegments[] with it - an
// out-of-range value there would otherwise PutPN_direct() to whatever
// garbage segment number happens to sit in that array slot.
static uint8_t __at(0x3852) mapperStorageCount;
// Set (once) by a bounds-check failure so it is visible after the fact,
// even though execution continues rather than halting.
static uint8_t __at(0x3853) mapperBankOutOfRange;

// Allocates 2 exec segments plus storageCount storage segments. Returns
// RC_SUCCESS, or RC_FAILED if there isn't enough free mapper RAM.
//
// _GetRamMapperBaseTable() returns one entry per mapper-equipped slot
// (built-in memory mapper, plus any mapper RAM expansion cartridge),
// terminated by an entry with slot==0. The first entry (the machine's
// built-in/primary mapper) is often mostly reserved by the system, so an
// expansion cartridge's own entry - found further down the table - is
// usually where the free segments actually are. All segments for this
// ROM are allocated from whichever single slot has enough room.
static uint8_t allocateMapperSegments(uint8_t storageCount) {
    MAPPERINFOBLOCK* table;
    SEGMENTSTATUS* status;
    uint8_t needed = (uint8_t)(storageCount + 2);
    uint8_t totalFree = 0;
    uint8_t i;
    uint8_t guard;

    // Report free segments across all mapper-equipped slots (informational
    // only). table->slot is a raw slot-address byte in a layout that isn't
    // documented anywhere reachable here, and passing it straight into
    // AllocateSegment's slotAddress parameter corrupted the system on real
    // testing (forced a reboot to BASIC) - so allocation below only ever
    // uses AllocateSegment(0, 0), the "primary mapper" shorthand that's the
    // only pattern actually exercised by Fusion-C's own reference examples.
    // A RAM expansion cartridge only helps here if it becomes the primary
    // mapper; a secondary/expansion slot isn't safely reachable yet.
    Print("allocateMapperSegments: enter\n");
    InitRamMapperInfo(0x04);
    Print("InitRamMapperInfo done\n");
    table = _GetRamMapperBaseTable();
    pprintf("table=", (uint16_t)table); Print("\n");
    for (guard = 0; guard < 8 && table != NULL && table->slot != 0; guard++) {
        totalFree += table->numberFree16KBSegments;
        table = table + 1;
    }
    pprintf("totalFree=", (uint16_t)totalFree); Print("\n");
    (void)needed;

    status = AllocateSegment(0, 0);
    pprintf("exec1 carry=", status->carryFlag); pprintf(" seg=", status->allocatedSegmentNumber); Print("\n");
    if (status->carryFlag) {
        Print("Not enough free segments in the primary mapper\n");
        return RC_FAILED;
    }
    execSegment1 = status->allocatedSegmentNumber;

    status = AllocateSegment(0, 0);
    pprintf("exec2 carry=", status->carryFlag); pprintf(" seg=", status->allocatedSegmentNumber); Print("\n");
    if (status->carryFlag) {
        FreeSegment(execSegment1, 0);
        Print("Not enough free segments in the primary mapper\n");
        return RC_FAILED;
    }
    execSegment2 = status->allocatedSegmentNumber;

    for (i = 0; i < storageCount; i++) {
        status = AllocateSegment(0, 0);
        if (status->carryFlag) {
            uint8_t j;
            pprintf("storage alloc failed at i=", (uint16_t)i); Print("\n");
            for (j = 0; j < i; j++) FreeSegment(storageSegments[j], 0);
            FreeSegment(execSegment1, 0);
            FreeSegment(execSegment2, 0);
            return RC_FAILED;
        }
        storageSegments[i] = status->allocatedSegmentNumber;
        pprintf("storage[", (uint16_t)i); pprintf("]=", storageSegments[i]); Print("\n");
    }

    status = AllocateSegment(0, 0);
    pprintf("safeZone carry=", status->carryFlag); pprintf(" seg=", status->allocatedSegmentNumber); Print("\n");
    if (status->carryFlag) {
        Print("Not enough free segments in the primary mapper\n");
        for (i = 0; i < storageCount; i++) FreeSegment(storageSegments[i], 0);
        FreeSegment(execSegment1, 0);
        FreeSegment(execSegment2, 0);
        return RC_FAILED;
    }
    safeZoneSegment = status->allocatedSegmentNumber;

    Print("allocateMapperSegments: done\n");

    return RC_SUCCESS;
}

// Releases every segment allocateMapperSegments() handed out for this
// load attempt. Must be called on any loadMappedRom() failure path taken
// after allocateMapperSegments() itself returned success - otherwise the
// segments stay owned by this process and are unavailable to the next
// load attempt (they don't get reclaimed just by the MSX being reset),
// starving later attempts within the same session.
static void freeMapperSegments(uint16_t storageCount) {
    uint16_t i;
    for (i = 0; i < storageCount; i++) FreeSegment(storageSegments[i], 0);
    FreeSegment(execSegment1, 0);
    FreeSegment(execSegment2, 0);
    FreeSegment(safeZoneSegment, 0);
}

// Direct mapper page-swap, bypassing Fusion-C's Put_PN() (which jumps
// through a jump table populated by MSX-DOS2's EXTBIO kernel call).
// EXECROM.MAC - a decades-proven megaROM loader - writes the mapper I/O
// ports directly (page N -> port 0xFC+N) rather than going through that
// DOS2 indirection, so bank-switching here does the same.
static void PutPN_direct(uint8_t page, uint8_t segment) {
    OutPort(0xFC + page, segment);
}

// Maps the dedicated safe-zone segment into page 2 for the duration of
// the bank-loading phase, relocating anything pinned into 0x8000+ (see
// safeZoneSegment's own comment) out of the linker's unsafe _DATA
// packing. Must be called before loadBanksIntoStorage's first Put_PN(1,
// ...), and page 2 must not be relied on for anything else again until
// the mapper-specific initial setup (which reclaims it) runs.
static void enterSafeZone(void) {
    pprintf("enterSafeZone: safeZoneSegment=", safeZoneSegment); Print("\n");
    PutPN_direct(2, safeZoneSegment);
    Print("enterSafeZone: after Put_PN\n");
}

// TEMPORARY debugging aid - remove once the mapper-loading stall is found.
// Writes a single character directly to VRAM via raw VDP port I/O,
// bypassing Fusion-C's Locate/PrintChar/cursor-tracking entirely, to
// rule out corrupted Fusion-C screen state as the reason markers stopped
// appearing on screen after the first Put_PN call (row 15, well clear of
// this program's normal Print() output).
#define VDP_MARKER_ROW_BASE 1840
static void vdpMarker(uint8_t col, char ch) {
    uint16_t vaddr = VDP_MARKER_ROW_BASE + col;
    OutPort(0x99, vaddr & 0xFF);
    OutPort(0x99, ((vaddr >> 8) & 0x3F) | 0x40);
    OutPort(0x98, ch);
}

// Streams bankCount banks of bankSizeKB each from the MSXPi link directly
// into their storage segments.
static uint8_t loadBanksIntoStorage(uint16_t bankCount, uint8_t bankSizeKB) {
    // Copy parameters into pinned storage immediately - SDCC's non-reentrant
    // model would otherwise place bankCount/bankSizeKB themselves wherever
    // normal _DATA packing lands, just as exposed as any other local.
    mapperBankCount = bankCount;
    mapperBankSizeKB = bankSizeKB;
    mapperBlockSize = (mapperBankSizeKB == 16) ? 16384 : 8192;
    mapperReceivedSize = mapperBlockSize;

    vdpMarker(0, 'A');
    mapperLoadRc = PerformHandshake(mapperBlockSize);
    vdpMarker(1, 'B');
    if (mapperLoadRc != RC_SUCCESS) return mapperLoadRc;

    for (mapperBankIndex = 0; mapperBankIndex < mapperBankCount; mapperBankIndex++) {
        mapperCurrentSegment = storageSegments[mapperBankSizeKB == 8 ? (mapperBankIndex >> 1) : mapperBankIndex];
        mapperCurrentOffset = (mapperBankSizeKB == 8 && (mapperBankIndex & 1)) ? BANK_HALF_SIZE : 0;

        vdpMarker(2, 'C');
        PutPN_direct(1, mapperCurrentSegment);
        vdpMarker(3, 'D');
        mapperLoadRc = RECVDATA_ONEBLOCK(PAGE0ADDRESS + mapperCurrentOffset, &mapperReceivedSize, mapperBlockSize);
        vdpMarker(9, 'J');
        if (mapperLoadRc != RC_READY && mapperLoadRc != RC_SUCCESS) return mapperLoadRc;
    }

    return RC_SUCCESS;
}

// Scans a 16K window for LD (targetAddr),A (0x32 lo hi) and patches
// matches to CALL handler instead, so the running game's bank-select
// writes land in our code rather than silently hitting plain RAM.
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

// Copies one 8K bank from its storage segment into a target exec page's
// half. sourcePage/targetPage are 1 or 2 (matching Put_PN's CPU page
// numbering). Disables interrupts while sourcePage briefly shows the
// wrong (storage) content instead of its own exec segment.
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
    src = (sourcePage == 1 ? PAGE0ADDRESS : PAGE1ADDRESS) + sourceOffset;
    dst = (targetPage == 1 ? PAGE0ADDRESS : PAGE1ADDRESS) + targetOffset;
    for (i = 0; i < BANK_HALF_SIZE; i++) {
        dst[i] = src[i];
    }
    PutPN_direct(sourcePage, sourcePage == 1 ? execSegment1 : execSegment2);

    __asm
        ei
    __endasm;
}

// ---- ASCII16: 16K banks, 2 windows, pure Put_PN, no copying ----
//
// The bank-select opcode patches (see patchAllStorageSegmentsAscii16)
// wire the running game's own bank-select writes to CALL these handlers -
// but that CALL executes only once the game is actually running, i.e.
// after main()'s final ENASLT has already switched page 0 away from this
// program's own code to the BIOS ROM. Anything living at a normal page-0
// compiled address (these functions themselves, PutPN_direct,
// storageSegments[]) no longer exists there by then - the CPU would jump
// into whatever BIOS ROM bytes happen to sit at that address instead of
// our handler. This is confirmed to be the actual cause of the ASCII16
// mapper-loaded games (ZANAC-EX, XEVIOUS) resetting shortly after
// "Starting game": they ran fine reading their fixed initial banks, then
// crashed the instant they first tried to switch one.
//
// EXECROM.MAC (a proven, decades-old MSX megaROM loader) solves the
// identical problem by copying a small resident bank-switch routine to a
// fixed address in page 3 (0xC000-0xFFFF) before booting the cartridge -
// page 3 is ordinary DOS RAM untouched by both ENASLT (only page 0) and
// our own PutPN_direct calls (only pages 1/2), so code living there stays
// valid regardless of what runs afterward. residentPage1Handler/
// residentPage2Handler below are written the same way: self-contained,
// calling no other C function (which would just have the same problem),
// referencing storageSegments[] only via the fixed RESIDENT_TABLE_ADDR
// copy relocateResidentHandlers() makes - not the original page-0 array.
// They are never called directly; only their compiled bytes are used,
// copied verbatim to RESIDENT_PAGE1_ADDR/RESIDENT_PAGE2_ADDR, which is
// what the ROM patches actually target.
#define RESIDENT_PAGE1_ADDR  0xE000
#define RESIDENT_PAGE2_ADDR  0xE040
#define RESIDENT_TABLE_ADDR  0xE080
#define RESIDENT_SLOT_SIZE   0x40

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

// Copies storageSegments[0..storageCount-1] and the two handler routines'
// compiled bytes to their fixed page-3 addresses. Must run once, after
// storageSegments[] is fully populated, before the final jump into the
// game (the handlers themselves are useless - never even reached - until
// this has run).
static void relocateResidentHandlers(uint16_t storageCount) {
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
    // Patches target the relocated page-3 copies (RESIDENT_PAGE1_ADDR/
    // RESIDENT_PAGE2_ADDR), not ascii16Page1Handler/Page2Handler's own
    // (page-0, post-ENASLT invalid) compiled addresses. Caller must have
    // already called relocateResidentHandlers() so those addresses hold
    // valid code by the time the game actually runs.
    for (s = 0; s < segmentCount; s++) {
        PutPN_direct(1, storageSegments[s]);
        patchWindow(PAGE0ADDRESS, 0x6000, (void (*)(void))RESIDENT_PAGE1_ADDR);
        patchWindow(PAGE0ADDRESS, 0x7000, (void (*)(void))RESIDENT_PAGE2_ADDR);
    }
}

// ---- Konami (no SCC): 8K banks, window1 fixed to bank0, windows 2-4 switchable ----
// window2 @ 0x6000 (page1 high half), window3 @ 0x8000 (page2 low half),
// window4 @ 0xA000 (page2 high half).

static void konamiWindow2Switch(void) { mapperCopyBank(mapperBankParam, BANK_HALF_SIZE, 2, 1); }
static void konamiWindow3Switch(void) { mapperCopyBank(mapperBankParam, 0, 1, 2); }
static void konamiWindow4Switch(void) { mapperCopyBank(mapperBankParam, BANK_HALF_SIZE, 1, 2); }

void konamiWindow2Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        ld (_mapperBankParam), a
        call _konamiWindow2Switch
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

void konamiWindow3Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        ld (_mapperBankParam), a
        call _konamiWindow3Switch
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

void konamiWindow4Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        ld (_mapperBankParam), a
        call _konamiWindow4Switch
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

static void patchAllStorageSegmentsKonami(uint16_t segmentCount) {
    uint16_t s;
    for (s = 0; s < segmentCount; s++) {
        PutPN_direct(1, storageSegments[s]);
        patchWindow(PAGE0ADDRESS, 0x6000, konamiWindow2Handler);
        patchWindow(PAGE0ADDRESS, 0x8000, konamiWindow3Handler);
        patchWindow(PAGE0ADDRESS, 0xA000, konamiWindow4Handler);
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

// ---- ASCII8: 8K banks, all 4 windows switchable ----
// window1 @ 0x4000 (page1 low half), window2 @ 0x6000 (page1 high half),
// window3 @ 0x8000 (page2 low half), window4 @ 0xA000 (page2 high half).

static void ascii8Window1Switch(void) { mapperCopyBank(mapperBankParam, 0, 2, 1); }
static void ascii8Window2Switch(void) { mapperCopyBank(mapperBankParam, BANK_HALF_SIZE, 2, 1); }
static void ascii8Window3Switch(void) { mapperCopyBank(mapperBankParam, 0, 1, 2); }
static void ascii8Window4Switch(void) { mapperCopyBank(mapperBankParam, BANK_HALF_SIZE, 1, 2); }

void ascii8Window1Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        ld (_mapperBankParam), a
        call _ascii8Window1Switch
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

void ascii8Window2Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        ld (_mapperBankParam), a
        call _ascii8Window2Switch
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

void ascii8Window3Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        ld (_mapperBankParam), a
        call _ascii8Window3Switch
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

void ascii8Window4Handler(void) __naked {
    __asm
        push af
        push bc
        push de
        push hl
        ld (_mapperBankParam), a
        call _ascii8Window4Switch
        pop hl
        pop de
        pop bc
        pop af
        ret
    __endasm;
}

static void patchAllStorageSegmentsAscii8(uint16_t segmentCount) {
    uint16_t s;
    for (s = 0; s < segmentCount; s++) {
        PutPN_direct(1, storageSegments[s]);
        patchWindow(PAGE0ADDRESS, 0x6000, ascii8Window1Handler);
        patchWindow(PAGE0ADDRESS, 0x6800, ascii8Window2Handler);
        patchWindow(PAGE0ADDRESS, 0x7000, ascii8Window3Handler);
        patchWindow(PAGE0ADDRESS, 0x7800, ascii8Window4Handler);
    }
}

static void ascii8InitialSetup(uint16_t bankCount) {
    PutPN_direct(1, execSegment1);
    PutPN_direct(2, execSegment2);
    mapperCopyBank(0, 0, 2, 1);
    if (bankCount > 1) mapperCopyBank(1, BANK_HALF_SIZE, 2, 1);
    if (bankCount > 2) mapperCopyBank(2, 0, 1, 2);
    if (bankCount > 3) mapperCopyBank(3, BANK_HALF_SIZE, 1, 2);
}

// Entry point: allocate mapper RAM, stream all banks into storage, patch
// bank-select writes, and set up the initial visible bank state. On
// success page1/page2 are ready for the same ENASLT+JP(HL) jump used for
// plain ROMs.
uint8_t loadMappedRom(RomHeader* hdr) {
    uint16_t storageCount;
    uint8_t rc;

    Print("loadMappedRom: enter\n");
    storageCount = (hdr->bankSizeKB == 16) ? hdr->bankCount : (hdr->bankCount + 1) / 2;
    if (storageCount > MAX_STORAGE_SEGMENTS) {
        pprintf("ROM too large: needs ", storageCount); Print(" segments\n");
        return RC_FAILED;
    }

    pprintf("storageCount=", storageCount); Print("\n");
    rc = allocateMapperSegments((uint8_t)storageCount);
    pprintf("allocateMapperSegments rc=", rc); Print("\n");
    if (rc != RC_SUCCESS) return rc;

    rc = loadBanksIntoStorage(hdr->bankCount, hdr->bankSizeKB);
    if (rc != RC_SUCCESS) {
        Print("Error loading ROM banks\n");
        freeMapperSegments(storageCount);
        return rc;
    }

    if (hdr->mapperType == MAPPER_ASCII16) {
        relocateResidentHandlers(storageCount);
        patchAllStorageSegmentsAscii16(storageCount);
        // The raw ASCII16 mapper hardware defaults BOTH windows to bank 0
        // on power-up/reset, but real MSX BIOS cartridge-boot sequences
        // explicitly set page 2 to bank 1 before handing control to the
        // ROM's own init code (msxgl's own docs confirm this: "when your
        // main() function starts, ... Bank #0 (page 1): Segment #0 ...
        // Bank #1 (page 2): Segment #1"), so a megaROM's first 32K looks
        // contiguous at startup, same as a plain ROM would. Since we jump
        // straight into the ROM's init code rather than going through
        // real BIOS cartridge detection, replicating that BIOS-established
        // state ourselves - not the raw hardware default - is what the
        // game actually expects the first time it runs. An earlier attempt
        // defaulted both windows to bank 0 (matching the hardware-reset
        // default rather than the BIOS-boot convention); that was wrong.
        PutPN_direct(1, storageSegments[0]);
        PutPN_direct(2, storageSegments[hdr->bankCount > 1 ? 1 : 0]);
    } else if (hdr->mapperType == MAPPER_KONAMI) {
        patchAllStorageSegmentsKonami(storageCount);
        konamiInitialSetup(hdr->bankCount);
    } else if (hdr->mapperType == MAPPER_ASCII8) {
        patchAllStorageSegmentsAscii8(storageCount);
        ascii8InitialSetup(hdr->bankCount);
    }

    Print("Game loaded\n");
    return RC_SUCCESS;
}

int main(void) {

    Width(80);

    const unsigned char* items[MAX_REPOS + 1];
    int repoCount = LoadRepositoryList();
    int i;

    if (repoCount == 0) {
        // MSXARCH.INI missing or empty: fall back to the original default
        StrCopy(repoList[0], "https://web.archive.org/web/20241204120811/https://www.msxarchive.nl/pub/msx/games/roms/msx1");
        repoCount = 1;
    }

    for (i = 0; i < repoCount; i++) {
        items[i] = (const unsigned char*)repoList[i];
    }
    items[repoCount] = "Exit";

    int itemCount = repoCount + 1;
    //char inputVar[5];
    char parameters[BLKSIZE + 1];
    const unsigned char* selected = showMenu(items, itemCount);

    // input variables

    if (StrCompare(selected, "Exit") == 0 || StrCompare(selected, "Q") == 0) {
        Print("Exit selected.\n");
        return 0;
    }

    if (selected != NULL) {
        // Clear buffer (pad with zeroes)
        for (int i = 0; i < BLKSIZE + 1; i++) {
            parameters[i] = 0;
        }

        int pos = 0;

        // Copy selected string first
        int j = 0;
        while (selected[j] != '\0' && pos < BLKSIZE) {
            parameters[pos] = selected[j];
            pos++;
            j++;
        }

        // Ensure null terminator
        parameters[BLKSIZE] = 0;

        Print("You selected: ");
        Print(parameters);
        Print("\nConnecting...\n");
    }

    uint8_t rc;
    int cmd;
    // Send the command
    rc = SendCommandToMSXPi("msxarchive", false);

    if (rc != RC_SUCCESS) {
        Print("Error sending command to MSXPi!\n");
        sendQuit();
        return 1;
    }

    // Send parameters
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
            // next page command
            rc = SendCommandToMSXPi("N", false);
        }
        else if (cmd == INPUT_P || cmd == INPUT_UP) {
            // previous page command
            rc = SendCommandToMSXPi("P", false);
        }
        else {
            // Sends a game index number and read teh full code (up to 32k) in RAM
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
                // sendQuit();
                {
                    uint8_t* romTop = (uint8_t*)0x4000;
                    pprintf("sig0=", romTop[0]); pprintf(" sig1=", romTop[1]); Print("\n");
                    pprintf("init=", *(uint16_t*)0x4002); Print("\n");
                }
                Print("Starting game");
                __asm
                ; No C calls (Print, pprintf, etc.) are safe from here on:
                ; their own code lives in page 0 RAM, and ENASLT below
                ; swaps page 0 to the BIOS slot, so any such call would
                ; jump into BIOS ROM content instead of our functions.
                ; Everything past this point must be raw asm only.
                DI
                ; Restore page 0 to the BIOS slot (in case anything left it
                ; pointing elsewhere), then jump straight to the loaded
                ; ROM entry vector. A software "warm reset" (JP 0) was
                ; tried here instead, matching a technique real loadrom
                ; style tools use, but it is a documented, known
                ; unreliable technique even in the reference tool (docs
                ; mention sometimes needing a physical power cycle) - it
                ; did not help in testing and risked breaking ROMs that
                ; already load correctly via a direct jump.
                ; A=0 selects primary slot 0, unexpanded - confirmed via
                ; openMSX own "slotmap" console command to be exactly
                ; where BIOS with BASIC ROM lives on this machine. The
                ; usual idiom (LD A,(0xFCC1) - EXPTBL[0]) was tried first,
                ; but "slotselect" showed page 0 landing on slot 1 (empty
                ; at address 0, reads as 0xFF) instead of slot 0 whenever
                ; that ran - confirmed with "debug read memory 0x38"
                ; reading back 255: 0xFF is the RST 38h opcode, so every
                ; interrupt was jumping into a self-trap at the interrupt
                ; vector, hanging with PC stuck at 0x0038 forever. Exactly
                ; what EXPTBL[0] read as at that moment, or why, was never
                ; pinned down - hardcoding the value that slotmap already
                ; confirmed is correct sidesteps the question entirely.
                ;
                ; Fixing that traded one hang for another: "slotselect"
                ; afterward showed pages 1/2/3 all landing on slot 3.0
                ; (empty) instead of slot 3.2 (Main RAM, where the loaded
                ; game data and the stack itself live) - PC bounced
                ; between BIOS interrupt code in page 0 and garbage in
                ; page 3 forever, never progressing. The secondary slot
                ; select register (0xFFFF) is shared by every page
                ; currently on the same expanded primary slot (slot 3
                ; here); ENASLT below only intends to change page 0
                ; PRIMARY slot, but apparently also disturbs 0xFFFF as
                ; part of switching an unexpanded slot in - clobbering the
                ; subslot selection for pages 1-3, which are still on slot
                ; 3 throughout. Save it once, before ANY of the ENASLT
                ; calls below (reads are the bitwise complement of what
                ; was last written - a documented MSX quirk, hence the
                ; CPL), and restore it once, after all of them, rather
                ; than around each individual call.
                LD A,(#0xFFFF)
                CPL
                LD B,A
                ;
                ; Fixing THAT revealed a third problem: openMSX own
                ; debugger ("Slots" panel) showed page 1 sitting on slot 1
                ; ("MSXDOS2 cart") instead of slot 3 (the mapper, where
                ; the loaded game actually lives) once execution reached
                ; this point - even though nothing here ever explicitly
                ; changes page 1 primary slot. The likely cause: the
                ; Print()/pprintf() diagnostic calls just above (sig0/
                ; sig1/init, "Starting game") go through BDOS, which can
                ; bank the MSXDOS2 kernel into page 1 to service the call
                ; - and nothing switches it back afterward. PutPN_direct
                ; alone cannot fix this: it only sets the mapper own
                ; segment register, which has no effect at all if page 1
                ; is not even primary-slotted to the mapper in the first
                ; place. Re-assert both page 1 and page 2 onto slot 3
                ; (bit 7 set = expanded, bits 0-1 = 3) right before
                ; reading the ROM entry vector, so whatever the Print
                ; calls above did to page 1 cannot matter by the time
                ; execution actually reaches the game. The mapper own
                ; segment selection (storageSegments[0]/[1], set via
                ; PutPN_direct back in loadMappedRom) is independent of
                ; primary-slot state and does not need to be redone here.
                LD HL,#0x4000
                LD A,#0x83
                CALL #0x0024
                LD HL,#0x8000
                LD A,#0x83
                CALL #0x0024
                ;
                LD A,#0
                LD HL,#0
                CALL #0x0024
                LD A,B
                LD (#0xFFFF),A
                LD HL,(#0x4002)
                ; Games typically expect interrupts enabled on startup (many
                ; wait on a VBLANK-driven frame counter via HALT/polling as
                ; their very first step) - re-enable before jumping in, or
                ; such a game hangs forever waiting for an interrupt that
                ; can never fire.
                EI
                JP (HL)
                __endasm;
            }
        }

        if (rc != RC_SUCCESS)
            break;
    }
    sendQuit();
    return 0;
}