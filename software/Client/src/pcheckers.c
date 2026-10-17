/*
 * MSXPi PCheckers (DAMAS) - Fusion-C SCREEN 5 client
 *
 * Brazilian draughts on the 8x8 board, for two players or against the AI.
 * Based on PChess: same SCREEN 5 board, cursor and joystick input, but the
 * rules and the AI run here (pcheckers_rules.c), so no MSXPi server or
 * network is needed. See PCHECKERS.md.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/vdp_graph2.h"

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
/* The longest line is the 47-character status. */
static char field_text[32][48];
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
    if(newlen>47) newlen=47;
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

static void set_flip(void) {
    uint8_t want=(vs_ai && ai_side==0)^user_rotate;
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
    text_at(206,2,!vs_ai?"PCHECKER":ai_side?"AS WHITE":"AS BLACK");
    text_at(206,12,turn ? "BLACK" : "WHITE");
    text_at(206,21,game_over?"GAMEOVER":"TURN");
    text_at(206,32,"MOVES");
    for (i = 0; i < 8; i++) {
        text_at(206,41+i*9,i<move_count?moves[i]:"");
    }
    text_at(206,122,"1 LOCAL");
    text_at(206,130,"2 AI WHT");
    text_at(206,138,"3 AI BLK");
    text_at(206,197,"ESC MENU");
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
    if(winner<2) pending_tune=(!vs_ai || winner!=ai_side)?tune_win:tune_lose;
}

static void new_turn(void) {
    legal_n=gen(cb,turn,legal,0); legal_cap=gen_capture;
    if(!legal_n) finish(turn^1,turn?"WHITE WINS":"BLACK WINS");
    else if(quiet>=40) finish(2,"DRAW - 20 KING MOVES");
    else {
        strcpy(status,turn?"BLACK TO MOVE":"WHITE TO MOVE");
        if(legal_cap) strcat(status," - MUST CAPTURE");
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
    new_turn();
}

static void new_game(uint8_t ai,uint8_t human_side) {
    rules_setup(cb);
    turn=0; game_over=0; quiet=0; move_count=0; vs_ai=ai; ai_side=human_side^1;
    user_rotate=0; clear_sel();
    set_flip();
    memset(painted,255,sizeof(painted));
    new_turn();
}

/* Return/Space: first pick a piece that can move, then the destination.
 * A capture with several routes is entered one landing square at a time;
 * when only one legal move still fits the squares entered, it is played. */
static void activate(void) {
    uint8_t s=BY(cursor_y)*8+BX(cursor_x),i,hits=0,k=0;
    if(game_over || (vs_ai && turn==ai_side)) return;
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
    if(hits==1) {play(&legal[k]); return;}
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
    credits_line(82,"PCHECKERS V1.0 (C) RCC 2026");
    credits_line(98,"DESIGN: RCC (ARCHITECT)");
    credits_line(110,"PROGRAMMING: CLAUDE (INTERN)");
    while(!Inkey());
}

/* ESC pop-up. Rows: 0 AI level (left/right), 1 offer a draw, 2 resign, each
 * after a Y/N, 3 rotate board, 4 credits, 5 exit to DOS. The AI accepts a
 * draw when it is not ahead; in a two-player game the offer is taken as
 * agreed by both. ESC resumes the game. */
#define MENU_X 44
#define MENU_Y 72
#define MENU_ROWS 6
#define MENU_H 84
static void popup_close(void) {
    field_count=0;
    solid(PANEL_X,0,256-PANEL_X,SCREEN_BOTTOM-7,C_BLACK);
    solid(0,SCREEN_BOTTOM-6,256,7,C_BLACK);
    memset(painted,255,sizeof(painted));
    memset(markers,255,sizeof(markers));
}
static const char * const menu_rows[]={"AI LEVEL","OFFER DRAW","RESIGN","ROTATE BOARD","CREDITS","EXIT"};
static uint8_t menu(void) {
    uint8_t key,row=0,i,quit=0;
    char line[20];
    int16_t v;
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
            text_at(MENU_X+8,MENU_Y+16+i*9,line);
        }
        do key=Inkey(); while(!key);
        if(key==27) break;
        if(key==0x1e && row) row--;
        else if(key==0x1f && row<MENU_ROWS-1) row++;
        else if(row==0 && key==0x1d && level>1) level--;
        else if(row==0 && key==0x1c && level<6) level++;
        else if(key==13 || key==' ') {
            if((row==1 || row==2) && !game_over) {
                strcpy(status,row==1?"OFFER DRAW? Y/N":"RESIGN? Y/N");
                text_at(8,205,status);
                do key=Inkey(); while(!key);
                if(key!='y' && key!='Y') strcpy(status,"GAME GOES ON");
                else if(row==2) {
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
            if(row==3) {user_rotate^=1; set_flip(); break;}
            if(row==4) {credits(); break;}
            if(row==5) {quit=1; break;}
        }
    }
    popup_close();
    return quit;
}

int main(void) {
    uint8_t key,joy,fire,lastjoy=0,lastfire=0,arrow_seen=0;
    uint16_t lastarrow=0,now;
    /* SCREEN 5 and the VDP commands need an MSX2 (V9938) or later. */
    if(!*(volatile uint8_t *)0xFAF8) {
        Print("PCHECKERS NEEDS AN MSX2\r\n");
        return 0;
    }
    field_count=0; pending_tune=0; coords_flip=255; flip=0; user_rotate=0;
    memset(painted,255,sizeof(painted));
    memset(markers,255,sizeof(markers));
    rules_setup(cb);
    turn=0; game_over=0; vs_ai=0; ai_side=1; quiet=0; move_count=0; clear_sel();
    new_turn();
    strcpy(status,"1 LOCAL 2 AI WHITE 3 AI BLACK");
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
        if(!key) continue;
        if(key==27) {
            if(menu()) break;
            draw_board();
            continue;
        }
        if(key=='1') new_game(0,0);
        else if(key=='2') new_game(1,0);
        else if(key=='3') new_game(1,1);
        else if(key==0x1e && cursor_y) cursor_y--;
        else if(key==0x1f && cursor_y<7) cursor_y++;
        else if(key==0x1d && cursor_x) cursor_x--;
        else if(key==0x1c && cursor_x<7) cursor_x++;
        else if(key==' ' || key==13) activate();
        draw_board();
    }
    RestoreSC5Palette();
    Screen(0);
    Cls();
    return 0;
}
