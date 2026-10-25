/*
 * MSX Free Chat - IRC chat client for the MSXPi (MSX1 build).
 *
 * The MSXPi server (msxpi_chat.py, command "mchat") holds the IRC
 * connection, the rooms, the scrollback and the user lists, and wraps every
 * line to this screen's width; this program only draws what the server hands
 * over and sends what is typed. All drawing goes through mchat_ui.h, so the
 * display backend can be replaced (MSX2 modes, another screen mode) without
 * touching this file.
 *
 *   MCHAT [/1] [/t] [nick]   ESC quits; /1 MSX1 screen on an MSX2; with an MSXPi the chat runs through it, without
 *                            one over TCP/IP UNAPI, and /t forces TCP/IP even when there is an MSXPi
 *   TAB, LEFT/RIGHT    next/previous room       UP/DOWN  read older/newer
 *   HOME               back to the latest       /help    commands
 *
 * Packet layouts are documented in msxpi_chat.py.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "../../C-common/header/fusion.h"
#include "../../C-common/header/msxpi.h"
#include "mchat_ui.h"

/* A key is in the BIOS buffer (PUTPNT != GETPNT): painting stops early to serve it. */
#define KEY_WAITING (*(volatile uint16_t *)0xF3F8 != *(volatile uint16_t *)0xF3FA)

/* Shift rows row..row+height-1 of a grid of 'stride' bytes a row, in columns col..col+width-1, up (delta > 0:
 * row r+delta becomes row r) or down by |delta| rows; the vacated rows get 'fill'. Shared by the backends'
 * ui_scroll() for their shadow grids. */
static void grid_move(uint8_t *g, uint8_t stride, uint8_t col, uint8_t row, uint8_t width, uint8_t height, int8_t delta, uint8_t fill) {
    uint8_t d = delta < 0 ? -delta : delta, n, i;
    uint8_t *dst, *src;
    if (d > height) d = height;
    n = height - d;
    g += col;
    for (i = 0; i < row; i++) g += stride;
    if (delta > 0) {
        dst = g;
        src = g;
        for (i = 0; i < d; i++) src += stride;
        for (i = 0; i < n; i++, dst += stride, src += stride) memmove(dst, src, width);
        for (i = 0; i < d; i++, dst += stride) memset(dst, fill, width);
    } else {
        dst = g;
        for (i = 1; i < height; i++) dst += stride;
        src = dst;
        for (i = 0; i < d; i++) src -= stride;
        for (i = 0; i < n; i++, dst -= stride, src -= stride) memmove(dst, src, width);
        for (i = 0; i < d; i++, dst -= stride) memset(dst, fill, width);
    }
}

/* Fills VRAM with block copies (FillVram() is not used: see mchat_ui_s6.c). */
static void vram_fill(uint16_t addr, uint8_t value, uint16_t len) {
    uint8_t block[256];
    uint16_t n;
    memset(block, value, sizeof(block));
    for (n = 0; n < len; n += 256) CopyRamToVram(block, addr + n, len - n < 256 ? len - n : 256);
}

/* The backends; see mchat_ui.h. ui_*() calls the one chosen in ui_mode. */
uint8_t ui_mode = UI_MSX1;
uint8_t ui_cols, ui_rows, ui_side;
#include "mchat_ui_s2.c"
#include "mchat_ui_s6.c"

void ui_text(uint8_t col, uint8_t row, const char *s, uint8_t width, uint8_t style) {
    if (ui_mode == UI_MSX2) s6_text(col, row, s, width, style);
    else s2_text(col, row, s, width, style);
}
void ui_scroll(uint8_t col, uint8_t row, uint8_t width, uint8_t height, int8_t delta) {
    if (ui_mode == UI_MSX2) s6_scroll(col, row, width, height, delta);
    else s2_scroll(col, row, width, height, delta);
}
uint8_t ui_flush(void) {
    return ui_mode == UI_MSX2 ? s6_flush() : s2_flush();
}
void ui_cursor(uint8_t col, uint8_t row, uint8_t visible) {
    if (ui_mode == UI_MSX2) s6_cursor(col, row, visible); else s2_cursor(col, row, visible);
}
uint8_t ui_open(void) {
    uint8_t ok;
    if (ui_mode == UI_MSX2) {ok = s6_open(); ui_cols = S6_COLS; ui_rows = S6_ROWS; ui_side = 16;}
    else {ok = s2_open(); ui_cols = GRID_COLS; ui_rows = GRID_ROWS; ui_side = 8;}
    return ok;
}
void ui_close(void) {
    if (ui_mode == UI_MSX2) s6_close(); else s2_close();
}

