/*
 * PChess over TCP/IP UNAPI (InterNestor Lite, GR8NET, ObsoNET...), chosen
 * with LINK in the ESC menu. local_exchange() takes the same "pchess ..."
 * commands the MSXPi server does and answers with the same 256-byte PCH1
 * packet, so the rest of pchess.c does not know which link is in use.
 *
 * LOCAL games use pchess_rules.c. ROOM and ONLINE speak the PCH1 IRC
 * protocol of msxpi_pchess_irc.py (a C port of its Peer class), so an MSX
 * here plays MSXPi players on the same IRC network. IRC over plain TCP:
 * no TLS on a Z80, so the server must accept port 6667 (Libera does).
 * AI games need the MSXPi server's engine.
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
 * RAM helper and CALSLT map it. They live just below the stack, at the top
 * of the TPA, well clear of page 1. */
#define RX_SIZE 512
typedef struct {
    char rx[RX_SIZE];
    char tx[300];
    uint8_t open[13];
    char host[64];
} NetMem;
static NetMem *net;

static uint8_t net_memory(void) {
    uint16_t top=*(uint16_t *)0x0006-1536-sizeof(NetMem);
    if(top<0x8000 || top<heap_top) return 0;
    net=(NetMem *)top;
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

/* ---------------------------------------------------------- game state */

#define MODE_LOCAL 0
#define MODE_IRC 1
static uint8_t link_mode;          /* LOCAL or IRC game on this link */

static char hist[8][10];
static uint8_t hist_n;
static uint16_t ply;
/* LOCAL: 1 draw agreed; 2 white resigned, 3 black resigned. */
static uint8_t local_end;

static void history_add(const char *san) {
    if(hist_n==8) { memmove(hist[0],hist[1],sizeof(hist)-10); hist_n--; }
    strncpy(hist[hist_n],san,9); hist[hist_n][9]=0;
    hist_n++;
}

static void board_reset(void) {
    rules_reset();
    hist_n=0; ply=0; local_end=0;
}

/* Parse and play a move for the side to move; fills san. */
static uint8_t play_text(const char *text,char *san,char *uci) {
    uint8_t from,to; char promo;
    if(!rules_parse(text,&from,&to,&promo)) { fail="ILLEGAL MOVE"; return 0; }
    make_san(from,to,promo,san);
    if(uci) {
        uci[0]=(char)('a'+COL(from)); uci[1]=(char)('8'-ROW(from));
        uci[2]=(char)('a'+COL(to)); uci[3]=(char)('8'-ROW(to));
        uci[4]=promo?(char)(promo|32):0; uci[5]=0;
    }
    rules_play(from,to,promo);
    history_add(san);
    ply++;
    return 1;
}

/* sha256(FEN)[:16] of pos, computed once per position. */
static char digest_cache[17];
static uint8_t digest_gen,digest_ok;
static void position_digest(char *out) {
    if(!digest_ok || digest_gen!=pos_gen) {
        char fen[96];
        make_fen(&pos,fen);
        sha_digest16(fen,digest_cache);
        digest_gen=pos_gen; digest_ok=1;
    }
    strcpy(out,digest_cache);
}

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

static struct {
    uint8_t net,conn,ready,announce;
    uint16_t started;
    char nick[17],peer[17],match[17],room[26];
    char invite[17],invite_match[17];
    uint8_t has_invite,phase,side,draw_offer,result;
    char status[48];
    char pending[80]; uint16_t pending_at; uint8_t pending_tries,has_pending;
    char last_move[80];
    uint16_t last_seek; uint8_t seeked;
    char players[7][17]; uint16_t seen_at[7]; uint8_t players_n;
    uint16_t rx_len;
} irc;
/* draw_offer: 0 none, 1 me, 2 peer. result: 0 none, 1 draw, 2 white
 * resigned, 3 black resigned. side: 1 white. */

static char cfg_host[48]="irc.libera.chat";
static uint16_t cfg_port=6667;
static char cfg_nick[17];

static void set_status(const char *s) { strncpy(irc.status,s,47); irc.status[47]=0; }

static uint8_t tcp_send(const char *data,uint16_t len) {
    uint8_t tries=0,err;
    if(irc.net<NET_REGISTER) return 0;
    memcpy(net->tx,data,len);
    do {
        ur_bc=((uint16_t)irc.conn<<8)|1; ur_de=(uint16_t)net->tx; ur_hl=len;
        err=unapi(TCPIP_TCP_SEND);
        if(err!=ERR_BUFFER) break;
        { uint16_t t=JIFFY; while(JIFFY==t); }
    } while(++tries<120);
    return err==0;
}

/* Send one IRC line (CR LF added). */
static uint8_t irc_line(const char *a,const char *b,const char *c) {
    static char line[300];
    uint16_t n;
    strcpy(line,a);
    if(b) strcat(line,b);
    if(c) strcat(line,c);
    n=strlen(line);
    if(n>296) return 0;
    line[n++]='\r'; line[n++]='\n';
    return tcp_send(line,n);
}

static uint8_t say(const char *target,const char *text) {
    static char head[40];
    if(!irc.ready) { fail="Lobby not ready; wait"; return 0; }
    strcpy(head,"PRIVMSG "); strcat(head,target); strcat(head," :");
    if(!irc_line(head,text,0)) { fail="Lobby send failed"; return 0; }
    return 1;
}

static uint8_t game_over_now(void) {
    return irc.result || rules_outcome();
}

static uint8_t is_free(void) {
    return irc.phase==PH_LOBBY || irc.phase==PH_ERROR ||
           (irc.phase==PH_PLAYING && game_over_now());
}

static void new_match(void) {
    board_reset();
    irc.side=1; irc.has_pending=0; irc.last_move[0]=0;
    irc.draw_offer=0; irc.result=0;
}

static void turn_status(void) {
    char *s=irc.status;
    strcpy(s,"YOU ARE "); strcat(s,irc.side?"WHITE":"BLACK");
    if(pos.white==irc.side) strcat(s," - YOUR MOVE");
    else { strcat(s," - "); strcat(s,irc.peer); strcat(s," MOVES"); }
}

static void seen(const char *nick) {
    uint8_t i;
    for(i=0;i<irc.players_n;i++) if(same(irc.players[i],nick)) break;
    if(i==irc.players_n) {
        if(i==7) { memmove(irc.players[0],irc.players[1],6*17); memmove(irc.seen_at,irc.seen_at+1,12); i=6; }
        else irc.players_n++;
    } else {
        /* Newest last, as the server's dict. */
        for(;i+1<irc.players_n;i++) { strcpy(irc.players[i],irc.players[i+1]); irc.seen_at[i]=irc.seen_at[i+1]; }
    }
    strncpy(irc.players[i],nick,16); irc.players[i][16]=0;
    irc.seen_at[i]=JIFFY;
}

static uint8_t peer_offer(const char *nick) {
    static char msg[40];
    uint8_t i;
    if(!valid_nick(nick)) { fail="Invalid nickname"; return 0; }
    if(!is_free() || same(nick,irc.nick)) { fail="Cannot challenge now"; return 0; }
    new_match();
    strcpy(irc.peer,nick);
    for(i=0;i<16;i++) irc.match[i]="0123456789abcdef"[rnd()&15];
    irc.match[16]=0;
    irc.phase=PH_OFFERED;
    strcpy(msg,"PCH1 OFFER "); strcat(msg,irc.match);
    if(!say(nick,msg)) return 0;
    set_status("INVITE SENT");
    return 1;
}

static uint8_t peer_accept(void) {
    static char msg[40];
    if(!is_free() || !irc.has_invite) { fail="No invitation"; return 0; }
    new_match();
    strcpy(irc.peer,irc.invite); strcpy(irc.match,irc.invite_match);
    irc.has_invite=0; irc.side=0; irc.phase=PH_ACCEPTED;
    strcpy(msg,"PCH1 ACCEPT "); strcat(msg,irc.match);
    if(!say(irc.peer,msg)) return 0;
    set_status("WAIT READY");
    return 1;
}

static uint8_t announce_room(void) {
    char *s=irc.status; uint8_t i;
    if(!is_free()) { fail="Already in a match"; return 0; }
    if(!say(irc.room,"PCH1 ROOM HELLO")) return 0;
    strcpy(s,"ROOM "); strcat(s,irc.room+8); strcat(s," - WAITING");
    for(i=0;s[i];i++) if(s[i]>='a' && s[i]<='z') s[i]-=32;
    return 1;
}

static void room_pair(const char *sender) {
    if(is_free() && fold_cmp(irc.nick,sender)<0) peer_offer(sender);
}

static uint8_t peer_seek(void) {
    if(irc.room[0]) { fail="In a room; no lobby"; return 0; }
    if(!is_free()) { fail="Already in a match"; return 0; }
    if(irc.seeked && (uint16_t)(JIFFY-irc.last_seek)<SECONDS(60)) { fail="Wait before announcing again"; return 0; }
    if(!say("#msxpi","PCH1 SEEK")) return 0;
    irc.last_seek=JIFFY; irc.seeked=1;
    set_status("SEEK SENT");
    return 1;
}

/* PCH1 MOVE <match> <ply> <uci> <before> <after> */
static uint8_t peer_move(const char *text) {
    char before[17],after[17],san[12],uci[6],*m=irc.pending;
    if(irc.phase!=PH_PLAYING || irc.has_pending) { fail="Waiting for peer"; return 0; }
    if(pos.white!=irc.side) { fail="Opponent turn"; return 0; }
    if(game_over_now()) { fail="Game over"; return 0; }
    position_digest(before);
    if(!play_text(text,san,uci)) return 0;
    position_digest(after);
    strcpy(m,"PCH1 MOVE "); strcat(m,irc.match); strcat(m," ");
    put_dec(m+strlen(m),ply); strcat(m," "); strcat(m,uci); strcat(m," ");
    strcat(m,before); strcat(m," "); strcat(m,after);
    if(!say(irc.peer,m)) return 0;
    if(irc.draw_offer==2) irc.draw_offer=0;
    irc.has_pending=1; irc.pending_at=JIFFY; irc.pending_tries=0;
    set_status("WAIT ACK");
    return 1;
}

static uint8_t peer_draw(void) {
    static char msg[40];
    if(irc.phase!=PH_PLAYING) { fail="No game in progress"; return 0; }
    if(game_over_now()) { fail="Game over"; return 0; }
    if(irc.draw_offer!=2 && pos.white!=irc.side) { fail="Offer a draw on your move"; return 0; }
    strcpy(msg,"PCH1 DRAW "); strcat(msg,irc.match);
    if(!say(irc.peer,msg)) return 0;
    if(irc.draw_offer==2) irc.result=1;
    else { irc.draw_offer=1; set_status("DRAW OFFERED"); }
    return 1;
}

static uint8_t peer_resign(void) {
    static char msg[40];
    if(irc.phase!=PH_PLAYING) { fail="No game in progress"; return 0; }
    if(game_over_now()) { fail="Game over"; return 0; }
    strcpy(msg,"PCH1 RESIGN "); strcat(msg,irc.match);
    if(!say(irc.peer,msg)) return 0;
    irc.result=irc.side?2:3;
    return 1;
}

static uint8_t is_hex16(const char *s) {
    uint8_t n=0;
    for(;*s;s++,n++) if(!((*s>='0' && *s<='9') || (*s>='a' && *s<='f'))) return 0;
    return n==16;
}

/* One PCH1 message from sender to target (our nick, #msxpi or the room). */
static void peer_receive(const char *sender,const char *target,char *text) {
    static char msg[80];
    char *f[8]; uint8_t n=0; char *p=text;
    static char copy[80];
    strncpy(copy,text,79); copy[79]=0;
    while(n<8) {
        while(*p==' ') p++;
        if(!*p) break;
        f[n++]=p;
        while(*p && *p!=' ') p++;
        if(*p) *p++=0;
    }
    if(n<2 || strcmp(f[0],"PCH1") || same(sender,irc.nick)) return;
    if(irc.room[0] && same(target,irc.room)) {
        if(n==3 && !strcmp(f[1],"ROOM") && (!strcmp(f[2],"HELLO") || !strcmp(f[2],"HERE"))) {
            if(!strcmp(f[2],"HELLO")) {
                if(is_free()) say(irc.room,"PCH1 ROOM HERE");
                else say(sender,"PCH1 ROOM BUSY");
            }
            room_pair(sender);
        }
        return;
    }
    if(same(target,"#msxpi")) {
        if(irc.room[0]) return;
        if(n==2 && !strcmp(f[1],"SEEK") && is_free()) {
            seen(sender);
            strcpy(msg,"PLAYER "); strcat(msg,sender); set_status(msg);
        }
        return;
    }
    if(!same(target,irc.nick)) return;
    if(!strcmp(f[1],"OFFER") && n==3 && is_hex16(f[2])) {
        seen(sender);
        if(is_free()) {
            strncpy(irc.invite,sender,16); irc.invite[16]=0;
            strcpy(irc.invite_match,f[2]); irc.has_invite=1;
            strcpy(msg,"INVITE "); strcat(msg,sender); strcat(msg," PRESS 7"); set_status(msg);
            if(irc.room[0]) peer_accept();
        }
        return;
    }
    if(!strcmp(f[1],"ROOM") && n==3 && !strcmp(f[2],"BUSY") && irc.room[0]) {
        if(is_free() && irc.phase!=PH_PLAYING) set_status("ROOM BUSY - GAME IN PROGRESS");
        return;
    }
    if(!irc.peer[0] || !same(sender,irc.peer) || n<3 || strcmp(f[2],irc.match)) return;
    if(!strcmp(f[1],"ACCEPT") && n==3 && (irc.phase==PH_OFFERED || irc.phase==PH_PLAYING)) {
        if(irc.phase==PH_OFFERED) { irc.side=1; irc.phase=PH_PLAYING; turn_status(); }
        strcpy(msg,"PCH1 READY "); strcat(msg,irc.match); say(irc.peer,msg);
    } else if(!strcmp(f[1],"READY") && n==3 && irc.phase==PH_ACCEPTED) {
        irc.phase=PH_PLAYING; turn_status();
    } else if(!strcmp(f[1],"MOVE") && n==7 && irc.phase==PH_PLAYING) {
        char digest[17],san[12],expect[6];
        if(!strcmp(copy,irc.last_move)) {
            strcpy(msg,"PCH1 ACK "); strcat(msg,irc.match); strcat(msg," "); strcat(msg,f[3]);
            strcat(msg," "); strcat(msg,f[6]); say(irc.peer,msg);
            return;
        }
        if(irc.result || irc.has_pending || pos.white==irc.side) return;
        put_dec(expect,ply+1);
        position_digest(digest);
        if(strcmp(f[3],expect) || strcmp(f[5],digest)) { set_status("OUT OF SYNC"); irc.phase=PH_ERROR; return; }
        if(strlen(f[4])<4 || strlen(f[4])>5) return;
        {
            /* UCI only, like parse_uci(); undo is by replay, so check first. */
            Pos saved; uint8_t saved_rep=rep_count,saved_n=hist_n; uint16_t saved_ply=ply;
            static char saved_hist[8][10];
            memcpy(&saved,&pos,sizeof(Pos)); memcpy(saved_hist,hist,sizeof(hist));
            if(!play_text(f[4],san,0)) return;
            position_digest(digest);
            if(strcmp(digest,f[6])) {
                memcpy(&pos,&saved,sizeof(Pos)); memcpy(hist,saved_hist,sizeof(hist)); pos_gen++;
                rep_count=saved_rep; hist_n=saved_n; ply=saved_ply;
                set_status("BAD POSITION"); irc.phase=PH_ERROR; return;
            }
        }
        strcpy(irc.last_move,copy);
        if(irc.draw_offer==1) irc.draw_offer=0;
        strcpy(msg,"PCH1 ACK "); strcat(msg,irc.match); strcat(msg," "); strcat(msg,f[3]);
        strcat(msg," "); strcat(msg,f[6]); say(irc.peer,msg);
        turn_status();
    } else if(!strcmp(f[1],"DRAW") && n==3 && irc.phase==PH_PLAYING && !irc.result) {
        if(irc.draw_offer==1) irc.result=1;
        else { irc.draw_offer=2; set_status("OPPONENT OFFERS DRAW - ESC MENU"); }
    } else if(!strcmp(f[1],"RESIGN") && n==3 && irc.phase==PH_PLAYING && !irc.result) {
        irc.result=irc.side?3:2;
    } else if(!strcmp(f[1],"ACK") && n==5 && irc.has_pending) {
        char digest[17],count[6];
        put_dec(count,ply);
        position_digest(digest);
        if(!strcmp(f[3],count) && !strcmp(f[4],digest)) { irc.has_pending=0; turn_status(); }
    }
}

static void peer_tick(void) {
    if(irc.result) irc.has_pending=0;
    if(irc.has_pending && (uint16_t)(JIFFY-irc.pending_at)>=SECONDS(5)) {
        if(irc.pending_tries>=3) {
            irc.phase=PH_ERROR; set_status("PEER TIMEOUT"); irc.has_pending=0;
        } else {
            say(irc.peer,irc.pending);
            irc.pending_at=JIFFY; irc.pending_tries++;
        }
    }
}

/* -------------------------------------------------------- IRC transport */

static void net_close(void) {
    if(irc.net>=NET_REGISTER) {
        irc_line("QUIT :bye",0,0);
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
    if(!strncmp(line,"PING ",5)) { irc_line("PONG ",line+5,0); return; }
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
        irc_line("JOIN ",irc.room[0]?irc.room:"#msxpi",0);
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
        if(*text!=':' || strncmp(text+1,"PCH1 ",5)) return;
        peer_receive(prefix,target,text+1);
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
        irc_line("NICK ",irc.nick,0);
        irc_line("USER ",irc.nick," 0 * :MSX PChess");
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

static void net_poll(void) {
    net_step();
    if(irc.announce && irc.ready) { irc.announce=0; announce_room(); fail=0; }
    peer_tick();
}

/* ------------------------------------------------------------ settings */

static void load_config(void) {
    static FCB fcb;
    static char data[256];
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

/* Called when LINK changes to TCPIP; 0 with a status when it cannot. */
static uint8_t tcp_link_start(char *status) {
    if(!tcp_find()) { strcpy(status,"NO TCP/IP UNAPI - RUN INL I"); return 0; }
    if(!net_memory()) { strcpy(status,"NOT ENOUGH MEMORY FOR TCP/IP"); return 0; }
    load_config();
    link_mode=MODE_LOCAL;
    board_reset();
    return 1;
}

static void tcp_link_stop(void) {
    if(net) net_close();
}

/* ----------------------------------------------------------- packets */

static void packet_status(const char *s) {
    uint8_t n=(uint8_t)strlen(s);
    if(n>47) n=47;
    memcpy(reply+72,s,n);
}

static void build_packet(void) {
    uint8_t i,outcome=rules_outcome(),over,matched=0,side=0;
    static char status[48];
    for(i=0;i<64;i++) reply[8+i]=pos.sq[i]?pos.sq[i]:'.';
    if(link_mode==MODE_LOCAL) {
        strcpy(status,pos.white?"WHITE TURN":"BLACK TURN");
        if(in_check(&pos)) strcpy(status,pos.white?"WHITE CHECK":"BLACK CHECK");
        over=outcome || local_end;
        if(outcome) strcpy(status,outcome==3?"DRAW":outcome==1?"WHITE WINS":"BLACK WINS");
        if(local_end==1) strcpy(status,"DRAW AGREED");
        if(local_end==2) strcpy(status,"WHITE RESIGNED - BLACK WINS");
        if(local_end==3) strcpy(status,"BLACK RESIGNED - WHITE WINS");
    } else {
        strcpy(status,irc.status);
        if(irc.has_invite && is_free()) {}
        else if(outcome) strcpy(status,outcome==3?"DRAW":outcome==1?"WHITE WINS":"BLACK WINS");
        else if(irc.result==1) strcpy(status,"DRAW AGREED");
        else if(irc.result) strcpy(status,irc.result==2?"WHITE RESIGNED - BLACK WINS":"BLACK RESIGNED - WHITE WINS");
        else if(in_check(&pos) && irc.phase==PH_PLAYING && !irc.has_pending)
            strcpy(status,pos.white?"WHITE CHECK":"BLACK CHECK");
        over=outcome || irc.result;
        matched=irc.phase==PH_PLAYING;
        side=!irc.side;
        strncpy((char *)reply+243,irc.peer,12);
    }
    reply[4]=1; reply[5]=pos.white; reply[6]=side; reply[7]=over?1:0;
    packet_status(status);
    for(i=0;i<hist_n;i++) memcpy(reply+120+i*10,hist[i],strlen(hist[i]));
    reply[240]=hist_n; reply[241]=ply>255?255:(uint8_t)ply;
    reply[242]=matched;
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
    if(!n) packet_status("NO PLAYERS - ASK THEM TO SEEK (5)");
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
    if(link_mode==MODE_IRC) net_poll();
    if(!strcmp(verb,"new")) {
        if(!strcmp(arg,"ai")) fail="AI NEEDS MSXPI - ESC MENU LINK";
        else { net_close(); link_mode=MODE_LOCAL; board_reset(); }
    } else if(!strcmp(verb,"join")) {
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
        else if(link_mode==MODE_IRC && irc.ready && same(irc.room,room)) announce_room();
        else { link_mode=MODE_IRC; board_reset(); net_start(room); }
    } else if(!strcmp(verb,"irc")) {
        link_mode=MODE_IRC; board_reset(); net_start(0);
    } else if(!strcmp(verb,"move") && link_mode==MODE_LOCAL) {
        char san[12];
        if(local_end || rules_outcome()) fail="Game over";
        else play_text(arg,san,0);
    } else if(!strcmp(verb,"draw") && link_mode==MODE_LOCAL) {
        if(local_end || rules_outcome()) fail="Game over"; else local_end=1;
    } else if(!strcmp(verb,"resign") && link_mode==MODE_LOCAL) {
        if(local_end || rules_outcome()) fail="Game over"; else local_end=pos.white?2:3;
    } else if(!strcmp(verb,"poll") && link_mode==MODE_LOCAL) {
    } else if(link_mode!=MODE_IRC) {
        fail=!strcmp(verb,"players")?"Go online first (4)":"Start a game first";
    } else if(!strcmp(verb,"players")) {
        if(irc.room[0]) fail="In a room; no lobby";
        else { players_packet(); return 1; }
    } else if(!strcmp(verb,"poll")) {
    } else if(!irc.ready) {
        fail=irc.net==NET_OFF?irc.status:"Lobby not ready; wait";
    } else if(!strcmp(verb,"seek")) peer_seek();
    else if(!strcmp(verb,"offer")) peer_offer(arg);
    else if(!strcmp(verb,"accept")) peer_accept();
    else if(!strcmp(verb,"move")) peer_move(arg);
    else if(!strcmp(verb,"draw")) peer_draw();
    else if(!strcmp(verb,"resign")) peer_resign();
    else fail="Unknown action";
    if(fail) { packet_status(fail); ok=0; }
    else build_packet();
    return ok;
}
