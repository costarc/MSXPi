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
#include "../../C-common/header/fusion.h"
#include "../../C-common/header/msxpi.h"
#include <string.h>

#include "showpage.c"

// ----------------------------------------------------------------------
// P command help screen
// ----------------------------------------------------------------------
void P_Help(void)
{
    Print("MSXPi Commands:\r\n");

    // List of commands (easy to extend)
    const char* cmds[] = {
        "ver    - Show board, CPLD and server version",
        "cd     - set directory",
        "dir    - List directory contents",
        "run    - Run a command",
        "date   - Set date/time",
        "set    - Manage MSXPi variables",
        "wifi   - Display and set WiFi configuration",
        "vol    - Volume control",
        "music  - Play audio files",
        "reboot - Reboot MSXPi",
        "shut   - Shutdown MSXPi",
        "restart- Restart MSXPi server",
        "netreset [secs] - Rebuild the Pi's TCP/IP setup for UNAPI",
        "reload A: or reload B: - Reload a drive's disk image from disk",
        "showpage [/4|/6|/8] <url> - Render a web page on the MSX screen",
        "chatgpt - Interact with ChatGPT",
        NULL
    };

    for (int i = 0; cmds[i] != NULL; i++)
    {
        Print("  ");
        Print(cmds[i]);
        Print("\r\n");
    }
}

uint8_t processLocalCommands(void) {
    const char* cmd = GetCmdLineParameters();
    if (cmd[0] == 0 || StrCompare(cmd, "/h") == 0 || StrCompare(cmd, "/help") == 0) {
        P_Help();
        return RC_TERMINATE;
    } else if (StrCompare(cmd, "/M") == 0 || StrCompare(cmd, "/m") == 0 || StrCompare(cmd, "ViewMemory") == 0) {
        uint8_t* buffer = (uint8_t*)(get_buffer_ptr() + 100);
        uint16_t sp = get_sp();
        pprintf("Start of Free RAM = ", (uint16_t)buffer);
        pprintf("Stack Point       = ", (uint16_t)sp);
        pprintf("TAP               = ", ReadTPA());
        pprintf("SP                = ", ReadSP());
        pprintf("Max buffer size   = ", get_max_buffer_size());
        return RC_TERMINATE;
    } else {
        return RC_SUCCESS;
    }
}

/* __sdcccall(0): the asm reads its three arguments from the stack and returns in HL. */
int SetTimeFromMSXPi(char hour, char min, char sec) __sdcccall(0) __naked {
    hour; min; sec;   // just to silence "unused" warnings
    __asm
    push ix
        ld   ix, #0
        add  ix, sp
        ld   h, 4(ix); hour
        ld   l, 5(ix); minute
        ld   d, 6(ix); second
        ld   e, #0; reserved
        ld   c, #0x2D; BDOS 2Dh - SET TIME
        call #5
        pop  ix
        ld   l, a; return BDOS result in HL
        ld   h, #0
        ret
        __endasm;
    return 0; // never reached - avoid compiler warning
}

void SetDateTime(void) {
    uint16_t block_size;            // Will hold size of received block - Updated by RECVDATA_ONEBLOCK
    uint16_t block_index = 0;       // Current block index - always zero

    uint8_t* buffer = (uint8_t*)(get_buffer_ptr() + 100);

    uint8_t rc = PerformHandshake(BLKSIZE);
    if (rc != RC_SUCCESS)
        return;

    rc = RECVDATA_ONEBLOCK(buffer, &block_size, BLKSIZE);

    if (rc == RC_SUCCESS) {
        
        char hour = buffer[4];
        char min = buffer[5];
        char sec = buffer[6];

        uint16_t year = buffer[2] | (buffer[3] << 8);
        char month = buffer[1];
        char day = buffer[0];
        int ret = SetDate(year, month, day);
        if (ret != 0) {
            Print("Invalid date\n");
        }
        else {
            Print("Date set\n");
        }

        ret = SetTimeFromMSXPi(hour, min, sec);
        if (ret != 0) {
            Print("Invalid time\n");
        }
        else {
            Print("Time set\n");
        }

    }
}

// ----------------------------------------------------------------------
// "p ver": board / CPLD firmware report (read locally from port $57)
//   bit 7     /WAIT mode read-back (v1.6 firmware)
//   bit 6     reserved, always 0 (keeps $57 below $FE, the openMSX marker)
//   bits 5-0  firmware build ID: every distinct firmware image has its own.
// The ID table is kept in step with hardware/CPLD_Project/LEGACY_BOARDS.md.
// Every line printed fits 29 columns (MSX-DOS 1 default WIDTH in SCREEN 1),
// so each value below is at most 19 characters after its label.
// ----------------------------------------------------------------------
typedef struct {
    uint8_t id;
    const char *board;
    const char *firmware;
} build_t;

