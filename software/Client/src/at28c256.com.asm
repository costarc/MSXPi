;|===========================================================================|
;|                       |
;| MSX Software for Cartridge AT28C256 32K EEPROM        |
;|                       |
;| Version : 1.4                 |
;|                       |
;| Copyright (c) 2020-2023 Costa RC (ronivon@outlook.com)        |
;|                       |
;| All rights reserved                   |
;|                       |
;| Redistribution and use in source and compiled forms, with or without      |
;| modification, are permitted under GPL license.        |
;|                       |
;|===========================================================================|
;|                       |
;| This file is part of msxcart_flash32k project.        |
;|                       |
;| msxcart_flash32k is free software: you can redistribute it and/or modify  |
;| it under the terms of the GNU General Public License as published by      |
;| the Free Software Foundation, either version 3 of the License, or     |
;| (at your option) any later version.               |
;|                       |
;| MSX PI Interface is distributed in the hope that it will be useful,       |
;| but WITHOUT ANY WARRANTY; without even the implied warranty of    |
;| MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the     |
;| GNU General Public License for more details.          |
;|                       |
;| You should have received a copy of the GNU General Public License     |
;| along with MSX PI Interface.  If not, see <http://www.gnu.org/licenses/>. |
;|===========================================================================|
;
; Compile this file with z80asm:
;  z80asm at28c256.asm -o at28c256.com
; 
; File history :
; 1.0  - 27/06/2020 : initial version
;    05/08/2020 : Revised version
; 1.1 - 24/08/2020 : Improved parsing of filename
; 1.2 - 26/02/2023 : Changed how slots are detected and added support to display extended slots
;      - Changed way how EEPROM is detected and fixed bug that was writting to MSX RAM in some models
; 1.3 - Changes to the write logic to address some issues with some eeproms
; 1.4 - Added option /r via command line to write very slowly to the eeprom 
;
; Note on this code:
; This version does not identify the AT28C256 automatically.
; Before running the EEPROM must have the Software Data Protection disabled,
; otherwise it need the slot to be passed "/i n" where n is a valid MSX slot.
;
; How to write and protect the eeprom against undesireable writes:
; This version will automatically write-protect the EEPROM (via chip SDP protocol) 
; after write process is completed.
; 
; The /WR jumper is basically useless, and was removed in newer versions of the PCB.
; 
; To re-write the interface once it has a bootable ROM, remove the CS12 jumper 
; (SLTSL in most recent PCBs) 
; ====================================================================================

regsize:    equ     1
numregtoread:   equ     512
TEXTTERMINATOR: EQU     0
BDOS:       EQU     5
CALLSTAT:       EQU     $55A8
INLINBUF:       EQU     $F55E
INLIN:      EQU     $00B1
CHPUT:      EQU     $00A2
CHGET:      EQU     $009F
INITXT:     EQU     $006C
EXPTBL:     EQU     $FCC1
RDSLT:      EQU     $000C
WRSLT:      EQU     $0014
CALSLT:     EQU     $001C
ENASLT:     EQU     $0024
RSLREG:     EQU     $0138
WSLREG:     EQU     $013B
CSRY:       EQU     $F3DC
CSRX:       EQU     $F3DD
ERAFNK:     EQU     $00CC
DSPFNK:     EQU     $00CF
PROCNM:     EQU     $FD89
XF365:      EQU     $F365       ; routine read primary slotregister

DEVICE:     equ     0FD99H

txttab:     equ     $f676
vartab:     equ     $f6c2
arytab:     equ     $f6c4
strend:     equ     $f6c6
SLTATR:     equ     $fcc9
CALBAS:     equ     $0159
CHRGTR:     equ     $4666

ERRHAND:    EQU     $406F
FRMEVL:     EQU     $4C64
FRESTR:     EQU     $67D0
VALTYP:     EQU     $F663
USR:    EQU     $F7F8
ERRFLG:     EQU     $F414
HIMEM:      EQU     $FC4A
MSXPICALLBUF:   EQU     $E3D8

