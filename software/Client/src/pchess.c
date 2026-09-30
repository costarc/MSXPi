/*
 * MSXPi PChess - Fusion-C SCREEN 5 client
 *
 * Graphical board, keyboard notation/cursor and joystick input. The MSXPi
 * server validates rules and supplies AI, IRC and room-relay opponents.
 * LINK in the ESC menu switches to TCP/IP UNAPI instead (pchess_tcp.c):
 * rules are then checked here and ROOM/ONLINE go straight to IRC.
 * See PCHESS.md and software/docs/PCHESS-IRC.md for setup and protocol.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/vdp_graph2.h"
#include "../../C-common/header/msxpi.h"

#define BOARD_X 8
#define BOARD_Y 12
#define SQUARE 24
#define BOARD_SIZE (SQUARE * 8)
#define PANEL_X 204
#define SCREEN_BOTTOM 211

/* SCREEN 5 (16 colours, 4 bits per pixel) so PChess also runs on MSX2
 * machines with 64 KB VRAM, such as the Canon V-25: SCREEN 7/8 need 128 KB.
 * Page 0 (VRAM 0x0000-0x7FFF) is displayed; page 1 (lines 256-511) holds
 * the tile and glyph caches. Palette indices, set in main(). */
#define C_BLACK 1
#define C_GREEN 2
#define C_BLUE 13
#define C_YELLOW 11
#define C_LIGHT 14
#define C_WHITE 15
#define PAIR(c) ((uint8_t)((c)*17))
static const Palette palette={{
    {0,0,0,0},{1,0,0,0},{2,0,6,0},{3,2,7,3},{4,1,1,7},{5,2,3,7},{6,5,1,1},{7,2,6,7},
    {8,7,1,1},{9,7,3,3},{10,6,6,1},{11,7,7,0},{12,1,4,1},{13,2,2,1},{14,5,5,3},{15,7,7,7}
}};
/* VRAM address of pixel (x,y), x even; y may be on page 1 (256-511). */
#define VADDR(x,y) ((uint16_t)((uint16_t)(y)*128+((x)>>1)))

/* Bold 5x7 font in 6x7 cells, one byte per row (bit 4 is the left column),
 * indexed by glyph(). Vertical strokes are two pixels wide wherever the
 * letter allows: a single SCREEN 8 pixel is narrower than composite video
 * can resolve, so thin strokes smear into the background on a real MSX. */
