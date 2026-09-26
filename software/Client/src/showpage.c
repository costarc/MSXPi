/* showpage - web pages rendered by the server for SCREEN 4, 6 or 8.
 * Included by p.c; run as: P SHOWPAGE [/4|/6|/8] <url>
 * Copyright (c) 2026 Ronivon Costa. MIT license (see repository LICENSE).
 *
 * The server captures the page, scales it to the width, visible height and
 * colours of the requested mode and caches it as native VDP scanlines. The
 * client asks for the header, then for the first screen ("rows"), then for
 * each scroll ("scroll <+-lines>"): the server keeps the current top line and
 * streams only the rows entering the screen, in 4KB blocks of whole rows.
 * The VDP vertical scroll register (R23) turns the 256-line VRAM area into a
 * ring: new rows are written just outside the visible window, then R23 moves.
 */
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/vdp_graph2.h"

#define SP_BUFFER_SIZE 4096
#define SP_HEADER_SIZE 79      /* "RPG2", mode, width, visible, height, stride, palette */
#define SP_LINE_STEP   8       /* Up/Down; Right/Left move 90% of the screen */
#define SP_KEY_ESC     27
#define SP_KEY_RIGHT   28
#define SP_KEY_LEFT    29
#define SP_KEY_UP      30
#define SP_KEY_DOWN    31

static uint8_t sp_buffer[SP_BUFFER_SIZE + 1];
static char sp_command[140];   /* "showpage " + DOS tail (max 127) */
static char sp_error[241];
static uint16_t sp_received, sp_visible, sp_stride, sp_page_step;
static uint32_t sp_height;
static uint8_t sp_mode, sp_scroll;

static uint16_t sp_word(uint8_t n)
{
    return sp_buffer[n] | ((uint16_t)sp_buffer[n + 1] << 8);
}

static uint32_t sp_dword(uint8_t n)
{
    return sp_word(n) | ((uint32_t)sp_word(n + 2) << 16);
}

/* One request, one block. The link is never held while drawing or waiting
 * for a key. A checksum failure retries the same block. */
static uint8_t sp_exchange(const char *cmd)
{
    uint8_t rc, attempts = 0;
    sp_received = 0;
    msxpi_link_claim();
    rc = SendCommandToMSXPi(cmd, false);
    if (rc == RC_SUCCESS) rc = PerformHandshake(SP_BUFFER_SIZE);
    if (rc == RC_SUCCESS) {
        do {
            sp_received = 0;
            rc = RECVDATA_ONEBLOCK(sp_buffer, &sp_received, SP_BUFFER_SIZE);
        } while (rc == RC_CHKSUM_ERR && ++attempts < MAX_BLOCK_RETRIES);
    }
    msxpi_link_release();
    if (rc == RC_FAILED && sp_received && sp_received <= 240) {
        memcpy(sp_error, sp_buffer, sp_received);
        sp_error[sp_received] = 0;
    }
    return rc;
}

static char *sp_decimal(char *out, uint32_t value)
{
    char digits[10];
    uint8_t n = 0;
    do {
        digits[n++] = '0' + value % 10;
        value /= 10;
    } while (value);
    while (n) *out++ = digits[--n];
    *out = 0;
    return out;
}

/* y is a VRAM line (0..255); R23 decides which of them are on screen. */
static void sp_write_row(uint8_t y, uint8_t *data)
{
    uint8_t x;
    uint16_t address;
    if (sp_mode == 4) {
        /* Row bytes: 32 pattern bytes, then 32 colour bytes. */
        address = ((uint16_t)(y >> 3) << 8) + (y & 7);
        for (x = 0; x < 32; ++x, address += 8) {
            CopyRamToVram(data + x, address, 1);
            CopyRamToVram(data + 32 + x, address + 0x2000, 1);
        }
    } else {
        CopyRamToVram(data, (uint16_t)y * sp_stride, sp_stride);
    }
}

