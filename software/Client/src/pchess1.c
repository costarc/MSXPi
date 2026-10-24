/*
 * MSXPi PChess1 - Fusion-C MSX1 (TMS9918, 16 KB VRAM) client
 *
 * MSX1 port of pchess.c. SCREEN 2 is used as a tile screen: the pattern and
 * colour tables hold the same 256 characters in all three banks, so the
 * board and text are refreshed by writing name-table bytes only. Squares are
 * 16x16 (2x2 characters) and pieces are the pchess.c silhouettes scaled to
 * two thirds. Cursor and selection frames are hardware sprites, avoiding the
 * two-colours-per-8-pixels limit. Server protocol is identical to pchess.c.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "../../C-common/header/fusion_hdr.h"
#include "../../C-common/header/msxpi.h"

#define NAMTBL 0x1800
#define PATTBL 0x0000
#define COLTBL 0x2000
#define SPRATR 0x1B00
#define SPRPAT 0x3800
#define BOARD_COL 1
#define BOARD_ROW 1
#define PANEL_COL 18
#define PANEL_W 14
#define FONT_BASE 96          /* ASCII 32-127 -> patterns 128-223 */
#define BLANK (32+FONT_BASE)

#define C_BLACK 1
#define C_WHITE 15
#define C_RED 8
#define C_YELLOW 11
#define C_GREEN 2
#define C_LIGHTSQ 10
#define C_DARKSQ 5

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
static char status[48]="1 LOCAL 2 AI WHT 3 AI BLK";
static char entry[24];
/* "pchess say " plus up to 100 characters of chat. */
static char command[120];
static uint8_t entry_len,room_entry,online,game_over;
/* Unread chat rows the server holds (reply[255] of every game packet), and
 * the count already beeped for. */
static uint8_t chat_unread,chat_seen;
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
/* "Tcha-Ham": a short G5 then a long C6, for a lobby SEEK. */
static const uint16_t tune_seek[]={143,5, 0,3, 107,30, 0,0};
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
/* Called with every state packet: a new draw offer beeps; a game that has
 * just ended plays the win or lose tune (any win in local two-player);
 * a new "PLAYER <nick> ..." seek announcement plays tcha-ham. */
static uint8_t offer_seen;
static char seek_seen[48];
static void queue_sounds(uint8_t was_over) {
    uint8_t offer=!memcmp(status,"OPPONENT OFFERS",15), winner;
    if(offer && !offer_seen) pending_tune=tune_offer;
    offer_seen=offer;
    if(!memcmp(status,"PLAYER ",7)) {
        if(strcmp(status,seek_seen)) pending_tune=tune_seek;
        strcpy(seek_seen,status);
    } else seek_seen[0]=0;
    if(was_over || !game_over) return;
    winner=strstr(status,"WHITE WINS")?1:strstr(status,"BLACK WINS")?2:0;
    if(winner) pending_tune=(!matched || (winner==1)==(my_side==0))?tune_win:tune_lose;
}

/* Chat scrollback, shared by both links as in pchess.c: chat_add() takes the
 * player's own words and what the TCP/IP link's IRC reader hears; with the
 * MSXPi link the chat window fetches rows from the server instead. Rows are
 * 32 characters, the width of the screen. */
#define CHAT_LINES 21
#define CHAT_COLS 32
#define SERVER_COLS 42      /* width of the rows the MSXPi server sends */
static char chat_log[CHAT_LINES][CHAT_COLS+1];
static uint8_t chat_private[CHAT_LINES];   /* 1: said privately, drawn yellow */
static uint8_t chat_rows,chat_new;

/* The BIOS font draws every printable character. */
static uint8_t glyph(char ch) {return ch>=32 && ch<127;}

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

/* TCP/IP UNAPI link, shared with pchess.c: see pchess_tcp.c. */
#include "pchess_rules.c"
#include "pchess_sha.c"
#include "pchess_tcp.c"

/* 0: commands go to the MSXPi server; 1: to local_exchange() over TCP/IP. */
static uint8_t link_tcp;

/* The MSXPi CPLD drives port $56 as 0 or 1 (its ready bit). With no
 * interface the bus floats to $FF, and CHKPIRDY() would wait on it for ever
 * (only CTRL+ESC breaks out), so no exchange starts without this. */