#define FONT_W 6
#define FONT_H 7
#define FONT_Y 336
#define GLYPHS 45
static const uint8_t font[GLYPHS][FONT_H] = {
    {0x00,0x00,0x00,0x00,0x00,0x00,0x00}, /*   */
    {0x0E,0x1B,0x1B,0x1B,0x1B,0x1B,0x0E}, /* 0 */
    {0x0C,0x1C,0x0C,0x0C,0x0C,0x0C,0x1E}, /* 1 */
    {0x1E,0x03,0x03,0x0E,0x18,0x18,0x1F}, /* 2 */
    {0x1E,0x03,0x03,0x0E,0x03,0x03,0x1E}, /* 3 */
    {0x1B,0x1B,0x1B,0x1F,0x03,0x03,0x03}, /* 4 */
    {0x1F,0x18,0x18,0x1E,0x03,0x03,0x1E}, /* 5 */
    {0x0E,0x18,0x18,0x1E,0x1B,0x1B,0x0E}, /* 6 */
    {0x1F,0x03,0x06,0x06,0x0C,0x0C,0x0C}, /* 7 */
    {0x0E,0x1B,0x1B,0x0E,0x1B,0x1B,0x0E}, /* 8 */
    {0x0E,0x1B,0x1B,0x0F,0x03,0x03,0x0E}, /* 9 */
    {0x0E,0x1B,0x1B,0x1F,0x1B,0x1B,0x1B}, /* A */
    {0x1E,0x1B,0x1B,0x1E,0x1B,0x1B,0x1E}, /* B */
    {0x0F,0x18,0x18,0x18,0x18,0x18,0x0F}, /* C */
    {0x1E,0x1B,0x1B,0x1B,0x1B,0x1B,0x1E}, /* D */
    {0x1F,0x18,0x18,0x1E,0x18,0x18,0x1F}, /* E */
    {0x1F,0x18,0x18,0x1E,0x18,0x18,0x18}, /* F */
    {0x0F,0x18,0x18,0x1B,0x1B,0x1B,0x0F}, /* G */
    {0x1B,0x1B,0x1B,0x1F,0x1B,0x1B,0x1B}, /* H */
    {0x1E,0x0C,0x0C,0x0C,0x0C,0x0C,0x1E}, /* I */
    {0x03,0x03,0x03,0x03,0x03,0x1B,0x0E}, /* J */
    {0x1B,0x1B,0x1E,0x1C,0x1E,0x1B,0x1B}, /* K */
    {0x18,0x18,0x18,0x18,0x18,0x18,0x1F}, /* L */
    {0x11,0x1B,0x1F,0x15,0x11,0x11,0x11}, /* M */
    {0x11,0x19,0x1D,0x17,0x13,0x11,0x11}, /* N */
    {0x0E,0x1B,0x1B,0x1B,0x1B,0x1B,0x0E}, /* O */
    {0x1E,0x1B,0x1B,0x1E,0x18,0x18,0x18}, /* P */
    {0x0E,0x1B,0x1B,0x1B,0x1B,0x1A,0x0D}, /* Q */
    {0x1E,0x1B,0x1B,0x1E,0x1E,0x1B,0x1B}, /* R */
    {0x0F,0x18,0x18,0x0E,0x03,0x03,0x1E}, /* S */
    {0x1F,0x0C,0x0C,0x0C,0x0C,0x0C,0x0C}, /* T */
    {0x1B,0x1B,0x1B,0x1B,0x1B,0x1B,0x0E}, /* U */
    {0x1B,0x1B,0x1B,0x1B,0x1B,0x0E,0x04}, /* V */
    {0x11,0x11,0x11,0x15,0x15,0x1F,0x1B}, /* W */
    {0x1B,0x1B,0x0E,0x04,0x0E,0x1B,0x1B}, /* X */
    {0x1B,0x1B,0x1B,0x0E,0x0C,0x0C,0x0C}, /* Y */
    {0x1F,0x03,0x06,0x0C,0x18,0x18,0x1F}, /* Z */
    {0x00,0x00,0x00,0x1E,0x00,0x00,0x00}, /* - */
    {0x00,0x0C,0x0C,0x00,0x0C,0x0C,0x00}, /* : */
    {0x00,0x0C,0x0C,0x1F,0x0C,0x0C,0x00}, /* + */
    {0x00,0x0A,0x1F,0x0A,0x1F,0x0A,0x00}, /* # */
    {0x00,0x00,0x1F,0x00,0x1F,0x00,0x00}, /* = */
    {0x06,0x0C,0x18,0x18,0x18,0x0C,0x06}, /* ( */
    {0x0C,0x06,0x03,0x03,0x03,0x06,0x0C}, /* ) */
    {0x00,0x00,0x00,0x00,0x00,0x0C,0x0C}, /* . */
};
/* 42 glyphs fit on one 252-pixel cache row; the rest go on the next. */
#define GLYPH_X(g) (((g)%42)*FONT_W)
#define GLYPH_Y(g) (FONT_Y+((g)/42)*(FONT_H+1))
static uint8_t field_x[32],field_y[32],field_count;
static char field_text[32][64];
static uint8_t glyph(char ch) {
    if(ch>='a' && ch<='z') ch-=32;
    if(ch>='0' && ch<='9') return 1+ch-'0';
    if(ch>='A' && ch<='Z') return 11+ch-'A';
    if(ch=='-') return 37;
    if(ch==':') return 38;
    if(ch=='+') return 39;
    if(ch=='#') return 40;
    if(ch=='=') return 41;
    if(ch=='(') return 42;
    if(ch==')') return 43;
    if(ch=='.') return 44;
    return 0;
}
static void text_at(uint8_t x,uint8_t y,const char *s) {
    uint8_t f,n=0,oldlen,newlen,g; char ch;
    for(f=0;f<field_count;f++) if(field_x[f]==x && field_y[f]==y) break;
    if(f==field_count) {
        if(field_count==32) return;
        field_count++; field_x[f]=x; field_y[f]=y; field_text[f][0]=0;
    }
    oldlen=strlen(field_text[f]); newlen=strlen(s);
    if(newlen>63) newlen=63;
    while(n<oldlen || n<newlen) {
        if((uint16_t)x+n*FONT_W+5>255) break;
        ch=n<newlen?s[n]:' ';
        if(n>=oldlen || field_text[f][n]!=ch) {
            g=glyph(ch);
            HMMM(GLYPH_X(g),GLYPH_Y(g),x+n*FONT_W,y,FONT_W,FONT_H);
        }
        field_text[f][n]=ch;
        n++;
    }
    field_text[f][newlen<n?newlen:n]=0;
}

static char board[8][8] = {
    { 'r','n','b','q','k','b','n','r' },
    { 'p','p','p','p','p','p','p','p' },
    {  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0 },
    {  0,  0,  0,  0,  0,  0,  0,  0 },
    { 'P','P','P','P','P','P','P','P' },
    { 'R','N','B','Q','K','B','N','R' }
};

