#!/bin/sh
# MSX-DOS's TPA top (the word at 0006h) on each set-up PLAYNET supports with a TCP/IP stack loaded (plan C1): TPATOP.COM before
# the stack, after MSR I / RAMHELPR I, and after INL I. A game's transport area + 512 must lie below the lowest of these
# (PLAYNET.COM's tcpFootprint; PLAYNET-PROTOCOLS 10.2).
#
#   SETUP=dos1|nextor|fdd sh tpatop.sh
#     dos1    Canon V-25 + ram2mb + MSXPi, MSX-DOS 1 from the MSXPi's boot disk, MSR I
#     nextor  Canon V-25 + MegaFlashROM SCC+ SD (Nextor) + slot expander + ram2mb + MSXPi, RAMHELPR I (WSL's openMSX builds the image:
#             OPENMSX_WSL=/usr/local/bin/openmsx)
#     fdd     Panasonic_FS-A1WSX (its own disk drive, MSX-DOS 1.8) + ram4mb + MSXPi, MSR I
#   OPENMSX  path to openmsx.exe.   WORK  scratch folder.   P1PORT  the MSXPi server's port (8117; its own: other rigs use 8115/8116/8137/8138)
# Result: the TPATOP lines printed at the end.
SETUP=${SETUP:-dos1}
HERE=$(cd "$(dirname "$0")" && pwd)
python "$HERE/rig_preflight.py" || exit 1
ROOT=$(cd "$HERE/../../../.." && pwd)
RW=$(cd "$ROOT" && pwd -W 2>/dev/null || echo "$ROOT")
ASM=${SJASMPLUS:-C:/Users/roniv/Dev/bin/sjasmplus.exe}
SERVER="$ROOT/software/Server/Python/src"
OMX=${OPENMSX:-C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe}
HARNESS="$RW/software/UNAPI/harness/lib/harness.tcl"
WORK=${WORK:-${TMP:-/tmp}/tpatop-work-$SETUP}
PORT=${P1PORT:-8117}
mkdir -p "$WORK"; WORKW=$(cd "$WORK" && pwd -W 2>/dev/null || echo "$WORK")
"$ASM" --raw="$WORK/TPATOP.COM" "$HERE/tpatop.asm" > /dev/null || exit 1
printf 'ip d 0\r\nip l 10.0.2.15\r\nip m 255.255.255.0\r\nip g 10.0.2.2\r\nip p 10.0.2.2\r\n\032' > "$WORK/INL.CFG"
UN="$ROOT/software/UNAPI/bin"
H="$WORK/msxhome"; rm -rf "$H"; mkdir -p "$H/disks" "$H/tmp"
cp "$ROOT/software/target/disks/msxpiboot.dsk" "$ROOT/software/target/disks/tools.dsk" "$H/disks/"
cat > "$H/msxpi.ini" <<INI
var PATH=https://www.msxarchive.nl/pub/msx/games/roms/msx1
var DriveA=$WORKW/msxhome/disks/msxpiboot.dsk
var DriveB=$WORKW/msxhome/disks/tools.dsk
var DriveM=https://github.com/costarc/MSXPi/raw/master/software/target
var WIDTH=80
var SPI_HW=False
INI
case "$SETUP" in
  dos1)
    for f in "$WORK/TPATOP.COM" "$WORK/INL.CFG"; do python "$HERE/fat12_add.py" "$H/disks/msxpiboot.dsk" "$f" "$(basename $f)" > /dev/null; done
    SEQ="TPATOP;MSR I;TPATOP;INL I;TPATOP"; BOOT=dos
    HW="-machine Canon_V-25 -ext ram2mb -ext MSXPi"; MEDIA=; DISKA= ;;
  fdd)
    rm -rf "$WORK/floppy"; mkdir -p "$WORK/floppy"
    cp "$WORK/TPATOP.COM" "$WORK/INL.CFG" "$UN/MSR.COM" "$UN/INL.COM" "$WORK/floppy/"
    for f in "$WORK/TPATOP.COM" "$WORK/INL.CFG"; do python "$HERE/fat12_add.py" "$H/disks/msxpiboot.dsk" "$f" "$(basename $f)" > /dev/null; done
    SEQ="TPATOP;MSR I;TPATOP;INL I;TPATOP"; BOOT=dos
    HW="-machine Panasonic_FS-A1WSX -ext MSXPi -ext ram4mb"; DISKA="-diska $WORKW/floppy"; MEDIA= ;;
  nextor)
    D="$WORK/hdplaynet"; rm -rf "$D"; mkdir -p "$D"
    cp "$WORK/TPATOP.COM" "$WORK/INL.CFG" "$UN/RAMHELPR.COM" "$UN/INL.COM" "$D/"
    sh "$HERE/nextor_folder.sh" "${NEXTORHD:-C:/Users/roniv/Dev/MSX/NextorHD.dsk}" "$WORKW/nextor.dsk" "$(cd "$D" && pwd -W)" PLAYNET || exit 1
    SEQ="C:;CD PLAYNET;TPATOP;RAMHELPR I;TPATOP;INL I;TPATOP"; BOOT=nextor
    HW="-machine Canon_V-25 -ext MegaFlashROM_SCC+_SD -ext slotexpander -ext ram2mb -ext MSXPi"; MEDIA="-command 'hdb {$WORKW/nextor.dsk}'"; DISKA= ;;
  *) echo "SETUP=dos1|nextor|fdd"; exit 1 ;;
