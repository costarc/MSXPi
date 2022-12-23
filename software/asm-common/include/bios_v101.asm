CONTROL_PORT1: EQU $56
CONTROL_PORT2: EQU $57
CONTROL_PORT3: EQU $58
CONTROL_PORT4: EQU $59
DATA_PORT1: EQU $5A
DATA_PORT2: EQU $5B
DATA_PORT3: EQU $5C
DATA_PORT4: EQU $5D

RC_SUCCESS:       EQU $E0
RC_INVALIDCOMMAND:EQU $E1
RC_CRCERROR:      EQU $E2
RC_TIMEOUT:       EQU $E3
RC_DSKIOERR:      EQU $E4
RC_OUTOFSYNC:     EQU $E5
RC_FILENOTFOUND:  EQU $E6
RC_FAILED:        EQU $E7
RC_CONNERR:       EQU $E8
RC_WAIT:          EQU $E9
RC_READY:         EQU $EA
RC_SUCCNOSTD:     EQU $EB
RC_FAILNOSTD:     EQU $EC
RC_ESCAPE:        EQU $ED
RC_UNDEFINED:     EQU $EF


MSXTOPI:
;  Send a block of data to RPi
; Block format:
; 0000 0001            : Block size (NNNN)
; 0002 NNNN+2      : Data 
; NNNN+3 NNNN+4: CRC16 for all data (block size + data)
;
; Input:
;  BC : Block size
;  DE: Address of Memory containing the data
; Output:
;  A: Error Code
; DE: Original Value if routine finishes with error
;        Memory address after the last byte read from Pi
;
; Destroy:
; AF, BC, HL

; Check if the interface is available
		in			a,(CONTROL_PORT1)
		or			a
		jr			nz,MSXTOPI
		push		de
; clear HL to calculate CRC16 using simple xor operation
; CLEAR CRC and save block size
        exx
        ld      hl,$ffff
        exx
; Send block size
		ld			a,c
		call		CRC16
		ld			a,c
		out		(DATA_PORT1),a
		ld			a,b
		call		CRC16
		ld			a,b
		out		(DATA_PORT1),a
SLP1:
		ld			a,(de)
		out		(DATA_PORT1),a
		call		CRC16
		inc		de
		dec		bc
		ld			a,b
		or			c
		jr			nz,SLP1
		exx
		in			a,(DATA_PORT1)
		cp			l
		jr			nz,crcerror
		in			a,(DATA_PORT1)
		cp			h
		jr			nz,crcerror
		pop		hl								;Discard DE in stack, so it will keep current address
		ld			a,RC_SUCCESS
		ret
crcerror:
		pop		de							; Restore original DE address
		ld			a,RC_CRCERROR
		ret		

PITOMSX:
;  Receive a block of data from RPi
; Block format:
; 0000 0001            : Block size (NNNN)
; 0002 NNNN+2      : Data 
; NNNN+3 NNNN+4: CRC16 for all data (block size + data)
;
; Input:
;  BC : Block size
;  DE: Address of Memory containing the data
; Output:
;  A: Error Code
; DE: Original Value if routine finishes with error
;        Memory address after the last byte read from Pi


; Input:
; A = byte to calculate CRC
; HL' = Current CRC 
; Output:
; HL' = CRC
; 
CRC16:
        exx
        xor     h
        ld      h,a
        ld      b,8
rotate16:
        add     hl,hl ; 11t - rotate crc left one
        jr      nc, nextbit16 ; 12/7t - only xor polyonimal if msb set
        ld      a,h ; 4t
        xor     $10 ; 7t - high byte with $10
        ld      h,a ; 4t
        ld      a,l ; 4t
        xor     $21 ; 7t - low byte with $21
        ld      l,a ; 4t - hl now xor $1021
nextbit16:
        djnz rotate16 ; 13/8t - loop over 8 bits
        exx
        ret
        