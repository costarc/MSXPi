/*
 * MSXPi PChess - Fusion-C SCREEN 8 client
 *
 * Graphical board, keyboard notation/cursor and joystick input. The MSXPi
 * server validates rules and supplies AI, IRC and room-relay opponents.
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
#define SCREEN8_BOTTOM 211

#define C_BLACK 0
#define C_WHITE 255
#define C_RED 224
#define C_GREEN 28
#define C_BLUE 73
#define C_YELLOW 252
#define C_DARK 36
#define C_LIGHT 182

/* Three columns by five rows, packed top-to-bottom, left-to-right. */
static const uint16_t font[] = {
    31599,11415,29671,29647,23497,31183,31215,29257,31727,31695,
    11245,27566,31015,27502,31143,31140,31087,23533,29847,4719,
    23469,18727,24557,27501,31599,27556,31609,27565,31183,29842,
    23407,23402,23549,23213,23186,29351
};
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
        if((uint16_t)x+n*4>252) break;
        ch=n<newlen?s[n]:' ';
        if(n>=oldlen || field_text[f][n]!=ch) {
            g=glyph(ch);
            HMMM(g*4,224,x+n*4,y,4,5);
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
static char painted[8][8];
static uint8_t markers[8][8];

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
        strcpy(status,"SERVER ERROR"); return 0;
    }
    memcpy(status,reply+72,47); status[47]=0;
    if(!reply[4]) return 0;
    for(i=0;i<8;i++) for(j=0;j<8;j++)
        board[i][j]=reply[8+i*8+j]=='.'?0:reply[8+i*8+j];
    white_turn=reply[5]; game_over=reply[7];
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

/* Build tiles once on the hidden VRAM page. HMMM is Fusion-C's assembly
 * VDP command routine: subsequent refreshes never redraw piece primitives. */
static const char tile_pieces[]=" PNBRQKpnbrqk";
static void cache_graphics(void) {
    uint8_t i,j,k,r,c,bg,sy,pixels[24]; uint16_t bits; int x,y;
    for(i=0;i<26;i++) {
        x=(i%10)*24; y=256+(i/10)*24;
        bg=i>=13?C_BLUE:C_LIGHT;
        j=i%13;
        if(!j) { HMMV(x,y,24,24,bg); continue; }
        /* Stage six rows at a time in the unused lines 212-223, alternating
         * halves so a pending HMMM never reads rows being rewritten. */
        for(k=0;k<4;k++) {
            sy=212+(k&1)*6;
            for(r=0;r<6;r++) {
                piece_row(pixels,j<7?j-1:j-7,k*6+r,bg,j<7);
                CopyRamToVram(pixels,((uint16_t)(sy+r)<<8),24);
            }
            HMMM(0,sy,x,y+k*6,24,6);
        }
    }
    for(i=0;i<42;i++) {
        bits=i>0 && i<37?font[i-1]:0;
        if(i==37) bits=448;
        if(i==38) bits=1040;
        if(i==39) bits=1488;
        if(i==40) bits=24445;
        if(i==41) bits=3640;
        for(r=0;r<5;r++) for(c=0;c<4;c++)
            pixels[r*4+c]=(c<3 && (bits & ((uint16_t)1<<(14-r*3-c))))?C_WHITE:C_DARK;
        for(r=0;r<5;r++) CopyRamToVram(pixels+r*4,((uint16_t)(224+r)<<8)+i*4,4);
    }
}

static void draw_panel(void) {
    int i;
    text_at(205,12,"PCHESS");
    text_at(205,26,white_turn ? "WHITE" : "BLACK");
    text_at(205,34,game_over?"GAME OVER":"TURN");
    text_at(205,48,"MOVES");
    for (i = 0; i < 8; i++) {
        text_at(205,58+i*9,i<move_count?moves[i]:"");
    }
    text_at(205,132,"1 LOCAL 2 AI");
    text_at(205,140,"3 ROOM");
    text_at(205,148,"4 ONLINE");
    text_at(205,156,"5 SEEK 6 ASK");
    text_at(205,164,"7 ACCEPT");
    text_at(205,174,room_entry==2?"PEER NICK":room_entry?"ROOM NAME":"MOVE");
    text_at(205,182,entry);
    text_at(205,198,"ESC MENU");
    text_at(8,205,status);
}

