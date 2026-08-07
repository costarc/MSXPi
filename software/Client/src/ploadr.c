#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "../../../../../MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../C-common/header/msxpi.h"

// ---------------------------------------------------------------------------
// ploadr - direct MegaROM/plain-ROM loader over MSXPi, execrom-style: takes
// a filename on the command line (no browsing UI), resolved server-side
// against whatever path was last set via "p cd <path>" - same convention
// EXECROM.MAC's own /W option uses, reusing the same server-side execrom()
// command (msxpi-server.py) unchanged.
//
// Step 1 scope: MAPPER_PLAIN only. Mapped ROMs (Konami/ASCII8/ASCII16) are
// explicitly rejected for now - see the project notes on why msxarch.c's
// existing mapper-loading code isn't reused: it has at least one live,
// unresolved slot/subslot bug in its execution handoff (hardcoded 0x83
// selecting subslot 0 for pages 1/2, while this machine's real Memory
// Mapper sits at subslot 2), on top of Konami/ASCII8's bank-switch handlers
// missing the page-3 relocation fix ASCII16 already has. Mapped-ROM support
// will be added incrementally, one mapper type at a time, once the plain
// path here is confirmed solid.
// ---------------------------------------------------------------------------

#define ROM_HEADER_MAGIC    0x52   // 'R'
#define ROM_HEADER_SIZE     16
#define ROM_REASON_MAX      144
#define ROM_MSG_MAX         (ROM_HEADER_SIZE + ROM_REASON_MAX)
#define MAPPER_PLAIN        0
#define MAPPER_KONAMI       1
#define MAPPER_ASCII8       2
#define MAPPER_ASCII16      3
#define MAPPER_REJECTED     0xFF

typedef struct {
    uint8_t  mapperType;
    uint8_t  bankSizeKB;
    uint16_t bankCount;
    uint32_t totalSize;
} RomHeader;

