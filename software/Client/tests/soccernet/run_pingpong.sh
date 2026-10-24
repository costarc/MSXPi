#!/bin/sh
# Two openMSX (Canon V-25 + MSXPi) play Konami's Ping Pong with PLAYNET.COM through two stock msxpi-server.py that
# relay the stub's packets over UDP on localhost (MSXPi transport, no TAP adapters, no mapper). From run_native.sh.
#
#   PINGPONG_ROM=/path/to/PINGPONG.ROM sh run_pingpong.sh <lag_ms> <loss_pct> [frames] [jitter_ms]
#
# Needs sjasmplus (SJASMPLUS=path), the Windows openMSX build with the MSXPi device and your own PINGPONG.ROM (never
# committed). The scripted-input test stub and its GPF come from profiles/pingpong/rebuild.py --test-gpf. Environment:
#   OPENMSX  path to openmsx.exe.   WORK  scratch folder (default $TMP/pingpong-work)   ONLY=P1  run one node
#   FORCE_DELAY=n  fix the delay.   POKEF=n  corrupt the game state on P1 at frame n (desync check)   EXITF=n  P2 exits at frame n
#   POKEPTS=n  both nodes set the points to 20 and 7 at frame n (a game ends at the next point)
#   EXITKEY=n  P2 presses Ctrl+Shift+F5 at frame n.   TMAX/NODETMO  emulated / wall seconds before a node is stopped
#   RENDERER=SDLGL-PP to watch it.   EXTRA_TCL / EXTRA_TCL_C  one more script for P1 / P2
#   SCENARIO=mixed  P1 over the MSXPi, P2 over the TCP/IP UNAPI: MSR I, INL I (on its server's user-mode UDP link, msxpi_ethnat.py,
#                 as 10.0.2.15), then PLAYNET /T pingpong P2 5102 10.0.2.2:5101. BOTH=1: both nodes over TCP/IP. HYBRID=1: the
#                 TCP/IP node(s) play through their MSXPi (PLAYNET /T /H, link 2). PNOPTS = more PLAYNET /T options.
# Not here yet (run_native.sh has them): the chat scenarios (plan B5/B6).
# Results: $WORK/np/{P1,P2}.trace; the script prints the comparison.
LAGMS=${1:-0}; LOSS=${2:-0}; STOPF=${3:-1500}; JIT=${4:-0}
HERE=$(cd "$(dirname "$0")" && pwd)
python "$HERE/rig_preflight.py" || exit 1   # the ROM openMSX loads must be this branch's (A1)
ROOT=$(cd "$HERE/../../../.." && pwd)               # repository root
RW=$(cd "$ROOT" && pwd -W 2>/dev/null || echo "$ROOT")
SRC="$ROOT/software/Client/src/playnet"
ASM=${SJASMPLUS:-C:/Users/roniv/Dev/bin/sjasmplus.exe}
SERVER="$ROOT/software/Server/Python/src"
OMX=${OPENMSX:-C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe}
HARNESS="$RW/software/UNAPI/harness/lib/harness.tcl"
[ -f "$PINGPONG_ROM" ] || { echo "set PINGPONG_ROM to your own PINGPONG.ROM"; exit 1; }
WORK=${WORK:-${TMP:-/tmp}/pingpong-work}
mkdir -p "$WORK"; WORKW=$(cd "$WORK" && pwd -W 2>/dev/null || echo "$WORK")
python "$SRC/build.py" --assembler "$ASM" || exit 1
python "$ROOT/software/ROM-Patcher/profiles/pingpong/rebuild.py" --assembler "$ASM" --rom "$PINGPONG_ROM" \
  --test-gpf "$WORK/PINGPONG.GPF" --test-syms "$WORK/stub_syms.tcl" || exit 1

sh "$HERE/kill_nodes.sh"
touch "$WORK/stop_servers"
for port in 8115 8116; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  if [ -n "$pid" ]; then taskkill //F //PID $pid > /dev/null 2>&1; fi
done
sleep 3
# fresh server homes with their own copies of the boot and tools disks (written while the servers are stopped)
for n in 1 2; do
  H="$WORK/msxhome$n"; rm -rf "$H"; mkdir -p "$H/disks" "$H/tmp" "$H/games"
  cp "$WORK/PINGPONG.GPF" "$H/games/PINGPONG.GPF"
  cp "$ROOT/software/target/disks/msxpiboot.dsk" "$ROOT/software/target/disks/tools.dsk" "$H/disks/"
  cat > "$H/msxpi.ini" <<INI
var PATH=https://www.msxarchive.nl/pub/msx/games/roms/msx1
var DriveA=$WORKW/msxhome$n/disks/msxpiboot.dsk
var DriveB=$WORKW/msxhome$n/disks/tools.dsk
var DriveM=https://github.com/costarc/MSXPi/raw/master/software/target
var WIDTH=80
var SPI_HW=False
INI
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$SRC/build/PLAYNET.COM" PLAYNET.COM > /dev/null
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$PINGPONG_ROM" PINGPONG.ROM > /dev/null
  if [ "$SCENARIO" = mixed ] && { [ $n = 2 ] || [ -n "$BOTH" ]; }; then   # a TCP/IP node
    printf 'ip d 0\r\nip l 10.0.2.15\r\nip m 255.255.255.0\r\nip g 10.0.2.2\r\nip p 10.0.2.2\r\n\032' > "$WORK/INL.CFG"
    for f in MSR.COM INL.COM; do python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$ROOT/software/UNAPI/bin/$f" $f > /dev/null; done
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/INL.CFG" INL.CFG > /dev/null
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$SRC/build/PLAYNET.OVL" PLAYNET.OVL > /dev/null
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/PINGPONG.GPF" PINGPONG.GPF > /dev/null
  fi
