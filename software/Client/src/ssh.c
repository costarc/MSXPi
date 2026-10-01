/* Interactive SSH terminal. The Pi owns the SSH process; the MSX is its TTY. */
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#ifndef SSH_VT_TEST
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../C-common/header/msxpi.h"
#endif

/* Fixed 80x24 VT100 editor subset. No heap and no dependence on CRT BSS
 * initialization. The parser survives arbitrary SSH packet boundaries.
 * SGR emphasis is rendered as inverse video; DEC graphics use ASCII
 * approximations. 132-column and double-size lines are not supported. */
#define VT_COLS 80
#define VT_ROWS 24
static uint8_t cells[VT_ROWS][VT_COLS], dirty[VT_ROWS], tabs[VT_COLS];
static uint8_t vx,vy,top,bottom,sx,sy,attr,sattr,wrap,autowrap,origin;
static uint8_t saved_origin,saved_wrap,insert_mode,appkeys,cursor_on;
static uint8_t parser,private_csi,param_index,params[8],gset[2],shift;
static uint8_t saved_gset[2],saved_shift;
static uint8_t answer[30],answer_len;

static uint8_t limit(uint16_t n,uint8_t max) { return n>max?max:(uint8_t)n; }
static void vt_reset(void) {
    uint8_t i;
    memset(cells,' ',sizeof(cells)); memset(dirty,1,sizeof(dirty));
    for(i=0;i<VT_COLS;++i) tabs[i]=(i && !(i%8));
    vx=vy=sx=sy=top=attr=sattr=wrap=origin=insert_mode=appkeys=parser=0;
    param_index=private_csi=answer_len=shift=saved_shift=saved_origin=0;
    gset[0]=gset[1]=saved_gset[0]=saved_gset[1]=0;
    bottom=VT_ROWS-1; autowrap=cursor_on=saved_wrap=1;
}
static void vt_save(void) {
    sx=vx; sy=vy; sattr=attr; saved_origin=origin; saved_wrap=autowrap;
    saved_gset[0]=gset[0]; saved_gset[1]=gset[1]; saved_shift=shift;
}
static void vt_restore(void) {
    vx=sx; vy=sy; attr=sattr; origin=saved_origin; autowrap=saved_wrap;
    gset[0]=saved_gset[0]; gset[1]=saved_gset[1]; shift=saved_shift; wrap=0;
}
static void vt_scroll(uint8_t first,uint8_t last,uint8_t n,uint8_t down) {
    uint8_t y;
    n=limit(n,last-first+1);
    if(down) {
        for(y=last+1;y>first+n;) {
            --y; memcpy(cells[y],cells[y-n],VT_COLS);
        }
        for(y=first;y<first+n;++y) memset(cells[y],' ',VT_COLS);
    } else {
        for(y=first;y+n<=last;++y) memcpy(cells[y],cells[y+n],VT_COLS);
        for(;y<=last;++y) memset(cells[y],' ',VT_COLS);
    }
    for(y=first;y<=last;++y) dirty[y]=1;
}
static void vt_lf(void) {
    wrap=0;
    if(vy==bottom) vt_scroll(top,bottom,1,0);
    else if(vy<VT_ROWS-1) ++vy;
}
static void vt_erase(uint8_t y,uint8_t first,uint8_t last) {
    memset(cells[y]+first,' ',last-first+1); dirty[y]=1;
}
static void vt_answer(const char *s) {
    uint8_t n=strlen(s);
    if(answer_len+n<=sizeof(answer)) {
        memcpy(answer+answer_len,s,n); answer_len+=n;
    }
}
static void vt_position_report(void) {
    char s[12]; uint8_t n=0,r=vy+1,c=vx+1;
    if(origin) r-=top;
    s[n++]=27; s[n++]='[';
    if(r>=10) s[n++]='0'+r/10;
    s[n++]='0'+r%10; s[n++]=';';
    if(c>=10) s[n++]='0'+c/10;
    s[n++]='0'+c%10; s[n++]='R'; s[n]=0;
    vt_answer(s);
}
static void vt_csi(uint8_t c) {
    uint8_t i,n=params[0]?params[0]:1,p=params[0];
    uint8_t lo=origin?top:0,hi=origin?bottom:VT_ROWS-1;
    if(private_csi && c!='h' && c!='l') return;
    switch(c) {
    case 'A': vy=n>vy-lo?lo:vy-n; break;
    case 'B': vy=limit((uint16_t)vy+n,hi); break;
    case 'C': vx=limit((uint16_t)vx+n,VT_COLS-1); break;
    case 'D': vx=n>vx?0:vx-n; break;
    case 'G': vx=limit(n-1,VT_COLS-1); break;
    case 'd': vy=limit((uint16_t)lo+n-1,hi); break;
    case 'H': case 'f':
        vy=limit((uint16_t)lo+n-1,hi);
        vx=limit(params[1]?params[1]-1:0,VT_COLS-1); break;
    case 'J':
        if(p==0) { vt_erase(vy,vx,79); for(i=vy+1;i<24;++i) vt_erase(i,0,79); }
        if(p==1) { for(i=0;i<vy;++i) vt_erase(i,0,79); vt_erase(vy,0,vx); }
        if(p==2) { for(i=0;i<24;++i) vt_erase(i,0,79); }
        break;
    case 'K':
        if(p==0) vt_erase(vy,vx,79);
        if(p==1) vt_erase(vy,0,vx);
        if(p==2) vt_erase(vy,0,79);
        break;
    case 'L': case 'M':
        if(vy>=top && vy<=bottom) vt_scroll(vy,bottom,n,c=='L'); break;
    case 'S': case 'T': vt_scroll(top,bottom,n,c=='T'); break;
    case 'P': case '@':
        n=limit(n,VT_COLS-vx);
        if(c=='P') {
            memmove(cells[vy]+vx,cells[vy]+vx+n,VT_COLS-vx-n);
            memset(cells[vy]+VT_COLS-n,' ',n);
        } else {
            memmove(cells[vy]+vx+n,cells[vy]+vx,VT_COLS-vx-n);
            memset(cells[vy]+vx,' ',n);
        }
        dirty[vy]=1; break;
    case 'X': vt_erase(vy,vx,vx+limit(n,VT_COLS-vx)-1); break;
    case 'r':
        i=params[1]?limit(params[1]-1,23):23;
        if(n-1<i) { top=n-1; bottom=i; vx=0; vy=origin?top:0; }
        break;
    case 'm':
        for(i=0;i<=param_index;++i) {
            p=params[i];
            if(p==0) attr=0;
            else if(p==1) attr|=1;
            else if(p==4) attr|=2;
            else if(p==5) attr|=4;
            else if(p==7) attr|=8;
            else if(p==22) attr&=~1;
            else if(p==24) attr&=~2;
            else if(p==25) attr&=~4;
            else if(p==27) attr&=~8;
        }
        break;
    case 'h': case 'l':
        for(i=0;i<=param_index;++i) {
            p=params[i];
            if(private_csi) {
                if(p==1) appkeys=c=='h';
                if(p==6) { origin=c=='h'; vx=0; vy=origin?top:0; }
                if(p==7) autowrap=c=='h';
                /* Keep the local cursor visible on the MSX. */
            } else if(p==4) insert_mode=c=='h';
        }
        break;
    case 'g': if(p==0) tabs[vx]=0; else if(p==3) memset(tabs,0,sizeof(tabs)); break;
    case 'n': if(p==5) vt_answer("\033[0n"); else if(p==6) vt_position_report(); break;
    case 'c': if(p==0) vt_answer("\033[?1;0c"); break;
    case 's': vt_save(); break;
    case 'u': vt_restore(); break;
    }
    wrap=0;
}
static void vt_byte(uint8_t c) {
    if(parser==5) { if(c==7) parser=0; else if(c==27) parser=6; return; }
    if(parser==6) { parser=c=='\\'?0:5; return; }
    if(c==24 || c==26) { parser=0; return; }
    if(c==27) { parser=1; return; }
    if(c<32) {
        if(c==13) { vx=0; wrap=0; }
        else if(c==10 || c==11 || c==12) vt_lf();
        else if(c==8) { if(vx) --vx; wrap=0; }
        else if(c==9) { do { if(vx==79) break; ++vx; } while(!tabs[vx]); wrap=0; }
        else if(c==14) shift=1;
        else if(c==15) shift=0;
        return;
    }
    if(parser==1) {
        parser=0;
        if(c=='[') { parser=2; memset(params,0,sizeof(params)); param_index=private_csi=0; }
        else if(c==']' || c=='P' || c=='^' || c=='_') parser=5;
        else if(c=='(') parser=3;
        else if(c==')') parser=4;
        else if(c=='#') parser=7;
        else if(c=='7') vt_save();
        else if(c=='8') vt_restore();
        else if(c=='D') vt_lf();
        else if(c=='E') { vx=0; vt_lf(); }
        else if(c=='M') { if(vy==top) vt_scroll(top,bottom,1,1); else if(vy) --vy; wrap=0; }
        else if(c=='H') tabs[vx]=1;
        else if(c=='Z') vt_answer("\033[?1;0c");
        else if(c=='c') vt_reset();
        return;
    }
    if(parser==2) {
        if(c=='?' && !param_index && !params[0]) private_csi=1;
        else if(c>='0' && c<='9') params[param_index]=limit((uint16_t)params[param_index]*10+c-'0',255);
        else if(c==';') { if(param_index<7) ++param_index; else parser=8; }
        else if(c>=0x40 && c<=0x7e) { vt_csi(c); parser=0; }
        else parser=8;
        return;
    }
    if(parser==8) { if(c>=0x40 && c<=0x7e) parser=0; return; }
    if(parser==3 || parser==4) { gset[parser-3]=c=='0'; parser=0; return; }
    if(parser==7) { if(c=='8') { memset(cells,'E',sizeof(cells)); memset(dirty,1,sizeof(dirty)); } parser=0; return; }
    if(c==127) return;
    if(c>=128) c='?'; /* ASCII VT100, not a UTF-8 terminal. */
    if(gset[shift] && c>=0x60 && c<=0x7e) {
        if(c=='q' || (c>='o' && c<='s')) c='-';
        else if(c=='x') c='|';
        else if(c=='a') c=':';
        else c='+';
    }
    if(wrap && autowrap) { vx=0; vt_lf(); }
    wrap=0;
    if(insert_mode && vx<79) memmove(cells[vy]+vx+1,cells[vy]+vx,79-vx);
    /* Keep the character byte in the ASCII MSX font range. Encoding SGR
     * attributes in bit 7 selects the MSX Katakana glyph bank, which makes
     * ordinary coloured `ls` output look like Japanese text. */
    cells[vy][vx]=c; dirty[vy]=1;
    if(vx==79) wrap=autowrap; else ++vx;
}
static uint8_t vt_key(uint8_t c,uint8_t *out) {
    if(c>=28 && c<=31) {
        out[0]=27; out[1]=appkeys?'O':'[';
        out[2]=c==28?'C':c==29?'D':c==30?'A':'B'; return 3;
    }
    out[0]=c; return 1;
}

