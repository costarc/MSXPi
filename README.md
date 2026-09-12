# MSXPi

MSXPi is a hardware interface and software solution to allow MSX computers 
to control and use Raspberry Pi resources. The interface exposes I/O ports 
that can be read and written by MSX, and in turn the data will be accessible 
on the Raspberry Pi. Many resources are implemented, such as access to 
network drives, internet, disk images, and the Raspberry Pi itself. To make 
the most of MSXPi resources, a Raspberry Pi Zero W should be attached to the 
interface.

* MSXPi is Now Available for openMSX! 
A virtual MSXPi device is now available for openMSX, allowing the emulated 
MSX to perform all the cool tricks MSXPi hardware can perform, such as 
browse internet in text mode, connect to IRC, check the weather or ask
ChatGPT for help do develop your MSX programs.

Read for and learn how to start using MSXPi extension in the openMSX section
below.

Quick Start Guide
=================

Version 1.6 breaks software compatibility with previous ROMS and server.
Upgrade the whole pack (ROM, msxpi-server and client commands), and this time
the CPLD firmware too: v1.6 adds hardware /WAIT flow control, which is what
makes the new burst transfers possible, and the earlier firmware cannot drive
them. A v1.6 ROM on older firmware falls back to the polled transfers and
still works, only slower.

If you need to run an older ROM, the matching server is kept alongside the
current one, named after that ROM's sha1 - see
"software/Server/Python/src/READ.md".

The documentation is very outdated - for reference, look the new source code,
they have plenty of information for developers.

This Quick Start Guide is updated to V1.2 of the Software and Interface.

Please refer to the full documentation under "documents" folder in github 
for detailed setup procedure and other information.

There are a few steps to setup MSXPi, and you can choose between using a 
MSXPi pre-installed SD Card image (ready to boot MSXPi), or build your own 
image using a fresh Raspbian Image downloaded from Raspberry Pi web site - 
both methods are described below.

Overall, the steps to get up and running are:

- Setup Raspberry Pi with the server-side software (Raspberry Pi SD Card)
- Setup MSX with the client side software (MSX SD Card / disk drive)


Prepare Raspberry Pi Using MSXPi SDCard Image
=============================================


### Step 1: Download and install Raspberry Pi SD Card with MSXPi server software. 
MSXPi SD Card image: https://tinyurl.com/MSXPi-SDCardV3


### Step 2: Write the image to a SD Card
Use a SD Card with a minimum of 4GB.

Use 7Zip to unzip the file, and use Win32diskImager to write the image to 
the SD Card.

Win32diskImager can be download from https://win32diskimager.org


### Step 3: Install the MSXPi commands for MSX-DOS

In your favourite PC computer, copy all MSXPi commands from 
https://github.com/costarc/MSXPi/tree/master/software/target to your MSX 
SD card or Disk.

After this basic setup, you should be able to use the MSXPi ".com" commands 
from your MSX. To unleash full MSXPi power, configure the 
Raspberry Pi Zero W WiFi:

          p set WIFISSID Your Wifi Name
 
          p set WIFIPWD YourWifiPassword
 
          p wifi set
 
          p reboot
 
 Note: The first reboot may take longer than 3 minutes, because Raspbian will 
 expand the filesystem in the SD and initialise the Linux system - following 
 reboots will be faster)

In case you need very detailed instructions, please read  "Tutorial - Setup 
Raspberry Pi for MSXPi the Easy Way - Using the MSXPi Pre-Installed Image.pdf", 
in https://github.com/costarc/MSXPi/tree/master/documents (Portuguese version 
also available).


Prepare Raspberry Pi Using a Fresh Raspbian Image
=================================================


In this mode, you will have to install all requirements for MSXPi - there is a 
script to help you with that, though.

### Step 1: Download the Raspberry Pi Imager
Download from https://www.raspberrypi.com/software

This is the official Raspberry Pi SD Card image writer - download and install in 
your desktop PC.

### Step 2: Write the Raspbian image to the SD Card
Run the Pi Imager software, and select the best  OS for your raspberry pi. If you 
are using the recommended Raspberry Pi Zero W, choose the lite version (without 
graphical desktop):

        CHOOSE OS -> Raspberry Pi OS Lite (other) -> Raspberry Pi OS LITE (32-bit)

