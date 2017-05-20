BUSYRETRIES:    EQU 2
GLOBALRETRIES:  EQU 5
RESET:          EQU $FF

STARTTRANSFER:  EQU $A0
SENDNEXT:       EQU $A1
ENDTRANSFER:    EQU $A2
READY:          EQU $AA
ABORT:          EQU $AD
BUSY:           EQU $AE

RC_SUCCESS:     EQU $E0
RC_CRCERROR:    EQU $E2
RC_OUTOFSYNC:   EQU $E5
RC_FILENOTFOUND:EQU $E6

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
CSRY:           EQU     $F3DC
CSRX:           EQU     $F3DD
ERAFNK:         EQU     $00CC
DSPFNK:         EQU     $00CF
PROCNM:         EQU     $FD89
XF365:          EQU     $F365                  ; routine read primary slotregister

CONTROL_PORT:   EQU $06
CONTROL_PORT2:  EQU $08
DATA_PORT:      EQU $07

BDOS:           EQU 5

