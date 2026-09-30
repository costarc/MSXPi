/*
 * SHA-256 for MSX (SDCC, Z80) - standalone.
 *
 * The compression function is Z80 assembly (about 0.2 s per 64-byte block
 * on a 3.58 MHz Z80); other compilers get the same code in plain C, so the
 * file can be checked on a PC. Streaming API, any message length.
 *
 *   Sha256 ctx; uint8_t digest[32];
 *   sha256_init(&ctx);
 *   sha256_update(&ctx, data, len);   // as many times as needed
 *   sha256_final(&ctx, digest);
 *
 * or sha256(data, len, digest) in one call. sha256_hex() writes the 64
 * lowercase hex digits plus a NUL.
 *
 * Not reentrant: the compression uses static work areas (one hash at a
 * time, not from an interrupt handler). It keeps no state between calls
 * outside the Sha256 context, so it is safe with crt0s that do not clear
 * static data. About 1 KB of code, 300 bytes of
 * data. Use it by adding sha256.c to the build, or #include "sha256.c" in
 * a program built as a single file (as make.bat does).
 */
#ifndef SHA256_H
#define SHA256_H
#include <stdint.h>

typedef struct {
    uint32_t h[8];
    uint8_t buf[64];
    uint32_t bytes_lo, bytes_hi;   /* message length in bytes */
    uint8_t used;                  /* bytes waiting in buf */
} Sha256;

void sha256_init(Sha256 *ctx);
void sha256_update(Sha256 *ctx, const void *data, uint16_t len);
void sha256_final(Sha256 *ctx, uint8_t digest[32]);
void sha256(const void *data, uint16_t len, uint8_t digest[32]);
void sha256_hex(const uint8_t digest[32], char out[65]);

#endif
