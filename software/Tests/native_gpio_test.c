/*
 * MSXPi Interface
 * Version 1.6
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

/* Simulate the CPLD's E1/load, E2..E9/data, E10/complete edge contract. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define MSXPI_GPIO_TEST
#include "../Server/Python/src/native/gpio_transfer.c"

static uint32_t regs[1024], levels;
static size_t completed, announced, fail_at;
static unsigned edges, samples, expected_samples, burst_mode;
static uint8_t received[8192], transmitted[8192], accumulator;
static uint64_t ticks;
static const uint32_t pins[5]={1,2,4,8,16};
uint64_t test_now(void) { return ticks += 100; }
uint32_t test_read(volatile uint32_t *r, unsigned offset) {
    (void)r; assert(offset==LEV);
    if (burst_mode && (levels&16) && !edges && completed!=fail_at) levels&=~8;
    if (edges>=2 && edges<=9 && !(levels&8)) ++samples;
    return levels;
}
void test_write(volatile uint32_t *r, unsigned offset, uint32_t mask) {
    (void)r; assert(offset==SET || offset==CLR);
    if (offset==SET) {
        if (mask==16) {
            assert(!(levels&16));
            ++announced; edges=samples=0; accumulator=0;
            if (completed==fail_at) levels|=8; else levels&=~8;
        }
        if (mask==1) {
            assert(!(levels&1)); assert(levels&16); assert(!(levels&8));
            ++edges; assert(edges<=10);
            if (edges>=2 && edges<=9) {
                accumulator=(uint8_t)((accumulator<<1) | !!(levels&2));
                if (transmitted[completed] & (0x80u>>(edges-2))) levels|=4;
                else levels&=~4;
            }
            if (edges==10) levels|=8;
        }
        levels|=mask;
    } else {
        if (mask==16) assert(levels&16);
        if (mask==1 && edges==10) {
            assert(samples==expected_samples);
            received[completed++]=accumulator;
            edges=samples=0; accumulator=0;
        }
        levels&=~mask;
    }
}
static void reset(void) {
    burst_mode=0; expected_samples=8; completed=announced=0; fail_at=(size_t)-1; levels=8; edges=samples=0; ticks=0;
    memset(received,0,sizeof(received));
    for (size_t i=0;i<sizeof(transmitted);++i) transmitted[i]=(uint8_t)((i*73)^(i>>3));
}
int main(void) {
    uint8_t rx[8192], tx[8192];
    for (size_t i=0;i<sizeof(tx);++i) tx[i]=(uint8_t)i;
    const size_t sizes[]={0,1,255,256,257,8192};
    size_t done; uint64_t waited;
    for (size_t n=0;n<sizeof(sizes)/sizeof(sizes[0]);++n) {
        reset();
        assert(msxpi_gpio_transfer(regs,pins,tx,rx,sizes[n],500,1,&done,&waited)==0);
        assert(done==sizes[n] && completed==sizes[n] && announced==sizes[n]);
        assert(memcmp(rx,transmitted,done)==0 && memcmp(received,tx,done)==0);
        assert(!(levels&17)); // READY and SCLK low on completion
        reset(); expected_samples=0;
        assert(msxpi_gpio_transfer(regs,pins,tx,NULL,sizes[n],500,1,&done,&waited)==0);
        assert(memcmp(received,tx,done)==0 && done==sizes[n]);
        reset();
        assert(msxpi_gpio_transfer(regs,pins,NULL,rx,sizes[n],500,1,&done,&waited)==0);
        assert(memcmp(rx,transmitted,done)==0);
        for (size_t i=0;i<done;++i) assert(received[i]==0); // passive MISO
    }
    reset(); fail_at=17;
    assert(msxpi_gpio_transfer(regs,pins,tx,rx,257,500,1,&done,&waited)==1);
    assert(done==17 && completed==17 && announced==18 && !(levels&17));
    assert(waited>=1000000 && memcmp(rx,transmitted,17)==0);
    reset(); fail_at=0;
    assert(msxpi_gpio_transfer(regs,pins,tx,rx,1,500,1,&done,&waited)==1);
    assert(done==0 && completed==0 && !(levels&17));
    reset();
    assert(msxpi_gpio_transfer(regs,pins,tx,rx,1,0,1,&done,&waited)==2);
    uint32_t bad[5]={1,1,4,8,16};
    assert(msxpi_gpio_transfer(regs,bad,tx,rx,1,500,1,&done,&waited)==2);
    assert(announced==0);
    for (size_t n=0;n<sizeof(sizes)/sizeof(sizes[0]);++n) {
        reset(); burst_mode=1;
        assert(msxpi_gpio_burst(regs,pins,tx,rx,sizes[n],500,1,&done,&waited)==0);
        assert(done==sizes[n] && completed==sizes[n] && announced==(sizes[n]!=0));
        assert(memcmp(rx,transmitted,done)==0 && memcmp(received,tx,done)==0);
        assert(!(levels&17));
    }
    reset(); burst_mode=1; fail_at=17;
    assert(msxpi_gpio_burst(regs,pins,tx,rx,257,500,1,&done,&waited)==1);
    assert(done==17 && completed==17 && announced==1 && !(levels&17));
    puts("PASS native GPIO: edge map, all byte values, lengths 0/1/255/256/257/8192, CS timeout, partial count, READY cleanup, invalid config");
    return 0;
}
