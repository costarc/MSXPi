; Nemesis (Gradius) adapter. Konami mapper, 8K windows 6000/8000/A000 with
; shadows at F0F1/F0F2/F0F3. Game RAM E000-F0F0; C000-DFFF is only cleared at
; power-up, so the runtime lives there. It is stored in unused bank 13.
;
; Entered from INIT at 4095, right after its ENASLT put the cartridge in page
; 2 and before it installs the H.KEYI hook, with bank 13 at 8000h and
; interrupts off. This first block runs from 8000h, copies the bank to C000h
; and continues from RAM. Earlier, at INIT's own bank setup (4074), page 2 is
; still RAM; later, the hook's sound driver would call volume_hook.
resident_boot:
        ld hl,$8000
        ld de,$c000
        ld bc,$2000
        ldir
        jp boot_ram
boot_ram:
        call decode_names
        ld a,($f0f2)            ; bank INIT's setup recorded for 8000h
        ld ($8000),a            ; rewritten by msxarch's server mapper patcher
        ; What the replaced INIT bytes did: install the game's H.KEYI hook.
        ld a,$c3
        ld ($fd9a),a
        ld hl,$4028
        ld ($fd9b),hl
        ei
        jp $40a0                ; rest of INIT; it ends in JP idle

; The whole game runs from the H.KEYI hook; the foreground only idles. One
; service call per frame, outside interrupt context.
idle:
        ei
        halt
        di
        call check_exit
        call service
        jr idle

; Filename-only escaping prevents server mapper scans from mistaking ASCII
; '2' (32h = LD (nn),A) for code. NUL/double-NUL remain list delimiters.
decode_names:
        ld hl,track_names
decode_name_byte:
        ld a,(hl)
        or a
        jr nz,decode_name_char
        inc hl
        ld a,(hl)
        or a
        ret z
decode_name_char:
        cp 2
        jr nz,decode_name_next
        ld (hl),'2'
decode_name_next:
        inc hl
        jr decode_name_byte

; Current sound of each PSG channel record (IX+2): E012, E023, E034.
desired_music:
        ld a,($e012)
        call music_id
        ret c
        ld a,($e023)
        call music_id
        ret c
        ld a,($e034)
        call music_id
        ret c
        xor a
        ret

; Hook bank 7 +0222h (runs at 8222h): LD A,C / RRCA / ADD A,88h. The original
; continues LD D,A / BIT 3,(IX+5) / ... and writes the volume from H through
; WRTPSG. A mapped music channel is written silent after a valid external PID;
; effects and offline music keep the original path.
volume_hook:
        push af
        ld a,(link_failed)
        or a
        jr nz,volume_original
        ld a,(pid)
        or a
        jr z,volume_original
        ld a,(ix+2)
        call music_id
        jr nc,volume_original
        pop af
        ld a,c
        rrca
        add a,$88
        ld e,0
        jp $0093
volume_original:
        pop af
        ld a,c
        rrca
        add a,$88
        jp $8226

; CTRL+SHIFT+F5 (row6 bits0,1 and row7 bit1). Direct matrix reads preserve
; PPI row selection. The transport checks ESC, so ESC is not the exit key.
check_exit:
        ld a,(exit_enabled)
        or a
        ret z
        in a,($aa)
        ld b,a
        and $f0
        or 6
        out ($aa),a
        in a,($a9)
        and 3
        ld c,a
        ld a,b
        and $f0
        or 7
        out ($aa),a
        in a,($a9)
        and 2
        or c
        ld c,a
        ld a,b
        out ($aa),a
        ld a,c
        or a
        ret nz
exit_game:
        ; One owned player only. Do not issue a global stop command.
        ld a,(link_failed)
        or a
        jr nz,exit_clear
        ld a,(pid)
        or a
        call nz,stop_music
exit_clear:
        di
        ; Bank 0 of the RAM-loaded image is at 4000h: clear its AB so the
        ; reset boots MSX-DOS. The file on disk is never modified; a real
        ; read-only cartridge cannot use this exit.
        xor a
        ld ($4000),a
        ld ($4001),a
        ld a,$c9
        ld ($fd9a),a            ; the game's H.KEYI hook
        ld ($fd9f),a
        jp 0
