;|===========================================================================|
;|                                                                           |
;| MSX Software for Cartridge AT28C256 32K EEPROM                            |
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
; Compile this file with z80asm:
;  z80asm at28c256.asm -o at28c256.com
; 
; File history :
; 1.0  - 27/06/2020 : initial version
;        05/08/2020 : Revised version
;
; Note on this code:
; Due to some technical problems to enable/disable the EEPROM Software Data 
; Protecion (SDP), this code only works if the SDP is previously disabled.
; Make sure the EEPROM SDP has not been enabled by other means, as for example,
; using an external EPROM programmer.
;
; Before writing a ROM to the EEPROM, use the "at28unpr.com <slot number>"
; to disable the SDP.
;
; After writing the ROM to the EEPROM, use the "at28prot.com <slot number>"
; to protect the EEPROM against writes when MSX boots.
;
; How to write and protect the eeprom against undesireable writes:
; 
; 1. Put jumper /wr in the interface
; 2. Plug the interface on the MSX and switch it on
; 3. Write the ROM to the EEPROM, for example: "at28c256 galaga.rom"
; 4. Switch off MSX and remove the interface
; 5. Remove the /wr Jumper
; 6. Plug the interface on the MSX and switch it on. Will boot into the game.
; ====================================================================================

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
    
        ld      hl,txt_credits
        call    print
        ld      hl,txt_ramsearch
        call    print
        call    search_eeprom
; Reenable interrupts that was disabled by RDSLT
        ei
; if could not find the cartridge, exit with error message
        ld      hl,txt_ramnotfound
        jp      c,print
; Found writable memory therefore can continue writing the ROM into the eeprom
instcall:
        push    af
        ld      hl,txt_ramfound
        call    print
        pop     af
        push    af
        call    PRINTNUMBER
        call    PRINTNEWLINE
        ld      hl,txt_ffound
        call    print
        pop     af  ; slot with ram is in (thisslt)
; read filename passed with DOS command line
; and update fcb with filename
        call    resetfcb
        call    readcliparms
        call    openfile
        cp      $ff
        jr      z, fnotfounderr 
        call    setdma
        ld      a,(thisslt)
        ld      h,$40
        call    ENASLT
        ld      a,(thisslt)
        ld      h,$80
        call    ENASLT
        ld      de,$4000
        ld      (curraddr),de
writeeeprom:
        ld      a,'.'
        call    PUTCHAR
        call    readfileregister    ; read 1 block of data from disk
        cp      2
        jr      nc,filereaderr      ; some error
        ld      d,a                 ; save error in D for a while
        ld      a,h
        or      l
        jr      z,endofreading      ; number of bytes read is zero, end.
        push    de                  ; save error code because this might be
                                    ; the last record of the file. will test 
                                    ; at the end of this loop, below.
        ld      b,l     ; hl = number of bytes read from disk, but we are
                        ; reading only 64 bytes at a time
                        ; therefore fits in register b
        ld      hl,dma  ; Area where the record was written
        di

writeeeprom0:
        ld      a,(hl)
        push    bc
        push    hl
        call    writebyte
        pop     hl
        pop     bc
        inc     hl
        djnz    writeeeprom0
        pop     af              ; retrieve the error code
        cp      1               ; 1 = this was last record.
        jr      z,endofreading   
        jr      writeeeprom
endofreading:
        ld      a,(RAMAD1)
        ld      h,$40
        call    ENASLT
        ld      a,(RAMAD2)
        ld      h,$80
        call    ENASLT
        ld      hl,txt_advice
        call    print
        ei
        ret

fnotfounderr:
        ld     hl,txt_fnotfound
        call   print
        ret

writebyte:
        ld      de,(curraddr)
        ld      (de),a
        inc     de
        ld      (curraddr),de   ; Write once to the EEPROM. After this, write is disabled on the EEPRPM
        ret
       
openfile:
        ld     c,$0f
        ld     de,fcb
        call   BDOS
        ret 

filereaderr:
        ld     hl,txt_err_reading
        call   print
        ret
        
readfileregister:
        ld     hl,numregtoread  ; read 128 bytes at a time (register is set to size 1 in fcb)
        ld     c,$27
        ld     de,fcb
        call   BDOS
        ret

setdma:
        ld      de,dma
        ld      c,$1a
        call    BDOS
        ld      hl,regsize      ;tamanho dos registros
        ld      (fcb+14),hl
        dec     hl
        ld      (fcb+32),hl
        ld      (fcb+34),hl
        ld      (fcb+36),hl
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

; ===============================================================
; Get parameters from DOS CLI and parse to get file parameters
; I extracted this part from an old MSX Book I have.
; ===============================================================
readcliparms:
        ld      de,fcb
        xor     a
        ld      (de),a
        ld      hl,dma+1
        call    pulaesp
        call    testacar
        ld      c,a
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      ':'
        ld      a,c
        jr      nz,lenome_ext
        inc     hl
        inc     hl
; CLI paramaters contain drive specification
; 0 = current
; 1 = drive A
; 2 = drive B and so on.
        sub     $41
        jr      c,espinval
        inc     a
        ld      (de),a
        jr      lenome_ext
espinval:
        ld      a,$ff       ; invalid drive to force bdos to return error
        ld      (de),a
lenome_ext:
        inc     de
        ld      c,0
        ld      b,8
        call    lenome
        ld      a,(hl)
        cp      '.'
        jr      nz,fimnome_ext
        inc     hl
        ld      b,3
        call    lenome_0