static uint8_t msxpi_present(void) { return InPort(CONTROL_PORT1)<=1; }

static uint8_t exchange(const char *cmd) {
    uint8_t rc,tries=0,i,j,was_over=game_over; uint16_t size=0;
    if(link_tcp) {
        local_exchange(cmd);
        size=256; rc=RC_SUCCESS;
        goto parse;
    }
    if(!msxpi_present()) {
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
parse:
    if(rc!=RC_SUCCESS || size!=256 || memcmp(reply,"PCH1",4)) {
        /* A failed background poll stays silent: the next one retries. */
        if(strcmp(cmd,"pchess poll")) strcpy(status,"LINK ERROR - RETRY");
        return 0;
    }
    /* A chat block ('C') carries text where the status would be: the chat
     * window reads it from reply and the status line stays as it was. */
    if(!reply[4] && reply[5]=='C') return 1;
    memcpy(status,reply+72,47); status[47]=0;
    if(!reply[4]) {queue_sounds(1); return 0;}
    for(i=0;i<8;i++) for(j=0;j<8;j++)
        board[i][j]=reply[8+i*8+j]=='.'?0:reply[8+i*8+j];
    white_turn=reply[5]; my_side=reply[6]; game_over=reply[7];
    matched=reply[242]==1;
    chat_unread=reply[255];
    if(chat_unread>chat_seen) pending_tune=tune_chat;
    chat_seen=chat_unread;
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

static uint8_t linebuf[32];
static void text_at(uint8_t col,uint8_t row,const char *s,uint8_t width) {
    uint8_t n; char ch;
    for(n=0;n<width;n++) {
        ch=*s?*s++:' ';
        linebuf[n]=(ch>=32 && ch<127)?ch+FONT_BASE:BLANK;
    }
    CopyRamToVram(linebuf,NAMTBL+row*32+col,width);
}

/* 24x24 piece bitmaps from pchess.c, one bit per pixel for tile rows 1-20
 * (MSB is the left column), in P N B R Q K order. Scaled to 16x16 below. */
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

static uint32_t piece_mask(uint8_t p,uint8_t r) {
    return r>=1 && r<=20 ? piece_fill[p][r-1] : 0;
}
static uint32_t detail_mask(uint8_t p,uint8_t r) {
    return r>=1 && r<=20 ? piece_detail[p][r-1] : 0;
}
/* Scale a 24-pixel row to 16 pixels: each output pixel ORs the two source
 * pixels it covers, keeping thin parts visible. */
static uint16_t scale_row(uint32_t a) {
    uint16_t out=0; uint8_t c,s0,s1;
    for(c=0;c<16;c++) {
        s0=(c*3)>>1; s1=(c*3+1)>>1;
        out<<=1;
        if((a & ((uint32_t)0x800000>>s0)) || (a & ((uint32_t)0x800000>>s1))) out|=1;
    }
    return out;
}

/* Tiles 0-12 on light squares, 13-25 on dark squares; tile t uses patterns
 * t*4 .. t*4+3 (top-left, top-right, bottom-left, bottom-right). The same
 * characters go into all three SCREEN 2 banks. */
static const char tile_pieces[]=" PNBRQKpnbrqk";
static void put_char(uint8_t n,const uint8_t *pat,const uint8_t *col) {
    uint8_t b;
    for(b=0;b<3;b++) {
        CopyRamToVram((void *)pat,PATTBL+b*0x800+n*8,8);
        CopyRamToVram((void *)col,COLTBL+b*0x800+n*8,8);
    }
}
static void cache_graphics(void) {
    uint8_t t,j,p,r,q,sq,fc,a,b,pat[4][8],colr[8]; uint16_t rows[16];
    for(t=0;t<26;t++) {
        sq=t>=13?C_DARKSQ:C_LIGHTSQ;
        j=t%13;
        if(!j) memset(rows,0,sizeof(rows));
        else {
            p=j<7?j-1:j-7;
            for(r=0;r<16;r++) {
                a=(r*3)>>1; b=(r*3+1)>>1;
                rows[r]=scale_row(piece_mask(p,a)|piece_mask(p,b)) &
                        ~scale_row(detail_mask(p,a)|detail_mask(p,b));
            }
        }
        fc=j && j<7?C_WHITE:C_BLACK;
        memset(colr,j?(fc<<4)|sq:(sq<<4)|sq,8);
        for(r=0;r<8;r++) {
            pat[0][r]=rows[r]>>8;   pat[1][r]=rows[r];
            pat[2][r]=rows[r+8]>>8; pat[3][r]=rows[r+8];
        }
        for(q=0;q<4;q++) put_char(t*4+q,pat[q],colr);
    }
}

/* SCREEN 1 loads the BIOS font into VRAM 0x0000; main() copies ASCII 32-127
 * here before switching to SCREEN 2. */
static uint8_t fontdata[96*8];
static void cache_font(void) {
    uint8_t i,colr[8];
    memset(colr,(C_WHITE<<4)|C_BLACK,8);
    for(i=0;i<96;i++) put_char(i+32+FONT_BASE,fontdata+i*8,colr);
}

static const uint8_t frame_outer[32]={
    0xFF,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0xFF,
    0xFF,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0x01,0xFF
};
static const uint8_t frame_inner[32]={
    0,0,0x3F,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x3F,0,0,
    0,0,0xFC,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0x04,0xFC,0,0
};
static uint8_t sprites_hidden;
/* Sprite 0 is the red cursor, 1 the green selection; 208 ends the list. */
static void draw_sprites(void) {
    uint8_t attr[9];
    attr[0]=(BOARD_ROW+cursor_y*2)*8-1; attr[1]=(BOARD_COL+cursor_x*2)*8;
    attr[2]=0; attr[3]=C_RED;
    attr[4]=selected_x==255?192:(BOARD_ROW+selected_y*2)*8-1;
    attr[5]=(BOARD_COL+selected_x*2)*8; attr[6]=4; attr[7]=C_GREEN;
    attr[8]=208;
    if(sprites_hidden) attr[0]=208;
    CopyRamToVram(attr,SPRATR,9);
}

static void draw_status(void) {
    text_at(0,22,status,32);
    text_at(0,23,strlen(status)>32?status+32:"",32);
}

static void draw_panel(void) {
    uint8_t i;
    text_at(PANEL_COL,1,"PCHESS MSX1",PANEL_W);
    text_at(PANEL_COL,2,!matched?"":my_side?"YOU ARE BLACK":"YOU ARE WHITE",PANEL_W);
    strcpy(command,matched && opponent[0]?"VS ":"");
    strcat(command,matched?opponent:"");
    text_at(PANEL_COL,5,command,PANEL_W);
    text_at(PANEL_COL,3,white_turn ? "WHITE" : "BLACK",PANEL_W);
    text_at(PANEL_COL,4,game_over?"GAME OVER":"TURN",PANEL_W);
    text_at(PANEL_COL,6,"MOVES",PANEL_W);
    for (i = 0; i < 8; i++)
        text_at(PANEL_COL,7+i,i<move_count?moves[i]:"",PANEL_W);
    text_at(0,18," 1 LOCAL 2 AI WHT 3 AI BLK",32);
    text_at(0,19," 4 ROOM 5 ONLINE 6 SEEK",32);
    text_at(0,20," 7 ASK 8 ACCEPT 9 PLAYERS",32);
    text_at(PANEL_COL,16,"ESC MENU",PANEL_W);
    if(chat_unread) {
        strcpy(command,"TAB CHAT ");
        command[9]=chat_unread>9?'+':'0'+chat_unread;
        command[10]=0;
        text_at(PANEL_COL,17,command,PANEL_W);
    } else text_at(PANEL_COL,17,"TAB CHAT",PANEL_W);
    strcpy(command,room_entry==2?" PEER NICK: ":room_entry?" ROOM NAME: ":" MOVE: ");
    strcat(command,entry);
    strcat(command,"_");
    text_at(0,21,command,32);
    draw_status();
}

/* Coordinates: files A-H on row 0 above the board, ranks in column 0.
 * Pop-ups clear rows 6-16, so they are rewritten with every refresh. */
static void draw_coords(void) {
    uint8_t i; char s[17];
    for(i=0;i<8;i++) {s[i*2]='A'+BX(i); s[i*2+1]=' ';}
    s[16]=0;
    text_at(BOARD_COL,0,s,16);
    for(i=0;i<8;i++) {
        s[0]='8'-BY(i); s[1]=0;
        text_at(0,BOARD_ROW+i*2,s,1);
    }
}

static void draw_board(void) {
    uint8_t x,y,tile,cell[2];
    uint16_t addr;
    draw_coords();
    for (y = 0; y < 8; y++) {
        for (x = 0; x < 8; x++) {
            if(painted[y][x]==SQ(y,x)) continue;
            painted[y][x]=SQ(y,x);
            tile=0;
            if(SQ(y,x)) {
                for(tile=1;tile<13;tile++) if(tile_pieces[tile]==SQ(y,x)) break;
                if(tile==13) tile=0;
            }
            if((x+y)&1) tile+=13;
            addr=NAMTBL+(BOARD_ROW+y*2)*32+BOARD_COL+x*2;
            cell[0]=tile*4; cell[1]=tile*4+1;
            CopyRamToVram(cell,addr,2);
            cell[0]=tile*4+2; cell[1]=tile*4+3;
            CopyRamToVram(cell,addr+32,2);
        }
    }
    draw_sprites();
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

/* ESC pop-up. Rows: 0 AI level (left/right choose, Return saves it to
 * msxpi.ini through "pchess level N"), 1 rooms on the MSXPi relay or IRC
 * ("pchess rooms X", also saved), 2 link MSXPI or TCPIP (Return or ESC
 * applies it; every start is MSXPI), 3 offer (or accept) a draw, 4 resign,
 * each after a Y/N, 5 rotate board, 6 chat (also the TAB key; menu() returns 2 and main()
 * opens it), 7 credits, 8 exit to DOS. The AI
 * answers a draw offer at once; a human opponent accepts by offering too.
 * ESC resumes the game. Add rows by extending menu_rows and the switch on
 * Return. */
#define MENU_ROW 5
/* Credits box over the board; any key closes it and resumes the game. */
#define CREDITS_COL 1
#define CREDITS_W 30
static void clear_rows(uint8_t first,uint8_t count) {
    FillVram(NAMTBL+first*32,(char)BLANK,count*32);
}
static void clear_popup(void) {
    clear_rows(MENU_ROW,13);
}
static void credits(void) {
    clear_popup();
    text_at(CREDITS_COL,MENU_ROW,  "+----------------------------+",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+1,"| PCHESS V1.1.1 (C) RCC 2026 |",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+2,"|                            |",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+3,"|  DESIGN: RCC (ARCHITECT)   |",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+4,"|PROGRAMMING: CLAUDE (INTERN)|",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+5,"|                            |",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+6,"+----------------------------+",CREDITS_W);
    while(!Inkey());
}

#define MENU_COL 2
#define MENU_W 20
static const char * const menu_rows[]={"AI LEVEL","ROOMS","LINK","OFFER DRAW","RESIGN",
                                 "ROTATE BOARD","CHAT","CREDITS","EXIT"};
#define MENU_ROWS 9
/* Switch the link: every game and connection of the old one ends. */
static void set_link(uint8_t tcp) {
    online=0; selected_x=255;
    if(tcp) {
        if(!tcp_link_start(status)) return;
        link_tcp=1;
        exchange("pchess new local");
        strcpy(status,"LINK TCPIP");
    } else {
        tcp_link_stop();
        link_tcp=0;
        strcpy(status,"LINK MSXPI");
    }
}
static uint8_t menu(void) {
    uint8_t key,row=0,level=2,rooms_irc=0,tcp=link_tcp,i,quit=0;
    char line[24];
    if(link_tcp) rooms_irc=1;
    else if(msxpi_present() &&
            (exchange("pchess level") || !memcmp(reply,"PCH1",4))) {
        if(reply[242]>=1 && reply[242]<=8) level=reply[242];
        rooms_irc=reply[243]==1;
    }
    sprites_hidden=1; draw_sprites();
    draw_status();
    clear_popup();
    text_at(MENU_COL,MENU_ROW,  "+------------------+",MENU_W);
    text_at(MENU_COL,MENU_ROW+1,"|       MENU       |",MENU_W);
    text_at(MENU_COL,MENU_ROW+11,"| ESC RESUME       |",MENU_W);
    text_at(MENU_COL,MENU_ROW+12,"+------------------+",MENU_W);
    while(1) {
        for(i=0;i<MENU_ROWS;i++) {
            strcpy(line,i==row?"| > ":"|   ");
            strcpy(line+4,menu_rows[i]);
            if(i==0) {
                strcat(line," - 0 +");
                line[strlen(line)-3]='0'+level;
            }
            /* TCP/IP rooms are always IRC: shown (and locked) as soon as
             * LINK reads TCPIP, before it is applied. */
            if(i==1) strcat(line,rooms_irc || tcp || link_tcp?" IRC":" RELAY");
            if(i==2) strcat(line,tcp?" TCPIP":" MSXPI");
            while(strlen(line)<MENU_W-1) strcat(line," ");
            strcat(line,"|");
            text_at(MENU_COL,MENU_ROW+2+i,line,MENU_W);
        }
        do key=Inkey(); while(!key);
        /* ESC keeps a LINK change too, as Return does. */
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
                draw_status();
                do key=Inkey(); while(!key);
                if(key=='y' || key=='Y')
                    exchange(row==3?"pchess draw":"pchess resign");
                else strcpy(status,"GAME GOES ON");
                break;
            }
            if(row==5) {user_rotate^=1; set_flip(); break;}
            if(row==6) {quit=2; break;}
            if(row==7) {credits(); break;}
            if(row==8) {quit=1; break;}
            if(row==2) {
                if(tcp!=link_tcp) set_link(tcp);
                tcp=link_tcp;
                break;
            }
            if(link_tcp || (row && tcp)) {
                strcpy(status,row?"TCPIP ROOMS ARE IRC":"AI NEEDS MSXPI - LINK");
                draw_status();
                continue;
            }
            strcpy(command,row?"pchess rooms ":"pchess level ");
            if(row) strcat(command,rooms_irc?"irc":"relay");
            else { line[0]='0'+level; line[1]=0; strcat(command,line); }
            exchange(command);
            if(!row && reply[242]>=1 && reply[242]<=8) level=reply[242];
            draw_status();
        }
    }
    /* Clear the pop-up rows; draw_board() repaints board and panel, and
     * this also removes the gap columns the menu or credits covered. */
    clear_popup();
    sprites_hidden=0;
    memset(painted,255,sizeof(painted));
    return quit;
}

/* Key 8: lobby players who sent SEEK or an invite in the last ten minutes.
 * Up/Down pick a nick, Return invites it (like 6), ESC closes. */
#define PLAYERS_ROW 4
#define PLAYERS_ROWS 11
static void players(void) {
    uint8_t key,row=0,count,i;
    char line[24];
    exchange("pchess players");
    if(memcmp(reply,"PCH1",4) || reply[5]!='P' || !reply[240]) return;
    count=reply[240]>7?7:reply[240];
    sprites_hidden=1; draw_sprites();
    draw_status();
    clear_rows(PLAYERS_ROW,PLAYERS_ROWS);
    text_at(MENU_COL,PLAYERS_ROW,  "+------------------+",MENU_W);
    text_at(MENU_COL,PLAYERS_ROW+1,"|     PLAYERS      |",MENU_W);
    for(i=count;i<7;i++)
        text_at(MENU_COL,PLAYERS_ROW+2+i,"|                  |",MENU_W);
    text_at(MENU_COL,PLAYERS_ROW+9,"| RET ASK ESC CLOSE|",MENU_W);
    text_at(MENU_COL,PLAYERS_ROW+10,"+------------------+",MENU_W);
    while(1) {
        for(i=0;i<count;i++) {
            strcpy(line,i==row?"|>":"| ");
            memcpy(line+2,reply+120+i*16,16); line[18]=0;
            while(strlen(line)<MENU_W-1) strcat(line," ");
            strcat(line,"|");
            text_at(MENU_COL,PLAYERS_ROW+2+i,line,MENU_W);
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
    clear_rows(PLAYERS_ROW,PLAYERS_ROWS);
    sprites_hidden=0;
    memset(painted,255,sizeof(painted));
}

/* Keys 1-4 while online (lobby or room) would drop the connection or the
 * game in progress, so they need a Y to go ahead. */
static uint8_t confirm_leave(void) {
    uint8_t key;
    strcpy(status,"LEAVE ONLINE GAME? Y/N");
    draw_status();
    do key=Inkey(); while(!key);
    if(key=='y' || key=='Y') return 1;
    strcpy(status,"STILL ONLINE");
    return 0;
}

/* Chat: a full-screen text window over the board (TAB or ESC menu, while
 * playing online). The MSXPi server queues what the opponent or channel says
 * and hands it over in blocks of up to five rows ("pchess chat"); the
 * TCP/IP link has already put it in the scrollback. Private rows are drawn
 * in yellow: while the window is open the yellow font replaces the board
 * tiles in characters 32-127, which wait in free VRAM at STASH and are put
 * back on closing (rebuilding them with cache_graphics() takes seconds). */
#define STASH 0x3840
#define CHAT_TOP 1
#define CHAT_INPUT_ROW 22
#define CHAT_MAX_INPUT 100

/* One screen row replacing whatever it held; priv draws it in yellow. */
static void chat_line(uint8_t row,const char *s,uint8_t priv) {
    uint8_t n; char ch;
    for(n=0;n<32;n++) {
        ch=*s?*s++:' ';
        if(ch<32 || ch>126) ch=' ';
        linebuf[n]=priv?ch:ch+FONT_BASE;
    }
    CopyRamToVram(linebuf,NAMTBL+row*32,32);
}

static void chat_draw_log(void) {
    uint8_t i;
    for(i=0;i<CHAT_LINES;i++)
        chat_line(CHAT_TOP+i,i<chat_rows?chat_log[i]:"",i<chat_rows && chat_private[i]);
}

static void chat_draw_input(const char *input,uint8_t len) {
    char line[CHAT_COLS+1];
    uint8_t shown=len>CHAT_COLS-3?CHAT_COLS-3:len;
    strcpy(line,"> ");
    memcpy(line+2,input+len-shown,shown);
    line[2+shown]='_'; line[3+shown]=0;
    chat_line(CHAT_INPUT_ROW,line,0);
}

/* Fetch what the server holds; false when the link failed. The server's
 * 42-character rows are wrapped again to the 32 this screen holds. */
static uint8_t chat_pull(void) {
    uint8_t i,n,rounds=0;
    char row[SERVER_COLS+1];
    do {
        if(!exchange("pchess chat") || reply[5]!='C') return 0;
        for(i=0;i<reply[240] && i<5;i++) {
            memcpy(row,reply+8+i*44,SERVER_COLS); row[SERVER_COLS]=0;
            for(n=SERVER_COLS;n && row[n-1]==' ';) row[--n]=0;
            chat_add("",row,reply[8+i*44+SERVER_COLS+1]);
        }
        chat_unread=reply[241]; chat_seen=chat_unread;
    } while(reply[241] && ++rounds<4);
    return 1;
}

static void chat_close(void) {
    uint8_t n,tile[16];
    FillVram(NAMTBL,(char)BLANK,768);
    for(n=32;n<128;n++) {
        CopyVramToRam(STASH+(n-32)*16,tile,16);
        put_char(n,tile,tile+8);
    }
    sprites_hidden=0;
    memset(painted,255,sizeof(painted));
    chat_unread=0; chat_seen=0;
    if(pending_tune==tune_chat) pending_tune=0;
}

static void chat_window(void) {
    char input[CHAT_MAX_INPUT+1];
    uint8_t key,len=0,i,colr[8],tile[16];
    uint16_t lastpoll,now;
    if(!online) {strcpy(status,"CHAT NEEDS AN ONLINE GAME (3 OR 4)"); return;}
    input[0]=0;
    sprites_hidden=1; draw_sprites();
    memset(colr,(C_YELLOW<<4)|C_BLACK,8);
    for(i=32;i<128;i++) {
        CopyVramToRam(PATTBL+i*8,tile,8);
        CopyVramToRam(COLTBL+i*8,tile+8,8);
        CopyRamToVram(tile,STASH+(i-32)*16,16);
        put_char(i,fontdata+(i-32)*8,colr);
    }
    FillVram(NAMTBL,(char)BLANK,768);
    chat_line(0,"CHAT - ESC OR TAB CLOSES",0);
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
                    chat_clean(input);
                    chat_add("YOU: ",input,matched);
                    len=0; input[0]=0;
                    chat_pull();
                    chat_draw_log();
                    chat_line(0,"CHAT - ESC OR TAB CLOSES",0);
                } else chat_line(0,status,0);
            }
        } else if(key>=32 && key<=126 && len<CHAT_MAX_INPUT) {
            input[len++]=key; input[len]=0;
        }
        chat_draw_input(input,len);
    }
    chat_close();
    exchange("pchess poll");
}