static uint8_t cursor_x = 4;
static uint8_t cursor_y = 6;
static uint8_t selected_x = 255;
static uint8_t selected_y = 255;
static uint8_t white_turn = 1;
static uint8_t move_count = 0;
static char moves[8][8];
static uint8_t reply[256];
static char status[48]="1 LOCAL 2 AI";
static char entry[24];
static char command[64];
static uint8_t entry_len,room_entry,online,game_over;
/* Set by the server once this player's colour is settled (AI, room or
 * lobby match): my_side 0 = white, 1 = black. */
static uint8_t matched,my_side;
static char opponent[13];
/* Black players see the board rotated 180 degrees. cursor_* and selected_*
 * are screen squares; SQ() and FILE_OF()/RANK_OF() map them to the board. */
static uint8_t flip,user_rotate;
#define BX(x) (flip?7-(x):(x))
#define BY(y) (flip?7-(y):(y))
#define SQ(y,x) board[BY(y)][BX(x)]
static char painted[8][8];
static uint8_t markers[8][8];

/* Rotated when playing black, toggled by ROTATE BOARD in the ESC menu.
 * Cursor and selection are mirrored so they stay on the same squares. */
static void set_flip(void) {
    uint8_t want=(matched && my_side)^user_rotate;
    if(flip==want) return;
    flip=want;
    memset(painted,255,sizeof(painted));
    cursor_x=7-cursor_x; cursor_y=7-cursor_y;
    if(selected_x!=255) {selected_x=7-selected_x; selected_y=7-selected_y;}
}

/* PSG channel A jingles, played after the board is redrawn. Periods are
 * 111861/Hz; each note is (period, jiffies), ending with 0,0. Register
 * 7 keeps port A input / port B output (bits 6-7) for the joystick. */
__sfr __at 0xA0 psg_reg;
__sfr __at 0xA1 psg_val;
static void psg(uint8_t r,uint8_t v) {psg_reg=r; psg_val=v;}
static const uint16_t tune_offer[]={127,6, 0,4, 127,6, 0,0};
static const uint16_t tune_win[]={214,8, 170,8, 143,8, 107,24, 0,0};
static const uint16_t tune_lose[]={285,16, 302,16, 320,16, 339,40, 0,0};
static const uint16_t *pending_tune;
static void play_pending(void) {
    const uint16_t *t=pending_tune;
    uint16_t start;
    if(!t) return;
    pending_tune=0;
    psg(7,0xBE);
    for(;t[0] || t[1];t+=2) {
        psg(0,t[0]&255); psg(1,t[0]>>8);
        psg(8,t[0]?12:0);
        start=*(volatile uint16_t *)0xFC9E;
        while((uint16_t)(*(volatile uint16_t *)0xFC9E-start)<t[1]);
        psg(8,0);
    }
}
/* Called with every state packet: a new draw offer beeps; a game that has
 * just ended plays the win or lose tune (any win in local two-player). */
static uint8_t offer_seen;
static void queue_sounds(uint8_t was_over) {
    uint8_t offer=!memcmp(status,"OPPONENT OFFERS",15), winner;
    if(offer && !offer_seen) pending_tune=tune_offer;
    offer_seen=offer;
    if(was_over || !game_over) return;
    winner=strstr(status,"WHITE WINS")?1:strstr(status,"BLACK WINS")?2:0;
    if(winner) pending_tune=(!matched || (winner==1)==(my_side==0))?tune_win:tune_lose;
}

#include "pchess_rules.c"
#include "pchess_sha.c"
#include "pchess_tcp.c"

/* 0: commands go to the MSXPi server; 1: to local_exchange() over TCP/IP. */
static uint8_t link_tcp;

static uint8_t exchange(const char *cmd) {
    uint8_t rc,tries=0,i,j,was_over=game_over; uint16_t size=0;
    if(link_tcp) {
        local_exchange(cmd);
        size=256; rc=RC_SUCCESS;
        goto parse;
    }
    msxpi_link_claim();
    rc=SendCommandToMSXPi(cmd,false);
    if(rc==RC_SUCCESS) rc=PerformHandshake(256);
    if(rc==RC_SUCCESS) {
        do { size=0; rc=RECVDATA_ONEBLOCK(reply,&size,256); }
        while(rc==RC_CHKSUM_ERR && ++tries<MAX_BLOCK_RETRIES);
    }
    msxpi_link_release();
parse:
    if(rc!=RC_SUCCESS || size!=256 || memcmp(reply,"PCH1",4)) {
        /* A failed background poll stays silent: the next one retries. */
        if(strcmp(cmd,"pchess poll")) strcpy(status,"LINK ERROR - RETRY");
        return 0;
    }
    memcpy(status,reply+72,47); status[47]=0;
    if(!reply[4]) {queue_sounds(1); return 0;}
    for(i=0;i<8;i++) for(j=0;j<8;j++)
        board[i][j]=reply[8+i*8+j]=='.'?0:reply[8+i*8+j];
    white_turn=reply[5]; my_side=reply[6]; game_over=reply[7];
    matched=reply[242]==1;
    queue_sounds(was_over);
    memcpy(opponent,reply+243,12); opponent[12]=0;
    set_flip();
    move_count=reply[240]>8?8:reply[240];
    for(i=0;i<move_count;i++) {
        memcpy(moves[i],reply+120+(reply[240]-move_count+i)*10,7);
        moves[i][7]=0;
    }
    return 1;
}

