/* PLAYNET.OVL: netcore on the MSX, over the TCP/IP UNAPI (InterNestor Lite, GR8NET, ...).
 * PLAYNET.COM /T loads it into a mapper segment and maps it at 8000h for each call: in MSX-DOS for the
 * connect phase, and through the UNAPI transport's shim (transport_unapi.asm) during the game.
 * Entries and the I/O block: ovl_crt0.s; documents/PLAYNET-PROTOCOLS.md 10.
 *
 * Everything the TCP/IP implementation reads or writes is in page 3 (io.buf), and the caller's stack is
 * in page 3 too: a RAM implementation maps its own segments into pages 1 and 2 while it runs (measured,
 * PLAYNET-DESIGN.md 8a), so this segment is not visible to it. In the game, page 3 is MSX-DOS's own
 * segment during a call (the game has another one), so io.buf and the stack are MSX-DOS's memory.
 */
#include <stdint.h>
#include <string.h>
#include "netcore.h"

/* The I/O block (its address is in the header, +16). PLAYNET.COM and the transport use fixed offsets:
 * keep in step with OVL_* in playnet.asm and transport_unapi.asm. */
typedef struct {
    uint16_t ticks;         /*  0  address of a 16-bit tick counter: JIFFY in MSX-DOS, the transport's in the game */
    uint8_t hz;             /*  2  its rate, 50 or 60 */
    uint8_t *buf;           /*  3  128 bytes in page 3 for the UNAPI calls */
    uint32_t profile;       /*  5 */
    uint8_t version;        /*  9 */
    uint8_t force_delay;    /* 10 */
    uint16_t lport;         /* 11  the local UDP port */
    uint8_t ncand;          /* 13 */
    nc_addr cand[NC_MAX_CANDIDATES];    /* 14  3 x (ip 4, port 2) */
    uint8_t *pkt;           /* 32  XCHG: the packet to send, or 0 */
    uint8_t len;            /* 34  its length L */
    uint8_t *rx;            /* 35  XCHG: where a received packet goes (L bytes) */
    uint8_t status;         /* 37  open: 0 ok, 1 no TCP/IP UNAPI, 2 UDP_OPEN failed; poll: NC_ST_*; xchg: NC_X_* */
    uint8_t delay;          /* 38  poll: the input delay once ready */
    uint8_t reason;         /* 39  xchg: the opponent's result code; bye: ours */
    uint8_t leader;         /* 40  poll: 1 when this side leads */
    uint8_t txbuf[NC_MAX_PKT];  /* 41  the game's packets cross a page-3 switch here (transport_unapi.asm) */
    uint8_t rxbuf[NC_MAX_PKT];  /* 87 */
    uint8_t irc;            /* 133 MCHAT /T's IRC TCP connection, kept alive through the game; FFh: none */
} ovl_io_t;

ovl_io_t ovl_io;

/* ---- UNAPI calls (as in mchat_local.c) -------------------------------------------------- */
#define EXTBIO 0xFFCA
#define ARG 0xF847
#define TCPIP_UDP_OPEN 8
#define TCPIP_UDP_CLOSE 9
#define TCPIP_UDP_SEND 11
#define TCPIP_UDP_RCV 12
#define TCPIP_TCP_SEND 17
#define TCPIP_TCP_RCV 18
#define ERR_OK 0
#define ERR_NO_DATA 3
#define since(a, b) ((int16_t)(uint16_t)((uint16_t)(a) - (uint16_t)(b)))   /* as in netcore.c */

uint8_t ur_a;
uint16_t ur_bc, ur_de, ur_hl, ur_ix;
uint16_t un_ix, un_iy;
uint8_t un_jp[3];
static uint8_t un_slot, un_seg, conn;
static uint16_t un_addr, un_helper;

