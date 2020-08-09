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
; This version does not identify the AT28C256 automatically.
; Before running the EEPROM must have the Software Data Protection disabled,
; otherwise it need the slot to be passed "/i n" where n is a valid MSX slot.
;
; How to write and protect the eeprom against undesireable writes:
; This version can write-protect the EEPROM after write process is completed.
; 
; to phisycally write-protect, remove the WR jumper.
; 
; To rewrite the interface once it has a bootable ROM, the /sltsl or /ce must be 
; disconnectd.
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
XF365:          EQU     $F365       ; routine read primary slotregister

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

RAMAD0:         EQU     $F341       ; slotid DOS ram page 0
RAMAD1:         EQU     $F342       ; slotid DOS ram page 1
RAMAD2:         EQU     $F343       ; slotid DOS ram page 2
RAMAD3:         EQU     $F344       ; slotid DOS ram page 3

; This is a MSX-DOS program
; STart address is $100

    org     $100

    ld      hl,txt_credits
    call    print
    call    resetfcb
    call    parseargs
    ld      a,(ignorerc)
    or      a
    ret     z
    ld      hl,txt_invparms
    ld      a,(parm_found)
    cp      $ff
    jp      z,print
    ld      hl,txt_needfname
    ld      a,(data_option_f)
    cp      $ff
    jp      z,print

    ld      a,(data_option_s)
    cp      $ff
    jr      nz,write
    ld      hl,txt_ramsearch
    call    print
    call    search_eeprom

                                ; if could not find the cartridge, exit with error message
    ld      hl,txt_ramnotfound
    jp      c,print
write:

                                ; Found writable memory (or received slot number
                                ; from CLI) therefore can continue 
                                ; writing the ROM into the eeprom
    push    af
    ld      hl,txt_ffound
    call    print
    ld      hl,txt_writingflash
    call    print
    pop     af
    call    PRINTNUMBER
    call    PRINTNEWLINE

                                ; read filename passed with DOS command line
                                ; and update fcb with filename
    ld      a,(thisslt)
    call    disable_w_prot
    call    openfile
    cp      $ff
    jp      z, fnotfounderr 
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
    jp      nc,filereaderr      ; some error
    ld      d,a                 ; save error in D for a while
    ld      a,h
    or      l
    jr      z,endofreading      ; number of bytes read is zero, end.
    push    de                  ; save error code because this might be
                                ; the last record of the file. will test 
                                ; at the end of this loop, below.
    ld      b,l                 ; hl = number of bytes read from disk, but we are
                                ; reading only 64 bytes at a time
                                ; therefore fits in register b
    ld      hl,dma              ; Area where the record was written
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
    pop     af                      ; retrieve the error code
    cp      1                       ; 1 = this was last record.
    jr      z,endofreading   
    jr      writeeeprom
endofreading:
    ld      a,(RAMAD1)
    ld      h,$40
    call    ENASLT
    ld      a,(RAMAD2)
    ld      h,$80
    call    ENASLT
    ld      a,(thisslt)
    call    enable_w_prot
    ld      hl,txt_advice
    call    print
    ei
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
    ld      a,(thisslt)             ; return the slot where eeprom was found
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

fnotfounderr:
    ld     hl,txt_fnotfound
    call   print
    ret

writebyte:
    ld      de,(curraddr)
    ld      (de),a
    inc     de
    ld      (curraddr),de           ; Write once to the EEPROM. After this, write is 
                                    ; disabled on the EEPRPM
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
    ld     hl,numregtoread          ; read 128 bytes at a time (register is set to size 1 in fcb)
    ld     c,$27
    ld     de,fcb
    call   BDOS
    ret

setdma:
    ld      de,dma
    ld      c,$1a
    call    BDOS
    ld      hl,regsize              ;tamanho dos registros
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
    ld      a,(hl)                  ;get a character to print
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
    call    PUTCHAR                 ;put a character
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

    ; ==============================================================