#define MAXR 4
#define VR_MAX 23               /* chat rows on screen (ui_rows - 3) */
#define TW_MAX 72               /* widest chat line the server may send */
#define HDR 24
#define UMAX 24
#define MAX_INPUT 100
#define POLL_TICKS 90

static uint8_t reply[256];
static uint8_t cw, vr;          /* chat width and chat rows */

/* Server state, as of the last reply. */
static uint8_t conn, nrooms, cur, meta_ver, meta_stale = 1;
static char rname[MAXR][12];
static char mynick[12];
static uint16_t rnext[MAXR], rseen[MAXR];
static char ulist[UMAX][12];
static uint8_t ushown;
static uint8_t usel = 0xFF;     /* highlighted user while picking a player (Ctrl-U), 0xFF = not picking */
static uint16_t utotal;
static char note[48];

/* Games: the server decides when one is ready (header byte 22) and gives the MSX-DOS command line that
 * starts it (reply to "mchat launch"). The client knows nothing about any game: it leaves the chat
 * running on the server, types the line into the keyboard buffer and returns to MSX-DOS; running MCHAT
 * again resumes the chat. */
#define GF_LAUNCH 1
#define GF_INVITED 2
#define KBUF_START 0xFBF0
#define KBUF_END 0xFC18
static uint8_t gflags, launching;
static char launch_cmd[40];

/* The visible window of the current room: row 'a' lives in slot a % vr. */
static uint16_t rabs[VR_MAX];
static uint8_t rkind[VR_MAX], rnick[VR_MAX];
static char rtext[VR_MAX][TW_MAX + 1];
static uint16_t top, first_abs, next_abs;

/* What the screen shows, so only what changed is composed (see draw_all). The log window is tracked by
 * row identity: drawn_abs[i] is the absolute row painted on screen row i (LOG_BLANK: blank, LOG_UNKNOWN:
 * not known), and rstale[slot] says the ring slot was stored or changed since it was drawn. */
#define LOG_BLANK 0xFFFD
#define LOG_UNKNOWN 0xFFFC
static uint16_t drawn_abs[VR_MAX], drawn_top;
static uint8_t rstale[VR_MAX];
static uint8_t log_full = 1;            /* repaint the whole log window */
static uint8_t side_dirty = 1;          /* user list changed */
static uint8_t in_from;                 /* first input character that changed, 0xFF: none */
static uint8_t drawn_ilen, drawn_skip;  /* what the input line shows */
static uint8_t flush_pending;           /* ui_flush() stopped early for a key */
static uint8_t live = 1;
static uint8_t ask_room;
static uint16_t ask_start;

static char input[MAX_INPUT + 1];
static uint8_t ilen;
static char cmd[MAX_INPUT + 16];

/* ------------------------------------------------------------ transport */

/* 0: commands go to the MSXPi server; 1: to local_exchange() over TCP/IP. */
static uint8_t link_tcp;
#include "mchat_local.c"

static uint8_t xchg(const char *c) {
    uint8_t rc, tries = 0;
    uint16_t size = 0;
    if (link_tcp) {
        if (local_exchange(c)) return 1;
        strcpy(note, "LINK ERROR - RETRYING");
        return 0;
    }
    msxpi_link_claim();
    rc = SendCommandToMSXPi(c, false);
    if (rc == RC_SUCCESS) rc = PerformHandshake(256);
    if (rc == RC_SUCCESS) {
        do { size = 0; rc = RECVDATA_ONEBLOCK(reply, &size, 256); }
        while (rc == RC_CHKSUM_ERR && ++tries < MAX_BLOCK_RETRIES);
    }
    msxpi_link_release();
    if (rc != RC_SUCCESS || size != 256 || memcmp(reply, "CHT1", 4)) {
        strcpy(note, "LINK ERROR - RETRYING");
        return 0;
    }
    return 1;
}

