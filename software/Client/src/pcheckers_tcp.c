/*
 * PCheckers over TCP/IP UNAPI (InterNestor Lite, GR8NET, ObsoNET...), chosen
 * with LINK in the ESC menu. local_exchange() takes the same "pchess ..."
 * commands the MSXPi server does (cjoin, circ, cseek, coffer, caccept,
 * cplayers, cmove, cpoll, cdraw, cresign, creset, cleave, say, chat) and answers with the same 256-byte PCH1 packet, so the
 * rest of pcheckers.c does not know which link is in use.
 *
 * Rooms and the lobby are PChess's own IRC channels (#pchess-<room>, #msxpi),
 * so chess and checkers players share the public talk; the game lines are
 * "PCH1 CK ..." (see peer_receive()), which PChess ignores.
 * IRC over plain TCP: no TLS on a Z80, so the server must accept port 6667
 * (Libera does). The AI plays on the MSX itself and needs no link.
 *
 * PCHESS.INI in the current directory may set IRCADDR, IRCPORT and IRCNICK
 * (KEY=VALUE lines); the defaults are irc.libera.chat, 6667 and pchXXXX.
 */

/* ---------------------------------------------------------------- UNAPI */

/* Registers for raw_call(); read and written by its assembly. */
uint8_t ur_a;
uint16_t ur_bc,ur_de,ur_hl,ur_ix;
uint16_t un_ix,un_iy;
uint8_t un_jp[3];
static uint8_t un_slot,un_seg;
static uint16_t un_addr,un_helper;

/* Call un_jp (a JP to the target) with A, BC, DE, HL, IX and IY loaded
 * from the variables above; the outputs are stored back. */
static void raw_call(void) __naked {
__asm
    push ix
    push iy
    ld ix,(_un_ix)
    ld iy,(_un_iy)
    ld a,(_ur_a)
    ld bc,(_ur_bc)
    ld de,(_ur_de)
    ld hl,(_ur_hl)
    call _un_jp
    ld (_ur_bc),bc
    ld (_ur_de),de
    ld (_ur_hl),hl
    ld (_ur_ix),ix
    ld (_ur_a),a
    pop iy
    pop ix
    ret
__endasm;
}

static void jp_to(uint16_t target) {
    un_jp[0]=0xC3; un_jp[1]=(uint8_t)target; un_jp[2]=(uint8_t)(target>>8);
}

#define EXTBIO 0xFFCA
#define ARG 0xF847
static void extbio(uint8_t a,uint8_t b,uint16_t hl) {
    memcpy((char *)ARG,"TCP/IP",7);
    jp_to(EXTBIO);
    ur_a=a; ur_bc=(uint16_t)b<<8; ur_de=0x2222; ur_hl=hl;
    raw_call();
}

/* Find the first TCP/IP implementation and, when it lives in a mapped RAM
 * segment (InterNestor Lite), the UNAPI RAM helper that calls it. */
static uint8_t tcp_find(void) {
    extbio(0,0,0);
    if(!(ur_bc>>8)) return 0;
    extbio(1,0,0);
    un_slot=ur_a; un_seg=(uint8_t)(ur_bc>>8); un_addr=ur_hl;
    un_helper=0;
    if(un_seg!=0xFF) {
        extbio(0xFF,0,0);
        un_helper=ur_hl;
        if(!un_helper) return 0;
    }
    return 1;
}

/* Call routine 'fn' of the implementation; returns its error code (A). */
static uint8_t unapi(uint8_t fn) {
    if(un_seg!=0xFF) {
        jp_to(un_helper);                   /* CALL_MAP */
        un_ix=un_addr; un_iy=((uint16_t)un_slot<<8)|un_seg;
    } else if(un_addr>=0xC000) {
        jp_to(un_addr);
    } else {
        jp_to(0x001C);                      /* CALSLT */
        un_ix=un_addr; un_iy=(uint16_t)un_slot<<8;
    }
    ur_a=fn;
    raw_call();
    return ur_a;
}

#define TCPIP_DNS_Q 6
#define TCPIP_DNS_S 7
#define TCPIP_TCP_OPEN 13
#define TCPIP_TCP_CLOSE 14
#define TCPIP_TCP_ABORT 15
#define TCPIP_TCP_STATE 16
#define TCPIP_TCP_SEND 17
#define TCPIP_TCP_RCV 18
#define ERR_NO_DATA 3
#define ERR_BUFFER 13

