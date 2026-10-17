/*
 * MSX Free Chat - MSX2 display backend (V9938 SCREEN 6). See mchat_ui.h.
 *
 * SCREEN 6 is 512x212 with 4 colours (2 bits a pixel), which fits 64 KB of
 * VRAM. The BIOS 8x8 font (copied from SCREEN 1 at start) is drawn on a 6
 * pixel pitch: 85 columns and 26 rows, the look of SCREEN 0 in 80 columns
 * but with a colour per cell. There is no tile clash here: every cell has its
 * own style, so ui_side only says how wide the user list is.
 *
 * Palette: 0 black, 1 white, 2 yellow, 3 blue (colour 0 is shown, not transparent). With four colours the styles
 * differ less than on MSX1: your own lines are plain white and system lines
 * are blue.
 *
 * The screen is repainted a text row at a time (8 lines of 128 bytes) from a
 * shadow grid, only for the rows that changed. The cursor is the cell drawn
 * with its colours swapped.
 */

#define S6_COLS 85
#define S6_ROWS 26
#define S6_PITCH 6

static char cell6[S6_ROWS][S6_COLS];
static uint8_t combo6[S6_ROWS][S6_COLS];     /* fg*4+bg of each cell */
static uint8_t row_dirty6[S6_ROWS];
static uint8_t cur6_col, cur6_row, cur6_on;
static uint8_t expand6[16 * 16];             /* [fg*4+bg][4 pixel bits] -> byte */
static uint8_t font6[96 * 8];
static uint8_t font6_loaded;
static uint8_t pal_idx, pal_rb, pal_g;

/* fg<<2 | bg, colours 0 black 1 white 2 yellow 3 blue. */
static const uint8_t style6[UI_STYLES] = {
    (1 << 2) | 0,   /* TEXT      white on black */
    (2 << 2) | 0,   /* PRIV      yellow */
    (3 << 2) | 0,   /* SYSTEM    blue */
    (1 << 2) | 0,   /* OWN       white */
    (2 << 2) | 0,   /* ACTION    yellow */
    (2 << 2) | 0,   /* PRIVOUT   yellow */
    (0 << 2) | 1,   /* STATUS    black on white */
    (1 << 2) | 3,   /* SIDE      white on blue */
    (2 << 2) | 3,   /* SIDE_HEAD yellow on blue */
    (1 << 2) | 3,   /* TAB       white on blue */
    (0 << 2) | 1,   /* TAB_ON    black on white */
    (0 << 2) | 2,   /* TAB_NEW   black on yellow */
    (1 << 2) | 0    /* INPUT     white on black */
};