static void sp_set_scroll(uint8_t value)
{
    *(uint8_t *)0xFFF6 = value; /* RG23SA: keep the BIOS shadow in sync */
    VDPwrite(23, value);
}

/* Send cmd and write the rows of every block to VRAM as it arrives, from
 * line dest downwards (or upwards when up is set: the server then sends the
 * rows bottom to top). *rows receives the number of rows written.
 * RC_SUCCNOSTD means there was nothing to send (top or bottom of the page). */
static uint8_t sp_stream(const char *cmd, uint8_t dest, bool up, uint16_t *rows)
{
    uint8_t rc, attempts;
    uint16_t n, count = 0;
    msxpi_link_claim();
    rc = SendCommandToMSXPi(cmd, false);
    if (rc == RC_SUCCESS) rc = PerformHandshake(SP_BUFFER_SIZE);
    while (rc == RC_SUCCESS) {
        attempts = 0;
        do {
            sp_received = 0;
            rc = RECVDATA_ONEBLOCK(sp_buffer, &sp_received, SP_BUFFER_SIZE);
        } while (rc == RC_CHKSUM_ERR && ++attempts < MAX_BLOCK_RETRIES);
        if (rc != RC_SUCCESS && rc != RC_READY) break;
        if (sp_received % sp_stride) { rc = RC_UNEXPECTEDDATA; break; }
        for (n = 0; n < sp_received; n += sp_stride, ++count)
            sp_write_row((uint8_t)(up ? dest - 1 - count : dest + count), sp_buffer + n);
        if (rc == RC_READY) rc = RC_SUCCESS;   /* more blocks follow */
        else break;                            /* last block */
    }
    msxpi_link_release();
    if (rc == RC_FAILED && sp_received && sp_received <= 240) {
        memcpy(sp_error, sp_buffer, sp_received);
        sp_error[sp_received] = 0;
    }
    *rows = count;
    return rc;
}

/* Scroll by lines in one request. Down: new rows go below the visible
 * window; up: above it. R23 moves once all rows are written. */
static bool sp_scroll_by(bool down, uint16_t lines)
{
    uint16_t rows;
    uint8_t rc;
    char *p;
    strcpy(sp_command, down ? "showpage scroll " : "showpage scroll -");
    p = sp_command + strlen(sp_command);
    sp_decimal(p, lines);
    rc = sp_stream(sp_command, down ? (uint8_t)(sp_scroll + sp_visible) : sp_scroll,
                   !down, &rows);
    if (rc == RC_SUCCNOSTD) return true;
    if (rc != RC_SUCCESS) return false;
    sp_scroll = down ? (uint8_t)(sp_scroll + rows) : (uint8_t)(sp_scroll - rows);
    sp_set_scroll(sp_scroll);
    return true;
}

static bool sp_valid_header(void)
{
    if (sp_received != SP_HEADER_SIZE || memcmp(sp_buffer, "RPG2", 4)) return false;
    sp_mode = sp_buffer[4];
    sp_visible = sp_word(7);
    sp_height = sp_dword(9);
    sp_stride = sp_word(13);
    return (sp_mode == 4 || sp_mode == 6 || sp_mode == 8) &&
           sp_word(5) == (sp_mode == 6 ? 512 : 256) &&
           sp_visible == (sp_mode == 4 ? 192 : 212) &&
           sp_height >= sp_visible &&
           sp_stride == (sp_mode == 4 ? 64 : sp_mode == 6 ? 128 : 256);
}

