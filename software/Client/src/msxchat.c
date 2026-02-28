#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>    /* for vsprintf used in fallback */
#include <stdarg.h>   /* for va_list */
#include <time.h>     /* for time(), may be absent on some SDCC targets */
#include "../../../../../MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../C-common/header/msxpi.h"

/* Map lightweight helpers to Fusion-C optimized routines where available.
   Fusion-C provides: StrCopy, NStrCopy, StrConcat, NStrConcat,
                      StrLen, StrCompare, NStrCompare, StrChr
   We map existing msx_* call sites to those names so the rest of the file
   remains unchanged.
*/
#define msx_strlen    StrLen
#define msx_strcmp    StrCompare
#define msx_strncpy(dest, src, n) NStrCopy(dest, src, n)
#define msx_strchr    StrChr
#define msx_memcpy    MemCopy         

/* simple reentrant strtok replacement (kept local — Fusion-C doesn't provide strtok) */
static char* msx_strtok_r(char *s, const char *delim, char **saveptr)
{
    char *start;
    const char *d;

    if (s)
        start = s;
    else if (saveptr && *saveptr)
        start = *saveptr;
    else
        return NULL;

    /* Skip leading delimiters */
    while (*start) {
        bool isdel = false;
        d = delim;
        while (*d) {
            if (*start == *d) { isdel = true; break; }
            ++d;
        }
        if (!isdel) break;
        ++start;
    }
    if (*start == '\0') {
        if (saveptr) *saveptr = NULL;
        return NULL;
    }

    /* Find end of token */
    char *tokend = start;
    bool isdel;
    while (*tokend) {
        isdel = false;
        d = delim;
        while (*d) {
            if (*tokend == *d) { isdel = true; break; }
            ++d;
        }
        if (isdel) break;
        ++tokend;
    }

    if (*tokend) {
        *tokend = '\0';
        if (saveptr) *saveptr = tokend + 1;
    } else {
        if (saveptr) *saveptr = NULL;
    }
    return start;
}

/* Simple ASCII → unsigned 32-bit integer parser (no libc atoi) */
static uint32_t str_to_u32(const char *s)
{
    uint32_t v = 0;
    if (!s) return 0;
    while (*s) {
        char c = *s++;
        if (c < '0' || c > '9') break;
        v = v * 10u + (uint32_t)(c - '0');
    }
    return v;
}

/* Provide a small snprintf fallback for toolchains (SDCC/Fusion-C) that lack it.
   It formats into a temporary buffer then copies/truncates into destination.
   Not ideal for very large strings, but safe and prevents implicit declaration.
*/
static int msx_snprintf(char *str, size_t size, const char *fmt, ...)
{
    va_list ap;
    char tmp[512];
    int n;

    va_start(ap, fmt);
    n = vsprintf(tmp, fmt, ap); /* vsprintf usually available; tmp guards overflow */
    va_end(ap);

    if (n < 0) {
        if (size) str[0] = '\0';
        return n;
    }

    if (size > 0) {
        size_t copy = (n < (int)(size - 1)) ? (size_t)n : (size_t)(size - 1);
        if (copy) msx_memcpy(str, tmp, copy);
        str[copy] = '\0';
    }

    return n;
}

/* Map snprintf to our fallback when the platform doesn't provide it */
#ifndef HAVE_SNPRINTF
#define snprintf msx_snprintf
#endif

/*
  Full MSX-side IRC client (text UI).

  - Connects by default to chat.freenode.net:6667 and joins #msxpi
  - UI: top channels row, left users column, main message area, bottom commands row
  - Polls server every REFRESH_SEC for unread messages, user list and channels
  - Uses SendCommandToMSXPi("<irc_cmd...>", false) to send commands to Python server
  - Receives server response using PerformHandshake/RECVDATA_ONEBLOCK into heap buffer,
    then parses the string responses (they are newline-separated)
*/

