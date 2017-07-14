MSXPi has two main branches:

<<<<<<< HEAD
Master - current working stable release. This contains code for the branch under development, in a more mature state. 
dev - current devlopment branch. code here might change overnight, and even several times a day. Things may nor work properly, so if oyu want something more usable, go to the master branch or dev_0.7.
=======
master - current working stable release. This contains code for the branch under development, in a more mature state, but may not contain most current tools. 

dev - current devlopment branch. code here might change overnight, and even several times a day. Things may nor work properly, so if you want something more usable, go to the master branch or dev_0.7. This is where latest tools are developed and tested.
>>>>>>> master

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


