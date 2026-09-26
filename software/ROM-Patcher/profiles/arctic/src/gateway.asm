        org $7e80
; Track the original cartridge's page-2 selector, including its RAM stub.
bank_select:
        push hl
        ld hl,$7ffc
        ld (hl),a
        pop hl
        push af                 ; distinctive predecessor for server scanner
        ld ($7000),a
        pop af
        ret
; Replace first three bytes of 7748, retaining its PUSH AF / LD A,FF.
music_event:
        push hl
        ld hl,$7ffd
        ld (hl),a
        push af
        xor a
        inc hl
        ld (hl),a
        pop af
        pop hl
        push af
        ld a,$ff
        jp $774b
; Only melodic volume output uses this wrapper; effects keep their engine.
music_volume:
        push af
        ld a,($7ffe)
        or a
        jr z,volume_native
        ld e,0
volume_native:
        pop af
        jp $0093
poll54:
        call poll
        ld a,($c054)
        ret
poll55:
        call poll
        ld a,($c055)
        ret
poll:
        push af
        push bc
        push de
        push hl
        push ix
        push iy
        exx
        push bc
        push de
        push hl
        exx
        ex af,af'
        push af
        ex af,af'
        ; These hooks are foreground keyboard polls with interrupts enabled.
        ; Do not sample IFF2 using LD A,I: an IRQ in that window can clear
        ; P/V and permanently disable the game's frame counter on return.
        di
        ld a,($c053)
        ld b,a
        ld a,($7fff)
        cp b
        jr z,poll_done
        ld a,b
        ld hl,$7fff
        ld (hl),a
        ; Only reached with the cartridge at 8000h: msxarch's page-2 select
        ; handler then maps bank 8 and the restore below. Do not save FEh with
        ; IN: mapper read-back is unreliable with two mappers (FS-A1WSX +
        ; ram4mb read 252 for segment 248) and restored the wrong segment.
        ld a,8
        ld ($7000),a
        call $8000
        ld a,($7ffc)
        ld ($7000),a
poll_done:
        ei
        ex af,af'
        pop af
        ex af,af'
        exx
        pop hl
        pop de
        pop bc
        exx
        pop iy
        pop ix
        pop hl
        pop de
        pop bc
        pop af
        ret
        assert $ <= $7ffc
        ds $7ffc-$,0
        db 1,0,0,0
