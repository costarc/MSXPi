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

/* The backends never run together, so they share the memory of their shadow grids: here the 51x24 cells and
 * the style of each tile, in mchat_ui_s6.c the 85x26 cells and their colours (a nibble each). */
static uint8_t ui_mem[85 * 26 + 26 * 43];
#define cell(r) ((char *)ui_mem + (r) * GRID_COLS)
#define tile_style (ui_mem + GRID_ROWS * GRID_COLS)
static uint8_t dirty[GRID_ROWS * 4];        /* one bit a tile: pattern to repaint */
static uint8_t cdirty[GRID_ROWS * 4];       /* same: colour to rewrite (the style changed) */
static uint8_t sh_tab[12][16];              /* [shift+4][nibble]: the glyph nibble in the high half, shifted */
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

static const uint8_t bit_of[8] = {1, 2, 4, 8, 16, 32, 64, 128};

static void mark_tiles(uint8_t *map, uint8_t row, uint8_t t0, uint8_t t1) {
    uint8_t *m = map + row * 4;
    for (; t0 <= t1; t0++) m[t0 >> 3] |= bit_of[t0 & 7];
}

static void s2_text(uint8_t col, uint8_t row, const char *s, uint8_t width, uint8_t style) {
    uint8_t i, lo = 0xFF, hi = 0, t, t1;
    uint8_t *ts;
    char c, *cp;
    if (row >= GRID_ROWS || col >= GRID_COLS || !width) return;
    if (col + width > GRID_COLS) width = GRID_COLS - col;
    /* Only what changed is queued: composing a whole screen costs nothing. */
    cp = (cell(row) + col);
    for (i = 0; i < width; i++, cp++) {
        c = *s ? *s++ : ' ';
        if (c < 32 || c > 126) c = '?';
        if (*cp != c) {
            *cp = c;
            if (lo == 0xFF) lo = i;
            hi = i;
        }
    }
    if (lo != 0xFF)
        mark_tiles(dirty, row, ((uint16_t)(col + lo) * PITCH) >> 3, ((uint16_t)(col + hi) * PITCH + 3) >> 3);
    ts = tile_style + row * 32;
    t1 = ((uint16_t)(col + width) * PITCH - 1) >> 3;
    for (t = ((uint16_t)col * PITCH) >> 3; t <= t1; t++)
        if (ts[t] != style) {
            ts[t] = style;
            mark_tiles(cdirty, row, t, t);
        }
}

static uint8_t flush_all2(void);

/* Move the cells of a rectangle, and their tiles in VRAM (patterns and colours, a few hundred bytes a
 * text row, VRAM to RAM to VRAM); only the vacated rows are queued for painting. */
static void s2_scroll(uint8_t col, uint8_t row, uint8_t width, uint8_t height, int8_t delta) {
    uint8_t d = delta < 0 ? -delta : delta, i, r, t0, t1, from, n;
    uint8_t buf[256];
    uint16_t at;
    if (row >= GRID_ROWS || col >= GRID_COLS || !width || !height || !delta) return;
    if (row + height > GRID_ROWS) height = GRID_ROWS - row;
    if (col + width > GRID_COLS) width = GRID_COLS - col;
    flush_all2();                                       /* what is queued must be in VRAM before it moves */
    t0 = ((uint16_t)col * PITCH) >> 3;
    t1 = ((uint16_t)(col + width) * PITCH - 1) >> 3;
    n = t1 - t0 + 1;
    grid_move(cell(0), GRID_COLS, col, row, width, height, delta, ' ');
    grid_move(tile_style, 32, t0, row, n, height, delta, UI_TEXT);
    for (i = 0; i < height; i++) {
        r = delta > 0 ? i : height - 1 - i;             /* destination, in an order that reads before it writes */
        from = delta > 0 ? r + d : r - d;               /* source: an offset in the rectangle, may be outside */
        if (from >= height) {
            mark_tiles(dirty, row + r, t0, t1);
            mark_tiles(cdirty, row + r, t0, t1);
            continue;
        }
        at = (uint16_t)((row + from) * 32 + t0) * 8;
        CopyVramToRam(PATTBL + at, buf, n * 8);
        CopyRamToVram(buf, PATTBL + (uint16_t)((row + r) * 32 + t0) * 8, n * 8);
        CopyVramToRam(COLTBL + at, buf, n * 8);
        CopyRamToVram(buf, COLTBL + (uint16_t)((row + r) * 32 + t0) * 8, n * 8);
    }
}

/* Paint one tile: pixel columns tile*8 .. tile*8+7 of text row 'row'; the colours only if asked. */
static void paint(uint8_t row, uint8_t tile, uint8_t with_pattern, uint8_t with_colour) {
    uint8_t pat[8], colr[8], c, c0, c1, ch, k;
    uint16_t px0 = (uint16_t)tile * 8;
    const uint8_t *g, *tp;
    uint16_t at = (uint16_t)row * 32 + tile;
    if (with_pattern) {
        memset(pat, 0, 8);
        c0 = px0 / PITCH;
        c1 = (px0 + 7) / PITCH;
        for (c = c0; c <= c1 && c < GRID_COLS; c++) {
            ch = cell(row)[c];
            if (ch == ' ') continue;
            g = mchat_font + (ch - 32) * 4;
            tp = sh_tab[(int16_t)((uint16_t)c * PITCH - px0) + 4];
            for (k = 0; k < 4; k++) {
                pat[k * 2] |= tp[g[k] >> 4];
                pat[k * 2 + 1] |= tp[g[k] & 15];
            }
        }
        CopyRamToVram(pat, PATTBL + at * 8, 8);
    }
    if (with_colour) {
        memset(colr, style_color[tile_style[at]], 8);
        CopyRamToVram(colr, COLTBL + at * 8, 8);
    }
}

static uint8_t flush_rows2(uint8_t abortable) {
    uint8_t row, byte, bit, p, c, v, *dp, *cp;
    for (row = 0; row < GRID_ROWS; row++) {
        dp = dirty + row * 4;
        cp = cdirty + row * 4;
        for (byte = 0; byte < 4; byte++) {
            v = dp[byte] | cp[byte];
            if (!v) continue;
            for (bit = 0; bit < 8; bit++) {
                if (!(v & bit_of[bit])) continue;
                p = dp[byte] & bit_of[bit];
                c = cp[byte] & bit_of[bit];
                dp[byte] &= ~bit_of[bit];
                cp[byte] &= ~bit_of[bit];
                paint(row, byte * 8 + bit, p, c);
                if (abortable && KEY_WAITING) return 0;
            }
        }
    }
    return 1;
}

static uint8_t flush_all2(void) {return flush_rows2(0);}
static uint8_t s2_flush(void) {return flush_rows2(1);}

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
    uint8_t ramp[256], n;
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
    memset(cell(0), ' ', GRID_ROWS * GRID_COLS);
    memset(tile_style, UI_TEXT, GRID_ROWS * 32);
    memset(dirty, 0, sizeof(dirty));
    memset(cdirty, 0, sizeof(cdirty));
    for (i = 0; i < 12; i++)
        for (n = 0; n < 16; n++) sh_tab[i][n] = i >= 4 ? (n << 4) >> (i - 4) : (uint8_t)(n << (8 - i));
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
