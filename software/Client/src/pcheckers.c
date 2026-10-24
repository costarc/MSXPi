/*
 * MSXPi PCheckers (DAMAS) - Fusion-C SCREEN 5 client
 *
 * Brazilian draughts on the 8x8 board, for two players or against the AI.
 * Based on PChess: same SCREEN 5 board, cursor and joystick input, but the
 * rules and the AI run here (pcheckers_rules.c). Online rooms and chat use
 * the pchess relay on the MSXPi server, or IRC on the TCP/IP link
 * (pcheckers_tcp.c). See PCHECKERS.md.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "../../C-common/header/fusion_hdr.h"
#include "../../C-common/header/fusion_gfx_hdr.h"
#include "../../C-common/header/msxpi.h"

#define BOARD_X 8
#define BOARD_Y 12
#define SQUARE 24
#define PANEL_X 204
#define SCREEN_BOTTOM 211

/* SCREEN 5 (16 colours) so the game also runs on MSX2 machines with 64 KB
 * VRAM. Page 0 is displayed; page 1 (lines 256-511) holds the tile and
 * glyph caches. Palette indices, set in main(). */
#define C_BLACK 1
#define C_GREEN 2
#define C_GREY 3
#define C_DARKP 4
#define C_YELLOW 11
#define C_DARK 13
#define C_LIGHT 14
#define C_WHITE 15
#define PAIR(c) ((uint8_t)((c)*17))
static const Palette palette={{
    {0,0,0,0},{1,0,0,0},{2,0,6,0},{3,5,5,5},{4,1,1,1},{5,0,0,0},{6,0,0,0},{7,0,0,0},
    {8,0,0,0},{9,0,0,0},{10,0,0,0},{11,7,7,0},{12,0,0,0},{13,3,1,0},{14,6,5,3},{15,7,7,7}
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
#define GLYPHS 50
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
    {0x0E,0x1B,0x03,0x06,0x0C,0x00,0x0C}, /* ? */
    {0x0C,0x0C,0x0C,0x0C,0x0C,0x00,0x0C}, /* ! */
    {0x00,0x00,0x00,0x00,0x0C,0x0C,0x18}, /* , */
    {0x0C,0x0C,0x18,0x00,0x00,0x00,0x00}, /* ' */
    {0x03,0x06,0x06,0x0C,0x0C,0x18,0x18}, /* / */
};
/* 42 glyphs fit on one 252-pixel cache row; the rest go on the next. */
#define GLYPH_X(g) (((g)%42)*FONT_W)
#define GLYPH_Y(g) (FONT_Y+((g)/42)*(FONT_H+1))
/* A yellow copy of the font (private chat rows) sits 16 lines further down. */
#define PRIVATE_FONT 16
static uint8_t field_x[32],field_y[32],field_count;
/* The longest line is the 47-character status at (8,205), which has its own
 * buffer; every other line (the longest are the credits) is at most 28
 * characters. PChess is close to the MSX-DOS memory limit, so the fields are
 * not 48 bytes each. */
#define FIELD_TEXT 29
#define STATUS_X 8
#define STATUS_Y 205
static char field_text[32][FIELD_TEXT];
static char status_text[48];
#define CHAT_LINES 20
#define CHAT_COLS 42
static char chat_log[CHAT_LINES][CHAT_COLS+1];
static uint8_t chat_private[CHAT_LINES];   /* 1: said privately, drawn yellow */
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
    if(ch=='?') return 45;
    if(ch=='!') return 46;
    if(ch==',') return 47;
    if(ch=='\'') return 48;
    if(ch=='/') return 49;
    return 0;
}
static void text_at(uint8_t x,uint8_t y,const char *s) {
    uint8_t f,n=0,oldlen,newlen,cap,g; char ch,*ft;
    for(f=0;f<field_count;f++) if(field_x[f]==x && field_y[f]==y) break;
    if(x==STATUS_X && y==STATUS_Y) {ft=status_text; cap=47;}
    else {ft=field_text[f<32?f:31]; cap=FIELD_TEXT-1;}
    if(f==field_count) {
        if(field_count==32) return;
        field_count++; field_x[f]=x; field_y[f]=y; ft[0]=0;
    }
    oldlen=strlen(ft); newlen=strlen(s);
    if(newlen>cap) newlen=cap;
    while(n<oldlen || n<newlen) {
        if((uint16_t)x+n*FONT_W+5>255) break;
        ch=n<newlen?s[n]:' ';
        if(n>=oldlen || ft[n]!=ch) {
            g=glyph(ch);
            HMMM(GLYPH_X(g),GLYPH_Y(g),x+n*FONT_W,y,FONT_W,FONT_H);
        }
        ft[n]=ch;
        n++;
    }
    ft[newlen<n?newlen:n]=0;
}

/* Glyph cache on page 1, written once at startup. */
static void cache_font(void) {
    uint8_t i,r,c,bits,pixels[FONT_W/2],set,fg;
    for(set=0;set<2;set++) {
        fg=set?C_YELLOW:C_WHITE;
        for(i=0;i<GLYPHS;i++)
            for(r=0;r<FONT_H;r++) {
                bits=font[i][r];
                for(c=0;c<FONT_W/2;c++) {
                    pixels[c]=((bits&0x10)?fg<<4:C_BLACK<<4)|((bits&0x08)?fg:C_BLACK);
                    bits<<=2;
                }
                CopyRamToVram(pixels,VADDR(GLYPH_X(i),GLYPH_Y(i)+r+set*PRIVATE_FONT),FONT_W/2);
            }
    }
}