static uint8_t is_white(char piece) { return piece >= 'A' && piece <= 'Z'; }

/* 24x24 piece bitmaps, one bit per pixel for tile rows 1-20 (MSB is the
 * left column), in P N B R Q K order. The fill mask is the silhouette; the
 * detail mask marks collar and base bands drawn in the contrast colour. The
 * black outline is derived at build time from the 8 neighbours of the fill. */
static const uint32_t piece_fill[6][20]={
    { /* P */ 0x000000,0x000000,0x003C00,0x007E00,0x00FF00,0x00FF00,0x007E00,0x00FF00,0x003C00,0x003C00,0x007E00,0x007E00,0x00FF00,0x01FF80,0x03FFC0,0x03FFC0,0x07FFE0,0x0FFFF0,0x0FFFF0,0x0FFFF0 },
    { /* N */ 0x000000,0x002800,0x007C00,0x00FE00,0x01FE00,0x03FF80,0x07FF80,0x0FFFC0,0x0FFFC0,0x0E7FC0,0x047FC0,0x00FFC0,0x01FFC0,0x01FFC0,0x03FFC0,0x03FFC0,0x07FFE0,0x0FFFF0,0x0FFFF0,0x0FFFF0 },
    { /* B */ 0x001800,0x003C00,0x001800,0x003C00,0x007E00,0x00FF00,0x01FF80,0x01FF80,0x01FF80,0x01FF80,0x00FF00,0x007E00,0x00FF00,0x003C00,0x003C00,0x007E00,0x07FFE0,0x0FFFF0,0x0FFFF0,0x0FFFF0 },
    { /* R */ 0x000000,0x000000,0x067E60,0x067E60,0x07FFE0,0x07FFE0,0x03FFC0,0x01FF80,0x01FF80,0x01FF80,0x01FF80,0x01FF80,0x01FF80,0x01FF80,0x03FFC0,0x03FFC0,0x07FFE0,0x0FFFF0,0x0FFFF0,0x0FFFF0 },
    { /* Q */ 0x000000,0x111888,0x3BBDDC,0x111888,0x19BD98,0x09FF90,0x0FFFF0,0x07FFE0,0x07FFE0,0x03FFC0,0x03FFC0,0x01FF80,0x03FFC0,0x03FFC0,0x01FF80,0x03FFC0,0x07FFE0,0x0FFFF0,0x0FFFF0,0x0FFFF0 },
    { /* K */ 0x001800,0x001800,0x007E00,0x001800,0x001800,0x003C00,0x0E7E70,0x1FFFF8,0x1FFFF8,0x1FFFF8,0x0FFFF0,0x07FFE0,0x03FFC0,0x03FFC0,0x01FF80,0x03FFC0,0x07FFE0,0x0FFFF0,0x0FFFF0,0x0FFFF0 },
};
static const uint32_t piece_detail[6][20]={
    { /* P */ 0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x01FF80,0x000000,0x000000,0x000000 },
    { /* N */ 0x000000,0x000000,0x000000,0x000000,0x002000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x01FF80,0x000000,0x000000,0x000000 },
    { /* B */ 0x000000,0x000000,0x000000,0x000000,0x000000,0x000800,0x001000,0x002000,0x004000,0x000000,0x000000,0x000000,0x003C00,0x000000,0x000000,0x000000,0x01FF80,0x000000,0x000000,0x000000 },
    { /* R */ 0x000000,0x000000,0x000000,0x000000,0x000000,0x01FF80,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x01FF80,0x000000,0x000000,0x000000 },
    { /* Q */ 0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x00FF00,0x000000,0x000000,0x000000,0x01FF80,0x000000,0x000000,0x000000 },
    { /* K */ 0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x000000,0x00FF00,0x000000,0x000000,0x000000,0x01FF80,0x000000,0x000000,0x000000 },
};

static uint32_t piece_mask(uint8_t p,int8_t r) {
    return r>=1 && r<=20 ? piece_fill[p][r-1] : 0;
}
static void piece_row(uint8_t *px,uint8_t p,int8_t r,uint8_t bg,uint8_t white) {
    uint32_t fill=piece_mask(p,r),detail=0,edge,bit=0x800000;
    uint8_t c;
    if(r>=1 && r<=20) detail=piece_detail[p][r-1];
    edge=piece_mask(p,r-1)|fill|piece_mask(p,r+1);
    edge|=(edge<<1)|(edge>>1);
    for(c=0;c<24;c++,bit>>=1) {
        if(fill&bit) px[c]=(detail&bit)?(white?C_BLACK:C_LIGHT):(white?C_WHITE:C_BLACK);
        else px[c]=(edge&bit)?C_BLACK:bg;
    }
}

