; Shared single-player MSXPi runtime, configuration ABI msxpi-music-v1.
; Game-specific entry, event detection, volume filter and exit live in game.asm.
        org $c000
        include "game.asm"

; Raw game ID -> configured track index (0 means original audio).
music_id:
        push hl
        ld l,a
        ld h,sound_map / 256
        ld a,(hl)
        pop hl
        or a
        ret z
        scf
        ret

service:
        ld a,(link_failed)
        or a
        ret nz
        call desired_music
        or a
        jr z,music_not_detected
        push af
        ld a,(gap_frames)       ; keep soundtrack through brief per-channel gaps
        ld (silence_frames),a
        pop af
        jr music_decided
music_not_detected:
        ld a,(current)
        or a
        jr z,music_decided
        ld a,(silence_frames)
        or a
        jr z,music_decided
        dec a
        ld (silence_frames),a
        ld a,(current)
music_decided:
        ld (desired),a
        ld b,a
        ld a,(current)
        cp b
        ret z
        ld a,(pid)
        or a
        call nz,stop_music
        ret c
        ld a,(desired)
        ld (current),a
        or a
        ret z
start_music:
        ; Locate Nth NUL-terminated filename; double NUL ends the list.
        ld a,(desired)
        ld b,a
        ld hl,track_names
        dec b
        jr z,filename_found
filename_next:
        ld a,(hl)
        inc hl
        or a
        jr nz,filename_next
        djnz filename_next
filename_found:
        push hl
        ld a,(desired)
        ld l,a
        ld h,track_modes / 256
        ld a,(hl)
        ld hl,play_prefix
        or a
        jr z,prefix_ready
        ld hl,loop_prefix
prefix_ready:
        ld de,command
        ld bc,11
        ldir
        pop hl
filename_copy:
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,filename_copy
        ld de,command
        call exchange
        ret c
        ; Accept 1..10 decimal digits plus optional trailing CR/LF.
        ; Player errors can also be delivered in RC_SUCCESS text blocks.
        ld hl,response
        ld de,pid
        ld b,0
parse_pid:
        ld a,(hl)
        or a
        jr z,pid_done
        cp 13
        jr z,pid_tail
        cp 10
        jr z,pid_tail
        cp '0'
        jr c,bad_pid
        cp '9'+1
        jr nc,bad_pid
        inc b
        ld a,b
        cp 11
        jr nc,bad_pid
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        jr parse_pid
pid_tail:
        inc hl
        ld a,(hl)
        or a
        jr z,pid_done
        cp 13
        jr z,pid_tail
        cp 10
        jr z,pid_tail
        jr bad_pid
pid_done:
        ld a,b
        or a
        jr z,bad_pid
        xor a
        ld (de),a
        ld a,(pid)
        cp '0'
        jr z,bad_pid
        or a
        ret
bad_pid:
        xor a
        ld (pid),a             ; discard any partially parsed numeric reply
        jp exchange_error      ; terminal fallback, including invalid first reply

stop_music:
        ld hl,pid
        ld de,stop_digits
stop_copy:
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,stop_copy
        ld de,stop_command
        call exchange          ; consume the stop response as well
        ret c
        ld hl,response
        ld a,(hl)
        cp 'O'
        jp nz,exchange_error
        inc hl
        ld a,(hl)
        cp 'k'
        jp nz,exchange_error
        inc hl
        ld a,(hl)
        or a
        jr z,stop_ok
        cp 13
        jr z,stop_ok
        cp 10
        jp nz,exchange_error
stop_ok:
        xor a
        ld (pid),a
        ret

; DE=command; NC=terminated response. Disable further wire attempts on
; failure (so a disconnected Pi cannot freeze every frame).
exchange:
        call resetMSXPI
        call SendCommandToMSXPi
        jr c,exchange_error
        ld bc,256
        call PerformHandshake
        jr c,exchange_error
        xor a
        ld (response_index),a
response_next:
        ld a,(response_index)
        ld de,response
        ld bc,256
        call RECVDATA_ONEBLOCK
        jr c,exchange_error
        xor a
        ld (de),a              ; payload <=256; allocation 257
        ld a,(MSXPI_STASH_BUF+5)
        cp RC_READY
        jr z,response_more
        cp RC_SUCCESS
        jr nz,exchange_error
        ld a,(response_index)
        or a
        ret z
        ld a,1                 ; drained multipart response is not a valid PID
        ld (response),a
        or a
        ret
response_more:
        ld a,(response_index)
        inc a
        cp 16
        jr nc,exchange_error
        ld (response_index),a
        jr response_next
exchange_error:
        call resetMSXPI
        ld a,1
        ld (link_failed),a
        scf                    ; retain owned PID, fall back to PSG
        ret

; Local MSXPi v1.6 snapshots with bounded waits/payload validation from
; the builder. No changes to the MSXPi repository or server are required.
        include "include.asm"
PUTCHAR:
        ret
        include "msxpi_bios.asm"
play_prefix:  db "music play "
loop_prefix:  db "music loop "
command:      ds 139,0          ; prefix(11) + filename(127) + NUL
stop_command: db "music stop "
stop_digits:  ds 11,0
pid:          ds 11,0
current:      db 0
desired:      db 0
silence_frames: db 0
link_failed:  db 0
response_index: db 0
response:     ds 257,0
code_end:
        assert code_end <= $d000
        ds $d000-$,0
sound_map:    ds 256,0          ; raw sound ID -> 1-based track index
track_modes:  ds 256,0          ; indexed by track, 0=play / 1=loop
exit_enabled: db 1
gap_frames:   db 120
        ds 14,0
track_names:  ds $e000-$,0      ; packed filename\0filename\0\0, max 3568 bytes
resident_end:
        assert resident_end = $e000