/* Configurable defaults */
#define DEFAULT_SERVER    "chat.freenode.net"
#define DEFAULT_PORT      6697
#define DEFAULT_CHANNEL   "#openmsx"
#define REFRESH_COUNTER   10000       /* seconds between automatic refreshes (can be changed) */

/* UI geometry (text-mode) */
#define SCREEN_COLS       79
#define SCREEN_ROWS       22
#define USERS_COL_WIDTH   16     /* left column width for user list */
#define TOP_ROWS          1
#define BOTTOM_ROWS       3
#define MSG_COL_START     (USERS_COL_WIDTH + 2)
#define MSG_COL_WIDTH     (SCREEN_COLS - MSG_COL_START - 1)
#define MSG_ROWS          (SCREEN_ROWS - TOP_ROWS - BOTTOM_ROWS - 2) /* keep 1 line padding */

/* Limits */
#define MAX_CHANNELS      8
#define MAX_USERS         64
#define MAX_USERLEN       (USERS_COL_WIDTH - 1)
#define MAX_MESSAGES      128
#define MAX_MSG_LEN       128     /* truncated if longer */
#define RECV_BUF_OFFSET   100     /* offset from heap buffer to avoid collisions */

/* Simple in-memory structures */
static char channels[MAX_CHANNELS][16];
static uint8_t channels_count = 0;
static int current_channel_idx = 0;

static char users[MAX_USERS][MAX_USERLEN + 1];
static uint8_t users_count = 0;

typedef struct {
    char channel[16];
    char nick[16];
    char text[MAX_MSG_LEN];
    uint32_t ts;
} ChatMsg;

static ChatMsg messages[MAX_MESSAGES];
static uint16_t messages_head = 0; /* index of oldest message */
static uint16_t messages_count = 0;

/* Commands shown in bottom row */
static const char* commands[] = {
    "Send",
    "Join",
    "Part",
    "PrivMsg",
    "ListCh",
    "Exit"
};
static const int n_commands = sizeof(commands) / sizeof(commands[0]);
static int cmd_selected = 0;

/* Helpers to push message into circular buffer */
static void push_message(const char* chan, const char* nick, const char* text, uint32_t ts)
{
    uint16_t idx;
    if (messages_count < MAX_MESSAGES) {
        idx = (messages_head + messages_count) % MAX_MESSAGES;
        messages_count++;
    } else {
        idx = messages_head;
        messages_head = (messages_head + 1) % MAX_MESSAGES;
    }
    msx_strncpy(messages[idx].channel, chan, sizeof(messages[idx].channel));
    msx_strncpy(messages[idx].nick, nick, sizeof(messages[idx].nick));
    msx_strncpy(messages[idx].text, text, sizeof(messages[idx].text));
    messages[idx].ts = ts;
}

/* Portable helper for timestamps:
   - If time() is present, use it.
   - Otherwise return 0 (or implement a tick counter here).
*/
static uint32_t now_seconds(void)
{
#if defined(__SDCC) || defined(NO_TIME)
    return 0;
#else
    return (uint32_t)time(NULL);
#endif
}

/* Clear users list */
static void clear_users(void)
{
    users_count = 0;
    for (int i = 0; i < MAX_USERS; ++i) users[i][0] = '\0';
}

/* Add channel if not present */
static void ensure_channel(const char* ch)
{
    if (!ch || ch[0] == '\0') return;
    for (int i = 0; i < channels_count; ++i) {
        if (msx_strcmp(channels[i], ch) == 0) return;
    }
    if (channels_count < MAX_CHANNELS) {
        msx_strncpy(channels[channels_count++], ch, sizeof(channels[0]));
    }
}

