/* games_local_host: games_local.c on a PC, driven by lines on stdin, for the conformance test against the
 * Pi's Invites (Server/Python/tests/test_games_local.py).
 *
 *   in:  game ID TITLE ROLE0 ROLE1 HASHHEX | open IP:PORT,... | time SECONDS | play NICK [GAME] | accept |
 *        decline | cancel | list | msg SENDER TEXT... | flags | launch | session | resumed CODE | quit
 *   out: SEND NICK TEXT | SAY TEXT | FLAGS n | LAUNCH line|- | SESSION hex
 *
 *   gcc -std=c99 -I../src -o games_local_host games_local_host.c ../src/games_local.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "games_local.h"

static uint16_t now;
static char cands[64] = "127.0.0.1:5000";
static uint32_t seed = 12345;

void gl_send(const char *nick, const char *text) { printf("SEND %s %s\n", nick, text); }
void gl_say(const char *text) { printf("SAY %s\n", text); }
uint16_t gl_seconds(void) { return now; }
uint8_t gl_random(void) { seed = seed * 1103515245u + 12345u; return (uint8_t)(seed >> 16); }

uint16_t gl_open(char *out)
{
    const char *p = strchr(cands, ':');
    strcpy(out, cands);
    return p ? (uint16_t)atoi(p + 1) : 0;
}

int main(void)
{
    char line[256], *arg;
    uint8_t rec[GL_SESSION];
    int i;
    setvbuf(stdout, 0, _IOLBF, 0);
    while (fgets(line, sizeof line, stdin)) {
        line[strcspn(line, "\r\n")] = 0;
        arg = strchr(line, ' ');
        if (arg) *arg++ = 0; else arg = line + strlen(line);
        if (!strcmp(line, "game") && gl_ngames < GL_MAX_GAMES) {
            gl_game *g = &gl_games[gl_ngames++];
            char hash[9];
            sscanf(arg, "%8s %24s %8s %8s %8s", g->id, g->title, g->roles[0], g->roles[1], hash);
            { uint32_t h = (uint32_t)strtoul(hash, 0, 16); for (i = 0; i < 4; i++) g->hash[i] = (uint8_t)(h >> 8 * i); }
            g->lockstep = 1;
        } else if (!strcmp(line, "open")) strncpy(cands, arg, 63);
        else if (!strcmp(line, "time")) now = (uint16_t)atoi(arg);
        else if (!strcmp(line, "play")) {
            char *gid = strchr(arg, ' ');
            if (gid) *gid++ = 0; else gid = "";
            gl_play(arg, gid);
        }
        else if (!strcmp(line, "accept")) gl_accept();
        else if (!strcmp(line, "decline")) gl_decline();
        else if (!strcmp(line, "cancel")) gl_cancel();
        else if (!strcmp(line, "list")) gl_list();
        else if (!strcmp(line, "msg")) {
            char *text = strchr(arg, ' ');
            if (text) { *text++ = 0; gl_on_message(arg, text); }
        }
        else if (!strcmp(line, "flags")) printf("FLAGS %u\n", gl_flags());
        else if (!strcmp(line, "launch")) { const char *l = gl_take_launch(); printf("LAUNCH %s\n", l ? l : "-"); }
        else if (!strcmp(line, "session")) {
            gl_session(rec);
            printf("SESSION ");
            for (i = 0; i < 64; i++) printf("%02x", rec[i]);
            printf("\n");
        }
        else if (!strcmp(line, "resumed")) gl_resumed((uint8_t)atoi(arg));
        else if (!strcmp(line, "quit")) break;
        printf("OK\n");
    }
    return 0;
}