/* Glyph cache on page 1, written once at startup. */
static void cache_font(void) {
    uint8_t i,r,c,bits,pixels[FONT_W/2];
    for(i=0;i<GLYPHS;i++)
        for(r=0;r<FONT_H;r++) {
            bits=font[i][r];
            for(c=0;c<FONT_W/2;c++) {
                pixels[c]=((bits&0x10)?C_WHITE<<4:C_BLACK<<4)|((bits&0x08)?C_WHITE:C_BLACK);
                bits<<=2;
            }
            CopyRamToVram(pixels,VADDR(GLYPH_X(i),GLYPH_Y(i)+r),FONT_W/2);
        }
}

/* Build tiles once on the hidden VRAM page. HMMM is Fusion-C's assembly
 * VDP command routine: subsequent refreshes never redraw piece primitives.
 * HMMM works on whole bytes (2 pixels) in SCREEN 5, so every HMMM x and
 * width here is even. */
static const char tile_pieces[]=" PNBRQKpnbrqk";
static void cache_graphics(void) {
    uint8_t i,j,r,c,bg,pixels[24]; int x,y;
    for(i=0;i<26;i++) {
        x=(i%10)*24; y=256+(i/10)*24;
        bg=i>=13?C_BLUE:C_LIGHT;
        j=i%13;
        if(!j) { HMMV(x,y,24,24,PAIR(bg)); continue; }
        /* Page 1 is never displayed, so rows go straight into VRAM. */
        for(r=0;r<24;r++) {
            piece_row(pixels,j<7?j-1:j-7,r,bg,j<7);
            for(c=0;c<12;c++) pixels[c]=(pixels[c*2]<<4)|pixels[c*2+1];
            CopyRamToVram(pixels,VADDR(x,y+r),12);
        }
    }
    cache_font();
}

/* The panel is 51 pixels wide: at most 8 characters per line. */
static void draw_panel(void) {
    int i;
    text_at(206,2,!matched?"PCHESS":my_side?"AS BLACK":"AS WHITE");
    text_at(206,12,white_turn ? "WHITE" : "BLACK");
    text_at(206,21,game_over?"GAMEOVER":"TURN");
    text_at(206,32,"MOVES");
    for (i = 0; i < 8; i++) {
        text_at(206,41+i*9,i<move_count?moves[i]:"");
    }
    text_at(206,114,"1 LOCAL");
    text_at(206,122,"2 AI");
    text_at(206,130,"3 ROOM");
    text_at(206,138,"4 ONLINE");
    text_at(206,146,"5 SEEK");
    text_at(206,154,"6 ASK");
    text_at(206,162,"7 ACCEPT");
    text_at(206,170,"8 PLAYER");
    text_at(206,179,room_entry==2?"PEER":room_entry?"ROOM":"MOVE");
    text_at(206,187,entry_len>8?entry+entry_len-8:entry);
    text_at(206,197,"ESC MENU");
    text_at(8,205,status);
}

/* Pixel-exact fill (LMMV): outlines start at odd x, which HMMV cannot do. */
static void solid(int x,int y,int w,int h,uint8_t color) {
    LMMV(x,y,w,h,color,0);
}
static void frame(int x,int y,uint8_t w,uint8_t h,uint8_t color) {
    solid(x,y,w,1,color);
    solid(x,y+h-1,w,1,color);
    solid(x,y,1,h,color);
    solid(x+w-1,y,1,h,color);
}

/* Coordinates: files A-H in the 12-pixel strip above the board, ranks
 * in the 8-pixel strip to its left. Redrawn only when the board turns. */
static uint8_t coords_flip=255;
static void draw_coords(void) {
    uint8_t i,g;
    if(coords_flip==flip) return;
    coords_flip=flip;
    for(i=0;i<8;i++) {
        g=glyph('A'+BX(i));
        HMMM(GLYPH_X(g),GLYPH_Y(g),BOARD_X+i*SQUARE+8,3,FONT_W,FONT_H);
        g=glyph('8'-BY(i));
        HMMM(GLYPH_X(g),GLYPH_Y(g),0,BOARD_Y+i*SQUARE+8,FONT_W,FONT_H);
    }
}

