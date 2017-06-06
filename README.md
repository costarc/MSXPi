MSXPi has two main branches:

Master - current working stable release. This contains code for the branch under development, in a more mature state. 
dev - current development branch. Code here might change overnight, and even several times a day. Things may nor work properly, so if oyu want something more usable, go to the master branch or dev_0.7.

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


