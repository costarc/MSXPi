/* games_local: MSXG1 game invitations (documents/PLAYNET-PROTOCOLS.md 12) for MCHAT /t, the C twin of the
 * Pi's msxpi_games.Invites. Portable C: MCHAT.COM (SDCC) includes it, and a gcc build plays it against
 * Invites in Server/Python/tests/test_games_local.py.
 *
 * One invitation or game at a time. The host provides the functions below and fills gl_games from the
 * GPF headers it finds (PLAYNET-PROTOCOLS.md 8: the 128-byte header). Times are in seconds.
 */
#ifndef GAMES_LOCAL_H
#define GAMES_LOCAL_H

#include <stdint.h>

#define GL_MAX_GAMES 6
#define GL_SESSION 256

typedef struct {
    char id[9];             /* lower case, as typed in /play */
    char title[25];
    char roles[2][9];       /* seat 0 (the inviter), seat 1 */
    uint8_t lockstep;       /* 1: PLAYNET runs it; 0: its own program (not supported over TCP/IP) */
    uint8_t hash[4];        /* the profile hash, little endian (GPF header bytes 8-11) */
} gl_game;

extern gl_game gl_games[GL_MAX_GAMES];
extern uint8_t gl_ngames;

/* ---- provided by the host -------------------------------------------------------------- */
void gl_send(const char *nick, const char *text);      /* a private message (PRIVMSG nick :text) */
void gl_say(const char *text);                         /* a line in the chat */
uint16_t gl_seconds(void);
uint8_t gl_random(void);                               /* a random byte */
/* open this machine's game port; write its candidates ("a.b.c.d:port,...", LAN first) to out (64 bytes);
   return the local port, 0 on failure */
uint16_t gl_open(char *out);

/* ---- start-up ---------------------------------------------------------------------------- */
/* Before anything else: MCHAT.COM's start-up zeroes no globals (they come in as FFh from the .COM). */
void gl_init(void);

/* ---- what the user types --------------------------------------------------------------- */
void gl_list(void);
void gl_play(const char *nick, const char *game_id);  /* game_id may be "" */
void gl_accept(void);
void gl_decline(void);
void gl_cancel(void);

/* ---- what arrives ------------------------------------------------------------------------ */
uint8_t gl_on_message(const char *sender, const char *text);   /* 1: it was "MSXG1 ...", never shown */

/* ---- the hand-over to PLAYNET ------------------------------------------------------------- */
#define GL_FLAG_LAUNCH 1
#define GL_FLAG_INVITED 2
uint8_t gl_flags(void);
const char *gl_take_launch(void);       /* the command line ("PLAYNET /T"), once; 0 when no game is ready */
void gl_session(uint8_t *rec);          /* the session record (13.1), 256 bytes; the host adds its IRC fields */
void gl_resumed(uint8_t result);        /* back in the chat after the game: say how it ended (13.2) */
void gl_restore(const char *peer_nick); /* a new MCHAT after the game: the game it launched (PLAYNET.SES) */
uint8_t gl_launched(void);              /* 1 between the launch and gl_resumed: keep the IRC connection */
uint8_t gl_busy(void);

#endif