static char *put_num(char *p, uint16_t v) {
    char t[6];
    uint8_t n = 0;
    do { t[n++] = '0' + v % 10; v /= 10; } while (v);
    while (n) *p++ = t[--n];
    *p = 0;
    return p;
}

static char *put_str(char *p, const char *s) {
    while (*s) *p++ = *s++;
    *p = 0;
    return p;
}

static uint16_t u16(const uint8_t *p) { return p[0] | (p[1] << 8); }

/* -------------------------------------------------------------- parsing */

static void ring_clear(void) {
    uint8_t i;
    log_full = 1;
    for (i = 0; i < VR_MAX; i++) rabs[i] = 0xFFFF;
}

static void follow(void) {
    top = next_abs > vr ? next_abs - vr : 0;
    if (top < first_abs) top = first_abs;
}

/* An 'M' reply: counts for every room, and rows of the room asked about. */
static uint8_t parse_m(void) {
    uint8_t i, n, slot, slotsize = 2 + cw;
    uint16_t first, a;
    conn = reply[4];
    if (conn >= 3) {                      /* error or no session */
        memcpy(note, reply + HDR + 2, 47);
        note[47] = 0;
        return 0;
    }
    gflags = reply[22];
    if (reply[6] < nrooms) for (i = 0; i < MAXR; i++) rseen[i] = u16(reply + 12 + i * 2);
    nrooms = reply[6];
    for (i = 0; i < nrooms; i++) rnext[i] = u16(reply + 12 + i * 2);
    if (reply[20] != meta_ver) {meta_ver = reply[20]; meta_stale = 1;}
    if (reply[21] != cur) {
        cur = reply[21];
        ring_clear();
        live = 1;
        rseen[cur] = rnext[cur];
    }
    if (ask_room != cur) return 1;
    first = u16(reply + 8);
    first_abs = first;
    next_abs = u16(reply + 10);
    if (live) follow();
    else if (top < first_abs) top = first_abs;
    n = reply[7];
    a = ask_start > first ? ask_start : first;
    for (i = 0; i < n; i++, a++) {
        if (a < top || a >= top + vr) continue;
        slot = a % vr;
        if (rabs[slot] != a || rkind[slot] != reply[HDR + i * slotsize]
            || memcmp(rtext[slot], reply + HDR + i * slotsize + 2, cw)) rstale[slot] = 1;
        rabs[slot] = a;
        rkind[slot] = reply[HDR + i * slotsize];
        rnick[slot] = reply[HDR + i * slotsize + 1];
        memcpy(rtext[slot], reply + HDR + i * slotsize + 2, cw);
        rtext[slot][cw] = 0;
    }
    return 1;
}

static uint8_t get_rows(uint16_t from) {
    char *p = put_str(cmd, "mchat get ");
    p = put_num(p, cur);
    *p++ = ' ';
    put_num(p, from);
    if (!xchg(cmd)) return 0;
    ask_room = cur;
    ask_start = from;
    return parse_m();
}

/* Fetch whatever part of the window the ring does not hold yet. */
static void cache_fill(void) {
    uint16_t a = top, end = top + vr, first;
    uint8_t guard = 0;
    if (end > next_abs) end = next_abs;
    while (a < end && guard++ < 12) {
        if (rabs[a % vr] == a) {a++; continue;}
        if (!get_rows(a) || !reply[7]) break;
        first = u16(reply + 8);
        a = (a > first ? a : first) + reply[7];
    }
}

