/* games_local: MSXG1 game invitations for MCHAT /t. See games_local.h; it follows the Pi's
 * Server/Python/src/msxpi_games.py (Invites) step by step. Written small: it shares MCHAT.COM's TPA with
 * the chat (no 32-bit arithmetic, one text buffer filled by app()). */
#include <string.h>
#include "games_local.h"

#define INVITE_TTL 120
#define LAUNCH_TTL 180
#define P_IDLE 0
#define P_INVITING 1
#define P_INVITED 2
#define P_ACCEPTED 3
#define P_READY 4
#define P_LAUNCHED 5

gl_game gl_games[GL_MAX_GAMES];
uint8_t gl_ngames;

static uint8_t phase, seat, game;
static char peer[17];
static char token[9];
static uint16_t deadline;
static char mine[64];                   /* this machine's candidates */
static uint16_t lport;
static uint8_t ncand;
static uint8_t cand[3][6];              /* the opponent's: ip 4, port 2 (little endian) */
static char msg[96], *mp;

static const char *const results[] = {
    "finished", "you ended it", "the opponent ended it", "connection lost", "the machines lost sync",
    "could not connect", "different game versions: update the game", "cancelled before the start",
    "ROM missing or not the expected dump", "not possible on this machine"};

/* msg = s1 s2 ... (0 ends the list) */
static void app(const char *s)
{
    if (s)
        while ((*mp = *s++)) mp++;
}

static void say3(const char *a, const char *b, const char *c)
{
    mp = msg; app(a); app(b); app(c);
    gl_say(msg);
}

/* "MSXG1 VERB a b c" to the peer, or to whom */
static void send_to(const char *whom, const char *verb, const char *a, const char *b, const char *c)
{
    mp = msg; app("MSXG1 "); app(verb);
    if (a) { app(" "); app(a); }
    if (b) { app(" "); app(b); }
    if (c) { app(" "); app(c); }
    gl_send(whom, msg);
}

#define send4(verb, a, b, c) send_to(peer, verb, a, b, c)

static char hexd(uint8_t v) { v &= 15; return (char)(v < 10 ? '0' + v : 'a' - 10 + v); }

/* the hash, a 32-bit little-endian number, as 8 hex digits (most significant first) */
static void hex8(char *out, const uint8_t *b)
{
    uint8_t i;
    for (i = 0; i < 4; i++) {
        out[2 * i] = hexd(b[3 - i] >> 4);
        out[2 * i + 1] = hexd(b[3 - i]);
    }
    out[8] = 0;
}

static uint8_t hexval(char c) { return (uint8_t)(c <= '9' ? c - '0' : c - 'a' + 10); }

static uint8_t is_hex8(const char *s)
{
    uint8_t i;
    for (i = 0; i < 8; i++)
        if (!((s[i] >= '0' && s[i] <= '9') || (s[i] >= 'a' && s[i] <= 'f')))
            return 0;
    return s[8] == 0;
}

static uint8_t fold(char c) { return (uint8_t)(c >= 'A' && c <= 'Z' ? c + 32 : c); }

static uint8_t same_nick(const char *a, const char *b)
{
    while (*a && fold(*a) == fold(*b)) { a++; b++; }
    return fold(*a) == fold(*b);
}

static void set_peer(const char *nick)
{
    strncpy(peer, nick, 16); peer[16] = 0;
}

static void clear(void)
{
    phase = P_IDLE;
    peer[0] = token[0] = 0;
    seat = 0;
    ncand = 0;
}

void gl_init(void)
{
    clear();
    gl_ngames = 0;
    deadline = 0;
    lport = 0;
    mine[0] = 0;
}

uint8_t gl_busy(void) { return phase != P_IDLE; }

static void abort_game(uint8_t notify)
{
    if (notify && peer[0])
        send4("CANCEL", token, 0, 0);
    clear();
}

static void expire(void)
{
    uint8_t was = phase;
    if (phase == P_IDLE || phase == P_LAUNCHED || (int16_t)(gl_seconds() - deadline) <= 0)
        return;
    abort_game(0);
    gl_say(was != P_READY ? "Game invitation expired" : "The game was not started in time");
}

static void set_deadline(uint8_t ttl) { deadline = gl_seconds() + ttl; }

static int8_t find_game(const char *id)
{
    uint8_t i;
    for (i = 0; i < gl_ngames; i++)
        if (!strcmp(gl_games[i].id, id))
            return (int8_t)i;
    return -1;
}