#include "pcheckers_rules.c"

/* Game state. cb is the board (see pcheckers_rules.c); the cursor is in
 * screen squares and the selection in board squares, so rotating the board
 * only has to mirror the cursor. */
static uint8_t cb[64];
static uint8_t turn,game_over,vs_ai,ai_side,level=2,quiet;
static uint8_t cursor_x=4,cursor_y=5;
static uint8_t spath[MAXN],slen,cand[64];
static Move legal[MAXM];
static uint8_t legal_n,legal_cap;
static uint8_t move_count;
static char moves[8][8];
static char status[48]="1 LOCAL 2 AI WHITE 3 AI BLACK";
static uint8_t flip,user_rotate;
#define BX(x) (flip?7-(x):(x))
#define BY(y) (flip?7-(y):(y))
static uint8_t painted[8][8],markers[8][8];
static uint8_t reply[256];
/* "pchess say " plus up to 100 characters of chat. */
static char command[120];
static char entry[24];
static uint8_t entry_len,room_entry,online,link_tcp;
/* my_side: 0 white, 1 black, for the AI game or the online room. matched:
 * an opponent has joined the room. ply_net counts the moves played, which
 * is what the server's move list is indexed by. */
static uint8_t my_side,matched,end_by_server,offer_seen;
static uint16_t ply_net;
/* Unread chat rows the server holds (reply[255] of every packet), and the
 * count already beeped for. */
static uint8_t chat_unread,chat_seen;