static void draw_board(void) {
    uint8_t x, y;
    for (y = 0; y < 8; y++) {
        for (x = 0; x < 8; x++) {
            uint8_t mark=(x==cursor_x && y==cursor_y ? 1 : 0) |
                         (x==selected_x && y==selected_y ? 2 : 0);
            uint8_t tile=0;
            int left = BOARD_X + x * SQUARE;
            int top = BOARD_Y + y * SQUARE;
            if(painted[y][x]==board[y][x] && markers[y][x]==mark) continue;
            painted[y][x]=board[y][x]; markers[y][x]=mark;
            if(board[y][x]) {
                for(tile=1;tile<13;tile++) if(tile_pieces[tile]==board[y][x]) break;
                if(tile==13) tile=0;
            }
            if((x+y)&1) tile+=13;
            HMMM((tile%10)*24,256+(tile/10)*24,left,top,24,24);
            if (x == cursor_x && y == cursor_y)
                BoxLine(left + 1, top + 1, left + 22, top + 22, C_YELLOW, 0);
            if (x == selected_x && y == selected_y)
                BoxLine(left + 3, top + 3, left + 20, top + 20, C_GREEN, 0);
        }
    }
    draw_panel();
}

static void make_move(void) {
    if(selected_x==255) return;
    strcpy(command,"pchess move ");
    command[12]='a'+selected_x; command[13]='8'-selected_y;
    command[14]='a'+cursor_x; command[15]='8'-cursor_y;
    command[16]=0;
    if((board[selected_y][selected_x]=='P' && cursor_y==0) ||
       (board[selected_y][selected_x]=='p' && cursor_y==7)) {
        command[16]='q'; command[17]=0;
    }
    if(exchange(command)) {selected_x=255; selected_y=255;}
}

/* ESC pop-up. Rows: 0 AI level (left/right choose, Return saves it to
 * msxpi.ini through "pchess level N"), 1 exit to DOS. ESC resumes the game.
 * Add rows by extending menu_rows and the switch on Return. */
#define MENU_X 44
#define MENU_Y 72
static const char *menu_rows[]={"AI LEVEL","EXIT"};
#define MENU_ROWS 2
static uint8_t menu(void) {
    uint8_t key,row=0,level=2,fields=field_count,i,quit=0;
    char line[20];
    if(exchange("pchess level") || !memcmp(reply,"PCH1",4))
        if(reply[242]>=1 && reply[242]<=8) level=reply[242];
    draw_panel();
    HMMV(MENU_X,MENU_Y,120,48,C_DARK);
    BoxLine(MENU_X,MENU_Y,MENU_X+119,MENU_Y+47,C_YELLOW,0);
    text_at(MENU_X+44,MENU_Y+5,"MENU");
    text_at(MENU_X+8,MENU_Y+38,"ESC RESUME");
    while(1) {
        for(i=0;i<MENU_ROWS;i++) {
            strcpy(line,i==row?"= ":"  ");
            strcat(line,menu_rows[i]);
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
        else if(row==0 && key==0x1c && level<8) level++;
        else if(key==13 || key==' ') {
            if(row==1) {quit=1; break;}
            strcpy(command,"pchess level ");
            line[0]='0'+level; line[1]=0; strcat(command,line);
            exchange(command);
            text_at(8,205,status);
        }
    }
    field_count=fields;
    memset(painted,255,sizeof(painted));
    memset(markers,255,sizeof(markers));
    return quit;
}

int main(void) {
    uint8_t key,joy,fire,lastjoy=0,lastfire=0,arrow_seen=0;
    uint16_t lastpoll=0,lastarrow=0,now;
    entry_len=0; room_entry=0; online=0; game_over=0;
    field_count=0;
    entry[0]=0;
    memset(moves,0,sizeof(moves));
    memset(reply,0,sizeof(reply));
    memset(painted,255,sizeof(painted));
    memset(markers,255,sizeof(markers));
    Screen(8);
    HideDisplay();
    SetColors(C_WHITE,C_DARK,C_DARK);
    *(uint8_t *)0xFFE8 |= 128;
    VDPwrite(9,*(uint8_t *)0xFFE8);
    HMMV(0,0,256,212,C_DARK);
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
        else if(!entry_len && !room_entry && (key=='1' || key=='2')) {
            online=0; selected_x=255;
            exchange(key=='1'?"pchess new local":"pchess new ai");
        }
        else if(!entry_len && !room_entry && key=='3') {room_entry=1; strcpy(status,"ENTER ROOM AND RETURN");}
        else if(!entry_len && !room_entry && key=='4') {if(exchange("pchess irc")) online=1;}
        else if(!entry_len && !room_entry && key=='5') {exchange("pchess seek");}
        else if(!entry_len && !room_entry && key=='6') {room_entry=2; strcpy(status,"ENTER PEER NICK AND RETURN");}
        else if(!entry_len && !room_entry && key=='7') {exchange("pchess accept");}
        else if(key==0x1e && cursor_y) cursor_y--;
        else if (key == 0x1f && cursor_y < 7) cursor_y++;
        else if (key == 0x1d && cursor_x) cursor_x--;
        else if (key == 0x1c && cursor_x < 7) cursor_x++;
        else if (key == ' ' || key == 13) {
            if (board[cursor_y][cursor_x] &&
                is_white(board[cursor_y][cursor_x]) == white_turn) {
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