void gl_list(void)
{
    uint8_t i;
    if (!gl_ngames) {
        gl_say("No games installed (no GAME.GPF in the current directory)");
        return;
    }
    mp = msg; app("Games:");
    for (i = 0; i < gl_ngames && mp - msg < (int)sizeof msg - 40; i++) {
        app(i ? ", " : " ");
        app(gl_games[i].id);
        app(" (");
        app(gl_games[i].title);
        app(")");
    }
    gl_say(msg);
}

static uint8_t no(uint8_t want, const char *text)
{
    expire();
    if (phase == want)
        return 0;
    gl_say(text);
    return 1;
}

void gl_play(const char *nick, const char *game_id)
{
    int8_t g;
    uint8_t i, r[4];
    char hash[9];
    if (no(P_IDLE, "! Already in a game or invitation: /cancel first")) return;
    if (!gl_ngames) { gl_list(); return; }
    if (!*nick) { gl_say("! Use /play NICK [GAME]"); return; }
    g = find_game(*game_id ? game_id : "soccer");
    if (g < 0 && !*game_id)
        g = 0;
    if (g < 0) { gl_say("! Unknown game"); gl_list(); return; }
    game = (uint8_t)g;
    seat = 0;
    set_peer(nick);
    for (i = 0; i < 4; i++) r[i] = gl_random();
    hex8(token, r);
    phase = P_INVITING;
    set_deadline(INVITE_TTL);
    say3("Invited ", peer, 0);
    hex8(hash, gl_games[game].hash);
    send4("INVITE", gl_games[game].id, hash, token);
}

static uint8_t open_port(void)
{
    lport = gl_open(mine);
    if (lport) return 1;
    abort_game(1);
    gl_say("Game failed: cannot open the game port");
    return 0;
}

void gl_accept(void)
{
    if (no(P_INVITED, "! No invitation to accept") || !open_port()) return;
    phase = P_ACCEPTED;
    set_deadline(INVITE_TTL);
    say3("Accepted; connecting to ", peer, "...");
    send4("ACCEPT", token, mine, 0);
}

void gl_decline(void)
{
    if (no(P_INVITED, "! No invitation to decline")) return;
    send4("DECLINE", token, "declined", 0);
    clear();
    gl_say("Invitation declined");
}

void gl_cancel(void)
{
    if (phase == P_IDLE) { gl_say("! Nothing to cancel"); return; }
    abort_game(1);
    gl_say("Game cancelled");
}

/* "a.b.c.d:port,..." -> cand[]; the number found */
static uint8_t parse_candidates(const char *s)
{
    uint16_t v;
    uint8_t part, n = 0, ok;
    while (*s && n < 3) {
        ok = 1;
        for (part = 0; part < 5; part++) {
            if (*s < '0' || *s > '9') { ok = 0; break; }
            v = 0;
            while (*s >= '0' && *s <= '9') v = v * 10 + (uint16_t)(*s++ - '0');
            if (part < 4) {
                if (v > 255 || *s != (part < 3 ? '.' : ':')) { ok = 0; break; }
                cand[n][part] = (uint8_t)v;
                s++;
            } else {
                if (!v || (*s && *s != ',')) { ok = 0; break; }
                cand[n][4] = (uint8_t)v; cand[n][5] = (uint8_t)(v >> 8);
            }
        }
        n += ok;
        while (*s && *s != ',') s++;
        if (*s == ',') s++;
    }
    return n;
}

static void ready_with(const char *candidates)
{
    ncand = parse_candidates(candidates);
    if (!ncand) {
        abort_game(1);
        gl_say("Game failed: The other side sent no address");
        return;
    }
    phase = P_READY;
    set_deadline(LAUNCH_TTL);
    say3(peer, " is ready: the game starts when this program returns to MSX-DOS", 0);
}

static void on_invite(const char *sender, const char *gid, const char *hash, const char *tok)
{
    char h[9];
    const char *why = 0, *said = 0;
    int8_t g = find_game(gid);
    if (!is_hex8(tok)) return;
    if (phase != P_IDLE)
        why = "busy";
    else if (g < 0) {
        why = "unknown-game";
        said = " invited you to a game that is not installed here: ";
    } else {
        hex8(h, gl_games[g].hash);
        if (!is_hex8(hash) || strcmp(hash, h)) {
            why = "profile";
            said = " invited you, but your versions of the game differ: one of you must update it";
            gid = 0;
        }
    }
    if (why) {                                          /* the answer goes to the sender */
        send_to(sender, "DECLINE", tok, why, 0);
        if (said) say3(sender, said, gid);
        return;
    }
    set_peer(sender);
    game = (uint8_t)g;
    strcpy(token, tok);
    seat = 1;
    phase = P_INVITED;
    set_deadline(INVITE_TTL);
    say3(sender, " invites you to play ", gl_games[game].title);
    gl_say("/accept or /decline");
}

