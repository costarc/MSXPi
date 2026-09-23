/* renderpage - cached web pages in SCREEN 4, 6 or 8, with line scrolling.
 * Build: make.bat renderpage. DOS: RENDERPA [/4|/6|/8] <url>
 * Copyright (c) 2026 Ronivon Costa. MIT license (see repository LICENSE).
 */
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/vdp_graph2.h"
#include "../../C-common/header/msxpi.h"

#define BUFFER_SIZE 4096
#define HEADER_SIZE 79
#define SCROLL_STEP 8
static uint8_t buffer[BUFFER_SIZE + 1];
static char command[48];
static char error_text[241];
static uint16_t received, visible, stride;
static uint32_t page_height, top_line;
static uint8_t mode, scroll;

static uint16_t word_at(uint8_t n)
{
    return buffer[n] | ((uint16_t)buffer[n + 1] << 8);
}

static uint32_t dword_at(uint8_t n)
{
    return word_at(n) | ((uint32_t)word_at(n + 2) << 16);
}

/* Every request/response fits one block; never leave the link claimed while
 * displaying or waiting for a key. Retry a rejected checksum on the same block. */
static uint8_t exchange(const char *cmd, bool tail)
{
    uint8_t rc, attempts;
    received = 0;
    msxpi_link_claim();
    rc = SendCommandToMSXPi(cmd, tail);
    if (rc == RC_SUCCESS) rc = PerformHandshake(BUFFER_SIZE);
    if (rc == RC_SUCCESS) {
        attempts = 0;
        do {
            received = 0;
            rc = RECVDATA_ONEBLOCK(buffer, &received, BUFFER_SIZE);
        } while (rc == RC_CHKSUM_ERR && ++attempts < MAX_BLOCK_RETRIES);
    }
    msxpi_link_release();
    if (rc == RC_FAILED && received && received <= 240) {
        memcpy(error_text, buffer, received);
        error_text[received] = 0;
    }
    return rc;
}

static char *decimal(char *out, uint32_t value)
{
    char digits[5];
    uint8_t n = 0;
    do {
        digits[n++] = '0' + value % 10;
        value /= 10;
    } while (value);
    while (n) *out++ = digits[--n];
    *out = 0;
    return out;
}

static bool fetch_rows(uint16_t first, uint8_t count)
{
    char *p;
    strcpy(command, "renderpage rows ");
    p = decimal(command + 16, first);
    *p++ = ' ';
    decimal(p, count);
    return exchange(command, false) == RC_SUCCESS && received == stride * count;
}

static void write_row(uint8_t y, uint8_t *data)
{
    uint8_t x;
    uint16_t address;
    if (mode == 4) {
        address = ((uint16_t)(y >> 3) << 8) + (y & 7);
        for (x = 0; x < 32; ++x, address += 8) {
            CopyRamToVram(data + x, address, 1);
            CopyRamToVram(data + 32 + x, address + 0x2000, 1);
        }
    } else {
        CopyRamToVram(data, (uint16_t)y * stride, stride);
    }
}

static void set_scroll(uint8_t value)
{
    *(uint8_t *)0xFFF6 = value; /* RG23SA: keep the BIOS shadow in sync */
    VDPwrite(23, value);
}

static bool scroll_line(bool down)
{
    uint32_t row, remaining;
    uint8_t dest, next, count, n;
    if (down) {
        remaining = page_height - visible - top_line;
        if (!remaining) return true;
        count = remaining >= SCROLL_STEP ? SCROLL_STEP : (uint8_t)remaining;
        row = top_line + visible;
        dest = scroll + (uint8_t)visible;
        next = scroll + count;
    } else {
        if (!top_line) return true;
        count = top_line >= SCROLL_STEP ? SCROLL_STEP : (uint8_t)top_line;
        row = top_line - count;
        dest = scroll - count;
        next = dest;
    }
    if (!fetch_rows(row, count)) return false;
    /* This slot is outside the old visible window. Change R23 only after
       writing it, so errors cannot expose a missing or partially received row. */
    for (n = 0; n < count; ++n)
        write_row(dest + n, buffer + (uint16_t)n * stride);
    scroll = next;
    top_line = down ? top_line + count : top_line - count;
    set_scroll(scroll);
    return true;
}