static void set_flip(void) {
    uint8_t want=((vs_ai || (online && matched)) && my_side)^user_rotate;
    if(flip==want) return;
    flip=want;
    memset(painted,255,sizeof(painted));
    cursor_x=7-cursor_x; cursor_y=7-cursor_y;
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
/* "Tcha-Ham": a short G5 then a long C6, for a lobby SEEK. */
static const uint16_t tune_seek[]={143,5, 0,3, 107,30, 0,0};
static char seek_seen[48];
/* A short high blip for new chat. */
static const uint16_t tune_chat[]={95,4, 0,0};
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

/* Chat scrollback, shared by both links: chat_add() is called by the chat
 * window (the player's own words) and by the TCP/IP link's IRC reader
 * (what others say); with the MSXPi link the window fetches rows from the
 * server instead. Rows are 42 characters, the most a 256-pixel line holds. */
static uint8_t chat_rows,chat_new;

static void chat_push(const char *row,uint8_t priv) {
    if(chat_rows==CHAT_LINES) {
        memmove(chat_log[0],chat_log[1],(CHAT_LINES-1)*(CHAT_COLS+1));
        memmove(chat_private,chat_private+1,CHAT_LINES-1);
        chat_rows--;
    }
    chat_new++;
    strncpy(chat_log[chat_rows],row,CHAT_COLS);
    chat_log[chat_rows][CHAT_COLS]=0;
    chat_private[chat_rows]=priv;
    chat_rows++;
}

/* prefix and text wrapped into rows (continuation rows start with two
 * blanks), the way the server wraps. priv rows are drawn in yellow. */
static void chat_add(const char *prefix,const char *text,uint8_t priv) {
    char row[CHAT_COLS+1];
    uint8_t n,first=1;
    while(first || *text) {
        strcpy(row,first?prefix:"  ");
        n=strlen(row);
        while(*text && n<CHAT_COLS) row[n++]=*text++;
        row[n]=0;
        chat_push(row,priv);
        first=0;
    }
}

/* Fold text to what the font can draw, as the server does: upper case, runs
 * of blanks become one, other characters it cannot draw become '?'; at most
 * 100 characters. */
static void chat_clean(char *s) {
    char *out=s,*start=s,c;
    uint8_t space=1;
    for(;(c=*s)!=0 && out-start<100;s++) {
        if(c>='a' && c<='z') c-=32;
        if(c==' ' || c=='\t' || c=='\r' || c=='\n') {
            if(!space) *out++=' ';
            space=1;
            continue;
        }
        if(c<' ' || c==127) continue;
        *out++=glyph(c)?c:'?';
        space=0;
    }
    if(out>start && out[-1]==' ') out--;
    *out=0;
}


/* 6 tiles, 24x24, built once on the hidden page: 0 light square, 1 dark
 * square, 2-5 white man, white king, black man, black king on dark. Pieces
 * are discs drawn from the distance to the tile centre (d2 is four times
 * the squared distance); kings have a filled centre as a crown. */
static void cache_graphics(void) {
    uint8_t i,r,c,bg,px[24],white,king,col; int16_t d2,a,sq[24];
    for(c=0;c<24;c++) {a=2*c-23; sq[c]=a*a;}
    for(i=0;i<6;i++) {
        bg=i?C_DARK:C_LIGHT;
        white=i==2 || i==3; king=i==3 || i==5;
        for(r=0;r<24;r++) {
            for(c=0;c<24;c++) {
                col=bg;
                if(i>=2) {
                    d2=sq[c]+sq[r];
                    if(d2<=441) {
                        col=white?C_WHITE:C_DARKP;
                        if((d2>=300 && d2<=340) || (king && d2<=60)) col=white?C_GREY:C_WHITE;
                    } else if(d2<=529) col=white?C_BLACK:C_GREY;
                }
                px[c]=col;
            }
            for(c=0;c<12;c++) px[c]=(px[c*2]<<4)|px[c*2+1];
            CopyRamToVram(px,VADDR(i*24,256+r),12);
        }
    }
    cache_font();
}

static void draw_panel(void) {
    int i;
    text_at(206,2,!(vs_ai || (online && matched))?"PCHECKER":my_side?"AS BLACK":"AS WHITE");
    text_at(206,12,turn ? "BLACK" : "WHITE");
    text_at(206,21,game_over?"GAMEOVER":"TURN");
    text_at(206,32,"MOVES");
    for (i = 0; i < 8; i++) {
        text_at(206,41+i*9,i<move_count?moves[i]:"");
    }
    text_at(206,114,"1 LOCAL");
    text_at(206,122,"2 AI WHT");
    text_at(206,130,"3 AI BLK");
    text_at(206,138,"4 ROOM");
    text_at(206,146,"5 ONLINE");
    text_at(206,154,"6 SEEK");
    text_at(206,162,"7 ASK");
    text_at(206,170,"8 ACCEPT");
    text_at(206,178,"9 PLAYER");
    text_at(206,187,entry_len>8?entry+entry_len-8:entry);
    if(chat_unread) {
        char note[8]="CHAT ";
        uint8_t n=chat_unread>99?99:chat_unread;
        if(n>9) {note[5]='0'+n/10; note[6]='0'+n%10; note[7]=0;}
        else {note[5]='0'+n; note[6]=0;}
        text_at(206,197,note);
    } else text_at(206,197,"ESC MENU");
    text_at(8,205,status);
}

/* Pixel-exact fill (LMMV). */
static void solid(int x,int y,int w,int h,uint8_t color) {
    LMMV(x,y,w,h,color,0);
}
static void frame(int x,int y,uint8_t w,uint8_t h,uint8_t color) {
    solid(x,y,w,1,color);
    solid(x,y+h-1,w,1,color);
    solid(x,y,1,h,color);
    solid(x+w-1,y,1,h,color);
}

/* Files A-H above the board, ranks to its left; redrawn only on rotation. */
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
    uint8_t x,y,s,p,mark,tile;
    int left,top;
    draw_coords();
    for(y=0;y<8;y++) {
        for(x=0;x<8;x++) {
            s=BY(y)*8+BX(x); p=cb[s];
            mark=(x==cursor_x && y==cursor_y?1:0);
            if(slen) {
                uint8_t k;
                for(k=0;k<slen;k++) if(spath[k]==s) mark|=2;
                if(cand[s]) mark|=4;
            }
            if(painted[y][x]==p && markers[y][x]==mark) continue;
            painted[y][x]=p; markers[y][x]=mark;
            left=BOARD_X+x*SQUARE; top=BOARD_Y+y*SQUARE;
            tile=(x+y)&1?(p?1+p:1):0;
            HMMM((tile%10)*24,256+(tile/10)*24,left,top,24,24);
            if(mark&4) solid(left+10,top+10,4,4,C_GREEN);
            if(mark&1) frame(left+1,top+1,22,22,C_YELLOW);
            if(mark&2) frame(left+3,top+3,18,18,C_GREEN);
        }
    }
    draw_panel();
    play_pending();
}

static void clear_sel(void) { slen=0; memset(cand,0,sizeof(cand)); }
static void refresh_cand(void) {
    uint8_t i;
    memset(cand,0,sizeof(cand));
    for(i=0;i<legal_n;i++)
        if(legal[i].n>slen && !memcmp(legal[i].sq,spath,slen)) cand[legal[i].sq[slen]]=1;
}

static void finish(uint8_t winner,const char *text) {
    game_over=1; clear_sel();
    strcpy(status,text);
    if(winner<2)
        pending_tune=((!vs_ai && !online) || winner==my_side)?tune_win:tune_lose;
}

static void new_turn(void) {
    legal_n=gen(cb,turn,legal,0,MAXM); legal_cap=gen_capture;
    if(!legal_n) finish(turn^1,turn?"WHITE WINS":"BLACK WINS");
    else if(quiet>=40) finish(2,"DRAW - 20 KING MOVES");
    else {
        if(online) strcpy(status,!matched?"WAITING FOR OPPONENT":
                          turn==my_side?"YOUR MOVE":"OPPONENT MOVES");
        else strcpy(status,turn?"BLACK TO MOVE":"WHITE TO MOVE");
        if(legal_cap && (!online || turn==my_side)) strcat(status," - MUST CAPTURE");
    }
}

