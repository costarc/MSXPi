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
 * The screen is repainted from a shadow grid, only the span of cells that
 * changed in each row (8 lines of 3 bytes per pair of cells). The cursor is
 * the cell drawn with its colours swapped.
 */

#define S6_COLS 85
#define S6_ROWS 26
#define S6_PITCH 6

#define cell6(r) ((char *)ui_mem + (r) * S6_COLS)
/* fg*4+bg of each cell, two cells to a byte (the even cell in the high nibble): a row is 43 bytes. */
#define combo6(r) (ui_mem + S6_ROWS * S6_COLS + (r) * 43)
static uint8_t lo6[S6_ROWS], hi6[S6_ROWS];   /* dirty cell span of each row; lo6 = 0xFF: clean */
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

/* Per cell pair of the span being painted (cells 2p and 2p+1): the two glyphs and the two colour tables. */
struct pair6 {const uint8_t *fa, *fb, *ea, *eb;};
static struct pair6 pr6[43];
static const uint8_t blank8[8] = {0, 0, 0, 0, 0, 0, 0, 0};
static uint8_t *k_out;
static const struct pair6 *k_pp;
static uint8_t k_r, k_n, k_a, k_b;

static void mark6(uint8_t row, uint8_t c0, uint8_t c1) {
    if (lo6[row] > c0) lo6[row] = c0;
    if (hi6[row] < c1) hi6[row] = c1;
}

/* One scan line r of k_n pairs from k_pp into k_out, 3 bytes a pair:
 *   a = 6 pixels of the first glyph, b = of the second; n1 = the 4 pixels that straddle the two cells
 *   out0 = ea[a >> 2]   out1 = ea[n1] high nibble | eb[n1] low nibble   out2 = eb[b & 15] */
static void kern6(void) __naked {
__asm
    push ix
    ld   ix,(_k_pp)
    ld   de,(_k_out)
1$:
    ld   l,0(ix)
    ld   h,1(ix)
    ld   a,(_k_r)
    add  a,l
    ld   l,a
    jr   nc,2$
    inc  h
2$: ld   a,(hl)
    rrca
    rrca
    and  a,#0x3f
    ld   (_k_a),a
    ld   l,2(ix)
    ld   h,3(ix)
    ld   a,(_k_r)
    add  a,l
    ld   l,a
    jr   nc,3$
    inc  h
3$: ld   a,(hl)
    rrca
    rrca
    and  a,#0x3f
    ld   (_k_b),a
    and  a,#0x30
    rrca
    rrca
    rrca
    rrca
    ld   c,a
    ld   a,(_k_a)
    and  a,#0x03
    add  a,a
    add  a,a
    or   a,c
    ld   c,a
    ld   l,4(ix)
    ld   h,5(ix)
    ld   a,(_k_a)
    rrca
    rrca
    and  a,#0x0f
    add  a,l
    ld   l,a
    jr   nc,4$
    inc  h
4$: ld   a,(hl)
    ld   (de),a
    inc  de
    ld   l,4(ix)
    ld   h,5(ix)
    ld   a,c
    add  a,l
    ld   l,a
    jr   nc,5$
    inc  h
5$: ld   a,(hl)
    and  a,#0xf0
    ld   b,a
    ld   l,6(ix)
    ld   h,7(ix)
    ld   a,c
    add  a,l
    ld   l,a
    jr   nc,6$
    inc  h
6$: ld   a,(hl)
    and  a,#0x0f
    or   a,b
    ld   (de),a
    inc  de
    ld   l,6(ix)
    ld   h,7(ix)
    ld   a,(_k_b)
    and  a,#0x0f
    add  a,l
    ld   l,a
    jr   nc,7$
    inc  h
7$: ld   a,(hl)
    ld   (de),a
    inc  de
    ld   bc,#8
    add  ix,bc
    ld   hl,#_k_n
    dec  (hl)
    jp   nz,1$
    pop  ix
    ret
__endasm;
}

/* Paint cells c0..c1 of a text row: pairs of cells are 3 bytes, 8 scan lines, one VRAM write each. */
static void paint6(uint8_t row, uint8_t c0, uint8_t c1) {
    uint8_t line[129], r, p, p0 = c0 >> 1, p1 = c1 >> 1, c, sa, sb;
    const char *cr = cell6(row);
    const uint8_t *kr = combo6(row);
    uint8_t cursor_here = cur6_on && cur6_row == row;
    if (p1 > 42) p1 = 42;
    for (p = p0; p <= p1; p++) {
        c = p << 1;
        sa = kr[p] >> 4;
        if (cursor_here && cur6_col == c) sa = (sa << 2 | sa >> 2) & 15;
        pr6[p].fa = font6 + (uint8_t)(cr[c] - 32) * 8;
        pr6[p].ea = expand6 + sa * 16;
        if (c + 1 < S6_COLS) {
            sb = kr[p] & 15;
            if (cursor_here && cur6_col == c + 1) sb = (sb << 2 | sb >> 2) & 15;
            pr6[p].fb = font6 + (uint8_t)(cr[c + 1] - 32) * 8;
        } else {
            sb = sa;
            pr6[p].fb = blank8;
        }
        pr6[p].eb = expand6 + sb * 16;
    }
    k_out = line;
    k_pp = &pr6[p0];
    for (r = 0; r < 8; r++) {
        k_r = r;
        k_n = p1 - p0 + 1;
        kern6();
        /* The last pair (cells 84 and 85) has one byte more than the 128 of a scan line. */
        CopyRamToVram(line, (uint16_t)(row * 8 + r) * 128 + (uint16_t)p0 * 3, (p1 - p0 + 1) * 3 - (p1 == 42));
    }
}