/* Buffers handed to the implementation must not be in page 1, where the
 * RAM helper and CALSLT map it. PChess is large enough that its static
 * data is in page 2; net_memory() checks that, and that the stack still
 * has room below the TPA top (extra drives and INL lower it). */
#define RX_SIZE 384    /* longer IRC lines are dropped */
typedef struct {
    char rx[RX_SIZE];
    char tx[300];
    uint8_t open[13];
    char host[64];
} NetMem;
static NetMem net_area;
static NetMem *net;
#define STACK_ROOM 768

static char *put_hex(char *out,uint16_t v) {
    uint8_t i;
    for(i=0;i<4;i++,v<<=4) *out++="0123456789ABCDEF"[v>>12];
    *out=0;
    return out;
}

/* 0 with a status naming the addresses when it cannot. */
static uint8_t net_memory(char *status) {
    uint16_t top=*(uint16_t *)0x0006;
    if((uint16_t)&net_area<0x8000) { strcpy(status,"TCP/IP BUFFER IN PAGE 1"); return 0; }
    if(top<heap_top || top-heap_top<STACK_ROOM) {
        char *p;
        strcpy(status,"LOW MEMORY: TPA "); p=put_hex(status+16,top);
        strcpy(p," END "); put_hex(p+5,heap_top);
        return 0;
    }
    net=&net_area;
    return 1;
}

/* ------------------------------------------------------------ utilities */

#define JIFFY (*(volatile uint16_t *)0xFC9E)
#define SECONDS(n) ((uint16_t)((n)*60u))

static uint16_t rnd_state;
uint8_t rnd_r;
static void read_r(void) __naked {
__asm
    ld a,r
    ld (_rnd_r),a
    ret
__endasm;
}
static uint8_t rnd(void) {
    read_r();
    rnd_state=rnd_state*25173u+13849u+JIFFY+rnd_r;
    return (uint8_t)(rnd_state>>8);
}

static char fold_char(char c) {
    if(c>='A' && c<='Z') return (char)(c+32);
    if(c=='[') return '{';
    if(c==']') return '}';
    if(c=='\\') return '|';
    if(c=='^') return '~';
    return c;
}
/* IRC nick/channel comparison (RFC 1459 case mapping), as fold(). */
static uint8_t same(const char *a,const char *b) {
    while(*a && fold_char(*a)==fold_char(*b)) { a++; b++; }
    return fold_char(*a)==fold_char(*b);
}
static int8_t fold_cmp(const char *a,const char *b) {
    while(*a && fold_char(*a)==fold_char(*b)) { a++; b++; }
    return fold_char(*a)<fold_char(*b)?-1:fold_char(*a)>fold_char(*b)?1:0;
}

static uint8_t valid_nick(const char *s) {
    uint8_t n=0;
    if(!((*s>='A' && *s<='Z') || (*s>='a' && *s<='z'))) return 0;
    for(;*s;s++,n++) {
        char c=*s;
        if(n>15 || !((c>='A' && c<='Z') || (c>='a' && c<='z') || (c>='0' && c<='9') || c=='_' || c=='-'))
            return 0;
    }
    return 1;
}

static char *put_dec(char *out,uint16_t n) {
    char d[6]; uint8_t i=0;
    do { d[i++]=(char)('0'+n%10); n/=10; } while(n);
    while(i) *out++=d[--i];
    *out=0;
    return out;
}

/* Errors abort a command with a message, like the server's ValueError. */
static const char *fail;

/* ------------------------------------------------------------ IRC peer */

#define PH_LOBBY 0
#define PH_OFFERED 1
#define PH_ACCEPTED 2
#define PH_PLAYING 3
#define PH_ERROR 4

#define NET_OFF 0
#define NET_DNS 1
#define NET_OPEN 2
#define NET_REGISTER 3
#define NET_READY 4

#define INBOX 8
#define PATH_MAX_TEXT 26
static struct {
    uint8_t net,conn,ready,announce;
    uint16_t started;
    char nick[17],peer[17],match[1],room[26],invite[17];
    uint8_t phase,side,draw_offer,result,has_invite,seeked;
    uint16_t last_seek;
    char players[7][17]; uint16_t seen_at[7]; uint8_t players_n;
    char status[48];
    /* Moves received and not yet handed to the client, as "c3e5g7". */
    char inbox[INBOX][PATH_MAX_TEXT+1]; uint8_t inbox_n;
    uint16_t ply;
    uint16_t rx_len;
} irc;
/* side: 0 white, 1 black. draw_offer: 0 none, 1 me, 2 peer. result: 0 none,
 * 1 white wins (black resigned), 2 black wins, 3 draw agreed. ply: moves
 * played in the game, mine and received. */