#ifndef SSH_VT_TEST
static uint8_t reply[256];
static uint8_t vt_mode,old_mode,old_width,old_cursor,old_lines,old_keys;
static uint8_t drawn_y;
static uint16_t name_address;

static void vt_open(void) {
    uint8_t glyph[8],i,j;
    uint16_t pattern;
    old_mode=*(uint8_t *)0xFCAF; old_width=*(uint8_t *)0xF3AE;
    old_cursor=*(uint8_t *)0xFCA9; old_lines=*(uint8_t *)0xF3B1;
    old_keys=*(uint8_t *)0xFBCE;
    Screen(0); Width(80); FunctionKeys(0);
    *(uint8_t *)0xFCA9=0;
    name_address=*(uint16_t *)0xF3B3;
    pattern=*(uint16_t *)0xF3B7;
    /* Upper font half holds inverse ASCII, independent of VDP blink state. */
    for(i=0;i<128;++i) {
        CopyVramToRam(pattern+(uint16_t)i*8,glyph,8);
        for(j=0;j<8;++j) glyph[j]^=0xFC;
        CopyRamToVram(glyph,pattern+1024+(uint16_t)i*8,8);
    }
    vt_reset(); drawn_y=0;
}
static void vt_draw(void) {
    uint8_t y,c;
    /* Repaint the previous cursor row before placing the new cursor. */
    dirty[drawn_y]=1; dirty[vy]=1;
    for(y=0;y<VT_ROWS;++y) if(dirty[y]) {
        CopyRamToVram(cells[y],name_address+(uint16_t)y*80,80); dirty[y]=0;
    }
    if(cursor_on) {
        /* Character DB is a solid block in the standard MSX font. */
        c=0xDB;
        CopyRamToVram(&c,name_address+(uint16_t)vy*80+vx,1);
    }
    drawn_y=vy;
}
static void vt_close(void) {
    *(uint8_t *)0xF3AE=old_width;
    Screen(old_mode);
    *(uint8_t *)0xF3B1=old_lines;
    FunctionKeys(old_keys?1:0);
    *(uint8_t *)0xFCA9=old_cursor;
}
/* Assembly instructions must occupy separate lines: ';' starts a comment.
 * Preserve IX for the caller's stack frame and re-enable interrupts after
 * the BIOS slot call. */