parseargs:
    ld      hl,$80
    ld      a,(hl)
    or      a
    scf
    ret     z
    ld      c,a
    ld      b,0
    inc     hl
    push    hl
    add     hl,bc
    ld      (hl),0                      ; terminates the command line with zero
    pop     hl
parse_next:
    call    space_skip
    ret     c
    inc     hl
    ld      de,parms_table
    call    table_inspect
    ret     c
    ld      a,(parm_found)
    or      a
    jr      nz,parse_checkendofparms
    pop     hl                          ; get form stack the address of the routine
                                        ; for this parameter
    ld      de,parse_checkendofparms
    push    de
    jp      (hl)                        ; jump to the routine for the parameter
parse_checkendofparms:
    ld      hl,(parm_address)
    jr      parse_next

param_h:
    xor     a
    ld      (ignorerc),a
    ld      hl,txt_help
    call    print
    or      a
    ret

param_s:
    ld      hl,(parm_address)
    call    space_skip
    ld      (parm_address),hl
    ret     c
    ld      a,(hl)
    cp      '0'
    ret     c
    sub     '0'
    ld      b,a
    inc     hl
    ld      (parm_address),hl
    ld      a,(hl)
    or      a
    jr      z,param_s_end
    cp      ' '
    jr      z,param_s_end
    cp      '0'
    jr      c,param_s_end
    ld      a,(hl)
    inc     hl
    ld      (parm_address),hl
    sub     '0'
    ld      c,a
    ld      a,b
    sla     a
    sla     a
    sla     a
    sla     a
    or      c
    ld      b,a
param_s_end:
    ld      a,b
    ld      (data_option_s),a
    ld      (thisslt),a
    ret

param_f:
    call    param_f_getfname
    ld      hl,data_option_f
    ld      de,fcb
    ld      bc,12
    ldir
    ret

param_f_getfname:
    ld      hl,(parm_address)       ; get current address in the bufer
    call    space_skip
    ld      (parm_address),hl
    ld      a,(hl)
    cp      '/'
    ret     z
    ld      de,data_option_f
    ;check if drive letter was passed
    inc     hl
    ld      a,(hl)
    dec     hl
    cp      ':'
    ld      c,0
    jr      nz,parm_f_a
    ld      a,(hl)
    inc     hl
    inc     hl
    cp      'a'
    jr      c,param_is_uppercase
    sub     'a'
    jr      param_checkvalid
param_is_uppercase:
    sub     'A'
param_checkvalid:
    jr      c,param_invaliddrive
    inc     a
    ld      c,a
    jr      parm_f_a
param_invaliddrive:
    ld      c,$ff                ; ivalid drive, BDOS will return error when called    
parm_f_a:
    ld      a,c
    ld      (de),a            ; drive number
    inc     de
    ld      b,8               ; filename in format "filename.ext"
    call    parm_f_0          ; get filename without extension
    ld      b,3               ; filename in format "filename.ext"
    ld      a,(hl)
    cp      '.'
    jr      nz,parm_f_b
    inc     hl
parm_f_b:
    ld      (parm_address),a
    call    parm_f_0          ; get extension
    ret
parm_f_0:
    ld      a,(hl)
    or      a
    jr      z,parm_f_2
    cp      '/'
    jr      z,parm_f_2
    cp      ' '
    jr      z,parm_f_2
    cp      '.'
    jr      z,parm_f_2
parm_f_1:
    ld      (de),a
    inc     hl
    inc     de
    djnz    parm_f_0
    ld      (parm_address),hl
    ret
parm_f_2:
    ld      a,' '
    ld      (de),a
    inc     de
    djnz    parm_f_2
    ld      (parm_address),hl
    ret

param_i:
    xor     a
    ld      (ignorerc),a

    ld      a,(data_option_s)
    cp      $ff
    jr      nz,param_i_show         ; received slot numnber from cli
                                    ; Search for the EEPROM for at28show command
search_cart:
    ld      a,$FF
    ld      (thisslt),a