static void play(const Move *m) {
    Move mv; uint8_t from,to,king;
    char *h;
    mv=*m; from=mv.sq[0]; to=mv.sq[mv.n-1]; king=cb[from]==WK || cb[from]==BK;
    if(move_count==8) {memmove(moves[0],moves[1],7*8); h=moves[7];}
    else h=moves[move_count++];
    h[0]='A'+COL(from); h[1]='8'-ROW(from); h[2]=mv.caps?'X':'-';
    h[3]='A'+COL(to); h[4]='8'-ROW(to); h[5]=0;
    apply(cb,&mv);
    quiet=king && !mv.caps?quiet+1:0;
    clear_sel();
    turn^=1;
    ply_net++;
    new_turn();
}

static uint8_t exchange(const char *cmd);
static void new_game(uint8_t ai,uint8_t human_side) {
    /* Leaving a room or the lobby drops the connection (IRC) or the room. */
    if(online) exchange("pchess cleave");
    rules_setup(cb);
    turn=0; game_over=0; quiet=0; move_count=0; vs_ai=ai; ai_side=human_side^1;
    my_side=human_side; online=0; ply_net=0; end_by_server=0; matched=0;
    user_rotate=0; clear_sel();
    set_flip();
    memset(painted,255,sizeof(painted));
    new_turn();
}


/* A new game in the same online room, after a rematch or a reset by the
 * other player. */
static void restart_online(void) {
    rules_setup(cb);
    turn=0; game_over=0; quiet=0; move_count=0; ply_net=0; end_by_server=0;
    clear_sel();
    memset(painted,255,sizeof(painted));
    new_turn();
}

/* ------------------------------------------------------------- the link */

#include "pcheckers_tcp.c"

static uint8_t exchange(const char *cmd);

/* "c3e5g7": a move as the server relays it. */
static void move_text(const Move *m,char *out) {
    uint8_t i;
    for(i=0;i<m->n;i++) {
        *out++='a'+COL(m->sq[i]);
        *out++='8'-ROW(m->sq[i]);
    }
    *out=0;
}


/* Apply a state packet from the server or the TCP/IP link (see
 * checkers_packet() in msxpi_pchess.py): opponent moves, how the game ended,
 * draw offers, unread chat. */
static void net_apply(void) {
    uint8_t i,j,n,k,found;
    uint16_t total;
    matched=reply[5]; my_side=reply[6];
    chat_unread=reply[255];
    if(chat_unread>chat_seen) pending_tune=tune_chat;
    chat_seen=chat_unread;
    total=((uint16_t)reply[238]<<8)|reply[241];
    /* The server's list is shorter than ours when the game was reset. */
    if(total<ply_net || (end_by_server && !reply[7])) restart_online();
    for(i=0;i<reply[240] && i<8;i++) {
        n=reply[120+i*14];
        found=0;
        for(k=0;k<legal_n && !found;k++) {
            if(legal[k].n!=n) continue;
            for(j=0;j<n && legal[k].sq[j]==reply[121+i*14+j];j++);
            if(j==n) {found=1; play(&legal[k]);}
        }
        if(!found) {strcpy(status,"OUT OF SYNC - REJOIN THE ROOM"); break;}
    }
    if(reply[7] && !game_over) {
        end_by_server=1;
        if(reply[7]==3) finish(2,"DRAW AGREED");
        else finish(reply[7]==1?0:1,reply[7]==1?"BLACK RESIGNED - WHITE WINS":"WHITE RESIGNED - BLACK WINS");
    } else if(!game_over) {
        if(reply[242]==1) {
            if(!offer_seen) pending_tune=tune_offer;
            offer_seen=1;
            strcpy(status,"OPPONENT OFFERS DRAW - ESC MENU");
        } else {
            offer_seen=0;
            if(reply[242]==2) strcpy(status,"DRAW OFFERED");
            else if(!matched) {
                /* Lobby or room not matched yet: the peer's own status
                 * (SEEK SENT, INVITE bob PRESS 8, ROOM x - WAITING...). */
                if(reply[72]) {memcpy(status,reply+72,47); status[47]=0;}
                else strcpy(status,"WAITING FOR OPPONENT");
                if(!memcmp(status,"PLAYER ",7)) {
                    if(strcmp(status,seek_seen)) pending_tune=tune_seek;
                    strcpy(seek_seen,status);
                } else seek_seen[0]=0;
            }
        }
    }
    set_flip();
}

/* One command to the MSXPi server (or the TCP/IP link): 1 when it gave a
 * state or chat packet, 0 with the reason in status when it did not. */
static uint8_t exchange(const char *cmd) {
    uint8_t rc,tries=0; uint16_t size=0;
    if(link_tcp) {
        local_exchange(cmd);
        size=256; rc=RC_SUCCESS;
    } else {
        /* No interface: port $56 floats to $FF and CHKPIRDY() never returns. */
        if(InPort(CONTROL_PORT1)>1) {
            strcpy(status,"NO MSXPI - ESC MENU LINK TCPIP");
            return 0;
        }
        msxpi_link_claim();
        rc=SendCommandToMSXPi(cmd,false);
        if(rc==RC_SUCCESS) rc=PerformHandshake(256);
        if(rc==RC_SUCCESS) {
            do { size=0; rc=RECVDATA_ONEBLOCK(reply,&size,256); }
            while(rc==RC_CHKSUM_ERR && ++tries<MAX_BLOCK_RETRIES);
        }
        msxpi_link_release();
    }
    if(rc!=RC_SUCCESS || size!=256 || memcmp(reply,"PCH1",4)) {
        /* A failed background poll stays silent: the next one retries. */
        if(memcmp(cmd,"pchess cpoll",12)) strcpy(status,"LINK ERROR - RETRY");
        return 0;
    }
    /* A chat block ('C') carries text where the status would be: the chat
     * window reads it from reply and the status line stays as it was. */
    if(!reply[4]) {
        if(reply[5]=='C') return 1;
        memcpy(status,reply+72,47); status[47]=0;
        return 0;
    }
    net_apply();
    return 1;
}