static char cfg_host[48]="irc.libera.chat";
static uint16_t cfg_port=6667;
static char cfg_nick[17];

static void set_status(const char *s) { strncpy(irc.status,s,47); irc.status[47]=0; }

/* Send one IRC line (CR LF added). It is built straight in the network
 * buffer net->tx. The parts must not point into net->tx. */
static uint8_t irc_line(const char *a,const char *b,const char *c,const char *d) {
    uint8_t tries=0,err;
    uint16_t n=strlen(a)+(b?strlen(b):0)+(c?strlen(c):0)+(d?strlen(d):0);
    if(irc.net<NET_REGISTER || n>296) return 0;
    strcpy(net->tx,a);
    if(b) strcat(net->tx,b);
    if(c) strcat(net->tx,c);
    if(d) strcat(net->tx,d);
    net->tx[n++]='\r'; net->tx[n++]='\n';
    do {
        ur_bc=((uint16_t)irc.conn<<8)|1; ur_de=(uint16_t)net->tx; ur_hl=n;
        err=unapi(TCPIP_TCP_SEND);
        if(err!=ERR_BUFFER) break;
        { uint16_t t=JIFFY; while(JIFFY==t); }
    } while(++tries<120);
    return err==0;
}

static uint8_t say(const char *target,const char *text) {
    if(!irc.ready) { fail="Lobby not ready; wait"; return 0; }
    if(!irc_line("PRIVMSG ",target," :",text)) { fail="Lobby send failed"; return 0; }
    return 1;
}

static uint8_t playing(void) { return irc.phase==PH_PLAYING; }
/* The channel everyone shares with PChess: #msxpi, or the room's. */
static const char *chan(void) { return irc.room[0]?irc.room:"#msxpi"; }
static uint8_t is_free(void) {
    return irc.phase==PH_LOBBY || irc.phase==PH_ERROR || (irc.phase==PH_PLAYING && irc.result);
}

/* "pchess say TEXT": to the opponent once matched, else to the channel.
 * text is the caller's command buffer and is cleaned in place; it has room
 * for the one blank that keeps chat from looking like a game message. */
static void chat_say(char *text) {
    chat_clean(text);
    if(!*text) { fail="Nothing to say"; return; }
    if(!strncmp(text,"PCH1",4)) { memmove(text+1,text,strlen(text)+1); text[0]=' '; }
    say(playing() && irc.peer[0]?irc.peer:chan(),text);
}

static void new_game_state(void) {
    irc.ply=0; irc.draw_offer=0; irc.result=0; irc.inbox_n=0;
}

static void pair(const char *nick,uint8_t side) {
    strncpy(irc.peer,nick,16); irc.peer[16]=0;
    irc.phase=PH_PLAYING; irc.side=side;
    new_game_state();
    set_status(side?"YOU ARE BLACK":"YOU ARE WHITE");
}

/* The lower nick plays white, so both ends agree without a message. */
static void pair_by_name(const char *nick) {
    pair(nick,fold_cmp(irc.nick,nick)<0?0:1);
}

static void seen(const char *nick) {
    uint8_t i;
    for(i=0;i<irc.players_n;i++) if(same(irc.players[i],nick)) break;
    if(i==irc.players_n) {
        if(i==7) { memmove(irc.players[0],irc.players[1],6*17); memmove(irc.seen_at,irc.seen_at+1,12); i=6; }
        else irc.players_n++;
    } else {
        /* Newest last. */
        for(;i+1<irc.players_n;i++) { strcpy(irc.players[i],irc.players[i+1]); irc.seen_at[i]=irc.seen_at[i+1]; }
    }
    strncpy(irc.players[i],nick,16); irc.players[i][16]=0;
    irc.seen_at[i]=JIFFY;
}

static uint8_t valid_path(const char *s) {
    uint8_t n=0;
    for(;s[n];n+=2)
        if(!(s[n]>='a' && s[n]<='h' && s[n+1]>='1' && s[n+1]<='8')) return 0;
    return n>=4 && n<=PATH_MAX_TEXT;
}

/* Ordinary talk: the opponent's private lines, or the room channel. Rows go
 * straight into the chat scrollback, yellow when private; each counts as
 * unread until the window shows it. */
