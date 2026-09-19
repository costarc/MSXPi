# Running MSXPi v1.6 on older boards

The v1.6 CPLD, BIOS/MSX-DOS ROM and server run on every earlier MSXPi board.
The I/O ports ($56/$57/$5A) and the ready flag have not changed since
v0.7 Rev.4, so the ROM and server are the same everywhere. Only the CPLD pin map
differs from board to board, plus whether the board wires `WAIT_n` to the
cartridge `/WAIT` line.

The main v1.6 build stays in this folder. The builds for older boards are in
one subfolder per release. Each subfolder holds a Quartus project that compiles
`../MSXPi.vhd` against its own `MSXPi_package_*.vhd`, which sets the build ID
and `WAIT_SUPPORT`.

## Which files to use

| Releases | PCB | CPLD image (ID) | ROM: `msxpibios.rom` on | `msxpi.ini` extras |
|---|---|---|---|---|
| v0.8.2, v1.0 | v0.7 Rev.7 | `v0.8.2/MSXPi_v1.6_polled.pof` ($10) | 27C256 EPROM, burned off-board | `GPIO_CS_SETUP_NS=1000` |
| v1.1, v1.2.1b | V1.1 Rev.1, V1.2.1b | `v1.1/MSXPi_v1.6_wait.pof` ($14) | AT28C256, flashed in circuit | V1.2.1b: `RPI_SHUTDOWN=26` |
| v1.3, v1.4, v1.5 | V1.3 Rev.1 | `MSXPi_v1.6.pof` ($0E) | AT28C256, flashed in circuit | `RPI_SHUTDOWN=26` |

- **ROM:** every board uses the same `software/target/msxpibios.rom`, the one
  `software/build` produces.
- **Server:** the same v1.6 server on every Pi. Pins from the `msxpi-Jumper*.ini`
  file matching the board (the older boards use `msxpi-JumperLeft.ini`); the
  extras column lists what to add. Settings left out stay unset.

- **EPROM jumpers on the v0.8.2 board (PCB v0.7 Rev.7).** /OE on **CS1**, so
  the ROM answers in page 1 (4000h-7FFFh) only, and the A14 jumper on **A15**,
  so page 1 reads the lower half of the 27C256, where the programmer puts the
  16 KB `msxpibios.rom`. (With the jumper on A14 the MSX would read the empty
  upper half.) **Never CS12**: the ROM then also answers
  in page 2, the MSX finds its `AB` header twice and initialises it twice, and
  the second init chains EXTBIO to itself. MSX-DOS still boots and `msxarch`
  works, but every program that calls EXTBIO - `p`, `pcopy`, `pver` - hangs
  the machine with interrupts off (Caps Lock dead).
- **Pi server.** The older boards use GPIO 21/20/16/12/25, which is
  `msxpi-JumperLeft.ini`. They have no shutdown button, so leave
  `RPI_SHUTDOWN` unset (or empty) in `msxpi.ini`: the server then never
  configures GPIO 26. With the button enabled, glitches on the unconnected pin
  read as a press and rebooted the Pi in a loop.
- **SPI settling time on the v0.8.2 board.** Add `var GPIO_CS_SETUP_NS=1000`
  to `msxpi.ini`. The native GPIO engine clocked the first edge of each byte
  the moment CS went low, and on this board's hand-wired Pi connection that
  latched bytes still settling: checksum errors and `completed=1/512`
  transfer failures in both directions, and a corrupted handshake that asked
  for /WAIT bursts. A slower clock did not help; this delay did. Other boards
  leave it unset (0, the original timing). `MSXPI_GPIO_CS_SETUP_NS` in the
  environment overrides the ini value. Needs `native/libmsxpi_gpio.so`
  rebuilt on the Pi (`native/build.sh`).
