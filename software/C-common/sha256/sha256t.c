/*
 * SHA256T.COM - checks sha256.c against the FIPS 180-2 test vectors and
 * times it. Build from software with:  make.bat ..\C-common\sha256\sha256t
 * or with the sdcc line in README.md. On a PC: gcc sha256t.c -o sha256t
 */
#include <stdint.h>
#include <string.h>
#ifdef __SDCC
#include "../../../../../MSX/MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#define JIFFY (*(volatile uint16_t *)0xFC9E)
static void say(const char *s) { Print((char *)s); }
#else
#include <stdio.h>
#define JIFFY 0
static void say(const char *s) { fputs(s,stdout); }
#endif
#include "sha256.c"

static uint8_t failures;
static void check(const char *name,const char *want,const char *got) {
    say(strcmp(want,got)?"FAIL ":"PASS ");
    say(name); say("\r\n");
    if(strcmp(want,got)) { say(" got  "); say(got); say("\r\n"); failures++; }
}

static char *number(uint16_t n) {
    static char s[6]; uint8_t i=5; s[5]=0;
    do { s[--i]=(char)('0'+n%10); n/=10; } while(n && i);
    return s+i;
}

int main(void) {
    static uint8_t d[32], block[100];
    static char hex[65];
    Sha256 ctx; uint16_t i,t;
    failures=0;   /* crt0_msxdos does not clear static data */

    sha256("",0,d); sha256_hex(d,hex);
    check("empty","e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",hex);
    sha256("abc",3,d); sha256_hex(d,hex);
    check("abc","ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",hex);
    sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",56,d); sha256_hex(d,hex);
    check("two blocks","248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",hex);
    /* 1000 x 'a' fed in odd-sized pieces: exercises the streaming path. */
    memset(block,'a',sizeof(block));
    sha256_init(&ctx);
    for(i=0;i<1000;) { uint16_t n=1000-i<37?1000-i:37; sha256_update(&ctx,block,n); i+=n; }
    sha256_final(&ctx,d); sha256_hex(d,hex);
    check("1000 a","41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",hex);
    t=JIFFY;
    for(i=0;i<10;i++) sha256(block,55,d);
    t=JIFFY-t;
    say("10 one-block hashes: "); say(number(t)); say(" jiffies\r\n");
    say(failures?"SHA256 FAILED\r\n":"SHA256 OK\r\n");
    return failures;
}