search_cart0:
    di
    call    sigslot
    cp      $FF
    jr      z,search_cart_end
    ld      h,$40
    call    ENASLT
    call    test_cart
    jr      c,search_cart0
    call    showcontent
    jr      search_cart0

search_cart_end:
    ld      a,(RAMAD1)
    ld      h,$40
    call    ENASLT
    ld      a,$FF
    scf
    ret

param_i_show:
    ld      a,(thisslt)
    ld      h,$40
    call    ENASLT
    call    showcontent
    call    PRINTNEWLINE
    ld      a,(RAMAD1)
    ld      h,$40
    call    ENASLT
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
    ld      hl,txt_slot
    call    print
    ld      a,(thisslt)
    call    PRINTNUMBER
    ld      a,':'
    call    PUTCHAR
    ld      hl,$4000
    ld      b,24
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

; ================================================================================
; table_inspect: get next parameters in the buffer and verify if it is valid
; then return the address of the routine to process the parameter
;
; Inputs:
; HL = address of buffer with parameters to parse, teminated in zero
; Outputs:
; HL = address of the buffer updated
; Stack = address of the routine for the parameter
; 

table_inspect:
    ld      a,$ff
    ld      (parm_index),a
    ld      (parm_found),a
table_inspect0:
    push    hl                       ; save the address of the parameters
table_inspect1:
    ld      a,(hl)
    cp      ' '
    jr      z,table_inspect_cmp
    or      a
    jr      z,table_inspect_cmp
    ld      c,a
    ld      a,(de)
    cp      c
    jr      nz,table_inspect_next   ; not this parameters, get next in the table
    inc     hl
    inc     de
    jr      table_inspect1
table_inspect_cmp:
    ld      a,(de)
    or      a
    jr      nz,table_inspect_next   ; not this parameters, check next in the table
    inc     de
    pop     af                      ; discard HL to keep current arrgs index
    xor     a
    ld      (parm_found),a
    ld      a,(de)
    ld      c,a
    inc     de
    ld      a,(de)
    ld      b,a
    pop     de                      ; get ret address out of the stack temporarily
    push    bc                      ; push the routine address in the stack
    push    de                      ; push the return addres of this routine back in the stack
    ld      (parm_address),hl
    scf
    ccf
    ret

table_inspect_next:
    ld      a,(de)
    inc     de
    or      a
    jr      nz,table_inspect_next
    ld      a,(parm_index)
    inc     a
    ld      (parm_index),a    ; this index will tell which parameter was found
    pop     hl
    inc     de
    inc     de
    ld      a,(de)
    or      a
    jr      nz,table_inspect0
    scf
    ret

; Skip spaces in the args.
; Inputs: 
; HL = memory address to start testing
;
; Outputs:
; HL = updated memory address 
; Flac C: set if found end of string (zero)
;
space_skip:
    ld      a,(hl)
    or      a
    scf
    ret     z
    cp      ' '
    scf
    ccf
    ret     nz
    inc     hl
    jr      space_skip

; ==================================================================
; Atmel AT28C256 Programming code
; routinefor SDP (software data protection) available in the eeprom.
; ==================================================================
; Enable write-protection
enable_w_prot:
    push    af
    ld      h,$40
    call    ENASLT
    pop     af
    ld      h,$80
    call    ENASLT
    ld      a, $AA
    ld      ($9555),a     ; 0x5555 + 0x4000
    ld      a, $55
    ld      ($6AAA),a     ; 0x2AAA + 0x4000
    ld      a, $A0
    ld      ($9555),a     ; 0x5555 + 0x4000
    call    waitforwrite
    ld      a,(RAMAD1)
    ld      h,$40
    call    ENASLT
    ld      a,(RAMAD2)
    ld      h,$80
    call    ENASLT
    ret