static void chat_in(const char *sender,const char *target,char *text) {
    char prefix[16];
    uint8_t i,priv,before=chat_new;
    if(*text==1 || same(sender,irc.nick)) return;           /* CTCP, own echo */
    priv=same(target,irc.nick) && irc.peer[0] && same(sender,irc.peer);
    if(!priv && !same(target,chan())) return;
    chat_clean(text);
    if(!*text) return;
    for(i=0;i<12 && sender[i];i++) {
        prefix[i]=sender[i];
        if(prefix[i]>='a' && prefix[i]<='z') prefix[i]-=32;
    }
    prefix[i++]=':'; prefix[i++]=' '; prefix[i]=0;
    chat_add(prefix,text,priv);
    i=(uint8_t)(chat_new-before);
    chat_unread=(uint16_t)chat_unread+i>255?255:chat_unread+i;
}

/* One game line from sender to target (our nick, #msxpi or the room), all
 * of the form "PCH1 CK <op> ..." (PChess ignores them); see
 * msxpi_pcheckers_irc.py for the list. */
static void peer_receive(const char *sender,const char *target,char *text) {
    char *op=text+8,*arg;
    uint8_t same_peer;
    if(strncmp(text,"PCH1 CK ",8) || same(sender,irc.nick)) return;
    arg=strchr(op,' ');
    if(arg) *arg++=0;
    same_peer=irc.peer[0] && same(sender,irc.peer);
    if(irc.room[0] && same(target,irc.room)) {
        if(!strcmp(op,"HELLO") && !arg) {
            if(!irc.peer[0] || same_peer || is_free()) {
                irc_line("PRIVMSG ",sender," :PCH1 CK HERE",0);
                pair_by_name(sender);
            } else irc_line("PRIVMSG ",sender," :PCH1 CK BUSY",0);
        }
        return;
    }
    if(same(target,"#msxpi")) {
        if(!irc.room[0] && !strcmp(op,"SEEK") && !arg && is_free()) {
            char *s=irc.status;
            seen(sender);
            strcpy(s,"PLAYER "); strncat(s,sender,16); strcat(s," WANTS TO PLAY");
        }
        return;
    }
    if(!same(target,irc.nick)) return;
    if(!strcmp(op,"OFFER") && !arg && !irc.room[0]) {
        seen(sender);
        if(is_free() || same_peer) {
            char *s=irc.status;
            strncpy(irc.invite,sender,16); irc.invite[16]=0; irc.has_invite=1;
            strcpy(s,"INVITE "); strncat(s,sender,16); strcat(s," PRESS 8");
        }
    } else if(!strcmp(op,"ACCEPT") && !arg) {
        if(irc.phase==PH_OFFERED && same_peer) pair(sender,0);
    } else if(!strcmp(op,"HERE") && !arg && irc.room[0]) {
        if(!irc.peer[0] || same_peer || is_free()) pair_by_name(sender);
    } else if(!strcmp(op,"BUSY") && !arg && irc.room[0]) {
        if(irc.phase!=PH_PLAYING) set_status("ROOM BUSY - GAME IN PROGRESS");
    } else if(same_peer && playing()) {
        if(!strcmp(op,"MOVE") && arg && !irc.result) {
            uint16_t n=0;
            char *path=arg;
            while(*path>='0' && *path<='9') n=n*10+(*path++-'0');
            if(*path++!=' ' || n!=irc.ply || !valid_path(path) || irc.inbox_n>=INBOX
               || (irc.ply&1)==irc.side) {
                set_status("OUT OF SYNC - REJOIN THE ROOM");
                return;
            }
            strcpy(irc.inbox[irc.inbox_n++],path);
            irc.ply++;
            if(irc.draw_offer==1) irc.draw_offer=0;
        } else if(!strcmp(op,"DRAW") && !irc.result) {
            if(irc.draw_offer==1) irc.result=3; else irc.draw_offer=2;
        } else if(!strcmp(op,"RESIGN") && !irc.result) {
            irc.result=irc.side?2:1;    /* the peer is the other colour */
        } else if(!strcmp(op,"RESET")) {
            new_game_state();
        }
    }
}