int main(void) {
    uint8_t key,joy,fire,lastjoy=0,lastfire=0,arrow_seen=0;
    uint16_t lastpoll=0,lastarrow=0,now;
    entry_len=0; room_entry=0; online=0; game_over=0; link_tcp=0;
    tcp_init();
    pending_tune=0; offer_seen=0; seek_seen[0]=0;
    chat_unread=0; chat_seen=0; chat_rows=0; chat_new=0;
    matched=0; my_side=0; flip=0; user_rotate=0; opponent[0]=0; sprites_hidden=0;
    entry[0]=0;
    memset(moves,0,sizeof(moves));
    memset(reply,0,sizeof(reply));
    memset(painted,255,sizeof(painted));
    Screen(1);
    CopyVramToRam(32*8,fontdata,sizeof(fontdata));
    Screen(2);
    SetColors(C_WHITE,C_BLACK,C_BLACK);
    /* Blank the display while building tiles; 16x16 unmagnified sprites. */
    *(uint8_t *)0xF3E0 = (*(uint8_t *)0xF3E0 & 0xBC) | 2;
    VDPwrite(1,*(uint8_t *)0xF3E0);
    FillVram(NAMTBL,(char)BLANK,768);
    cache_graphics();
    cache_font();
    CopyRamToVram((void *)frame_outer,SPRPAT,32);
    CopyRamToVram((void *)frame_inner,SPRPAT+32,32);
    draw_board();
    *(uint8_t *)0xF3E0 |= 0x40;
    VDPwrite(1,*(uint8_t *)0xF3E0);
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
        /* ESC in the ROOM or ASK prompt cancels it rather than opening the
         * menu, which would leave the prompt taking every key afterwards. */
        if(key==27 && room_entry) {
            room_entry=0; entry_len=0; entry[0]=0; strcpy(status,"CANCELLED");
            draw_board();
            continue;
        }
        if (key == 27) {
            uint8_t quit=menu();
            if(quit==1) break;
            if(quit==2) chat_window();
            draw_board();
            continue;
        }
        if(key==9) {chat_window(); draw_board(); continue;}
        if(key==8 && entry_len) entry[--entry_len]=0;
        else if(key==13 && entry_len) {
            strcpy(command,room_entry==2?"pchess offer ":room_entry?"pchess join ":"pchess move ");
            strcat(command,entry);
            if(exchange(command)) {
                if(room_entry) online=1;
                if(room_entry==1) chat_rows=0;
                room_entry=0; entry_len=0; entry[0]=0; selected_x=255;
            } else if(room_entry) {
                /* A failed ROOM or ASK closes the prompt; the status line
                 * keeps the reason. A refused move stays to be corrected. */
                room_entry=0; entry_len=0; entry[0]=0;
            }
        }
        else if(!entry_len && !room_entry && online && key>='1' && key<='5' &&
                !confirm_leave()) {}
        else if(!entry_len && !room_entry && key>='1' && key<='3') {
            online=0; selected_x=255;
            exchange(key=='1'?"pchess new local":key=='2'?"pchess new ai":"pchess new ai black");
        }
        else if(!entry_len && !room_entry && key=='4') {room_entry=1; strcpy(status,"ENTER ROOM AND RETURN");}
        else if(!entry_len && !room_entry && key=='5') {if(exchange("pchess irc")) {online=1; chat_rows=0;}}
        else if(!entry_len && !room_entry && key=='6') {exchange("pchess seek");}
        else if(!entry_len && !room_entry && key=='7') {room_entry=2; strcpy(status,"ENTER PEER NICK AND RETURN");}
        else if(!entry_len && !room_entry && key=='8') {exchange("pchess accept");}
        else if(!entry_len && !room_entry && key=='9') {players();}
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
    Screen(0);
    Cls();
    return 0;
}
