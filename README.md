Note: This project is WIP. master repo is fairly stable, but the dev branches are not. Not all commands are working, and there are stabilityh issues with the transfers. For any of this to work, a mod is necessary in the MSXPi interface: connect /wait signal to CPLD pin 11 (this pin is currently connected to /busdir via a jumper).

MSXPi has two main branches:

master - current working stable release. This contains code for the branch under development, in a more mature state, but may not contain most current tools. 

dev - current devlopment branch. This is where latest tools are developed and tested. Code here might change overnight, and even several times a day. Things may nor work properly, so if you want something more usable, go to the master branch. 

dev_0.7_with_wait_mod - this branch might be up to date with branch dev, but it is intended to be used with the MSXPi interface V0.7 Rev7 and older with a mod to support /wait signal. Software on this branch is the identical to software in the dev branch.

dev_0.7 - Contain ealier development code. Uses an old single-byte protocol, and only support BASIC client (no MSX_DOS).

Other branches might appear and dissapear. I recommend you not to use them.


MSXPi project is structured around three directories:

    /software  - all software goes here
    /hardware  - electric schematics, cpld design files
    /documents - documentation

The /software branch has this structure:


    /software 
    |---- 
    |    | 
    |    /asm-common
    |    |----
    |    |    |
    |    |    /include
    |    |    
    |    |
    |    /ROM
    |    |----
    |    |    |
    |    |    /src
    |    |
    |    /Client
    |    |----
    |    |    |
    |    |    /src
    |    |
    |    /Server
    |    |----
    |         |
    |         /c
    |         |
    |         |----
    |         |    |
    |         |    /include
    |         |    |
    |         |    /src
    |         |