/* Our own commands. */
static void peer_cmove(const char *arg) {
    uint16_t n=0;
    const char *path=arg;
    char *line=(char *)reply+8;     /* the reply is rebuilt afterwards */
    if(!playing()) { fail="Waiting for opponent"; return; }
    if(irc.result) { fail="Game over"; return; }
    while(*path>='0' && *path<='9') n=n*10+(*path++-'0');
    if(*path++!=' ' || !valid_path(path)) { fail="Bad move"; return; }
    if(n!=irc.ply || irc.inbox_n) { fail="Out of sync; poll"; return; }
    if((irc.ply&1)!=irc.side) { fail="Opponent turn"; return; }
    strcpy(line,"PCH1 CK MOVE ");
    put_dec(line+13,n);
    strcat(line," ");
    strcat(line,path);
    if(!say(irc.peer,line)) return;
    irc.ply++;
    if(irc.draw_offer==2) irc.draw_offer=0;
}

static void peer_draw(void) {
    if(!playing()) { fail="Waiting for opponent"; return; }
    if(irc.result) { fail="Game over"; return; }
    if(!say(irc.peer,"PCH1 CK DRAW")) return;
    if(irc.draw_offer==2) irc.result=3; else irc.draw_offer=1;
}

static void peer_resign(void) {
    if(!playing()) { fail="Waiting for opponent"; return; }
    if(irc.result) { fail="Game over"; return; }
    if(!say(irc.peer,"PCH1 CK RESIGN")) return;
    irc.result=irc.side?1:2;
}

static void peer_reset(void) {
    if(!playing()) { fail="Waiting for opponent"; return; }
    if(!say(irc.peer,"PCH1 CK RESET")) return;
    new_game_state();
}

static uint8_t announce_room(void) {
    char *p;
    if(!say(irc.room,"PCH1 CK HELLO")) return 0;
    if(!irc.peer[0]) {
        strcpy(irc.status,"ROOM "); strcat(irc.status,irc.room+8); strcat(irc.status," - WAITING");
        for(p=irc.status;*p;p++) if(*p>='a' && *p<='z') *p-=32;
    }
    return 1;
}

static void peer_seek(void) {
    if(irc.room[0]) { fail="In a room; no lobby"; return; }
    if(!is_free()) { fail="Already in a match"; return; }
    if(irc.seeked && (uint16_t)(JIFFY-irc.last_seek)<SECONDS(60)) { fail="Wait before announcing again"; return; }
    if(!say("#msxpi","PCH1 CK SEEK")) return;
    irc.last_seek=JIFFY; irc.seeked=1;
    set_status("SEEK SENT");
}

static void peer_offer(const char *nick) {
    if(!valid_nick(nick)) { fail="Invalid nickname"; return; }
    if(!is_free() || same(nick,irc.nick)) { fail="Cannot challenge now"; return; }
    strcpy(irc.peer,nick);
    irc.phase=PH_OFFERED;
    new_game_state();
    if(!say(nick,"PCH1 CK OFFER")) return;
    set_status("INVITE SENT");
}

static void peer_accept(void) {
    if(!is_free() || !irc.has_invite) { fail="No invitation"; return; }
    irc.has_invite=0;
    pair(irc.invite,1);
    say(irc.peer,"PCH1 CK ACCEPT");
}

/* -------------------------------------------------------- IRC transport */

static void net_close(void) {
    if(irc.net>=NET_REGISTER) {
        irc_line("QUIT :bye",0,0,0);
        ur_bc=(uint16_t)irc.conn<<8; unapi(TCPIP_TCP_CLOSE);
    } else if(irc.net==NET_OPEN) {
        ur_bc=(uint16_t)irc.conn<<8; unapi(TCPIP_TCP_ABORT);
    }
    irc.net=NET_OFF; irc.ready=0;
}

static uint8_t net_error(const char *s) {
    net_close();
    set_status(s);
    irc.phase=PH_ERROR;
    fail=irc.status;
    return 0;
}