/* Parse server returned serialized messages:
   expected format per line: "<ts>|<channel>|<nick>|<text>"
*/
static void parse_and_store_messages(const char* payload)
{
    if (!payload) return;
    const char* p = payload;
    char line[256];
    while (*p) {
        /* read a line */
        int li = 0;
        while (*p && *p != '\n' && li < (int)sizeof(line)-1) {
            line[li++] = *p++;
        }
        if (*p == '\n') p++;
        line[li] = '\0';
        if (li == 0) continue;

        /* tokenize */
        char *s_ts = NULL, *s_chan = NULL, *s_nick = NULL, *s_text = NULL;
        char temp[256];
        msx_strncpy(temp, line, sizeof(temp));

        s_ts = temp;
        char* t = (char*)msx_strchr(s_ts, '|'); if (!t) continue; *t++ = '\0';
        s_chan = t;
        t = (char*)msx_strchr(s_chan, '|'); if (!t) continue; *t++ = '\0';
        s_nick = t;
        t = (char*)msx_strchr(s_nick, '|'); if (!t) continue; *t++ = '\0';
        s_text = t;

        uint32_t ts = str_to_u32(s_ts);
        ensure_channel(s_chan);
        push_message(s_chan, s_nick, s_text, ts);
    }
}

/* Receive arbitrary response from Python server into MSX heap buffer and return pointer.
   Returns pointer to NUL-terminated buffer (inside heap) or NULL on error.
   Uses BLKSIZE as msx_blocksize for handshake.
*/
static char* recv_server_response(void)
{
    uint8_t rc;
    uint16_t block_size;
    uint8_t* buf = (uint8_t*)(get_buffer_ptr() + RECV_BUF_OFFSET);
    uint16_t offset = 0;
    uint16_t msx_blocksize = BLKSIZE;

    rc = PerformHandshake(msx_blocksize);
    if (rc != RC_SUCCESS) {
        return NULL;
    }

    while (1) {
        rc = RECVDATA_ONEBLOCK(buf + offset, &block_size, msx_blocksize);
        if (block_size == 0) {
            /* ensure empty string */
            buf[offset] = '\0';
        } else {
            uint16_t pos = offset + (block_size < (MAXBUFSIZE - RECV_BUF_OFFSET - offset) ? block_size : (MAXBUFSIZE - RECV_BUF_OFFSET - offset - 1));
            buf[pos] = '\0';
        }

        if (rc == RC_SUCCESS || rc == RC_READY) {
            /* Advance offset to received bytes */
            offset += (block_size < (MAXBUFSIZE - RECV_BUF_OFFSET - offset) ? block_size : (MAXBUFSIZE - RECV_BUF_OFFSET - offset - 1));
        }

        if (rc != RC_READY) break;
        /* loop to receive next block if any */
    }

    /* Ensure NUL termination */
    buf[offset] = '\0';
    return (char*)buf;
}

/* Send command to Python server and receive response string (or NULL on error) */
static char* send_command_and_get_response(const char* cmd)
{
    uint8_t rc;
    if (!cmd) return NULL;

    /* Debug: show the command being sent in bottom row so you can verify it */
    Locate(2, SCREEN_ROWS - 1);
    /* Send primary command (do not append DOS tail) */
    rc = SendCommandToMSXPi(cmd, false);
    if (rc != RC_SUCCESS && rc != RC_FAILED) {
        /* error handshake: provide immediate UI feedback */
        Locate(2, SCREEN_ROWS - 1);
        Print("Error: failed to send command to server");
        return NULL;
    }

    /* Receive server response into heap buffer */
    char* resp = recv_server_response();
    if (!resp) {
        /* show short debug in UI */
        Locate(2, SCREEN_ROWS - 1);
        Print("No response from server");
        return NULL;
    }

    /* If server returned an error prefix, show it briefly in the bottom area */
    if (resp[0] == 'e' && resp[1] == 'r' && resp[2] == 'r') {
        Locate(2, SCREEN_ROWS - 1);
        /* resp might be longer than line; truncate to fit */
        char tmp[80];
        msx_strncpy(tmp, resp, sizeof(tmp));
        Print(tmp);
    }

    return resp;
}

