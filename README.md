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

          pset WIFISSID Your Wifi Name
 
          pset WIFIPWD YourWifiPassword
 
          pwifi set
 
          preboot
 
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



