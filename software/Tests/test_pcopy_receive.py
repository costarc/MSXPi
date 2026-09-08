"""Run the real pcopy control flow with a scripted transport and disk backend."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

SOFTWARE = Path(__file__).resolve().parents[1]


class ReceiveTests(unittest.TestCase):
    def test_failed_receive_never_reaches_disk(self):
        source = (SOFTWARE / 'Client/src/pcopy.c').read_text()
        source = re.sub(r'^#include.*$', '', source, flags=re.M)
        # Substitute only the MSX PSP address; retain the argument parser and
        # every transfer/disk decision from the production source.
        source = source.replace('(uint8_t *)0x0080', 'mock_psp')
        source = source.replace('void main(void)', 'void msx_main(void)')
        constants = '\n'.join(re.findall(r'^#define RC_.*$',
            (SOFTWARE / 'C-common/header/msxpi.h').read_text(), re.M))
        fixture = r'''
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <assert.h>
typedef struct { uint8_t bytes[37]; } FCB;
static uint8_t mock_psp[] = {10,'A','L','E','S','T','E','.','R','O','M',0};
static uint8_t buffer[8192];
static uint8_t failure;
static int receives, writes, closes, claims;
static uint8_t *get_buffer_ptr(void) { return buffer; }
static void Print(char *p) { (void)p; }
static void pprintf(char *p, uint16_t n) { (void)p; (void)n; }
static void pprints(char *p, char *q) { (void)p; (void)q; }
static uint8_t parseConnError(uint8_t rc) { return rc; }
static uint8_t fcb_open(FCB *p) { (void)p; return 0; }
static uint8_t fcb_create(FCB *p) { (void)p; return 0; }
static uint8_t fcb_close(FCB *p) { (void)p; ++closes; return 0; }
static uint16_t fcb_read(FCB *p, uint8_t *b, uint16_t n) {
    (void)p; (void)b; (void)n; return 0;
}
static uint8_t fcb_write(FCB *p, uint8_t *b, uint16_t n) {
    (void)p; assert(b == buffer); assert(n == 512); ++writes; return 0;
}
static uint8_t SendCommandToMSXPi(char *p, bool b) {
    (void)p; (void)b; return RC_SUCCESS;
}
static uint8_t PerformHandshake(uint16_t n) { (void)n; return RC_SUCCESS; }
static uint8_t SENDDATA2(uint8_t *b, uint16_t n, uint16_t *m) {
    (void)b; (void)n; (void)m; return RC_SUCCESS;
}
static uint8_t RECVDATA_ONEBLOCK(uint8_t *b, uint16_t *n, uint16_t m) {
    (void)b; (void)m;
    if (++receives == 1) { *n = 0; return RC_SUCCESS; } // init
    *n = 512; // even failures may leave a nonzero length and partial data
    if (failure) return failure;
    return receives == 2 ? RC_READY : RC_SUCCESS;
}
static void msxpi_link_claim(void) { ++claims; }
static void msxpi_link_release(void) { --claims; }
'''
        checks = r'''
int main(void) {
    const uint8_t errors[] = {RC_CONNERR, RC_CHKSUM_ERR, RC_HANDSHAKEERR};
    for (unsigned i = 0; i < sizeof(errors); ++i) {
        receives = writes = closes = claims = 0;
        failure = errors[i];
        assert(pcopy() == failure);
        assert(writes == 0 && closes == 1 && claims == 0);
    }
    receives = writes = closes = claims = 0;
    failure = 0;
    assert(pcopy() == RC_SUCCESS);
    assert(writes == 2 && closes == 1 && claims == 0);
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            c = Path(tmp) / 'test.c'
            c.write_text(constants + '\n' + fixture + '\n' + source + checks)
            binary = Path(tmp) / 'test'
            subprocess.run([os.environ.get('CC', 'cc'), '-std=c99', '-O0',
                            str(c), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True)


if __name__ == '__main__':
    unittest.main()