RAMAD0:     EQU     $F341       ; slotid DOS ram page 0
RAMAD1:     EQU     $F342       ; slotid DOS ram page 1
RAMAD2:     EQU     $F343       ; slotid DOS ram page 2
RAMAD3:     EQU     $F344       ; slotid DOS ram page 3

; This is a MSX-DOS program
; Start address is $100

    org     $100
    ld    a,$ff
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
   ; if could not find the cartridge, exit with error message
    ld      hl,txt_param_s_missing
    jp      print   
    
write:
    
    call    testEpromWrite
    jp    c,notEprom    ; did not find the EEPROM
    
; given the slot passed in command line,
; verify if it is expanded and added the final slot configuration to expandedslt
; call    getExpandedSlot    
; will write only to primary slots
    
; Found writable memory (or received slot number
; from CLI) therefore can continue 
; writing the ROM into the eeprom

    ld      hl,txt_ffound
    call    print
    ld      hl,fcb+1
    call    PRINTFCBFNAME
    call    PRINTNEWLINE
    ld      hl,txt_writingflash
    call    print
    ld      a,(thisslt)
    call    PRINTNUMBER
    call    PRINTNEWLINE

            ; read filename passed with DOS command line
            ; and update fcb with filename
    call    openfile
    cp      $ff
    jp      z, fnotfounderr 
    call    setdma
    ld      de,$4000
    ld      (curraddr),de
    ld      a,(thisslt)
    call    erase_chip

writeeeprom:
    ld      a,(data_option_z)
    call    PUTCHAR
    call    readfileregister    ; read 1 block of data from disk
    cp      2
    jp      nc,filereaderr      ; some error
    ld      d,a         ; save error in D for a while
    ld      a,h
    or      l
    jr      z,endofreading    ; number of bytes read is zero, end.
    push    de    ; save error code because this might be
            ; the last record of the file. will test 
            ; at the end of this loop, below.
    ;ld      b,0         ; hl = number of bytes read from disk, but we are
    ;ld      c,l    ; are using a fixed 512 bytes
    ld      bc,numregtoread

write_set:
    di
    ld     a,(data_option_r)
    or     a
    jr     z,writeeeprom0
    call   ByteModeSlow
    jr     writeeeprom1
    
writeeeprom0:
    call     BlockModeFast

writeeeprom1:
    pop     af          ; retrieve the error code
    cp      1           ; 1 = this was last record. 
    jr    nz,writeeeprom

endofreading:
    di
    call    enable_w_prot
    call    restore_ram_slots
    ld      a,(data_option_p)
    cp      1
    ;call    z,param_p_patch_rom
    ld      hl,txt_advice
    call    print
    ld      a,5

safety_wait:
    push    af
    call    wait_eeprom
    pop     af
    dec     a
    or      a
    jr      nz,safety_wait
    ei
    ret
    
writeretry:
    ld      a,(retries)
    dec     a
    or      a
    jr      z,wexitfail
    ld      (retries),a
    ld      (curraddr),de
    jr      write_set

wexitfail:
    pop     af    ; discard file read error code
    call    enable_w_prot
    call    restore_ram_slots
    ld      hl,txt_writefailed
    call    print
    ret
    
notEprom:
    ld      hl,txt_ramfoundnoteeprom
    cp      1
    jr      z,notEprom2
    ld      hl,txt_ramnotfound
notEprom2:
    call    print
    ld      a,(thisslt)
    call    PRINTNUMBER
    call    PRINTNEWLINE
    ret
    
enable_eeprom_slot:
    ld      a,(thisslt)
    ld      h,$40
    call    ENASLT
    ld      a,(thisslt)
    ld      h,$80
    call    ENASLT
    ret

restore_ram_slots:
    ld      a,(RAMAD1)
    ld      h,$40
    call    ENASLT
    ld      a,(RAMAD2)
    ld      h,$80
    call    ENASLT
    ret

testEpromWrite:
; Will run tests in the slot number passed via command line
; to try and determine if the slot is actually the flash or the computer RAM

; tag ram in current slot to check later after tried to write the the flash
; when writting to the flash, the RAM is this slot must no be changed - if it does
; then program is not writing to the eeprom correctly
    call    savePage0Hdr        ; save $4000 header in ram in current slot
    call    writePage0TestHdr    ; write to the ram in the slot passed by command line
    call    checkPage0Hrd
    push    af
    call    restorePage0Hdr    
    pop     af
    ret
    