/* UI drawing primitives (text-mode borders) */
static void draw_borders(void)
{
    int i, r, c;

    Cls();

    /* Top border: columns 1..SCREEN_COLS */
    Locate(1, 1);
    Print("+");
    for (i = 0; i < SCREEN_COLS - 2; ++i) Print("-");
    Print("+");

    /* Channels row immediately below title (interior reserved) */
    Locate(1, 2);
    Print("| Channels: ");
    /* fill interior up to column SCREEN_COLS-1 */
    {
        int interior = SCREEN_COLS - 2 - (int)msx_strlen(" Channels: ");
        for (i = 0; i < interior; ++i) Print(" ");
    }
    Print("|");

    /* horizontal separator */
    Locate(1, 3);
    Print("+");
    for (i = 0; i < SCREEN_COLS - 2; ++i) Print("-");
    Print("+");

    /* left users column border and vertical separators for message area */
    for (r = 4; r <= SCREEN_ROWS - BOTTOM_ROWS - 1; ++r) {
        Locate(1, r);
        Print("|");
        /* users column: USERS_COL_WIDTH chars (inside area) */
        for (c = 0; c < USERS_COL_WIDTH; ++c) Print(" ");
        Print("|");
        /* message column: MSG_COL_WIDTH chars (inside area) */
        for (c = 0; c < MSG_COL_WIDTH; ++c) Print(" ");
        /* right border */
        Print("|");
    }

    /* bottom separator (one row above commands area) */
    int bottom_start = SCREEN_ROWS - BOTTOM_ROWS + 1;
    Locate(1, bottom_start - 1);
    Print("+");
    for (i = 0; i < SCREEN_COLS - 2; ++i) Print("-");
    Print("+");

    /* commands area box: keep exactly SCREEN_COLS-2 interior columns */
    for (r = bottom_start; r <= SCREEN_ROWS; ++r) {
        Locate(1, r);
        Print("|");
        for (c = 0; c < SCREEN_COLS - 2; ++c) Print(" ");
        Print("|");
    }
}

/* Draw top title and channels */
static void draw_top_and_channels(void)
{
    int i, used = 0;
    char tmp[32];

    /* Title */
    Locate(3, 1);
    Print("MSXPI Chat");

    /* Channels list on second row */
    const int startCol = 13;
    Locate(startCol, 2);

    int avail = SCREEN_COLS - startCol; /* columns from startCol .. SCREEN_COLS-1 */

    for (i = 0; i < (int)channels_count && used < avail; ++i) {
        if (i == current_channel_idx) {
            /* token = [name] */
            int name_len = (int)msx_strlen(channels[i]);
            int need = 3 + name_len; /* '[' name ']' and trailing space counted as +1 */
            if (need > avail - used) {
                int space_for_name = avail - used - 3;
                if (space_for_name < 1) break;
                msx_strncpy(tmp, channels[i], (size_t)space_for_name + 1);
                tmp[space_for_name] = '\0';
                Print("["); Print(tmp); Print("] ");
                used += 3 + space_for_name;
                break;
            } else {
                Print("["); Print(channels[i]); Print("] ");
                used += need;
            }
        } else {
            int name_len = (int)msx_strlen(channels[i]);
            int need = 2 + name_len; /* space + name + space */
            if (need > avail - used) {
                int space_for_name = avail - used - 2;
                if (space_for_name < 1) break;
                msx_strncpy(tmp, channels[i], (size_t)space_for_name + 1);
                tmp[space_for_name] = '\0';
                Print(" "); Print(tmp); Print(" ");
                used += 2 + space_for_name;
                break;
            } else {
                Print(" "); Print(channels[i]); Print(" ");
                used += need;
            }
        }
    }

    /* pad remaining interior columns (do not touch right border column) */
    while (used < avail) { Print(" "); used++; }
}

/* Draw users in left column */
static void draw_users(void)
{
    int start_row = 4;
    int i, k;

    for (i = 0; i < (int)users_count && i < MSG_ROWS; ++i) {
        Locate(2, start_row + i);
        /* clear line portion */
        for (k = 0; k < USERS_COL_WIDTH - 1; ++k) Print(" ");
        Locate(2, start_row + i);
        Print(users[i]);
    }
}