static void put(uint8_t c) __naked {
    c;
    __asm
    push ix
    ld ix,#0
    add ix,sp
    ld a,4(ix)
    ld iy,(#0xFCC0)
    ld ix,#0x00A2
    call #0x001C
    ei
    pop ix
    ret
    __endasm;
}
/* Match nitros.c: retry a rejected block within the existing exchange. */
static uint8_t exchange(const char *cmd) {
    uint8_t rc, tries=0;
    uint16_t size=0;
    msxpi_link_claim();
    rc=SendCommandToMSXPi(cmd,false);
    if(rc==RC_SUCCESS) rc=PerformHandshake(256);
    if(rc==RC_SUCCESS) {
        do { size=0; rc=RECVDATA_ONEBLOCK(reply,&size,256); }
        while(rc==RC_CHKSUM_ERR && ++tries<MAX_BLOCK_RETRIES);
    }
    msxpi_link_release();
    return rc==RC_SUCCESS && size==256 && !memcmp(reply,"SSH1",4) && reply[5]<=248;
}
static uint8_t key(void) __naked {
    __asm
    call _Inkey
    ld h,#0
    ret
    __endasm;
}
static void wait_key(void) {
    uint16_t tick;
    while(!key()) {
        tick=*(volatile uint16_t *)0xFC9E;
        while(*(volatile uint16_t *)0xFC9E==tick);
    }
}
static void show(void) {
    static uint8_t previous=0;
    uint8_t i,c;
    for(i=0;i<reply[5];++i) {
        c=reply[8+i];
        if(vt_mode) { vt_byte(c); continue; }
        if(c==10 && previous!=13) put(13);
        put(c); previous=c;
    }
    if(vt_mode) vt_draw();
}

int main(void) {
    const char *tail=GetCmdLineParameters();
    const char *hex="0123456789abcdef";
    char cmd[128];
    uint8_t line[30],n,c,i,result=0;
    uint16_t tick;
    vt_mode=1;
    if(!strncmp(tail,"/TEXT ",6) || !strncmp(tail,"/text ",6)) {
        vt_mode=0; tail+=6;
    }
    if(vt_mode && ReadMSXtype()==0) {
        Print("80-column mode needs MSX2. Use SSH /TEXT user@host\r\n"); return 1;
    }
    if(!tail[0] || strlen(tail)>100) {
        Print("SSH [/TEXT] USER@HOST [PORT]\r\n"); return 1;
    }
    strcpy(cmd,vt_mode?"ssh start --vt100 ":"ssh start "); strcat(cmd,tail);
    if(!exchange(cmd)) {
        exchange("ssh stop");
        Print("MSXPi SSH connection error\r\n"); return 1;
    }
    if(vt_mode) { vt_open(); vt_draw(); }
    else Print("SSH text terminal\r\n");
    for(;;) {
        show();
        if(reply[4]==3) {
            /* Keep the diagnostic visible before restoring the DOS screen. */
            if(vt_mode) {
                vt_byte('\r'); vt_byte('\n');
                vt_byte('P'); vt_byte('r'); vt_byte('e'); vt_byte('s');
                vt_byte('s'); vt_byte(' '); vt_byte('a'); vt_byte('n');
                vt_byte('y'); vt_byte(' '); vt_byte('k'); vt_byte('e');
                vt_byte('y'); vt_byte(' '); vt_byte('t'); vt_byte('o');
                vt_byte(' '); vt_byte('c'); vt_byte('l'); vt_byte('o');
                vt_byte('s'); vt_byte('e'); vt_byte('.');
                vt_draw(); wait_key();
            }
            break;
        }
        /* Give the interrupt-driven keyboard scanner a full tick between
         * exchanges, even when the server has no output to display. */
        tick=*(volatile uint16_t *)0xFC9E;
        while(*(volatile uint16_t *)0xFC9E==tick);
        n=0;
        if(vt_mode) { n=answer_len; memcpy(line,answer,n); answer_len=0; }
        /* Leave excess keys in the DOS buffer for the next poll. */
        while(n<=sizeof(line)-3 && (c=key())!=0) {
            if(vt_mode) n+=vt_key(c,line+n);
            else line[n++]=c;
        }
        strcpy(cmd,"ssh poll ");
        for(i=0;i<n;++i) {
            cmd[9+i*2]=hex[line[i]>>4]; cmd[10+i*2]=hex[line[i]&15];
        }
        cmd[9+n*2]=0;
        if(!exchange(cmd)) {
            result=1; break;
        }
    }
close:
    exchange("ssh stop");
    if(vt_mode) vt_close();
    Print(result?"\r\nMSXPi SSH link lost\r\n":"\r\nSSH closed\r\n");
    return result;
}
#endif
