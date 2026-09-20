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

/* MSXPi v1.6 GPIO payload engine. Same ten clocks and per-byte READY as Python.
 * This is NOT standard SPI: the CPLD drives CS and the Pi supplies the clocks.
 */
#define _POSIX_C_SOURCE 200809L
#include <stddef.h>
#include <stdint.h>
#include <time.h>

#define SET 7
#define CLR 10
#define LEV 13

#ifdef MSXPI_GPIO_TEST
extern uint32_t test_read(volatile uint32_t *, unsigned);
extern void test_write(volatile uint32_t *, unsigned, uint32_t);
extern uint64_t test_now(void);
#define read_reg test_read
#define write_reg test_write
#define now_ns test_now
#else
static uint32_t read_reg(volatile uint32_t *reg, unsigned offset) {
    return reg[offset];
}
static void write_reg(volatile uint32_t *reg, unsigned offset, uint32_t value) {
    reg[offset] = value;
    /* Complete each MMIO write before the next edge, including on ARM. */
#if defined(__aarch64__) || defined(__arm__)
    __sync_synchronize();
#else
    __asm__ volatile("" ::: "memory");
#endif
}
static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000u + (uint64_t)ts.tv_nsec;
}
#endif

static void delay_ns(uint32_t ns) {
    uint64_t until = now_ns() + ns;
    while (now_ns() < until) { }
}

/* Settling time between seeing CS low and the first clock edge (E1).  CS goes
 * low as soon as the MSX's OUT starts, and E1 loads the CPLD's write latch, so
 * clocking E1 at once can latch a byte that is still settling.  0 (the
 * default) keeps the original behaviour; the v0.8.2 board (PCB v0.7 Rev.7)
 * needed a delay here.  Set by msxpi_gpio_set_cs_setup(), from
 * MSXPI_GPIO_CS_SETUP_NS - a separate export, so the transfer ABI is unchanged.
 */
static uint32_t cs_setup_ns = 0;
int msxpi_gpio_set_cs_setup(uint32_t ns) {
    if (ns > 100000) return 2;
    cs_setup_ns = ns;
    return 0;
}

/* masks: SCLK, MISO, MOSI, CS, READY. tx==NULL is passive reception (MISO=0).
 * Return 0=success, 1=CS timeout, 2=invalid arguments. done counts WHOLE bytes.
 * wait_ns measures waiting for the MSX; Python can distinguish it from clocking.
 */
static int transfer(volatile uint32_t *reg, const uint32_t masks[5],
                      const uint8_t *tx, uint8_t *rx, size_t count,
                      uint32_t half_period_ns, uint32_t timeout_ms,
                      size_t *done, uint64_t *wait_ns, int burst) {
    if (!reg || !masks || !done || !wait_ns || (!tx && !rx && count) ||
        half_period_ns < 250 || half_period_ns > 100000 || !timeout_ms ||
        timeout_ms > 60000) return 2;
    uint32_t used = 0;
    for (unsigned i = 0; i < 5; ++i) {
        if (!masks[i] || (masks[i] & (masks[i]-1)) || (used & masks[i])) return 2;
        used |= masks[i];
    }
    *done = 0;
    *wait_ns = 0;
    uint32_t clk=masks[0], miso=masks[1], mosi=masks[2], cs=masks[3], ready=masks[4];
    if (burst && count) write_reg(reg, SET, ready);
    for (size_t n=0; n<count; ++n) {
        uint8_t input=0, output=tx ? tx[n] : 0;
        uint64_t start=now_ns();
        if (!burst) write_reg(reg, SET, ready);
        while (read_reg(reg, LEV) & cs) {
            if (now_ns()-start >= (uint64_t)timeout_ms*1000000u) {
                *wait_ns += now_ns()-start;
                write_reg(reg, CLR, ready);
                return 1;
            }
        }
        *wait_ns += now_ns()-start;
        if (cs_setup_ns) delay_ns(cs_setup_ns);
        /* E1: load the CPLD write latch into its shift register. */
        write_reg(reg, SET, clk);
        delay_ns(half_period_ns);
        write_reg(reg, CLR, clk);
        /* E2..E9: MISO setup, clock high, MOSI settling/sample, clock low. */
        for (unsigned bit=0x80; bit; bit>>=1) {
            write_reg(reg, (output & bit) ? SET : CLR, miso);
            delay_ns(half_period_ns);
            write_reg(reg, SET, clk);
            delay_ns(half_period_ns);
            if (rx && (read_reg(reg, LEV) & mosi)) input |= bit;
            write_reg(reg, CLR, clk);
        }
        /* E10: completes the CPLD byte and releases CS. */
        delay_ns(half_period_ns);
        write_reg(reg, SET, clk);
        delay_ns(half_period_ns);
        write_reg(reg, CLR, clk);
        if (!burst) write_reg(reg, CLR, ready);
        if (rx) rx[n]=input;
        *done=n+1;
    }
    if (burst && count) write_reg(reg, CLR, ready);
    return 0;
}

/* Separate exports keep the original per-byte ABI intact. */
#define TRANSFER_ARGS volatile uint32_t *reg, const uint32_t masks[5], \
    const uint8_t *tx, uint8_t *rx, size_t count, uint32_t half_period_ns, \
    uint32_t timeout_ms, size_t *done, uint64_t *wait_ns
#define TRANSFER_VALUES reg, masks, tx, rx, count, half_period_ns, timeout_ms, done, wait_ns
int msxpi_gpio_transfer(TRANSFER_ARGS) { return transfer(TRANSFER_VALUES, 0); }
int msxpi_gpio_burst(TRANSFER_ARGS) { return transfer(TRANSFER_VALUES, 1); }