fimnome_ext:
        ld      a,c
        ret
lenome:
        call    testacar
        jr      c,codesp
        jr      z,codesp
lenome_0:
        call    testacar
        jr      c,tstfimle
        jr      z,tstfimle
        inc     hl
        inc     b
        dec     b
        jr      z,lenome_0
        cp      '*'
        jr      z,coringa
        ld      (de),a
        inc     de
        dec     b
        cp      '?'
        jr      z,acheicor
        jr      lenome_0
coringa:
        call    subscor
acheicor:
        ld      c,1
codesp:
        ld      a,e
        add     a,b
        ld      e,a
        ret     nc
        inc     d
        ret
tstfimle:
        inc     b
        dec     b
        ret     z
        ld      a,' '
        jr      preenche
subscor:
        ld      a,'?'
preenche:
        ld      (de),a
        inc     de
        djnz    preenche
        ret
pulaesp:
        ld      a,(hl)
        inc     hl
        call    testaesp
        jr      z,pulaesp
        dec     hl
        ret
testacar:
        ld      a,(hl)
        cp      'a'
        jr      c,testacar_1
        cp      $7b
        jr      nc,testacar_1
        sub     $20
testacar_1: 
        cp      ':'
        ret     z
        cp      '.'
        ret     z
        cp      $22
        ret     z
        cp      '['
        ret     z
        cp      ']'
        ret     z
        cp      '_'
        ret     z
        cp      '/'
        ret     z
        cp      '+'
        ret     z
        cp      '='
        ret     z
        cp      ';'
        ret     z
        cp      ','
        ret     z
testaesp:
        cp      $09
        ret     z
        cp      ' '
        ret

resetfcb:
        ex    af,af'
        exx
        ld    hl,fcb
        ld    (hl),0
        ld    de,fcb+1
        ld    bc,$23
        ldir
        ld    hl,fcb_fn
        ld    (hl),' '
        ld    de,fcb_fn+1
        ld    bc,10
        ldir
        exx
        ex    af,af'
        ret

; Search for the EEPROM
search_eeprom:
        ld      a,$FF
        ld      (thisslt),a
nextslot:
         di
         call    sigslot
         cp      $FF
         jr      z,endofsearch
         ld      h,$40
         call    ENASLT
         call    testram
         jr      c,nextslot
         ld      a,(RAMAD1)
         ld      h,$40
         call    ENASLT
         ld      a,(thisslt)   ; return the slot where eeprom was found
         or      a
         ret 
endofsearch:
         ld      a,(RAMAD1)
         ld      h,$40
         call    ENASLT
         ld      a,$FF
         scf
         ret 

testram:
        ld      hl,$4000
        ld      a,'A'
        call    write_test
        ret     c
        ld      a,'T'
        call    write_test
        ret     c
        ld      a,'C'
        call    write_test
        ret 

write_test:
        ld      b,a
        ld      (hl),a
        call    waitforwrite
        ld      a,(hl)
        inc     hl
        cp      b
        ret     z
        scf
        ret

waitforwrite:
        push    bc
        ld      bc,300
waitforwrite0:
        push    af
        push    bc
        push    de
        push    hl
        pop     hl
        pop     de
        pop     bc
        pop     af
        dec     bc
        ld      a,b
        or      c
        jr      nz,waitforwrite0
        pop     bc
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

; ==================================================================
; Atmel AT28C256 Programming code
; There SDP (software data protection) available in the eeprom.
; However, I could not make it work on the MSX despite many efforts.
; I believe the MSX is too slow to cope with the eeprom timing reqs.
; I leave the code here for information and documentation purposes.
; ==================================================================
; Disable write-protection
disable_w_prot:
        push    af
        ld      a, $AA
        ld      ($9555),a 
        ld      a, $55
        ld      ($6AAA),a 
        ld      a, $80
        ld      ($9555),a 
        ld      a, $AA
        ld      ($9555),a 
        ld      a, $55
        ld      ($6AAA),a 
        ld      a, $20
        ld      ($9555),a
        call    waitforwrite
        pop     af
        ret

; Enable write-protection
enable_w_prot:
        push    af
        ld      a, $AA
        ld      ($9555),a     ; 0x5555 + 0x4000
        ld      a, $55
        ld      ($6AAA),a     ; 0x2AAA + 0x4000
        ld      a, $A0
        ld      ($9555),a     ; 0x5555 + 0x4000
        call    waitforwrite
        pop     af
        ret

enable_w_prot_final:
        push    af
        ld      a, $AA
        ld      ($9555),a
        ld      a, $55
        ld      ($6AAA),a 
        ld      a, $A0
        ld      ($9555),a 
        ld      b,10
waitloop:
        call    waitforwrite
        djnz    waitloop
        pop     af
        ret

erase_chip:
        push    af
        ld      a, $AA
        ld      ($9555),a 
        ld      a, $55
        ld      ($6AAA),a 
        ld      a, $80
        ld      ($9555),a 
        ld      a, $AA
        ld      ($9555),a 
        ld      a, $55
        ld      ($6AAA),a 
        ld      a, $10
        ld      ($9555),a 
        call    waitforwrite
        pop     af
        ret
; ==============================================================

txt_ramsearch:   db      "Searching for EEPROM",13,10,0
txt_ramfound:   db      "Found writable memory in slot ",0
txt_newline:    db      13,10,0
txt_ramnotfound:   db      "EEPROM not found",13,10,0
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
