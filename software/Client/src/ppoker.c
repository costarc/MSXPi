/*
 * MSXPi PPoker - nine-seat no-limit Texas Hold'em tournament, SCREEN 5.
 *
 * The client draws the table and sends the player's actions.  The MSXPi (or
 * the server it is pointed at with POKERRELAY) is the dealer and holds every
 * rule: cards, blinds, side pots, the clock and eliminations.  This file is
 * the MSX side, cloned from PChess: same SCREEN 5 layout, font cache, chat
 * window, PSG jingles and MSXPi exchange ("poker <cmd>" over the C9
 * transaction the PLAYNET MSXPi transport also uses).  See PPOKER.md and
 * documents/POKER-TOURNAMENT.md.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "../../C-common/header/fusion.h"
#include "../../C-common/header/msxpi.h"
#include "arrowkeys.h"
#include "ppoker_cards.h"

#define CARD_NONE 0xFF

/* SCREEN 5 (16 colours, 4 bits per pixel) on any MSX2 with 64 KB VRAM.
 * Page 0 is displayed; page 1 (lines 256-511) holds the 53 card tiles in six
 * rows of 36 lines, then two copies of the font. */
#define C_BLACK 0
#define C_INK 1
#define C_FELT 2
#define C_FELT2 3
#define C_RED 5
#define C_GOLD 7
#define C_GREY 8
#define C_YELLOW 10
#define C_WHITE 15

static const Palette palette={{   /* colour, R, G, B */
    {0,0,0,0},{1,0,0,0},{0,4,1,0},{1,6,2,0},{5,0,0,0},{7,1,1,0},{3,2,0,0},{7,4,0,0},
    {2,2,2,0},{7,2,2,0},{6,6,0,0},{7,7,1,0},{0,0,3,0},{1,1,6,0},{4,4,4,0},{7,7,7,0}
}};
/* VRAM address of pixel (x,y), x even; y may be on page 1 (256-511). */
#define VADDR(x,y) ((uint16_t)((uint16_t)(y)*128+((x)>>1)))
#define PAIR(c) ((uint8_t)((c)*17))

/* Bold 5x7 font in 6x7 cells, one byte per row (bit 4 is the left column).
 * The same font as PChess: vertical strokes are two pixels wide, because a
 * single SCREEN 5 pixel is narrower than composite video can resolve. */
#define FONT_W 6
#define FONT_H 7
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
#define FONT_TOP 472
#define FONT2_TOP 489
#define GLYPH_X(g) (((g)%25)*FONT_W)
#define GLYPH_Y(g) (FONT_TOP+((g)/25)*8)
#define PRIVATE_FONT (FONT2_TOP-FONT_TOP)

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

/* Text is cached per position, so a repaint only writes the characters that
 * changed: the seat cells and the panel redraw every poll without flicker. */
#define FIELD_MAX 44
#define FIELD_TEXT 30
#define STATUS_X 0
#define STATUS_Y 205
static uint8_t field_x[FIELD_MAX],field_y[FIELD_MAX],field_count;
static char field_text[FIELD_MAX][FIELD_TEXT];
static char status_drawn[44];