static void fetch_meta(void) {
    uint8_t i, got = 0, shown = 0;
    uint16_t from = 0;
    do {
        char *p = put_str(cmd, "mchat meta ");
        put_num(p, from);
        if (!xchg(cmd) || reply[5] != 'U') return;
        conn = reply[4];
        nrooms = reply[6];
        if (reply[7] != cur) return;           /* a room change is pending */
        utotal = u16(reply + 8);
        got = reply[10];
        memcpy(mynick, reply + 12, 11);
        mynick[11] = 0;
        for (i = 0; i < nrooms; i++) {
            memcpy(rname[i], reply + 24 + i * 12, 11);
            rname[i][11] = 0;
        }
        for (i = 0; i < got && shown < UMAX; i++, shown++) {
            memcpy(ulist[shown], reply + 72 + i * 12, 11);
            ulist[shown][11] = 0;
        }
        from += got;
    } while (got == 15 && from < utotal && shown < UMAX);
    ushown = shown;
    side_dirty = 1;
    if (usel != 0xFF && usel >= ushown) usel = ushown ? ushown - 1 : 0xFF;
    meta_stale = 0;
}

/* ------------------------------------------------------------- drawing */

static void draw_tabs(void) {
    uint8_t i, col = 0, len, style;
    for (i = 0; i < nrooms && col < ui_cols; i++) {
        len = strlen(rname[i]);
        style = i == cur ? UI_TAB_ON : (rnext[i] != rseen[i] ? UI_TAB_NEW : UI_TAB);
        ui_text(col, 0, rname[i], len, style);
        col += len;
        ui_text(col, 0, " ", 1, UI_TAB);
        col++;
    }
    if (col < ui_cols) ui_text(col, 0, "", ui_cols - col, UI_TAB);
}

static void draw_side(void) {
    uint8_t i;
    char head[12], *p;
    p = put_str(head, "USERS ");
    put_num(p, utotal);
    ui_text(0, 1, head, ui_side, UI_SIDE_HEAD);
    for (i = 0; i + 1 < vr; i++)
        ui_text(0, 2 + i, i < ushown ? ulist[i] : "", ui_side, i == usel ? UI_TAB_ON : UI_SIDE);
}

/* The log window: rows whose identity is already on screen are not composed again, and when 'top'
 * moved by less than a window the screen is scrolled and only the vacated rows are painted. */
static void draw_log(void) {
    uint8_t i, slot, d;
    uint16_t a;
    int16_t delta = (int16_t)(top - drawn_top);
    if (log_full || delta >= vr || delta <= -(int16_t)vr) {
        for (i = 0; i < VR_MAX; i++) drawn_abs[i] = LOG_UNKNOWN;
        log_full = 0;
    } else if (delta) {
        d = delta < 0 ? -delta : delta;
        ui_scroll(ui_side, 1, cw, vr, (int8_t)delta);
        if (delta > 0) {
            memmove(drawn_abs, drawn_abs + d, (vr - d) * 2);
            for (i = vr - d; i < vr; i++) drawn_abs[i] = LOG_BLANK;
        } else {
            memmove(drawn_abs + d, drawn_abs, (vr - d) * 2);
            for (i = 0; i < d; i++) drawn_abs[i] = LOG_BLANK;
        }
    }
    drawn_top = top;
    for (i = 0; i < vr; i++) {
        a = top + i;
        slot = a % vr;
        if (a < next_abs && rabs[slot] == a) {
            if (drawn_abs[i] == a && !rstale[slot]) continue;
            ui_text(ui_side, 1 + i, rtext[slot], cw, rkind[slot] < UI_STATUS ? rkind[slot] : UI_TEXT);
            drawn_abs[i] = a;
        } else if (drawn_abs[i] != LOG_BLANK) {
            ui_text(ui_side, 1 + i, "", cw, UI_TEXT);
            drawn_abs[i] = LOG_BLANK;
        }
    }
    memset(rstale, 0, sizeof(rstale));
}

static void draw_status(void) {
    char line[64], *p = line;
    if (note[0]) p = put_str(p, note);
    else {
        p = put_str(p, mynick);
        *p++ = ' ';
        p = put_str(p, rname[cur]);
        p = put_str(p, conn == 1 ? "  " : "  CONNECTING ");
        if (usel != 0xFF) p = put_str(p, " PICK: UP/DOWN, ENTER=INVITE, ESC");
        else if (gflags & GF_INVITED) p = put_str(p, " GAME INVITE: /ACCEPT /DECLINE");
        else if (!live) p = put_str(p, " SCROLLED-HOME=LATEST");
        else if (conn == 1) p = put_str(p, " /HELP");
    }
    ui_text(0, vr + 1, line, ui_cols, UI_STATUS);
}

