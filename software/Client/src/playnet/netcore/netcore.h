/* netcore: the MSXNP session engine (documents/PLAYNET-PROTOCOLS.md 11), the MSX-side twin of the
 * Pi's msxpi_netplay.Netplay.
 *
 * Portable C: the same file is compiled by SDCC into PLAYNET.OVL (the TCP/IP UNAPI path) and by gcc into
 * host/netcore_host, which the conformance test (Server/Python/tests/test_netcore.py) plays against Netplay
 * over localhost UDP. No allocation, no floating point, no library calls beyond memcpy/memcmp.
 *
 * The host provides the four functions below. Time is in centiseconds, 16 bits, wrapping (differences
 * are taken modulo 65536, and no timeout here is longer than 120 s).
 */
#ifndef NETCORE_H
#define NETCORE_H

#include <stdint.h>

typedef struct {
    uint8_t ip[4];
    uint16_t port;
} nc_addr;

/* ---- provided by the host -------------------------------------------------------------- */
void nc_send(const nc_addr *to, const uint8_t *data, uint8_t len);
uint8_t nc_recv(nc_addr *from, uint8_t *buf, uint8_t max);     /* 0 = nothing waiting */
uint16_t nc_now(void);                                          /* centiseconds */
uint32_t nc_rand32(void);                                       /* not seeded alike on both sides */

/* ---- MSX-visible status (as the Pi's opcode C9 status, 10.1) --------------------------- */
#define NC_ST_CONNECTING   0
#define NC_ST_READY        1
#define NC_ST_INCOMPATIBLE 2
#define NC_ST_FAILED       3
#define NC_ST_LEFT         4

/* ---- XCHG results (10) ----------------------------------------------------------------- */
#define NC_X_NOTHING 0
#define NC_X_PACKET  1
#define NC_X_GONE    2
#define NC_X_LEFT    3

#define NC_MAX_CANDIDATES 3
#define NC_MAX_PKT 46                   /* 14 + 8W, W = 1..4 */

/* version: MSXNP version (1); force_delay: 0, or an input delay the leader uses instead of measuring */
void nc_init(uint32_t profile_hash, uint8_t version, uint8_t force_delay);
void nc_set_peers(const nc_addr *candidates, uint8_t count);
void nc_restart(void);                  /* start connecting (HELLO to every candidate) */
void nc_poll(void);                     /* take what arrived, run the timers */
uint8_t nc_status(uint8_t *delay);      /* NC_ST_*, and the input delay when ready */
uint8_t nc_xchg(const uint8_t *pkt, uint8_t len, uint8_t *rx, uint8_t *reason);
void nc_bye(uint8_t result);            /* end here: BYE goes out 3 times, 100 ms apart (keep polling) */
uint8_t nc_bye_pending(void);           /* BYEs still to send */
uint8_t nc_is_leader(void);
const nc_addr *nc_peer(void);           /* the locked opponent, or 0 */

#endif
