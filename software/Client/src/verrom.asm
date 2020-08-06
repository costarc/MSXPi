;|===========================================================================|
;|                                                                           |
;| MSXPi Cartridge 32K EEPROM                                                |
;|                                                                           |
;| Version : 1.0                                                             |
;|                                                                           |
;| Copyright (c) 2020 Ronivon Candido Costa (ronivon@outlook.com)            |
;|                                                                           |
;| All rights reserved                                                       |
;|                                                                           |
;| Redistribution and use in source and compiled forms, with or without      |
;| modification, are permitted under GPL license.                            |
;|                                                                           |
;|===========================================================================|
;|                                                                           |
;| This file is part of msxcart_flash32k project.                            |
;|                                                                           |
;| msxcart_flash32k is free software: you can redistribute it and/or modify  |
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
; 1.0  - 27/06/2020 : initial version
;        05/08/2020 : Revised versoin

dma:            equ     $80
regsize:        equ     1
numregtoread:   equ     64
TEXTTERMINATOR: EQU     0
BDOS:           EQU     5
CALLSTAT:       EQU     $55A8
INLINBUF:       EQU     $F55E
INLIN:          EQU     $00B1
CHPUT:          EQU     $00A2
CHGET:          EQU     $009F
INITXT:         EQU     $006C
EXPTBL:         EQU     $FCC1
RDSLT:          EQU     $000C
WRSLT:          EQU     $0014
CALSLT:         EQU     $001C
ENASLT:         EQU     $0024
RSLREG:         EQU     $0138
WSLREG:         EQU     $013B
CSRY:           EQU     $F3DC
CSRX:           EQU     $F3DD
ERAFNK:         EQU     $00CC
DSPFNK:         EQU     $00CF
PROCNM:         EQU     $FD89
XF365:          EQU     $F365                  ; routine read primary slotregister

DEVICE:         equ     0FD99H

txttab:         equ     $f676
vartab:         equ     $f6c2
arytab:         equ     $f6c4
strend:         equ     $f6c6
SLTATR:         equ     $fcc9
CALBAS:         equ     $0159
CHRGTR:         equ     $4666

ERRHAND:        EQU     $406F
FRMEVL:         EQU     $4C64
FRESTR:         EQU     $67D0
VALTYP:         EQU     $F663
USR:            EQU     $F7F8
ERRFLG:         EQU     $F414
HIMEM:          EQU     $FC4A
MSXPICALLBUF:   EQU     $E3D8

RAMAD0:         EQU     $F341             ; slotid DOS ram page 0
RAMAD1:         EQU     $F342             ; slotid DOS ram page 1
RAMAD2:         EQU     $F343             ; slotid DOS ram page 2
RAMAD3:         EQU     $F344             ; slotid DOS ram page 3

; This is a MSX-DOS program
; STart address is $100

        org     $100
    
        call    readparms
        jr      nc,showcart        ; received slot numnber from cli

        ld      hl,txt_ramsearch
        call    print
        call    search_cart
        ld      hl,txt_ramnotfound
        ld      a,(thisslt)
        cp      $ff
        call    z,print
        ret

showcart:
         ld      a,(thisslt)
         ld      h,$40
         call    ENASLT
         call    showcontent
         ld      a,(RAMAD1)
         ld      h,$40
         call    ENASLT
         ret

; get slot number from CLI
readparms:
       ld      a,($80)
       or      a
       scf
       ret     z  ; no parameters passed
       cp      3
       jr      z,readparms1
       ld      hl,txt_invalidparms
       call    print
       scf
       ret                 ; parameter must be space + 2 digit
readparms1:
       ld      a,($82)
       sub     $30
       sla     a
       sla     a
       sla     a
       sla     a
       ld      b,a

       ld      a,($83)
       sub     $30
       or      b
       ld      (thisslt),a
       scf
       ccf
       ret

; Search for the EEPROM
search_cart:
        ld      a,$FF
        ld      (thisslt),a
nextslot:
         ld      a,'.'
         call    PUTCHAR
         di
         call    sigslot
         cp      $FF
         jr      z,endofsearch
         ld      h,$40
         call    ENASLT
         call    test_cart
         jr      c,nextslot
         call    showcontent
         jr      nextslot

endofsearch:
         ld      a,(RAMAD1)
         ld      h,$40
         call    ENASLT
         ld      a,$FF
         scf
         ret

test_cart:
        ld      a,($4000)
        cp      'A'
        scf
        ret     nz
        ld      a,($4001)
        cp      'B'
        ret     Z
        SCF
        ret

showcontent:
        ld      a,(thisslt)
        call    PRINTNUMBER
        call    PRINTNEWLINE
        ld      hl,$4000
        ld      b,0
showcontent0:
        ld      a,(hl)
        call    PRINTNUMBER
        ld      a,' '
        push    bc
        call    PUTCHAR
        pop     bc
        inc     hl
        djnz    showcontent0
        call    PRINTNEWLINE
        ret

; -------------------------------------------------------
; SIGSLOT
; Returns in A the next slot every time it is called.
; For initializing purposes, thisslt has to be #FF.
; If no more slots, it returns A=#FF.
; this code is programmed by Nestor Soriano aka Konamiman
; --------------------------------------------------------
sigslot:
    ld      a, (thisslt)                ; Returns the next slot, starting by
    cp      $FF                         ; slot 0. Returns #FF when there are not more slots
    jr      nz, .p1                     ; Modifies AF, BC, HL.
    ld      a, (EXPTBL)
    and     %10000000
    ld      (thisslt), a
    ret