static void text_at(uint8_t x,uint8_t y,const char *s) {
    uint8_t f,n=0,oldlen,newlen,cap,g; char ch,*ft;
    for(f=0;f<field_count;f++) if(field_x[f]==x && field_y[f]==y) break;
    if(x==STATUS_X && y==STATUS_Y) {ft=status_drawn; cap=42;}
    else {ft=field_text[f<FIELD_MAX?f:FIELD_MAX-1]; cap=FIELD_TEXT-1;}
    if(f==field_count) {
        if(field_count==FIELD_MAX) return;
        field_count++; field_x[f]=x; field_y[f]=y; ft[0]=0;
        f=field_count-1;
        if(x==STATUS_X && y==STATUS_Y) ft=status_drawn; else ft=field_text[f];
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

/* Replace a whole line.  This is text_at(): it already pads a shorter line
 * with blanks to erase what was there, and forgetting the cached length here
 * would leave the tail of the previous line on screen. */
static void text_force(uint8_t x,uint8_t y,const char *s) {text_at(x,y,s);}

/* Pixel-exact fill (LMMV): outlines start at odd x, which HMMV cannot do. */
static void solid(int x,int y,int w,int h,uint8_t color) {LMMV(x,y,w,h,color,0);}
static void frame(int x,int y,int w,uint8_t h,uint8_t color) {
    solid(x,y,w,1,color); solid(x,y+h-1,w,1,color);
    solid(x,y,1,h,color); solid(x+w-1,y,1,h,color);
}

/* Decimal, no printf on this target. */
static void u2s(char *out,uint16_t v) {
    char tmp[6]; uint8_t n=0,i;
    if(!v) {out[0]='0'; out[1]=0; return;}
    while(v && n<5) {tmp[n++]=(char)('0'+v%10); v/=10;}
    for(i=0;i<n;i++) out[i]=tmp[n-1-i];
    out[n]=0;
}

/* ---------------------------------------------------------------- cards */

#define CARD_COLS 9
#define CARD_CELL 28
static const uint8_t card_colour[4]={C_WHITE,C_INK,C_RED,C_FELT};

static uint8_t card_pixel(uint8_t tile,uint8_t y,uint8_t x) {
    uint8_t b=card_tiles[tile][y*CARD_STRIDE+x/4];
    return (b>>(6-2*(x%4)))&3;
}

/* Expand the 2-bit tiles into 4-bit VRAM rows once, on page 1. */
static void cache_cards(void) {
    uint8_t tile,y,x,px;
    uint8_t row[CARD_W/2];
    for(tile=0;tile<CARD_COUNT;tile++)
        for(y=0;y<CARD_H;y++) {
            for(x=0;x<CARD_W;x+=2) {
                px=card_colour[card_pixel(tile,y,x)]<<4;
                px|=(card_colour[card_pixel(tile,y,x+1)]&15);
                row[x/2]=px;
            }
            CopyRamToVram(row,VADDR((tile%CARD_COLS)*CARD_CELL,
                256+(tile/CARD_COLS)*CARD_H+y),CARD_W/2);
        }
}

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

static void draw_card(uint8_t card,uint8_t x,uint8_t y) {
    if(card==CARD_NONE) {solid(x,y,CARD_W,CARD_H,C_FELT); return;}
    HMMM((card%CARD_COLS)*CARD_CELL,256+(card/CARD_COLS)*CARD_H,x,y,CARD_W,CARD_H);
}

/* ---------------------------------------------------------------- state */

#define SEAT_MAX 9
#define PACKET 256
static uint8_t reply[PACKET];

/* The table as the server last sent it (packet layout: POKER-TOURNAMENT.md). */
static uint8_t g_stage,g_flags,g_seat,g_timer,g_left,g_level;
static uint8_t g_board[5],g_cards[2],g_chat_unread,g_over,g_next_level,g_kind;
static uint16_t g_pot,g_call,g_minraise,g_stack,g_bet,g_hand,g_sb,g_bb;
static char g_status[41];
static struct {
    uint8_t flags;
    uint16_t stack,bet;
    uint8_t cards[2];
    char nick[8];
} seats[SEAT_MAX];
static char g_hand_name[12];
static char g_nick[13]="PLAYER";
static char g_room[17];
static uint8_t joined,seated,entry_mode,entry_len,action_row;
static char entry[20];

static uint16_t get16(const uint8_t *p) {return (uint16_t)p[0]|((uint16_t)p[1]<<8);}

static void parse_status(void) {
    uint8_t i;
    memset(g_status,0,sizeof(g_status));
    for(i=0;i<40 && reply[208+i];i++) g_status[i]=(char)reply[208+i];
}

static void parse_table(void) {
    uint8_t i;
    g_stage=reply[6]; g_flags=reply[7];
    g_hand=get16(reply+8); g_pot=get16(reply+10); g_seat=reply[12];
    g_call=get16(reply+14); g_minraise=get16(reply+16);
    g_stack=get16(reply+18); g_bet=get16(reply+20); g_timer=reply[22];
    g_left=reply[23]; g_level=reply[24];
    g_sb=get16(reply+26); g_bb=get16(reply+28);
    for(i=0;i<5;i++) g_board[i]=reply[32+i];
    g_cards[0]=reply[37]; g_cards[1]=reply[38];
    memset(g_hand_name,0,sizeof(g_hand_name));
    for(i=0;i<10 && reply[44+i];i++) g_hand_name[i]=(char)reply[44+i];
    parse_status();
    g_chat_unread=reply[248]; g_over=reply[249]; g_next_level=reply[251];
    for(i=0;i<SEAT_MAX;i++) {
        uint8_t base=(uint8_t)(64+i*16),j;
        seats[i].flags=reply[base];
        seats[i].stack=get16(reply+base+2);
        seats[i].bet=get16(reply+base+4);
        seats[i].cards[0]=reply[base+6];
        seats[i].cards[1]=reply[base+7];
        memset(seats[i].nick,0,sizeof(seats[i].nick));
        for(j=0;j<6 && reply[base+8+j];j++) seats[i].nick[j]=(char)reply[base+8+j];
    }
    seated=(uint8_t)(g_seat<SEAT_MAX);
}

/* ---------------------------------------------------------------- link */

/* The MSXPi CPLD drives port $56 as 0 or 1 (its ready bit).  With no
 * interface the bus floats to $FF and the wait would never end. */
static uint8_t msxpi_present(void) {return (uint8_t)(InPort(CONTROL_PORT1)<=1);}

static uint8_t exchange(const char *cmd) {
    uint8_t rc,i; uint16_t size=0,sum=0;
    if(!msxpi_present()) {
        strcpy(g_status,"NO MSXPI - CHECK THE INTERFACE");
        return 0;
    }
    msxpi_link_claim();
    rc=link_command(cmd,false);
    if(rc==RC_SUCCESS) rc=link_recv(LINK_RECV_BUFFER,(uint8_t *)reply,PACKET,&size);
    msxpi_link_release();
    if(rc!=RC_SUCCESS || size!=PACKET || memcmp(reply,"POKR",4)) {
        return 0;
    }
    for(i=0;i<255;i++) sum+=reply[i];
    if((sum&0xFF)!=reply[255]) {strcpy(g_status,"BAD PACKET - RETRY"); return 0;}
    if(reply[4]==0 && (reply[5]=='C' || reply[5]=='E')) {
        g_kind=reply[5];
        if(reply[5]=='E') {parse_status(); text_at(STATUS_X,STATUS_Y,g_status);}
        return 1;
    }
    g_kind=1;
    parse_table();
    return 1;
}

/* ---------------------------------------------------------------- drawing */

#define HEADER_Y 1
#define SEAT_Y0 10
#define SEAT_H 24
#define SEAT_W 64
#define BOARD_X 26
#define BOARD_Y 92
#define MY_X 26
#define MY_Y 132
#define PANEL_X 194
#define ACTION_Y 174

static uint8_t seat_mark[SEAT_MAX];
static uint8_t painted_board[5];
static uint8_t painted_mine[2];

static void draw_header(void) {
    char line[32],num[6];
    if(!joined) {text_at(0,HEADER_Y,"PPOKER TOURNAMENT - MSXPI"); return;}
    strcpy(line,"LV"); u2s(num,g_level); strcat(line,num);
    strcat(line," "); u2s(num,g_sb); strcat(line,num); strcat(line,"/"); u2s(num,g_bb); strcat(line,num);
    strcat(line,"  HAND "); u2s(num,g_hand); strcat(line,num);
    strcat(line,"  PL"); u2s(num,g_left); strcat(line,num);
    text_at(0,HEADER_Y,line);
}

#ifndef OVAL_TABLE
/* Seat cells: three columns of three, the same order as the packet.  A gold
 * frame marks my seat, a yellow one the player on the clock. */
static void draw_seats(void) {
    uint8_t i,x,y,mark;
    char one[12],two[14],num[6],bet[6];
    for(i=0;i<SEAT_MAX;i++) {
        x=(uint8_t)((i%3)*SEAT_W); y=(uint8_t)(SEAT_Y0+(i/3)*SEAT_H);
        mark=(uint8_t)((i==g_seat?1:0)|((seats[i].flags&64)?2:0));
        if(mark!=seat_mark[i]) {
            if(mark&1) frame(x,y,SEAT_W,SEAT_H,C_GOLD);
            else if(mark&2) frame(x,y,SEAT_W,SEAT_H,C_YELLOW);
            else frame(x,y,SEAT_W,SEAT_H,C_FELT2);
            seat_mark[i]=mark;
        }
        if(!(seats[i].flags&1)) {text_at((uint8_t)(x+3),(uint8_t)(y+2),""); text_at((uint8_t)(x+3),(uint8_t)(y+11),""); continue;}
        one[0]=(char)('1'+i); one[1]=' '; one[2]=0;
        if(i==g_seat) strcat(one,">");
        strcat(one,seats[i].nick[0]?seats[i].nick:"?");
        text_at((uint8_t)(x+3),(uint8_t)(y+2),one);
        if(!seats[i].stack) strcpy(two,"OUT");
        else {
            u2s(num,seats[i].stack);
            strcpy(two,num);
            if(seats[i].flags&128) strcat(two," DISC");
            else if(seats[i].flags&8) strcat(two," ALL");
            else if(seats[i].flags&4) strcat(two," FOLD");
            else if(g_over) strcat(two," WIN");
            else if(!(seats[i].flags&2)) strcat(two," WAIT");
            else if(seats[i].bet) {u2s(bet,seats[i].bet); strcat(two,"+"); strcat(two,bet);}
        }
        text_at((uint8_t)(x+3),(uint8_t)(y+11),two);
    }
}

static void draw_board(void) {
    uint8_t i; char line[26],num[6];
    for(i=0;i<5;i++)
        if(painted_board[i]!=g_board[i]) {
            draw_card(g_board[i],(uint8_t)(BOARD_X+i*CARD_CELL),BOARD_Y);
            painted_board[i]=g_board[i];
        }
    strcpy(line,"POT "); u2s(num,g_pot); strcat(line,num);
    text_at(2,85,line);
    if(seated && (g_flags&2) && !(g_flags&4)) {
        if(g_call) {strcpy(line,"CALL "); u2s(num,g_call); strcat(line,num);}
        else strcpy(line,"CHECK");
        text_at(120,85,line);
    } else text_at(120,85,"");
}

static void draw_mine(void) {
    uint8_t i;
    for(i=0;i<2;i++)
        if(painted_mine[i]!=g_cards[i]) {
            draw_card(g_cards[i],(uint8_t)(MY_X+i*CARD_CELL),MY_Y);
            painted_mine[i]=g_cards[i];
        }
}

#endif /* !OVAL_TABLE */

#ifndef OVAL_TABLE
static void draw_panel(void) {
    char line[12],num[6];
    if(!seated) {
        text_at(PANEL_X,12,"NOT SEATED");
        text_at(PANEL_X,22,"J JOIN");
        text_at(PANEL_X,31,"H HOST");
        text_at(PANEL_X,40,"N NICK");
        text_at(PANEL_X,49,"ESC MENU");
        return;
    }
    strcpy(line,"SEAT "); u2s(num,(uint16_t)(g_seat+1)); strcat(line,num);
    text_at(PANEL_X,12,line);
    strcpy(line,"STK "); u2s(num,g_stack); strcat(line,num);
    text_at(PANEL_X,21,line);
    strcpy(line,"CALL "); u2s(num,g_call); strcat(line,num);
    text_at(PANEL_X,30,line);
    strcpy(line,"MIN "); u2s(num,g_minraise); strcat(line,num);
    text_at(PANEL_X,39,line);
    strcpy(line,"POT "); u2s(num,g_pot); strcat(line,num);
    text_at(PANEL_X,48,line);
    if(g_flags&1) {strcpy(line,"ACT "); u2s(num,g_timer); strcat(line,num); strcat(line,"S"); text_at(PANEL_X,57,line);}
    else text_at(PANEL_X,57,"");
    if(g_over) text_at(PANEL_X,68,"OVER");
}

#endif /* !OVAL_TABLE */

static const char *action_name(uint8_t row) {
    if(row==0) return "FOLD";
    if(row==1) return g_call?"CALL":"CHECK";
    if(row==2) return "BET";
    if(row==3) return "RAISE";
    return "ALL IN";
}

static void draw_actions(void) {
    char line[30];
    if(!seated || !(g_flags&1)) {
        text_at(0,ACTION_Y,""); text_at(0,(uint8_t)(ACTION_Y+9),"");
        text_at(0,(uint8_t)(ACTION_Y+18),"");
        return;
    }
    strcpy(line,"F FOLD    ");
    strcat(line,g_call?"C CALL":"C CHECK");
    text_at(0,ACTION_Y,line);
    text_at(0,(uint8_t)(ACTION_Y+9),"B BET  R RAISE  A ALL IN");
    strcpy(line,"SEL ");
    strcat(line,action_name(action_row));
    strcat(line,"  FIRE=GO TAB=CHAT");
    text_at(0,(uint8_t)(ACTION_Y+18),line);
}

#ifndef OVAL_TABLE
static void draw_mine_label(void) {
    char line[20],num[6];
    if(seated) {strcpy(line,"STK "); u2s(num,g_stack); strcat(line,num);}
    else line[0]=0;
    text_at(92,(uint8_t)(MY_Y+2),line);
    text_at(92,(uint8_t)(MY_Y+12),g_hand_name);
    text_at(92,(uint8_t)(MY_Y+22),g_over?"OVER":"");
}
#endif /* !OVAL_TABLE */

#ifdef OVAL_TABLE
/* ------------------------------------------------------------ oval table */
/* PP-OVAL-TABLE: the X68000 Poker Tournament table, whose screen is 768x512,
 * scaled by a third and fitted to 256x212.  Its geometry, for the record:
 * table centre (384,236); rings 334x158, 326x150, 306x130 and 300x124; nine
 * pods of 156x44 at
 *    (384,376) (191,343) (89,260) (124,166) (281,104)
 *    (487,104) (644,166) (679,260) (577,343),
 * clockwise from the bottom one.  A third of those, clamped to the screen
 * edges, are the pods below; the rings become 112x56, 110x54 and 106x50. */
#define OVAL_CX 128
#define OVAL_CY 88
#define POD_W 52
#define POD_H 16
static const uint8_t pod_x[9]={128, 55, 26, 26, 89,167,227,230,201};
static const uint8_t pod_y[9]={140,128, 97, 62, 39, 39, 62, 97,128};
#define OVAL_PANEL_Y 9
#define OVAL_POT_X 107
#define OVAL_POT_Y 44
#define OVAL_BOARD_X 63
#define OVAL_BOARD_Y 54
#define OVAL_MY_X 102
#define OVAL_MY_Y 96
#define OVAL_LABEL_X 36

static uint8_t oval_drawn;
/* The two lines each pod last drew, so an unchanged pod is left alone:
 * clearing and redrawing all nine every poll costs about 6 ms each. */
static char pod_line[SEAT_MAX][2][8];

/* Integer square root: the half-width of the ellipse on each row needs it and
 * the Z80 has no floating point.  The same walk as ui_x68k.c's isqrt(). */
static uint16_t isqrt16(uint16_t v) {
    uint16_t r=0,bit=0x4000;
    while(bit>v) bit>>=2;
    while(bit) {
        if(v>=r+bit) {v=(uint16_t)(v-(r+bit)); r=(uint16_t)((r>>1)+bit);}
        else r>>=1;
        bit>>=2;
    }
    return r;
}

/* A filled ellipse as one LMMV per row, the way the X68000 fills its rings. */
static void oval_fill(uint8_t cx,uint8_t cy,uint8_t rx,uint8_t ry,uint8_t colour) {
    int8_t dy; uint16_t dx,t;
    for(dy=(int8_t)(-ry);dy<=(int8_t)ry;dy++) {
        t=(uint16_t)((uint16_t)ry*(uint16_t)ry-(uint16_t)((int16_t)dy*(int16_t)dy));
        dx=(uint16_t)(((unsigned long)rx*(unsigned long)isqrt16(t))/(unsigned long)ry);
        solid((int)((int16_t)cx-(int16_t)dx),(int)((int16_t)cy+(int16_t)dy),
              (int)(2*dx+1),1,colour);
    }
}

static void draw_oval(void) {
    oval_fill(OVAL_CX,OVAL_CY,112,56,C_GREY);   /* the rail */
    oval_fill(OVAL_CX,OVAL_CY,110,54,C_FELT2);  /* the rim round the felt */
    oval_fill(OVAL_CX,OVAL_CY,106,50,C_FELT);   /* the felt */
    oval_drawn=1;
}

/* The glyph tiles carry a black background, so a label on the felt is a dark
 * patch.  Repainting that patch means the cached text has to be forgotten, or
 * text_at() would think the line is still on screen and skip it. */
static void text_forget(uint8_t x,uint8_t y) {
    uint8_t f;
    for(f=0;f<field_count;f++) if(field_x[f]==x && field_y[f]==y) {field_text[f][0]=0; return;}
}

/* Nine pods round the rim, mine always at the bottom: the pod a seat gets is
 * its seat number turned so that my seat lands on position 0. */
static void draw_pods(void) {
    uint8_t i,pos,x,y,mark;
    char one[12],two[14],num[6],bet[6];
    for(i=0;i<SEAT_MAX;i++) {
        pos=(uint8_t)((i+SEAT_MAX-g_seat)%SEAT_MAX);
        x=(uint8_t)(pod_x[pos]-POD_W/2); y=(uint8_t)(pod_y[pos]-POD_H/2);
        mark=(uint8_t)((i==g_seat?1:0)|((seats[i].flags&64)?2:0));
        one[0]=0; two[0]=0;
        if(seats[i].flags&1) {
            one[0]=(char)('1'+i); one[1]=' '; one[2]=0;
            if(i==g_seat) strcat(one,">");
            strcat(one,seats[i].nick[0]?seats[i].nick:"?");
            one[7]=0;                   /* the pod is 52 wide: seven characters */
            if(!seats[i].stack) strcpy(two,"OUT");
            else {
                u2s(num,seats[i].stack);
                strcpy(two,num);
                if(seats[i].flags&128) strcat(two,"D");
                else if(seats[i].flags&8) strcat(two,"A");
                else if(seats[i].flags&4) strcat(two,"F");
                else if(!(seats[i].flags&2)) strcat(two,"W");
                else if(seats[i].bet) {u2s(bet,seats[i].bet); strcat(two,"+"); strcat(two,bet);}
            }
            two[7]=0;
        }
        if(mark==seat_mark[i] && !strcmp(one,pod_line[i][0]) && !strcmp(two,pod_line[i][1]))
            continue;                   /* nothing about this pod changed */
        solid(x,y,POD_W,POD_H,C_BLACK);
        /* the fill erased the glyphs: forget the cached lines */
        text_forget((uint8_t)(x+3),(uint8_t)(y+2));
        text_forget((uint8_t)(x+3),(uint8_t)(y+9));
        if(mark&1) frame(x,y,POD_W,POD_H,C_GOLD);
        else if(mark&2) frame(x,y,POD_W,POD_H,C_YELLOW);
        else frame(x,y,POD_W,POD_H,C_FELT2);
        seat_mark[i]=mark;
        text_at((uint8_t)(x+3),(uint8_t)(y+2),one);
        text_at((uint8_t)(x+3),(uint8_t)(y+9),two);
        strcpy(pod_line[i][0],one);
        strcpy(pod_line[i][1],two);
    }
}

/* The panel is a 62-pixel column today and the rim pods need that space, so
 * under OVAL_TABLE it becomes one row of text under the header. */
static void draw_panel_line(void) {
    char line[44],num[6];
    if(!seated) {text_at(0,OVAL_PANEL_Y,"NOT SEATED  J JOIN  H HOST  N NICK"); return;}
    strcpy(line,"SEAT "); u2s(num,(uint16_t)(g_seat+1)); strcat(line,num);
    strcat(line," STK "); u2s(num,g_stack); strcat(line,num);
    strcat(line," CALL "); u2s(num,g_call); strcat(line,num);
    strcat(line," MIN "); u2s(num,g_minraise); strcat(line,num);
    text_at(0,OVAL_PANEL_Y,line);
    strcpy(line,"POT "); u2s(num,g_pot); strcat(line,num);
    if(g_flags&1) {strcat(line," T"); u2s(num,g_timer); strcat(line,num);}
    if(g_over) strcat(line," OVER");
    text_at(202,OVAL_PANEL_Y,line);
}

static void draw_all_oval(void) {
    uint8_t i; char line[26],num[6];
    if(!oval_drawn) draw_oval();
    draw_pods();
    for(i=0;i<5;i++)
        if(painted_board[i]!=g_board[i]) {
            draw_card(g_board[i],(uint8_t)(OVAL_BOARD_X+i*CARD_CELL),OVAL_BOARD_Y);
            painted_board[i]=g_board[i];
        }
    for(i=0;i<2;i++)
        if(painted_mine[i]!=g_cards[i]) {
            draw_card(g_cards[i],(uint8_t)(OVAL_MY_X+i*CARD_CELL),OVAL_MY_Y);
            painted_mine[i]=g_cards[i];
        }
    /* Clearing the pot each time keeps a shrink from leaving digits behind;
     * the erase needs the cached text forgotten or text_at() skips it. */
    solid(105,42,46,10,C_FELT);
    text_forget(OVAL_POT_X,OVAL_POT_Y);
    strcpy(line,"POT "); u2s(num,g_pot); strcat(line,num);
    text_at(OVAL_POT_X,OVAL_POT_Y,line);
    solid(34,94,62,20,C_FELT);
    text_forget(OVAL_LABEL_X,96); text_forget(OVAL_LABEL_X,106);
    if(seated) {strcpy(line,"STK "); u2s(num,g_stack); strcat(line,num);}
    else line[0]=0;
    text_at(OVAL_LABEL_X,96,line);
    text_at(OVAL_LABEL_X,106,g_hand_name);
    draw_header();
    draw_panel_line();
    draw_actions();
    text_at(STATUS_X,STATUS_Y,g_status);
}
#endif /* OVAL_TABLE */


static void draw_all(void) {
#ifdef OVAL_TABLE
    draw_all_oval();
#else
    draw_header();
    draw_seats();
    draw_board();
    draw_mine();
    draw_mine_label();
    draw_panel();
    draw_actions();
    text_at(STATUS_X,STATUS_Y,g_status);
#endif
}

#ifdef OVAL_TIMING
#define JIFFY (*(volatile uint16_t *)0xFC9E)
/* Jiffy bench: a fake table, then ten draws of whatever screen this build
 * has, so the 3x3 and the oval are timed by identical code. */
static void bench(void) {
    uint8_t i; uint16_t t0,t1,a,b;
    char line[44],num[6];
    joined=1; seated=1; g_seat=0; g_flags=2; g_call=20; g_pot=180; g_hand=2;
    g_level=1; g_sb=10; g_bb=20; g_left=9; g_stack=1460; g_minraise=40; g_timer=12;
    g_over=0;
    strcpy(g_hand_name,"HIGH CARD");
    g_board[0]=8; g_board[1]=12; g_board[2]=16; g_board[3]=CARD_NONE; g_board[4]=CARD_NONE;
    g_cards[0]=4; g_cards[1]=22;
    for(i=0;i<SEAT_MAX;i++) {
        seats[i].flags=1|2; seats[i].stack=(uint16_t)(1480-i*10); seats[i].bet=0;
        strcpy(seats[i].nick,"BOT4"); seats[i].nick[0]=(char)('0'+i+1);
    }
    seats[0].nick[0]='1'; seats[0].nick[1]=' '; seats[0].nick[2]='A';
    seats[0].nick[3]='N'; seats[0].nick[4]='N'; seats[0].nick[5]=0;
    field_count=0;
    HMMV(0,0,256,212,PAIR(C_BLACK));
    a=0;
#ifdef OVAL_TABLE
    t0=JIFFY;
    for(i=0;i<10;i++) {oval_drawn=0; draw_oval();}
    t1=JIFFY; a=(uint16_t)(t1-t0);
#endif
    t0=JIFFY;
    for(i=0;i<10;i++) draw_all();
    t1=JIFFY; b=(uint16_t)(t1-t0);
    strcpy(line,"10X OVAL "); u2s(num,a); strcat(line,num); strcat(line,"J 10X REDRAW ");
    u2s(num,b); strcat(line,num); strcat(line,"J");
    text_at(0,STATUS_Y,line);
    while(!Inkey());
}
#endif

static void draw_lobby(void) {
    char line[26];
    field_count=0;
    HMMV(0,9,256,212-9,PAIR(C_FELT));
    frame(8,12,240,120,C_GOLD);
    text_at(24,20,"PPOKER - NO LIMIT HOLD'EM");
    text_at(24,32,"TOURNAMENT, 9 SEATS, MSXPI");
    text_at(24,52,"J  JOIN A TABLE");
    text_at(24,62,"H  HOST A TABLE");
    text_at(24,72,"N  NICKNAME");
    text_at(24,82,"ESC  MENU");
    if(g_room[0]) {strcpy(line,"ROOM: "); strcat(line,g_room); text_at(24,100,line);}
    strcpy(line,"NICK: "); strcat(line,g_nick); text_at(24,110,line);
    text_at(24,120,"ESC MENU");
    text_at(STATUS_X,STATUS_Y,g_status);
}

/* ---------------------------------------------------------------- sound */

/* PSG channel A jingles, as in PChess: (period, jiffies) pairs, 0,0 ends.
 * Register 7 keeps port A input / port B output for the joystick. */
__sfr __at 0xA0 psg_reg;
__sfr __at 0xA1 psg_val;
static void psg(uint8_t r,uint8_t v) {psg_reg=r; psg_val=v;}
static const uint16_t tune_turn[]={143,4, 0,2, 143,4, 0,0};
static const uint16_t tune_win[]={214,8, 170,8, 143,8, 107,20, 0,0};
static const uint16_t tune_lose[]={285,14, 302,14, 320,14, 339,30, 0,0};
static const uint16_t tune_chat[]={95,4, 0,0};
static const uint16_t *pending_tune;
static void play_pending(void) {
    const uint16_t *t=pending_tune; uint16_t start;
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

/* ---------------------------------------------------------------- chat */

#define CHAT_LINES 18
#define CHAT_COLS 42
#define CHAT_TOP 12
#define CHAT_INPUT_Y 193
#define CHAT_MAX_INPUT 100
static char chat_log[CHAT_LINES][CHAT_COLS+1];
static uint8_t chat_private[CHAT_LINES],chat_rows,chat_new;

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

static void chat_add(const char *prefix,const char *text,uint8_t priv) {
    char row[CHAT_COLS+1]; uint8_t n,first=1;
    while(first || *text) {
        strcpy(row,first?prefix:"  ");
        n=(uint8_t)strlen(row);
        while(*text && n<CHAT_COLS) row[n++]=*text++;
        row[n]=0;
        chat_push(row,priv);
        first=0;
    }
}

static void chat_line(uint8_t y,const char *s,uint8_t priv) {
    uint8_t n,g;
    solid(0,y,256,FONT_H+1,C_BLACK);
    for(n=0;s[n] && n<CHAT_COLS;n++) {
        g=glyph(s[n]);
        HMMM(GLYPH_X(g),(uint8_t)(GLYPH_Y(g)+(priv?PRIVATE_FONT:0)),(uint8_t)(2+n*FONT_W),y,FONT_W,FONT_H);
    }
}

static void chat_draw_log(void) {
    uint8_t i;
    for(i=0;i<CHAT_LINES;i++) chat_line((uint8_t)(CHAT_TOP+i*9),i<chat_rows?chat_log[i]:"",(uint8_t)(i<chat_rows && chat_private[i]));
}
static void chat_draw_input(const char *input,uint8_t len) {
    char line[CHAT_COLS+1];
    uint8_t shown=(uint8_t)(len>CHAT_COLS-4?CHAT_COLS-4:len);
    strcpy(line,"> ");
    memcpy(line+2,input+len-shown,shown);
    line[2+shown]='_'; line[3+shown]=0;
    chat_line(CHAT_INPUT_Y,line,0);
}

static uint8_t chat_pull(void) {
    uint8_t i,rounds=0;
    char row[CHAT_COLS+1];
    do {
        if(!exchange("poker chat") || reply[5]!='C') return 0;
        for(i=0;i<reply[240] && i<5;i++) {
            memcpy(row,reply+8+i*44,CHAT_COLS); row[CHAT_COLS]=0;
            chat_push(row,reply[8+i*44+CHAT_COLS+1]);
        }
        g_chat_unread=reply[241];
    } while(reply[241] && ++rounds<4);
    return 1;
}

static void chat_window(void) {
    char input[CHAT_MAX_INPUT+1];
    uint8_t key,len=0;
    uint16_t lastpoll,now;
    if(!seated) {strcpy(g_status,"CHAT NEEDS A TABLE"); return;}
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
            if((uint16_t)(now-lastpoll)>=60) {
                lastpoll=now; chat_new=0;
                if(chat_pull() && chat_new) chat_draw_log();
            }
            continue;
        }
        if(key==27 || key==9) break;
        if(key==8) {if(len) input[--len]=0;}
        else if(key==13) {
            if(len) {
                char cmd[110];
                strcpy(cmd,"poker say "); strcat(cmd,input);
                if(exchange(cmd)) {
                    chat_add("YOU: ",input,0);
                    len=0; input[0]=0;
                    chat_pull(); chat_draw_log();
                    chat_line(1,"CHAT - ESC OR TAB CLOSES",0);
                } else chat_line(1,"LINK ERROR",0);
            }
        } else if(key>=32 && key<=126 && len<CHAT_MAX_INPUT) {input[len++]=key; input[len]=0;}
        chat_draw_input(input,len);
    }
    HMMV(0,0,256,212,PAIR(C_BLACK));
    field_count=0;
    memset(seat_mark,255,sizeof(seat_mark));
    memset(painted_board,255,sizeof(painted_board));
    memset(painted_mine,255,sizeof(painted_mine));
    g_chat_unread=0;
    if(pending_tune==tune_chat) pending_tune=0;
    exchange("poker poll");
}

/* ---------------------------------------------------------------- menu */

#define MENU_X 40
#define MENU_Y 52
static void popup_close(void) {
    field_count=0;
#ifdef OVAL_TABLE
    oval_drawn=0;                       /* the table itself has to be redrawn */
    memset(pod_line,0,sizeof(pod_line));
#endif
    solid(0,0,256,212,C_BLACK);
    memset(seat_mark,255,sizeof(seat_mark));
    memset(painted_board,255,sizeof(painted_board));
    memset(painted_mine,255,sizeof(painted_mine));
    status_drawn[0]=0;
}

static void credits(void) {
    solid(MENU_X,72,176,58,C_BLACK);
    frame(MENU_X,72,176,58,C_YELLOW);
    field_count=0;
    text_at(MENU_X+22,80,"PPOKER V1.0 (C) RCC 2026");
    text_at(MENU_X+40,92,"DESIGN: RCC");
    text_at(MENU_X+30,104,"PROGRAMMING: CLAUDE");
    while(!Inkey());
}

static void info_window(void) {
    uint8_t key; char line[26],num[6];
    solid(MENU_X,52,176,92,C_BLACK);
    frame(MENU_X,52,176,92,C_YELLOW);
    field_count=0;
    text_at(MENU_X+52,58,"TABLE INFO");
    strcpy(line,"ROOM "); strcat(line,g_room); text_at(MENU_X+8,72,line);
    strcpy(line,"NICK "); strcat(line,g_nick); text_at(MENU_X+8,81,line);
    strcpy(line,"PLAYERS "); u2s(num,g_left); strcat(line,num); text_at(MENU_X+8,90,line);
    strcpy(line,"LEVEL "); u2s(num,g_level); strcat(line,num);
    strcat(line," "); u2s(num,g_sb); strcat(line,num); strcat(line,"/"); u2s(num,g_bb); strcat(line,num);
    text_at(MENU_X+8,99,line);
    strcpy(line,"NEXT BLIND "); u2s(num,g_next_level); strcat(line,num); strcat(line,"S");
    text_at(MENU_X+8,108,line);
    text_at(MENU_X+62,124,"ANY KEY");
    while(!(key=Inkey()));
    popup_close();
}

/* J/H name a room, N names the player, B/R take an amount. */
static void prompt(uint8_t mode) {
    entry_mode=mode; entry_len=0; entry[0]=0;
    if(mode==1) strcpy(g_status,"ROOM NAME AND RETURN");
    else if(mode==2) strcpy(g_status,"NEW ROOM AND RETURN");
    else if(mode==3) strcpy(g_status,"YOUR NICKNAME AND RETURN");
    else if(mode==4) strcpy(g_status,"BET AMOUNT AND RETURN");
    else strcpy(g_status,"RAISE TO AMOUNT AND RETURN");
    text_force(STATUS_X,STATUS_Y,g_status);
}

static uint16_t parse_amount(void) {
    uint16_t value=0; uint8_t i=0;
    while(entry[i]>='0' && entry[i]<='9' && i<5) value=(uint16_t)(value*10+(entry[i++]-'0'));
    return value;
}

static void accept_entry(void) {
    char cmd[30],tail[10];
    if(entry_mode==4 || entry_mode==5) {
        uint16_t amount=parse_amount();
        if(amount) {
            strcpy(cmd,entry_mode==4?(g_call?"poker raise ":"poker bet "):"poker raise ");
            u2s(tail,amount); strcat(cmd,tail);
            exchange(cmd);
        }
        entry_mode=0; entry_len=0; entry[0]=0;
        return;
    }
    if(entry_mode==3) {
        if(entry_len) {
            strcpy(cmd,"poker nick "); strcat(cmd,entry);
            exchange(cmd);
            strncpy(g_nick,entry,12); g_nick[12]=0;
            strcpy(g_status,"NICK SET");
        }
        entry_mode=0; entry_len=0; entry[0]=0;
        return;
    }
    if(entry_len) {
        strcpy(cmd,entry_mode==2?"poker host ":"poker join ");
        strcat(cmd,entry);
        if(exchange(cmd) && g_kind==1 && seated) {
            strcpy(g_room,entry);
            joined=1;
            chat_rows=0;
            popup_close();
        }
    }
    entry_mode=0; entry_len=0; entry[0]=0;
}

static void leave_table(void) {
    if(!seated) return;
    exchange("poker leave");
    joined=0; seated=0; g_room[0]=0;
    strcpy(g_status,"LEFT THE TABLE");
    popup_close();
}

static uint8_t menu(void) {
    uint8_t key,row=0,i,quit=0; char line[26];
    field_count=0;
    solid(MENU_X,MENU_Y,176,96,C_BLACK);
    frame(MENU_X,MENU_Y,176,96,C_YELLOW);
    text_at(MENU_X+64,MENU_Y+5,"MENU");
    while(1) {
        for(i=0;i<6;i++) {
            strcpy(line,i==row?"= ":"  ");
            if(i==0) strcat(line,"CHAT");
            if(i==1) strcat(line,"NICKNAME");
            if(i==2) strcat(line,"TABLE INFO");
            if(i==3) strcat(line,seated?"LEAVE TABLE":"JOIN A TABLE");
            if(i==4) strcat(line,"CREDITS");
            if(i==5) strcat(line,"EXIT TO DOS");
            text_at(MENU_X+14,(uint8_t)(MENU_Y+18+i*9),line);
        }
        do key=Inkey(); while(!key);
        if(key==27) break;
        if(key==0x1e && row) row--;
        else if(key==0x1f && row<5) row++;
        else if(key==13 || key==' ') {
            if(row==0) {quit=2; break;}
            if(row==1) {prompt(3); break;}
            if(row==2) {info_window(); field_count=0; break;}
            if(row==3) {if(seated) leave_table(); else prompt(1); break;}
            if(row==4) {credits(); field_count=0; break;}
            if(row==5) {quit=1; break;}
        }
    }
    if(quit!=2) popup_close();
    return quit;
}

static void execute_row(void) {
    if(action_row==0) exchange("poker fold");
    else if(action_row==1) exchange(g_call?"poker call":"poker check");
    else if(action_row==2) prompt(4);
    else if(action_row==3) prompt(5);
    else exchange("poker allin");
}

/* The player's action sound: a blip when the clock starts on them. */
static void queue_sound(uint8_t my_turn) {
    static uint8_t was_turn;
    if(my_turn && !was_turn) pending_tune=tune_turn;
    was_turn=my_turn;
}

/* ---------------------------------------------------------------- main */

int main(void) {
    uint8_t key,joy,fire,lastjoy=0,lastfire=0,quit;
    uint16_t lastpoll=0,now;
    char line[30];

    if(!*(volatile uint8_t *)0xFAF8) {
        Print("PPOKER NEEDS AN MSX2\r\n");
        return 0;
    }
    Screen(5);
    HideDisplay();
    SetSC5Palette((Palette *)&palette);
    SetColors(C_WHITE,C_BLACK,C_BLACK);
    *(uint8_t *)0xFFE8 |= 128;
    VDPwrite(9,*(uint8_t *)0xFFE8);
    HMMV(0,0,256,212,PAIR(C_FELT));
    cache_font();
    cache_cards();
#ifdef OVAL_TIMING
    bench();
#endif
    field_count=0;
    memset(seat_mark,255,sizeof(seat_mark));
    memset(painted_board,255,sizeof(painted_board));
    memset(painted_mine,255,sizeof(painted_mine));
    joined=0; seated=0; entry_mode=0; entry_len=0; action_row=0;
    g_seat=0xFF; g_kind=0; g_status[0]=0; g_room[0]=0; g_hand=0;
    pending_tune=0;
    strcpy(g_status,"J JOIN  H HOST  N NICK");
    draw_lobby();
    ShowDisplay();
    while(1) {
        key=Inkey();
        joy=JoystickRead(1); fire=TriggerRead(1);
        if(joy!=lastjoy) {
            if(joy==1) key=30; if(joy==3) key=28;
            if(joy==5) key=31; if(joy==7) key=29;
        }
        if(fire && !lastfire) key=' ';
        lastjoy=joy; lastfire=fire;
        now=*(volatile uint16_t *)0xFC9E;
        key=arrow_gate(key);
        if(!key) {
            if(joined && (uint16_t)(now-lastpoll)>=60) {
                lastpoll=now;
                exchange("poker poll");
                draw_all();
                queue_sound((uint8_t)(seated && (g_flags&1)));
                play_pending();
            }
            continue;
        }
        if(key==27) {
            quit=menu();
            if(quit==1) break;
            if(quit==2) {chat_window(); draw_all();}
            else if(seated) draw_all(); else draw_lobby();
            arrow_done();
            continue;
        }
        if(entry_mode) {
            uint8_t limit=(uint8_t)(entry_mode==3?12:(entry_mode>=4?5:16));
            if(key==27) {entry_mode=0; entry_len=0; entry[0]=0; strcpy(g_status,"CANCELLED");}
            else if(key==8) {if(entry_len) entry[--entry_len]=0;}
            else if(key==13) accept_entry();
            else if(key>=32 && key<=126 && entry_len<limit) {entry[entry_len++]=key; entry[entry_len]=0;}
            if(entry_mode) {
                strcpy(line,entry_mode==4?"BET ":entry_mode==5?"RAISE ":
                              entry_mode==3?"NICK ":"> ");
                strcat(line,entry); strcat(line,"_");
                text_force(STATUS_X,STATUS_Y,line);
            } else if(seated) draw_all(); else draw_lobby();
            arrow_done();
            continue;
        }
        if(!seated) {
            if(key=='j'||key=='J') {prompt(1); continue;}
            if(key=='h'||key=='H') {prompt(2); continue;}
            if(key=='n'||key=='N') {prompt(3); continue;}
            if(key==9) {chat_window(); draw_lobby(); continue;}
            if(joined) {draw_all(); arrow_done();}
            continue;
        }
        if(key==9) {chat_window(); draw_all(); arrow_done(); continue;}
        if(key=='f'||key=='F') exchange("poker fold");
        else if(key=='c'||key=='C') exchange(g_call?"poker call":"poker check");
        else if(key=='a'||key=='A') exchange("poker allin");
        else if(key=='b'||key=='B') {prompt(4); continue;}
        else if(key=='r'||key=='R') {prompt(5); continue;}
        else if(key==0x1e) {if(action_row) action_row--;}
        else if(key==0x1f) {if(action_row<4) action_row++;}
        else if(key==13 || key==' ') {execute_row(); if(entry_mode) continue;}
        draw_all();
        queue_sound((uint8_t)(g_flags&1));
        play_pending();
        arrow_done();
    }
    RestoreSC5Palette();
    Screen(0);
    Cls();
    return 0;
}
