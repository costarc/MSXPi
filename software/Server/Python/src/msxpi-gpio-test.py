#!/usr/bin/env python3
"""
MSXPi GPIO / CPLD interface harness.

Run this with the MSXPi cartridge OUT of the MSX, powered from the Raspberry Pi
alone.  That is safe and it is the point: MSX +5V reaches the board only through
D5 (a 1N5817 Schottky, J1 pins 45/47 -> D5 -> the +5V rail), while the Pi's 5V
on J4 pins 2/4 feeds that rail directly.  So the Pi powers the whole board on its
own, and D5 blocks any back-feed toward the MSX.

The harness never drives a pin the CPLD drives.  SPI_CS and SPI_MOSI are CPLD
outputs and are only ever read; SPI_SCLK, SPI_MISO and RPI_READY are CPLD inputs
and are the only pins driven here.

  sudo ./msxpi-gpio-test.py

IMPORTANT CAVEAT.  With the cartridge out of the MSX, the CPLD's bus-side inputs
(A[7:0], D[7:0], /IORQ, /RD, /WR) are floating, so its internal state is
undefined - a floating /IORQ+/WR can look like a write and start a transfer.
Test 3 is therefore advisory.  Tests 1 and 2 do not depend on CPLD state and are
the ones that find damaged silicon.
"""

import sys
import time

try:
    import RPi.GPIO as GPIO
except ImportError:
    sys.exit("RPi.GPIO not available - run this on the Raspberry Pi.")

# Match the values msxpi-server.py prints at startup.  Override on the command
# line as: msxpi-gpio-test.py CS CLK MOSI MISO READY
SPI_CS       = 21   # CPLD output -> Pi input   (R9 10K pull-UP to 3V3 on board)
SPI_SCLK     = 20   # Pi output   -> CPLD input
SPI_MOSI     = 16   # CPLD output -> Pi input
SPI_MISO     = 12   # Pi output   -> CPLD input
RPI_READY    = 25   # Pi output   -> CPLD input (R8 10K pull-DOWN to GND on board)
RPI_SHUTDOWN = 26   # button      -> Pi input

if len(sys.argv) == 6:
    SPI_CS, SPI_SCLK, SPI_MOSI, SPI_MISO, RPI_READY = (int(a) for a in sys.argv[1:6])

CPLD_DRIVES = {SPI_CS: "SPI_CS", SPI_MOSI: "SPI_MOSI"}
PI_DRIVES   = {SPI_SCLK: "SPI_SCLK", SPI_MISO: "SPI_MISO", RPI_READY: "RPI_READY"}
ALL         = {**CPLD_DRIVES, **PI_DRIVES, RPI_SHUTDOWN: "RPI_SHUTDOWN"}

# On-board passives that the pull test must account for (from msxpi.kicad_pcb)
BOARD_PULL = {SPI_CS: "up (R9 10K to 3V3)", RPI_READY: "down (R8 10K to GND)"}

faults = []


def rule(t=""):
    print("\n" + t)
    print("-" * 68)


def sample(pin, pud, n=5):
    """Read a pin as an input under a given internal pull, settled."""
    GPIO.setup(pin, GPIO.IN, pull_up_down=pud)
    time.sleep(0.02)
    vals = [GPIO.input(pin) for _ in range(n)]
    return vals[0] if len(set(vals)) == 1 else None   # None = unstable


def test1_pull_probe():
    """
    Damage / short detector.  Read every pin as an input three ways: no pull,
    internal pull-up, internal pull-down.  The Pi's internal pulls are ~50K, so:

      follows the pull        -> nothing is driving it (floating, or the far
                                 side is an input and there is no board pull)
      independent of the pull -> something IS driving it, hard.  Good for
                                 SPI_CS/SPI_MOSI (the CPLD), suspicious for the
                                 pins only the Pi should drive.
      stuck 0 / stuck 1 and   -> short to GND / short to 3V3, OR a damaged
      nothing else moves         output latched on.  THIS is the failure we
                                 are hunting.
      unstable                -> floating with no pull, or noise pickup
    """
    rule("TEST 1  pull probe - detects shorts and stuck pins")
    print(f"{'pin':>4}  {'name':<13} {'no-pull':>8} {'pull-up':>8} {'pull-dn':>8}   verdict")
    for pin, name in ALL.items():
        off = sample(pin, GPIO.PUD_OFF)
        up = sample(pin, GPIO.PUD_UP)
        dn = sample(pin, GPIO.PUD_DOWN)
        f = lambda v: "unstable" if v is None else str(v)

        if up == 1 and dn == 0:
            verdict = "floating - follows pull (no external driver)"
            if pin in BOARD_PULL:
                verdict = f"SUSPECT: board pull {BOARD_PULL[pin]} missing/open"
                faults.append(f"{name}: board pull resistor appears open")
        elif up == dn and up is not None:
            level = up
            if pin in CPLD_DRIVES:
                verdict = f"driven {level} by CPLD - pin alive"
            elif pin in BOARD_PULL and (
                (level == 1 and "up" in BOARD_PULL[pin]) or
                (level == 0 and "down" in BOARD_PULL[pin])
            ):
                verdict = f"held {level} by board {BOARD_PULL[pin]} - correct"
            else:
                verdict = f"STUCK AT {level} - short or damaged output"
                faults.append(f"{name}: stuck at {level} regardless of pull")
        else:
            verdict = "unstable / indeterminate"

        print(f"{pin:>4}  {name:<13} {f(off):>8} {f(up):>8} {f(dn):>8}   {verdict}")


