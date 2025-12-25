#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "../../../../../MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../C-common/header/msxpi.h"

// ----------------------------------------------------------------------
// P command help screen
// ----------------------------------------------------------------------
void P_Help(void)
{
    Print("MSXPi Commands:\r\n");

    // List of commands (easy to extend)
    const char* cmds[] = {
        "ver    - Show MSXPi version",
        "cd     - set directory",
        "dir    - List directory contents",
        "run    - Run a command",
        "date   - Set date/time",
        "set    - Manage MSXPi variables",
        "wifi   - Display and set WiFi configuration",
        "vol    - Volume control",
        "play   - Play audio files",
        "reboot - Reboot MSXPi",
        "shut   - Shutdown MSXPi",
        "restart- Restart MSXPi server",

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
        uint8_t* buf = get_buffer_ptr();
        uint16_t sp = get_sp();
        pprintf("Start of Free RAM = ", (uint16_t)buf);
        pprintf("Stack Point       = ", (uint16_t)sp);
        pprintf("TAP               = ", ReadTPA());
        pprintf("SP                = ", ReadSP());
        pprintf("Max buffer size   = ", get_max_buffer_size());
        return RC_TERMINATE;
    } else {
        return RC_SUCCESS;
    }
}

int SetTimeFromMSXPi(char hour, char min, char sec) __naked {
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
    uint16_t block_size;            // Will hold size of received block - Updated by RECVDATA2_ONEBLOCK
    uint16_t block_index = 0;       // Current block index - always zero

    uint8_t* buffer = (uint8_t*)(get_max_buffer_size() + 100);
    uint8_t rc = RECVDATA2_ONEBLOCK(buffer, &block_size, BLKSIZE);

    uint16_t year = buffer[2] | (buffer[3] << 8);
    char hour = buffer[4];
    char min = buffer[5];
    char sec = buffer[6];

    if (rc == RC_SUCCESS) {
        int year = buffer[2] | (buffer[3] << 8);
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

int main(void)
{
    if (processLocalCommands() == RC_TERMINATE)
        return 0;

    const char* parms = GetCmdLineParameters();
    uint8_t rc = SendCommandToMSXPi("", false);
	uint8_t rcFinal = parseConnError(rc);
    if (rcFinal == RC_SUCCESS || rcFinal == RC_FAILED || rc == RC_BUFOVFLW) {
        if (StrCompare(parms, "date") == 0) {
            SetDateTime();
        }
        else {
            uint8_t* buf = (uint8_t*)(get_max_buffer_size() + 100);
            printstdout(buf, BLKSIZE);
        }
    } else {
		Print("Connection error\n");
    }
    
    return 0;
}