/* Ask for what happened since our last move. */
static void poll_server(void) {
    strcpy(command,"pchess cpoll ");
    put_dec(command+13,ply_net);
    exchange(command);
}

/* A move of ours: the opponent's side must accept it before it is played. */
static void commit(const Move *m) {
    if(online) {
        strcpy(command,"pchess cmove ");
        put_dec(command+13,ply_net);
        strcat(command," ");
        move_text(m,command+strlen(command));
        if(!exchange(command)) {clear_sel(); return;}
    }
    play(m);
}

/* Return/Space: first pick a piece that can move, then the destination.
 * A capture with several routes is entered one landing square at a time;
 * when only one legal move still fits the squares entered, it is played. */
/* 0 with a status when it is not the player's turn to move. */
static uint8_t my_turn(void) {
    if(game_over || (vs_ai && turn==ai_side)) return 0;
    if(online && (!matched || turn!=my_side)) {
        strcpy(status,matched?"OPPONENT MOVES":"WAITING FOR OPPONENT");
        return 0;
    }
    return 1;
}

/* A typed move: "c3d4" (also "c3-d4", "c3xe5"), or every landing square of
 * a capture ("c3e5g7"). From and to alone are enough when only one legal
 * move fits. */
static void type_move(const char *text) {
    uint8_t sq[MAXN],n=0,i,j,hits=0,k=0;
    char c,d;
    if(!my_turn()) return;
    while((c=*text++)!=0) {
        if(c>='A' && c<='H') c+=32;
        if(c=='-' || c=='x' || c=='X' || c==' ') continue;
        d=*text++;
        if(c<'a' || c>'h' || d<'1' || d>'8' || n>=MAXN) {strcpy(status,"BAD MOVE - TYPE C3D4"); return;}
        sq[n++]=(uint8_t)((8-(d-'0'))*8+(c-'a'));
    }
    if(n<2) {strcpy(status,"BAD MOVE - TYPE C3D4"); return;}
    for(i=0;i<legal_n;i++) {
        if(legal[i].n==n) {
            for(j=0;j<n && legal[i].sq[j]==sq[j];j++);
            if(j==n) {commit(&legal[i]); return;}
        }
        if(n==2 && legal[i].sq[0]==sq[0] && legal[i].sq[legal[i].n-1]==sq[1]) {hits++; k=i;}
    }
    if(hits==1) commit(&legal[k]);
    else strcpy(status,hits?"SEVERAL ROUTES - TYPE EVERY SQUARE":"ILLEGAL MOVE");
}

static void activate(void) {
    uint8_t s=BY(cursor_y)*8+BX(cursor_x),i,hits=0,k=0;
    if(!my_turn()) return;
    if(slen==1 && s==spath[0]) {clear_sel(); return;}
    if(!slen || (slen==1 && cb[s] && SIDE_OF(cb[s])==turn)) {
        if(!cb[s] || SIDE_OF(cb[s])!=turn) {strcpy(status,"SELECT ONE OF YOUR PIECES"); return;}
        for(i=0;i<legal_n;i++) if(legal[i].sq[0]==s) break;
        if(i==legal_n) {strcpy(status,legal_cap?"MUST CAPTURE":"THAT PIECE CANNOT MOVE"); return;}
        spath[0]=s; slen=1; refresh_cand();
        strcpy(status,"CHOOSE DESTINATION");
        return;
    }
    for(i=0;i<legal_n;i++)
        if(legal[i].n>slen && !memcmp(legal[i].sq,spath,slen) && legal[i].sq[slen]==s) {hits++; k=i;}
    if(!hits) {strcpy(status,"ILLEGAL MOVE"); return;}
    if(hits==1) {commit(&legal[k]); return;}
    spath[slen++]=s; refresh_cand();
    strcpy(status,"CONTINUE THE CAPTURE");
}

/* Level 1-6 searches level+1 plies. The clock seeds the choice among
 * equal moves. */
static void ai_turn(void) {
    Move m;
    strcpy(status,"THINKING...");
    draw_board();
    ai_seed^=*(volatile uint16_t *)0xFC9E;
    ai_pick(cb,turn,level+1,&m);
    play(&m);
}