static const char *reason_text(const char *reason)
{
    if (!strcmp(reason, "busy")) return " is busy";
    if (!strcmp(reason, "unknown-game")) return " does not have that game";
    if (!strcmp(reason, "profile")) return " has a different version of the game: one of you must update it";
    if (!strcmp(reason, "no-mapper")) return " cannot play it (TCP/IP needs a memory mapper)";
    return " declined the game";
}

uint8_t gl_on_message(const char *sender, const char *text)
{
    static char buf[96];
    char *f[5], *p;
    const char *why = 0;
    uint8_t n = 0;
    if (strncmp(text, "MSXG1 ", 6))
        return 0;
    expire();
    strncpy(buf, text, sizeof buf - 1);
    buf[sizeof buf - 1] = 0;
    for (p = buf; n < 5 && *p; ) {
        f[n++] = p;
        while (*p && *p != ' ') p++;
        if (*p) *p++ = 0;
    }
    if (n < 2) return 1;
    if (!strcmp(f[1], "INVITE")) {
        if (n >= 5) on_invite(sender, f[2], f[3], f[4]);
        return 1;
    }
    if (n < 3 || phase == P_IDLE || !same_nick(sender, peer) || strcmp(f[2], token))
        return 1;                                       /* not about our game */
    if (!strcmp(f[1], "ACCEPT") && n >= 4 && phase == P_INVITING) {
        if (!open_port()) return 1;
        send4("GO", token, mine, 0);
        ready_with(f[3]);
    } else if (!strcmp(f[1], "GO") && n >= 4 && phase == P_ACCEPTED)
        ready_with(f[3]);
    else if (!strcmp(f[1], "DECLINE"))
        why = reason_text(n > 3 ? f[3] : "declined");
    else if (!strcmp(f[1], "CANCEL"))
        why = " cancelled the game";
    if (why) {
        say3(peer, why, 0);
        clear();
    }
    return 1;
}

uint8_t gl_flags(void)
{
    expire();
    return phase == P_READY ? GL_FLAG_LAUNCH : phase == P_INVITED ? GL_FLAG_INVITED : 0;
}

const char *gl_take_launch(void)
{
    expire();
    if (phase != P_READY)
        return 0;
    phase = P_LAUNCHED;
    return "PLAYNET /T";
}

void gl_session(uint8_t *rec)
{
    uint8_t i;
    char c;
    const gl_game *g = &gl_games[game];
    memset(rec, 0, GL_SESSION);
    if (phase != P_LAUNCHED)
        return;
    memcpy(rec, "PNS1", 4);
    for (i = 0; i < 4; i++)
        rec[4 + i] = (uint8_t)(hexval(token[2 * i]) << 4 | hexval(token[2 * i + 1]));
    rec[8] = seat;
    rec[9] = 1;                                         /* link: TCP/IP UNAPI */
    rec[10] = (uint8_t)lport; rec[11] = (uint8_t)(lport >> 8);
    memcpy(rec + 12, g->hash, 4);
    memset(rec + 16, ' ', 8);
    for (i = 0; i < 8 && (c = g->id[i]); i++)
        rec[16 + i] = (uint8_t)(c >= 'a' && c <= 'z' ? c - 32 : c);
    for (i = 0; i < 8 && peer[i]; i++)
        rec[24 + i] = (uint8_t)peer[i];
    rec[40] = ncand;
    memcpy(rec + 41, cand, sizeof cand);
}

void gl_resumed(uint8_t result)
{
    if (phase != P_LAUNCHED)
        return;
    mp = msg;
    app("Game with "); app(peer); app(" ended (");
    app(result < sizeof results / sizeof results[0] ? results[result] : "finished");
    app(")");
    clear();
    gl_say(msg);
}

void gl_restore(const char *peer_nick)
{
    clear();
    set_peer(peer_nick);
    phase = P_LAUNCHED;
}

uint8_t gl_launched(void) { return phase == P_LAUNCHED; }