Write the image to your SD Card and when completed, boot the Raspberry with the 
SD Card inserted.

### Step 3: Setup MSXPi using MSXPI-Setup tool
You will need to connect the Raspberry Pi to a HDMI TV and a keyboard to complete 
these steps.

Login to Raspbian using default user and password: pi / raspberry

Configure the WiFi using raspi-config command

Download the MSXPi setup script - it will download and install everything
needed to have MSXPi up and running the following commands - but note: the finals 
stages of the setup installs OPENAI library (the "Install Additional Python 
libraries required by msxpi-server" section the reboot command), which requires 
compilation - this stage may take over an hour if done in the Pi Zero, therefore 
you may choose to remove these from the MSXPI-Setup script before running it, and 
do it at later time if you want to use ChatGPT with MSXPi.

          wget https://tinyurl.com/MSXPi-Setup

          chmod 755 MSXPi-Setup

          bash ./MSXPi-Setup
          
If you need very detailed instructions, please read 
"Tutorial - Setup  Raspberry Pi for MSXPi the Hard Way - 
Installing Raspbian from Scratch.pdf", in 
https://github.com/costarc/MSXPi/tree/master/documents 
(Portuguese version also available).


MSXPi in openMSX
================
The MSXPi extension allows you to connect a virtual MSXPi to your MSX 
running in the openMSX, and use the same commands found in the physical
MSXPi running in real hardware.

It works by implementing a MSXPi Device that listen to the I/O ports allocated
for MSXPi and forwarding the data to a local TCP socket, which is implemented
by a Python program (the msxpi-server). The MSXPi device also works for data
send by the Python program, that is, reading the responses and forwarding to
the MSX computer, just like the real thing.

There are some difference in the Python code that runs along with openMSX and
the Python server that runs in the Raspberry Pi - specifically, the low-level
byte transfer which uses GPIO in the Raspberry Pi, and Socket communication
in the openMSX solution, but other than that, the remaining code should be
the same and work on both platforms.

To have MSXPi in you openMSX, download the binary for your operating system from
the latest release in the MSXPi Extension official repository:
https://github.com/costarc/openMSX/releases

Follow the instructions in:
https://github.com/costarc/openMSX/blob/master/Contrib/README.MSXPi

MSXPi specific documentation is available in the MSXPi repository:
https://github.com/costarc/MSXPi/tree/master/documents

Internet from the MSX in openMSX (Windows)
=========================================

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


### Step 1: Install the OpenVPN TAP driver

Install OpenVPN (https://openvpn.net/community-downloads/) and keep the "TAP
Virtual Ethernet Adapter" component, or install the standalone tap-windows6
driver on its own. Afterwards an adapter named "OpenVPN TAP-Windows6" appears
in Network Connections - nothing else about OpenVPN is used or needs
configuring.


### Step 2: Run the setup once, as Administrator

From an elevated PowerShell:

          powershell -ExecutionPolicy Bypass -File software/Server/Shell/msxpi-tcpip-setup.ps1

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


### Step 3: Start the server

          python msxpi-server.py

No administrator rights are needed for this part. It should print:

          eth: TAP device OpenVPN TAP-Windows6 up

If it says "TAP unavailable ... falling back to MockLink", something else has
the adapter open - a running OpenVPN session will do that. MockLink answers
every UNAPI call correctly and carries no traffic at all, so the MSX will look
configured and reach nothing.


### Step 4: On the MSX

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

MSXPi v1.6 Release Notes
========================
Hardware /WAIT flow control for data transfers, Ethernet UNAPI in the ROM, and
MSX-DOS 2 / Nextor compatibility. ROM, msxpi-server and the client commands
must be upgraded together, and the CPLD firmware moves to v1.6 - the /WAIT
logic is new, so the previous firmware cannot drive burst transfers.

Transfer speed
- The CPLD now asserts /WAIT while a byte is in flight, so the MSX moves payloads with INIR/OTIR at 21 T-states per byte instead of polling the status port for every one. The Pi holds RPI_READY high for the whole run (SPI_BurstOut / SPI_BurstIn) - without that, the gap between bytes would let a block instruction read a stale byte and silently desynchronise the stream.
- Both ends negotiate it per block: the MSX marks the block size it asks for, the server marks the length it answers with, and either side declining falls back to the polled path. A checksum retry never bursts.
- Measured on a Canon V-25 with real hardware: 256 KB in 51.95 s, down from 1:45.00.
- The native GPIO payload engine is now on by default (MSXPI_NATIVE_GPIO=1) in msxpi-monitor and in both systemd units; without the native library the server falls back to Python GPIO and says so in the log.

MSX-DOS 2 / Nextor
- GETDPB returned with the carry flag as the caller happened to pass it in, so Nextor read a perfectly good DPB as a failure: every access through a MAPDRV'd MSXPi drive answered "Not a DOS disk". It now clears carry explicitly.
- DSKIO staged every sector through the driver's own buffer. Transfers now go directly to the caller's buffer when it is outside page 1, and through the kernel's XFER routine when it is not - page 1 is where the driver ROM is banked in, so the driver cannot see the caller's memory there. This is what produced "Bad file allocation table" on larger copies.
- Tests/p1test/P1TEST.COM is a 40 KB self-checking program for exactly that case, for use on real hardware.

Ethernet UNAPI
- The Ethernet UNAPI implementation is in msxpibios.rom, so InterNestor Lite installs with no helper: RAMHELPR is not needed and ETHUNAPI refuses, because the ROM already registers an ETHERNET implementation.
- Pi side: msxpi_eth.py shuttles frames over a TAP device (msxpi0), and Server/Shell/msxpi-tcpip-setup.sh creates it, owns it as the server's user, and sets up routing and NAT to whichever interface carries the default route. The MSX sits on an isolated subnet behind NAT because an access point will not forward frames whose source MAC is not the associated station's - bridging cannot work over WiFi.
- ethtrans.asm uses the same /WAIT burst path as the disk transfers.
- DSKIO only asks for /WAIT bursts once wait mode has actually engaged, so an openMSX without the v1.6 MSXPi device still works, on the polled transport.
- Windows, under openMSX: the same ROM driver reaches a real network there too. msxpi_eth.py opens an OpenVPN TAP-Windows adapter (WinTapLink) and Server/Shell/msxpi-tcpip-setup.ps1 does what the shell script does on the Pi - the address, forwarding, and a WinNAT instance for the MSX's subnet. Opening the adapter needs no administrator rights; only that one-time setup does. InterNestor Lite installs and resolves names from the emulated MSX, so telnet, HGET and the rest work in the emulator as they do on hardware.

New and changed client commands
- "p netreset [secs]" rebuilds the Pi's whole TCP/IP setup from the MSX - tear down the TAP and the iptables rules, run the setup again, and reopen the link - for the case where the Pi had no default route when it booted and the MSX therefore has no network at all. Optional argument is how long to wait for a default route (default 15 s, capped at 60). "p tcpip" is an alias.
- "p wifi" listed interfaces by filtering "ip a" for lines starting 1 to 4, so an interface numbered 5 or above lost its header line and its address appeared to belong to the interface above it. It now builds the list itself: one 40-column line per address, with the interface name and state.
- "p wlanreset [secs]" resets wlan0 from the MSX: drops the lease, cycles the WiFi radio, and asks NetworkManager, dhcpcd or dhclient - whichever owns the interface - to reconnect, then waits for a fresh IPv4 address (default 30 s, 5 to 90). It does not touch msxpi0 or NAT, so run "p netreset" afterwards if the uplink address changed.

Server
- PerformHandshake ended by restoring the caller's flags, so it reported the carry it was entered with rather than its own result: a failed handshake could look successful, and the caller then read a block nobody was sending.
- SPI_BurstIn - the receive half of the burst path - was missing, so every burst write died with "name 'SPI_BurstIn' is not defined" and left the driver mid-block.
- The Ethernet link is no longer chosen once and kept for the life of the process. If msxpi0 is not ready when the first UNAPI opcode arrives - msxpi-monitor starts the setup script in the background, so that is a race - the server retries and swaps the real TAP in when it appears, instead of answering every opcode correctly while carrying no traffic at all.
- Historical servers are kept alongside the current one, named after the sha1 of the ROM they pair with; see Server/Python/src/READ.md.
- When openMSX exited, five loops waiting for the MSX retried the closed connection forever, flooding the console, and the server never got back to accepting. They now give up on a closed connection (timeouts still wait; the Pi's GPIO link is unaffected). That exposed a second bug: every reconnect opened port 5000 again while the first listener was still bound, so the first reconnect killed the server with "Address already in use". The listener is now opened once.
- The API keys the stock demo uses are no longer in the source: set RAPIDAPIKEY, FINNHUBKEY, TWELVEDATAKEY and ALPHAVANTAGEKEY in msxpi.ini ("var RAPIDAPIKEY=..."). The jumper .ini files list these names with placeholder values. The archived server copies had the old keys in plain text; they are blanked there too - anyone who used them should reissue their own.
- The per-sector disk read line and the debug timestamps are gone from the log.

Pi network setup (msxpi-tcpip-setup.sh)
- The uplink was read from a fixed field position of "ip route show default", which is the interface only when the route has a gateway. A gatewayless route reads "default dev wlan0 scope link" and the field is then the word "link" - and iptables accepts a nonexistent interface without complaint, so the rules installed and never matched. Forwarding happened, masquerading did not, and every lookup from the MSX timed out. The interface is now read after "dev", and no rule is written if it is not a real interface.
- The TAP was created only when absent, never checked for ownership, so a device left behind by a server that once ran as root could never be opened by the pi-owned server: it sat UP but never RUNNING. The owner is now checked and the device recreated if it does not match.
- The address is added with "broadcast +" rather than coming up with broadcast 0.0.0.0.

BASIC extension without an EPROM (MSXPIEXT.BIN)
- MSXPIEXT.BIN builds again for v1.6: BLOAD"MSXPIEXT.BIN",R relocates it into page-1 RAM and adds CALL MSXPIVER and CALL MSXPI to BASIC on an MSXPi with no EPROM. It shares the CALL MSXPI handler with the driver ROM (asm-common/include/msxpi_call.asm), so the two cannot drift apart again; the obsolete msxpibios.asm is removed.
- The installer registered the CALL handler for the wrong slot whenever page-1 RAM sits in an expanded slot - most MSX2s, e.g. the Philips NMS 8245 has it in 3-2 - so CALL MSXPIVER crashed and rebooted the machine. It now includes the subslot. The install help no longer lists the CALL MSXPISEND / MSXPIRECV commands that no longer exist.
- msxpiboot.dsk carries it, and the BASIC programs BLOAD it when CALL MSXPIVER is not available.

openMSX
- The MSXPi device emulates the CPLD /WAIT flow control, so burst transfers can be developed and tested without hardware, with fault injection for a low RPI_READY.
- It no longer discards received bytes. The queue was capped at 16 KB and the remainder thrown away, which silently truncated every large transfer - a 16384-byte block with its header and checksum is 16389 - including the checksum byte the MSX then waited for forever. Back-pressure replaces discarding.
- TCP_NODELAY on the server socket. Each OUT to the data port is its own one-byte write, and with Nagle plus the server's delayed ACK each took about 40 ms, so a 512-byte burst write took minutes and looked exactly like a hung transfer.
- MSXPiNoROM.xml: the MSXPi I/O ports with no EPROM, for running MSXPIEXT.BIN the way it is used on an interface without one.

Housekeeping
- MIT licence headers and version 1.6 across the sources, third-party copyrights preserved.
- The discontinued C server, the MEMTEST ROM and the legacy client sources are gone; asm-common/transport holds the generated transfer code.
- build reorganised; the updater copies only the current BIOS ROM, not every archived one. The CPLD firmware and BIOS ROM of every release are kept, named by version.
- STELNET and CP437 added to the disk and the updater; TESTRAM.COM dropped.
- Regression tests cover the DSKIO sector loops and burst routines on an emulated Z80 against the real ROM, the Pi-side transfer engine, PCOPY, "p netreset", "p wifi", and a full Nextor + MegaFlashROM SCC+ SD copy in openMSX. They live under software/Tests on the development branches, and are not carried on the release branch.

MSXPi v1.5 Release Notes
========================
Network MegaROM loading, replacing the old disk-only "ploadr" command.
- "loadrom/LOADROM.COM": a binary patch of the third-party LOADROM.COM (v1.97) adding MSXPi network loading ("/N") for plain ROMs and MegaROMs (Konami/Konami SCC, ASCII8, ASCII16) alongside its existing local-disk loading - see "Client/src/loadrom/README.md" for how it works and why
- Per-block transfer protocol, with checksum-mismatch retry added to SENDDATA/RECVDATA_ONEBLOCK
- Server-side path-resolution fixes: a double-slash bug when joining network paths, and case-sensitive remote filenames now resolved correctly against typed-uppercase (FCB) input
Reliability fixes for `CALL MSXPI("2,...")` (save-response-to-buffer mode) and the IRC client.
- Fixed several real bugs that made mode "2" responses unreliable or crash-prone: a failed transfer could leave stale buffer data that got misread as a valid response, and two register-preservation bugs in the low-level receive routine could corrupt the reported response code or size - most visible on short messages or slower/larger transfers
- IRC.BAS: fixed a buffer memory-safety issue, a blank line that appeared on every periodic NAMES refresh, and CTCP probes (VERSION, PING, etc.) from other clients/bots are now filtered server-side instead of showing up as chat noise
- msxpi-server.py: fixed JOIN notifications picking up extra IRCv3 fields into the channel name, and a multi-block transfer desync when a command handler sends an explicit status code

MSXPi v1.4 Release Notes
========================
Mostly a Software major overhauling.
- C BIOS now available
- Replaced all p<commands> by p <command>, now developed in C
- Most block data transfers re-written for easy of use and stability
- MSX-DOS1 is back
- BASIC BIOS simplified, now there is only one command: CALL MSXPI 

MSXPi v1.3 Release Notes
========================
This is mainly a PCB redesign and firmware om the CPLD. From v1.3, firmware (msxpi.pof) is no longer compatible with previous versions due to pin mapping changes.
- Changed CPLD pin mappings to optimize PCB routing
- Changed the EEPROM footprint from DIP to PLCC
- Improved routing with power rails uninterrupted and wide.
- 5V power rail (for PI and EEPROM) routed on the edge of the card to avoid EMI 
- Bottom layer is now fully ground plane, with uninterrupted gnd plane across the PCB#
- Rev1: Updated silk in back of pcb to reflect new jumper names

MSXPi v1.2.1b Release Notes
===============================
- Activity LED now connects to RPi Ready signal - allows to see when RPi Server is online
- SPI_RDY resistor changed to pull-down 
- Re-routed power rails to minimise EMI & cross-signal interferences
- BASIC programs updated to run also under openMSX; defaults to 80 columns
- Firmware (CPLD) logic updated but keeping compatibility with previous versions; version "1100"

MSXPi v1.2 Release Notes
========================
- Added support in the software for the extension MSXPi for openMSX
- Added Pull-Up resistors to SPI_CS & SPI_RDY
- Added Push-button to Shutdown and Reboot Raspberry Pi (via interruption)
- Removed MSX RESET button from the interface
- Added diode in the 5V rail - allow Raspberry Pi to be powered
  via USB without leaking to the MSX
- Changed the 5V rail capacitor to 10uF
- Made optimisation to the CPLD firmware to save some logic gates
- Extensive changes to all software for stability
- Added new build file msxpibios.rom with MSXPi BIOS for BASIC CALL commands
- Lots of bug fixes to the code

MSXPi v1.1 Release Notes
========================
- New PCB layout
- Schema & PCB  changed to support future expansion to Raspberry Pi hardware SPIO
- New basic IO routines (used by all components)
- Lots of code changes to improve stability
- Improved pcopy: can decompress files, use virtual remote devices  
- Added BASIC API to support development in BASIC
- Added IRC.BAS - IRC client to chat in webchat.freenode.net
- Added BASIC programs from Retropix Brazil:
  - DOLAR.BAS
  - WEATHER.BAS
- Added chatgpt.com (OpenAI/chatgpt client)
- Lots of bug fixes and improvements
- All changes are fully compatible with interface v0.7

MSXPi v1.0.1 Release Notes
==========================
- Redesigned the interface in Kicad format, both schematic and PCB
- Replaced the 27C256 by AT28C256 to allow MSX to program the EEPROM from the MSX-DOS
- Added the EEPROM programmer AT28C256.COM to available commands - re-using it from my other project https://github.com/costarc/msxcart_flash32k
- Updated the msxpi-seerver.py to run in Python3, which is the default on newer versions of Raspbian

This version allows:
- Set MSX data & time from Raspberry Pi
- Copy programs from Internet to MSX disk (ftp, http, smb)
- Run 8KB/16KB/32KB ROMS directly from Pi or from the network (ftp, http, smb)
- Run commands on Pi directly from MSX-DOS command line
- Configure Pi wifi from MSX-DOS

Known issues and defects
========================
- MSXPI-DOS1 is not booting - it's not actually important, because the best way to use MSXPi is along with a MSX-DOS2 system, usually running with a SDCard cartridge
- pplay.sh notworking

MSXPi v1.0 Release Notes
========================
This release has some major changes to the hardware and software components.

On the hardware side:

- Implemented the /wait signal on the PCB (CPLD does not drives at this time, it is always tri-state, therefore this signal is for future use)
- Schematics was updated to support the /wait signal
- CPLD logic update to drive /wait to tri-state (to avoid MSX to freeze)
- LED is driven by the SPI_CS signal (needed that CPLD pin for the /wait signal)
- Removed the jumper for the BUSDIR signal (since it is always driven by CPLD internal logic)
- Added pull-up resistors for all Raspberry Pins used in the design
- Added by-pass capacitors for all CIs.

On the software side:

- The server component was mostly rewritten to be more modular
- Every command now can be implemented in a self-contained function inside msxpi-server.py
- No changes are needed in the main loop of the program when new featuers or commandss are added
- Main data transfer routine (senddatablock / receivedatablock) rewritten to allow retries and block size configuration
- Many functions removed (deprecated) resulting in a less complex and easier to maintain and expand solution
- All clients rewritten based on a simple and better communication logic
- Many improvements and bug fixes
- More stable softwre architecture


Other non functional changes includes a new design using KiCad 5 instead of Eagle, some more jumpers to support new EEPROM features.

Limitations and bugs
- When booting from MSXPI-DOS, pcopy cannot copy file to the msxpiboot.dsk
- The CPLD logic and software are not benefiting of the /wait signal (future improvement)


MSXPi has two main branches:

master - Most up-to-date version. This contains fresh code, that might have been updated just couple mintues ago. Expect to find bugs, but also expect them to be fixed very quickly.

Release branches - Contains previous releases.

Other branches might appear and disappear. I recommend you not to use them.

To-Do / Wish List
=================
1. Redesign the interface to use Raspberry Pi SPI GPIO pins & hardware support
2. Implement Z80 /WAIT states in the interface
3. Implement Z80 /INT support in the interface
4. Redesign the interface for Parallel bus support

MSXPi project is structured around three directories:

    /software  - all software goes here
    /hardware  - interface schematics, CPLD design files
    /documents - documentation


The /software branch has this structure:


    MSXPi
    |-------/software 
    |       |---- 
    |       |    | 
    |       |    /asm-common
    |       |    |----
    |       |    |    |
    |       |    |    /include
    |       |    |    
    |       |    |
    |       |    /ROM
    |       |    |----
    |       |    |    |
    |       |    |    /src
    |       |    |    |----
    |       |    |         |
    |       |    |         /MSX-DOS
    |       |    |         |
    |       |    |         /BIOS
    |       |    |
    |       |    |
    |       |    /Client
    |       |    |----
    |       |    |    |
    |       |    |    /src
    |       |    |
    |       |    /Server
    |       |    |----
    |       |         |
    |       |         /Python
    |       |         |----
    |       |         |    |
    |       |         |    /src
    |       |         |
    |       |         /Shell
    |       |         |
    |       |         /systemd
    |       |         |
    |       |         /C (deprecated)
    |       |         |----
    |       |              |
    |       |              /src
    |       |
    |-------/openMSX	
    |       |
    |-------/hardware 
    |       |---- 
    |       |    | 
    |       |    /CPLD_Project
    |       |    |
    |       |    /Schematic
    |       |    |----
    |       |         |
    |       |         /Fabrication
    |       |
    |-------/Documentation



