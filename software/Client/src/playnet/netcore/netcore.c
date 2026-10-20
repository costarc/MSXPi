/* netcore: the MSXNP session engine. Specification: documents/PLAYNET-PROTOCOLS.md 11; it follows
 * Server/Python/src/msxpi_netplay.py (Netplay) step by step, so that the two meet as equals.
 * See netcore.h for the host interface. */
#include <string.h>
#include "netcore.h"

#define KIND_GAME 0x10
#define CTL_LEN 14
#define T_HELLO 1
#define T_PING 2
#define T_PONG 3
#define T_SETUP 4
#define T_ACK 5
#define T_BYE 6

#define S_IDLE 0
#define S_CONNECT 1
#define S_SETUP 2
#define S_READY 3
#define S_INCOMPATIBLE 4
#define S_FAILED 5
#define S_DEAD 6
#define S_LEFT 7
#define S_ENDED 8

#define PINGS 8
#define MIN_SAMPLES 4
#define MAX_PINGS 64
#define CONNECT_TIMEOUT 12000           /* centiseconds */
#define START_TIMEOUT 6000
#define DEAD_AFTER 1500
#define HELLO_GAP 20
#define PING_GAP 10
#define SETUP_GAP 20
#define BYE_GAP 10
#define BYE_REPEAT 3
#define PING_QUIET 100                  /* no PING for this long after the last one: decide with what came back */
#define MIN_DELAY 2
#define MAX_DELAY 6
#define FRAME_MS 20                     /* 50 Hz: the longest frame */
#define RXQ 8                           /* game packets received and not yet taken */

static uint8_t state;
static uint8_t version;
static uint32_t profile;
static uint8_t forced_delay;
static nc_addr peers[NC_MAX_CANDIDATES];
static uint8_t npeers;
static nc_addr peer;
static uint8_t locked;
static uint32_t nonce;
static uint8_t have_peer_nonce;
static uint8_t leader;
static uint8_t pings_sent;
static uint16_t ping_t[MAX_PINGS];
static uint8_t ping_open[MAX_PINGS / 8];
static uint16_t rtts[MAX_PINGS];
static uint8_t nrtts;
static uint16_t next_ping, next_hello, next_setup, t_start, t_ready, last_rx, next_bye;
static uint8_t playing;
static uint8_t delay;
static uint8_t bye_reason, local_result, bye_left;
static uint8_t q[RXQ][NC_MAX_PKT];
static uint8_t qlen[RXQ];
static uint8_t qhead, qcount;
static uint8_t rbuf[64];
static uint8_t cbuf[CTL_LEN];

/* signed difference a - b of two centisecond times. A macro, not a function: SDCC 4.0.0 compiles
 * "return a - b" of two uint16_t arguments into code that overwrites L while HL still points at b. */
#define since(a, b) ((int16_t)(uint16_t)((uint16_t)(a) - (uint16_t)(b)))

static uint32_t get32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void put32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
}

static uint8_t same_addr(const nc_addr *a, const nc_addr *b)
{
    return a->port == b->port && memcmp(a->ip, b->ip, 4) == 0;
}

static uint8_t game_packet_ok(const uint8_t *d, uint8_t len)
{
    return len >= 4 && d[0] == KIND_GAME && d[3] >= 1 && d[3] <= 4 && len == 14 + 8 * d[3];
}

static void send_all(const uint8_t *d, uint8_t len)
{
    uint8_t i;
    if (locked) {
        nc_send(&peer, d, len);
        return;
    }
    for (i = 0; i < npeers; i++)
        nc_send(&peers[i], d, len);
}

static void send_ctl(uint8_t type, uint32_t a)
{
    cbuf[0] = type;
    cbuf[1] = version;
    put32(cbuf + 2, nonce);
    put32(cbuf + 6, a);
    put32(cbuf + 10, 0);
    send_all(cbuf, CTL_LEN);
}

static uint32_t new_nonce(void)
{
    uint32_t n = nc_rand32();
    return n ? n : 1;
}

static void set_ready(uint16_t now)
{
    state = S_READY;
    t_ready = now;
}