/* Credits box over the board; any key closes it and resumes the game. */
#define CREDITS_X 12
#define CREDITS_W 184
static void credits_line(uint8_t y,const char *s) {
    text_at((CREDITS_X+(CREDITS_W-strlen(s)*FONT_W)/2)&0xFE,y,s);
}
static void credits(void) {
    /* The panel and menu already fill the text fields, so text_at() would
     * drop these lines. popup_close() repaints them afterwards. */
    field_count=0;
    solid(CREDITS_X,72,CREDITS_W,57,C_BLACK);
    frame(CREDITS_X,72,CREDITS_W,57,C_YELLOW);
    credits_line(82,"PCHECKERS V1.1.1 (C) RCC 2026");
    credits_line(98,"DESIGN: RCC (ARCHITECT)");
    credits_line(110,"PROGRAMMING: CLAUDE (INTERN)");
    while(!Inkey());
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


/* Chat: a full-screen text window over the board (TAB or ESC menu, while
 * playing online). The MSXPi server queues what the opponent or channel says
 * and hands it over in blocks of up to five rows ("pchess chat"); the
 * TCP/IP link has already put it in the scrollback. Closing repaints the
 * board from scratch. The scrollback is kept while the program runs and
 * starts empty when a new online session begins. */
#define CHAT_TOP 12
#define CHAT_INPUT_Y 199
#define CHAT_MAX_INPUT 100

/* One line of text at y, replacing whatever the row held; priv draws it in
 * the yellow font. */
static void chat_line(uint8_t y,const char *s,uint8_t priv) {
    uint8_t n,g;
    solid(0,y,256,FONT_H+1,C_BLACK);
    for(n=0;s[n] && n<CHAT_COLS;n++) {
        g=glyph(s[n]);
        HMMM(GLYPH_X(g),GLYPH_Y(g)+(priv?PRIVATE_FONT:0),2+n*FONT_W,y,FONT_W,FONT_H);
    }
}

static void chat_draw_log(void) {
    uint8_t i;
    for(i=0;i<CHAT_LINES;i++) chat_line(CHAT_TOP+i*9,i<chat_rows?chat_log[i]:"",i<chat_rows && chat_private[i]);
}

static void chat_draw_input(const char *input,uint8_t len) {
    char line[CHAT_COLS+1];
    uint8_t shown=len>CHAT_COLS-4?CHAT_COLS-4:len;
    strcpy(line,"> ");
    memcpy(line+2,input+len-shown,shown);
    line[2+shown]='_'; line[3+shown]=0;
    chat_line(CHAT_INPUT_Y,line,0);
}

/* Fetch what the server holds; false when the link failed. */
static uint8_t chat_pull(void) {
    uint8_t i,rounds=0;
    char row[CHAT_COLS+1];
    do {
        if(!exchange("pchess chat") || reply[5]!='C') return 0;
        for(i=0;i<reply[240] && i<5;i++) {
            memcpy(row,reply+8+i*44,CHAT_COLS); row[CHAT_COLS]=0;
            chat_push(row,reply[8+i*44+CHAT_COLS+1]);
        }
        chat_unread=reply[241]; chat_seen=chat_unread;
    } while(reply[241] && ++rounds<4);
    return 1;
}

/* Leave the board repainted by the next draw_board(). */
static void chat_close(void) {
    HMMV(0,0,256,212,PAIR(C_BLACK));
    field_count=0;
    memset(painted,255,sizeof(painted));
    memset(markers,255,sizeof(markers));
    coords_flip=255;
    chat_unread=0; chat_seen=0;
    if(pending_tune==tune_chat) pending_tune=0;
}

static void chat_window(void) {
    char input[CHAT_MAX_INPUT+1];
    uint8_t key,len=0;
    uint16_t lastpoll,now;
    if(!online) {strcpy(status,"CHAT NEEDS AN ONLINE GAME (4)"); return;}
    input[0]=0;
    HMMV(0,0,256,212,PAIR(C_BLACK));
    chat_line(1,"CHAT - ESC OR TAB CLOSES",0);
    solid(0,9,256,1,C_YELLOW);
    solid(0,CHAT_INPUT_Y-3,256,1,C_YELLOW);
    chat_pull();
    chat_draw_log();
    chat_draw_input(input,len);
    lastpoll=*(volatile uint16_t *)0xFC9E;
    while(1) {
        key=Inkey();
        now=*(volatile uint16_t *)0xFC9E;
        if(!key) {
            if((uint16_t)(now-lastpoll)>=90) {
                lastpoll=now;
                chat_new=0;
                if(chat_pull() && chat_new) chat_draw_log();
            }
            continue;
        }
        if(key==27 || key==9) break;
        if(key==8) {
            if(len) input[--len]=0;
        } else if(key==13) {
            if(len) {
                strcpy(command,"pchess say ");
                strcat(command,input);
                if(exchange(command)) {
                    chat_add("YOU: ",input,matched);
                    len=0; input[0]=0;
                    chat_pull();
                    chat_draw_log();
                    chat_line(1,"CHAT - ESC OR TAB CLOSES",0);
                } else chat_line(1,status,0);
            }
        } else if(key>=32 && key<=126 && len<CHAT_MAX_INPUT) {
            input[len++]=key; input[len]=0;
        }
        chat_draw_input(input,len);
    }
    chat_close();
    poll_server();
}


/* Lobby players who sent SEEK or an invitation in the last ten minutes
 * (key 9): Up/Down pick a nick, Return invites it (like 7), ESC closes. */
#define MENU_X 44
#define MENU_Y 72
#define PLAYERS_Y 56
#define PLAYERS_H 93
static void popup_close(void) {
    field_count=0;
    solid(PANEL_X,0,256-PANEL_X,SCREEN_BOTTOM-7,C_BLACK);
    solid(0,SCREEN_BOTTOM-6,256,7,C_BLACK);
    memset(painted,255,sizeof(painted));
    memset(markers,255,sizeof(markers));
}
static void players(void) {
    uint8_t key,row=0,count,i;
    char line[20];
    exchange("pchess cplayers");
    if(reply[5]!='P' || !reply[240]) {
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
            strcpy(command,"pchess coffer ");
            memcpy(line,reply+120+row*16,16); line[16]=0;
            strcat(command,line);
            exchange(command);
            break;
        }
    }
    popup_close();
}

