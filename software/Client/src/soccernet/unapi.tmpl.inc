; UNAPI TCP/IP transport for the lockstep stub (assembled into the stub with
; -DUNAPI; replaces the mailbox send/recv).  DRAFT - not yet run against a real
; stack.  Register conventions are from the TCP/IP UNAPI specification:
;   UDP_SEND  A=11 B=conn HL=data DE=params(+0 dest IP(4), +4 port(2), +6 len(2)) -> A=err
;   UDP_RCV   A=12 B=conn HL=dest DE=max size -> A=err (3 = no data), BC = size
;   UDP_STATE A=10 B=conn -> A=err, B=pending datagram count
;
; The implementation lives in page 1 (a ROM slot, or a mapper segment) and
; must be mapped there for the call, but page 1 is where the game runs. So
; every call: DI, swap to the alternate registers (they carry A, B, DE, HL
; across the switching code), put the UNAPI slot/segment into page 1, call,
; put the game's slot/segment back, EI.
;
; Variables, filled by the loader (or the lobby hand-off):
;   u_slot   slot code (ENASLT format) of the implementation   (0 = no switch)
;   u_seg    mapper segment for page 1, or FFh for a ROM-based implementation
;   u_entry  entry address of the implementation
;   g_slot   slot code of the game's RAM in page 1
;   g_seg    mapper segment the game occupies in page 1
;   conn     UDP connection number
;   dest     params block: peer IP (4), peer port (2), data length (2)

ENASLT:         EQU     $0024
MAPPER_P1:      EQU     $FD

; A = function, B/HL/DE per function. Returns the implementation's registers.
unapi_call:
        di
        ex      af,af'
        exx                             ; arguments now live in the alternates
        ld      a,(u_slot)
        or      a
        jr      z,.noslot
        ld      h,$40
        call    ENASLT                  ; page 1 -> the implementation's slot
        di
.noslot:
        ld      a,(u_seg)
        cp      $FF
        jr      z,.norom
        out     (MAPPER_P1),a           ; page 1 -> its mapper segment
.norom: exx
        ex      af,af'                  ; arguments back in the main registers
        call    u_jump
        ex      af,af'
        exx                             ; results parked in the alternates
        ld      a,(g_slot)
        ld      h,$40
        call    ENASLT                  ; page 1 -> the game's slot...
        di
        ld      a,(g_seg)
        out     (MAPPER_P1),a           ; ...and its segment
        exx
        ex      af,af'                  ; results back
        ei
        ret
u_jump: defb    $C3                     ; jp nnnn, operand patched with the entry address,
u_entry: defw   0                       ; so A, B, DE and HL reach the implementation intact
