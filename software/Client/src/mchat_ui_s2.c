/*
 * MSX Free Chat - MSX1 display backend (TMS9918 SCREEN 2). See mchat_ui.h.
 * Included by mchat.c, which dispatches ui_*() to s2_*() or s6_*().
 *
 * SCREEN 2 is used as a bitmap: the name table is the identity map, so tile
 * n has its own 8 bytes of pattern and colour and text is drawn into
 * them by software. The font is 4x8 on a 5 pixel pitch, 51 columns on the
 * 256 pixel line (the BIOS 6x8 font gives only 40 or 42). A tile is 8 pixels,
 * so tiles and columns line up every 40 pixels = 8 columns = 5 tiles: that is
 * ui_side, where the user list ends and the chat begins.
 *
 * Characters live in a shadow grid; s2_text() queues tiles and s2_flush()
 * redraws only those. One colour pair per tile row, so a tile takes the
 * style of whatever was written to it last.
 */

#include "mchat_font4x8.h"

#define PITCH 5
#define GRID_COLS 51
#define GRID_ROWS 24
#define NAMTBL 0x1800
#define PATTBL 0x0000
#define COLTBL 0x2000
#define SPRATR 0x1B00
#define SPRPAT 0x3800

static char cell[GRID_ROWS][GRID_COLS];
static uint8_t tile_style[GRID_ROWS * 32];
static uint8_t dirty[GRID_ROWS * 4];        /* one bit a tile */
static uint8_t cursor_attr[8];

/* fg<<4 | bg for each UI_ style. MSX1 palette: 1 black 4 dark blue 5 light
 * blue 7 cyan 10 dark yellow 11 light yellow 13 magenta 14 gray 15 white. */
static const uint8_t style_color[UI_STYLES] = {
    0xF1,   /* TEXT      white on black */
    0xB1,   /* PRIV      light yellow */
    0xE1,   /* SYSTEM    gray */
    0x31,   /* OWN       light green */
    0xD1,   /* ACTION    magenta */
    0xA1,   /* PRIVOUT   dark yellow */
    0x1E,   /* STATUS    black on gray */
    0xF4,   /* SIDE      white on dark blue */
    0xB4,   /* SIDE_HEAD yellow on dark blue */
    0xE4,   /* TAB       gray on dark blue */
    0x1B,   /* TAB_ON    black on light yellow */
    0xFD,   /* TAB_NEW   white on magenta */
    0xF1    /* INPUT     white on black */
};

static void s2_text(uint8_t col, uint8_t row, const char *s, uint8_t width, uint8_t style) {
    uint8_t i, last, t, first;
    uint16_t n;
    char c;
    if (row >= GRID_ROWS || col >= GRID_COLS || !width) return;
    if (col + width > GRID_COLS) width = GRID_COLS - col;
    /* Only what changed is queued: composing a whole screen costs nothing. */
    for (i = 0; i < width; i++) {
        c = *s ? *s++ : ' ';
        if (c < 32 || c > 126) c = '?';
        if (cell[row][col + i] != c) {
            cell[row][col + i] = c;
            first = ((uint16_t)(col + i) * PITCH) >> 3;
            last = ((uint16_t)(col + i) * PITCH + 3) >> 3;
            for (t = first; t <= last; t++) {
                n = (uint16_t)row * 32 + t;
                dirty[n >> 3] |= 1 << (n & 7);
            }
        }
    }
    last = ((uint16_t)(col + width) * PITCH - 1) >> 3;
    for (t = ((uint16_t)col * PITCH) >> 3; t <= last; t++) {
        n = (uint16_t)row * 32 + t;
        if (tile_style[n] != style) {
            tile_style[n] = style;
            dirty[n >> 3] |= 1 << (n & 7);
        }
    }
}

/* Paint one tile: pixel columns tile*8 .. tile*8+7 of text row 'row'. */
static void paint(uint8_t row, uint8_t tile) {
    uint8_t pat[8], colr[8], r, c, c0, c1, ch, nib;
    int8_t shift;
    uint16_t px0 = (uint16_t)tile * 8;
    const uint8_t *g;
    memset(pat, 0, 8);
    c0 = px0 / PITCH;
    c1 = (px0 + 7) / PITCH;
    for (c = c0; c <= c1 && c < GRID_COLS; c++) {
        ch = cell[row][c];
        if (ch < 32 || ch > 126) continue;
        g = mchat_font + (ch - 32) * 4;
        shift = (int8_t)(c * PITCH - px0);
        for (r = 0; r < 8; r++) {
            nib = (r & 1) ? (g[r >> 1] & 15) : (g[r >> 1] >> 4);
            nib <<= 4;
            pat[r] |= shift >= 0 ? (nib >> shift) : (nib << -shift);
        }
    }
    memset(colr, style_color[tile_style[(uint16_t)row * 32 + tile]], 8);
    CopyRamToVram(pat, PATTBL + ((uint16_t)row * 32 + tile) * 8, 8);
    CopyRamToVram(colr, COLTBL + ((uint16_t)row * 32 + tile) * 8, 8);
}

static void s2_flush(void) {
    uint16_t n;
    for (n = 0; n < GRID_ROWS * 32; n++) {
        if (!(dirty[n >> 3] & (1 << (n & 7)))) continue;
        dirty[n >> 3] &= ~(1 << (n & 7));
        paint(n >> 5, n & 31);
    }
}

static void s2_cursor(uint8_t col, uint8_t row, uint8_t visible) {
    cursor_attr[0] = visible ? row * 8 - 1 : 0xD0;       /* 0xD0 ends the list */
    cursor_attr[1] = col * PITCH;
    cursor_attr[2] = 0;
    cursor_attr[3] = 11;                                 /* light yellow */
    cursor_attr[4] = 0xD0;
    CopyRamToVram(cursor_attr, SPRATR, 5);
}

static uint8_t s2_open(void) {
    static const uint8_t underline[8] = {0, 0, 0, 0, 0, 0, 0, 0xF0};
    uint8_t ramp[256];
    uint16_t i;
    Screen(2);
    SetColors(15, 1, 1);
    /* 8x8 unmagnified sprites; display blank while the tiles are written. */
    *(uint8_t *)0xF3E0 &= 0xBC;
    VDPwrite(1, *(uint8_t *)0xF3E0);
    for (i = 0; i < 256; i++) ramp[i] = (uint8_t)i;
    for (i = 0; i < 3; i++) CopyRamToVram(ramp, NAMTBL + i * 256, 256);
    vram_fill(PATTBL, 0, 6144);
    vram_fill(COLTBL, style_color[UI_TEXT], 6144);
    CopyRamToVram((void *)underline, SPRPAT, 8);
    memset(cell, ' ', sizeof(cell));
    memset(tile_style, UI_TEXT, sizeof(tile_style));
    memset(dirty, 0, sizeof(dirty));
    s2_cursor(0, 0, 0);
    *(uint8_t *)0xF3E0 |= 0x40;
    VDPwrite(1, *(uint8_t *)0xF3E0);
    return 1;
}

static void s2_close(void) {
    s2_cursor(0, 0, 0);
    Screen(0);
    Cls();
}