/* One line from the server, without CR LF. */
static void irc_input(char *line) {
    char *prefix=0,*cmd,*rest,*p;
    if(*line=='@') { line=strchr(line,' '); if(!line) return; line++; }
    if(!strncmp(line,"PING ",5)) { irc_line("PONG ",line+5,0,0); return; }
    if(!strncmp(line,"ERROR ",6)) { line[46]=0; net_error(line); return; }
    if(*line==':') { prefix=line+1; line=strchr(line,' '); if(!line) return; *line++=0; }
    cmd=line; rest=strchr(line,' ');
    if(rest) *rest++=0; else rest="";
    if(prefix && (p=strchr(prefix,'!'))) *p=0;
    if(!strcmp(cmd,"001")) {
        /* rest = "<nick> :Welcome..." */
        p=strchr(rest,' '); if(p) *p=0;
        strncpy(irc.nick,rest,16); irc.nick[16]=0;
        set_status(irc.room[0]?"JOINING ROOM":"JOINING LOBBY");
        irc_line("JOIN ",irc.room[0]?irc.room:"#msxpi",0,0);
    } else if(!strcmp(cmd,"JOIN") && prefix && same(prefix,irc.nick)) {
        if(*rest==':') rest++;
        if(same(rest,irc.room[0]?irc.room:"#msxpi")) {
            irc.ready=1; irc.net=NET_READY;
            strcpy(irc.status,"LOBBY "); strcat(irc.status,irc.nick);
            if(irc.room[0]) irc.announce=1;
        }
    } else if(!strcmp(cmd,"401")) {
        /* "<me> <nick> :No such nick" */
        char *nick=strchr(rest,' '),*end;
        if(!nick) return;
        nick++; end=strchr(nick,' '); if(end) *end=0;
        if(irc.peer[0] && same(nick,irc.peer) && (irc.phase==PH_OFFERED || irc.phase==PH_ACCEPTED)) {
            irc.peer[0]=0; irc.match[0]=0; irc.phase=PH_LOBBY;
        }
        strncpy(irc.status,nick,30); irc.status[30]=0; strcat(irc.status,": No such nick");
    } else if(!strcmp(cmd,"433")) {
        net_error("Lobby nickname in use");
    } else if(!strcmp(cmd,"477")) {
        net_error("Lobby account login required (477)");
    } else if(!strcmp(cmd,"403") || !strcmp(cmd,"404") || !strcmp(cmd,"432") ||
              !strcmp(cmd,"464") || !strcmp(cmd,"465") || !strcmp(cmd,"471") ||
              !strcmp(cmd,"473") || !strcmp(cmd,"474") || !strcmp(cmd,"475") || !strcmp(cmd,"489")) {
        static char err[48];
        strcpy(err,"Lobby error "); strcat(err,cmd);
        net_error(err);
    } else if(!strcmp(cmd,"PRIVMSG") && prefix) {
        char *target=rest,*text=strchr(rest,' ');
        if(!text) return;
        *text++=0;
        if(*text!=':') return;
        if(strncmp(text+1,"PCH1 ",5)) chat_in(prefix,target,text+1);
        else peer_receive(prefix,target,text+1);
    }
}

/* TCP_OPEN to net->open[0..3]:cfg_port; the parameter block is the rest. */
static uint8_t tcp_open(void) {
    net->open[4]=(uint8_t)cfg_port; net->open[5]=(uint8_t)(cfg_port>>8);
    net->open[6]=0xFF; net->open[7]=0xFF;
    net->open[8]=0; net->open[9]=0; net->open[10]=0;
    ur_hl=(uint16_t)net->open;
    if(unapi(TCPIP_TCP_OPEN)) return net_error("CONNECTION FAILED");
    irc.conn=(uint8_t)(ur_bc>>8); irc.net=NET_OPEN;
    return 1;
}

static void set_ip(void) {
    net->open[0]=(uint8_t)ur_hl; net->open[1]=(uint8_t)(ur_hl>>8);
    net->open[2]=(uint8_t)ur_de; net->open[3]=(uint8_t)(ur_de>>8);
}

static void net_step(void) {
    uint8_t err,state;
    if(irc.net==NET_OFF) return;
    if(!irc.ready && (uint16_t)(JIFFY-irc.started)>SECONDS(60)) {
        net_error("Lobby connection timed out"); return;
    }
    if(irc.net==NET_DNS) {
        ur_bc=0; err=unapi(TCPIP_DNS_S);
        if(err) { net_error("DNS ERROR"); return; }
        if((ur_bc>>8)==1) return;
        if((ur_bc>>8)!=2) { net_error("DNS FAILED"); return; }
        set_ip(); tcp_open();
        return;
    }
    if(irc.net==NET_OPEN) {
        ur_bc=(uint16_t)irc.conn<<8; ur_hl=0;
        err=unapi(TCPIP_TCP_STATE); state=(uint8_t)(ur_bc>>8);
        if(err) { net_error("CONNECTION FAILED"); return; }
        if(state!=4) return;
        irc.net=NET_REGISTER;
        irc_line("NICK ",irc.nick,0,0);
        irc_line("USER ",irc.nick," 0 * :MSX PCheckers",0);
        return;
    }
    /* Registered or ready: read what arrived and handle whole lines. */
    for(;;) {
        char *nl;
        ur_bc=(uint16_t)irc.conn<<8; ur_de=(uint16_t)(net->rx+irc.rx_len); ur_hl=RX_SIZE-1-irc.rx_len;
        err=unapi(TCPIP_TCP_RCV);
        if(err==ERR_NO_DATA) break;
        if(err) { net_error("Lobby disconnected"); return; }
        if(!ur_bc) break;
        irc.rx_len+=ur_bc;
        net->rx[irc.rx_len]=0;
        while((nl=strchr(net->rx,'\n'))) {
            *nl=0;
            if(nl>net->rx && nl[-1]=='\r') nl[-1]=0;
            irc_input(net->rx);
            if(irc.net==NET_OFF) return;
            irc.rx_len-=(uint16_t)(nl+1-net->rx);
            memmove(net->rx,nl+1,irc.rx_len+1);
        }
        if(irc.rx_len>=RX_SIZE-1) irc.rx_len=0;   /* overlong line: drop */
    }
}