/* Draw messages in main area (only messages for current channel) */
static void draw_messages(void)
{
    int start_row = 4;
    const char* curchan = channels_count ? channels[current_channel_idx] : DEFAULT_CHANNEL;
    int shown = 0;
    int to_show = MSG_ROWS;
    int i, k;

    for (i = 0; i < (int)messages_count && shown < to_show; ++i) {
        int idx = (messages_head + messages_count - 1 - i) % MAX_MESSAGES;
        if (msx_strcmp(messages[idx].channel, curchan) == 0) {
            int disp_row = start_row + (to_show - 1 - shown);

            /* truncate nick to fit */
            int nick_len = (int)msx_strlen(messages[idx].nick);
            int max_nick = MSG_COL_WIDTH - 3; /* at least 1 char text and ": " */
            char nickbuf[32];
            if (nick_len > max_nick) {
                msx_strncpy(nickbuf, messages[idx].nick, (size_t)max_nick + 1);
                nickbuf[max_nick] = '\0';
                nick_len = max_nick;
            } else {
                msx_strncpy(nickbuf, messages[idx].nick, sizeof(nickbuf));
            }

            /* allowed text width inside interior (do not overwrite right border) */
            int allowed = MSG_COL_WIDTH - nick_len - 2;
            if (allowed < 1) allowed = 1;

            char textbuf[MAX_MSG_LEN];
            msx_strncpy(textbuf, messages[idx].text, (size_t)allowed + 1);
            textbuf[allowed] = '\0';

            /* clear line interior and print */
            Locate(MSG_COL_START, disp_row);
            for (k = 0; k < MSG_COL_WIDTH; ++k) Print(" ");
            Locate(MSG_COL_START, disp_row);
            Print(nickbuf); Print(": "); Print(textbuf);

            shown++;
        }
    }

    /* clear remaining interior lines */
    for (i = shown; i < to_show; ++i) {
        int disp_row = start_row + (to_show - 1 - i);
        Locate(MSG_COL_START, disp_row);
        for (k = 0; k < MSG_COL_WIDTH; ++k) Print(" ");
    }
}

/* Draw bottom commands and show selected */
static void draw_commands(void)
{
    int y = SCREEN_ROWS - BOTTOM_ROWS + 2;
    Locate(2, y);
    {
        int i;
        for (i = 0; i < n_commands; ++i) {
            if (i == cmd_selected) {
                Print("[");
                Print(commands[i]);
                Print("] ");
            } else {
                Print(" ");
                Print(commands[i]);
                Print("  ");
            }
        }
    }
}

/* Utility: prompt input string in bottom area. Returns true if OK (Enter), false if cancelled (Esc). */
static bool prompt_input(const char* prompt, char* outbuf, int maxlen)
{
    int y = SCREEN_ROWS - 1;
    int i;
    Locate(2, y);
    /* clear input area */
    for (i = 0; i < SCREEN_COLS - 4; ++i) Print(" ");
    Locate(2, y);
    Print(prompt);
    Print(": ");

    int pos = 0;
    outbuf[0] = '\0';
    while (1) {
        uint8_t k = Inkey();
        if (k == 0) {
            /* no key */
            continue;
        }
        if (k == 0x0D) { /* Enter */
            outbuf[pos] = '\0';
            return true;
        }
        if (k == 0x1B) { /* ESC */
            return false;
        }
        if (k == 0x08 || k == 0x7F) { /* Backspace */
            if (pos > 0) {
                pos--;
                outbuf[pos] = '\0';
                /* reprint */
                Locate(2 + (int)msx_strlen(prompt) + 2, y);
                for (i = 0; i < maxlen; ++i) Print(" ");
                Locate(2 + (int)msx_strlen(prompt) + 2, y);
                Print(outbuf);
            }
            continue;
        }
        /* printable ASCII only */
        if (k >= 32 && k <= 126 && pos < maxlen - 1) {
            outbuf[pos++] = (char)k;
            outbuf[pos] = '\0';
            PrintChar(k);
        }
    }
}