static void sp_setup_screen(void)
{
    uint16_t i;
    Screen(sp_mode);
    HideDisplay();
    /* Disable sprites; make palette colour 0 opaque (SCREEN 6 uses it). */
    *(uint8_t *)0xFFE7 |= 0x22;
    VDPwrite(8, *(uint8_t *)0xFFE7);
    /* 192 lines for SCREEN 4, 212 lines for 6 and 8. */
    *(uint8_t *)0xFFE8 = (*(uint8_t *)0xFFE8 & 0x7F) | (sp_mode == 4 ? 0 : 0x80);
    VDPwrite(9, *(uint8_t *)0xFFE8);
    sp_set_scroll(0);
    if (sp_mode != 8) SetSC5Palette((Palette *)(sp_buffer + 15));
    if (sp_mode == 4) {
        /* Four pattern banks (0000-1FFF) and colour banks (2000-3FFF) cover a
           256-line ring. Move the name table out of the fourth pattern bank. */
        VDPwrite(2, 0x10); /* name table 4000-43FF */
        VDPwrite(3, 0xFF);
        VDPwrite(4, 3);
        VDPwrite(10, 0);
        for (i = 0; i < 1024; ++i) sp_buffer[i] = (uint8_t)i;
        CopyRamToVram(sp_buffer, 0x4000, 1024);
    }
}

static bool sp_draw_first_screen(void)
{
    uint16_t rows;
    char *p;
    strcpy(sp_command, "showpage rows 0 ");
    p = sp_command + strlen(sp_command);
    sp_decimal(p, sp_visible);
    return sp_stream(sp_command, 0, false, &rows) == RC_SUCCESS && rows == sp_visible;
}

/* Entry point for P SHOWPAGE. args holds the options and URL, e.g. "/8 https://...". */
int ShowPageMain(const char *args)
{
    uint8_t oldscreen, old8, old9, old23, key;
    bool ok;

    sp_error[0] = 0;
    sp_scroll = 0;
    if (ReadMSXtype() == 0) {
        Print("Requires MSX2 or later.\r\n");
        return 1;
    }
    if (!args || !*args) {
        Print("Usage: P SHOWPAGE [/4|/6|/8] http[s]://url\r\n");
        return 1;
    }
    /* SCREEN 7/8 interleave both VRAM banks; with 64KB VRAM they show
       garbage. MODE (FAFC) bits 2-1: 00=16KB, 01=64KB, 10=128KB. */
    if (strstr(args, "/8") && (*(uint8_t *)0xFAFC & 0x06) != 0x04) {
        Print("SCREEN 8 needs 128KB VRAM. Use /4 or /6.\r\n");
        return 1;
    }
    Print("Rendering page, please wait...\r\n");
    strcpy(sp_command, "showpage ");
    strncat(sp_command, args, sizeof(sp_command) - 10);
    if (sp_exchange(sp_command) != RC_SUCCESS || !sp_valid_header()) goto failed;
    sp_page_step = (uint16_t)(((uint32_t)sp_visible * 9) / 10);

    oldscreen = *(uint8_t *)0xFCAF;
    old8 = *(uint8_t *)0xFFE7;
    old9 = *(uint8_t *)0xFFE8;
    old23 = *(uint8_t *)0xFFF6;
    sp_setup_screen();
    ok = sp_draw_first_screen();
    ShowDisplay();
    while (ok) {
        key = Inkey();
        if (key == SP_KEY_ESC) break;
        if (key == SP_KEY_DOWN)  ok = sp_scroll_by(true, SP_LINE_STEP);
        if (key == SP_KEY_UP)    ok = sp_scroll_by(false, SP_LINE_STEP);
        if (key == SP_KEY_RIGHT) ok = sp_scroll_by(true, sp_page_step);
        if (key == SP_KEY_LEFT)  ok = sp_scroll_by(false, sp_page_step);
    }
    /* After a broken transfer do not send another command; the next open
       replaces the abandoned server cache. A clean exit frees it now. */
    if (ok) ok = sp_exchange("showpage close") == RC_SUCCESS;
    sp_set_scroll(old23);
    *(uint8_t *)0xFFE7 = old8;
    *(uint8_t *)0xFFE8 = old9;
    VDPwrite(8, old8);
    VDPwrite(9, old9);
    RestoreSC5Palette();
    Screen(oldscreen <= 1 ? oldscreen : 0);
    if (ok) return 0;
failed:
    Print(sp_error[0] ? sp_error : "Page transfer failed or invalid image.");
    Print("\r\n");
    return 1;
}
