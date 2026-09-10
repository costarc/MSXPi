# Native GPIO payload engine — first performance test

Target: Raspberry Pi Zero 2 W and MSXPi CPLD v1.6. This moves the payload bit loop from Python/ctypes GPIO operations into native C, with one Python→C call per 256 bytes. Pure output also skips unused MOSI reads. Pin setup, pulls, and cleanup remain owned by RPi.GPIO. The existing direct-register self-test must pass before the native engine can load.

The first patch retains the existing ten-clock byte sequence and per-byte READY handshake. It does not enable /WAIT bursts or change framing. The ASM BIOS, C BIOS, disk driver, and clients therefore stay compatible without recompilation. This isolates the Pi-side performance change; a later block protocol can address Z80-side overhead if measurements require it.

## Build on the Raspberry Pi

Run from the directory containing the updated `msxpi-server.py` and `msxpi_gpio_native.py`:

```sh
bash native/build.sh
```

Requires a C compiler (`cc`, or set `CC`). The generated `native/libmsxpi_gpio.so` is architecture-specific and ignored by Git. **Build it on the Pi; do not copy the x86-64 library generated during WSL tests.** If deploying the server outside the checkout, also deploy `msxpi_gpio_native.py` and the `native` directory beside it.

## A/B test

Stop the existing server before each run. Use the same user/permissions and configuration as the current working server.

Baseline:

```sh
MSXPI_NATIVE_GPIO=0 python3 msxpi-server.py
```

Native:

```sh
MSXPI_NATIVE_GPIO=1 python3 msxpi-server.py
```

The native run must print:

```text
init_fast_gpio(): native GPIO payload engine active (half-period 250 ns)
```

If it reports that the native engine is unavailable, it is still using Python GPIO and the result is not a native-engine benchmark. Native mode is opt-in; omission of the environment variable keeps the Python path. openMSX/TCP continues using the Python byte transport.

Copy the same 256 KiB (or larger) file at least three times in each mode. Measure from the MSX command to return of the DOS prompt. Test download and upload separately, as well as copying onto the Pi-served drive B. Read the copied file back to the Pi under a different name and compare it with `sha256sum` or `cmp`. Keep the MSX model/clock, input file, disk state and server logging settings the same. More than 30% throughput improvement means native elapsed time is below baseline/1.30 (about 76.9% of baseline).

For example, after setting the Pi directory with `p cd`:

```text
B:
A:pcopy SAMPLE.ROM
A:pcopy B:SAMPLE.ROM ROUNDTRP.ROM
```

On the Pi, compare `SAMPLE.ROM` and `ROUNDTRP.ROM`. Use a disposable destination disk/file for the initial hardware test.

For a separate diagnostic run:

```sh
MSXPI_NATIVE_GPIO=1 MSXPI_PROFILE=1 python3 msxpi-server.py
```

`[native GPIO]` lines report payload bytes, time inside the engine, and time spent waiting for the MSX to assert CS. A large wait fraction points to the MSX transfer routines as the next bottleneck. Existing `[prof]` lines describe the Python byte path (principally headers/status in this mode); do not treat them as complete native-payload timing. Disable profiling for final speed comparisons because it adds logging overhead.

## Timing and integrity

- Default minimum data setup/high interval: 250 ns. Override with `MSXPI_GPIO_HALF_PERIOD_NS=500` for a slower timing comparison. Accepted range is 250–100000 ns; actual intervals include GPIO, barrier, and timing-call overhead.
- Default CS inactivity timeout is 1000 ms per byte, configurable via `MSXPI_GPIO_TIMEOUT_MS` (1–60000). On timeout the engine lowers READY and reports failure; it never silently replays a partial transfer through Python.
- Payload length, block index, folded checksum, status acknowledgement and retry logic are unchanged. Received data is returned to the protocol only after the complete native payload read succeeds.
- READY still cycles per byte. This is not the continuous-READY backend required for a new unpolled INIR/OTIR protocol. Existing UNAPI `SPI_BurstOut` remains unchanged.
- Host waveform/protocol tests pass, but physical clock timing, scheduler-induced /WAIT stalls and the actual speedup require testing on the board. No >30% physical speedup is claimed yet.

## Host regression tests

From the repository root:

```sh
cc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined \
  software/Tests/native_gpio_test.c -o /tmp/native-gpio-test
/tmp/native-gpio-test
python3 software/Tests/test_native_gpio.py
python3 software/Tests/test_pcopy_receive.py
python3 software/Server/Python/src/test_msxpi_eth.py
```

The C test simulates the CPLD edge contract for reads and writes, checks all byte values and 0/1/255/256/257/8192-byte boundaries, and checks partial-transfer timeout/READY cleanup. Python tests compare native and fallback protocol frames and retransmissions. They do not touch real GPIO.

The shared MSX payload revision also routes existing UNAPI receive bursts
through `msxpi_gpio_burst`. Rebuild the library when updating Python: the new
export keeps READY asserted across the complete burst. Ordinary file/disk
payloads retain per-byte READY and return to Python every 256 bytes.
