;|===========================================================================|
;|                                                                           |
;| MSXPi Interface                                                           |
;|                                                                           |
;| Version : 0.8                                                             |
;|                                                                           |
;| Copyright (c) 2015-2016 Ronivon Candido Costa (ronivon@outlook.com)       |
;|                                                                           |
;| All rights reserved                                                       |
;|                                                                           |
;| Redistribution and use in source and compiled forms, with or without      |
;| modification, are permitted under GPL license.                            |
;|                                                                           |
;|===========================================================================|
;|                                                                           |
;| This file is part of MSXPi Interface project.                             |
;|                                                                           |
;| MSX PI Interface is free software: you can redistribute it and/or modify  |
;| it under the terms of the GNU General Public License as published by      |
;| the Free Software Foundation, either version 3 of the License, or         |
;| (at your option) any later version.                                       |
;|                                                                           |
;| MSX PI Interface is distributed in the hope that it will be useful,       |
;| but WITHOUT ANY WARRANTY; without even the implied warranty of            |
;| MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             |
;| GNU General Public License for more details.                              |
;|                                                                           |
;| You should have received a copy of the GNU General Public License         |
;| along with MSX PI Interface.  If not, see <http://www.gnu.org/licenses/>. |
;|===========================================================================|
;
; File history :
; 0.1    : initial version
TEXTTERMINATOR: EQU     '$'
BDOS:           EQU     5
DOSSENDPICMD:
; Copy our command to the buffer
        ld      hl,FULLCMD
        ex      de,hl
        push    bc
;CALL    DBGHL
;CALL    DBGDE
;CALL    DBGBC
        ldir

; now check if there are parameters in the command line
        ld      hl,$80
        ld      a,(hl)
        ld      b,a
        or      a
        jr      z,DOSSEND1

DOSSENDPICMD0:
; b contain number of chars passed as arguments in the command
        inc     hl
        call    EATSPACES
        jr      c,DOSSEND1

; save number of characters in B
        push    bc

; there are parameters - have to concatenate to our buffer
DOSSENDPICMD1:
        ld      a,32
        ld      (de),a
        inc     de
DOSSENDPICMD2:
        ld      a,(hl)
        ld      (de),a
;call    PUTCHAR
        inc     hl
        inc     de
        djnz    DOSSENDPICMD2

; now get number of chars in command line arguments
        pop     hl
        ld      l,h
        ld      h,0

; then get number of chars in our command
        pop     bc

; and calc the total size of the command line to send to RPi
        add     hl,bc
        ld      b,h
        ld      c,l
        push    bc

DOSSEND1:
        ld      a,0
        ld      (de),a
        pop     bc
        inc     bc
        ld      de,FULLCMD
        call    SENDPICMD
        ret

PUTCHAR:
        push    bc
        push    de
        push    hl
        ld      e,a
        ld      c,2
        call    BDOS
        pop     hl
        pop     de
        pop     bc
        ret

EATSPACES:
        ld      a,(hl)
        cp      32
        jr      nz,EATSPACEEND
        inc     hl
        djnz    EATSPACES
        scf
        ret
EATSPACEEND:
        or      a
        ret
;INCLUDE "debug.asm"
FULLCMD:equ     $
        ds      256

