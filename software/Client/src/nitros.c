/* NitrOS-9 text console. ESC closes the session; guest I/O uses DriveWire. */
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../C-common/header/msxpi.h"

static uint8_t reply[256];
static char command[128];
static const char hex[]="0123456789abcdef";
static const char no_echo[]="746d6f646520656b6f3d300d";

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
    return rc==RC_SUCCESS && size==256 && !memcmp(reply,"NTR1",4) && reply[5]<=248;
}

/* BIOS CHPUT renders on the VDP and never treats Ctrl-C as DOS abort.
 * CALSLT returns with interrupts disabled. Restore them before returning:
 * submitting a line calls CHPUT then waits for the interrupt-driven JIFFY. */
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

static uint8_t key(void) __naked {
    __asm
    push ix
    ld c,#6
    ld e,#0xFF
    call #5
    ld l,a
    ld h,#0
    pop ix
    ret
    __endasm;
}

static void display(void) {
    uint16_t i;
    for(i=0;i<reply[5];++i) {
        uint8_t c=reply[8+i];
        /* DriveWire /term is a plain SCF terminal: CR/LF, BS and bell.
         * Translate OS-9 clear-screen to MSX CLS. */
        if(c==12) put(12);
        else if(c==8 || c==7 || c==13 || c==10 || c>=32) put(c);
    }
}

int main(void) {
    const char *tail=GetCmdLineParameters();
    char args[112];
    uint8_t line[30], line_len=0, setup_echo=1;
    uint8_t pos;
    uint8_t c, n, state, i;
    uint8_t cursor_save;
    uint16_t tick;
    if(strlen(tail)>110) { Print("Arguments too long\r\n"); return 1; }
    strcpy(args,tail);
    for(pos=0;args[pos] && args[pos]!=' ';++pos)
        if(args[pos]>='A' && args[pos]<='Z') args[pos]+=32;
    tail=args;
    if(tail[0]) {
        if(strlen(tail)>110) { Print("Arguments too long\r\n"); return 1; }
        strcpy(command,"nitros "); strcat(command,tail);
        /* Administrative operations are one shot. START is only issued by
         * the interactive path, so it always has a live polling client. */
        if(strncmp(tail,"put ",4) && strncmp(tail,"get ",4) &&
           (strcmp(tail,"list") && strncmp(tail,"list ",5)) && strcmp(tail,"stop")) {
            Print("NITROS [put HOST GUEST|get GUEST HOST|list|stop]\r\n");
            return 1;
        }
        if(!exchange(command)) { Print("MSXPi connection error\r\n"); return 1; }
        display(); return reply[4]==3;
    }
    Print("NitrOS-9 on Raspberry Pi. ESC: close\r\n");
    if(!exchange("nitros start")) {
        exchange("nitros stop");
        Print("MSXPi connection error\r\n"); return 1;
    }
    /* CHPUT updates the BIOS text cursor, but applications may arrive with
     * the BIOS cursor hidden. Turn on the real blinking MSX cursor while the
     * line editor is active, then restore DOS's setting on exit. */
    cursor_save=*(volatile uint8_t *)0xFCA9;
    *(volatile uint8_t *)0xFCA9=0xFF;
    for(;;) {
        display(); state=reply[4];
        if(state==0 || state==3) break;
        strcpy(command,"nitros poll "); n=12;
        if(setup_echo) {
            /* Line editing now happens on the MSX. Turn off the guest
             * driver's echo before accepting user input, otherwise each
             * completed line would be printed twice. */
            strcpy(command+n,no_echo);
            n+=sizeof(no_echo)-1;
            setup_echo=0;
        } else {
            uint8_t submit=0, control_c=0;
            while((c=key())!=0) {
                if(c==27) goto close_session;
                if(c==13 || c==10) {
                    put(13); put(10); submit=1; break;
                }
                if(c==8 || c==127) {
                    if(line_len) {
                        --line_len;
                        put(8); put(' '); put(8);
                    }
                    continue;
                }
                if(c==3) {
                    line_len=0; control_c=1; submit=1;
                    put('^'); put('C'); put(13); put(10);
                    break;
                }
                if(c>=32 && c<=126) {
                    if(line_len<sizeof(line)) {
                        line[line_len++]=c;
                        put(c);
                    } else put(7);
                }
            }
            if(control_c) {
                command[n++]='0'; command[n++]='3';
            } else if(submit) {
                for(i=0;i<line_len;++i) {
                    command[n++]=hex[line[i]>>4];
                    command[n++]=hex[line[i]&15];
                }
                command[n++]='0'; command[n++]='d';
                line_len=0;
            }
        }
        command[n]=0;
        tick=*(volatile uint16_t *)0xFC9E;
        while(*(volatile uint16_t *)0xFC9E==tick);
        if(!exchange(command)) {
            Print("\r\nMSXPi link lost\r\n"); goto close_session;
        }
    }
    *(volatile uint8_t *)0xFCA9=cursor_save;
    return state==3;
close_session:
    if(exchange("nitros stop")) display();
    else Print("Session will stop when its lease expires.\r\n");
    *(volatile uint8_t *)0xFCA9=cursor_save;
    return 0;
}