/* the leader's input delay: the 90th percentile round trip, one way, in frames, plus 2 */
static uint8_t choose_delay(void)
{
    uint8_t i, j;
    uint16_t v, ms;
    uint8_t d;
    for (i = 1; i < nrtts; i++) {           /* insertion sort, at most 64 values */
        v = rtts[i];
        for (j = i; j > 0 && rtts[j - 1] > v; j--)
            rtts[j] = rtts[j - 1];
        rtts[j] = v;
    }
    ms = rtts[(uint16_t)(9 * (nrtts - 1)) / 10] * 10;
    d = (uint8_t)((ms + 2 * FRAME_MS - 1) / (2 * FRAME_MS)) + 2;
    if (d < MIN_DELAY) d = MIN_DELAY;
    if (d > MAX_DELAY) d = MAX_DELAY;
    return d;
}

static void reset_session(void)
{
    uint16_t now = nc_now();
    nonce = new_nonce();
    have_peer_nonce = 0;
    leader = 0;
    pings_sent = 0;
    memset(ping_open, 0, sizeof ping_open);
    nrtts = 0;
    next_ping = next_hello = next_setup = now;
    t_start = last_rx = now;
    playing = 0;
    delay = 0;
    bye_reason = local_result = bye_left = 0;
    qhead = qcount = 0;
}

void nc_init(uint32_t profile_hash, uint8_t ver, uint8_t force_delay)
{
    profile = profile_hash;
    version = ver;
    forced_delay = force_delay;
    npeers = 0;
    locked = 0;
    state = S_IDLE;
    reset_session();
}

void nc_set_peers(const nc_addr *candidates, uint8_t count)
{
    if (count > NC_MAX_CANDIDATES)
        count = NC_MAX_CANDIDATES;
    memcpy(peers, candidates, count * sizeof(nc_addr));
    npeers = count;
    locked = 0;
}

void nc_restart(void)
{
    reset_session();
    locked = 0;
    state = npeers ? S_CONNECT : S_FAILED;
}

void nc_bye(uint8_t result)
{
    if (state == S_IDLE || state == S_ENDED)
        return;
    local_result = result;
    state = S_ENDED;
    bye_left = BYE_REPEAT;
    next_bye = nc_now();
}

uint8_t nc_bye_pending(void) { return bye_left; }
uint8_t nc_is_leader(void) { return leader; }
const nc_addr *nc_peer(void) { return locked ? &peer : 0; }

static void on_ctl(uint16_t now, const uint8_t *d)
{
    uint8_t type = d[0];
    uint32_t n = get32(d + 2), a = get32(d + 6);
    uint8_t i;
    if (state == S_IDLE) {
        if (type == T_PING)                 /* still answer pings: the peer may be ahead of us */
            send_ctl(T_PONG, a);
        return;
    }
    if (d[1] != version || (type == T_HELLO && a != profile)) {
        if (state == S_CONNECT || state == S_SETUP)
            state = S_INCOMPATIBLE;
        if (state == S_INCOMPATIBLE && type == T_HELLO)
            send_ctl(T_HELLO, profile);     /* let a peer that started later see it too */
        return;
    }
    last_rx = now;
    switch (type) {
    case T_BYE:
        if (state == S_CONNECT || state == S_SETUP || state == S_READY) {
            state = S_LEFT;
            bye_reason = (uint8_t)a;
        }
        break;
    case T_HELLO:
        if (state == S_CONNECT && !have_peer_nonce) {
            if (n == nonce) {
                nonce = new_nonce();
            } else {
                have_peer_nonce = 1;
                leader = nonce > n;
            }
        }
        break;
    case T_PING:
        send_ctl(T_PONG, a);
        break;
    case T_PONG:
        i = (uint8_t)a;
        if (a < MAX_PINGS && (ping_open[i >> 3] & (1 << (i & 7)))) {
            ping_open[i >> 3] &= (uint8_t)~(1 << (i & 7));
            if (state == S_CONNECT)
                rtts[nrtts++] = now - ping_t[i];
        }
        break;
    case T_SETUP:
        if (state == S_CONNECT) {
            delay = (uint8_t)a;
            set_ready(now);
        }
        send_ctl(T_ACK, a);
        break;
    case T_ACK:
        if (state == S_SETUP && a == delay)
            set_ready(now);
        break;
    }
}

