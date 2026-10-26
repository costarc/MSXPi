/*
 * MSX Free Chat over TCP/IP UNAPI (InterNestor Lite, GR8NET, ObsoNET...),
 * used when there is no MSXPi, or forced with "mchat /t". local_exchange() takes the same "mchat ..."
 * commands the MSXPi server does and fills `reply` with the same CHT1
 * packets, so mchat.c does not know which link is in use (see msxpi_chat.py
 * for the packets). It is msxpi_chat.py's ChatIRC in C, with less memory:
 * LMAXR rooms of LROWS wrapped rows and LUSERS users each. When the screen
 * width changes the history is dropped (there is no unwrapped copy).
 *
 * IRC over plain TCP: no TLS on a Z80, so the server must accept port 6667
 * (Libera does) and there is no SASL login. MCHAT.INI in the current directory
 * may set IRCADDR, IRCPORT, IRCNICK and MCHATROOM (KEY=VALUE lines); the
 * defaults are irc.libera.chat, 6667, msxXXXX and #msxpi. The UNAPI layer is
 * copied from pchess_tcp.c.
 */

/* ---------------------------------------------------------------- UNAPI */

uint8_t ur_a, ur_cf;
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
    sbc a,a
    ld (_ur_cf),a
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

/* An MSXPi interface is in the machine when some slot's ROM carries "MSXPI" at 400Ah (the tag the MSXPi BIOS
 * ROM has in its header). RDSLT returns with interrupts off: they are switched on again before the return. */