checkPage0Hrd:    
    ; now check this RAM page 0 header
    ; if match bytes written to SLOT, its is incorrect!!
    
    ld    a,($4000)        ; read current by in this ram
    ld    b,a    
    ld    a,(workarea + 0)    
    cp    b            ; compare to what was there before
    ld    a,1
    scf    
    ret   nz            ; if different, flags error (scf) and return
            ; it means the slot switch did not work and the program wrote to ram instead of EEPROM

    ; repeat the test for the other two bytes
    ld    a,($4001)        ; read current by in this ram
    ld    b,a    
    ld    a,(workarea + 1)    
    cp    b            ; compare to what was there before
    ld    a,1
    scf    
    ret    nz            ; if different, flags error (scf) and return

    ld    a,($4002)        ; read current by in this ram
    ld    b,a    
    ld    a,(workarea + 2)    
    cp    b            ; compare to what was there before
    ld    a,1
    scf    
    ret    nz            ; if different, flags error (scf) and return

    ; this RAM was not changed - thats good.
    ; now will check the EEPROM and see if it was correctly written
    
    call    enable_eeprom_slot    ; switch to the slot with the eeprom
    call    testPage0SlotHdr
    push    af        ; save flags with return code
    call    restore_ram_slots
    pop     af
    ret
    
testPage0SlotHdr:
    ld    a,($4000)
    cp    'A'
    scf        ; flag error - header not found in the eeprom
    ld    a,2
    ret   nz
    ld    a,($4001)
    cp    'T'
    scf        ; flag error - header not found in the eeprom
    ld    a,2
    ret   nz
    ld    a,($4002)
    cp    'C'
    scf        ; flag error - header not found in the eeprom
    ld    a,2
    ret   nz
    scf        ; set error flag
    ccf        ; to 0 to flag the eeprom was correctly found and written
    ret
     
savePage0Hdr:
    ld    a,($4000)
    ld    (workarea + 0),a
    ld    a,($4001)
    ld    (workarea + 1),a
    ld    a,($4002)
    ld    (workarea + 2),a
    ret
    
restorePage0Hdr:
    ld    a,(workarea + 0)
    ld    ($4000),a
    ld    a,(workarea + 1)
    ld    ($4001),a
    ld    a,(workarea + 2)
    ld    ($4002),a
    ret

writePage0TestHdr:
    ld    a,(thisslt)
    call  enable_eeprom_slot    ; enable the eeprom slot (from command line)
    call  disable_w_prot
    ld    hl,$4000
    ld    a,'A'
    ld    (hl),a
    inc   hl
    call  wait_eeprom
    ld    a,'T'
    ld    (hl),a
    inc   hl
    call  wait_eeprom
    ld    a,'C'
    ld    (hl),a
    call  wait_eeprom
    call  enable_w_prot
    call  restore_ram_slots    ; restore the original RAM slots
    ret 

BlockModeFast:
    ld     a,(thisslt)
    call   enable_eeprom_slot    ; enable the eeprom slot (from command line)
    call   disable_w_prot
    ld     hl,dma
    ld     de,(curraddr)
    ld     b,8        ; will write 64 bytes every time (8 * 64 = 512)
wr_blk_fast:
    push   bc
    ld     bc,64
    LDIR
    call   wait_eeprom2
    pop    bc
    djnz   wr_blk_fast
    ld     (curraddr),de
    call   enable_w_prot
    call   restore_ram_slots    ; restore the original RAM slots
    ret 

; Very slow write mode
; Write one byte at a time, with delays between each write operation
; Also re-enable / disable slots on every block
ByteModeSlow:
    ld      hl,dma
    ld      de,(curraddr)
    ld      bc,numregtoread
    push    bc
    push    de
    push    hl
    ld      a,(thisslt)
    call    enable_eeprom_slot    ; enable the eeprom slot (from command line)
    di
    call    disable_w_prot
    pop     hl
    pop     de
    pop     bc