static void on_game(uint16_t now, const uint8_t *d, uint8_t len)
{
    uint8_t slot;
    if (state == S_SETUP)                   /* the follower started playing: that is the ACK */
        set_ready(now);
    if (state != S_READY)
        return;
    last_rx = now;
    playing = 1;
    if (qcount == RXQ)
        return;                             /* full: the redundancy in later packets covers it */
    slot = (uint8_t)((qhead + qcount) % RXQ);
    memcpy(q[slot], d, len);
    qlen[slot] = len;
    qcount++;
}

static void receive(uint16_t now)
{
    nc_addr from;
    uint8_t len, i, ok;
    while ((len = nc_recv(&from, rbuf, sizeof rbuf)) != 0) {
        if (!((len == CTL_LEN && rbuf[0] >= T_HELLO && rbuf[0] <= T_BYE) || game_packet_ok(rbuf, len)))
            continue;                       /* malformed, or a STUN reply */
        if (locked) {
            if (!same_addr(&from, &peer))
                continue;
        } else {
            ok = 0;                         /* any port: a NAT may change it */
            for (i = 0; i < npeers; i++)
                if (memcmp(from.ip, peers[i].ip, 4) == 0)
                    ok = 1;
            if (!ok)
                continue;
            if (state == S_CONNECT || state == S_SETUP) {
                peer = from;                /* the first answer: talk to this address only */
                locked = 1;
            }
        }
        if (rbuf[0] == KIND_GAME)
            on_game(now, rbuf, len);
        else
            on_ctl(now, rbuf);
    }
}

void nc_poll(void)
{
    uint16_t now = nc_now();
    receive(now);
    if (bye_left && since(now, next_bye) >= 0) {
        bye_left--;
        next_bye = now + BYE_GAP;
        send_ctl(T_BYE, local_result);
    }
    if (state == S_CONNECT || state == S_SETUP) {
        if (since(now, t_start) > CONNECT_TIMEOUT) {
            state = S_FAILED;
            return;
        }
        if (state == S_CONNECT && since(now, next_hello) >= 0) {
            next_hello = now + HELLO_GAP;
            send_ctl(T_HELLO, profile);
        }
        if (leader && state == S_CONNECT && since(now, next_ping) >= 0
                && (pings_sent < PINGS || (nrtts < MIN_SAMPLES && pings_sent < MAX_PINGS))) {
            next_ping = now + PING_GAP;     /* keep pinging while too few answers came back */
            ping_t[pings_sent] = now;
            ping_open[pings_sent >> 3] |= (uint8_t)(1 << (pings_sent & 7));
            send_ctl(T_PING, pings_sent);
            pings_sent++;
        }
        if (leader && state == S_CONNECT && nrtts >= MIN_SAMPLES
                && (nrtts >= PINGS || since(now, next_ping) > PING_QUIET)) {
            delay = forced_delay ? forced_delay : choose_delay();
            state = S_SETUP;
        }
        if (state == S_SETUP && since(now, next_setup) >= 0) {
            next_setup = now + SETUP_GAP;
            send_ctl(T_SETUP, delay);
        }
    } else if (state == S_READY) {
        if (!playing && since(now, t_ready) > START_TIMEOUT)
            state = S_DEAD;
        else if (playing && since(now, last_rx) > DEAD_AFTER)
            state = S_DEAD;
    }
}

uint8_t nc_status(uint8_t *d)
{
    uint8_t code;
    switch (state) {
    case S_READY: code = NC_ST_READY; break;
    case S_INCOMPATIBLE: code = NC_ST_INCOMPATIBLE; break;
    case S_FAILED: case S_DEAD: code = NC_ST_FAILED; break;
    case S_LEFT: case S_ENDED: code = NC_ST_LEFT; break;
    default: code = NC_ST_CONNECTING;
    }
    if (d)
        *d = code == NC_ST_READY ? delay : 0;
    return code;
}

uint8_t nc_xchg(const uint8_t *pkt, uint8_t len, uint8_t *rx, uint8_t *reason)
{
    nc_poll();
    if (pkt && state == S_READY && game_packet_ok(pkt, len))
        send_all(pkt, len);
    if (state == S_DEAD || state == S_FAILED)
        return NC_X_GONE;
    if (state == S_LEFT) {
        if (reason)
            *reason = bye_reason;
        return NC_X_LEFT;
    }
    if (!qcount)
        return NC_X_NOTHING;
    memcpy(rx, q[qhead], qlen[qhead]);
    qhead = (uint8_t)((qhead + 1) % RXQ);
    qcount--;
    return NC_X_PACKET;
}
