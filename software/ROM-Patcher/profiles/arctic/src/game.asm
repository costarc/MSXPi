; Arctic adapter. Runtime is in writable msxarch bank 8, never game RAM.
bank_service:
        ld a,(initialized)
        or a
        jr nz,initialized_ok
        call decode_names
        ld a,1
        ld (initialized),a
initialized_ok:
        call check_exit
        call service
        xor a
        ld hl,$7ffe
        ld (hl),a
        ld a,(link_failed)
        or a
        ret nz
        ld a,(pid)
        or a
        ret z
        ld a,(current)
        ld hl,$7ffe
        ld (hl),a
        ret
initialized: db 0
desired_music:
        ld a,($c970)
        inc a
        jr z,native_silent
        ld a,($7ffd)
        jp music_id
native_silent:
        xor a
        ret
decode_names:
        ld hl,track_names
decode_next:
        ld a,(hl)
        or a
        jr nz,decode_char
        inc hl
        ld a,(hl)
        or a
        ret z
decode_char:
        cp 2
        jr nz,decode_advance
        ld (hl),'2'
decode_advance:
        inc hl
        jr decode_next
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
        ld a,(link_failed)
        or a
        jr nz,exit_reset
        ld a,(pid)
        or a
        call nz,stop_music
exit_reset:
        di
        xor a
        ld ($4000),a
        ld ($4001),a
        ld a,$c9
        ld ($fd9f),a
        jp 0
