#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "../../fusion-c/header/msx_fusion.h"
#include "../header/msxpi.h"
#define buffer ((uint8_t*)0x8000)

uint8_t processLocalCommands(void) {
    const char* cmd = GetCmdLineParameters();
    if (cmd[0] == 0) {
        return RC_INVALIDCOMMAND;
    } else if (StrCompare(cmd, "/M") == 0  || StrCompare(cmd, "/m") == 0 || StrCompare(cmd, "ViewMemory") == 0) {
        uint8_t* buf = get_buffer_ptr();
        uint16_t sp = get_sp();
        pprintf("Start of Free RAM = ", (uint16_t)buf);
        pprintf("Stack Point = ", (uint16_t)sp);
        pprintf("TAP = ", ReadTPA());
        pprintf("SP = ", ReadSP());
        pprintf("Max buffer size = ", get_max_buffer_size());
        return RC_TERMINATE;
    }
	return RC_INVALIDCOMMAND;
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

    const char* tail = GetCmdLineParameters();
    uint8_t rc = SendCommandToMSXPi("", false);
	uint8_t rcFinal = parseConnError(rc);
    if (rcFinal == RC_SUCCESS || rcFinal == RC_FAILED || rc == RC_BUFOVFLW) {
        if (StrCompare(tail, "date") == 0) {
            SetDateTime();
        }
        else {
            printstdout((uint16_t)BLKSIZE);
        }
    } else {
		Print("Connection error\n");
    }
    
    return 0;
}