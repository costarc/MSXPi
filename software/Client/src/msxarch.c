#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "../../fusion-c/header/msx_fusion.h"
#include "../header/msxpi.h"

#define PAGESIZE (22 * 80)
#define INPUTLEN 4

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
    uint8_t rc = SendCommandToMSXPi("Q");
}

int main(void) {

    Width(80);

    const unsigned char* items[] = {
        "https://web.archive.org/web/20241204120811/https://www.msxarchive.nl/pub/msx/games/roms/msx1",
        "https://web.archive.org/web/20241204120811/https://www.msxarchive.nl/pub/msx/games/roms/msx2",
        "https://web.archive.org/web/20241204120811/https://www.msxarchive.nl/pub/msx/games/msx1",
        "https://web.archive.org/web/20241204120811/https://www.msxarchive.nl/pub/msx/games/turbo_r",
        "Exit"
    };

    int itemCount = sizeof(items) / sizeof(items[0]);
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
    rc = SendCommandToMSXPi("msxarchive");

    if (rc != RC_SUCCESS) {
		Print("Error sending command to MSXPi!\n");
		sendQuit();
        return 1;
    }

    // Send parameters
    pprints("Sending parameters: ", parameters);
    rc = SendCommandToMSXPi(parameters);

    if (rc != RC_SUCCESS) {
        sendQuit();
        return 1;
    }

    uint8_t buffer[PAGESIZE + 1];
    uint16_t size = sizeof(buffer);
    char userNumber[INPUTLEN];
    uint16_t replySize = 0;
    uint16_t maxbuf = MAXBUFSIZE;

    while (1) {
        rc = RECVDATA2(buffer, &replySize, &maxbuf);

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
        Print("Q = Quit  N/Down = Next Page  P/Up = Previous Page or Game Number to load:");

        cmd = GetValidInput(userNumber);
        if (cmd == INPUT_Q)
            break;
        else if (cmd == INPUT_N || cmd == INPUT_DOWN) {
            // next page command
            rc = SendCommandToMSXPi("N");
        }
        else if (cmd == INPUT_P || cmd == INPUT_UP) {
            // previous page command
            rc = SendCommandToMSXPi("P");
        }
        else {
            // Sends a game index number and read teh full code (up to 32k) in RAM
            rc = SendCommandToMSXPi(userNumber);
            if (rc != RC_SUCCESS)
                break;

            //rc = recvmultiblock
        }

        if (rc != RC_SUCCESS)
            break;
    }
    sendQuit();
    Width(80);
    return 0;
}