static void draw_board(void) {
    uint8_t x, y;
    draw_coords();
    for (y = 0; y < 8; y++) {
        for (x = 0; x < 8; x++) {
            uint8_t mark=(x==cursor_x && y==cursor_y ? 1 : 0) |
                         (x==selected_x && y==selected_y ? 2 : 0);
            uint8_t tile=0;
            int left = BOARD_X + x * SQUARE;
            int top = BOARD_Y + y * SQUARE;
            if(painted[y][x]==SQ(y,x) && markers[y][x]==mark) continue;
            painted[y][x]=SQ(y,x); markers[y][x]=mark;
            if(SQ(y,x)) {
                for(tile=1;tile<13;tile++) if(tile_pieces[tile]==SQ(y,x)) break;
                if(tile==13) tile=0;
            }
            if((x+y)&1) tile+=13;
            HMMM((tile%10)*24,256+(tile/10)*24,left,top,24,24);
            if (x == cursor_x && y == cursor_y)
                frame(left + 1, top + 1, 22, 22, C_YELLOW);
            if (x == selected_x && y == selected_y)
                frame(left + 3, top + 3, 18, 18, C_GREEN);
        }
    }
    draw_panel();
    play_pending();
}

static void make_move(void) {
    if(selected_x==255) return;
    strcpy(command,"pchess move ");
    command[12]='a'+BX(selected_x); command[13]='8'-BY(selected_y);
    command[14]='a'+BX(cursor_x); command[15]='8'-BY(cursor_y);
    command[16]=0;
    if((SQ(selected_y,selected_x)=='P' && BY(cursor_y)==0) ||
       (SQ(selected_y,selected_x)=='p' && BY(cursor_y)==7)) {
        command[16]='q'; command[17]=0;
    }
    if(exchange(command)) {selected_x=255; selected_y=255;}
}

/* Credits box over the board; any key closes it and resumes the game. */
#define CREDITS_X 12
#define CREDITS_W 184
static void credits_line(uint8_t y,const char *s) {
    text_at((CREDITS_X+(CREDITS_W-strlen(s)*FONT_W)/2)&0xFE,y,s);
}
static void credits(void) {
    /* The panel and menu already fill all 32 text fields, so text_at()
     * would drop these lines. popup_close() repaints them afterwards. */
    field_count=0;
    solid(CREDITS_X,72,CREDITS_W,57,C_BLACK);
    frame(CREDITS_X,72,CREDITS_W,57,C_YELLOW);
    credits_line(82,"PCHESS V1.0 (C) RCC 2026");
    credits_line(98,"DESIGN: RCC");
    credits_line(110,"PROGRAMMING: CLAUDE (INTERN)");
    while(!Inkey());
}

/* ESC pop-up. Rows: 0 AI level (left/right choose, Return saves it to
 * msxpi.ini through "pchess level N"), 1 rooms on the MSXPi relay or IRC
 * ("pchess rooms X", also saved), 2 link MSXPI or TCPIP (Return or ESC applies it; for this run
 * only; every start is MSXPI), 3 offer (or accept) a draw, 4 resign, each
 * after a Y/N, 5 rotate board, 6 credits, 7 exit to DOS. The AI answers a
 * draw offer at once; a human opponent accepts by offering too. ESC
 * resumes the game. Add rows by extending menu_rows and the switch on
 * Return. */
#define MENU_X 44
#define MENU_Y 72
/* Repaint the whole panel and status line from scratch, so closing a
 * pop-up also clears anything stray drawn over the text. */
static void popup_close(void) {
    field_count=0;
    solid(PANEL_X,0,256-PANEL_X,SCREEN_BOTTOM-7,C_BLACK);
    solid(0,SCREEN_BOTTOM-6,256,7,C_BLACK);
    memset(painted,255,sizeof(painted));
    memset(markers,255,sizeof(markers));
}
static const char * const menu_rows[]={"AI LEVEL","ROOMS","LINK","OFFER DRAW","RESIGN",
                                 "ROTATE BOARD","CREDITS","EXIT"};
