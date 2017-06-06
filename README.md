MSXPi is an open project.

There are two software versions:
 - dev_0.7, stable, with a client running from BASIC
 - dev - current development branch. Code here might change overnight, and even several times a day. Things may nor work properly, so if oyu want something more usable, go to the master branch or dev_0.7.
 - 0.8.1, unstable, with MSX-DOS support and also the client running from BASIC
 - master - current working stable release. This contains code for the branch under development, in a more mature state. 
When booting version 0.8.1, presing ESC will skip MSX-DOS and jump straight into BASIC.
dev - current development branch. Code here might change overnight, and even several times a day. Things may nor work properly, so if oyu want something more usable, go to the master branch or dev_0.7.

dev_0.7 - the stable old version as mentioned above.

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