// Reads the fixed-size ROM header the server sends immediately after
// "execrom <filename>". For MAPPER_REJECTED, the header is followed by a
// short reason string instead of a ROM body; it's copied into reason.
static uint8_t readRomHeader(RomHeader* hdr, char* reason, uint16_t reasonBufSize) {
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

// Streams a plain (<=32K) ROM straight into 0x4000-0xBFFF, same mechanism
// as msxarch.c's own loadrom() (that path was never implicated in any of
// the mapper-handoff bugs - only the mapper loading/patching/handoff code
// was, so it's reused as-is). Progress is shown as a single line updated
// in place (Locate + fixed-width field) rather than one scrolling "Reading
// block N" line per block, which used to run on right into whatever the
// caller printed just before it (no blank line/margin of its own).
#define STATUS_ROW 4
static uint8_t loadPlainRom(void) {
    uint8_t  rc;
    uint16_t block_size = 16384;
    uint8_t  index = 1;

    rc = PerformHandshake(block_size);
    if (rc != RC_SUCCESS)
        return rc;

    uint8_t* romaddress = PAGE0ADDRESS;
    while (1) {
        Locate(0, STATUS_ROW);
        pprintf("Loading block ", index++);
        Print("   ");   // pad over a possible leftover longer number
        rc = RECVDATA_ONEBLOCK(romaddress, &block_size, block_size);
        romaddress += block_size;
        if (rc != RC_READY)
            break;
    }
    Locate(0, STATUS_ROW);
    Print("Loading complete.        \n");
    return rc;
}

int main(void) {
    const char* filename = GetCmdLineParameters();
    if (filename == NULL || filename[0] == '\0') {
        Print("Usage: ploadr <game.rom>\n");
        return 1;
    }

    Cls();
    Locate(0, 0);
    Print("ploadr - MSXPi ROM loader\n\n");

    // Build "ploadr <filename>" - the server resolves the bare filename
    // against whatever path was last set via "p cd <path>", exactly like
    // "p dir"/"p run" already do for other commands.
    char cmd[80];
    StrCopy(cmd, "ploadr ");
    {
        int i = 0;
        int j = StrLen(cmd);
        while (filename[i] != '\0' && j < (int)sizeof(cmd) - 1) {
            cmd[j++] = filename[i++];
        }
        cmd[j] = '\0';
    }

    Locate(0, 2);
    pprints("Requesting: ", (char*)filename);
    Print("\n");
    uint8_t rc = SendCommandToMSXPi(cmd, false);
    if (rc != RC_SUCCESS) {
        Print("Error contacting MSXPi\n");
        return 1;
    }

    RomHeader romHeader;
    char romRejectReason[ROM_REASON_MAX];
    rc = readRomHeader(&romHeader, romRejectReason, sizeof(romRejectReason));
    if (rc != RC_SUCCESS) {
        Print("Error reading ROM header\n");
        return 1;
    }
    if (romHeader.mapperType == MAPPER_REJECTED) {
        Print(romRejectReason);
        Print("\n");
        return 1;
    }
    if (romHeader.mapperType != MAPPER_PLAIN) {
        Print("Mapper type not yet supported by this build (plain ROMs only for now)\n");
        return 1;
    }
    if (romHeader.totalSize > 0x8000) {
        Print("ROM too large for plain loading (>32K needs a mapper - not yet supported)\n");
        return 1;
    }

    rc = loadPlainRom();
    if (rc != RC_SUCCESS) {
        pprintf("Error loading ROM: ", rc);
        return 1;
    }

    // Deliberately no BDOS-routed call (Print/pprintf/etc) between here and
    // the jump - msxarch.c's own mapper-loading code documents BDOS calls
    // banking a different slot into page 1 to service themselves, with
    // nothing switching it back afterward. For a mapper ROM that gets fixed
    // by explicitly reasserting page 1/2's slot right before reading the
    // entry vector; a plain ROM has no mapper slot to reassert to (it's
    // ordinary program RAM), so the only safe fix here is to never call
    // anything BDOS-routed after loading finishes and before the jump.
    // loadPlainRom()'s own "Reading block N" lines already confirm loading
    // happened, so no extra status print is needed at this point anyway.

    // Execution handoff: a direct JP to the ROM's entry vector, restoring
    // only page 0's PRIMARY slot (port 0xA8) to 0 first, consistently
    // landed back in BASIC ("Break in 0"/"Ok") for some ROMs. Switching to
    // RST 0 (software reset) instead fixed that for kmaster.rom, but
    // Galaga still failed - it booted into MSXPI-DOS instead of the game
    // rather than reaching BASIC, a different symptom, so RST 0 wasn't
    // actually fixing the same root cause, just tolerating it sometimes.
    //
    // Disassembling LOADROM.COM (a proven, working third-party loader -
    // Galaga loads and plays correctly with it) - properly this time, via
    // a hand-verified fix to the disassembler's own JR/DJNZ target-address
    // bug - confirmed it clears page 0's SECONDARY slot (subslot) bits
    // too, via address 0xFFFF, in addition to the primary slot via port
    // 0xA8, with a plain direct JP, no reset at all. Verified this is
    // real, executed code for Galaga specifically (its ROM header entry
    // vector is $4017, so the CP $40 branch it's gated behind is taken).
    // Port 0xFFFF reads as the bitwise complement of what was last
    // written (a documented MSX quirk) - CPL after reading it to recover
    // the true value before masking and writing back; writes are not
    // inverted.
    //
    // LOADROM.COM also never re-enables interrupts before its JP - DI
    // holds all the way through. That matches the standard MSX cartridge
    // boot convention: the BIOS calls a ROM's init vector with interrupts
    // disabled, and it's the cartridge's own job to EI once its own
    // interrupt hooks/handlers are set up. The EI previously here broke
    // that contract - dropped, to match both the convention and the
    // proven-working reference exactly.
    //
    // LOADROM.COM also patches BOTH BIOS interrupt hooks (H.KEYI at
    // 0xFD9A, H.TIMI at 0xFD9F) to a bare RET (0xC9) right before the
    // jump. Tried matching that here too, on the theory that a stale
    // MSXPi driver hook left in that chain could be the gameplay-hang
    // cause - but that build made Galaga regress to NOT completing the
    // handoff at all (stalls at "Loading complete.", title screen never
    // even appears), worse than before. Reverted pending isolation - it's
    // possible Galaga's own init code inspects/relies on what's already
    // in that hook table (e.g. to distinguish warm-restart from cold
    // boot) and wiping it broke that assumption. pacman.rom didn't show
    // this regression, so it's not universally safe the way the
    // page-0/subslot clear is.
    __asm
        DI
        ; Clear page 0 secondary/subslot bits.
        LD A,(0xFFFF)
        CPL
        LD B,#0xFC
        AND B
        LD (0xFFFF),A
        ; Clear page 0 primary slot bits (register-register AND form here
        ; instead of AND with an immediate operand, which tripped a parser
        ; warning in SDCC own instruction-size estimator).
        IN A,(0xA8)
        LD B,#0xFC
        AND B
        OUT (0xA8),A
        LD HL,(0x4002)
        JP (HL)
    __endasm;

    return 0;  // unreachable
}