wr_blk_slow:
    ld      a,(hl)
    ld     (de),a
    inc     hl
    inc     de
    call    wait_eeprom2
    dec     bc
    ld      a,b
    or      c
    jr      nz,wr_blk_slow
    push    de
    call    enable_w_prot
    call    restore_ram_slots    ; restore the original RAM slots
    pop     de
    ld     (curraddr),de
    ret 
     
fnotfounderr:
    ld     hl,txt_fnotfound
    call   print
    ret

verifywrite:
    push    bc
    push    de
    jr    verifywrite_set
    ; forceing an error to test verification code
    ld    a,(retries)
    cp    3
    jr    z,inserterror
    cp     0
    jr    z,removeerror
    jr    verifywrite_set
inserterror:
    ld    ix,dma
    ld    a,(ix+62)
    ld    (workarea),a
    ld    a,$FF
    ld    (ix+62),a
    jr    verifywrite_set
removeerror:
    ld    ix,dma
    ld    a,(workarea)
    ld    (ix+62),a
verifywrite_set:
    ld    c,b
    ld    b,0    ; only 64 bytes, but the data is in b
verifywrite0:
    ld    a,(de)
    cpi        ; compare with A, inc hl, dec bc
    jr    nz,verifywrite1
    inc    de
    ld    a,b
    or    c
    jr    nz,verifywrite0
    ld    a,'='
    call    PUTCHAR
    or    a        ; eeprom data matches with buffer
    pop    de
    pop    bc
    ret
verifywrite1:
    ld    a,'!'
    ld    (writefailed),a
    call    PUTCHAR
    pop    de
    pop    bc
    scf        ; flag the error
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
    ld     hl,numregtoread      ; read 64 bytes at a time (register is set to size 1 in fcb)
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
    ; PRINT    |
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
    ; PRINTNUMBER      |
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

; --------   http://map.grauw.nl/sources/getslot.php. --------
; GetSlotID

; h = memory address high byte (bits 6-7: page)
; a <- slot ID formatted F000SSPP
; Modifies: f, bc, de
Memory_GetSlot:
    call RSLREG
    bit 7,h
    jr z,PrimaryShiftContinue
    rrca
    rrca
    rrca
    rrca
PrimaryShiftContinue:
    bit 6,h
    jr z,PrimaryShiftDone
    rrca
    rrca
PrimaryShiftDone:
    and 00000011B
    ld c,a
    ld b,0
    ex de,hl
    ld hl,EXPTBL
    add hl,bc
    ex de,hl
    ld a,(de)
    and 80H
    or c
    ret p
    ld c,a
    inc de  ; move to SLTTBL
    inc de
    inc de
    inc de
    ld a,(de)
    bit 7,h
    jr z,SecondaryShiftContinue
    rrca
    rrca
    rrca
    rrca
SecondaryShiftContinue:
    bit 6,h
    jr nz,SecondaryShiftDone
    rlca
    rlca
SecondaryShiftDone:
    and 00001100B
    or c
    ret
; ---------------------------------------------

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

;-------------------------------------------
; print file name from FCB properly parsed |
;-------------------------------------------
PRINTFCBFNAME:
    ld       b,8
    call     PRINTFCBFNAME2
    ld       a,'.'
    call     PUTCHAR
    ld       b,3
    call     PRINTFCBFNAME2
    ret
PRINTFCBFNAME2:
    ld       a,(hl)
    inc      hl
    cp       ' '
    jr       z,PRINTFCBFNAME3
    call     PUTCHAR
PRINTFCBFNAME3:
    djnz     PRINTFCBFNAME2
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
    ld      a, (thisslt)    ; Returns the next slot, starting by
    cp      $FF         ; slot 0. Returns #FF when there are not more slots
    jr      nz, .p1         ; Modifies AF, BC, HL.
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
    ld      (hl),0          ; terminates the command line with zero
    pop     hl
parse_next:
    call    space_skip
    jr      c,parse_filename
    inc     hl
    ld      de,parms_table
    call    table_inspect
    jr      c,parse_filename
    ld      a,(parm_found)
    or      a
    jr      nz,parse_checkendofparms
    pop     hl          ; get the address of the routine
            ; for this parameter
    ld      de,parse_checkendofparms
    push    de
    jp      (hl)        ; jump to the routine for the parameter