static void touch_in(uint8_t i) {
    if (i < in_from) in_from = i;
}

/* The input line from the first character that changed; all of it once it scrolls sideways. */
static void draw_input(void) {
    uint8_t shown = ui_cols - 3, skip = ilen > shown ? ilen - shown : 0, from = in_from, end;
    ui_text(0, vr + 2, ">", 1, UI_INPUT);
    if (skip || drawn_skip) {
        ui_text(1, vr + 2, input + skip, ui_cols - 1, UI_INPUT);
    } else {
        end = ilen > drawn_ilen ? ilen : drawn_ilen;
        if (from < end) ui_text(1 + from, vr + 2, input + from, end - from, UI_INPUT);
    }
    drawn_ilen = ilen;
    drawn_skip = skip;
    in_from = 0xFF;
    ui_cursor(1 + ilen - skip, vr + 2, 1);
}

/* Compose what may have changed and paint it. The tab and status rows are a few cells; the user list,
 * the log window and the input line are redrawn only when they changed. If a key is waiting, the
 * painting stops and goes on the next time (flush_pending). */
static void draw_all(void) {
    draw_tabs();
    if (side_dirty) {side_dirty = 0; draw_side();}
    draw_log();
    draw_status();
    if (in_from != 0xFF) draw_input();
    flush_pending = !ui_flush();
}

/* The screen is blank (new display mode): everything must be composed again. */
static void dirty_all(void) {
    log_full = 1;
    side_dirty = 1;
    in_from = 0;
    drawn_ilen = drawn_skip = 0;
}

/* ------------------------------------------------------------- actions */

/* Pick up new rows of the current room (and any meta change). */
static void poll(void) {
    char *p = put_str(cmd, "mchat get ");
    uint8_t before = conn;
    p = put_num(p, cur);
    *p++ = ' ';
    put_num(p, next_abs);
    ask_room = cur;
    ask_start = next_abs;
    if (!xchg(cmd)) return;
    note[0] = 0;
    if (!parse_m()) return;
    cache_fill();
    rseen[cur] = rnext[cur];
    if (meta_stale || before != conn) {fetch_meta();}
}

/* Picking a player (Ctrl-U, Up/Down, Enter): the input line becomes "/play NICK " so a game can be added
 * or Enter pressed again. The server picks its default game; the client knows no game by name. */
static void pick_start(void) {
    if (!ushown) {strcpy(note, "NOBODY TO INVITE"); return;}
    usel = 0;
    side_dirty = 1;
}

static void pick_key(uint8_t key) {
    const char *n;
    char *p;
    side_dirty = 1;
    if (key == 0x1E) {if (usel) usel--;}
    else if (key == 0x1F) {if (usel + 1 < ushown && usel + 2 < vr) usel++;}
    else if (key == 13) {
        n = ulist[usel];
        while (*n == '@' || *n == '%' || *n == '+') n++;
        if (!strcmp(n, mynick)) {strcpy(note, "THAT IS YOU"); usel = 0xFF; return;}
        p = put_str(input, "/play ");
        p = put_str(p, n);
        *p++ = ' ';
        *p = 0;
        ilen = p - input;
        touch_in(0);
        usel = 0xFF;
    }
    else usel = 0xFF;                   /* ESC, Ctrl-U again, anything else: back to typing */
}

/* A game is ready: fetch its command line. 1 = launch_cmd is set. */
static uint8_t fetch_launch(void) {
    if (!(gflags & GF_LAUNCH)) return 0;
    gflags &= ~GF_LAUNCH;
    if (!xchg("mchat launch") || reply[5] != 'L' || !reply[6]) return 0;
    memcpy(launch_cmd, reply + HDR, 39);
    launch_cmd[39] = 0;
    return launch_cmd[0] != 0;
}

/* Type "line<Enter>" into the BIOS keyboard buffer (40 bytes, get/put pointers at F3FA/F3F8),
 * dropping what was there, so MSX-DOS runs it as soon as it shows its prompt. */
