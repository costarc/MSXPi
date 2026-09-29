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
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
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

static uint8_t exchange(const char *cmd) {
    uint8_t rc,tries=0,i,j; uint16_t size=0;
    msxpi_link_claim();
    rc=SendCommandToMSXPi(cmd,false);
    if(rc==RC_SUCCESS) rc=PerformHandshake(256);
    if(rc==RC_SUCCESS) {
        do { size=0; rc=RECVDATA_ONEBLOCK(reply,&size,256); }
        while(rc==RC_CHKSUM_ERR && ++tries<MAX_BLOCK_RETRIES);
    }
    msxpi_link_release();
    if(rc!=RC_SUCCESS || size!=256 || memcmp(reply,"PCH1",4)) {
        /* A failed background poll stays silent: the next one retries. */
        if(strcmp(cmd,"pchess poll")) strcpy(status,"LINK ERROR - RETRY");
        return 0;
    }
    memcpy(status,reply+72,47); status[47]=0;
    if(!reply[4]) return 0;
    for(i=0;i<8;i++) for(j=0;j<8;j++)
        board[i][j]=reply[8+i*8+j]=='.'?0:reply[8+i*8+j];
    white_turn=reply[5]; my_side=reply[6]; game_over=reply[7];
    matched=reply[242]==1;
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
    text_at(0,18," 1 LOCAL  2 AI  3 ROOM 4 ONLINE",32);
    text_at(0,19," 5 SEEK 6 ASK 7 ACCEPT 8 PLAYERS",32);
    text_at(0,20," ESC MENU",32);
    strcpy(command,room_entry==2?" PEER NICK: ":room_entry?" ROOM NAME: ":" MOVE: ");
    strcat(command,entry);
    strcat(command,"_");
    text_at(0,21,command,32);
    draw_status();
}

static void draw_board(void) {
    uint8_t x,y,tile,cell[2];
    uint16_t addr;
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
 * msxpi.ini through "pchess level N"), 1 offer (or accept) a draw, 2
 * resign, each after a Y/N, 3 rotate board, 4 credits, 5 exit to DOS. The AI
 * answers a draw offer at once; a human opponent accepts by offering too. ESC
 * resumes the game. Add rows by extending menu_rows and the switch on
 * Return. */
#define MENU_ROW 6
/* Credits box over the board; any key closes it and resumes the game. */
#define CREDITS_COL 1
#define CREDITS_W 30
static void clear_rows(uint8_t first,uint8_t count) {
    FillVram(NAMTBL+first*32,(char)BLANK,count*32);
}
static void clear_popup(void) {
    clear_rows(MENU_ROW,11);
}
static void credits(void) {
    clear_popup();
    text_at(CREDITS_COL,MENU_ROW,  "+----------------------------+",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+1,"|  PCHESS V1.0 (C) RCC 2026  |",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+2,"|                            |",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+3,"|        DESIGN: RCC         |",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+4,"|PROGRAMMING: CLAUDE (INTERN)|",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+5,"|                            |",CREDITS_W);
    text_at(CREDITS_COL,MENU_ROW+6,"+----------------------------+",CREDITS_W);
    while(!Inkey());
}

#define MENU_COL 2
#define MENU_W 20
static const char * const menu_rows[]={"AI LEVEL","OFFER DRAW","RESIGN","ROTATE BOARD",
                                 "CREDITS","EXIT"};
#define MENU_ROWS 6
static uint8_t menu(void) {
    uint8_t key,row=0,level=2,i,quit=0;
    char line[24];
    if(exchange("pchess level") || !memcmp(reply,"PCH1",4))
        if(reply[242]>=1 && reply[242]<=8) level=reply[242];
    sprites_hidden=1; draw_sprites();
    draw_status();
    clear_popup();
    text_at(MENU_COL,MENU_ROW,  "+------------------+",MENU_W);
    text_at(MENU_COL,MENU_ROW+1,"|       MENU       |",MENU_W);
    text_at(MENU_COL,MENU_ROW+8,"|                  |",MENU_W);
    text_at(MENU_COL,MENU_ROW+9,"| ESC RESUME       |",MENU_W);
    text_at(MENU_COL,MENU_ROW+10,"+------------------+",MENU_W);
    while(1) {
        for(i=0;i<MENU_ROWS;i++) {
            strcpy(line,i==row?"| > ":"|   ");
            strcpy(line+4,menu_rows[i]);
            if(i==0) {
                strcat(line," - 0 +");
                line[strlen(line)-3]='0'+level;
            }
            while(strlen(line)<MENU_W-1) strcat(line," ");
            strcat(line,"|");
            text_at(MENU_COL,MENU_ROW+2+i,line,MENU_W);
        }
        do key=Inkey(); while(!key);
        if(key==27) break;
        if(key==0x1e && row) row--;
        else if(key==0x1f && row<MENU_ROWS-1) row++;
        else if(row==0 && key==0x1d && level>1) level--;
        else if(row==0 && key==0x1c && level<8) level++;
        else if(key==13 || key==' ') {
            if(row==1 || row==2) {
                strcpy(status,row==1?"OFFER DRAW? Y/N":"RESIGN? Y/N");
                draw_status();
                do key=Inkey(); while(!key);
                if(key=='y' || key=='Y')
                    exchange(row==1?"pchess draw":"pchess resign");
                else strcpy(status,"GAME GOES ON");
                break;
            }
            if(row==3) {user_rotate^=1; set_flip(); break;}
            if(row==4) {credits(); break;}
            if(row==5) {quit=1; break;}
            strcpy(command,"pchess level ");
            line[0]='0'+level; line[1]=0; strcat(command,line);
            exchange(command);
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

int main(void) {
    uint8_t key,joy,fire,lastjoy=0,lastfire=0,arrow_seen=0;
    uint16_t lastpoll=0,lastarrow=0,now;
    entry_len=0; room_entry=0; online=0; game_over=0;
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
            if(online && (uint16_t)(now-lastpoll)>=120) {
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
    Screen(0);
    Cls();
    return 0;
}
