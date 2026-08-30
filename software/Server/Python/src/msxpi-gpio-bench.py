#!/usr/bin/env python3
"""
MSXPi GPIO micro-benchmark: RPi.GPIO vs direct /dev/gpiomem register access.

Measures the per-operation cost of the two GPIO paths and projects what a byte
costs on each, so the effect of any change to the GPIO path can be measured
rather than estimated.

  sudo ./msxpi-gpio-bench.py

WHY A MICRO-BENCHMARK AND NOT A REAL TRANSFER
SPI_ByteTransfer() blocks on `while GPIO.input(SPI_CS): pass` until the CPLD
asserts CS, which only happens when the MSX writes a port. So a full transfer
cannot be timed standalone. What this does instead is time the primitives that
actually changed and reconstruct the byte cost from them - the ~38 GPIO
operations per byte plus, on the old path, the two sleeps.

SAFETY
Only drives SPI_SCLK, SPI_MISO and RPI_READY. Those are all CPLD *inputs*, so
there is no contention. SPI_CS and SPI_MOSI are CPLD outputs and are only ever
read here. Toggling SCLK while no transfer is open is harmless: MSXPi.vhd gates
the shift register on SPI_en_s, so idle clock edges are ignored. Running with
the MSX powered off (or the cartridge out, board powered from the Pi) is still
the tidiest way to do it.
"""

import os
import sys
import time

try:
    import RPi.GPIO as GPIO
except ImportError:
    sys.exit("RPi.GPIO not available - run this on the Raspberry Pi.")

# Match what msxpi-server.py prints at startup; override on the command line as:
#   msxpi-gpio-bench.py CS CLK MOSI MISO READY
SPI_CS, SPI_SCLK, SPI_MOSI, SPI_MISO, RPI_READY = 21, 20, 16, 12, 25
if len(sys.argv) == 6:
    SPI_CS, SPI_SCLK, SPI_MOSI, SPI_MISO, RPI_READY = (int(a) for a in sys.argv[1:6])

GPSET0, GPCLR0, GPLEV0 = 0x1C >> 2, 0x28 >> 2, 0x34 >> 2
N = 20000          # iterations per measurement

# Ops per byte in SPI_ByteTransfer(): 2 RDY + 4 tick writes
# + 8 bits x (1 MISO write + 2 SCLK writes + 1 MOSI read)
OPS_PER_BYTE = 2 + 4 + 8 * 4


def bench(fn, n=N):
    """Median-of-3 to shrug off scheduler noise."""
    runs = []
    for _ in range(3):
        t0 = time.perf_counter()
        fn(n)
        runs.append((time.perf_counter() - t0) / n * 1e6)   # us per op
    runs.sort()
    return runs[1]


