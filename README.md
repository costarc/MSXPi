Attention: I am in the process of review, update and change both interface and software.
As of now, the software is not functional. I will update here once I finish the revision process.

====

For more details, please refer to the github project: 
https://github.com/costarc/MSXPi

github project: https://github.com/costarc/MSXPi/tree/release/v1.0

MSXPi is a hardware interface and software solution to allow MSX computers to control and user Raspberry Pi resources.
The interface exposes ports that can be read and written by MSX, and in turn will be accessible on the Raspberry Pi.
Many resources are implemented, such as access to network drives, internet, disk images, and the Raspberry Pi itself.

Quick Start Guide
=================

Please refer to the full documentation under "documents" folder in github for detailed setup procedure and other information.

There are two main steps to setup MSXPi, once you choose the correct branch for your interface:

- Setup Rapsberry Pi with the server-side software (Raspberry Pi SD Card)
- Setup MSX with the client side software (MSX SD Card or disk)

Step 1: The easier way to setup the Raspberry Pi is to download the SD CARD image from a MSXPi release - latest image for interface release v0.8.2 and v1.0 can be found under: https://github.com/costarc/MSXPi/releases/download/v1.0.1.20200905.001/MSXPiv1.0Rev0_b20200905.001_SDCard_vhd.zip

The login user and password are the default for Raspbian:

user: pi

password: raspberry

Step 2: Copy all MSXPi commands from the latest release - https://github.com/costarc/MSXPi/releases/tag/v1.0.0.20201015.000/ to your MSX-DOS SD card (or disk). Use pwifi command from MSX-DOS to setup the wifi network and key, and MSXPi is fully ready to use.

Jumpers:

A14 - Load the MSX-DOS 1.03 from Raspberry Pi disk image (msxpiboot.dsk). BIOS is available from BASIC

A15 - BIOS is available from BASIC. MSX Will boot to BASIC or to another connectd IDE interface.

MSXPi v1.0 Release Notes
========================
This release has some major changes to the hardware and software components.

On the hardware side:

- Implemented the /wait signal on the PCB (CPLD does not drives at this time, it is always tai-state)
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
    |       |    /CPLD Project
    |       |    |
    |       |    /Schematic
    |       |    |----
    |       |         |
    |       |         /Fabrication
    |       |
    |-------/Documentation