parse_checkendofparms:
    ld      hl,(parm_address)
    jr      parse_next
    
; After parsing is complete for all options, run another check to check
; if filename was provided without the "/f" option. However, /if "/f" had
; already been provided, will simply ignore en exit this routine.
parse_filename:
    ld      a,(data_option_f)
    cp      $ff
    ret     nz
    ld      hl,$80
    ld      a,(hl)
    cp      2
    ret     c
parse_filename1:
    inc     hl
    ld      a,(hl)
    or      a
    jr      nz,parse_filename1
parse_filename2:
    dec     hl
    ld      a,(hl)
    cp      ' ' 
    jr      nz,parse_filename2
    inc     hl
    ld      (parm_address),hl
    xor      a
    ld      (parm_found),a
    jp      param_f


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
    push    hl           ; save the address of the parameters
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
    pop     af          ; discard HL to keep current arrgs index
    xor     a
    ld      (parm_found),a
    ld      a,(de)
    ld      c,a
    inc     de
    ld      a,(de)
    ld      b,a
    pop     de          ; get ret address out of the stack temporarily
    push    bc          ; push the routine address in the stack
    push    de          ; push the return addres of this routine back in the stack
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
    ld      a, $AA
    ld      ($9555),a     ; 0x5555 + 0x4000
    ld      a, $55
    ld      ($6AAA),a     ; 0x2AAA + 0x4000
    ld      a, $A0
    ld      ($9555),a     ; 0x5555 + 0x4000
    call    wait_eeprom
    ret

; Disable write-protection
disable_w_prot:
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
    call    wait_eeprom
    ret

; Chip Erase
erase_chip:
    ld      a, $AA
    ld      ($9555),a     ; 0x5555 + 0x4000
    ld      a, $55
    ld      ($6AAA),a     ; 0x2AAA + 0x4000
    ld      a, $80
    ld      ($9555),a     ; 0x5555 + 0x4000
    ld      a, $AA
    ld      ($9555),a     ; 0x5555 + 0x4000
    ld      a, $55
    ld      ($6AAA),a     ; 0x2AAA + 0x4000
    ld      a, $10
    ld      ($9555),a     ; 0x5555 + 0x4000
    call    wait_eeprom
    ret

wait_eeprom:
    push    bc
    ld      bc,300
    call    wait_eeprom0    
    pop     bc
    ret
wait_eeprom2:
    push    bc
    ld      bc,300
    call    wait_eeprom0    
    pop     bc
    ret
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
    ret
    
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
    ld      c,$ff    ; ivalid drive, BDOS will return error when called    
parm_f_a:
    ld      a,c
    ld      (de),a    ; drive number
    inc     de
    ld      b,8       ; filename in format "filename.ext"
    call    parm_f_0      ; get filename without extension
    ld      b,3       ; filename in format "filename.ext"
    ld      a,(hl)
    cp      '.'
    jr      nz,parm_f_b
    inc     hl
parm_f_b:
    ld      (parm_address),a
    call    parm_f_0      ; get extension
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
    jp      nz,param_i_show     ; received slot numnber from cli
            ; Search for the EEPROM for at28show command
search_cart:
    ld      a,$FF
    ld      (thisslt),a
search_cart0:
    call    sigslot
    cp      $FF
    ret     z
    call    checkHdr
    jr      c,search_cart0
    call    showcontent
    jr      search_cart0

param_e:
    xor     a
    ld      (ignorerc),a
    ld      a,(data_option_s)
    cp      $ff
    ld      hl,txt_param_s_missing
    jp      z,print
    ld      hl,txt_erasing
    call    print
    call    enable_eeprom_slot
    call    erase_chip
    call    restore_ram_slots
    or      a
    ret

param_z:
    ld      a,'>'
    ld      (data_option_z),a
    or      a
    ret

param_r:
    ld      a,1
    ld      (data_option_r),a
    ret
    