/* ESC pop-up. Rows: 0 AI level (left/right; the AI runs on the MSX), 1 rooms
 * on the MSXPi relay or IRC (left/right, Return saves "pchess rooms X" in
 * msxpi.ini; the TCP/IP link is always IRC), 2 link MSXPI or TCPIP (Return or
 * ESC applies it; for this run only), 3 offer a draw, 4 resign, each after a
 * Y/N, 5 rotate board, 6 chat (also the TAB key; menu() returns 2 and main()
 * opens it), 7 rematch in an online game, 8 credits, 9 exit to DOS. The AI
 * accepts a draw when it is not ahead; online the offer goes to the other
 * player, who accepts by offering too. ESC resumes the game. */
#define MENU_ROWS 10
#define MENU_H 120
static const char * const menu_rows[]={"AI LEVEL","ROOMS","LINK","OFFER DRAW","RESIGN",
                                       "ROTATE BOARD","CHAT","REMATCH","CREDITS","EXIT"};
/* Switch the link: every game and connection of the old one ends. */
static void set_link(uint8_t tcp) {
    clear_sel();
    if(online) {exchange("pchess cleave"); online=0;}
    if(tcp) {
        if(!tcp_link_start(status)) return;
        link_tcp=1;
        strcpy(status,"LINK TCPIP");
    } else {
        tcp_link_stop();
        link_tcp=0;
        strcpy(status,"LINK MSXPI");
    }
    new_game(0,0);
}
static uint8_t menu(void) {
    uint8_t key,row=0,i,quit=0,tcp=link_tcp,rooms_irc=0;
    char line[20];
    int16_t v;
    /* The server tells which rooms it uses (the reply is a level packet). */
    if(link_tcp) rooms_irc=1;
    else if(InPort(CONTROL_PORT1)<=1) {
        strcpy(command,status);
        exchange("pchess level");
        if(!memcmp(reply,"PCH1",4)) rooms_irc=reply[243]==1;
        strcpy(status,command);
    }
    draw_panel();
    field_count=0;
    solid(0,SCREEN_BOTTOM-6,256,7,C_BLACK);
    text_at(8,205,status);
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
        else if(row==0 && key==0x1c && level<6) level++;
        else if(row==1 && !tcp && !link_tcp && (key==0x1c || key==0x1d)) rooms_irc^=1;
        else if(row==2 && (key==0x1c || key==0x1d)) tcp^=1;
        else if(key==13 || key==' ') {
            if(row==1) {
                if(link_tcp || tcp) {
                    strcpy(status,"TCPIP ROOMS ARE IRC");
                    text_at(8,205,status);
                    continue;
                }
                strcpy(command,"pchess rooms ");
                strcat(command,rooms_irc?"irc":"relay");
                exchange(command);
                text_at(8,205,status);
                continue;
            }
            if(row==2) {
                if(tcp!=link_tcp) set_link(tcp);
                tcp=link_tcp;
                break;
            }
            if((row==3 || row==4) && !game_over) {
                strcpy(status,row==3?"OFFER DRAW? Y/N":"RESIGN? Y/N");
                text_at(8,205,status);
                do key=Inkey(); while(!key);
                if(key!='y' && key!='Y') strcpy(status,"GAME GOES ON");
                else if(online) exchange(row==3?"pchess cdraw":"pchess cresign");
                else if(row==4) {
                    /* Against the AI the player resigns; otherwise the side to move. */
                    uint8_t loser=vs_ai?ai_side^1:turn;
                    finish(loser^1,loser?"WHITE WINS - BLACK RESIGNED":"BLACK WINS - WHITE RESIGNED");
                } else if(!vs_ai) finish(2,"DRAW AGREED");
                else {
                    v=eval(cb); if(ai_side) v=-v;
                    if(v<=30) finish(2,"DRAW AGREED");
                    else strcpy(status,"DRAW REFUSED");
                }
                break;
            }
            if(row==5) {user_rotate^=1; set_flip(); break;}
            if(row==6) {quit=2; break;}
            if(row==7) {
                if(online && game_over) exchange("pchess creset");
                else strcpy(status,"REMATCH NEEDS AN ENDED ONLINE GAME");
                break;
            }
            if(row==8) {credits(); break;}
            if(row==9) {quit=1; break;}
        }
    }
    popup_close();
    return quit;
}