static const build_t builds[] = {
    { 0x02, "semi-wired proto",    "original" },
    { 0x03, "10-sample PCB",       "original" },
    { 0x04, "1-sample PCB 4-bit",  "original" },
    { 0x05, "10-sample PCB Rev3",  "original" },
    { 0x06, "proto EPM7128",       "original" },
    { 0x07, "v0.7 Rev4 / v0.8.2",  "original v0.7 Rev.4" },
    { 0x09, "v1.0",                "original v1.0" },
    { 0x0A, "v1.1 PCB 1.0.1+",     "original v1.1" },
    { 0x0B, "v1.2 PCB 1.1/1.2",    "original v1.2" },
    { 0x0C, "v1.2.1b",             "original v1.2.1b" },
    { 0x0D, "v1.3 / v1.5",         "original v1.3" },
    { 0x0E, "v1.3 to v1.6",        "v1.6 /WAIT build" },
    { 0x10, "v0.8.2 / v1.0",       "v1.6 polled build" },
    { 0x14, "v1.1 / v1.2.1b",      "v1.6 /WAIT build" },
};

static void PrintHexByte(uint8_t b)
{
    Print("$");
    PutCharHex(b);
}

static void print_board(uint8_t raw)
{
    uint8_t probe, id, i;
    const build_t *found = NULL;

    /* The same probe the disk driver makes (dskio_rxsize.asm): switch /WAIT
       mode on and see whether $57 changes.  Firmware without the mode register
       ignores the write.  Mode is switched straight off again. */
    OutPort(CONTROL_PORT2, 0x01);
    probe = InPort(CONTROL_PORT2);
    OutPort(CONTROL_PORT2, 0x00);

    id = raw & 0x3F;
    for (i = 0; i < sizeof(builds) / sizeof(builds[0]); i++) {
        if (builds[i].id == id) {
            found = &builds[i];
            break;
        }
    }

    Print("Build ID: ");
    PrintHexByte(id);
    Print("
");
    Print("Board   : ");
    Print(found ? (char *)found->board : "unknown ID");
    Print("
");
    Print("CPLD    : ");
    Print(found ? (char *)found->firmware : "unknown");
    Print("
");
    Print("/WAIT   : ");
    Print(probe != (raw & 0x7F) ? "yes (burst)"
                                : "no (polled)");
    Print("
");
}

/* Returns false when no MSXPi CPLD answered (nothing to ask the server). */
static bool PrintBoardInfo(void)
{
    uint8_t raw = InPort(CONTROL_PORT2);

    Print("Port $57: ");
    PrintHexByte(raw);
    Print("
");

    if (raw >= 0xFE) {
        Print("Board   : no MSXPi found
");
        return false;
    }
    print_board(raw);
    Print("
");
    return true;
}

static bool IsVerCommand(const char *parms)
{
    return (parms[0] == 'v' || parms[0] == 'V') &&
           (parms[1] == 'e' || parms[1] == 'E') &&
           (parms[2] == 'r' || parms[2] == 'R') &&
           (parms[3] == 0 || parms[3] == ' ' || parms[3] == '	');
}

int main(void)
{
    if (processLocalCommands() == RC_TERMINATE)
        return 0;

    const char* parms = GetCmdLineParameters();
    if ((parms[0] == 's' || parms[0] == 'S') &&
        (parms[1] == 'h' || parms[1] == 'H') &&
        (parms[2] == 'o' || parms[2] == 'O') &&
        (parms[3] == 'w' || parms[3] == 'W') &&
        (parms[4] == 'p' || parms[4] == 'P') &&
        (parms[5] == 'a' || parms[5] == 'A') &&
        (parms[6] == 'g' || parms[6] == 'G') &&
        (parms[7] == 'e' || parms[7] == 'E') &&
        (parms[8] == 0 || parms[8] == ' ' || parms[8] == '\t')) {
        const char *showpage_args = parms + 8;
        while (*showpage_args == ' ' || *showpage_args == '\t') ++showpage_args;
        return ShowPageMain(showpage_args);
    }
    // "p ver": report the board and CPLD build first, then fall through to
    // ask the server for its version like any other command.
    if (IsVerCommand(parms) && !PrintBoardInfo())
        return 0;

    // Hold the link across the WHOLE exchange - command, the server's
    // execution, and the response.  msxpi_exchange() covers the common case,
    // but the "date" branch below answers through SetDateTime() rather than
    // printstdout(), so the pair is used directly here.  Both exits from the
    // region are in view, which is the property that matters: a missed release
    // would silently stop the Ethernet UNAPI ISR polling for the rest of the
    // session.
    msxpi_link_claim();
    uint8_t rc = SendCommandToMSXPi("", false);
	uint8_t rcFinal = parseConnError(rc);
    if (rcFinal == RC_SUCCESS || rcFinal == RC_FAILED || rc == RC_BUFOVFLW) {
        if (StrCompare(parms, "date") == 0) {
            SetDateTime();
        }
        else {
            uint8_t* buffer = (uint8_t*)(get_buffer_ptr() + 100);
            printstdout(buffer, MAXBUFSIZE);
        }
    } else {
		Print("Connection error\n");
    }
    
    msxpi_link_release();

    return 0;
}