/* Request an updated user list for current channel from server and populate users[] */
static void refresh_users_for_channel(const char* ch)
{
    /* Defensive: ensure channel pointer is valid and contains a sensible printable name.
       On some startup paths channels[...] may be uninitialized (garbage/0xFF) and
       we must avoid sending that to the Python server. */
    clear_users();
    if (!ch) return;
    if (ch[0] == '\0') return;
    /* Reject obviously invalid strings (non-printable first char) */
    if ((unsigned char)ch[0] < 32 || (unsigned char)ch[0] > 126) return;

    char cmd[64];
    snprintf(cmd, sizeof(cmd), "irc_list_users %s", ch);
    char* resp = send_command_and_get_response(cmd);
    if (!resp) return;
    /* resp is "ok:..." or usage */
    if (msx_strcmp(resp, "ok:") >= 0 || (resp[0] == 'o' && resp[1] == 'k' && resp[2] == ':')) {
        if (msx_strcmp(resp, "ok:") == 0 && resp[3] == '\0') return;
        const char* p = resp + 3;
        /* split by spaces into user names */
        char tmp[256];
        msx_strncpy(tmp, p, sizeof(tmp));
        char *save = NULL;
        char *tok = msx_strtok_r(tmp, " ", &save);
        while (tok && users_count < MAX_USERS) {
            msx_strncpy(users[users_count], tok, (size_t)MAX_USERLEN + 1);
            users[users_count][MAX_USERLEN] = '\0';
            users_count++;
            tok = msx_strtok_r(NULL, " ", &save);
        }
    }
}

/* Request unread messages (for current channel or all) and store them */
static void refresh_messages_for_channel(const char* ch)
{
    /* Use a local sanitized channel name to avoid sending garbage bytes
       (uninitialized buffers or non-printable content) to the Python server. */
    char safe_chan[32];
    const char* usechan = ch;

    if (!ch || ch[0] == '\0' || (unsigned char)ch[0] < 32 || (unsigned char)ch[0] > 126) {
        /* fallback to default channel if incoming pointer is invalid */
        msx_strncpy(safe_chan, DEFAULT_CHANNEL, sizeof(safe_chan));
        safe_chan[sizeof(safe_chan) - 1] = '\0';
        usechan = safe_chan;
    } else {
        /* copy and NUL-terminate to ensure safety */
        msx_strncpy(safe_chan, ch, sizeof(safe_chan));
        safe_chan[sizeof(safe_chan) - 1] = '\0';
        usechan = safe_chan;
    }

    /* Small sanity: require printable first char (helps filter garbage) */
    if ((unsigned char)usechan[0] < 33 || (unsigned char)usechan[0] > 126) return;

    char cmd[64];
    snprintf(cmd, sizeof(cmd), "irc_read_unread %s", usechan);

    char* resp = send_command_and_get_response(cmd);
    if (!resp) return;

    /* resp format: either "ok:0" or "ok:<lines...>" */
    if (resp[0] == 'o' && resp[1] == 'k' && resp[2] == ':') {
        const char* payload = resp + 3;
        if (payload[0] == '0' && payload[1] == '\0') {
            return;
        }
        /* parse payload lines and store */
        parse_and_store_messages(payload);
    }
}

/* Request channel list from client */
static void refresh_channels(void)
{
    char* resp = send_command_and_get_response("irc_list_channels");
    if (!resp) return;
    if (resp[0] == 'o' && resp[1] == 'k' && resp[2] == ':') {
        const char* p = resp + 3;
        channels_count = 0;
        char tmp[128];
        msx_strncpy(tmp, p, sizeof(tmp));
        char *save = NULL;
        char* tok = msx_strtok_r(tmp, " ", &save);
        while (tok && channels_count < MAX_CHANNELS) {
            msx_strncpy(channels[channels_count], tok, sizeof(channels[0]));
            channels_count++;
            tok = msx_strtok_r(NULL, " ", &save);
        }
        if (channels_count == 0) {
            /* ensure default channel present */
            msx_strncpy(channels[0], DEFAULT_CHANNEL, sizeof(channels[0]));
            channels_count = 1;
        }
        if (current_channel_idx >= channels_count) current_channel_idx = 0;
    }
}