static uint8_t net_start(const char *room) {
    uint8_t err;
    net_close();
    memset(&irc,0,sizeof(irc));
    strcpy(irc.nick,cfg_nick);
    if(room) strcpy(irc.room,room);
    irc.started=JIFFY;
    set_status("ACCESSING LOBBY");
    strcpy(net->host,cfg_host);
    ur_hl=(uint16_t)net->host; ur_bc=0;
    err=unapi(TCPIP_DNS_Q);
    if(err) return net_error(err==2?"NO NETWORK":"DNS ERROR");
    if((ur_bc>>8)==0) { irc.net=NET_DNS; return 1; }
    set_ip();
    return tcp_open();
}




/* ------------------------------------------------------------ settings */

static void load_config(void) {
    static FCB fcb;
    char *data=(char *)reply;   /* idle until the next exchange(): no 256-byte buffer of its own */
    char *line,*eq,*end; uint16_t n; uint8_t i;
    strcpy(cfg_nick,"pch");
    for(i=3;i<7;i++) cfg_nick[i]="0123456789abcdef"[rnd()&15];
    cfg_nick[7]=0;
    memset(&fcb,0,sizeof(fcb));
    memcpy(fcb.name,"PCHESS  INI",11);
    if(fcb_open(&fcb)) return;
    fcb.record_size=1;
    n=fcb_read(&fcb,data,255);
    fcb_close(&fcb);
    data[n]=0;
    for(line=data;*line;line=end) {
        end=line;
        while(*end && *end!='\r' && *end!='\n' && *end!=0x1A) end++;
        if(*end) *end++=0;
        while(*end=='\r' || *end=='\n' || *end==0x1A) end++;
        eq=strchr(line,'=');
        if(!eq) continue;
        *eq++=0;
        if(!strcmp(line,"IRCADDR") && *eq && strlen(eq)<48) strcpy(cfg_host,eq);
        else if(!strcmp(line,"IRCPORT")) { cfg_port=0; while(*eq>='0' && *eq<='9') cfg_port=cfg_port*10+(*eq++-'0'); }
        else if(!strcmp(line,"IRCNICK") && valid_nick(eq)) strcpy(cfg_nick,eq);
    }
}


/* Fusion-C's crt0 does not clear static data: whatever the last program
 * left there is what an uninitialised static starts with. main() calls
 * this before anything here runs. */
static uint8_t irc_on;
static void tcp_init(void) {
    memset(&irc,0,sizeof(irc));
    net=0; irc_on=0;
}

/* Called when LINK changes to TCPIP; 0 with a status when it cannot. */
static uint8_t tcp_link_start(char *status) {
    if(!tcp_find()) { strcpy(status,"NO TCP/IP UNAPI - RUN INL I"); return 0; }
    if(!net_memory(status)) return 0;
    load_config();
    return 1;
}

static void tcp_link_stop(void) {
    if(net) net_close();
    memset(&irc,0,sizeof(irc));
    irc_on=0;
}

/* ----------------------------------------------------------- packets */

static void packet_status(const char *s) {
    uint8_t n=(uint8_t)strlen(s);
    if(n>47) n=47;
    memcpy(reply+72,s,n);
}