def test2_pi_outputs():
    """
    Tests the Pi's own output drivers, which is what you asked for.  Each pin
    the Pi owns is driven high and low and read back.  A GPIO whose output
    driver is damaged will not read back the level it is driving.

    Safe because all three of these are CPLD *inputs* - nothing else is driving
    them, so there is no contention.
    """
    rule("TEST 2  Pi output drivers - drive and read back")
    for pin, name in PI_DRIVES.items():
        ok = True
        detail = []
        for level in (0, 1, 0, 1):
            GPIO.setup(pin, GPIO.OUT)
            GPIO.output(pin, level)
            time.sleep(0.02)
            read = GPIO.input(pin)
            detail.append(f"{level}->{read}")
            # RPI_READY fights R8 (10K).  A healthy 3V3 push-pull wins easily;
            # if it cannot pull high, the driver is weak or dead.
            if read != level:
                ok = False
        status = "OK" if ok else "FAIL - driver damaged or pin shorted"
        if not ok:
            faults.append(f"{name}: output driver readback mismatch")
        print(f"{pin:>4}  {name:<13} {'  '.join(detail):<24} {status}")
        GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_OFF)


def test3_cpld_liveness():
    """
    Advisory only - see the caveat at the top of this file.  With the MSX absent
    the CPLD's bus inputs float, so it may or may not think a transfer is open.
    """
    rule("TEST 3  CPLD liveness (ADVISORY - bus inputs are floating)")
    GPIO.setup(SPI_SCLK, GPIO.OUT); GPIO.output(SPI_SCLK, 0)
    GPIO.setup(SPI_MISO, GPIO.OUT); GPIO.output(SPI_MISO, 0)
    GPIO.setup(RPI_READY, GPIO.OUT); GPIO.output(RPI_READY, 0)
    GPIO.setup(SPI_CS, GPIO.IN, pull_up_down=GPIO.PUD_OFF)
    GPIO.setup(SPI_MOSI, GPIO.IN, pull_up_down=GPIO.PUD_OFF)
    time.sleep(0.05)

    cs = GPIO.input(SPI_CS)
    print(f"  SPI_CS idle = {cs}  ", end="")
    if cs == 1:
        print("(expected: no transfer in progress)")
    else:
        print("(CPLD is asserting CS - a transfer looks stuck open,\n"
              "     which floating /IORQ+/WR can cause with the cartridge out)")

    # Clock 32 edges and watch MOSI.  If the CPLD is shifting, MOSI moves.
    seen = set()
    for _ in range(32):
        GPIO.output(SPI_SCLK, 1); time.sleep(0.001)
        seen.add(GPIO.input(SPI_MOSI))
        GPIO.output(SPI_SCLK, 0); time.sleep(0.001)
    print(f"  MOSI over 32 clocks = {sorted(seen)}  "
          f"{'(changing - CPLD is shifting)' if len(seen) > 1 else '(static)'}")

    for p in (SPI_SCLK, SPI_MISO, RPI_READY):
        GPIO.setup(p, GPIO.IN, pull_up_down=GPIO.PUD_OFF)


def main():
    GPIO.setwarnings(False)
    GPIO.setmode(GPIO.BCM)
    print("MSXPi GPIO / CPLD harness")
    print("Run with the cartridge OUT of the MSX, powered from the Pi only.")
    print(f"pins: CS={SPI_CS} CLK={SPI_SCLK} MOSI={SPI_MOSI} "
          f"MISO={SPI_MISO} READY={RPI_READY} SHUTDOWN={RPI_SHUTDOWN}")
    try:
        test1_pull_probe()
        test2_pi_outputs()
        test3_cpld_liveness()
    finally:
        GPIO.cleanup()

    rule("SUMMARY")
    if faults:
        for f in faults:
            print("  FAULT  " + f)
        print("\n  A pin that is stuck regardless of the internal pull is either")
        print("  shorted or has a damaged output driver.")
    else:
        print("  No stuck or shorted pins found on the Pi <-> CPLD interface.")
        print("  Note this harness cannot see /WAIT (U2 pin 37 -> J1 pin 7):")
        print("  that net does not reach the Pi.  Check it with a meter.")


if __name__ == "__main__":
    main()
