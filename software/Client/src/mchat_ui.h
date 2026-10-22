/*
 * MSX Free Chat - display contract.
 *
 * mchat.c draws only through this interface, in character cells. It never
 * touches the VDP, so the same mchat.c runs on any backend:
 *   mchat_ui_s2.c  MSX1 SCREEN 2, software 4x8 font, 51 x 24 cells
 *   mchat_ui_s6.c  MSX2 SCREEN 6, BIOS font on a 6 pixel pitch, 85 x 26 cells
 * Both are in the one binary; ui_mode picks one (mchat.c dispatches).
 * and a backend may be swapped at run time: call ui_close(), then the other
 * backend's ui_open(), read ui_cols/ui_rows/ui_side again and redraw all.
 *
 * Nothing is drawn until ui_flush(), so a screen can be composed in any
 * order. The backend may not be able to colour every cell independently
 * (SCREEN 2 colours whole 8-pixel tiles): ui_side is the column where the
 * left-hand panel ends and a new style may start without a clash. A text
 * call that crosses a style boundary elsewhere recolours the shared tile.
 */
#ifndef MCHAT_UI_H
#define MCHAT_UI_H

enum {
    UI_TEXT,        /* chat text */
    UI_PRIV,        /* private message in */
    UI_SYSTEM,      /* joins, parts, errors, help */
    UI_OWN,         /* what you said */
    UI_ACTION,      /* /me */
    UI_PRIVOUT,     /* private message out */
    UI_STATUS,      /* status bar */
    UI_SIDE,        /* user list */
    UI_SIDE_HEAD,   /* user list heading */
    UI_TAB,         /* room tab */
    UI_TAB_ON,      /* current room tab */
    UI_TAB_NEW,     /* room tab with unread messages */
    UI_INPUT,       /* input line */
    UI_STYLES
};

enum { UI_MSX1 = 1, UI_MSX2 = 2 };
extern uint8_t ui_mode;            /* choose before ui_open(); one binary holds both */
extern uint8_t ui_cols, ui_rows;   /* size of the cell grid, set by ui_open() */
extern uint8_t ui_side;            /* suggested width of the left panel, same */

uint8_t ui_open(void);             /* enter the mode; 0 if this machine can't */
void ui_close(void);               /* leave it (text mode, cursor hidden) */

/* Write exactly 'width' cells at (col,row): s padded with blanks, or cut. */
void ui_text(uint8_t col, uint8_t row, const char *s, uint8_t width, uint8_t style);
/* Move the cells of a rectangle up (delta > 0: row r+delta becomes row r) or down (delta < 0) by |delta|
 * rows. The vacated rows read as blanks in UI_TEXT style and need no ui_text() to be correct. */
void ui_scroll(uint8_t col, uint8_t row, uint8_t width, uint8_t height, int8_t delta);
/* Paint everything queued by ui_text and ui_scroll. Returns 0 if it stopped early because a key is
 * waiting (what is left stays queued and the next ui_flush() continues), 1 when everything is painted. */
uint8_t ui_flush(void);
/* Text cursor at (col,row), or hidden. */
void ui_cursor(uint8_t col, uint8_t row, uint8_t visible);

#endif