esac
# EXTRA_B = files for drive B: (tools.dsk), SEQ_OVERRIDE = other commands (a run of PLAYNET to read its message off the screen)
for f in $EXTRA_A; do python "$HERE/fat12_add.py" "$H/disks/msxpiboot.dsk" "$f" "$(basename $f)" > /dev/null; done   # EXTRA_A: files for drive A: (CTRL at boot leaves A: only)
for f in $EXTRA_B; do python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$f" "$(basename $f)" > /dev/null; done
[ -z "$SEQ_OVERRIDE" ] || SEQ="$SEQ_OVERRIDE"
pid=$(netstat -ano | grep -E ":$PORT .*LISTENING" | awk '{print $5}' | head -1)
[ -z "$pid" ] || { echo "port $PORT is in use (pid $pid): another rig? set P1PORT"; exit 1; }
( cd "$SERVER"; env MSXPI_PORT=$PORT MSXPI_HOME="$WORKW/msxhome" MSXPI_INI="$WORKW/msxhome/msxpi.ini" MSXPI_TMP="$WORKW/msxhome/tmp" \
    MSXPI_ETH_LINK=udpnat python -u msxpi-server.py > "$WORK/server.log" 2>&1 ) &
sleep 12
rm -f "$WORK/node".*
echo "RUN: $HW $DISKA $MEDIA" > "$WORK/cmd.txt"
eval "BOOT=$BOOT SEQ='$SEQ' PLAYNET_SYMS= MSXPI_HARNESS_OUT=$WORKW/node timeout 900 \"$OMX\" $HW $DISKA $MEDIA -command 'set msxpiserver_port $PORT' \
  -command 'set msxpirom_bank BANK2' -command 'set msxpirom_sltsl ON' -command reset -command 'set renderer none' -command 'set mute on' \
  -script \"$HARNESS\" -script \"$RW/software/Client/tests/soccernet/tpatop_node.tcl\" > \"$WORK/node.log\" 2>&1"
echo "== $SETUP"; cat "$WORK/node.top" 2>/dev/null || { echo "no result"; tail -5 "$WORK/node.log"; }
pid=$(netstat -ano | grep -E ":$PORT .*LISTENING" | awk '{print $5}' | head -1)
[ -z "$pid" ] || taskkill //F //PID $pid > /dev/null 2>&1
