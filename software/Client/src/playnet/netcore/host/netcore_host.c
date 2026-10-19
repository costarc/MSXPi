/* netcore_host: netcore on a PC, for the conformance test against the Pi's Netplay
 * (Server/Python/tests/test_netcore.py). A real UDP socket, a centisecond clock, and a game loop that
 * sends one game packet per 20 ms frame once ready and counts what comes back.
 *
 *   netcore_host LPORT PEER_IP PEER_PORT PROFILE_HEX FRAMES [BYE_AT [WIDTH [VERSION [NONCE_HEX]]]]
 *
 * Prints one line per event: "STATUS n delay d leader l", "PACKET seq", "LEFT reason", "GONE", "DONE rx=n".
 * BYE_AT > 0: after that many frames, end the game here with result 1.
 * NONCE_HEX: when not 0, every nonce this side draws (to choose who leads).
 *
 *   gcc -O2 -I.. -o netcore_host netcore_host.c ../netcore.c
 */
#include <arpa/inet.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include "netcore.h"

static int sock;
static uint32_t forced_nonce;

void nc_send(const nc_addr *to, const uint8_t *data, uint8_t len)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    memcpy(&a.sin_addr, to->ip, 4);
    a.sin_port = htons(to->port);
    sendto(sock, data, len, 0, (struct sockaddr *)&a, sizeof a);
}

uint8_t nc_recv(nc_addr *from, uint8_t *buf, uint8_t max)
{
    struct sockaddr_in a;
    socklen_t al = sizeof a;
    ssize_t n = recvfrom(sock, buf, max, 0, (struct sockaddr *)&a, &al);
    if (n <= 0)
        return 0;
    memcpy(from->ip, &a.sin_addr, 4);
    from->port = ntohs(a.sin_port);
    return (uint8_t)n;
}

uint16_t nc_now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint16_t)(t.tv_sec * 100 + t.tv_nsec / 10000000);
}

uint32_t nc_rand32(void)
{
    if (forced_nonce)
        return forced_nonce;
    return ((uint32_t)rand() << 16) ^ (uint32_t)rand() ^ (uint32_t)getpid();
}

static void sleep_ms(int ms)
{
    struct timespec t = { 0, ms * 1000000L };
    nanosleep(&t, 0);
}

int main(int argc, char **argv)
{
    struct sockaddr_in me;
    nc_addr cand;
    uint8_t pkt[NC_MAX_PKT], rx[NC_MAX_PKT], reason, d, st, last = 0xFF, width = 1, ver = 1;
    unsigned frames, bye_at = 0, f = 0, got = 0, i;
    uint16_t next_frame = 0, done_at = 0;
    uint8_t ended = 0;
    int r;

    if (argc < 6) {
        fprintf(stderr, "usage: netcore_host LPORT PEER_IP PEER_PORT PROFILE_HEX FRAMES [BYE_AT [WIDTH [VERSION [NONCE]]]]\n");
        return 2;
    }
    frames = (unsigned)atoi(argv[5]);
    if (argc > 6) bye_at = (unsigned)atoi(argv[6]);
    if (argc > 7) width = (uint8_t)atoi(argv[7]);
    if (argc > 8) ver = (uint8_t)atoi(argv[8]);
    if (argc > 9) forced_nonce = (uint32_t)strtoul(argv[9], 0, 16);
    srand((unsigned)time(0) ^ (unsigned)getpid());
    setvbuf(stdout, 0, _IOLBF, 0);

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    memset(&me, 0, sizeof me);
    me.sin_family = AF_INET;
    me.sin_port = htons((uint16_t)atoi(argv[1]));
    if (bind(sock, (struct sockaddr *)&me, sizeof me) < 0) {
        perror("bind");
        return 2;
    }
    fcntl(sock, F_SETFL, O_NONBLOCK);
    inet_pton(AF_INET, argv[2], cand.ip);
    cand.port = (uint16_t)atoi(argv[3]);

    nc_init((uint32_t)strtoul(argv[4], 0, 16), ver, 0);
    nc_set_peers(&cand, 1);
    nc_restart();
    for (;;) {
        sleep_ms(5);
        nc_poll();
        st = nc_status(&d);
        if (st != last) {
            last = st;
            printf("STATUS %u delay %u leader %u\n", st, d, nc_is_leader());
            if (st == NC_ST_INCOMPATIBLE || st == NC_ST_FAILED)
                break;
        }
        if (done_at && (int16_t)(nc_now() - done_at) > 0)
            break;                                  /* the last frame (or our BYE) was a while ago */
        if (!(st == NC_ST_READY || st == NC_ST_LEFT) || (int16_t)(nc_now() - next_frame) < 0)
            continue;
        next_frame = nc_now() + 2;                  /* a 50 Hz game */
        if (bye_at && f == bye_at && !ended) {
            nc_bye(1);                              /* the exit key, here */
            ended = 1;
            done_at = nc_now() + 50;
            continue;
        }
        pkt[0] = 0x10; pkt[1] = (uint8_t)f; pkt[2] = (uint8_t)f; pkt[3] = width;
        for (i = 0; i < 8u * width + 8; i++)
            pkt[4 + i] = (uint8_t)(f + i);
        pkt[12 + 8 * width] = 0xFF; pkt[13 + 8 * width] = 0;
        r = nc_xchg(!ended && f < frames ? pkt : 0, (uint8_t)(14 + 8 * width), rx, &reason);
        if (r == NC_X_PACKET) {
            got++;
            printf("PACKET %u\n", rx[1]);
        } else if (r == NC_X_LEFT) {
            printf("LEFT %u\n", reason);
            break;
        } else if (r == NC_X_GONE) {
            printf("GONE\n");
            break;
        }
        if (f < frames && ++f == frames && !done_at)
            done_at = nc_now() + 100;               /* then a second to take what is still coming */
    }
    printf("DONE rx=%u\n", got);
    return 0;
}
