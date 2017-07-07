MSXPi is an open project.

There are two software versions:
 - master - current stable release, based on dev branch. 
 - dev - current development branch, version 0.8.1. Code here might change overnight, and even several times a day. Things may not work properly, so if you want something more usable, go get the master branch. This branch has MSX-DOS support and also the client running from BASIC, but it sometimes hangs when accessing sectors. When booting from this version, presing ESC should skip MSX-DOS and jump straight into BASIC, where you can still use the CALL commands to invoke the msxpi client.
- dev_0.7 - the stable old version as mentioned in the above comments. Eventual changes to this (old) release will be pushed first to this branch, and only after proven stable will be pushed to master.


You are strongly encouraged to do any work on top of version 0.8.1 (the dev branch). This is because this versions is using a more straight forward protocol, using full-command names on the MSX-side. And on the Pi side, it uses functions for every command implemented, making it very modular and easy to understand and improve with new commands.
I know it is buggy, but working on top of this version will assure any future development will be re-usable (I have no plans to support any develoment on top of version 0.7).
Also, I expect someone can eventually come up with a fix to the bug on this version that cause the sector transfer to hang up sometimes, then this will be the bests and greatest version of MSXPi, and no one will be happy to have Apps compatible with v0.7 only when this happens. :)

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