#define MENU_ROWS 8
#define MENU_H 102
/* Switch the link: every game and connection of the old one ends. */
static void set_link(uint8_t tcp) {
    online=0; selected_x=255;
    if(tcp) {
        if(!tcp_link_start(status)) return;
        link_tcp=1;
        exchange("pchess new local");
        strcpy(status,"LINK TCPIP - 1 LOCAL 3 ROOM 4 ONLINE");
    } else {
        tcp_link_stop();
        link_tcp=0;
        strcpy(status,"LINK MSXPI");
    }
}
static uint8_t menu(void) {
    uint8_t key,row=0,level=2,rooms_irc=0,tcp=link_tcp,i,quit=0;
    char line[20];
    if(link_tcp) rooms_irc=1;
    else if(exchange("pchess level") || !memcmp(reply,"PCH1",4)) {
        if(reply[242]>=1 && reply[242]<=8) level=reply[242];
        rooms_irc=reply[243]==1;
    }
    draw_panel();
    /* The panel fills most of the 32 text fields; the menu needs 11. */
    field_count=0;
    solid(MENU_X,MENU_Y,120,MENU_H,C_BLACK);
    frame(MENU_X,MENU_Y,120,MENU_H,C_YELLOW);
    text_at(MENU_X+40,MENU_Y+5,"M E N U");
    text_at(MENU_X+30,(uint8_t)(MENU_Y+MENU_H-10),"ESC RESUME");
    while(1) {
        for(i=0;i<MENU_ROWS;i++) {
            strcpy(line,i==row?"= ":"  ");
            strcpy(line+2,menu_rows[i]);
            if(i==0) {
                strcat(line,": - 0 +");
                line[strlen(line)-3]='0'+level;
            }
            /* TCP/IP rooms are always IRC: shown (and locked) as soon as
             * LINK reads TCPIP, before Return applies it. */
            if(i==1) strcat(line,rooms_irc || tcp || link_tcp?": IRC":": RELAY");
            if(i==2) strcat(line,tcp?": TCPIP":": MSXPI");
            text_at(MENU_X+8,MENU_Y+16+i*9,line);
        }
        do key=Inkey(); while(!key);
        /* ESC keeps a LINK change too: leaving the menu is how most
         * people finish, and silently dropping it looked like a revert. */
        if(key==27) { if(tcp!=link_tcp) set_link(tcp); break; }
        if(key==0x1e && row) row--;
        else if(key==0x1f && row<MENU_ROWS-1) row++;
        else if(row==0 && key==0x1d && level>1) level--;
        else if(row==0 && key==0x1c && level<8) level++;
        else if(row==1 && !tcp && !link_tcp && (key==0x1c || key==0x1d)) rooms_irc^=1;
        else if(row==2 && (key==0x1c || key==0x1d)) tcp^=1;
        else if(key==13 || key==' ') {
            if(row==3 || row==4) {
                strcpy(status,row==3?"OFFER DRAW? Y/N":"RESIGN? Y/N");
                text_at(8,205,status);
                do key=Inkey(); while(!key);
                if(key=='y' || key=='Y')
                    exchange(row==3?"pchess draw":"pchess resign");
                else strcpy(status,"GAME GOES ON");
                break;
            }
            if(row==5) {user_rotate^=1; set_flip(); break;}
            if(row==6) {credits(); break;}
            if(row==7) {quit=1; break;}
            if(row==2) {
                if(tcp!=link_tcp) set_link(tcp);
                tcp=link_tcp;
                break;
            }
            if(link_tcp || (row && tcp)) {
                strcpy(status,row?"TCPIP ROOMS ARE IRC":"AI NEEDS MSXPI - LINK");
                text_at(8,205,status);
                continue;
            }
            strcpy(command,row?"pchess rooms ":"pchess level ");
            if(row) strcat(command,rooms_irc?"irc":"relay");
            else { line[0]='0'+level; line[1]=0; strcat(command,line); }
            exchange(command);
            if(!row && reply[242]>=1 && reply[242]<=8) level=reply[242];
            text_at(8,205,status);
        }
    }
    popup_close();
    return quit;
}

/* Key 8: lobby players who sent SEEK or an invite in the last ten minutes.
 * Up/Down pick a nick, Return invites it (like 6), ESC closes. */
#define PLAYERS_Y 56
#define PLAYERS_H 93
static void players(void) {
    uint8_t key,row=0,count,i;
    char line[20];
    exchange("pchess players");
    if(memcmp(reply,"PCH1",4) || reply[5]!='P' || !reply[240]) {
        text_at(8,205,status);
        return;
    }
    count=reply[240]>7?7:reply[240];
    solid(MENU_X,PLAYERS_Y,120,PLAYERS_H,C_BLACK);
    frame(MENU_X,PLAYERS_Y,120,PLAYERS_H,C_YELLOW);
    text_at(MENU_X+39,PLAYERS_Y+5,"PLAYERS");
    text_at(MENU_X+6,(uint8_t)(PLAYERS_Y+83),"RET ASK  ESC CLOSE");
    text_at(8,205,status);
    while(1) {
        for(i=0;i<count;i++) {
            strcpy(line,i==row?"= ":"  ");
            memcpy(line+2,reply+120+i*16,16); line[18]=0;
            text_at(MENU_X+8,PLAYERS_Y+16+i*9,line);
        }
        do key=Inkey(); while(!key);
        if(key==27) break;
        if(key==0x1e && row) row--;
        else if(key==0x1f && row<count-1) row++;
        else if(key==13 || key==' ') {
            strcpy(command,"pchess offer ");
            memcpy(line,reply+120+row*16,16); line[16]=0;
            strcat(command,line);
            exchange(command);
            break;
        }
    }
    popup_close();
}

/* Keys 1-4 while online (lobby or room) would drop the connection or the
 * game in progress, so they need a Y to go ahead. */
static uint8_t confirm_leave(void) {
    uint8_t key;
    strcpy(status,"LEAVE ONLINE GAME? Y/N");
    text_at(8,205,status);
    do key=Inkey(); while(!key);
    if(key=='y' || key=='Y') return 1;
    strcpy(status,"STILL ONLINE");
    return 0;
}