/* Write palette entry pal_idx from pal_rb (red<<4 | blue) and pal_g. */
static void write_palette(void) __naked {
__asm
    ld a,(_pal_idx)
    di
    out (#0x99),a
    ld a,#0x90
    out (#0x99),a
    ld a,(_pal_rb)
    out (#0x9A),a
    ld a,(_pal_g)
    out (#0x9A),a
    ei
    ret
__endasm;
}

static void set_pal(uint8_t idx, uint8_t rb, uint8_t g) {
    pal_idx = idx; pal_rb = rb; pal_g = g;
    write_palette();
}

static void paint6(uint8_t row) {
    uint8_t line[129], r, p, c, ca, cb, sa, sb, a, b, n1;
    uint8_t *out;
    for (r = 0; r < 8; r++) {
        out = line;
        for (p = 0; p < 43; p++) {
            c = p * 2;
            ca = cell6[row][c];
            sa = combo6[row][c];
            if (cur6_on && cur6_row == row && cur6_col == c) sa = (sa << 2 | sa >> 2) & 15;
            if (c + 1 < S6_COLS) {
                cb = cell6[row][c + 1];
                sb = combo6[row][c + 1];
                if (cur6_on && cur6_row == row && cur6_col == c + 1) sb = (sb << 2 | sb >> 2) & 15;
            } else {
                cb = ' ';
                sb = sa;
            }
            a = (ca >= 32 && ca <= 126) ? font6[(ca - 32) * 8 + r] >> 2 : 0;
            b = (cb >= 32 && cb <= 126) ? font6[(cb - 32) * 8 + r] >> 2 : 0;
            n1 = ((a & 3) << 2) | (b >> 4);
            out[0] = expand6[sa * 16 + (a >> 2)];
            out[1] = (expand6[sa * 16 + n1] & 0xF0) | (expand6[sb * 16 + n1] & 0x0F);
            out[2] = expand6[sb * 16 + (b & 15)];
            out += 3;
        }
        CopyRamToVram(line, (uint16_t)(row * 8 + r) * 128, 128);
    }
}

static void s6_text(uint8_t col, uint8_t row, const char *s, uint8_t width, uint8_t style) {
    uint8_t i, combo = style6[style];
    char c;
    if (row >= S6_ROWS || col >= S6_COLS || !width) return;
    if (col + width > S6_COLS) width = S6_COLS - col;
    for (i = 0; i < width; i++) {
        c = *s ? *s++ : ' ';
        if (c < 32 || c > 126) c = '?';
        if (cell6[row][col + i] != c || combo6[row][col + i] != combo) {
            cell6[row][col + i] = c;
            combo6[row][col + i] = combo;
            row_dirty6[row] = 1;
        }
    }
}

static void s6_flush(void) {
    uint8_t row;
    for (row = 0; row < S6_ROWS; row++)
        if (row_dirty6[row]) {row_dirty6[row] = 0; paint6(row);}
}

static void s6_cursor(uint8_t col, uint8_t row, uint8_t visible) {
    if (cur6_on && cur6_row < S6_ROWS) row_dirty6[cur6_row] = 1;
    cur6_col = col; cur6_row = row; cur6_on = visible;
    if (visible && row < S6_ROWS) row_dirty6[row] = 1;
}

static uint8_t s6_open(void) {
    uint8_t fg, bg, nib, k, pix;
    if (!font6_loaded) {                    /* the BIOS font lives in SCREEN 1's VRAM */
        Screen(1);
        CopyVramToRam(32 * 8, font6, sizeof(font6));
        font6_loaded = 1;
    }
    Screen(6);
    set_pal(0, 0x00, 0);
    set_pal(1, 0x77, 7);
    set_pal(2, 0x70, 7);
    set_pal(3, 0x26, 3);
    /* Colour 0 is "transparent" unless R#8 bit 5 is set: it then shows the
     * backdrop, which SCREEN 6 draws as a stripe of two palette colours. Show
     * palette 0 (black) instead, and make the backdrop black as well. */
    *(uint8_t *)0xFFE7 |= 0x20;
    VDPwrite(8, *(uint8_t *)0xFFE7);
    *(uint8_t *)0xF3E6 = 0;
    VDPwrite(7, 0);
    vram_fill(0, 0, 27136);
    for (fg = 0; fg < 4; fg++)
        for (bg = 0; bg < 4; bg++)
            for (nib = 0; nib < 16; nib++) {
                pix = 0;
                for (k = 0; k < 4; k++) pix |= ((nib >> (3 - k)) & 1 ? fg : bg) << (6 - 2 * k);
                expand6[(fg * 4 + bg) * 16 + nib] = pix;
            }
    memset(cell6, ' ', sizeof(cell6));
    memset(combo6, style6[UI_TEXT], sizeof(combo6));
    memset(row_dirty6, 0, sizeof(row_dirty6));
    cur6_on = 0;
    return 1;
}

static void s6_close(void) {
    set_pal(1, 0x00, 0);                   /* back to the BIOS defaults we changed */
    set_pal(2, 0x11, 6);
    set_pal(3, 0x33, 7);
    Screen(0);
    Cls();
}
