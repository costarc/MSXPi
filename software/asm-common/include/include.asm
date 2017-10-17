CONTROL_PORT1: EQU $56
CONTROL_PORT2: EQU $57
CONTROL_PORT3: EQU $58
CONTROL_PORT4: EQU $59
DATA_PORT1: EQU $5A
DATA_PORT2: EQU $5B
DATA_PORT3: EQU $5C
DATA_PORT4: EQU $5D

BUSYRETRIES:    EQU 2
GLOBALRETRIES:  EQU 5
RESET:          EQU $FF

STARTTRANSFER:  EQU $A0
SENDNEXT:       EQU $A1
ENDTRANSFER:    EQU $A2
READY:          EQU $AA
ABORT:          EQU $AD
BUSY:           EQU $AE

RC_SUCCESS:       EQU $E0
RC_INVALIDCOMMAND:EQU $E1
RC_CRCERROR:      EQU $E2
RC_OUTOFSYNC:     EQU $E5
RC_FILENOTFOUND:  EQU $E6
RC_FAILED:        EQU $E7
RC_WAIT:          EQU $E9
RC_SUCCNOSTD:     EQU $EB

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
XF365:          EQU     $F365                  ; routine read primary slotregister

BDOS:           EQU 5

DEVICE:         equ	0FD99H

txttab:         equ	$f676
vartab:         equ	$f6c2
arytab:         equ	$f6c4
strend:         equ	$f6c6
SLTATR:         equ	$fcc9
CALBAS:         equ   $0159
CHRGTR:         equ   $4666


