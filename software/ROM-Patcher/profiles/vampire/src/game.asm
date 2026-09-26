; Vampire Killer adapter. Konami mapper, 8K windows 6000/8000/A000 with
; shadows F0F1/F0F2/F0F3. The ROM has no free byte and the game uses all RAM
; C000-F0F0, so the runtime runs in place from added bank 16 at 8000h (writable
; under msxarch) and only a small gateway lives in RAM at F100h, which neither
; the game nor the BIOS writes after start-up.
;
; Every window is a Konami bank register range, so a store into bank 16 would
; switch banks (and msxpi-server rewrites LD (nn),A there into handler calls):
; the gateway and the runtime's writable data are copied to RAM at start-up.
;
; Sound: the driver entry 509F takes A = 0 (stop), 01-7F (effect), 80-8F
; (music), FB-FF (commands). Music channels add the fade offset C0A6 to their
; volume and clamp at 0; the effect channel does not, so C0A6 = F0h silences
; only the music.
GATEWAY equ $f100
RT_DATA equ $f130           ; runtime's writable data, after the gateway

        jp boot                 ; 8000: from INIT, replacing its hook install
        jp bank_service         ; 8003: once per frame from the RAM gateway

boot:
        ld hl,gateway_image
        ld de,GATEWAY
        ld bc,gateway_end-GATEWAY
        ldir
        ld hl,rt_data_image
        ld de,RT_DATA
        ld bc,rt_data_end-RT_DATA
        ldir
        ; What the replaced INIT bytes did: install H.TIMI, CLIKSW off.
        ld a,$c3
        ld ($fd9f),a
        ld hl,$4028
        ld ($fda0),hl
        xor a
        ld ($f3db),a
        jp gw_restore           ; restores 8000h from its shadow, then idles

bank_service:
        call check_exit
        call service
        ld a,(link_failed)
        or a
        jr nz,unmute
        ld a,(pid)
        or a
        jr z,unmute
        ld a,(current)
        or a
        jr z,unmute
        ld a,$f0                ; music channels silent, effects untouched
        ld ($c0a6),a
        ld a,1
        ld (muted),a
        ret
unmute:
        ld a,(muted)
        or a
        ret z
        xor a
        ld (muted),a
        ld ($c0a6),a
        ret

; The last music request, while channel 0 still runs a tune (C010 is the
; driver's idle handler 89CE once a song has ended or was stopped).
desired_music:
        ld hl,($c010)
        ld de,$89ce
        or a
        sbc hl,de
        jr z,native_silent
        ld a,(gw_req)
        or a
        ret z
        jp music_id
native_silent:
        xor a
        ret

; Track names keep their '2' escape (02h) in the bank: start_music decodes it
; while copying into the RAM command buffer (see rebuild.py).

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
        ld a,(link_failed)
        or a
        jr nz,exit_reset
        ld a,(pid)
        or a
        call nz,stop_music
exit_reset:
        di
        ; Bank 0 of the RAM-loaded image is at 4000h: clear its AB so the
        ; reset boots MSX-DOS. A read-only cartridge cannot use this exit.
        xor a
        ld ($4000),a
        ld ($4001),a
        ld a,$c9
        ld ($fd9f),a            ; the game's H.TIMI hook
        jp 0

; Copied to F100h by boot. Runs from RAM, whatever banks are mapped.
gateway_image:
        disp GATEWAY
gw_req: db 0                    ; last music request (80-8F) or 0 after stop
muted:  db 0                    ; C0A6 is held at F0h
gw_restore:
        ld a,($f0f2)
        ld ($8000),a            ; rewritten by msxarch's server mapper patcher
; The whole game runs from H.TIMI; the foreground only idles. One service
; call per frame, outside interrupt context, with bank 16 at 8000h.
gw_idle:
        ei
        halt
        di
        ld a,16
        ld ($8000),a
        call $8003
        ld a,($f0f2)
        ld ($8000),a
        jr gw_idle
; Replaces PUSH HL / PUSH DE / PUSH BC at the driver entry 509F.
gw_music:
        push hl
        push de
        push bc
        or a
        jr z,gw_record          ; stop
        cp $fb
        jr nc,gw_done           ; driver commands
        bit 7,a
        jr z,gw_done            ; effects
gw_record:
        ld (gw_req),a
gw_done:
        jp $50a2                ; PUSH AF and the rest of the entry
gateway_end:
        ent