static void type_ahead(const char *line) {
    uint16_t at = KBUF_START;
    char *b;
    *(volatile uint16_t *)0xF3FA = KBUF_START;
    for (;; line++) {
        b = (char *)at;
        *b = *line ? *line : 13;
        if (++at >= KBUF_END) at = KBUF_START;
        if (!*line) break;
    }
    *(volatile uint16_t *)0xF3F8 = at;
}

static void start_session(const char *nick) {
    char *p = put_str(cmd, "mchat start ");
    p = put_str(p, nick[0] ? nick : "-");
    *p++ = ' ';
    put_num(p, cw);
    if (!xchg(cmd)) return;
    ask_room = 0;
    ask_start = 0;
    cur = 0xFF;                       /* make parse_m reset the ring */
    parse_m();
    follow();
    fetch_meta();
    cache_fill();
}

static void switch_room(uint8_t i) {
    char *p;
    if (nrooms < 2) return;
    p = put_str(cmd, "mchat room ");
    put_num(p, i);
    if (!xchg(cmd)) return;
    ask_room = i;
    ask_start = 0xFFFF;
    parse_m();
    meta_stale = 1;
    cache_fill();
    fetch_meta();
}

static uint8_t machine;

static void layout(void) {
    cw = ui_cols - ui_side;
    if (cw > TW_MAX) cw = TW_MAX;
    vr = ui_rows - 3;
    if (vr > VR_MAX) vr = VR_MAX;
}

/* /screen: the other display mode (MSX2 only). The server wraps to a new
 * width and numbers its rows again, so the window is fetched afresh. */
static void switch_screen(void) {
    uint8_t i;
    ui_close();
    ui_mode = ui_mode == UI_MSX2 ? UI_MSX1 : UI_MSX2;
    ui_open();
    layout();
    ring_clear();
    dirty_all();
    start_session("");
    for (i = 0; i < MAXR; i++) rseen[i] = rnext[i];
}

static void send_input(void) {
    char *p;
    if (!ilen) return;
    if (!strcmp(input, "/quit") || !strcmp(input, "/exit")) {ilen = 0xFF; return;}
    if (!strcmp(input, "/screen")) {
        ilen = 0;
        input[0] = 0;
        touch_in(0);
        if (machine) switch_screen();
        else strcpy(note, "THIS IS AN MSX1: SCREEN 2 ONLY");
        return;
    }
    p = put_str(cmd, "mchat say ");
    put_str(p, input);
    ilen = 0;
    input[0] = 0;
    touch_in(0);
    if (!xchg(cmd)) return;
    note[0] = 0;
    ask_room = reply[21];
    ask_start = 0xFFFF;
    live = 1;
    parse_m();
    poll();
    meta_stale = 1;
}

static void scroll_log(int8_t dir) {
    uint16_t last = next_abs > vr ? next_abs - vr : 0;
    if (dir < 0) {
        top = top > first_abs + 5 ? top - 5 : first_abs;
        live = 0;
    } else {
        top += 5;
        if (top >= last) {live = 1; follow();}
    }
    cache_fill();
}

/* Command line: "[/1] [/t] [nick]". /1 forces the MSX1 screen on any machine,
 * /t talks to IRC over TCP/IP UNAPI even when there is an MSXPi; without an MSXPi TCP/IP is used anyway. */
static uint8_t force_msx1, auto_tcp;

static void read_args(char *dest) {
    uint8_t len = *(uint8_t *)0x80, n = 0, i = 0;
    char *s = (char *)0x81, c;
    dest[0] = 0;
    force_msx1 = 0;
    link_tcp = 0;
    auto_tcp = 0;
    while (i < len) {
        while (i < len && s[i] == ' ') i++;
        if (i + 1 < len && s[i] == '/' && (s[i + 1] == '1' || s[i + 1] == 't' || s[i + 1] == 'T')) {
            if (s[i + 1] == '1') force_msx1 = 1; else link_tcp = 1;
            i += 2;
            continue;
        }
        for (n = 0; i < len && n < 15; i++) {
            c = s[i];
            if (c == ' ' || c < 33 || c > 126) break;
            dest[n++] = c;
        }
        dest[n] = 0;
        break;
    }
    if (!link_tcp && !msxpi_present()) link_tcp = auto_tcp = 1;
}