int main(void) {
    uint8_t key,joy,fire,lastjoy=0,lastfire=0,arrow_seen=0;
    uint16_t lastarrow=0,lastpoll=0,now;
    /* SCREEN 5 and the VDP commands need an MSX2 (V9938) or later. */
    if(!*(volatile uint8_t *)0xFAF8) {
        Print("PCHECKERS NEEDS AN MSX2\r\n");
        return 0;
    }
    field_count=0; pending_tune=0; coords_flip=255; flip=0; user_rotate=0;
    entry_len=0; room_entry=0; online=0; link_tcp=0; entry[0]=0;
    chat_unread=0; chat_seen=0; chat_rows=0; chat_new=0; offer_seen=0; seek_seen[0]=0;
    memset(reply,0,sizeof(reply));
    tcp_init();
    memset(painted,255,sizeof(painted));
    memset(markers,255,sizeof(markers));
    new_game(0,0);
    strcpy(status,"1 LOCAL 2 AI WHITE 3 AI BLACK 4 ROOM");
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
    while(1) {
        if(vs_ai && !game_over && turn==ai_side) {
            ai_turn();
            draw_board();
            continue;
        }
        key=Inkey();
        joy=JoystickRead(1); fire=TriggerRead(1);
        if(joy!=lastjoy) {
            if(joy==1) key=30; if(joy==3) key=28;
            if(joy==5) key=31; if(joy==7) key=29;
        }
        if(fire && !lastfire) key=' ';
        lastjoy=joy; lastfire=fire;
        now=*(volatile uint16_t *)0xFC9E;
        /* Consume rapid BIOS repeats without queuing delayed cursor moves. */
        if(key>=0x1c && key<=0x1f) {
            if(arrow_seen && (uint16_t)(now-lastarrow)<8) key=0;
            else {lastarrow=now; arrow_seen=1;}
        }
        if(!key) {
            /* Every 2 s on the MSXPi; every second on TCP/IP, where this
             * poll is also what reads the IRC connection. */
            if(online && (uint16_t)(now-lastpoll)>=(link_tcp?60:120)) {
                lastpoll=now; poll_server(); draw_board();
            }
            continue;
        }
        /* ESC in the ROOM prompt cancels it rather than opening the menu,
         * which would leave the prompt taking every key afterwards. */
        if(key==27 && room_entry) {
            room_entry=0; entry_len=0; entry[0]=0; strcpy(status,"CANCELLED");
            draw_board();
            continue;
        }
        if(key==27) {
            uint8_t quit=menu();
            if(quit==1) break;
            if(quit==2) chat_window();
            draw_board();
            continue;
        }
        if(key==9) {chat_window(); draw_board(); continue;}
        if(room_entry) {
            if(key==8 && entry_len) entry[--entry_len]=0;
            else if(key==13 && entry_len) {
                /* 1: join the room (4); 2: invite a nick (7). */
                strcpy(command,room_entry==2?"pchess coffer ":"pchess cjoin ");
                strcat(command,entry);
                clear_sel();
                if(exchange(command) && room_entry==1) {
                    online=1; vs_ai=0; chat_rows=0;
                    restart_online();
                    /* The server may hold moves already played in this room. */
                    ply_net=0; poll_server();
                }
                room_entry=0; entry_len=0; entry[0]=0;
            } else if(((key>='0' && key<='9') || (key>='a' && key<='z') || (key>='A' && key<='Z') ||
                       (room_entry==2 && (key=='_' || key=='-'))) && entry_len<16) {
                entry[entry_len++]=key; entry[entry_len]=0;
            }
        }
        else if(key==8 && entry_len) entry[--entry_len]=0;
        else if(key==13 && entry_len) {
            type_move(entry);
            entry_len=0; entry[0]=0;
        }
        else if(!entry_len && online && key>='1' && key<='5' && !confirm_leave()) {}
        else if(!entry_len && key=='1') new_game(0,0);
        else if(!entry_len && key=='2') new_game(1,0);
        else if(!entry_len && key=='3') new_game(1,1);
        else if(!entry_len && key=='4') {room_entry=1; strcpy(status,"ENTER ROOM AND RETURN");}
        else if(!entry_len && key=='5') {
            clear_sel();
            if(exchange("pchess circ")) {
                online=1; vs_ai=0; chat_rows=0;
                restart_online();
                ply_net=0;
            }
        }
        else if(!entry_len && key=='6') exchange("pchess cseek");
        else if(!entry_len && key=='7') {room_entry=2; strcpy(status,"ENTER NICK AND RETURN");}
        else if(!entry_len && key=='8') exchange("pchess caccept");
        else if(!entry_len && key=='9') players();
        else if(key==0x1e && cursor_y) cursor_y--;
        else if(key==0x1f && cursor_y<7) cursor_y++;
        else if(key==0x1d && cursor_x) cursor_x--;
        else if(key==0x1c && cursor_x<7) cursor_x++;
        else if(key==' ' || key==13) activate();
        else if(((key>='a' && key<='h') || (key>='A' && key<='H') || key=='-' || key=='x' ||
                 (key>='1' && key<='8')) && entry_len<26) {
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