/* Connect to default server and join default channel */
static void auto_connect_and_join(void)
{
    char cmd[128];
    char nick[32];

    msx_strncpy(nick, "msxpi", sizeof(nick));

    /* Connect */
    /* include 'ssl' token so the Python side opens a TLS socket */
    snprintf(cmd, sizeof(cmd), "irc_connect %s %d %s ssl", DEFAULT_SERVER, DEFAULT_PORT, nick);
    char* resp = send_command_and_get_response(cmd);
    if (!resp || strncmp(resp, "ok:", 3) != 0) {
        Locate(2, SCREEN_ROWS - 1);
        if (resp) { Print(resp); } else { Print("irc_connect failed"); }
        return;
    }

    /* Join default channel */
    snprintf(cmd, sizeof(cmd), "irc_join %s", DEFAULT_CHANNEL);
    resp = send_command_and_get_response(cmd);
    if (!resp || strncmp(resp, "ok:", 3) != 0) {
        Locate(2, SCREEN_ROWS - 1);
        if (resp) { Print(resp); } else { Print("irc_join failed"); }
        return;
    }

    /* Ensure local channels cache */
    ensure_channel(DEFAULT_CHANNEL);
}

/* Main loop */
int main(void)
{
    /* prepare UI */
    draw_borders();
    draw_top_and_channels();
    draw_users();
    draw_messages();
    draw_commands();

    /* Connect in background (synchronous here) */
    auto_connect_and_join();

    /* initial refresh */
    refresh_channels();
    /* ensure we use a safe channel pointer (fallback to DEFAULT_CHANNEL) */
    //refresh_users_for_channel(channels_count ? channels[current_channel_idx] : DEFAULT_CHANNEL);
    refresh_messages_for_channel(channels_count ? channels[current_channel_idx] : DEFAULT_CHANNEL);
    draw_top_and_channels();
    draw_users();
    draw_messages();

    uint32_t last_refresh = now_seconds();

    /* pick DEFAULT_CHANNEL if present in channels[] */
    for (int i = 0; i < channels_count; ++i) {
        if (msx_strcmp(channels[i], DEFAULT_CHANNEL) == 0) {
            current_channel_idx = i;
            break;
        }
    }

	int refresh_count = 0;
    while (1) {
        /* handle periodic refresh */
        refresh_count++;
        if (refresh_count >= REFRESH_COUNTER) {
			Beep();
            refresh_channels();
            refresh_users_for_channel(channels_count ? channels[current_channel_idx] : DEFAULT_CHANNEL);
            refresh_messages_for_channel(channels_count ? channels[current_channel_idx] : DEFAULT_CHANNEL);
            draw_top_and_channels();
            draw_users();
            draw_messages();
            draw_commands();
            refresh_count = 0;
        }
        /* always poll unread messages */
        //refresh_messages_for_channel(channels[current_channel_idx]);
        //draw_messages();

        /* handle input: Tab cycles commands; Enter executes; arrow keys change channel */
        uint8_t k = Inkey();
        if (k == 0) {
            /* yield */
            continue;
        }
        if (k == 0x09) { /* TAB ASCII 9 */
            cmd_selected = (cmd_selected + 1) % n_commands;
            draw_commands();
            continue;
        }
        if (k == 0x0D) { /* Enter: execute selected command */
            const char* cmdname = commands[cmd_selected];

            if (msx_strcmp(cmdname, "Send") == 0) {
                /* send message to current channel */
                char input[128];
                char prompt[64];
                snprintf(prompt, sizeof(prompt), "SEND %s", channels[current_channel_idx]);
                if (prompt_input(prompt, input, sizeof(input))) {
                    char cmd[256];
                    snprintf(cmd, sizeof(cmd), "irc_send %s %s", channels[current_channel_idx], input);
                    char* resp = send_command_and_get_response(cmd);
                    if (!resp || strncmp(resp, "ok:", 3) != 0) {
                        Locate(2, SCREEN_ROWS - 1);
                        if (resp) Print(resp); else Print("Send failed");
                    }
                    /* store local and refresh immediately so UI updates */
                    push_message(channels[current_channel_idx], "me", input, now_seconds());
                    refresh_users_for_channel(channels[current_channel_idx]);
                    refresh_messages_for_channel(channels[current_channel_idx]);
                    draw_top_and_channels();
                    draw_users();
                    draw_messages();
                }
            } else if (msx_strcmp(cmdname, "Join") == 0) {
                char input[64];
                if (prompt_input("Join channel", input, sizeof(input))) {
                    char cmd[128];
                    snprintf(cmd, sizeof(cmd), "irc_join %s", input);
                    send_command_and_get_response(cmd);
                    ensure_channel(input);
                    /* update channels list & select newly joined */
                    refresh_channels();
                    {
                        int i;
                        for (i = 0; i < channels_count; ++i) {
                            if (msx_strcmp(channels[i], input) == 0) { current_channel_idx = i; break; }
                        }
                    }
                    refresh_users_for_channel(channels[current_channel_idx]);
                    draw_top_and_channels();
                    draw_users();
                    draw_messages();
                }
            } else if (msx_strcmp(cmdname, "Part") == 0) {
                char cmd[128];
                snprintf(cmd, sizeof(cmd), "irc_part %s", channels[current_channel_idx]);
                send_command_and_get_response(cmd);
                /* simple behavior: just refresh list from server */
                refresh_channels();
                if (current_channel_idx >= channels_count) current_channel_idx = 0;
                draw_top_and_channels();
                refresh_users_for_channel(channels[current_channel_idx]);
                draw_users();
                draw_messages();
            } else if (msx_strcmp(cmdname, "PrivMsg") == 0) {
                char who[32];
                char text[128];
                if (prompt_input("Private to", who, sizeof(who))) {
                    if (prompt_input("Message", text, sizeof(text))) {
                        char cmd[256];
                        snprintf(cmd, sizeof(cmd), "irc_send %s %s", who, text); /* use PRIVMSG via irc_send to nick */
                        send_command_and_get_response(cmd);
                    }
                }
            } else if (msx_strcmp(cmdname, "ListCh") == 0) {
                refresh_channels();
                draw_top_and_channels();
            } else if (msx_strcmp(cmdname, "Exit") == 0) {
                /* Clean exit: disconnect and quit program */
                send_command_and_get_response("irc_disconnect");
                Cls();
                Print("Exiting MSXPI Chat");
                return 0;
            }
            draw_commands();
        } else if (k == 0x1B) {
            /* ESC to exit */
            send_command_and_get_response("irc_disconnect");
            Cls();
            Print("Exiting MSXPI Chat");
            return 0;
        } else if (k == 0x0B) { /* ctrl-K: previous channel */
            if (channels_count > 0) {
                current_channel_idx = (current_channel_idx - 1 + channels_count) % channels_count;
                refresh_users_for_channel(channels_count ? channels[current_channel_idx] : DEFAULT_CHANNEL);
                draw_top_and_channels();
                draw_users();
                draw_messages();
            }
        } else if (k == 0x0A) { /* ctrl-J: next channel */
            if (channels_count > 0) {
                current_channel_idx = (current_channel_idx + 1) % channels_count;
                refresh_users_for_channel(channels_count ? channels[current_channel_idx] : DEFAULT_CHANNEL);
                draw_top_and_channels();
                draw_users();
                draw_messages();
            }
        }
    }

    return 0;
}