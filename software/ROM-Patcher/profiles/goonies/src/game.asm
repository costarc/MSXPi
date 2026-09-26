; Goonies adapter: game RAM/stack E000-E5FF, runtime C000-DFFF.
resident_boot:
        di
        call decode_names
        ld a,2
        ld ($6000),a           ; rewritten by msxarch's server mapper patcher
        ld a,1
        ld ($7000),a
        jp $406a

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

idle:
        ei
        halt
        di
        call check_exit
        call service
        jr idle

desired_music:
        ld a,($e07f)
        or a
        jr nz,no_music
        ld a,($e012)
        call music_id
        ret c
        ld a,($e020)
        call music_id
        ret c
        ld a,($e02e)
        call music_id
        ret c
no_music:
        xor a
        ret

; Hook B76C's first four bytes; preserve original flags/register behavior.
; Continue the original sound sequencer, suppressing only a mapped music
; channel's volume AFTER a valid external PID. Effects and offline music
; retain the original volume. IX addresses the current channel state.
volume_hook:
        push af
        push hl
        ld a,(link_failed)
        or a
        jr nz,volume_original
        ld a,(pid)
        or a
        jr z,volume_original
        ld a,(ix+2)
        call music_id
        jr nc,volume_original
        pop hl
        pop af
        ld a,c
        rrca
        add a,$88
        ld e,0
        jp $b771
volume_original:
        pop hl
        pop af
        ld a,c
        rrca
        add a,$88
        jp $b770

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
        ; RAM-loaded ASCII16 bank 2 is currently in page 1. Clear its AB,
        ; then select bank 0 and clear the bootstrap AB too. The original
        ; file on disk is never modified. A real read-only cartridge cannot
        ; use this exit mechanism; this profile targets msxarch RAM loading.
        xor a
        ld ($4000),a
        ld ($4001),a
        ld ($6000),a
        xor a
        ld ($4000),a
        ld ($4001),a
        ld a,$c9
        ld ($fd9f),a           ; remove game timer hook before BIOS reset
        jp 0
