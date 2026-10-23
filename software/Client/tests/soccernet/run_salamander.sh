#!/bin/sh
# Two openMSX (Canon V-25 + MSXPi + a 2 MB memory mapper) play Salamander's DUALPLAY with PLAYNET.COM (image host
# mapper-ram) through two stock msxpi-server.py that relay the stub's packets over UDP on localhost.
#
#   SALAMANDER_ROM=/path/to/SALAMAND.ROM sh run_salamander.sh [frames] [lag_ms] [loss_pct]
#
# Needs sjasmplus (SJASMPLUS=path), the Windows openMSX build with the MSXPi device and your own SALAMAND.ROM (never
# committed). The release stub and its GPF come from software/ROM-Patcher/profiles/salamander/rebuild.py. Environment:
#   OPENMSX  path to openmsx.exe.   WORK  scratch folder (default $TMP/salamander-work)
#   ONLY=P1  run one node.          MENU=single  P1 picks 1PLAYER instead of DUALPLAY
#   EXT2=... the second node's memory instead of ram2mb (for example ram512k, to run with fewer segments)
#   TMAX/NODETMO  emulated / wall seconds before a node is stopped.   RENDERER=SDLGL-PP to watch it
# Results: $WORK/np/{P1,P2}.trace (+ .screen and screenshots); the script prints the comparison.
STOPF=${1:-3000}; LAGMS=${2:-0}; LOSS=${3:-0}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
RW=$(cd "$ROOT" && pwd -W 2>/dev/null || echo "$ROOT")
SRC="$ROOT/software/Client/src/playnet"
PKG="$ROOT/software/ROM-Patcher/profiles/salamander"
ASM=${SJASMPLUS:-C:/Users/roniv/Dev/bin/sjasmplus.exe}
SERVER="$ROOT/software/Server/Python/src"
OMX=${OPENMSX:-C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe}
HARNESS="$RW/software/UNAPI/harness/lib/harness.tcl"
[ -f "$SALAMANDER_ROM" ] || { echo "set SALAMANDER_ROM to your own SALAMAND.ROM"; exit 1; }
WORK=${WORK:-${TMP:-/tmp}/salamander-work}
mkdir -p "$WORK"; WORKW=$(cd "$WORK" && pwd -W 2>/dev/null || echo "$WORK")
python "$SRC/build.py" --assembler "$ASM" || exit 1
python "$PKG/rebuild.py" --assembler "$ASM" --syms "$WORK/stub_syms.tcl" || exit 1
rm -f "$WORK/SALAMAND.GPF"
python "$ROOT/software/ROM-Patcher/patch_rom.py" --profile "$PKG/profile.json" --gpf "$WORK/SALAMAND.GPF" "$SALAMANDER_ROM" || exit 1

sh "$HERE/kill_nodes.sh"
touch "$WORK/stop_servers"
for port in 8115 8116; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  if [ -n "$pid" ]; then taskkill //F //PID $pid > /dev/null 2>&1; fi
done
sleep 3
for n in 1 2; do
  H="$WORK/msxhome$n"; rm -rf "$H"; mkdir -p "$H/disks" "$H/tmp" "$H/games"
  cp "$WORK/SALAMAND.GPF" "$H/games/SALAMAND.GPF"
  cp "$ROOT/software/target/disks/msxpiboot.dsk" "$ROOT/software/target/disks/tools.dsk" "$H/disks/"
  cat > "$H/msxpi.ini" <<INI
var PATH=https://www.msxarchive.nl/pub/msx/games/roms/msx1
var DriveA=$WORKW/msxhome$n/disks/msxpiboot.dsk
var DriveB=$WORKW/msxhome$n/disks/tools.dsk
var DriveM=https://github.com/costarc/MSXPi/raw/master/software/target
var WIDTH=80
var SPI_HW=False
INI
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$SRC/build/PLAYNET.COM" PLAYNET.COM > /dev/null || exit 1
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$SALAMANDER_ROM" SALAMAND.ROM > /dev/null || exit 1
done
PROFHASH=$(python -c "import struct,sys; print('%08x' % struct.unpack('<I', open(sys.argv[1],'rb').read()[8:12])[0])" "$WORK/SALAMAND.GPF")
rm -f "$WORK/stop_servers"
start() {  # n port local_udp peer_udp
  ( cd "$SERVER"; while [ ! -f "$WORK/stop_servers" ]; do
      env MSXPI_PORT=$2 MSXPI_HOME="$WORKW/msxhome$1" MSXPI_INI="$WORKW/msxhome$1/msxpi.ini" MSXPI_TMP="$WORKW/msxhome$1/tmp" \
        MSXPI_NETPLAY=$3:127.0.0.1:$4 MSXPI_NETPLAY_PROFILE=$PROFHASH MSXPI_NETPLAY_LAG_MS=$LAGMS MSXPI_NETPLAY_LOSS_PCT=$LOSS \
        MSXPI_NETPLAY_DELAY=0 MSXPI_NETPLAY_VERSION=1 python -u msxpi-server.py >> "$WORK/server$1.log" 2>&1
      echo "=== server $1 exited, restarting ===" >> "$WORK/server$1.log"
      sleep 1
    done ) > /dev/null 2>&1 &
}
: > "$WORK/server1.log"; : > "$WORK/server2.log"
start 1 8115 5101 5102
start 2 8116 5102 5101
sleep 15
mkdir -p "$WORK/np"; rm -f "$WORK"/np/*
node() {  # role port ext
  PLAYNET_SYMS="$WORKW/stub_syms.tcl" STUB_BIN="$(cd "$PKG" && pwd -W 2>/dev/null || echo "$PKG")/assets/stub.bin" \
  ROLEARG=$1 TRACE=$WORKW/np/$1.trace STOPF=$STOPF MENU=${MENU:-dual} SEED=${SEED:-0} MSXPI_HARNESS_OUT=$WORKW/np/$1.result \
  timeout ${NODETMO:-1800} "$OMX" -machine Canon_V-25 -ext $3 -ext MSXPi \
    -command "set msxpiserver_port $2" -command "set msxpirom_bank BANK2" \
    -command "set msxpirom_sltsl ON" -command "reset" -command "set renderer ${RENDERER:-none}" -command "set mute on" \
    -script "$HARNESS" -script "$RW/software/Client/tests/soccernet/salamander_node.tcl" ${EXTRA_TCL:+-script "$EXTRA_TCL"} > "$WORK/np/$1.log" 2>&1
}
node P1 8115 ram2mb &
NPIDS=$!
if [ -z "$ONLY" ]; then sleep 5; node P2 8116 ${EXT2:-ram2mb} & NPIDS="$NPIDS $!"; fi
wait $NPIDS
python "$HERE/cmp_pair.py" "$WORK/np/P1.trace" "$WORK/np/P2.trace"
grep -h "^#" "$WORK/np/P1.trace" "$WORK/np/P2.trace"
grep -h "netplay: [a-z]" "$WORK/server1.log" "$WORK/server2.log" | grep -v "{" | tail -8
touch "$WORK/stop_servers"
for port in 8115 8116; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  if [ -n "$pid" ]; then taskkill //F //PID $pid > /dev/null 2>&1; fi
done