int main(void) {
    uint8_t key,joy,fire,lastjoy=0,lastfire=0,arrow_seen=0;
    uint16_t lastpoll=0,lastarrow=0,now;
    /* SCREEN 5 and the VDP commands need an MSX2 (V9938) or later. An
     * MSX1 has no SUB-ROM, so its slot in EXBRSA is 0. */
    if(!*(volatile uint8_t *)0xFAF8) {
        Print("PCHESS NEEDS AN MSX2\r\n");
        return 0;
    }
    entry_len=0; room_entry=0; online=0; game_over=0; link_tcp=0;
    tcp_init();
    matched=0; my_side=0; flip=0; user_rotate=0; opponent[0]=0;
    field_count=0; pending_tune=0; offer_seen=0; coords_flip=255;
    entry[0]=0;
    memset(moves,0,sizeof(moves));
    memset(reply,0,sizeof(reply));
    memset(painted,255,sizeof(painted));
    memset(markers,255,sizeof(markers));
    Screen(5);
    HideDisplay();
    SetSC5Palette((Palette *)&palette);
    SetColors(C_WHITE,C_BLACK,C_BLACK);
    *(uint8_t *)0xFFE8 |= 128;
    VDPwrite(9,*(uint8_t *)0xFFE8);
    HMMV(0,0,256,212,PAIR(C_BLACK));
    cache_graphics();
    draw_board();
    ShowDisplay();
    while (1) {
        key = Inkey();
        joy=JoystickRead(1); fire=TriggerRead(1);
        if(joy!=lastjoy) {
            if(joy==1) key=30; if(joy==3) key=28;
            if(joy==5) key=31; if(joy==7) key=29;
        }
        if(fire && !lastfire) key=' ';
        lastjoy=joy; lastfire=fire;
        now=*(volatile uint16_t *)0xFC9E;
        /* Consume rapid BIOS repeats without queuing delayed cursor moves.
         * Eight jiffies is 133 ms at 60 Hz, 160 ms at 50 Hz. The first
         * arrow is immediate; unsigned subtraction handles timer wrap. */
        if(key>=0x1c && key<=0x1f) {
            if(arrow_seen && (uint16_t)(now-lastarrow)<8) key=0;
            else {lastarrow=now; arrow_seen=1;}
        }
        if(!key) {
            /* Every 2 s on the MSXPi; every second on TCP/IP, where this
             * poll is also what reads the IRC connection. */
            if(online && (uint16_t)(now-lastpoll)>=(link_tcp?60:120)) {
                lastpoll=now; exchange("pchess poll"); draw_board();
            }
            continue;
        }
        if (key == 27) {
            if(menu()) break;
            draw_board();
            continue;
        }
        if(key==8 && entry_len) entry[--entry_len]=0;
        else if(key==13 && entry_len) {
            strcpy(command,room_entry==2?"pchess offer ":room_entry?"pchess join ":"pchess move ");
            strcat(command,entry);
            if(exchange(command)) {
                if(room_entry) online=1;
                room_entry=0; entry_len=0; entry[0]=0; selected_x=255;
            }
        }
        else if(!entry_len && !room_entry && online && key>='1' && key<='4' &&
                !confirm_leave()) {}
        else if(!entry_len && !room_entry && (key=='1' || key=='2')) {
            online=0; selected_x=255;
            exchange(key=='1'?"pchess new local":"pchess new ai");
        }
        else if(!entry_len && !room_entry && key=='3') {room_entry=1; strcpy(status,"ENTER ROOM AND RETURN");}
        else if(!entry_len && !room_entry && key=='4') {if(exchange("pchess irc")) online=1;}
        else if(!entry_len && !room_entry && key=='5') {exchange("pchess seek");}
        else if(!entry_len && !room_entry && key=='6') {room_entry=2; strcpy(status,"ENTER PEER NICK AND RETURN");}
        else if(!entry_len && !room_entry && key=='7') {exchange("pchess accept");}
        else if(!entry_len && !room_entry && key=='8') {players();}
        else if(key==0x1e && cursor_y) cursor_y--;
        else if (key == 0x1f && cursor_y < 7) cursor_y++;
        else if (key == 0x1d && cursor_x) cursor_x--;
        else if (key == 0x1c && cursor_x < 7) cursor_x++;
        else if (key == ' ' || key == 13) {
            if (SQ(cursor_y,cursor_x) &&
                is_white(SQ(cursor_y,cursor_x)) == white_turn) {
                selected_x = cursor_x;
                selected_y = cursor_y;
            } else make_move();
        } else if(key>=33 && key<=126 && entry_len<16) {
            entry[entry_len++]=key; entry[entry_len]=0;
        }
        draw_board();
    }
    tcp_link_stop();
    RestoreSC5Palette();
    Screen(0);
    Cls();
    return 0;
}
