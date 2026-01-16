#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "../../../../../MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../C-common/header/msxpi.h"
#include "fusion-c/header/printf.h"

#define MSXPI_BUF   0xC000
#define MSXPI_RC    (*(unsigned char*)MSXPI_BUF)

// Simple wrapper to mimic CALL MSXPI("2,C000,IRC ...")
void MSXPiCommand(const char *cmd, char *buf, unsigned int bufaddr) {
    // You’ll need to implement this according to your MSXPi extension:
    // Typically it’s a BDOS call or a hook that takes a string like "2,C000,IRC CONNECT msxpi"
    // For now, assume you have something like:
    //   CallMSXPi(cmd);
    // and it fills memory at bufaddr with the response.
    //
    // Placeholder:
    (void)cmd;
    (void)buf;
    (void)bufaddr;
}

// Build and send an MSXPi IRC command, like BASIC’s SENDCOMMAND
unsigned char SendIRC(const char *subcmd, char *buf) {
    char cmdline[128];
    sprintf(cmdline, "2,%X,IRC %s", MSXPI_BUF, subcmd);
    MSXPiCommand(cmdline, buf, MSXPI_BUF);
    return MSXPI_RC;
}

void ClearChatArea(void) {
    int y;
    for (y = 3; y <= 19; y++) {
        Locate(1, y);
        Printf("                                                                             ");
    }
}

void DrawScreen(void) {
    int l, n;
    Locate(0, 0);
    Printf("\x01X");
    for (l = 2; l <= 29; l++) Printf("\x01W");
    Printf("\x01R");
    for (l = 31; l <= 78; l++) Printf("\x01W");
    Printf("\x01Y");

    Printf("\x01V   MSXPi Chat - version 0.1  \x01V                  (c) 2026 RCC                  \x01V");

    Printf("\x01T");
    for (l = 2; l <= 29; l++) Printf("\x01W");
    Printf("\x01Q");
    for (l = 31; l <= 78; l++) Printf("\x01W");
    Printf("\x01S");

    for (n = 4; n <= 20; n++) {
        Printf("\x01V");
        Printf("                                                                             ");
        Printf("\x01V");
    }

    Printf("\x01T");
    for (l = 2; l <= 78; l++) Printf("\x01W");
    Printf("\x01S");

    Printf("\x01VType a message:                                                     \x01V");

    Printf("\x01Z");
    for (l = 2; l <= 78; l++) Printf("\x01W");
    Printf("\x01[");
}

void PrintFromPiBuffer(int *ml) {
    unsigned char *p = (unsigned char*)MSXPI_BUF;
    unsigned char rc = p[0];
    unsigned int len = p[1] + 256 * p[2];
    int i;

    if (rc != 0xEB) return; // same check as BASIC (header_rc)

    Locate(1, *ml);
    for (i = 9; i < (int)len; i++) { // BASIC used &HC009 = C000+9
        char c = p[i];
        if (c == 0) break;
        Printf("%c", c);
    }
    (*ml)++;
    if (*ml > 19) {
        *ml = 3;
        ClearChatArea();
        DrawScreen();
    }
}

void InputAndSend(const char *chan, const char *nick, int *ml) {
    char line[80];
    int pos = 0;
    int c;

    Locate(16, 21);
    Printf(".............................................................");
    Locate(16, 21);

    memset(line, 0, sizeof(line));

    while (1) {
        c = Inkey();
        if (c == 0) continue;

        if (c == 13) { // ENTER
            if (pos > 0) {
                char cmd[128];
                line[pos] = 0;
                sprintf(cmd, "SAY %s %s", chan, line);
                SendIRC(cmd, (char*)MSXPI_BUF);

                Locate(1, *ml);
                Printf("<%s> %s -> %s", chan, nick, line);
                (*ml)++;
                if (*ml > 19) {
                    *ml = 3;
                    ClearChatArea();
                    DrawScreen();
                }
            }
            break;
        } else if (c == 27) { // ESC
            Exit(0);
        } else if (c == 8) { // BACKSPACE
            if (pos > 0) {
                pos--;
                line[pos] = 0;
                Locate(16 + pos, 21);
                Printf(".");
                Locate(16 + pos, 21);
            }
        } else if (pos < 61 && c >= 32 && c <= 126) {
            line[pos++] = (char)c;
            Printf("%c", c);
        }
    }
}

int main(void) {
    const char *chan = "#openmsx";
    const char *nick = "msxpi";
    int ml = 3;
    unsigned long t0;
    char buf[1]; // dummy, buffer is actually at 0xC000

    Screen(0);
    Width(80);
    Cls();

    Printf("Connecting to chat channel...\r\n");

    // CONNECT
    SendIRC("CONNECT msxpi", buf);

    // Wait for Ready / Connected
    t0 = Timer();
    while (1) {
        if ((Timer() - t0) > 300) break; // ~3 seconds
        SendIRC("READ", buf);
        // Here you’d parse MSXPI_BUF for "Pi:Ok:Connected" or "Pi:Ok:Ready"
        // For now, just break after timeout.
    }

    DrawScreen();

    // JOIN
    {
        char cmd[64];
        sprintf(cmd, "JOIN %s", chan);
        SendIRC(cmd, buf);
    }

    while (1) {
        // Poll IRC
        SendIRC("READ", buf);
        PrintFromPiBuffer(&ml);

        // Handle user input
        InputAndSend(chan, nick, &ml);
    }

    return 0;
}