- **`/WAIT` wiring, checked against each release's PCB layout.** Slot pin 7
  (`/WAIT`) goes to CPLD pin 28 on PCB V1.1 Rev.1 and V1.2.1b (pin map B), and
  to pin 37 on V1.3 Rev.1 (map C, releases v1.3 to v1.5); every other pin in
  those `.qsf` files matches its PCB too. Releases v0.8.2 and v1.0 both ran on
  PCB v0.7 Rev.7, where pin 8 drives the LED and nothing reaches slot pin 7,
  so they have a polled build only. (The v1.0 firmware's "/WAIT on the LED
  pin" never had a PCB behind it.)
  - The disk driver decides whether to use /WAIT by reading the CPLD register.
    It never tests the wire. So a /WAIT build on a board whose pin is not
    connected makes the driver use burst transfers that do not stall the Z80,
    and every sector fails its checksum.
  - The v0.8.2 board has only a polled build: its pin 8 drives the on-board LED
    through a resistor, not the slot line.
- **Server-status LED on the v0.8.2 board.** Pin 8 (`WAIT_n` on the other
  boards) drives the LED on this board, so its build sets `WAIT_PIN_IS_LED`:
  - off while `msxpi-server.py` is not running (before it starts, after it
    stops, after a shutdown)
  - while the server is online, the original activity light: lit while the
    Pi is ready (READY high), dark while it works on a command or a byte
    moves, so it flickers during transfers

  This follows READY much as the newer PCBs do: there the LED hangs straight
  off the READY line (R7), and R8 pulls READY low when the server is not
  running. The v0.8.2 board has no such pull-down, so the CPLD adds an online
  flag. The server sets it with one SCLK edge outside a transfer (MISO = 1)
  when it sets up the link, and clears it (MISO = 0) at a clean exit
  (Ctrl-C, SIGTERM, `p shut`, shutdown, a sync-error restart). Both are sent
  only while CS is high and READY is low. After `kill -9` the flag stays set
  until the restarted server sets it again.

  At exit the server keeps SCLK and MISO driven low: released, they float,
  and noise read as an "online" edge turned the LED back on. At shutdown
  `msxpi-monitor` exits on SIGTERM instead of restarting the server, and a
  server started while the Pi is stopping never announces online.

  There is no LED code in the transfer path: two announces per server run,
  nothing per block or byte. Every other CPLD build and every older firmware
  ignores these edges; the testbench checks that against v1.3. The LED needs
  this server version: with an older server it stays off.

## Build IDs ($57 bits 5-0)

`$57` layout: bit 7 is the /WAIT mode read-back, bit 6 is reserved and always
0 (it keeps the port below $FE, the openMSX marker), and bits 5-0 are the build
ID.

The ID field was 4 bits (`MSXPIVer`) until every value was used up. It is now
6 bits. The old bits 5-4 were always 0, so every existing ID reads exactly as
before, and the main v1.6 build still reads $0E / $8E. Every distinct firmware
image gets its own ID. Run `pver.com` on the MSX to print the board and build
name.

| ID | Firmware |
|---|---|
| $02 - $06 | Prototypes and sample PCBs, original firmware |
| $07 | v0.7 Rev.4 / v0.8.2 original |
| $09 | v1.0 original |
| $0A | v1.1 original (PCB v1.0.1) |
| $0B | v1.2 original (PCB v1.1/v1.2) |
| $0C | v1.2.1b original |
| $0D | v1.3 original (also shipped with v1.5) |
| $0E | v1.6 main build, pin map C, /WAIT |
| $10 | v1.6 for the v0.8.2 board, polled, server-status LED |
| $11 | retired - v1.0 ran on PCB v0.7 Rev.7, so it uses $10 |
| $12 | retired - that PCB has no /WAIT; never use |
| $13 | retired - `/WAIT` is wired on map B boards, so $14 is the only build |
| $14 | v1.6 for the v1.1 and v1.2.1b boards (map B), /WAIT |

Next free ID: $15. An ID identifies a board and firmware variant, not a
build: rebuilding or fixing a variant keeps its ID. Adding a new variant means
adding a row to this table and to the table in `software/Client/src/pver.c`. IDs go up to $3F. Bit 6 must never be
used.

## Verification

- `sim.sh` runs the differential testbench against the v1.3 reference. Choose
  the build with `PKG=...`, for example `PKG=v1.1/MSXPi_package_wait.vhd ./sim.sh`.
  All three builds pass: the main build, `v0.8.2/MSXPi_package_polled.vhd` and
  `v1.1/MSXPi_package_wait.vhd`.
  - Polled builds are checked as follows: identical to v1.3 apart from the ID,
    `$57` ignores the $01 write, and `WAIT_n` is never driven.
  - /WAIT builds run all six phases.
- Quartus 13.0sp1 fit (EPM3064ALC44-10):
  - v0.8.2 (polled, LED): 45/64
  - v1.1 (/WAIT): 53/64
  - main build: 46/64

  In no build does `wait_mode` appear as an inferred latch.
- Pin maps come from each release's original fitted `.pin` report.
  - `BUSDIR_n` is pinned explicitly: pin 6 on map A, pin 31 on map B.
  - The main build leaves `BUSDIR_n` unpinned, because pinning it to pin 31 (the
    pin the fitter picks anyway) grows the fit to 61/64. Check `MSXPi.pin` after
    each build.
- Hardware tests:
  - v0.8.2 board (PCB v0.7 Rev.7), `v0.8.2/MSXPi_v1.6_polled.pof` (ID $10, before the LED), MSX
    running Nextor with the MSXPi ROM disabled: `pver` reads ID $10, and
    `pver` and `p` commands reach the server. Needs `RPI_SHUTDOWN=none`
    (server fix `23bd98e`), otherwise the unconnected GPIO 26 reboots the Pi
    in a loop. The 27C256 ROM and MSX-DOS boot are not tested yet.
  - The v1.1 images (PCB V1.1 Rev.1 and V1.2.1b) are not tested on real boards yet.
- If the MSX never sends a byte (`PRINT INP(&H56)` stays 1 while the server
  is idle), the CPLD is not seeing RDY. Check GPIO 25 and its wire. The first
  v0.8.2 test failed because of a damaged GPIO 25 on the Pi.
