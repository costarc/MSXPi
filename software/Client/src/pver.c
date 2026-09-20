/*
 * pver.com - tell which MSXPi board and CPLD firmware build this is, then
 * print the server version (the output of "p ver").
 *
 * The board part reads the CPLD's port $57 locally and needs no server.
 *   bit 7     /WAIT mode read-back (v1.6 firmware)
 *   bit 6     reserved, always 0 (keeps $57 below $FE, the openMSX marker)
 *   bits 5-0  firmware build ID: every distinct firmware image has its own.
 *             Widened from 4 bits once 0-15 ran out; the old IDs are unchanged.
 * The ID table is kept in step with hardware/CPLD_Project/LEGACY_BOARDS.md.
 *
 * Build: make.bat pver (from the software folder).
 */
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../C-common/header/msxpi.h"

typedef struct {
    uint8_t id;
    const char *board;
    const char *firmware;
} build_t;

/* Every line pver prints fits 29 columns - MSX-DOS 1's default WIDTH in
   SCREEN 1 - so each value below is at most 19 characters after its label. */
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
    Print("\r\n");
    Print("Board   : ");
    Print(found ? (char *)found->board : "unknown ID");
    Print("\r\n");
    Print("CPLD    : ");
    Print(found ? (char *)found->firmware : "unknown");
    Print("\r\n");
    Print("/WAIT   : ");
    Print(probe != (raw & 0x7F) ? "yes (burst)"
                                : "no (polled)");
    Print("\r\n");
}

int main(void)
{
    uint8_t raw, rc;

    raw = InPort(CONTROL_PORT2);
    Print("Port $57: ");
    PrintHexByte(raw);
    Print("\r\n");

    if (raw >= 0xFE) {
        /* No MSXPi CPLD answered: nothing to ask the server through. */
        Print("Board   : no MSXPi found\r\n");
        return 0;
    }
    print_board(raw);
    Print("\r\n");

    /* Server version: the same request, and the same handling, as "p ver"
       (see p.c - the link is held across the whole exchange). */
    msxpi_link_claim();
    rc = SendCommandToMSXPi("ver", false);
    if (parseConnError(rc) == RC_SUCCESS || rc == RC_FAILED || rc == RC_BUFOVFLW) {
        printstdout((uint8_t *)(get_buffer_ptr() + 100), MAXBUFSIZE);
    } else {
        Print("Server  : connection error\r\n");
    }
    msxpi_link_release();
    return 0;
}