/* Call un_jp (a JP to the target) with A, BC, DE, HL, IX and IY loaded from the variables above. */
static void raw_call(void) __naked
{
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

static void jp_to(uint16_t target)
{
    un_jp[0] = 0xC3; un_jp[1] = (uint8_t)target; un_jp[2] = (uint8_t)(target >> 8);
}

static void extbio(uint8_t a)
{
    memcpy((char *)ARG, "TCP/IP", 7);
    jp_to(EXTBIO);
    un_ix = 0; un_iy = 0;
    ur_a = a; ur_bc = 0; ur_de = 0x2222; ur_hl = 0;
    raw_call();
}

static uint8_t tcp_find(void)
{
    extbio(0);
    if (!(ur_bc >> 8))
        return 0;
    extbio(1);
    un_slot = ur_a; un_seg = (uint8_t)(ur_bc >> 8); un_addr = ur_hl;
    un_helper = 0;
    if (un_seg != 0xFF) {
        extbio(0xFF);
        un_helper = ur_hl;
        if (!un_helper)
            return 0;
    }
    return 1;
}

static uint8_t unapi(uint8_t fn)
{
    if (un_seg != 0xFF) {
        jp_to(un_helper);                   /* CALL_MAP */
        un_ix = un_addr; un_iy = ((uint16_t)un_slot << 8) | un_seg;
    } else if (un_addr >= 0xC000) {
        jp_to(un_addr);
    } else {
        jp_to(0x001C);                      /* CALSLT */
        un_ix = un_addr; un_iy = (uint16_t)un_slot << 8;
    }
    ur_a = fn;
    raw_call();
    return ur_a;
}

/* ---- netcore's host functions -------------------------------------------------------------- */
#define TXBUF 0                             /* offsets in io.buf */
#define PARAMS 48                           /* UDP_SEND: ip 4, port 2, length 2 */
#define RXBUF 56                            /* 64 bytes */

void nc_send(const nc_addr *to, const uint8_t *data, uint8_t len)
{
    uint8_t *b = ovl_io.buf;
    memcpy(b + TXBUF, data, len);
    memcpy(b + PARAMS, to->ip, 4);
    b[PARAMS + 4] = (uint8_t)to->port; b[PARAMS + 5] = (uint8_t)(to->port >> 8);
    b[PARAMS + 6] = len; b[PARAMS + 7] = 0;
    ur_bc = (uint16_t)conn << 8; ur_hl = (uint16_t)(b + TXBUF); ur_de = (uint16_t)(b + PARAMS);
    unapi(TCPIP_UDP_SEND);
}

uint8_t nc_recv(nc_addr *from, uint8_t *buf, uint8_t max)
{
    uint8_t *b = ovl_io.buf;
    ur_bc = (uint16_t)conn << 8; ur_hl = (uint16_t)(b + RXBUF); ur_de = 64;
    if (unapi(TCPIP_UDP_RCV) != ERR_OK)
        return 0;                           /* ERR_NO_DATA, or anything else: nothing */
    from->ip[0] = (uint8_t)ur_hl; from->ip[1] = (uint8_t)(ur_hl >> 8);      /* L.H.E.D */
    from->ip[2] = (uint8_t)ur_de; from->ip[3] = (uint8_t)(ur_de >> 8);
    from->port = ur_ix;
    if (ur_bc > max || ur_bc > 64)
        return 0;
    memcpy(buf, b + RXBUF, ur_bc);
    return (uint8_t)ur_bc;
}

/* netcore's time is the host's tick itself: a 16-bit read, no arithmetic (the rate goes to nc_init) */
uint16_t nc_now(void)
{
    return *(volatile uint16_t *)ovl_io.ticks;
}

static uint8_t r_reg(void) __naked
{
__asm
    ld a,r
    ld l,a
    ret
__endasm;
}

uint32_t nc_rand32(void)
{
    uint32_t x = ((uint32_t)r_reg() << 24) ^ ((uint32_t)*(volatile uint16_t *)0xFC9E << 8) ^ r_reg();
    x ^= (uint32_t)ovl_io.lport << 12;
    return x ^ ((uint32_t)r_reg() << 16);
}

/* ---- the IRC connection MCHAT /T left open (PROTOCOLS 14) -----------------------------------------
 * Twice a second: read what arrived (at most 4 x 56 bytes), drop it, and answer each "PING x" with
 * "PONG x", so the server keeps the connection through a long game. io.buf: 0-55 what is read, 64-127
 * the answer (the UDP calls use it only inside nc_send / nc_recv). */
#define IRC_LINE 62
static char irc_line[IRC_LINE];
static uint8_t irc_len;                     /* FFh: in a line too long to be a PING: skipped to its end */
static uint16_t irc_due;

static void irc_keep(uint16_t now)
{
    uint8_t *b = ovl_io.buf, i, n, reads = 4;
    if (ovl_io.irc == 0xFF || since(now, irc_due) < 0)
        return;
    irc_due = now + (ovl_io.hz >> 1);
    do {
        ur_bc = (uint16_t)ovl_io.irc << 8; ur_de = (uint16_t)b; ur_hl = 56;
        i = unapi(TCPIP_TCP_RCV);
        if (i != ERR_OK) {
            if (i != ERR_NO_DATA)
                ovl_io.irc = 0xFF;          /* closed or gone: MCHAT /T connects again */
            return;
        }
        n = (uint8_t)ur_bc;
        for (i = 0; i < n; i++) {
            char c = b[i];
            if (c == '\n') {
                if (irc_len != 0xFF && irc_len >= 5 && !memcmp(irc_line, "PING ", 5)) {
                    memcpy(b + 64, irc_line, irc_len);
                    b[65] = 'O';            /* PONG */
                    b[64 + irc_len] = '\r'; b[65 + irc_len] = '\n';
                    ur_bc = ((uint16_t)ovl_io.irc << 8) | 1; ur_de = (uint16_t)(b + 64); ur_hl = irc_len + 2;
                    unapi(TCPIP_TCP_SEND);
                }
                irc_len = 0;
            } else if (c != '\r' && irc_len != 0xFF)
                irc_line[irc_len] = c, irc_len = irc_len < IRC_LINE - 1 ? irc_len + 1 : 0xFF;
        }
    } while (n == 56 && --reads);
}

/* ---- the entries --------------------------------------------------------------------------- */
void ovl_open(void)
{
    if (!tcp_find()) {
        ovl_io.status = 1;
        return;
    }
    ur_hl = ovl_io.lport; ur_bc = 0;        /* transient */
    if (unapi(TCPIP_UDP_OPEN) != ERR_OK) {
        ovl_io.status = 2;
        return;
    }
    conn = (uint8_t)(ur_bc >> 8);
    nc_init(ovl_io.profile, ovl_io.version, ovl_io.force_delay, ovl_io.hz);
    nc_set_peers(ovl_io.cand, ovl_io.ncand);
    nc_restart();
    ovl_io.status = 0;
}

void ovl_poll(void)
{
    irc_keep(nc_now());
    nc_poll();
    ovl_io.status = nc_status(&ovl_io.delay);
    ovl_io.leader = nc_is_leader();
}

void ovl_xchg(void)
{
    irc_keep(nc_now());
    ovl_io.status = nc_xchg(ovl_io.pkt, ovl_io.len, ovl_io.rx, &ovl_io.reason);
}

/* the clock must be running (interrupts on): the BYEs go 100 ms apart; at most about a second */
void ovl_bye(void)
{
    uint16_t t0 = nc_now();
    nc_bye(ovl_io.reason);
    while (nc_bye_pending() && (uint16_t)(nc_now() - t0) < ovl_io.hz)
        nc_poll();
}

void ovl_close(void)
{
    ur_bc = (uint16_t)conn << 8;
    unapi(TCPIP_UDP_CLOSE);
}