static uint8_t msxpi_present(void) {
    static const char tag[5] = {'M', 'S', 'X', 'P', 'I'};
    uint8_t p, s, i, slot, found = 0;
    for (p = 0; p < 4 && !found; p++) {
        uint8_t exp = *(volatile uint8_t *)(0xFCC1 + p) & 0x80;
        for (s = 0; s < (exp ? 4 : 1) && !found; s++) {
            slot = p | (exp ? (uint8_t)(0x80 | (s << 2)) : 0);
            for (i = 0; i < 5; i++) {
                jp_to(0x000C);                  /* RDSLT */
                ur_a = slot; ur_hl = 0x400A + i;
                raw_call();
                if (ur_a != (uint8_t)tag[i]) break;
            }
            found = i == 5;
        }
    }
    __asm
    ei
    __endasm;
    return found;
}
static void extbio(uint8_t a,uint8_t b,uint16_t hl) {
    memcpy((char *)ARG,"TCP/IP",7);
    un_jp[0]=0xC3; un_jp[1]=(uint8_t)EXTBIO; un_jp[2]=(uint8_t)(EXTBIO>>8);
    un_ix=0; un_iy=0;
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

#define JIFFY (*(volatile uint16_t *)0xFC9E)
#define SECONDS(n) ((uint16_t)((n)*60u))

#include "games_local.h"

/* -------------------------------------------------------------- the model */

enum {K_TEXT_L, K_PRIV_IN_L, K_SYSTEM_L, K_OWN_L, K_ACTION_L, K_PRIV_OUT_L};

#define LMAXR 3                 /* rooms (the server allows 4) */
#define LROWS 32                /* wrapped rows kept a room */
#define LUSERS 32               /* users listed a room */
#define RX_SIZE 384             /* longer IRC lines are dropped */
#define TX_SIZE 160
#define LTEXT 230               /* longest message text kept */
#define NET_OFF 0
#define NET_DNS 1
#define NET_OPEN 2
#define NET_REGISTER 3
#define NET_READY 4

typedef struct {
    char name[24];
    uint16_t next;              /* absolute number of the row after the last */
    uint8_t nusers, joined;
} LRoom;

static LRoom lr[LMAXR];
static uint8_t lcount, lcur, lmeta, lw;
/* The rows' text lives in a mapper segment of its own (7 KB that MCHAT.COM's TPA does not have once INL is
   loaded), at 4000h when it is mapped into page 1. lt_copy maps it, copies and maps the TPA back, with
   interrupts off; it runs from a copy in seg_code (page 2 or 3), and its buffers are never in page 1. */
#define RW (TW_MAX + 3)          /* a row: its kind, the nick's length, the text and its terminator */
#define LT(r, s) ((char *)0x4000 + ((uint16_t)(r) * LROWS + (s)) * RW)
#define LU(r, i) ((char *)0x4000 + LMAXR * LROWS * RW + ((uint16_t)(r) * LUSERS + (i)) * 12)   /* the user lists */
uint8_t lt_seg, lt_tpa;
static uint16_t map_tab;
static uint8_t seg_code[32];
/* __sdcccall(0): the copy takes (dst, src, n) from the stack. */
static void lt_copy_code(void) __sdcccall(0) __naked {
__asm
    ld hl,#2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    push bc
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    pop hl
    ld a,(_lt_seg)
    di
    out (#0xFD),a
    ldir
    ld a,(_lt_tpa)
    out (#0xFD),a
    ei
    ret
_lt_copy_end::
__endasm;
}
extern uint8_t lt_copy_end[];
typedef void lt_copy_fn(void *, const void *, uint16_t) __sdcccall(0);
#define lt_copy(dst, src, n) ((lt_copy_fn *)seg_code)(dst, src, n)

/* A = routine (offset in the mapper support table) with A, B */
/* user i of room r, copied out of the segment */
static char ub[12];
static char *uget(uint8_t r, uint8_t i) {
    lt_copy(ub, LU(r, i), 12);
    return ub;
}

static void mapper(uint8_t fn, uint8_t a, uint8_t b) {
    jp_to(map_tab + fn);
    ur_a = a; ur_bc = (uint16_t)b << 8;
    raw_call();
}
#define M_ALL_SEG 0x00
#define M_FRE_SEG 0x03
#define M_GET_P1 0x21

static const char *lt_open(void) {
    jp_to(EXTBIO);
    un_ix = 0; un_iy = 0;
    ur_a = 0; ur_bc = 0; ur_de = 0x0402; ur_hl = 0;
    raw_call();
    map_tab = ur_hl;
    if (!map_tab) return "No memory mapper support";
    mapper(M_GET_P1, 0, 0);
    lt_tpa = ur_a;
    mapper(M_ALL_SEG, 0, 0);
    if (ur_cf) return "No free memory segment";
    lt_seg = ur_a;
    memcpy(seg_code, (void *)lt_copy_code, lt_copy_end - (uint8_t *)lt_copy_code);
    return 0;
}

static void lt_close(void) {
    if (lt_seg) mapper(M_FRE_SEG, lt_seg, 0);
    lt_seg = 0;
}

static struct {
    uint8_t net, conn, ready, active, lost;
    uint16_t started, rx_len;
    char nick[17];
} ln;

static char cfg_host[48] = "irc.libera.chat";
static uint16_t cfg_port = 6667;
static char cfg_nick[17];
static char cfg_room[24] = "#msxpi";
static uint16_t rnd_state;
uint8_t rnd_r;

static char fold_char(char c) {
    if (c >= 'A' && c <= 'Z') return (char)(c + 32);
    if (c == '[') return '{';
    if (c == ']') return '}';
    if (c == '\\') return '|';
    if (c == '^') return '~';
    return c;
}
static int8_t fold_cmp(const char *a, const char *b) {
    while (*a && fold_char(*a) == fold_char(*b)) {a++; b++;}
    return fold_char(*a) < fold_char(*b) ? -1 : fold_char(*a) > fold_char(*b) ? 1 : 0;
}
static uint8_t same(const char *a, const char *b) { return !fold_cmp(a, b); }

static void read_r(void) __naked {
__asm
    ld a,r
    ld (_rnd_r),a
    ret
__endasm;
}
static uint8_t rnd(void) {
    read_r();
    rnd_state = rnd_state * 25173u + 13849u + JIFFY + rnd_r;
    return (uint8_t)(rnd_state >> 8);
}

static uint8_t valid_nick(const char *s) {
    uint8_t n = 0;
    if (!((*s >= 'A' && *s <= 'Z') || (*s >= 'a' && *s <= 'z') || *s == '[' || *s == ']' || *s == '\\' ||
          *s == '`' || *s == '_' || *s == '^' || *s == '{' || *s == '|' || *s == '}')) return 0;
    for (; *s; s++, n++) {
        char c = *s;
        if (n > 15 || c <= ' ' || c > '~' || c == ',' || c == ':' || c == '!' || c == '@' || c == '#') return 0;
    }
    return 1;
}

static void clean(char *s) {
    for (; *s; s++) if (*s < 32 || *s > 126) *s = '?';
}

/* ----------------------------------------------------------- the rooms */

static uint8_t find_room(const char *name) {
    uint8_t i;
    for (i = 0; i < lcount; i++) if (same(lr[i].name, name)) return i;
    return 0xFF;
}

/* Append one wrapped row. */
static void push_row(uint8_t r, uint8_t kind, uint8_t nicklen, const char *text, uint8_t len) {
    uint8_t slot = lr[r].next % LROWS;
    if (len > lw) len = lw;
    char row[RW];
    row[0] = kind;
    row[1] = nicklen;
    memcpy(row + 2, text, len);
    row[2 + len] = 0;
    lt_copy(LT(r, slot), row, len + 3);
    lr[r].next++;
}

/* Wrap "<np><text>" to lw columns (continuation rows start with a blank). */
static void add_row(uint8_t r, uint8_t kind, const char *np, const char *text) {
    static char buf[LTEXT + 26];
    uint16_t n, pos = 0;
    uint8_t first = 1, cap, len, k, nplen = (uint8_t)strlen(np);
    strncpy(buf, np, 24); buf[24] = 0;
    n = strlen(buf);
    strncpy(buf + n, text, LTEXT); buf[n + LTEXT] = 0;
    clean(buf);
    n = strlen(buf);
    if (r >= lcount) return;
    if (!n) {push_row(r, kind, 0, "", 0); return;}
    while (pos < n) {
        static char row[TW_MAX + 1];
        if (!first) while (pos < n && buf[pos] == ' ') pos++;
        if (pos >= n) break;
        cap = first ? lw : lw - 1;
        len = n - pos > cap ? cap : (uint8_t)(n - pos);
        if (pos + len < n) {                 /* break at the last blank that fits */
            for (k = len; k > 0 && buf[pos + k] != ' '; k--) ;
            if (k) len = k;
        }
        if (first) memcpy(row, buf + pos, len);
        else {row[0] = ' '; memcpy(row + 1, buf + pos, len);}
        push_row(r, kind, first ? nplen : 0, row, first ? len : len + 1);
        pos += len;
        first = 0;
    }
}

static void say_system(const char *text) { add_row(lcur, K_SYSTEM_L, "", text); }

static uint8_t user_rank(const char *u) { return *u == '@' ? 0 : *u == '%' ? 1 : *u == '+' ? 2 : 3; }
static const char *user_name(const char *u) { return (*u == '@' || *u == '%' || *u == '+') ? u + 1 : u; }

static int8_t user_find(uint8_t r, const char *nick) {
    uint8_t i;
    for (i = 0; i < lr[r].nusers; i++) if (same(user_name(uget(r, i)), nick)) return i;
    return -1;
}

static void user_del(uint8_t r, const char *nick) {
    int8_t i = user_find(r, nick);
    if (i < 0) return;
    for (; i + 1 < lr[r].nusers; i++) lt_copy(LU(r, i), LU(r, i + 1), 12);
    lr[r].nusers--;
    lmeta++;
}

static void user_add(uint8_t r, const char *nick, char prefix) {
    uint8_t i, n, rank;
    char entry[12];
    user_del(r, nick);
    if (lr[r].nusers >= LUSERS) return;
    n = 0;
    if (prefix) entry[n++] = prefix;
    while (*nick && n < 11) entry[n++] = *nick++;
    entry[n] = 0;
    rank = user_rank(entry);
    for (i = 0; i < lr[r].nusers; i++) {
        uint8_t other = user_rank(uget(r, i));
        if (other > rank || (other == rank && fold_cmp(user_name(ub), user_name(entry)) > 0)) break;
    }
    for (n = lr[r].nusers; n > i; n--) lt_copy(LU(r, n), LU(r, n - 1), 12);
    lt_copy(LU(r, i), entry, 12);
    lr[r].nusers++;
    lmeta++;
}

/* ------------------------------------------------------------ transport */

typedef struct {
    char rx[RX_SIZE];
    char tx[TX_SIZE];
    uint8_t open[13];
    char host[48];
} NetMem;
/* Declared last: buffers handed to the implementation must not be in page 1
 * (0x4000-0x7FFF), where the RAM helper and CALSLT map it. */
static NetMem net_area;
static NetMem *net;
#define STACK_ROOM 768

static void net_close(void) {
    uint8_t err;
    if (ln.net >= NET_REGISTER) {
        strcpy(net->tx, "QUIT :bye\r\n");
        ur_bc = ((uint16_t)ln.conn << 8) | 1; ur_de = (uint16_t)net->tx; ur_hl = 11;
        err = unapi(TCPIP_TCP_SEND);
        ur_bc = (uint16_t)ln.conn << 8; err = unapi(TCPIP_TCP_CLOSE);
    } else if (ln.net == NET_OPEN) {
        ur_bc = (uint16_t)ln.conn << 8; err = unapi(TCPIP_TCP_ABORT);
    }
    (void)err;
    ln.net = NET_OFF; ln.ready = 0;
}

static uint8_t net_error(const char *s) {
    char text[60];
    net_close();
    ln.lost = 1;
    strcpy(text, "Connection lost: ");
    strncat(text, s, 40);
    say_system(text);
    return 0;
}

/* Send one IRC line (CR LF added), built in net->tx. */
static uint8_t irc_line(const char *a, const char *b, const char *c, const char *d) {
    uint8_t tries = 0, err;
    uint16_t n = strlen(a) + (b ? strlen(b) : 0) + (c ? strlen(c) : 0) + (d ? strlen(d) : 0);
    if (ln.net < NET_REGISTER || n > TX_SIZE - 4) return 0;
    strcpy(net->tx, a);
    if (b) strcat(net->tx, b);
    if (c) strcat(net->tx, c);
    if (d) strcat(net->tx, d);
    net->tx[n++] = '\r'; net->tx[n++] = '\n';
    do {
        ur_bc = ((uint16_t)ln.conn << 8) | 1; ur_de = (uint16_t)net->tx; ur_hl = n;
        err = unapi(TCPIP_TCP_SEND);
        if (err != ERR_BUFFER) break;
        {uint16_t t = JIFFY; while (JIFFY == t) ;}
    } while (++tries < 120);
    return err == 0;
}

/* One line from the server, without CR LF. */
static void irc_input(char *line) {
    char *prefix = 0, *cmd, *rest, *p, *text, *target;
    uint8_t r, kind, i;
    int8_t u;
    char np[24];
    if (*line == '@') {line = strchr(line, ' '); if (!line) return; line++;}
    if (!strncmp(line, "PING ", 5)) {irc_line("PONG ", line + 5, 0, 0); return;}
    if (!strncmp(line, "ERROR ", 6)) {line[46] = 0; net_error(line + 6); return;}
    if (*line == ':') {prefix = line + 1; line = strchr(line, ' '); if (!line) return; *line++ = 0;}
    cmd = line; rest = strchr(line, ' ');
    if (rest) *rest++ = 0; else rest = "";
    if (prefix && (p = strchr(prefix, '!'))) *p = 0;
    if (!strcmp(cmd, "001")) {
        p = strchr(rest, ' '); if (p) *p = 0;
        strncpy(ln.nick, rest, 16); ln.nick[16] = 0;
        ln.ready = 1; ln.net = NET_READY; lmeta++;
        for (i = 0; i < lcount; i++) irc_line("JOIN ", lr[i].name, 0, 0);
    } else if (!strcmp(cmd, "433")) {
        if (!ln.ready) {                      /* nick taken while registering: try another */
            if (strlen(ln.nick) < 15) strcat(ln.nick, "_"); else ln.nick[strlen(ln.nick) - 1] = '_';
            irc_line("NICK ", ln.nick, 0, 0);
        } else say_system("Nick already in use");
    } else if (!strcmp(cmd, "NICK") && prefix) {
        if (*rest == ':') rest++;
        for (r = 0; r < lcount; r++) {
            u = user_find(r, prefix);
            if (u >= 0) {
                char pre = uget(r, u)[0];
                pre = (pre == '@' || pre == '%' || pre == '+') ? pre : 0;
                user_add(r, rest, pre);
                strcpy(np, prefix); strcat(np, " is now ");
                add_row(r, K_SYSTEM_L, np, rest);
            }
        }
        if (same(prefix, ln.nick)) {strncpy(ln.nick, rest, 16); ln.nick[16] = 0; lmeta++;}
    } else if (!strcmp(cmd, "JOIN") && prefix) {
        if (*rest == ':') rest++;
        r = find_room(rest);
        if (r == 0xFF) return;
        if (same(prefix, ln.nick)) {
            lr[r].joined = 1; lr[r].nusers = 0;
            add_row(r, K_SYSTEM_L, "Joined ", lr[r].name);
        } else {
            user_add(r, prefix, 0);
            add_row(r, K_SYSTEM_L, prefix, " joined");
        }
    } else if ((!strcmp(cmd, "PART") || !strcmp(cmd, "KICK")) && prefix) {
        char *who = prefix;
        p = strchr(rest, ' ');
        if (p) {*p++ = 0; if (!strcmp(cmd, "KICK")) {who = p; p = strchr(p, ' '); if (p) *p = 0;}}
        r = find_room(rest);
        if (r == 0xFF) return;
        user_del(r, who);
        if (!strcmp(cmd, "KICK")) {strcpy(np, who); add_row(r, K_SYSTEM_L, np, " was kicked");}
        else if (!same(prefix, ln.nick)) add_row(r, K_SYSTEM_L, prefix, " left");
    } else if (!strcmp(cmd, "QUIT") && prefix) {
        for (r = 0; r < lcount; r++)
            if (user_find(r, prefix) >= 0) {user_del(r, prefix); add_row(r, K_SYSTEM_L, prefix, " quit");}
    } else if (!strcmp(cmd, "353")) {         /* me = #chan :@op +v nick */
        p = strstr(rest, " :");
        if (!p) return;
        *p = 0; text = p + 2;
        p = strrchr(rest, ' ');
        r = find_room(p ? p + 1 : rest);
        if (r == 0xFF) return;
        while (*text) {
            char *end = strchr(text, ' '), pre = 0;
            if (end) *end++ = 0; else end = text + strlen(text);
            while (*text == '@' || *text == '%' || *text == '+' || *text == '~' || *text == '&') {
                if (!pre) pre = (*text == '~' || *text == '&') ? '@' : *text;
                text++;
            }
            if (*text) user_add(r, text, pre);
            text = end;
        }
    } else if (!strcmp(cmd, "PRIVMSG") || !strcmp(cmd, "NOTICE")) {
        target = rest; text = strchr(rest, ' ');
        if (!text || !prefix) return;
        *text++ = 0;
        if (*text != ':') return;
        text++;
        if (!strncmp(text, "PCH1 ", 5)) return;          /* PChess game traffic */
        if (!strncmp(text, "MSXG1 ", 6)) {               /* game invitations (games_local.c) */
            if (*target != '#' && *target != '&') gl_on_message(prefix, text);
            return;
        }
        kind = K_TEXT_L;
        if (!strncmp(text, "\x01" "ACTION ", 8)) {
            text += 8; kind = K_ACTION_L;
            p = strchr(text, '\x01'); if (p) *p = 0;
        } else if (*text == '\x01') return;
        if (*target == '#' || *target == '&') {
            r = find_room(target);
            if (r == 0xFF) return;
            if (kind == K_ACTION_L) {strcpy(np, "* "); strncat(np, prefix, 16); strcat(np, " ");}
            else {strncpy(np, prefix, 16); np[16] = 0; strcat(np, cmd[0] == 'P' ? ": " : "- ");}
            add_row(r, kind, np, text);
        } else if (strchr(prefix, '.') == 0 && *prefix) {
            if (kind == K_ACTION_L) {strcpy(np, "* "); strncat(np, prefix, 16); strcat(np, " ");}
            else {strcpy(np, "*"); strncat(np, prefix, 16); strcat(np, "* ");}
            add_row(lcur, K_PRIV_IN_L, np, text);
        } else if (ln.ready) add_row(lcur, K_SYSTEM_L, "", text);
    } else if (cmd[0] >= '4' && cmd[0] <= '5' && cmd[1] >= '0' && cmd[1] <= '9' && cmd[2] >= '0' && cmd[2] <= '9') {
        p = strstr(rest, " :");
        say_system(p ? p + 2 : cmd);
    }
}

static uint8_t tcp_open(void) {
    net->open[4] = (uint8_t)cfg_port; net->open[5] = (uint8_t)(cfg_port >> 8);
    net->open[6] = 0xFF; net->open[7] = 0xFF;
    net->open[8] = 0; net->open[9] = 0; net->open[10] = 2;      /* resident: it outlives this program */
    ur_hl = (uint16_t)net->open;
    if (unapi(TCPIP_TCP_OPEN)) return net_error("CONNECTION FAILED");
    ln.conn = (uint8_t)(ur_bc >> 8); ln.net = NET_OPEN;
    return 1;
}

static void set_ip(void) {
    net->open[0] = (uint8_t)ur_hl; net->open[1] = (uint8_t)(ur_hl >> 8);
    net->open[2] = (uint8_t)ur_de; net->open[3] = (uint8_t)(ur_de >> 8);
}

/* Advance the connection and handle whatever has arrived. */
static void net_step(void) {
    uint8_t err, state;
    if (ln.net == NET_OFF) return;
    if (!ln.ready && (uint16_t)(JIFFY - ln.started) > SECONDS(60)) {net_error("timed out"); return;}
    if (ln.net == NET_DNS) {
        ur_bc = 0; err = unapi(TCPIP_DNS_S);
        if (err) {net_error("DNS ERROR"); return;}
        if ((ur_bc >> 8) == 1) return;
        if ((ur_bc >> 8) != 2) {net_error("DNS FAILED"); return;}
        set_ip(); tcp_open();
        return;
    }
    if (ln.net == NET_OPEN) {
        ur_bc = (uint16_t)ln.conn << 8; ur_hl = 0;
        err = unapi(TCPIP_TCP_STATE); state = (uint8_t)(ur_bc >> 8);
        if (err) {net_error("CONNECTION FAILED"); return;}
        if (state != 4) return;
        ln.net = NET_REGISTER;
        irc_line("NICK ", ln.nick, 0, 0);
        irc_line("USER ", ln.nick, " 0 * :MSX Free Chat", 0);
        return;
    }
    for (;;) {
        char *nl;
        ur_bc = (uint16_t)ln.conn << 8; ur_de = (uint16_t)(net->rx + ln.rx_len); ur_hl = RX_SIZE - 1 - ln.rx_len;
        err = unapi(TCPIP_TCP_RCV);
        if (err == ERR_NO_DATA) break;
        if (err) {net_error("disconnected"); return;}
        if (!ur_bc) break;
        ln.rx_len += ur_bc;
        net->rx[ln.rx_len] = 0;
        while ((nl = strchr(net->rx, '\n'))) {
            *nl = 0;
            if (nl > net->rx && nl[-1] == '\r') nl[-1] = 0;
            irc_input(net->rx);
            if (ln.net == NET_OFF) return;
            ln.rx_len -= (uint16_t)(nl + 1 - net->rx);
            memmove(net->rx, nl + 1, ln.rx_len + 1);
        }
        if (ln.rx_len >= RX_SIZE - 1) ln.rx_len = 0;     /* overlong line: drop */
    }
}

static uint8_t net_begin(const char *nick, const char *room) {
    uint8_t err;
    net_close();
    memset(&ln, 0, sizeof(ln));
    memset(lr, 0, sizeof(lr));
    lcount = 1; lcur = 0; lmeta++;
    strncpy(lr[0].name, room, 23);
    strncpy(ln.nick, nick, 16);
    ln.active = 1;
    ln.started = JIFFY;
    strcpy(net->host, cfg_host);
    ur_hl = (uint16_t)net->host; ur_bc = 0;
    err = unapi(TCPIP_DNS_Q);
    if (err) return net_error(err == 2 ? "NO NETWORK" : "DNS ERROR");
    if ((ur_bc >> 8) == 0) {ln.net = NET_DNS; return 1;}
    set_ip();
    return tcp_open();
}


/* ------------------------------------------------------- games (PLAYNET) */
/* MSXG1 invitations (games_local.c, PLAYNET-PROTOCOLS.md 12), the games being the GAME.GPF files in the
 * current directory. A game is handed to PLAYNET /T through PLAYNET.SES (13.1). The IRC connection is closed
 * (QUIT) before the game: kept open it cost 3-54 % of the game's speed (PLAYNET-TCPIP-PERFORMANCE.md 5.6a), and
 * the MCHAT /T that PLAYNET types afterwards connects again. */
#include "games_local.c"

#define TCPIP_GET_IPINFO 2
#define SES_STATE 32

static uint16_t gsec, gjif, grem;
static uint16_t cfg_gport;
static uint8_t cfg_glink;               /* MCHAT.INI GAMELINK=1: the game's packets over TCP/IP even with an MSXPi */
static char cfg_gaddr[16];
static uint8_t ses[GL_SESSION];

uint16_t gl_seconds(void) {
    uint16_t j = JIFFY, d = j - gjif;
    gjif = j;
    d += grem;
    gsec += d / 60u;
    grem = d % 60u;
    return gsec;
}
uint8_t gl_random(void) { return rnd(); }
void gl_send(const char *nick, const char *text) { irc_line("PRIVMSG ", nick, " :", text); }
void gl_say(const char *text) { say_system(text); }

static char *put_dec(char *p, uint16_t v) {
    char d[6]; uint8_t n = 0;
    do {d[n++] = (char)('0' + v % 10); v /= 10;} while (v);
    while (n) *p++ = d[--n];
    *p = 0;
    return p;
}

/* An MSXPi command "playnet ..." (PLAYNET-PROTOCOLS.md 15): the reply text into pr. 1 on success. With no
   interface the control port floats to FFh and the exchange would wait for ever, so it is not tried. */
static char pcmd[112], pr[80];
static uint8_t pi_playnet(void) {
    uint8_t rc;
    uint16_t size = 0, maxbuf = sizeof(pr) - 1;
    if (InPort(CONTROL_PORT1) > 1) return 0;
    msxpi_link_claim();
    rc = link_command(pcmd, false);
    if (rc == RC_SUCCESS) rc = link_recv(LINK_RECV_BUFFER, (uint8_t *)pr, maxbuf, &size);
    msxpi_link_release();
    if (rc != RC_SUCCESS) return 0;
    pr[size < sizeof(pr) ? size : sizeof(pr) - 1] = 0;
    return 1;
}

/* "playnet open ID": the Pi opens its game socket and answers "<profile hash> <candidates>" (the candidates go to out,
   64 bytes). 0 when there is no MSXPi, or it does not have the game or does not know the command. */
static uint8_t pi_game_port(char *out) {
    char *c;
    strcpy(pcmd, "playnet open "); strcat(pcmd, gl_cur_game);
    if (!pi_playnet() || !(c = strchr(pr, ' ')) || strlen(c + 1) > 63) return 0;
    strcpy(out, c + 1);
    return 1;
}

uint8_t gl_peers(const char *token, uint8_t seat, const char *candidates) {
    strcpy(pcmd, "playnet peers "); strcat(pcmd, token);
    strcat(pcmd, seat ? " 1 " : " 0 "); strcat(pcmd, gl_cur_game); strcat(pcmd, " "); strcat(pcmd, candidates);
    return pi_playnet() && pr[0] == 'O';
}

/* the game's UDP port and where it can be reached: the LAN address first, then GAMEADDR (MCHAT.INI: a
   forwarded or public address) when set */
uint16_t gl_open(char *out) {
    uint16_t port = cfg_gport ? cfg_gport : (uint16_t)(5000 + (rnd() & 0x3FF));
    char *p = out;
    uint8_t i;
    if (cfg_glink != 1 && pi_game_port(out)) {gl_link = 2; return 1;}   /* an MSXPi: it carries the game's packets (link 2) */
    ur_bc = 1 << 8;                                          /* B = 1: the local address */
    if (unapi(TCPIP_GET_IPINFO)) return 0;
    for (i = 0; i < 4; i++) {
        p = put_dec(p, i == 0 ? (uint8_t)ur_hl : i == 1 ? (uint8_t)(ur_hl >> 8) : i == 2 ? (uint8_t)ur_de : (uint8_t)(ur_de >> 8));
        *p++ = i < 3 ? '.' : ':';
    }
    p = put_dec(p, port);
    if (cfg_gaddr[0]) {*p++ = ','; strcpy(p, cfg_gaddr); p += strlen(p); *p++ = ':'; put_dec(p, port);}
    return port;
}

static void ses_name(FCB *f) {
    memset(f, 0, sizeof(FCB));
    memcpy(f->name, "PLAYNET SES", 11);
}

/* the GPF headers in the current directory: the games this machine has */
static void load_games(void) {
    static FCB f;
    static FCB_FIND found;
    uint8_t *h = ses, i;
    gl_ngames = 0;
    memset(&f, 0, sizeof(f));
    memcpy(f.name, "????????GPF", 11);
    if (fcb_find_first(&f, &found)) return;
    do {
        static FCB g;
        memset(&g, 0, sizeof(g));
        memcpy(g.name, found.dirinfo.name, 11);
        if (fcb_open(&g)) continue;
        g.record_size = 1;
        i = (uint8_t)fcb_read(&g, h, 128);
        fcb_close(&g);
        if (i == 128 && !memcmp(h, "GPF1", 4) && h[4] == 1 && (h[5] & 1) && gl_ngames < GL_MAX_GAMES) {
            gl_game *gm = &gl_games[gl_ngames++];
            memcpy(gm->id, h + 12, 8); gm->id[8] = 0;
            memcpy(gm->title, h + 20, 24); gm->title[24] = 0;
            memcpy(gm->roles[0], h + 44, 8); gm->roles[0][8] = 0;
            memcpy(gm->roles[1], h + 52, 8); gm->roles[1][8] = 0;
            gm->lockstep = 1;
            memcpy(gm->hash, h + 8, 4);
        }
    } while (!fcb_find_next(&found));
}

/* the game is handed over: PLAYNET.SES with the session and this connection */
static uint8_t write_session(void) {
    static FCB f;
    uint8_t i;
    gl_session(ses);
    ses[59] = 0xFF;                     /* no connection kept: PLAYNET.OVL has nothing to read */
    strncpy((char *)ses + 60, ln.nick, 16);
    ses[77] = lcount;
    for (i = 0; i < lcount; i++) strncpy((char *)ses + 78 + i * 24, lr[i].name, 23);
    ses_name(&f);
    if (fcb_create(&f)) return 0;
    f.record_size = 1;
    i = fcb_write(&f, ses, GL_SESSION);
    fcb_close(&f);
    return i == 0;
}

/* After a game: PLAYNET wrote its result into PLAYNET.SES. Take the IRC connection back when it is still
   up, and say how the game ended. 1 = the chat is back as it was. */
static uint8_t resume_session(void) {
    static FCB f;
    uint8_t i, ok = 0;
    char peer[9];
    ses_name(&f);
    if (fcb_open(&f)) return 0;
    f.record_size = 1;
    i = (uint8_t)fcb_read(&f, ses, 128) == 128;
    fcb_close(&f);
    if (!i || memcmp(ses, "PNS1", 4) || (ses[9] != 1 && ses[9] != 2)) return 0;
    ses_name(&f);                                             /* used: empty it */
    if (!fcb_create(&f)) fcb_close(&f);
    ur_bc = (uint16_t)ses[59] << 8; ur_hl = 0;
    if (ses[59] != 0xFF && !unapi(TCPIP_TCP_STATE) && (uint8_t)(ur_bc >> 8) == 4) {
        ln.conn = ses[59]; ln.net = NET_READY; ln.ready = 1; ln.active = 1;
        ln.started = JIFFY;
        strncpy(ln.nick, (char *)ses + 60, 16); ln.nick[16] = 0;
        lcount = ses[77] > LMAXR ? LMAXR : ses[77];
        if (!lcount) lcount = 1;
        for (i = 0; i < lcount; i++) {
            strncpy(lr[i].name, (char *)ses + 78 + i * 24, 23);
            lr[i].joined = 1;
            irc_line("NAMES ", lr[i].name, 0, 0);
        }
        lcur = 0; lmeta++;
        ok = 1;
    }
    memcpy(peer, ses + 24, 8); peer[8] = 0;
    gl_restore(peer);
    gl_resumed(ses[SES_STATE] == 2 ? ses[SES_STATE + 1] : 0);
    if (!ok && ses[59] != 0xFF) say_system("The IRC connection did not survive the game: connecting again");
    return ok;
}

/* ------------------------------------------------------------- settings */

static void load_config(void) {
    static FCB fcb;
    char *data = (char *)reply;      /* idle until the first exchange */
    char *line, *eq, *end;
    uint16_t n;
    uint8_t i;
    strcpy(cfg_nick, "msx");
    for (i = 3; i < 7; i++) cfg_nick[i] = "0123456789abcdef"[rnd() & 15];
    cfg_nick[7] = 0;
    memset(&fcb, 0, sizeof(fcb));
    memcpy(fcb.name, "MCHAT   INI", 11);
    if (fcb_open(&fcb)) return;
    fcb.record_size = 1;
    n = fcb_read(&fcb, data, 255);
    fcb_close(&fcb);
    data[n] = 0;
    for (line = data; *line; line = end) {
        end = line;
        while (*end && *end != '\r' && *end != '\n' && *end != 0x1A) end++;
        if (*end) *end++ = 0;
        while (*end == '\r' || *end == '\n' || *end == 0x1A) end++;
        eq = strchr(line, '=');
        if (!eq) continue;
        *eq++ = 0;
        if (!strcmp(line, "IRCADDR") && *eq && strlen(eq) < 48) strcpy(cfg_host, eq);
        else if (!strcmp(line, "IRCPORT")) {cfg_port = 0; while (*eq >= '0' && *eq <= '9') cfg_port = cfg_port * 10 + (*eq++ - '0');}
        else if (!strcmp(line, "IRCNICK") && valid_nick(eq)) strcpy(cfg_nick, eq);
        else if (!strcmp(line, "MCHATROOM") && *eq == '#' && strlen(eq) < 24) strcpy(cfg_room, eq);
        else if (!strcmp(line, "GAMEPORT")) {cfg_gport = 0; while (*eq >= '0' && *eq <= '9') cfg_gport = cfg_gport * 10 + (*eq++ - '0');}
        else if (!strcmp(line, "GAMEADDR") && strlen(eq) < 16) strcpy(cfg_gaddr, eq);
        else if (!strcmp(line, "GAMELINK")) cfg_glink = (uint8_t)(*eq == '1');
    }
    memset(reply, 0, 256);
}

/* Called for "mchat /t"; 0 with a message when TCP/IP is not usable. */
static const char *tcp_link_start(void) {
    const char *why;
    uint16_t top = *(uint16_t *)0x0006;
    memset(&ln, 0, sizeof(ln));
    memset(lr, 0, sizeof(lr));
    lcount = 0; lcur = 0; lmeta = 0; lw = 40;
    /* the start-up zeroes nothing: these come in as FFh, and an FFh GAMEADDR is a string without an end */
    lt_seg = 0; cfg_gport = 0; cfg_gaddr[0] = 0; cfg_glink = 0;
    gsec = 0; grem = 0; gjif = JIFFY;
    gl_init();
    if (!tcp_find()) return "No TCP/IP UNAPI: run INL I first";
    if ((uint16_t)&net_area < 0x8000 || (uint16_t)seg_code < 0x8000) return "TCP/IP buffer is in page 1";
    if ((why = lt_open())) return why;
    if (top < heap_top || top - heap_top < STACK_ROOM) return "Not enough memory for TCP/IP";
    net = &net_area;
    load_config();
    load_games();
    return 0;
}

static void tcp_link_stop(void) {
    if (net && !gl_launched()) net_close();      /* a game keeps the connection */
    lt_close();
}

/* -------------------------------------------------------------- packets */

static void packet_header(char type) {
    memset(reply, 0, 256);
    memcpy(reply, "CHT1", 4);
    reply[4] = !ln.active ? 4 : ln.lost ? 2 : ln.ready ? 1 : 0;
    reply[5] = type;
    reply[22] = gl_flags();
}

static void rows_packet(uint8_t r, uint16_t start) {
    uint8_t i, count, slot_size = 2 + lw, per = (256 - 24) / (2 + lw), s;
    char row[RW];
    uint16_t first, n;
    packet_header('M');
    if (!ln.active || r >= lcount) {reply[4] = 4; return;}
    first = lr[r].next > LROWS ? lr[r].next - LROWS : 0;
    if (start < first) start = first;
    n = lr[r].next > start ? lr[r].next - start : 0;
    count = n > per ? per : (uint8_t)n;
    reply[6] = lcount; reply[7] = count;
    reply[8] = (uint8_t)first; reply[9] = (uint8_t)(first >> 8);
    reply[10] = (uint8_t)lr[r].next; reply[11] = (uint8_t)(lr[r].next >> 8);
    for (i = 0; i < lcount; i++) {reply[12 + i * 2] = (uint8_t)lr[i].next; reply[13 + i * 2] = (uint8_t)(lr[i].next >> 8);}
    reply[20] = lmeta; reply[21] = lcur;
    for (i = 0; i < count; i++) {
        s = (start + i) % LROWS;
        lt_copy(row, LT(r, s), RW);
        reply[24 + i * slot_size] = row[0];
        reply[25 + i * slot_size] = row[1];
        memcpy(reply + 26 + i * slot_size, row + 2, strlen(row + 2));
    }
}

static void meta_packet(uint8_t first) {
    uint8_t i, n = 0;
    packet_header('U');
    if (!ln.active) return;
    reply[6] = lcount; reply[7] = lcur;
    reply[8] = lr[lcur].nusers; reply[9] = 0;
    memcpy(reply + 12, ln.nick, strlen(ln.nick) > 11 ? 11 : strlen(ln.nick));
    for (i = 0; i < lcount; i++) memcpy(reply + 24 + i * 12, lr[i].name, strlen(lr[i].name) > 11 ? 11 : strlen(lr[i].name));
    for (i = first; i < lr[lcur].nusers && n < 15; i++, n++) {uget(lcur, i); memcpy(reply + 72 + n * 12, ub, strlen(ub));}
    reply[10] = n;
}

/* ------------------------------------------------------------- commands */

static const char *num_arg(const char *p, uint16_t *v) {
    *v = 0;
    while (*p == ' ') p++;
    while (*p >= '0' && *p <= '9') *v = *v * 10 + (*p++ - '0');
    return p;
}

static void user_say(char *text) {
    char *arg, *p;
    uint8_t r;
    while (*text == ' ') text++;
    clean(text);
    if (!*text) return;
    if (*text != '/') {
        if (!ln.ready) {say_system("! Not connected yet; wait"); return;}
        if (!irc_line("PRIVMSG ", lr[lcur].name, " :", text)) {say_system("! Send failed"); return;}
        {char np[24]; strcpy(np, ln.nick); strcat(np, ": "); add_row(lcur, K_OWN_L, np, text);}
        return;
    }
    arg = strchr(text, ' ');
    if (arg) {*arg++ = 0; while (*arg == ' ') arg++;} else arg = text + strlen(text);
    text++;
    for (p = text; *p; p++) if (*p >= 'A' && *p <= 'Z') *p += 32;
    if (!strcmp(text, "msg") || !strcmp(text, "m") || !strcmp(text, "query") || !strcmp(text, "q")) {
        char *body = strchr(arg, ' ');
        if (!body) {say_system("! Use /msg NICK TEXT"); return;}
        *body++ = 0;
        while (*body == ' ') body++;
        if (!*arg || !*body) {say_system("! Use /msg NICK TEXT"); return;}
        if (!irc_line("PRIVMSG ", arg, " :", body)) {say_system("! Send failed"); return;}
        {char np[24]; strcpy(np, "->"); strncat(np, arg, 16); strcat(np, ": "); add_row(lcur, K_PRIV_OUT_L, np, body);}
    } else if (!strcmp(text, "me")) {
        char line[TX_SIZE - 40];
        if (!*arg) {say_system("! Use /me TEXT"); return;}
        strcpy(line, "\x01" "ACTION "); strncat(line, arg, 100); strcat(line, "\x01");
        if (!irc_line("PRIVMSG ", lr[lcur].name, " :", line)) {say_system("! Send failed"); return;}
        {char np[24]; strcpy(np, "* "); strcat(np, ln.nick); strcat(np, " "); add_row(lcur, K_ACTION_L, np, arg);}
    } else if (!strcmp(text, "nick")) {
        if (!valid_nick(arg)) {say_system("! Invalid nick"); return;}
        irc_line("NICK ", arg, 0, 0);
    } else if (!strcmp(text, "join") || !strcmp(text, "j")) {
        char name[24];
        if (!*arg) {say_system("! Use /join #ROOM"); return;}
        p = strchr(arg, ' '); if (p) *p = 0;
        if (*arg != '#') {name[0] = '#'; strncpy(name + 1, arg, 22); name[23] = 0;} else {strncpy(name, arg, 23); name[23] = 0;}
        r = find_room(name);
        if (r == 0xFF) {
            if (lcount >= LMAXR) {say_system("! Room limit reached; /part one first"); return;}
            r = lcount++;
            memset(&lr[r], 0, sizeof(LRoom));
            strcpy(lr[r].name, name);
            if (ln.ready) irc_line("JOIN ", name, 0, 0);
        }
        lcur = r; lmeta++;
    } else if (!strcmp(text, "part") || !strcmp(text, "leave")) {
        if (lcount < 2) {say_system("! Cannot leave the only room"); return;}
        irc_line("PART ", lr[lcur].name, 0, 0);
        for (r = lcur; r + 1 < lcount; r++) {
            lr[r] = lr[r + 1];
            lt_copy(LT(r, 0), LT(r + 1, 0), LROWS * RW); lt_copy(LU(r, 0), LU(r + 1, 0), LUSERS * 12);
        }
        lcount--;
        if (lcur) lcur--;
        lmeta++;
    } else if (!strcmp(text, "who")) {
        char list[LTEXT]; uint8_t i;
        list[0] = 0;
        for (i = 0; i < lr[lcur].nusers && strlen(list) < LTEXT - 14; i++) {strcat(list, uget(lcur, i)); strcat(list, " ");}
        add_row(lcur, K_SYSTEM_L, "", list);
    } else if (!strcmp(text, "play")) {
        char *gid = strchr(arg, ' ');
        if (gid) {*gid++ = 0; while (*gid == ' ') gid++; for (p = gid; *p; p++) if (*p >= 'A' && *p <= 'Z') *p += 32;}
        else gid = "";
        if (!ln.ready) {say_system("! Not connected yet; wait"); return;}
        gl_play(arg, gid);
    } else if (!strcmp(text, "accept")) gl_accept();
    else if (!strcmp(text, "decline")) gl_decline();
    else if (!strcmp(text, "cancel")) gl_cancel();
    else if (!strcmp(text, "games")) gl_list();
    else if (!strcmp(text, "help") || !strcmp(text, "?")) {
        say_system("/nick N /msg N TEXT /join #ROOM /part /me TEXT /who /screen /help. TAB next room, ESC quit");
    } else say_system("! Unknown command; /help");
}

/* The same commands the MSXPi server answers; cmd starts with "mchat ". */
static uint8_t local_exchange(const char *cmd) {
    const char *p = cmd + 6;
    uint16_t a, b;
    static char tmp[MAX_INPUT + 2];
    if (!net) return 0;
    net_step();
    if (!strncmp(p, "start", 5)) {
        char nick[17];
        uint16_t width;
        p += 5; while (*p == ' ') p++;
        for (b = 0; *p && *p != ' ' && b < 16; ) nick[b++] = *p++;
        nick[b] = 0;
        p = num_arg(p, &width);
        if (width < 20 || width > TW_MAX) width = 40;
        if (ln.active && !ln.lost) {
            if (width != lw) {                       /* the history cannot be wrapped again */
                uint8_t i;
                for (i = 0; i < lcount; i++) {lr[i].next = 0;}
                lw = (uint8_t)width;
                say_system("Screen changed: history cleared");
                lmeta++;
            }
        } else {
            lw = (uint8_t)width;
            if (!resume_session()) {
                net_begin(nick[0] && strcmp(nick, "-") ? nick : cfg_nick, cfg_room);
                say_system("Connecting...");
            }
        }
        rows_packet(lcur, 0xFFFF);
    } else if (!strncmp(p, "launch", 6)) {
        const char *line = gl_take_launch();
        packet_header('L');
        if (line && write_session()) {reply[6] = 1; strcpy((char *)reply + 24, line); net_close(); ln.active = 0;}
        else if (line) say_system("! Cannot write PLAYNET.SES");
    } else if (!strncmp(p, "quit", 4)) {
        net_close(); ln.active = 0;
        packet_header('M'); reply[4] = 4;
    } else if (!ln.active) {
        packet_header('M'); reply[4] = 4;
    } else if (!strncmp(p, "get", 3)) {
        p = num_arg(p + 3, &a); p = num_arg(p, &b);
        rows_packet((uint8_t)a, b);
    } else if (!strncmp(p, "meta", 4)) {
        num_arg(p + 4, &a);
        meta_packet((uint8_t)a);
    } else if (!strncmp(p, "room", 4)) {
        num_arg(p + 4, &a);
        if (a < lcount) {lcur = (uint8_t)a; lmeta++;}
        rows_packet(lcur, 0xFFFF);
    } else if (!strncmp(p, "say", 3)) {
        strncpy(tmp, p + 3, MAX_INPUT); tmp[MAX_INPUT] = 0;
        user_say(tmp);
        rows_packet(lcur, 0xFFFF);
    } else {
        packet_header('M'); reply[4] = 3;
        strcpy((char *)reply + 26, "Unknown mchat command");
    }
    return 1;
}