checkHdr:
    ld      hl,txt_nextslot
    call    print
    ld      a,(thisslt)
    bit     7,a
    jr      z,checkHdrnotexpanded
    ld      b,a
    and     %00000011
    push    bc
    call    PRINTNUMBER
    ld      a,'.'
    call    PUTCHAR
    pop     bc
    ld      a,b
    and     %00001100
    sra     a
    sra     a
checkHdrnotexpanded:
    call    PRINTNUMBER
    call    PRINTNEWLINE
    call    enable_eeprom_slot
    ld      a,($4000)
    cp      'A'
    scf
    jr      nz,checkHdr_end
    ld      a,($4001)
    cp      'B'
    jr      z,checkHdr_end
    scf
checkHdr_end:
    push    af
    call    restore_ram_slots
    pop     af
    ret
    
param_i_show:
    call    enable_eeprom_slot
    call    showcontent
    call    PRINTNEWLINE
    call    restore_ram_slots
    ret

showcontent:
    ld      hl,$4000
    ld      b,6
    call    showcontent0
    ld      hl,$4010
    ld      b,6
    call    showcontent0
    call    PRINTNEWLINE
    ret
      
showcontent0:
    exx
    call    enable_eeprom_slot
    exx
    ld      a,(hl)
    call    PRINTNUMBER
    ld      a,' '
    push    bc
    call    PUTCHAR
    pop     bc
    inc     hl
    djnz    showcontent0
    call    restore_ram_slots
    ret

param_p:
    ld     a,1
    ld     (data_option_p),a
    ret

param_p_patch_rom:
    ld     hl,txt_patching_rom
    call   print

    call   wait_eeprom
    call   enable_eeprom_slot
    call   disable_w_prot
    call   wait_eeprom

    ld     hl,($4002)
    ld     (param_p_jump + 1),hl
    ld     hl,$8000 - (parap_p_end - param_p_patch)
    LD     ($4002),hl

    call   wait_eeprom
    call   wait_eeprom

    ld     bc,parap_p_end - param_p_patch
    ld     hl,param_p_patch
    ld     de,$8000 - (parap_p_end - param_p_patch)
param_p_patch_rom_wloop:
    ld     a,(hl)
    ld     (de),a
    inc    hl
    inc    de
    dec    bc
    ld     a,b
    or     c
    jr     nz,param_p_patch_rom_wloop

    call    wait_eeprom
    call    enable_w_prot
    call    restore_ram_slots
    ret

param_p_patch:
    ld    a,7
    call  $0141
    bit   2,a
    ret   z
param_p_jump:
    jp    $0000

parap_p_end: equ $

ROM_NEW_INIT: EQU $400A

txt_erasing:		db "Erasing the EEPROM...",0
txt_slot:		db "Slot ",0
txt_nextslot:		db "Checking slot ",0
txt_ramsearch:		db "Searching for EEPROM",13,10,0
txt_ramfound:		db "Found writable memory in slot ",0
txt_ramfoundnoteeprom:	db "Found writable memory but its not the eeprom in slot ",0
txt_newline:		db 13,10,0
txt_ramnotfound:	db "EEPROM not found in slot ",0
txt_writingflash:	db "Writing file to EEPROM in slot ",0
txt_completed:		db "Completed.",13,10,0
txt_nofn:		db "Filename is empty or not valid",13,10,0
txt_fileopenerr:	db "Error opening file",13,10,0
txt_fnotfound:		db "File not found",13,10,0
txt_ffound:		db "Reading file from disk:",0
txt_err_reading:	db "Error reading data from file",13,10,0
txt_endoffile:		db "End of file",13,10,0
txt_noparams:		db "No command line parameters passed",13,10,0
txt_parm_f:		db "Filename:",13,10,0
txt_exit:		db "Returning to MSX-DOS",13,10,0
txt_needfname:		db "File name not specified",13,10,0
txt_unprotecting:	db "Disabling AT28C256 Software Data Protection on slot:",0
txt_protecting:		db "Enabling AT28C256 Software Data Protection on slot:",0
txt_param_s_missing:	db 13,10,"Error - parameter /s <slot> must come first or it is missing",13,10,0
txt_param_dx_err1:	db 13,10,"Error - missing parameter /s <slot> before parameter /dx",13,10,0
txt_param_ex_err1:	db 13,10,"Error - missing parameter /s <slot> before parameter /ex",13,10,0
txt_patching_rom:	db 13,10,"Patching ROM. Use ESC to bypass ROM boot",13,10,0
txt_advice:		db 13,10
			db "Write process completed",13,10,0
