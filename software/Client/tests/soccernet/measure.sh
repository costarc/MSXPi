#!/bin/sh
# PLAYNET-DESIGN section 8 measurements on one openMSX (Canon V-25 + MSXPi + 2 MB mapper, MSX-DOS 1 served
# by its own msxpi-server.py on port 8117): measure_node.tcl at the prompt and after each install command.
#
#   sh measure.sh                                      MSR I; INL I, then "INL S" as the UNAPI probe
#   INSTALL="MSR I;INL I" PROBE="INL S" sh measure.sh
#   NET=nat PROBE="PING 10.0.2.2" sh measure.sh       INL on the server's user-mode UDP link (INL.CFG 10.0.2.15)
#   BOOT=nextor sh measure.sh                         Nextor (MSX-DOS 2) from a copy of NEXTORHD: "CD TCPIP", "INL I"
#
# Puts MSR.COM, RAMHELPR.COM and INL.COM (software/UNAPI/bin) and MCHAT.COM on the tools disk (B:).
# Results: $WORK/measure.txt (+ .screen). Environment: OPENMSX, WORK, INSTALL, PROBE, NODETMO.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
RW=$(cd "$ROOT" && pwd -W 2>/dev/null || echo "$ROOT")
OMX=${OPENMSX:-C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe}
WORK=${WORK:-${TMP:-/tmp}/playnet-measure}
PORT=8117
mkdir -p "$WORK"; WORKW=$(cd "$WORK" && pwd -W 2>/dev/null || echo "$WORK")
H="$WORK/msxhome"; rm -rf "$H"; mkdir -p "$H/disks" "$H/tmp"
cp "$ROOT/software/target/disks/msxpiboot.dsk" "$ROOT/software/target/disks/tools.dsk" "$H/disks/"
for f in MSR.COM RAMHELPR.COM INL.COM; do
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$ROOT/software/UNAPI/bin/$f" $f > /dev/null
done
[ -f "$ROOT/software/target/mchat.com" ] && python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$ROOT/software/target/mchat.com" MCHAT.COM > /dev/null
NETENV=""
if [ "$NET" = nat ]; then               # the server's user-mode UDP link (msxpi_ethnat.py): INL at 10.0.2.15
  printf 'ip d 0\r\nip l 10.0.2.15\r\nip m 255.255.255.0\r\nip g 10.0.2.2\r\nip p 10.0.2.2\r\n\032' > "$WORK/INL.CFG"
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/INL.CFG" INL.CFG > /dev/null
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$ROOT/software/target/ping.com" PING.COM > /dev/null
  NETENV="MSXPI_ETH_LINK=udpnat"
fi
cat > "$H/msxpi.ini" <<INI
var DriveA=$WORKW/msxhome/disks/msxpiboot.dsk
var DriveB=$WORKW/msxhome/disks/tools.dsk
var WIDTH=80
var SPI_HW=False
INI
pid=$(netstat -ano | grep -E ":$PORT .*LISTENING" | awk '{print $5}' | head -1)
[ -n "$pid" ] && taskkill //F //PID $pid > /dev/null 2>&1
( cd "$ROOT/software/Server/Python/src" && env $NETENV MSXPI_PORT=$PORT MSXPI_HOME="$WORKW/msxhome" MSXPI_INI="$WORKW/msxhome/msxpi.ini" \
    MSXPI_TMP="$WORKW/msxhome/tmp" python -u msxpi-server.py > "$WORK/server.log" 2>&1 ) &
sleep 8
: > "$WORK/measure.txt"; : > "$WORK/measure.txt.screen"
if [ "$BOOT" = nextor ]; then           # MSX-DOS 2: Nextor on a MegaFlashROM SCC+ SD, from a COPY of the HD image
  cp "${NEXTORHD:-C:/Users/roniv/Dev/MSX/NextorHD.dsk}" "$WORK/nextor.dsk"
  HW="-ext MegaFlashROM_SCC+_SD"; MEDIA="hdb {$WORKW/nextor.dsk}"
  : ${INSTALL:=INL I}; : ${TOOLS:=CD TCPIP}
else
  HW="-ext ram2mb"; MEDIA="set renderer none"
fi
export BOOT
INSTALL=${INSTALL:-MSR I;INL I} PROBE=${PROBE:-INL S} TOOLS=${TOOLS:-B:} MEASOUT="$WORKW/measure.txt" \
MSXPI_HARNESS_OUT="$WORKW/measure.result" \
  timeout ${NODETMO:-600} "$OMX" -machine Canon_V-25 $HW -ext MSXPi -command "$MEDIA" \
    -command "set msxpiserver_port $PORT" -command "set msxpirom_bank BANK2" -command "set msxpirom_sltsl ON" \
    -command "reset" -command "set renderer none" -command "set throttle on" \
    -script "$RW/software/UNAPI/harness/lib/harness.tcl" -script "$RW/software/Client/tests/soccernet/measure_node.tcl" \
    > "$WORK/openmsx.log" 2>&1
cat "$WORK/measure.txt"
pid=$(netstat -ano | grep -E ":$PORT .*LISTENING" | awk '{print $5}' | head -1)
[ -n "$pid" ] && taskkill //F //PID $pid > /dev/null 2>&1
