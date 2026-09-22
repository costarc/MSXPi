# MSXPi

MSXPi is a hardware interface and software solution that lets MSX computers
control and use Raspberry Pi resources. The interface exposes I/O ports that
the MSX reads and writes, and the data appears on the Raspberry Pi side, where
a Python program (the *msxpi-server*) acts on it. Through it the MSX can reach
network drives, the internet, disk images, ROM archives, ChatGPT, an IRC
server, TCP/IP (via UNAPI) and the Raspberry Pi itself. A Raspberry Pi Zero W
or Zero 2 W is the recommended companion board.

MSXPi also exists as a virtual device for **openMSX**: the emulated MSX gets
the same commands and the same server, with no hardware at all. See
[Quick Start 2 - openMSX](#quick-start-2---openmsx-no-hardware-needed).

Version 1.6 is the current release. What changed is in
[Release_Notes](Release_Notes); how to use everything is in the
[documents](documents) folder.

**Version 1.6 breaks software compatibility with previous ROMs and servers.**
Upgrade the whole set together: ROM, msxpi-server, the client commands (`.COM`
files) and, on real hardware, the CPLD firmware. A v1.6 ROM on older CPLD
firmware still works, using the slower polled transfers. If you must keep an
older ROM, the matching historical server is kept next to the current one,
named after the ROM's sha1, in `software/Server/Python/src`.

**About the DOS.** MSXPi's own ROM contains **MSX-DOS 1 (1.03) only**. It does not
contain Nextor or MSX-DOS 2. MSXPi *coexists* with them: Nextor or MSX-DOS 2 come
from another disk interface in the same MSX (for example a MegaFlashROM SCC+ SD),
and MSXPi's commands, BASIC extension and UNAPI work alongside them.

Contents

1. [How the pieces fit together](#how-the-pieces-fit-together)
2. [Quick Start 1 - Real hardware](#quick-start-1---real-hardware-msxpi-interface--raspberry-pi)
3. [Quick Start 2 - openMSX](#quick-start-2---openmsx-no-hardware-needed)
4. [Using MSXPi: the p commands](#using-msxpi-the-p-commands)
5. [Bugs and known limitations](#bugs-and-known-limitations)
6. [Repository structure](#repository-structure)


How the pieces fit together
===========================

    Real hardware:
    MSX  <-- I/O ports $56 $57 $5A -->  MSXPi interface  <-- GPIO -->  Raspberry Pi
    (p.com, pcopy, msxarch,             (CPLD + EEPROM with            (msxpi-server.py,
     BASIC CALL MSXPI, ROM BIOS)         the MSXPi ROM)                 Python 3)

    openMSX:
    MSX  <-- I/O ports $56 $57 $5A -->  MSXPiDevice      <-- TCP :5000 --> msxpi-server.py
                                        (emulated CPLD)                    (on your PC)

* **MSX side** - the ROM in the interface's EEPROM (`msxpibios.rom`: MSXPi
  BIOS, disk driver, `CALL MSXPI` for BASIC, Ethernet UNAPI) and the `.COM`
  programs that you copy to your MSX disk or SD card.
* **Interface** - a CPLD decodes ports $56/$57/$5A and shifts bytes to and
  from the Pi; since v1.6 it also holds the Z80 /WAIT line while a byte is in
  flight, so the MSX can move data with INIR/OTIR.
* **Server side** - `msxpi-server.py`, which runs on the Pi (GPIO link) or on
  your PC next to openMSX (TCP socket link). Everything it needs lives in one
  folder, the *MSXPi home directory*: `/home/pi/msxpi`.


Quick Start 1 - Real hardware (MSXPi interface + Raspberry Pi)
==============================================================

You will need:

* An MSXPi interface (built from `hardware/`; assembly notes in
  `documents/MSXPi Assembly Instructions.txt`) with an AT28C256 EEPROM.
* A Raspberry Pi Zero W / Zero 2 W (not a Pico - it cannot run Linux), with
  the 40-pin header on the side that matches your PCB, a micro SD card of 8 GB
  or more, and a PC to prepare it.
* An MSX with a disk or SD interface running MSX-DOS 1, MSX-DOS 2 or Nextor
  (MSXPi itself only has MSX-DOS 1 in its ROM; MSX-DOS 2 / Nextor must come
  from that other interface),
  and a way to copy files from your PC onto that disk. A second disk interface
  (Nextor / MSX-DOS 2) next to MSXPi is the best way to use it.
* Only if the CPLD is not programmed yet: an Altera USB-Blaster and Quartus
  13.0 SP1 on Windows.

Do the steps in order. Each ends with a check, so you know where a problem is.

### Step 1 - Program the CPLD (skip if it is already programmed)

1. Connect the USB-Blaster to the JTAG connector of the interface. The
   interface must be in the MSX slot and the MSX switched on.
2. In Quartus: Tools -> Programmer, mode JTAG, *Add File*, pick the `.pof` for
   your board, tick *Program/Configure* and *Verify*, *Start*.

   | Board | File (in `hardware/CPLD_Project`) |
   |---|---|
   | V1.3 Rev.1 (and boards built for v1.3 to v1.5) | `MSXPi_v1.6.pof` |
   | V1.1 Rev.1, V1.2.1b | `v1.1/MSXPi_v1.6_wait.pof` |
   | v0.8.2 / v1.0 (PCB v0.7 Rev.7) | `v0.8.2/MSXPi_v1.6_polled.pof` |

3. **Check:** in MSX BASIC, `PRINT INP(&H57)` must not print 254 or 255 (that
   means no CPLD answered); `pver` shows the same build ID in readable form later. Older boards need a few extra settings - see
   `hardware/CPLD_Project/LEGACY_BOARDS.md` and `documents/Legacy Support.odt`.

### Step 2 - Write the ROM to the EEPROM with AT28C256.COM

The EEPROM holds `msxpibios.rom` (16 KB). It is written from the MSX itself,
so you need a working MSX with a disk drive and the interface plugged in. The
Raspberry Pi does not need to be attached yet.

1. Copy `software/target/at28c256.com` and `software/target/msxpibios.rom` to
   your MSX disk or SD card.
2. Boot MSX-DOS (from your disk interface) and list the ROMs the tool can see:

        at28c256 /i

   If the interface already holds a bootable ROM, remove its enable jumper
   (`SLTSL`, `CS12` on some boards) first, otherwise the MSX finds it, boots
   from it and the tool cannot write. Note the slot number of the interface.
3. Write the ROM (2 is the slot number here; use yours):

        at28c256 /s 2 msxpibios.rom

   The tool write-protects the EEPROM (software data protection) when it is
   done. If your chip fails to program, repeat with `/r`, which writes slowly.
   The chip is 32 KB: two 16 KB ROMs can share it and be chosen with the
   A14/A15 bank jumper, if you merge them into one file first.
4. Switch the MSX off and set the jumpers for how you will use it:

   * **With another disk interface (recommended):** remove the enable jumper
     (`SLTSL`). The MSXPi ROM (and its MSX-DOS 1) is off, the MSX boots Nextor / MSX-DOS 2 from the
     other interface, and MSXPi still works through the `.COM` commands.
     (The ROM must be enabled for `CALL MSXPI` in BASIC and for the Ethernet
     UNAPI; if you want them, leave the jumper closed and put MSXPi in a higher
     slot than the disk interface.)
   * **Booting MSX-DOS 1 from a disk image on the Pi:** close `SLTSL` and
     select the bank that holds the MSXPi ROM. The Pi must finish booting
     first, so the first cold boot takes a few minutes. Press ESC during boot
     to go straight to BASIC.
5. **Check:** in BASIC (ROM enabled), `CALL MSXPIVER` prints the ROM version.

### Step 3 - Prepare the Raspberry Pi

Choose one.

**3a. Ready-made SD card image (easiest).** (This SD card is outdated, and will require the msxpi-setup.sh to be run to update it to latest code - refer to 3b step 2 below to make this update) - Download from
https://tinyurl.com/MSXPi-SDCardV3, unzip with 7-Zip and write to the SD card
with Win32DiskImager (https://win32diskimager.org) or Raspberry Pi Imager
("Use custom"). Insert the card in the Pi.

**3b. Fresh Raspberry Pi OS Lite (32-bit).**

1. Write *Raspberry Pi OS Lite (32-bit)* to the SD card with Raspberry Pi
   Imager (https://www.raspberrypi.com/software). In its settings choose user
   name `pi`, enable SSH and enter your WiFi details.
2. Boot the Pi, log in (SSH, or keyboard and HDMI) and run:

        wget https://tinyurl.com/MSXPi-Setup
        chmod 755 MSXPi-Setup
        bash ./MSXPi-Setup

   The script checks the Pi, the network and the clock, installs everything
   below, starts the server, checks that it runs, and reboots (a few minutes).
   It asks which board you have; to skip the question add `--board v1.3`,
   `--board v1.1` or `--board old` (see the table below). `--help` lists the
   other options (WiFi, `--no-reboot`, ...). It is safe to run again: it
   updates the server and repairs what is missing, and never overwrites
   `msxpi.ini`.

What the setup gives you (check it, or do it by hand):

* **Python 3** with the modules `requests`, `fs` and `RPi.GPIO`. `fs` needs
  `pkg_resources`, so a `setuptools` older than version 81 must be present
  (`python3 -m pip install fs "setuptools<81" --break-system-packages` if you do it
  by hand). The packages `unar`, `lhasa`, `unzip`, `music123`, `alsa-utils` and
  `smbclient` are for unpacking archives, playing audio and reading network
  shares; `iptables` gives the MSX its network; `gcc` builds the native GPIO
  engine.
* **The MSXPi home directory `/home/pi/msxpi`**, owned by user `pi`. The path is
  built into the server. It holds:

  | File | Purpose |
  |---|---|
  | `msxpi-server.py`, `mapper_detect.py`, `msxpi_eth.py`, `msxpi_gpio_native.py` | the server and its modules |
  | `native/` | the native GPIO library `libmsxpi_gpio.so`, built on the Pi (without it the server falls back to slower Python GPIO and says so in its log) |
  | `msxpi.ini` | your settings, see below |
  | `disks/msxpiboot.dsk`, `disks/tools.dsk` | drives A: and B: for the MSX-DOS 1 boot mode |
  | `msxpi-tcpip-setup.sh`, `kill.sh`, `pplay.sh` | helpers |

* **A systemd service** (`msxpi-monitor`) that starts the server at boot. To
  watch it work, run it by hand: `cd /home/pi/msxpi && python3 msxpi-server.py`.
* **msxpi.ini**, copied from the template that matches your PCB
  (`software/Server/Python/src`):

  | Board | Template |
  |---|---|
  | V1.3 (and later) | `msxpi-JumperRight.ini` |
  | V1.1 Rev.0 | `msxpi-JumperRight_PCBV1.1Rev.0.ini` |
  | Older boards | `msxpi-JumperLeft.ini` |

  A board **without** the shutdown push-button needs `var RPI_SHUTDOWN=none`.
  Optional keys: `OPENAIKEY` and `OPENAIMODEL` (ChatGPT), `RAPIDAPIKEY`,
  `FINNHUBKEY`, `TWELVEDATAKEY`, `ALPHAVANTAGEKEY` (stock quotes),
  `WIFISSID`, `WIFIPWD`, `WIFICOUNTRY`. From the MSX you can change any of
  them with `p set NAME value`.

Insert the SD card, plug the Pi into the interface **with its component side
facing you**, and switch the MSX on. The interface LED lights when the server
is running.

### Step 4 - Copy the MSX-side programs

Copy the contents of `software/target` (at least `p.com`, `pcopy.com`,
`pver.com`, `msxarch.com`, `msxarch.ini`, `LOADROM.COM`, `INL.CFG` and the
`.BAS` programs) to your MSX disk or SD card.

**Check:** at the MSX-DOS prompt type

        pver

It prints the board (build ID, CPLD, `/WAIT` yes or no) and the server version.
"Connection error" means the Pi is still booting (the first boot may take three
minutes), the interface is not seated, or the ROM and server versions do not
match. Press ESC, wait five seconds, and try again.

### Step 5 - Connect to WiFi and the network

        p set WIFISSID Your Wifi Name
        p set WIFIPWD YourWifiPassword
        p wifi set
        p reboot

`p wifi` alone lists the interfaces and addresses. For TCP/IP programs (UNAPI:
InterNestor Lite, telnet, HGET) the Ethernet driver is in the ROM, and the Pi
builds the network behind it with `msxpi-tcpip-setup.sh` when the server
starts. If the Pi had no default route at boot, run `p netreset`. Then:

        MSR I           (MSX-DOS 1 only - do NOT run RAMHELPR)
        INL I
        HOST GOOGLE.COM

`HOST` printing an address means the whole path works. `p wlanreset` resets the
Pi's WiFi. Details: `software/UNAPI/README.md`.

### Step 6 - Try it

        p dir /home/pi/msxpi
        p run uname -a
        pcopy m:pver.com
        msxarch                     (browse and start ROM games from the network)
        LOADROM game.rom /N
        p chatgpt Tell me a fun fact about MSX

### Updating

* MSX disk (the `.COM` files): run `msxpiupd.bat` (network required).
* Server: run the setup script again, from the Pi or from the MSX:

        p run wget https://tinyurl.com/MSXPi-Setup
        p run chmod 755 MSXPi-Setup
        p run sudo ./MSXPi-Setup

* ROM: the updater downloads it but never writes it - repeat Step 2.

Update all three together. Run `p shut` before you switch the MSX off: the Pi is
powered by the MSX, and an SD card can be corrupted by a sudden power cut.

More detail with pictures: `documents/Quick Start.odt` and the two tutorials
("Easy Way" with the ready-made image, "Hard Way" from scratch; Portuguese
versions available) in the `documents` folder.


Quick Start 2 - openMSX (no hardware needed)
============================================

The MSXPi device for openMSX emulates the interface, including the CPLD /WAIT
flow control, and talks over a local TCP socket to the same `msxpi-server.py`
that runs on the Pi. The p commands, BASIC, msxarch, ChatGPT and UNAPI
networking all work as on real hardware, and what you write under openMSX runs
unchanged on the real interface.

### Step 1 - Install openMSX with the MSXPi device

The official openMSX lives at https://github.com/openMSX/openMSX
(binaries and documentation at https://openmsx.org). The MSXPi device is not in
the official build yet, so download openMSX from the MSXPi fork instead:

* **https://github.com/costarc/openMSX/releases** - take the newest release for
  your operating system; the notes of each release say what it contains. Unpack
  it anywhere. It includes the MSXPi extension (`MSXPi.xml`) and the matching
  `msxpibios.rom`.
* Use the fork release, the `msxpibios.rom`, and the server from the same MSXPi
  version - the device, ROM and server share one protocol.
* If you keep your own openMSX, the two data files are also in this repository:
  `software/openMSX/share/extensions/MSXPi.xml` goes to openMSX's
  `share/extensions`, and `software/openMSX/share/systemroms/extensions/msxpibios.rom`
  goes to `share/systemroms/extensions`. The `MSXPiDevice` itself is only in
  builds of the fork.

### Step 2 - Python and the MSXPi home directory

* **Python 3** (3.9 or newer; on Windows from python.org or the Microsoft
  Store, with *Add to PATH*).
* **Python modules:** `python -m pip install requests fs "setuptools<81"` (`fs`
  needs `pkg_resources`, which `setuptools` 81 and later no longer has). If the
  server complains about another module when it starts, install that too.
* **7-Zip** (`7z.exe` on the PATH) for zip, lzh, pma and 7z archives, used by
  msxarch and `pcopy /z`. On Linux/macOS install `p7zip`, `lhasa` and `unar`.
* **The MSXPi home directory.** The server has `/home/pi/msxpi` built in. On
  Linux and macOS create that folder. On Windows the path resolves on the
  *current drive*, so create `C:\home\pi\msxpi` and start the server from drive
  C:. Put in it: `msxpi-server.py`, `mapper_detect.py` and `msxpi_eth.py`
  (from `software/Server/Python/src`), `msxpi.ini` (copy `msxpi-JumperLeft.ini`
  and rename it), and a `disks` folder with `msxpiboot.dsk` and `tools.dsk` from
  `software/target/disks`.
* Add the keys you need to `msxpi.ini` (for example `OPENAIKEY` for ChatGPT).
  Commands that only make sense on a Pi (`wifi`, `reboot`, `shut`, `play`) answer
  "Command not supported on this platform".

**Windows shortcut:** right-click
`software/Server/Setup/msxpi-windows-setup.ps1` and choose *Run with
PowerShell*. It installs Python and 7-Zip (with winget), the modules,
`C:\home\pi\msxpi`, openMSX with the MSXPi files, the TAP driver, and a
`start-msxpi.ps1` launcher with a desktop shortcut. Running it again is safe.

### Step 3 - Start the server, then openMSX

        cd C:\home\pi\msxpi           (Linux/macOS: cd /home/pi/msxpi)
        python msxpi-server.py

The server listens on TCP port **5000**. Now prepare a folder that openMSX uses
as disk A:. Call it `FloppyA`, copy `MSXDOS.SYS` and `COMMAND.COM` from
`software/target/disks` into it, and add the MSXPi commands from
`software/target`. Then start openMSX with the extension:

        openmsx -machine Panasonic_FS-A1WSX -ext MSXPi -diska FloppyA

Any MSX2 with 64 KB RAM will do, and Nextor on an SD/IDE image works too.
The fork also has an `MSXPiNoROM` extension (the ports without the ROM), for
trying `BLOAD"MSXPIEXT.BIN",R` the way an interface without an EEPROM is used.

**Optional: a different port.** The device takes the TCP port from the openMSX
setting `msxpiserver_port` (default 5000). Change it in the openMSX console
(F10) and the device reconnects at once:

        set msxpiserver_port 5001

Make the server listen on the same port by changing the `PORT` value near the
top of `msxpi-server.py`. Use this when port 5000 is taken, or to run two
emulators with two servers.

### Step 4 - Try it

At the MSX-DOS prompt:

        pver
        p dir /
        p set
        msxarch
        p chatgpt Tell me a funny fact about MSX

`pver` reports `/WAIT: yes (burst)` when the device emulates the wait flow
control. "Connection error" means the server is not running, the ports differ,
or the ROM and server versions do not match. Read the log window of the server:
it prints every command it receives.


### Internet from the MSX in openMSX (Windows)

The MSXPi extension carries real network traffic, so InterNestor Lite, telnet,
HGET and the other UNAPI clients work in the emulator exactly as they do on
hardware. The emulated MSX gets its own subnet (192.168.99.0/24) and Windows
NATs it out through whichever interface carries your default route - the same
arrangement the Raspberry Pi uses, and for the same reason: bridging cannot
work over WiFi, because an access point will not forward frames whose source
MAC is not the associated station's.

This works best with an openMSX whose MSXPi device implements the v1.6
hardware /WAIT flow control (openMSX/openMSX#2194). An older build still
works: the ROM probes for wait mode, does not find it, and falls back to the
polled transport - the same path MSXPi has always used under emulation. What
you lose is the v1.6 speedup, not the connection.


#### Step 1: Install the OpenVPN TAP driver

Install OpenVPN (https://openvpn.net/community-downloads/) and keep the "TAP
Virtual Ethernet Adapter" component, or install the standalone tap-windows6
driver on its own. Afterwards an adapter named "OpenVPN TAP-Windows6" appears
in Network Connections - nothing else about OpenVPN is used or needs
configuring.


#### Step 2: Run the setup once, as Administrator

From an elevated PowerShell:

          powershell -ExecutionPolicy Bypass -File software/Server/Setup/msxpi-tcpip-setup.ps1

It reports what it did:

          adapter: OpenVPN TAP-Windows6  [TAP-Windows Adapter V9]
          uplink: Wi-Fi
          OpenVPN TAP-Windows6 up: 192.168.99.1/24 mtu 576
          NAT: 192.168.99.0/24 -> Wi-Fi
          dns: 192.168.1.254

and prints the InterNestor Lite settings to match. Note the "dns:" line - that
is the resolver the MSX should use.

This is NOT persistent across reboots; re-run it after a restart. To undo it
and give the adapter back to OpenVPN, add "-Down".

Windows generally allows only one NAT instance, and Docker Desktop, Hyper-V and
WSL each take one. If something already holds it the script names it and stops
rather than half-configuring.


#### Step 3: Start the server

          python msxpi-server.py

No administrator rights are needed for this part. It should print:

          eth: TAP device OpenVPN TAP-Windows6 up

If it says "TAP unavailable ... falling back to MockLink", something else has
the adapter open - a running OpenVPN session will do that. MockLink answers
every UNAPI call correctly and carries no traffic at all, so the MSX will look
configured and reach nothing.


#### Step 4: On the MSX

Start openMSX with the MSXPi extension, then:

          MSR I              (MSX-DOS 1 only - see below)
          INL I
          HOST GOOGLE.COM

`HOST` printing an address means the whole path works. The Ethernet UNAPI
driver is in msxpibios.rom, so nothing needs installing first: ETHUNAPI will
refuse, because the ROM already registers an ETHERNET implementation.

**Do not run RAMHELPR I.** It installs the UNAPI RAM helper on its own, and
MSR.COM installs the mapper support routines AND a helper - so MSR then finds a
helper already present and aborts, leaving INL to fail with "No mapper support
routines found". A cold boot clears it. Under Nextor or MSX-DOS 2, skip MSR
entirely: the mapper routines are already there.

If `HOST` answers "8: DNS not found" but the link is otherwise up, the resolver
is the problem rather than the network - INL.CFG ships with 1.1.1.1, and some
networks block public resolvers. Use the address the setup script printed:

          INL IP P 192.168.1.254

Using MSXPi: the p commands
===========================

Type `p` with no arguments (or `p /help`) to list them. All work under MSX-DOS 1,
MSX-DOS 2 and Nextor. Paths can be on the Pi, on the network (http, https, ftp,
smb) or on one of the virtual drives set with `p set`: `m:` (your local
server), `r1:` and `r2:` (MSX1 and MSX2 ROMs on msxarchive.nl).

| Command | What it does |
|---|---|
| `p ver`, `pver` | server version; `pver` also shows the board, CPLD build and /WAIT support |
| `p cd`, `p dir` | change and list the current path |
| `p run <cmd>` | run a command on the Pi; use `::` for a pipe |
| `p date` | set the MSX date and time from the Pi |
| `p set [NAME value]` | show or change MSXPi variables (saved in `msxpi.ini`) |
| `p wifi`, `p wifi set` | list interfaces / apply WIFISSID and WIFIPWD |
| `p wlanreset [secs]`, `p netreset [secs]` | reset the Pi's WiFi / rebuild its TCP/IP setup for UNAPI |
| `p play`, `p vol` | audio playback and volume on the Pi |
| `p reload A:` (or `B:`) | reload a drive's disk image |
| `p reboot`, `p shut`, `p restart` | reboot / shut down the Pi, restart the server |
| `p chatgpt <question>` | ask ChatGPT (needs OPENAIKEY) |
| `pcopy` | copy Pi/network file to the MSX drive (`/z` unpacks archives) or an MSX file to the Pi |
| `msxarch` | browse ROM repositories (listed in `MSXARCH.INI`) and start a game |
| `LOADROM name /N` | load a plain ROM or MegaROM from the network |
| `at28c256` | write the interface EEPROM |
| `msxpiupd.bat` | update the MSX-side files |

From BASIC use `CALL MSXPI("1,C000,dir /home/pi/msxpi")` (see `target/API.BAS`).
The full reference, with examples, is in `documents/MSXPi Users and Developers Guide.odt`.


Bugs and known limitations
==========================

* **Upgrade as a set.** A v1.6 ROM, server, `.COM` files and CPLD are meant to
  be used together. Mixed versions usually show up as "Connection error", not as
  a clear refusal.
* **/WAIT bursts need a v1.6 CPLD image and a board that wires /WAIT.** Boards
  built for v0.8.2 and v1.0 (PCB v0.7 Rev.7) have no /WAIT connection and run
  the polled transfers only. At the time of writing, disk writes from the MSX
  also use the polled transfer while reads use bursts.
* **Older boards need settings**: `RPI_SHUTDOWN=none` without the push-button,
  and `GPIO_CS_SETUP_NS=1000` on the v0.8.2 board. On that board the EPROM
  /OE jumper must be on CS1, never CS12, or programs that call EXTBIO (`p`,
  `pcopy`, `pver`) hang the MSX. See `hardware/CPLD_Project/LEGACY_BOARDS.md`.
* **MSXPi only carries MSX-DOS 1.** Nextor and MSX-DOS 2 are not in the MSXPi
  ROM; they run from another disk interface that MSXPi coexists with.
* **Booting MSX-DOS 1 from the Pi is slow and fragile.** It needs the Pi to
  finish booting first and depends on the disk images; use another interface
  with Nextor or MSX-DOS 2 for daily work. Do not delete files on drive A: in
  that mode.
* **A stuck transfer needs ESC.** Press ESC to abort, wait about five seconds
  while the server resynchronises, and retry. If commands keep failing, restart
  the server (`p restart`) or reboot the Pi.
* **msxarch and MegaROMs.** Mappers detected: plain, Konami, Konami SCC, ASCII8
  and ASCII16. Other mappers, ROMs that need more RAM than the MSX has, and some
  titles that rewrite their own bank switching are rejected with a reason or may
  not run. Bank-switch writes are patched by the server, so what runs is not byte-for-byte the original ROM.
* **UNAPI/TCP/IP.** Do not run `RAMHELPR` before `MSR` under MSX-DOS 1 (INL then
  fails with "No mapper support routines found"; a cold boot clears it). If
  `HOST` answers "8: DNS not found" the resolver, not the link, is the problem:
  use `INL IP P <address>`. Under openMSX on Windows the TAP setup script must be
  run again after every reboot, only one Windows NAT instance can exist (Docker
  Desktop, Hyper-V and WSL each take one), and if the server prints "falling back
  to MockLink" the MSX looks configured but reaches nothing.
* **The server on Windows and macOS** runs the commands that make sense there;
  `wifi`, `reboot`, `shut`, `play` and `vol` are Raspberry Pi only.
* **Hardware compatibility.** Some MSX models have unusual slot or bus
  implementations and may not work; MSX-DOS needs 64 KB RAM. The Pi header must
  face the correct way for your PCB (a Zero WH has its header on the wrong side
  for the standard PCB).
* **ChatGPT and stock commands** need your own API keys in `msxpi.ini`; no key
  ships with MSXPi.
* **Regression tests** are not carried on the release branch; they live in
  `software/Tests` on the development branches.
* The PDF copies of the documents in `documents` may be older than the `.odt`
  files.

Report problems at https://github.com/costarc/MSXPi/issues.


Repository structure
====================

Branches:

    master          the most recent code; may change within minutes - expect bugs,
                    and fixes just as fast
    release/vX.Y    one branch per release (v0.8.2, v1.0, v1.1, v1.2.1b, v1.3,
                    v1.4, v1.5, v1.6); use these for a known-good state
    feature/*, fix/*, docs_*
                    short-lived working branches; they appear and disappear, and
                    I recommend you do not use them

Directories:

    MSXPi
    |-- software
    |   |-- asm-common
    |   |   |-- include          BIOS routines for assembly (msxpi_bios.asm, include.asm, ...)
    |   |   `-- transport        generator for the /WAIT burst transfer code
    |   |-- C-common
    |   |   |-- header           msxpi.h - the C BIOS API
    |   |   `-- lib              msxpi-bios.c and the compiled library
    |   |-- ROM/src
    |   |   |-- BIOS             CALL MSXPI for BASIC (msxpiext.asm, MSXPIEXT.BIN)
    |   |   `-- MSX-DOS          disk driver and MSX-DOS 1 kernel sources
    |   |-- Client/src           p, pcopy, pver, msxarch, templates, at28c256
    |   |   `-- loadrom          the LOADROM.COM network patch
    |   |-- Server
    |   |   |-- Python/src       msxpi-server.py, mapper_detect.py, msxpi_eth.py,
    |   |   |                    ini templates, native GPIO engine
    |   |   |-- Shell            setup scripts (Pi and Windows), msxpi-monitor
    |   |   `-- systemd          service unit
    |   |-- UNAPI                Ethernet UNAPI: sources, tools, INL, documentation
    |   |-- openMSX              MSXPiDevice source, extension XML, ROMs, README
    |   |-- target               everything you copy to the MSX (.COM, .BAS, ROM, disks)
    |   |-- VirtualDrive         virtual drive hook sources
    |   |-- Tests                regression tests (development branches)
    |   `-- docs                 mapper and ROM design notes
    |-- hardware
    |   |-- CPLD_Project         VHDL, Quartus project, .pof images for every board
    |   `-- Schematic            KiCad schematic and PCB, Fabrication, BOM
    `-- documents                Users and Developers Guide, Quick Start,
                                 Legacy Support, tutorials
