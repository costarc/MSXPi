#!/bin/sh
# Two openMSX (Canon V-25 + MSXPi) play Konami's Soccer through two stock msxpi-server.py that relay the
# stub's packets over UDP on localhost (MSXPi-native transport, opcode C9; no TAP adapters, no mapper).
#
#   SOCCER_ROM=/path/to/SOCCER.ROM sh run_native.sh <lag_ms> <loss_pct> [frames] [jitter_ms]
#
# Needs: sjasmplus (build first: sh ../../src/soccernet/build.sh), the Windows openMSX build with the MSXPi
# device, your own SOCCER.ROM (never committed). Environment:
#   SOCCER_ROM    required.        OPENMSX   path to openmsx.exe.     WORK  scratch folder (default $TMP/soccernet-work)
#   ONLY=H        run one node.    FORCE_DELAY=n  fix the delay.      VER2=n  version announced by node C
#   POKEF=n       corrupt the ball on node H at frame n (desync check)    EXITF=n  node C exits at frame n
#   TMAX/NODETMO  emulated / wall seconds before a node is stopped.   RENDERER=SDL  to watch it
# Results: $WORK/np/{H,C}.trace (+.ticks, .screen); the script prints the comparison.
LAGMS=${1:-0}; LOSS=${2:-0}; STOPF=${3:-1500}; JIT=${4:-0}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)               # repository root
RW=$(cd "$ROOT" && pwd -W 2>/dev/null || echo "$ROOT")
SRC="$ROOT/software/Client/src/soccernet"
SRCW=$(cd "$SRC" && pwd -W 2>/dev/null || echo "$SRC")
SERVER="$ROOT/software/Server/Python/src"
OMX=${OPENMSX:-C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe}
HARNESS="$RW/software/UNAPI/harness/lib/harness.tcl"
[ -f "$SOCCER_ROM" ] || { echo "set SOCCER_ROM to your own SOCCER.ROM"; exit 1; }
[ -f "$SRC/build/SOCNAT.COM" ] || { echo "build first: sh $SRC/build.sh"; exit 1; }
WORK=${WORK:-${TMP:-/tmp}/soccernet-work}
mkdir -p "$WORK"; WORKW=$(cd "$WORK" && pwd -W 2>/dev/null || echo "$WORK")

sh "$HERE/kill_nodes.sh"
touch "$WORK/stop_servers"
for port in 8115 8116; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  [ -n "$pid" ] && taskkill //F //PID $pid > /dev/null 2>&1
done
sleep 3
# fresh server homes with their own copies of the boot and tools disks (written while the servers are stopped)
for n in 1 2; do
  H="$WORK/msxhome$n"; rm -rf "$H"; mkdir -p "$H/disks" "$H/tmp"
  cp "$ROOT/software/target/disks/msxpiboot.dsk" "$ROOT/software/target/disks/tools.dsk" "$H/disks/"
  cat > "$H/msxpi.ini" <<INI
var PATH=https://www.msxarchive.nl/pub/msx/games/roms/msx1
var DriveA=$WORKW/msxhome$n/disks/msxpiboot.dsk
var DriveB=$WORKW/msxhome$n/disks/tools.dsk
var DriveM=https://github.com/costarc/MSXPi/raw/master/software/target
var WIDTH=80
var SPI_HW=False
INI
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$SRC/build/SOCNAT.COM" SOCNAT.COM > /dev/null
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$SOCCER_ROM" SOCCER.ROM > /dev/null
done
rm -f "$WORK/stop_servers"
start() {  # n port local_udp peer_udp version
  ( cd "$SERVER"; while [ ! -f "$WORK/stop_servers" ]; do
      MSXPI_PORT=$2 MSXPI_HOME="$WORKW/msxhome$1" MSXPI_INI="$WORKW/msxhome$1/msxpi.ini" MSXPI_TMP="$WORKW/msxhome$1/tmp" \
      MSXPI_NETPLAY="$3:127.0.0.1:$4" MSXPI_NETPLAY_LAG_MS=$LAGMS MSXPI_NETPLAY_LOSS_PCT=$LOSS MSXPI_NETPLAY_JITTER_MS=$JIT \
      MSXPI_NETPLAY_DELAY=${FORCE_DELAY:-0} MSXPI_NETPLAY_VERSION=${5:-1} \
        python -u msxpi-server.py >> "$WORK/server$1.log" 2>&1
      echo "=== server $1 exited, restarting ===" >> "$WORK/server$1.log"
      sleep 1
    done ) > /dev/null 2>&1 &
}
: > "$WORK/server1.log"; : > "$WORK/server2.log"
start 1 8115 5101 5102
start 2 8116 5102 5101 ${VER2:-1}
sleep 15
mkdir -p "$WORK/np"; rm -f "$WORK"/np/*
node() {  # role port
  SOCCERNET_BUILD="$SRCW/build" SOCCERNET_SRC="$SRCW" ROLEARG=$1 TRACE=$WORKW/np/$1.trace STOPF=$STOPF \
  MSXPI_HARNESS_OUT=$WORKW/np/$1.result \
  timeout ${NODETMO:-1500} "$OMX" -machine Canon_V-25 -ext ram2mb -ext MSXPi \
    -command "set msxpiserver_port $2" -command "set msxpirom_bank BANK2" \
    -command "set msxpirom_sltsl ON" -command "reset" -command "set renderer ${RENDERER:-none}" \
    -script "$HARNESS" -script "$RW/software/Client/tests/soccernet/native_node.tcl" > "$WORK/np/$1.log" 2>&1
}
PROG=SOCNAT
export PROG
node H 8115 &
if [ -z "$ONLY" ]; then sleep 5; node C 8116 & fi
wait
python "$HERE/cmp_pair.py" "$WORK/np/H.trace" "$WORK/np/C.trace"
grep -h "desync=" "$WORK/np/H.trace" "$WORK/np/C.trace"
grep -h "netplay: [a-z]" "$WORK/server1.log" "$WORK/server2.log" | grep -v "{" | tail -12
touch "$WORK/stop_servers"
for port in 8115 8116; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  [ -n "$pid" ] && taskkill //F //PID $pid > /dev/null 2>&1
done
