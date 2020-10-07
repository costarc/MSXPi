MSXPi
=====

MSXPi is a hardware interface and software solution to allow MSX computers to control and user Raspberry Pi resources.
The interface exposes ports that can be read and written by MSX, and in turn will be accessible on the Raspberry Pi.
Many resources are implemented, such as access to network drives, internet, disk images, and the Raspberry Pi itself.

The code, schematics and cpld designs for MSXPi are released in git branches as they achieve an acceptable maturity level. Use one of the "release/version" branches that is more appropriate to your interface.

Note that this is Work In Progress, therefore there are already a few versions released and under tests. None of this work is provided with warranty, and should be used at your own risks even though I never damaged any MSX or Raspberry pi in the 4 years of development of this project.

Current releases:

 * release/v1.1   => Target for interface v1.1. Can also be used with interfaces v1.0 reprogramming the CPLD with this release's bitstream. New CPLD logic (more space efficient and more features implemented). Low-level transfer routines improved, including the use of CRC16 for error check. Z80 /wait signal i sused by default, which means this release can only be used with interfaces v0.7 if a hardware modification is performed.


* release/v1.0   => Targeted for all interfaces from v0.7 up to v1.0. Server and client software was re-written to support a new transfer protocol. More modular and easier to expand, consist of the basis for all future updates.


* release/v0.8.2 => Targeted for interface v0.7. This is the first and longer lasting release, originally developed for first batches of interfaces. Code from this release can be used by all interfaces released up to v1.0 without need to reprogram the CPLD.

Quick Start Guide
=================

Please refer to the full documentation under "documents" folder for detailed setup procedure.

There are two main steps to setup MSXPi, once you choose the correct branch for your interface:

1. Setup Rapsberry Pi with the server-side software (Raspberry Pi SD Card)
2. Setup MSX with the client side software (MSX SD Card or disk)


* Step 1: The easier way to setup the Raspberry Pi is to download the SD CARD image from a MSXPi release - latest image for release v0.8.2 and v1.0 can be found under: https://github.com/costarc/MSXPi/releases/download/v1.0.1.20200905.001/MSXPiv1.0Rev0_b20200905.001_SDCard_img.zip

The login user and password are the default for Raspbian: 

user: pi

password: raspberry


* Step 2: Copy all MSXPi commands form the /software/target to your MSX-DOS SD card (or disk). Use pwifi command from MSX-DOS to setup the wifi network and key, and MSXPi is fully ready to use.

Jumpers:
A14 - MSX detects MSXPi BIOS and continue to BASIC (MSX-DOS if other IDE interface is connected).
A15 - MSX detects MSXPI BIOS. If user press P, boots from MSXPi-DOS. Otherwise proceeds with MSX boot.

In either jumper setup, the MSXPi BIOS is available to use from BASIC. Type "CALL MSXPIVER" for a list of commands.


Relese Notes
============
Get the full release notes on the separate file "Release_Notes" in the root of the project.
The latest and more significant changes are listed next.

MSXPi v1.1 Release Notes
==========================
Major release with support for the new interface v1.1. for this reason, includes big changes to the software and cpld logic.

- Replaced the EPROM 27C256 by EEPROM AT28C256 (re-writable from MSX-DOS)
- CPLD Logic logic re-written to save space in the cpld and add features.
- Implemented support for 17 bits bus transfer - RPi now receives MSX WR_n, Port Address and Data (17 bits total).
- Fixed bugs in code, and added support for interfaces with or without /wait enabled.
- Addition of new program AT28C256.COM to write roms to the new EEPROM directly from the MSX-DOS


MSXPi v1.0 Release Notes
========================
This release has some major changes to the hardware and software components.

On the hardware side:

- Implemented the /wait signal on the PCB (CPLD does not drives at this time, it is always tri-state)
- Schematics was updated to supporgt the /wait signal
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


Other non functional changes includes a new design using KiCad 5 instead of Eagle.

Limitations and bugs
- To write a rom to the eeprom, you may need to specify the slot number where the MSXPi is plugged - there is not, currently, an automated and failsafe method to detect on whaat slot the epprom is connected.
- The CPLD logic and softwares are not benefiting of the /wait signal (future improvement)


MSXPi Branching strategy and Other information
===============================================

MSXPi Project is organized in a series of branches.
Here is what you need to know to choose the right branch for your interface:


Interfaces v0.7 (without reprogramming the CPLD) => use release branch 0.8.2 (release/v0.8.2)

Interfaces v0.7 (if you can reprogram the CPLD)  => use any release branch 1.0.n (release/v1.0.n)

Interfaces v1.0 (without reprogramming the CPLD) => use release branch 1.0 (release/v1.0)

Interfaces v1.0 (if you can reprogram the CPLD)  => use release branch 1.0.1 (release/v1.0.1)

Interfaces v1.1 => use release/v1.1. You can also use "master" or "dev", but those may be unstable.


In general, development and distribution of code follows this process:


dev --> master --> release

dev - current devlopment branch. This is where latest tools are developed and tested. Code here might change overnight, and even several times a day. Things may nor work properly, so if you want something more usable, go to the master branch or dev_0.7. 

master - current working stable release. This contains code for the branch under development, in a more mature state, but may not contain most current tools. 

release/version - contains a major release, which should not change frequently but may receive fixes or important improvements over time.

Note: dev_0.7 - Contain ealier development code. Uses an old single-byte protocol, and only support BASIC client (no MSX_DOS). This should definitely not be used.

Other branches might appear and dissapear. I recommend you not to use them.


MSXPi project is structured around three directories:

    /software  - all software goes here
    /hardware  - electric schematics, cpld design files
    /documents - documentation

The branches are structured as follows:
```
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