txt_writefailed:	db 13,10,"Writing process failed!",13,10
			db  "Check if eeprom legs are clean,",13,10
			db "and well seated in the socket (if socketed).",13,10,0
txt_invparms:		db "Invalid parameters",13,10
txt_help:		db "Command line options: at28c256 </h | /i | /e> | </s <slot> </r> </f> file.rom>",13,10,13,10
			db "/h Show this help",13,10
			db "/i Show initial 24 bytes of the slot cartridge",13,10
			db "/e Erase the EEPROM",13,10
			db "/s <slot number>",13,10
			db "/r Slow write to work around unstable eeproms",13,10
			db "/f File name with extension, for example game.rom",13,10,0
txt_credits:		db 13,10,"AT28C256 EEPROM Programmer for MSX",13,10
			db "v1.4."
BuildId: db "20230307.037"
			db 13,10
			db "RCC (c) 2020-2023",13,10,13,10,0


parms_table:    
    db "h",0
    dw param_h
    db "help",0
    dw param_h
    db "i",0
    dw param_i
    db "s",0
    dw param_s
    db "p",0
    dw param_p
    db "f",0
    dw param_f
    db "e",0
    dw param_e
    db "r",0
    dw param_r

    db 0    ; end of table. this byte is mandatory to be zero

thisslt:		db $00
parm_index:		db $ff
parm_found:		db $ff
ignorerc:		db $ff
data_option_s:		db $ff
data_option_f:		db $ff,0,0,0,0,0,0,0,0,0,0,0,0
data_option_p:		db $ff
data_option_e:		db $ff
data_option_z:		db '.'
data_option_r:		db 0
parm_address:		dw 0000
curraddr:		dw 0000
eeprom_saved_bytes:	db 0,0,0
expandedslt:		db $FF
workarea:		db 0,0,0,0
retries:		db 3
writefailed:		db 0

fcb:
				; reference: https://www.msx.org/wiki/FCB    
fcb_drv: 	db 0		; Drive number containing the file.
				; (0 for Default drive, 1 for A, 2 for B, ..., 8 for H)

fcb_fn:		db "filename"   ; 8 bytes for filename and 3 bytes for its extension. 
db "ext"			; When filename or extension has less than 8 or 3, the rest are 
				; filled in by spaces (20h). In case of search "?" (3Fh) may be used
				; to represent any character.
fcb_ex: db 0			; "Current block LO" or "Extent number LO" depending of function called.
fcb_s1: db 0			; "Current block HI" or "File attributes" (DOS2) depending of function called.
fcb_s2: db 0			; "Record size LO" or "Extent number HI" depending of function called. 
				; NOTE: Because of Extent number the record size must be manually 
				; defined after opening a file!
fcb_rc: db 0			; "Record size HI" or "Record count" depending of function called.
fcb_al: db 0,0,0,0		; File size in bytes (1~4294967296).
db 0,0				; Date (DOS1) / Volume ID (DOS2)
db 0,0				; Time (DOS1) / Volume ID (DOS2)
db 0				; Device ID. (DOS1)
				; FBh = PRN (Printer)
				; FCh = LST (List)
				; FCh = NUL (Null)
				; FEh = AUX (Auxiliary)
				; FFh = CON (Console)
db 0				; Directory location. (DOS1)
db 0,0				; Top cluster number of the file. (DOS1)
db 0,0				; Last cluster number accessed (DOS1)
db 0,0				; Relative location from top cluster of the file number of clusters
				; from top of the file to the last cluster accessed. (DOS1)
fcb_cr: db 0			; Current record within extent (0...127)
fcb_rn:	db 0,0,0,0		; Random record number. If record size <64 then all 4 bytes will be used.
db	0,0,0
ds		10
dma:  	equ     $