; Disable write-protection
disable_w_prot:
    push    af
    ld      h,$40
    call    ENASLT
    pop     af
    ld      h,$80
    call    ENASLT
    ld      a,$AA
    ld      ($9555),a 
    ld      a,$55
    ld      ($6AAA),a 
    ld      a,$80
    ld      ($9555),a 
    ld      a,$AA
    ld      ($9555),a 
    ld      a,$55
    ld      ($6AAA),a 
    ld      a,$20
    ld      ($9555),a
    call    waitforwrite
    ld      a,(RAMAD1)
    ld      h,$40
    call    ENASLT
    ld      a,(RAMAD2)
    ld      h,$80
    call    ENASLT
    ret

; Search for the EEPROM
search_eeprom_for_future_improvement:
    di
    call    sigslot
    cp      $FF
    jr      z,search_eeprom_end
    ld      h,$40
    call    ENASLT
    ld      a,(thisslt)
    ld      h,$80
    call    ENASLT

    call   save_tested_bytes      ; savem the address used to enable SDP
    call   disable_w_prot
    ;                             ; re-enable current slot for the memory tests
    ld      a,(thisslt)
    ld      h,$40
    call    ENASLT
    ld      a,(thisslt)
    ld      h,$80
    call    ENASLT
    ;
    call   compare_with_sdp_bytes   ; compare ram with the sdp control bytes
    jr     z,restore_bytes          ; if same, the ram is not ATC28C256 
                                    ; the memory was not overwritten by sdp control bytes
    call   test_for_ram             ; Now test if can write to the memory
                                    ; since we potentially disabled SDP
    jr     z,restore_slots          ; found the eeprom 
                                    ; otherwise continue looking
restore_bytes:
    call   restore_tested_bytes     ; this slot is not AT28C256
    jp     search_eeprom            ; test next slot

restore_slots:
    ld      a,(RAMAD1)
    ld      h,$40
    call    ENASLT
    ld      a,(RAMAD2)
    ld      h,$80
    call    ENASLT
    ei
    ret 
search_eeprom_end:
    call     restore_slots
    scf
    ret

save_tested_bytes:
    ld     a,($9555)
    ld     (eeprom_saved_bytes),a
    ld     a,($6AAA)
    ld     (eeprom_saved_bytes + 1),a
    ret
restore_tested_bytes:
    ld     a,(eeprom_saved_bytes)
    ld     ($9555),a
    ld     a,(eeprom_saved_bytes + 1)
    ld     ($6AAA),a
    ret
compare_with_sdp_bytes:
    ld     hl,eeprom_saved_bytes
    ld     a,($9555)
    cp     (hl)
    ret    z
    inc    hl
    ld     a,($6AAA)
    cp     (hl)
    ret

; write 'ATC' to address $4000,4001,4002
; Restore the original values before exiting the routine
; C flag set if written value was not verified (that is, not RAM)
;
test_for_ram:
    ld      hl,$4000
    ld      a,(hl)
    ld      b,a
    ld      a,'A'
    ld      (hl),a
    inc     hl
    ld      a,(hl)
    ld      c,a
    ld      a,'T'
    ld      (hl),a
    inc     hl
    ld      a,(hl)
    ld      d,a
    ld      a,'C'
    ld      (hl),a
    call    wait_eeprom
    ld      a,d
    cp      (hl)
    ret     nz
    dec     hl
    ld      a,c
    cp      (hl)
    ret     nz
    dec     hl
    ld      a,b
    cp      (hl)
    ret

wait_eeprom:
    push    bc
    ld      bc,300