def main():
    GPIO.setwarnings(False)
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(SPI_SCLK, GPIO.OUT)
    GPIO.setup(SPI_MISO, GPIO.OUT)
    GPIO.setup(RPI_READY, GPIO.OUT)
    GPIO.setup(SPI_MOSI, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
    GPIO.setup(SPI_CS, GPIO.IN, pull_up_down=GPIO.PUD_UP)

    print("MSXPi GPIO micro-benchmark")
    print(f"pins: CS={SPI_CS} CLK={SPI_SCLK} MOSI={SPI_MOSI} "
          f"MISO={SPI_MISO} READY={RPI_READY}\n")

    # ---------------- RPi.GPIO path ----------------
    def rpi_write(n):
        o, p, hi, lo = GPIO.output, SPI_SCLK, GPIO.HIGH, GPIO.LOW
        for _ in range(n):
            o(p, hi)
            o(p, lo)

    def rpi_read(n):
        i, p = GPIO.input, SPI_MOSI
        for _ in range(n):
            i(p)

    w_rpi = bench(rpi_write) / 2      # two writes per iteration
    r_rpi = bench(rpi_read)

    # ---------------- sleep cost ----------------
    def sleeper(n):
        s = time.sleep
        for _ in range(n):
            s(0.00001)

    t_sleep = bench(sleeper, 2000)

    # ---------------- register path ----------------
    reg = None
    try:
        import ctypes
        import mmap
        fd = os.open("/dev/gpiomem", os.O_RDWR | os.O_SYNC)
        try:
            mm = mmap.mmap(fd, 4096, mmap.MAP_SHARED,
                           mmap.PROT_READ | mmap.PROT_WRITE, offset=0)
        finally:
            os.close(fd)
        reg = (ctypes.c_uint32 * 1024).from_buffer(mm)

        # self-test, same one msxpi-server.py uses
        m_rdy = 1 << RPI_READY
        reg[GPSET0] = m_rdy
        hi_ok = GPIO.input(RPI_READY) == 1
        reg[GPCLR0] = m_rdy
        lo_ok = GPIO.input(RPI_READY) == 0
        if not (hi_ok and lo_ok):
            raise RuntimeError(f"self-test failed (high={hi_ok} low={lo_ok})")
        print("register self-test: PASSED\n")
    except Exception as e:
        print(f"register path unavailable: {e}")
        print("(expected on a Pi 5 - BCM2712/RP1 has a different GPIO block)\n")

    if reg is not None:
        m_sclk = 1 << SPI_SCLK
        m_mosi = 1 << SPI_MOSI

        def reg_write(n):
            r, s, c, m = reg, GPSET0, GPCLR0, m_sclk
            for _ in range(n):
                r[s] = m
                r[c] = m

        def reg_read(n):
            r, l, m = reg, GPLEV0, m_mosi
            for _ in range(n):
                _ = r[l] & m

        w_reg = bench(reg_write) / 2
        r_reg = bench(reg_read)
    else:
        w_reg = r_reg = float("nan")

    GPIO.cleanup()

    # ---------------- report ----------------
    print(f"{'operation':<28}{'RPi.GPIO':>12}{'register':>12}{'speedup':>10}")
    print("-" * 62)
    print(f"{'single write':<28}{w_rpi:>10.2f}us{w_reg:>10.2f}us{w_rpi/w_reg:>9.1f}x")
    print(f"{'single read':<28}{r_rpi:>10.2f}us{r_reg:>10.2f}us{r_rpi/r_reg:>9.1f}x")
    print(f"\ntime.sleep(0.00001) actually costs {t_sleep:.1f} us "
          f"(you asked for 10)")

    # Reconstruct byte cost. 30 writes + 8 reads per byte.
    old = 30 * w_rpi + 8 * r_rpi + 2 * t_sleep
    mid = 30 * w_rpi + 8 * r_rpi                      # change 1 only
    new = 30 * w_reg + 8 * r_reg                      # changes 1 + 2

    print(f"\n{'projected cost per byte':<40}")
    print("-" * 62)
    print(f"{'original (RPi.GPIO + 2 sleeps)':<40}{old:>10.1f} us")
    print(f"{'change 1 only (sleeps removed)':<40}{mid:>10.1f} us"
          f"   {old/mid:>5.1f}x")
    print(f"{'changes 1+2 (register path)':<40}{new:>10.1f} us"
          f"   {old/new:>5.1f}x")

    print(f"\n{OPS_PER_BYTE} GPIO ops per byte. A 142 KB transfer is "
          f"~{145408*old/1e6:.0f}s before, ~{145408*new/1e6:.0f}s after "
          f"(Pi-side only, excluding MSX and protocol overhead).")

    if new < 20:
        print("\nUnder 20 us/byte - this is the range where hardware /WAIT stops\n"
              "violating SR-3. See WAIT_STATE_IMPLEMENTATION.md section 6.")
    else:
        print(f"\nStill {new:.0f} us/byte. Hardware /WAIT needs roughly <20 us to be\n"
              "safe, so it is not yet worth enabling the mode register.")


if __name__ == "__main__":
    main()
