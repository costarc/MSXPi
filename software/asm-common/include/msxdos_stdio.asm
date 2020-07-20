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
; check if there are parameters in the command line
; Input Parameters:
;  HL = Address of the command
;  BC = Number of chars in the command 

        push    bc
        ld      de,FULLCMD
        ldir
        ld      hl,$80
        ld      a,(hl)
        inc     hl
        or      a
        jr      z,SENDCMD  ;There are no parameters, send the command to MSXPi
        ld      b,a
        call    EATSPACES  ; send number of chars in A
        jr      c,SENDCMD  ; found only spaces after command name
        pop     af         ; discard original command size
moveparms:
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        djnz    moveparms

; calc the total size of the command line to send to RPi
        ld      hl,FULLCMD
        or      a       ; reset carry so won't affect subtraction
        ex      de,hl   ; De contain start address, then need to exchange place with DE
        sbc     hl,de   ; to apply a subtraction and get final command size
        ld      b,h     ; load size in BC for senddatablock function
        ld      c,l
        jr      SENDCMD1
SENDCMD:
        pop    bc
SENDCMD1:
        ld     hl,FULLCMD
        jp     SENDDATABLOCK

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
        cp      ' '
        jr      nz,EATSPACEEND
        inc     hl
        djnz    EATSPACES
        scf
        ret
EATSPACEEND:
        or      a
        ret
FULLCMD:equ     $
        ds      256