/* 0 on an MSX1, else 1: ask the BIOS for SCREEN 6, which only an MSX2 has;
 * SCRMOD (0xFCAF) says whether it took. The version bytes the BIOS offers
 * (MSXVER in ROM, EXBRSA in RAM) read as MSX2 on an MSX1 once MSR and
 * InterNestor Lite were loaded, so they cannot be trusted here. */
static uint8_t msx_version(void) {
    Screen(6);
    return *(volatile uint8_t *)0xFCAF == 6;
}

int main(void) {
    char nick[16];
    uint8_t key;
    uint16_t now, lastpoll;
    read_args(nick);
    net = 0;
    lt_seg = 0;                 /* tcp_link_stop frees it on the way out, over the MSXPi as well */
    machine = msx_version();
    ui_mode = (machine && !force_msx1) ? UI_MSX2 : UI_MSX1;
    /* No C runtime start-up here: nothing is zeroed for us. */
    conn = nrooms = cur = utotal = ushown = ilen = 0;
    meta_ver = 0; meta_stale = 1; live = 1;
    top = first_abs = next_abs = ask_start = 0; ask_room = 0;
    memset(rname, 0, sizeof(rname));
    memset(mynick, 0, sizeof(mynick));
    memset(ulist, 0, sizeof(ulist));
    memset(rnext, 0, sizeof(rnext));
    memset(rseen, 0, sizeof(rseen));
    memset(rkind, 0, sizeof(rkind));
    memset(rnick, 0, sizeof(rnick));
    memset(rtext, 0, sizeof(rtext));
    memset(rstale, 0, sizeof(rstale));
    drawn_top = 0;
    flush_pending = 0;
    memset(input, 0, sizeof(input));
    memset(note, 0, sizeof(note));
    gflags = launching = 0;
    usel = 0xFF;
    font6_loaded = 0;                  /* the S6 font is read from the BIOS once */
    if (link_tcp) {
        const char *why = tcp_link_start();
        if (why) {
            if (auto_tcp) Print("No MSXPi found. ");
            Print((char *)why); Print("\r\n"); return 1;
        }
    }
    if (!ui_open()) return 1;
    layout();
    ring_clear();
    strcpy(rname[0], "#MSXPI");
    strcpy(mynick, "...");
    strcpy(note, "CONNECTING...");
    dirty_all();
    draw_all();
    note[0] = 0;
    start_session(nick);
    draw_all();
    lastpoll = *(volatile uint16_t *)0xFC9E;
    for (;;) {
        key = Inkey();
        if (key) {
            if (note[0] && conn == 1) note[0] = 0;
            if (usel != 0xFF) {pick_key(key); draw_all(); continue;}
            if (key == 0x15) {pick_start(); draw_all(); continue;}
            if (key == 27) break;
            else if (key == 13) {send_input(); if (ilen == 0xFF) break;}
            else if (key == 8 || key == 127) {if (ilen) {input[--ilen] = 0; touch_in(ilen);}}
            else if (key == 9 || key == 0x1C) switch_room((cur + 1) % nrooms);
            else if (key == 0x1D) switch_room((cur + nrooms - 1) % nrooms);
            else if (key == 0x1E) scroll_log(-1);
            else if (key == 0x1F) scroll_log(1);
            else if (key == 0x0B) {live = 1; follow(); cache_fill();}
            else if (key >= 32 && key <= 126 && ilen < MAX_INPUT) {touch_in(ilen); input[ilen++] = key; input[ilen] = 0;}
            draw_all();
            continue;
        }
        now = *(volatile uint16_t *)0xFC9E;
        if ((uint16_t)(now - lastpoll) >= POLL_TICKS) {
            lastpoll = now;
            if (conn == 4) start_session("");
            else poll();
            draw_all();
            if (fetch_launch()) {launching = 1; break;}
        } else if (flush_pending) flush_pending = !ui_flush();
    }
    if (!launching) xchg("mchat quit");   /* a game start leaves the chat running on the server */
    tcp_link_stop();
    ui_close();
    if (launching) type_ahead(launch_cmd);
    return 0;
}