static void s6_text(uint8_t col, uint8_t row, const char *s, uint8_t width, uint8_t style) {
    uint8_t i, combo = style6[style], lo = 0xFF, hi = 0, half, old;
    char c, *cp;
    uint8_t *kp;
    if (row >= S6_ROWS || col >= S6_COLS || !width) return;
    if (col + width > S6_COLS) width = S6_COLS - col;
    cp = (cell6(row) + col);
    kp = (combo6(row) + (col >> 1));
    half = col & 1;
    for (i = 0; i < width; i++, cp++) {
        c = *s ? *s++ : ' ';
        if (c < 32 || c > 126) c = '?';
        old = half ? *kp & 15 : *kp >> 4;
        if (*cp != c || old != combo) {
            *cp = c;
            *kp = half ? (*kp & 0xF0) | combo : (combo << 4) | (*kp & 15);
            if (lo == 0xFF) lo = i;
            hi = i;
        }
        if (half) kp++;
        half ^= 1;
    }
    if (lo != 0xFF) mark6(row, col + lo, col + hi);
}

static uint8_t hm_regs[15];

/* HMMM (VRAM to VRAM, byte aligned): loads R#32..R#46 from hm_regs, then waits for the command engine to
 * finish (S#2 bit 0). The BIOS interrupt expects status register 0 to be selected: R#15 goes back to 0. */
static void hmmm(void) __naked {
__asm
    di
    ld a,#32
    out (#0x99),a
    ld a,#0x91
    out (#0x99),a
    ld hl,#_hm_regs
    ld bc,#0x0F9B
    otir
    ei
1$:
    di
    ld a,#2
    out (#0x99),a
    ld a,#0x8F
    out (#0x99),a
    in a,(#0x99)
    ld b,a
    xor a
    out (#0x99),a
    ld a,#0x8F
    out (#0x99),a
    ei
    ld a,b
    rrca
    jr c,1$
    ret
__endasm;
}

static void put16(uint8_t *p, uint16_t v) {
    p[0] = v;
    p[1] = v >> 8;
}

static uint8_t flush_all6(void);

/* Move the cells of a rectangle (col must be even: the colours are two to a byte); with the command engine
 * the pixels move in one HMMM (the rectangle must start and end on a byte: 4 pixels), and only the vacated
 * rows are queued for painting. */
static void s6_scroll(uint8_t col, uint8_t row, uint8_t width, uint8_t height, int8_t delta) {
    uint8_t d = delta < 0 ? -delta : delta, r, keep, aligned;
    uint16_t x0, nx;
    if (row >= S6_ROWS || col >= S6_COLS || !width || !height || !delta) return;
    if (row + height > S6_ROWS) height = S6_ROWS - row;
    if (col + width > S6_COLS) width = S6_COLS - col;
    flush_all6();                                       /* what is queued must be in VRAM before it moves */
    if (d > height) d = height;
    keep = height - d;
    grid_move(cell6(0), S6_COLS, col, row, width, height, delta, ' ');
    grid_move(combo6(0), 43, col >> 1, row, (width + 1) >> 1, height, delta, style6[UI_TEXT] * 17);
    x0 = (uint16_t)col * S6_PITCH;
    nx = col + width == S6_COLS ? 512 - x0 : (uint16_t)width * S6_PITCH;
    aligned = keep && !(x0 & 3) && !(nx & 3);
    if (aligned) {
        put16(hm_regs, x0);
        put16(hm_regs + 4, x0);
        put16(hm_regs + 8, nx);
        put16(hm_regs + 10, (uint16_t)keep * 8);
        hm_regs[12] = 0;
        hm_regs[14] = 0xD0;
        if (delta > 0) {
            put16(hm_regs + 2, (uint16_t)(row + d) * 8);
            put16(hm_regs + 6, (uint16_t)row * 8);
            hm_regs[13] = 0;
        } else {
            put16(hm_regs + 2, (uint16_t)(row + keep) * 8 - 1);      /* bottom line first, going up */
            put16(hm_regs + 6, (uint16_t)(row + keep + d) * 8 - 1);
            hm_regs[13] = 0x08;
        }
        hmmm();
    }
    for (r = 0; r < height; r++)
        if (!aligned || (delta > 0 ? r >= keep : r < d)) mark6(row + r, col, col + width - 1);
}

static uint8_t flush_rows6(uint8_t abortable) {
    uint8_t row, lo, hi;
    for (row = 0; row < S6_ROWS; row++) {
        lo = lo6[row];
        if (lo == 0xFF) continue;
        hi = hi6[row];
        lo6[row] = 0xFF;
        hi6[row] = 0;
        paint6(row, lo, hi);
        if (abortable && KEY_WAITING) return 0;
    }
    return 1;
}

static uint8_t flush_all6(void) {return flush_rows6(0);}
static uint8_t s6_flush(void) {return flush_rows6(1);}

static void s6_cursor(uint8_t col, uint8_t row, uint8_t visible) {
    if (cur6_on && cur6_row < S6_ROWS) mark6(cur6_row, cur6_col, cur6_col);
    cur6_col = col; cur6_row = row; cur6_on = visible;
    if (visible && row < S6_ROWS && col < S6_COLS) mark6(row, col, col);
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
    memset(cell6(0), ' ', S6_ROWS * S6_COLS);
    memset(combo6(0), style6[UI_TEXT] * 17, S6_ROWS * 43);
    memset(lo6, 0xFF, sizeof(lo6));
    memset(hi6, 0, sizeof(hi6));
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
