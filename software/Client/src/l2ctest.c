/*
 * MSXPi Interface
 * Version 1.6.1
 * ------------------------------------------------------------------------------
 * MIT License
 *
 * Copyright (c) 2015-2026 Ronivon Costa
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 * ------------------------------------------------------------------------------
 */

/*
 * L2CTEST.COM - the C library's LINK2 calls against the server's `l2test` command
 * (documents/LINK2-TEST-PLAN.md, T7).  Not shipped: build with `make.bat l2ctest`.
 *
 * It checks, with the server's pattern (byte i = i*13 + (i>>8)*7 + seed):
 *   link_send of 1, 255, 256, 8191, 8192 and 20000 bytes, from a buffer in page 2/3
 *   (the Pi may burst) and from one below 8000h (polled), each verified by the server
 *   link_recv modes 2, 0 and 1 of the same patterns (mode 0 and 1 by the byte count)
 *   link_recv_open / link_recv_next taking a 20000 byte stream block by block into
 *   different places: RC_READY, RC_READY, RC_SUCCESS, the pattern intact
 * and prints "L2C PASS n FAIL m" (and "L2C FAIL <name>" for each failure).
 */
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include "../../C-common/header/fusion.h"
#include "../../C-common/header/msxpi.h"

#define SEED 7
#define BUFSZ 8192

static uint8_t low[300];          /* below 8000h: polled sends */
static uint8_t pass, fail;
static char cmd[40];

static void put_num(char *p, uint16_t v) {
    char t[6];
    uint8_t n = 0;
    do { t[n++] = '0' + v % 10; v /= 10; } while (v);
    while (n) *p++ = t[--n];
    *p = 0;
}

static void make_cmd(const char *verb, uint16_t n) {
    char num[6];
    strcpy(cmd, verb);
    put_num(num, n);
    strcat(cmd, num);
    strcat(cmd, " 7");
}

static void pattern(uint8_t *p, uint16_t from, uint16_t n) {
    uint16_t i;
    for (i = 0; i < n; i++, from++)
        p[i] = (uint8_t)(from * 13 + (from >> 8) * 7 + SEED);
}

static bool check(const uint8_t *p, uint16_t from, uint16_t n) {
    uint16_t i;
    for (i = 0; i < n; i++, from++)
        if (p[i] != (uint8_t)(from * 13 + (from >> 8) * 7 + SEED)) return false;
    return true;
}

static void result(const char *name, bool ok) {
    if (ok) { pass++; return; }
    fail++;
    Print("L2C FAIL ");
    Print((char *)name);
    Print("\r\n");
}

/* The server's sink answers "L2TEST OK n crc xxxx" */
static void send_test(const char *name, uint8_t *buf, uint16_t n) {
    uint8_t rc;
    uint16_t got;
    static uint8_t reply[64];
    pattern(buf, 0, n);
    make_cmd("l2test sink ", n);
    rc = link_command(cmd, false);
    if (rc == RC_SUCCESS) rc = link_send(buf, n);
    got = 0;
    if (rc == RC_SUCCESS) rc = link_recv(LINK_RECV_BUFFER, reply, sizeof(reply) - 1, &got);
    reply[got] = 0;
    result(name, rc == RC_SUCCESS && !memcmp(reply, "L2TEST OK", 9));
}

static void recv_test(const char *name, uint8_t *buf, uint16_t n) {
    uint8_t rc;
    uint16_t got = 0;
    memset(buf, 0, 16);
    make_cmd("l2test pat ", n);
    rc = link_command(cmd, false);
    if (rc == RC_SUCCESS) rc = link_recv(LINK_RECV_BUFFER, buf, BUFSZ, &got);
    result(name, rc == RC_SUCCESS && got == n && check(buf, 0, n));
}

static void discard_test(const char *name, uint16_t n) {
    uint8_t rc;
    uint16_t got = 0;
    make_cmd("l2test pat ", n);
    rc = link_command(cmd, false);
    if (rc == RC_SUCCESS) rc = link_recv(LINK_RECV_DISCARD, get_buffer_ptr(), 1024, &got);
    result(name, rc == RC_SUCCESS && got == n);
}

static void print_test(const char *name, uint16_t n) {
    uint8_t rc;
    uint16_t got = 0;
    make_cmd("l2test pat ", n);
    rc = link_command(cmd, false);
    if (rc == RC_SUCCESS) rc = link_recv(LINK_RECV_PRINT, get_buffer_ptr(), 1024, &got);
    Print("\r\n");
    result(name, rc == RC_SUCCESS && got == n);
}

/* 20000 bytes in blocks of at most 8192, taken block by block into two places */
static void blocks_test(const char *name, uint8_t *a, uint8_t *b) {
    uint8_t rc, k, blocks = 0;
    uint16_t got, total = 0;
    bool ok = true;
    make_cmd("l2test pat ", 20000);
    rc = link_command(cmd, false);
    if (rc == RC_SUCCESS) rc = link_recv_open(a, BUFSZ);
    if (rc == RC_SUCCESS) {
        for (k = 0; k < 4; k++) {
            uint8_t *dest = (k & 1) ? b : a;
            got = 0;
            rc = link_recv_next(dest, &got);
            if (rc != RC_READY && rc != RC_SUCCESS) break;
            if (!check(dest, total, got)) ok = false;
            total += got;
            blocks++;
            if (rc == RC_SUCCESS) break;
        }
    }
    result(name, ok && rc == RC_SUCCESS && total == 20000 && blocks == 3);
}

int main(void) {
    uint8_t *big = (uint8_t *)0x8000;     /* page 2: the Pi may burst */
    uint8_t *big2 = (uint8_t *)0xA000;

    pass = 0; fail = 0;      /* BSS is not cleared (--no-std-crt0) */
    msxpi_link_claim();
    send_test("send 1 low", low, 1);
    send_test("send 255 low", low, 255);
    send_test("send 256 low", low, 256);
    send_test("send 1 high", big, 1);
    send_test("send 256 high", big, 256);
    send_test("send 8191 high", big, 8191);
    send_test("send 8192 high", big, 8192);
    send_test("send 9000 high", big, 9000);
    recv_test("recv 1", big, 1);
    recv_test("recv 256 low", low, 256);
    recv_test("recv 8192", big, 8192);
    recv_test("recv 8192 again", big2, 8192);
    discard_test("discard 5000", 5000);
    print_test("print 300", 300);
    blocks_test("blocks high", big, big2);
    msxpi_link_release();

    Print("L2C PASS ");
    PrintNumber(pass);
    Print(" FAIL ");
    PrintNumber(fail);
    Print("\r\n");
    return 0;
}
