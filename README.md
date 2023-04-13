# MSXPi

MSXPi is a hardware interface and software solution to allow MSX computers to control and use Raspberry Pi resources.
The interface exposes I/O ports that can be read and written by MSX, and in turn the data will be accessible on the Raspberry Pi.
Many resources are implemented, such as access to network drives, internet, disk images, and the Raspberry Pi itself.

Quick Start Guide
=================


This Quick Start Guide is updated to V1.1 of the Software and Interface.

Please refer to the full documentation under "documents" folder in github for detailed setup procedure and other information.

There are a few steps to setup MSXPi, and you can choose between using a MSXPi pre-installed SD Card image (ready to boot MSXPi), or build your own image using a fresh Raspbian Image downloaded from Raspberry Pi web site - both methods are described below.

Overall, the steps to get up and running are:

- Setup Rapsberry Pi with the server-side software (Raspberry Pi SD Card)
- Setup MSX with the client side software (MSX SD Card / disk drive)

Prepare Raspberry Pi Using MSXPi SDCard Image
=============================================
### Step 1: Download and install Raspberry Pi SD Card with MSXPi server software. 
MSXPi SD Card image: https://tinyurl.com/MSXPi-SDCard


### Step 2: Write the image to a SD Card
Use a SD Card with a minimum of 4GB.

Use 7Zip to unzip the file, and use Raspberry PI Imager to write the image to the SD Card (select option "Use Custom" in the Operating System drop box).

RPi Imager can be download from https://www.raspberrypi.com/news/raspberry-pi-imager-imaging-utility/


### Step 3: Install the MSXPi commands for MSX-DOS

In your favorite PC computer, copy all MSXPi commands from https://github.com/costarc/MSXPi/tree/master/software/target to your MSX SD card or Disk.

After this basic setup, you should be able to use the MSXPi ".com" commands from your MSX. To unleash full MSXPi power, configure the Raspberry Pi Zero W WiFi:

          pset WIFISSID Your Wifi Name
 
          pset WIFIPWD YourWifiPassword
 
          pwifi set
 
          preboot
 
 Note: The first reboot may take longer than 3 minutes, because Raspbian will expand the filesystem in the SD and initialize the Linux system - following reboots will be faster)

In case you need very detailed instructions, please read  "Tutorial - Setup Raspberry Pi for MSXPi the Easy Way - Using the MSXPi Pre-Installed Image.pdf", in https://github.com/costarc/MSXPi/tree/master/documents (Portuguese version also available).


Prepare Raspberry Pi Using a Fresh Raspbian Image
=================================================
In this mode, you will have to install all requirements for MSXPi - there is a script to help you with that, though.

### Step 1: Download the Raspberry Pi Imager
Download from https://www.raspberrypi.com/software

This is the official Raspberry Pi SD Card image writer - download and install in your desktop PC.

### Step 2: Write the Raspbian image to the SD Card
Run the Pi Imager software, and select the best  OS for your raspberry pi. If you are using the recommended Raspberry Pi Zero W, choose the lite version (without graphical desktop):

          CHOOSE OS -> Raspberry Pi OS Lite (other) -> Raspberry Pi OS LITE (32-bit)

Write the image to your SD Card and when completed, boot the Raspberry with the SD Card inserted.

### Step 3: Setup MSXPi using MSXPI-Setup tool
You will need to connect the Raspberry Pi to a HDMI TV and a keyboard to complete these steps.

Login to Raspbian using default user and passwird: pi / raspberry

Configure the WiFi using raspi-config command

Download the MSXPi setup script - it will download and install everything needed to have MSXPi up and running:

          mkdir /home/pi/msxpi

          cd /home/pi/msxpi

          wget https://tinyurl.com/MSXPi-Setup

          chmod 755 MSXPi-Setup

          sudo ./MSXPi-Setup
          
If you need very detailed instructions, please read "Tutorial - Setup  Raspberry Pi for MSXPi the Hard Way - Installing Raspbian from Scratch.pdf", in https://github.com/costarc/MSXPi/tree/master/documents (Portuguese version also available).

MSXPi v1.1 Release Notes
========================
- New PCB layout
- New basic IO routines (used by all components)
- Lots of code changes to improve stability
- Improved pcopy: can decompress files, use virtual remote devices  
- Added BASIC API to support development in BASIC
- Added IRC.BAS - IRC client to chat in webchat.freenode.net
- Added BASIC programs from Retropix Brazil:
  - DOLAR.BAS
  - WEATHER.BAS
- Lots of bug fixes and improvements

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

- Implemented the /wait signal on the PCB (CPLD does not drives at this time, it is always tai-state, therefore this signal is for future use)
- Schematics was updated to support the /wait signal
- CPLD logic update to drive /wait to tri-state (to avoid MSX to freeze)
- LED is driven by the SPI_CS signal (needed that CPLD pin for the /wait signal)
- Removed the jumper for the BUSDIR signal (since it is always driven by CPLD internal logic)
- Added pull-up resistors for all Raspbery Pins used in the design
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
- The CPLD logic and softwares are not benefiting of the /wait signal (future improvement)


MSXPi has two main branches:

master - current working stable release. This contains code for the branch under development, in a more mature state, but may not contain most current tools. 

dev - current devlopment branch. This is where latest tools are developed and tested. Code here might change overnight, and even several times a day. Things may nor work properly, so if you want something more usable, go to the master branch or dev_0.7. 

dev_0.7 - Contain ealier development code. Uses an old single-byte protocol, and only support BASIC client (no MSX_DOS).

Other branches might appear and dissapear. I recommend you not to use them.


To-Do / Wish List
=================
1. Redesign the interface to use Raspberry Pi SPI GPIO pins & hardware support
2. Implement Z80 /WAIT states in the interface
3. Implement Z80 /INT support in the interface
4. Redesign the interace for Parallel bus support

MSXPi project is structured around three directories:

    /software  - all software goes here
    /hardware  - electric schematics, cpld design files
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



