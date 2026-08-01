#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "../../../../../MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
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

uint8_t loadrom() {
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
    Print("Game loaded\n");
    return rc;
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
            rc = loadrom();
            if (rc != RC_SUCCESS) {
                pprintf("Error loading the rom: ", rc);
                return 1;
            }
            else {
                // sendQuit();
                Print("Starting game");
                __asm
                LD HL,#0
                LD A,(#0xFCC1)
                CALL #0x0024
                LD HL,(#0x4002)
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