.p1:
    ld      a, (thisslt)
    cp      %10001111
    jr      z, .nomaslt
    cp      %00000011
    jr      z, .nomaslt
    bit     7, a
    jr      nz, .sltexp
.p2:
    and     %00000011
    inc     a
    ld      c, a
    ld      b, 0
    ld      hl, EXPTBL
    add     hl, bc
    ld      a, (hl)
    and     %10000000
    or      c
    ld      (thisslt), a
    ret
.sltexp:
    ld      c, a
    and     %00001100
    cp      %00001100
    ld      a, c
    jr      z, .p2
    add     a, %00000100
    ld      (thisslt), a
    ret
.nomaslt:
    ld      a, $FF
    ret

;-----------------------
; PRINT                |
;-----------------------
print:
        push    af
        ld      a,(hl)      ;get a character to print
        cp      TEXTTERMINATOR
        jr      Z,PRINTEXIT
        cp      10
        jr      nz,PRINT1
        pop     af
        push    af
        ld      a,10
        jr      nc,PRINT1
        call    PUTCHAR
        ld      a,13
PRINT1:
        call    PUTCHAR     ;put a character
        INC     hl
        pop     af
        jr      print
PRINTEXIT:
        pop     af
        ret

;-----------------------
; PRINTNUMBER          |
;-----------------------
PRINTNUMBER:
printnumber:
        push    de
        ld      e,a
        push    de
        AND     0F0H
        rra
        rra
        rra
        rra
        call    PRINTDIGIT
        pop     de
        ld      a,e
        AND     0FH
        call    PRINTDIGIT
        pop     de
        ret

PRINTDIGIT:
        cp      0AH
        jr      c,PRINTNUMERIC
PRINTALFA:
        ld      d,37H
        jr      PRINTNUM1

PRINTNUMERIC:
        ld      d,30H
PRINTNUM1:
        add     a,d
        call    PUTCHAR
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

PRINTNEWLINE:
       push     hl
       ld       hl,txt_newline
       call     print
       pop      hl
       ret

txt_ramsearch:   db      "Search for EEPROM",13,10,0
txt_ramfound:   db      "Found RAM in slot ",0
txt_newline:    db      13,10,0
txt_ramnotfound:   db      "ram not found",13,10,0
txt_writingflash:   db      "Writing to EEPROM on slot ",0
txt_completed: db      "Completed.",13,10,0
txt_nofn:         db "Filename is empty or not valid",13,10,0
txt_fileopenerr:  db "Error opening file",13,10,0
txt_fnotfound: db "File not found",13,10,0
txt_ffound: db "Reading file",13,10,0
txt_err_reading: db "Error reading data from file",13,10,0
txt_endoffile:   db "End of file",13,10,0
txt_credits: db "AT28C256 EEPROM Programmer for MSX",13,10
             db "(c) Ronivon Costa, 2020",13,10,13,10,0
txt_invalidparms: db "Invalid parameters",13,10
                  db "Must pass a slot number using two digits, for example:",13,10
                  db "at28c256 02 game.rom",13,10,0
txt_advice: db 13,10
            db "Write process completed",13,10
            db "==> ATTENTION <==",13,10
            db "Switch off the MSX immediately, remove the interface, then remove the /wr jumper"
            db 13,10,0
txt_sdp:    db "To force disabling the AT28C256 Software Data Protction (SDP),",13,10
            db "call this program passing the slot as parameter.",13,10
            db "Must specify two digits for the slot, as for example:",13,10
            db "at28csdp 01",13,10,13,10
            db "Afterwards, you can use verrom.com to verify if the SDP was correctly disable.",13,10,0

thisslt: db $FF
curraddr: dw $0000

fcb:
; reference: https://www.msx.org/wiki/FCB    
fcb_drv: db 0           ; Drive number containing the file.
                        ; (0 for Default drive, 1 for A, 2 for B, ..., 8 for H)

fcb_fn: db "filename"   ; 8 bytes for filename and 3 bytes for its extension. 
        db "ext"        ; When filename or extension has less than 8 or 3, the rest are 
                        ; filled in by spaces (20h). In case of search "?" (3Fh) may be used
                        ; to represent any character.
fcb_ex: db 0            ; "Current block LO" or "Extent number LO" depending of function called.
fcb_s1: db 0            ; "Current block HI" or "File attributes" (DOS2) depending of function called.
fcb_s2: db 0            ; "Record size LO" or "Extent number HI" depending of function called. 
                        ; NOTE: Because of Extent number the record size must be manually 
                        ; defined after opening a file!
fcb_rc: db 0            ; "Record size HI" or "Record count" depending of function called.
fcb_al: db 0,0,0,0      ; File size in bytes (1~4294967296).
        db 0,0          ; Date (DOS1) / Volume ID (DOS2)
        db 0,0          ; Time (DOS1) / Volume ID (DOS2)
        db 0            ; Device ID. (DOS1)
                        ; FBh = PRN (Printer)
                        ; FCh = LST (List)
                        ; FCh = NUL (Null)
                        ; FEh = AUX (Auxiliary)
                        ; FFh = CON (Console)
        db 0            ; Directory location. (DOS1)
        db 0,0          ; Top cluster number of the file. (DOS1)
        db 0,0          ; Last cluster number accessed (DOS1)
        db 0,0          ; Relative location from top cluster of the file number of clusters
                        ; from top of the file to the last cluster accessed. (DOS1)
fcb_cr: db 0            ; Current record within extent (0...127)
fcb_rn: db 0,0,0,0      ; Random record number. If record size <64 then all 4 bytes will be used.
        db 0,0,0