done
# the profile hash the servers announce: the GPF's
PROFHASH=$(python -c "import struct,sys; print('%08x' % struct.unpack('<I', open(sys.argv[1],'rb').read()[8:12])[0])" "$WORK/PINGPONG.GPF")
rm -f "$WORK/stop_servers"
start() {  # n port local_udp peer_udp version
  nat=""; [ "$SCENARIO" = mixed ] && { [ $1 = 2 ] || [ -n "$BOTH" ]; } && nat="MSXPI_ETH_LINK=udpnat"
  np=""      # the Pi's own session: an MSXPi node always; a TCP/IP node only for HYBRID=1 (its game packets go through the MSXPi)
  if [ -z "$nat" ] || [ -n "$HYBRID" ]; then np="MSXPI_NETPLAY=$3:127.0.0.1:$4 MSXPI_NETPLAY_PROFILE=$PROFHASH"; fi
  ( cd "$SERVER"; while [ ! -f "$WORK/stop_servers" ]; do
      env MSXPI_PORT=$2 MSXPI_HOME="$WORKW/msxhome$1" MSXPI_INI="$WORKW/msxhome$1/msxpi.ini" MSXPI_TMP="$WORKW/msxhome$1/tmp" \
        $nat $np \
        MSXPI_NETPLAY_LAG_MS=$LAGMS MSXPI_NETPLAY_LOSS_PCT=$LOSS MSXPI_NETPLAY_JITTER_MS=$JIT \
        MSXPI_NETPLAY_DELAY=${FORCE_DELAY:-0} MSXPI_NETPLAY_VERSION=${5:-2} \
        python -u msxpi-server.py >> "$WORK/server$1.log" 2>&1
      echo "=== server $1 exited, restarting ===" >> "$WORK/server$1.log"
      sleep 1
    done ) > /dev/null 2>&1 &
}
: > "$WORK/server1.log"; : > "$WORK/server2.log"
start 1 8115 5101 5102
start 2 8116 5102 5101 ${VER2:-2}
sleep 15
mkdir -p "$WORK/np"; rm -f "$WORK"/np/*
if [ "$SCENARIO" = mixed ]; then        # what the TCP/IP node(s) type
  export PRE_P2="MSR I;INL I" CMD_P2="PLAYNET /T $PNOPTS pingpong P2 5102 10.0.2.2:5101"
  [ -z "$BOTH" ] || export PRE_P1="MSR I;INL I" CMD_P1="PLAYNET /T $PNOPTS pingpong P1 5101 10.0.2.2:5102"
  if [ -n "$HYBRID" ]; then              # link 2: the game's packets through the node's MSXPi
    export CMD_P2="PLAYNET /T /H pingpong P2"
    [ -z "$BOTH" ] || export CMD_P1="PLAYNET /T /H pingpong P1"
  fi
fi
node() {  # role port
  xs=""; [ "$1" = P1 ] && xs="$EXTRA_TCL"; [ "$1" = P2 ] && xs="$EXTRA_TCL_C"
  PLAYNET_SYMS="$WORKW/stub_syms.tcl" ROLEARG=$1 TRACE=$WORKW/np/$1.trace STOPF=$STOPF PROG="PLAYNET pingpong" \
  MSXPI_HARNESS_OUT=$WORKW/np/$1.result \
  timeout ${NODETMO:-1500} "$OMX" -machine Canon_V-25 -ext ram2mb -ext MSXPi -command "set renderer none" \
    -command "set msxpiserver_port $2" -command "set msxpirom_bank BANK2" \
    -command "set msxpirom_sltsl ON" -command "reset" -command "set renderer ${RENDERER:-none}" \
    -script "$HARNESS" -script "$RW/software/Client/tests/soccernet/pingpong_node.tcl" ${xs:+-script "$xs"} > "$WORK/np/$1.log" 2>&1
}
node P1 8115 &
NPIDS=$!
if [ -z "$ONLY" ]; then sleep 5; node P2 8116 & NPIDS="$NPIDS $!"; fi
wait $NPIDS
python "$HERE/cmp_pair.py" "$WORK/np/P1.trace" "$WORK/np/P2.trace"
grep -h "desync=" "$WORK/np/P1.trace" "$WORK/np/P2.trace"
grep -h "netplay: [a-z]" "$WORK/server1.log" "$WORK/server2.log" | grep -v "{" | tail -12
[ -z "$EXITKEY" ] || grep -h -E "^# (xend|back)" "$WORK/np/P1.trace" "$WORK/np/P2.trace"
touch "$WORK/stop_servers"
for port in 8115 8116; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  if [ -n "$pid" ]; then taskkill //F //PID $pid > /dev/null 2>&1; fi
done