int main(void)
{
    uint8_t rc, oldscreen, old8, old9, old23, key, count, n;
    uint16_t y, i;
    bool ok;
    error_text[0] = 0;
    top_line = 0;
    scroll = 0;
    if (ReadMSXtype() == 0) {
        Print("Requires MSX2 or later.\r\n");
        return 1;
    }
    if (!*GetCmdLineParameters()) {
        Print("Usage: RENDERPA [/4|/6|/8]\r\n       http[s]://url\r\n");
        return 1;
    }
    Print("Rendering page; ESC cancels.\r\nUp/Down scroll. ESC exits.\r\n");
    rc = exchange("renderpage", true);
    if (rc != RC_SUCCESS) goto failed;
    if (received != HEADER_SIZE || memcmp(buffer, "RPG2", 4)) goto failed;
    mode = buffer[4];
    visible = word_at(7);
    page_height = dword_at(9);
    stride = word_at(13);
    if ((mode != 4 && mode != 6 && mode != 8) ||
        word_at(5) != (mode == 6 ? 512 : 256) ||
        visible != (mode == 4 ? 192 : 212) || page_height < visible ||
        stride != (mode == 4 ? 64 : mode == 6 ? 128 : 256)) goto failed;

    oldscreen = *(uint8_t *)0xFCAF;
    old8 = *(uint8_t *)0xFFE7;
    old9 = *(uint8_t *)0xFFE8;
    old23 = *(uint8_t *)0xFFF6;
    Screen(mode);
    HideDisplay();
    /* Disable sprites and make palette colour zero opaque (SCREEN 6). */
    *(uint8_t *)0xFFE7 |= 0x22;
    VDPwrite(8, *(uint8_t *)0xFFE7);
    *(uint8_t *)0xFFE8 = (old9 & 0x7F) | (mode == 4 ? 0 : 0x80);
    VDPwrite(9, *(uint8_t *)0xFFE8);
    set_scroll(0);
    if (mode != 8) SetSC5Palette((Palette *)(buffer + 15));
    if (mode == 4) {
        /* Four pattern banks (0000..1FFF) and colour banks (2000..3FFF)
           cover a 256-line ring. Move names out of the fourth pattern bank. */
        VDPwrite(2, 0x10); /* name table 4000..43FF */
        VDPwrite(3, 0xFF);
        VDPwrite(4, 3);
        VDPwrite(10, 0);
        for (i = 0; i < 1024; ++i) buffer[i] = (uint8_t)i;
        CopyRamToVram(buffer, 0x4000, 1024);
    }
    ok = true;
    for (y = 0; y < visible; y += count) {
        count = visible - y >= 16 ? 16 : (uint8_t)(visible - y);
        if (!fetch_rows(y, count)) { ok = false; break; }
        for (n = 0; n < count; ++n)
            write_row((uint8_t)(y + n), buffer + (uint16_t)n * stride);
    }
    ShowDisplay();
    while (ok) {
        key = Inkey();
        if (key == 27) break;
        if (key == 30) ok = scroll_line(false);
        if (key == 31) ok = scroll_line(true);
    }
    /* Do not attempt a new command after a broken transfer. The next open
       replaces any abandoned server cache. Successful exits explicitly free it. */
    if (ok) ok = exchange("renderpage close", false) == RC_SUCCESS;
    set_scroll(old23);
    *(uint8_t *)0xFFE7 = old8;
    *(uint8_t *)0xFFE8 = old9;
    VDPwrite(8, old8);
    VDPwrite(9, old9);
    RestoreSC5Palette();
    Screen(oldscreen <= 1 ? oldscreen : 0);
    if (ok) return 0;
failed:
    Print(error_text[0] ? error_text : "Page transfer failed or invalid image.");
    Print("\r\n");
    return 1;
}