wait_eeprom0:
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
    jr      nz,wait_eeprom0
    pop     bc
    ret

    txt_slot: db "Slot ",0
    txt_ramsearch: db "Searching for EEPROM",13,10,0
    txt_ramfound:  db "Found writable memory in slot ",0
    txt_newline:   db 13,10,0
    txt_ramnotfound: db "EEPROM not found",13,10,0
    txt_writingflash: db "Writing file to EEPROM in slot ",0
    txt_completed: db "Completed.",13,10,0
    txt_nofn: db "Filename is empty or not valid",13,10,0
    txt_fileopenerr: db "Error opening file",13,10,0
    txt_fnotfound: db "File not found",13,10,0
    txt_ffound: db "Reading file from disk",13,10,0
    txt_err_reading: db "Error reading data from file",13,10,0
    txt_endoffile: db "End of file",13,10,0
    txt_noparams: db "No command line parameters passed",13,10,0
    txt_parm_f: db "Filename:",13,10,0
    txt_exit: db "Returning to MSX-DOS",13,10,0
    txt_needfname: db "File name not specified",13,10,0
    txt_unprotecting: db "Disabling AT28C256 Software Data Protection on slot:",0
    txt_protecting: db "Enabling AT28C256 Software Data Protection on slot:",0
    txt_param_dx_err1: db 13,10,"Error - missing parameter /s <slot> before parameter /dx",13,10,0
    txt_param_ex_err1: db 13,10,"Error - missing parameter /s <slot> before parameter /ex",13,10,0
    txt_credits: db "AT28C256 EEPROM Programmer for MSX",13,10
    db "(c) Ronivon Costa, 2020",13,10,13,10,0
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
    txt_invparms: db "Invalid parameters",13,10
    txt_help: db "Command line options: at28c256 </h | /i> </s /f file.rom>",13,10,13,10
    db "/h Show this help",13,10
    db "/s <slot number>",13,10
    db "/i Show initial 24 bytes of the slot cartridge",13,10
    db "/f File name with extension, for example game.rom",13,10,0

parms_table:    
    db "h",0
    dw param_h
    db "help",0
    dw param_h
    db "i",0
    dw param_i
    db "s",0
    dw param_s
    db "f",0
    dw param_f
    db 0                ; end of table. this byte is mandatory to be zero

thisslt:        db $FF
parm_index:     db $ff
parm_found:     db $ff
ignorerc:       db $ff
data_option_s:  db $ff
data_option_f:  db $ff,0,0,0,0,0,0,0,0,0,0,0,0
parm_address:   dw 0000
curraddr:       dw 0000
eeprom_saved_bytes:  db 0,0,0

fcb:
                        ; reference: https://www.msx.org/wiki/FCB    
fcb_drv: db 0           ; Drive number containing the file.
                        ; (0 for Default drive, 1 for A, 2 for B, ..., 8 for H)

fcb_fn: db "filename"   ; 8 bytes for filename and 3 bytes for its extension. 
db "ext"                ; When filename or extension has less than 8 or 3, the rest are 
                        ; filled in by spaces (20h). In case of search "?" (3Fh) may be used
                        ; to represent any character.
fcb_ex: db 0            ; "Current block LO" or "Extent number LO" depending of function called.
fcb_s1: db 0            ; "Current block HI" or "File attributes" (DOS2) depending of function called.
fcb_s2: db 0            ; "Record size LO" or "Extent number HI" depending of function called. 
                        ; NOTE: Because of Extent number the record size must be manually 
                        ; defined after opening a file!
fcb_rc: db 0            ; "Record size HI" or "Record count" depending of function called.
fcb_al: db 0,0,0,0      ; File size in bytes (1~4294967296).
db 0,0                  ; Date (DOS1) / Volume ID (DOS2)
db 0,0                  ; Time (DOS1) / Volume ID (DOS2)
db 0                    ; Device ID. (DOS1)
                        ; FBh = PRN (Printer)
                        ; FCh = LST (List)
                        ; FCh = NUL (Null)
                        ; FEh = AUX (Auxiliary)
                        ; FFh = CON (Console)
db 0                    ; Directory location. (DOS1)
db 0,0                  ; Top cluster number of the file. (DOS1)
db 0,0                  ; Last cluster number accessed (DOS1)
db 0,0                  ; Relative location from top cluster of the file number of clusters
                        ; from top of the file to the last cluster accessed. (DOS1)
fcb_cr: db 0            ; Current record within extent (0...127)
fcb_rn: db 0,0,0,0      ; Random record number. If record size <64 then all 4 bytes will be used.
db 0,0,0