/* The state packet of checkers_packet() in msxpi_pchess.py. */
static void build_packet(void) {
    uint8_t i,j,len;
    const char *p;
    memset(reply+8,0,64);
    reply[4]=1; reply[5]=playing(); reply[6]=irc.side; reply[7]=irc.result;
    packet_status(irc.status);
    for(i=0;i<irc.inbox_n;i++) {
        p=irc.inbox[i]; len=(uint8_t)(strlen(p)/2);
        reply[120+i*14]=len;
        for(j=0;j<len;j++) reply[121+i*14+j]=(uint8_t)((8-(p[j*2+1]-'0'))*8+(p[j*2]-'a'));
    }
    reply[240]=irc.inbox_n; irc.inbox_n=0;
    reply[241]=(uint8_t)irc.ply; reply[238]=(uint8_t)(irc.ply>>8);
    reply[242]=irc.draw_offer==2?1:irc.draw_offer==1?2:0;
    reply[255]=chat_unread;
}

static void net_poll(void) {
    net_step();
    if(irc.announce && irc.ready) { irc.announce=0; announce_room(); fail=0; }
}

static void players_packet(void) {
    uint8_t i,n=0;
    reply[5]='P';
    for(i=irc.players_n;i--;) {
        if((uint16_t)(JIFFY-irc.seen_at[i])>=SECONDS(600) || same(irc.players[i],irc.nick)) continue;
        memcpy(reply+120+n*16,irc.players[i],strlen(irc.players[i]));
        n++;
    }
    reply[240]=n;
    if(!n) packet_status("NO PLAYERS - ASK THEM TO SEEK (6)");
    else { static char s[12]; put_dec(s,n); strcat(s,n==1?" PLAYER":" PLAYERS"); packet_status(s); }
}

/* The server's handle_command() for this link. cmd is "pchess ...". */
static uint8_t local_exchange(const char *cmd) {
    static char args[64];
    char *verb,*arg;
    uint8_t ok=1;
    memset(reply,0,256);
    memcpy(reply,"PCH1",4);
    fail=0;
    strncpy(args,cmd+7,63); args[63]=0;
    verb=args; arg=strchr(args,' ');
    if(arg) *arg++=0; else arg="";
    if(irc.net!=NET_OFF) net_poll();
    if(!strcmp(verb,"cjoin")) {
        static char room[26]; uint8_t i,n=(uint8_t)strlen(arg);
        strcpy(room,"#pchess-");
        for(i=0;i<n && i<16;i++) {
            char c=arg[i];
            if(c>='A' && c<='Z') c+=32;
            if(!((c>='a' && c<='z') || (c>='0' && c<='9'))) break;
            room[8+i]=c;
        }
        room[8+i]=0;
        if(!n || n>16 || i!=n) fail="Room: 1-16 letters or digits";
        else if(irc.ready && same(irc.room,room)) {irc.peer[0]=0; irc.phase=PH_LOBBY; new_game_state(); announce_room();}
        else { irc_on=1; net_start(room); }
    } else if(!strcmp(verb,"circ")) {
        irc_on=1; net_start(0);
    } else if(!strcmp(verb,"cleave")) {
        net_close(); memset(&irc,0,sizeof(irc)); irc_on=0;
    } else if(!irc_on) {
        /* Lobby commands before going online, as the server says. */
        fail=(!strcmp(verb,"cplayers") || !strcmp(verb,"cseek") || !strcmp(verb,"coffer") ||
              !strcmp(verb,"caccept"))?"Go online first (5)":
             (!strcmp(verb,"say") || !strcmp(verb,"chat"))?"NO ONE TO CHAT WITH":"Start a game first";
    } else if(!strcmp(verb,"cplayers")) {
        if(irc.room[0]) fail="In a room; no lobby";
        else { players_packet(); return 1; }
    } else if(!strcmp(verb,"chat")) {
        /* The rows are in the scrollback already: an empty chat block. */
        reply[5]='C';
        return 1;
    } else if(!irc.ready) {
        fail=irc.net==NET_OFF?irc.status:"Lobby not ready; wait";
    } else if(!strcmp(verb,"cpoll")) {
    } else if(!strcmp(verb,"cseek")) peer_seek();
    else if(!strcmp(verb,"coffer")) peer_offer(arg);
    else if(!strcmp(verb,"caccept")) peer_accept();
    else if(!strcmp(verb,"cmove")) peer_cmove(arg);
    else if(!strcmp(verb,"cdraw")) peer_draw();
    else if(!strcmp(verb,"cresign")) peer_resign();
    else if(!strcmp(verb,"creset")) peer_reset();
    else if(!strcmp(verb,"say")) chat_say((char *)cmd+11);
    else fail="Unknown action";
    if(fail) { memset(reply+8,0,64); packet_status(fail); ok=0; }
    else build_packet();
    return ok;
}
