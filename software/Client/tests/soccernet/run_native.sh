#!/bin/sh
# Two openMSX (Canon V-25 + MSXPi) play Konami's Soccer with PLAYNET.COM through two stock msxpi-server.py that
# relay the stub's packets over UDP on localhost (MSXPi transport, opcode C9; no TAP adapters, no mapper).
#
#   SOCCER_ROM=/path/to/SOCCER.ROM sh run_native.sh <lag_ms> <loss_pct> [frames] [jitter_ms]
#
# Needs: sjasmplus (SJASMPLUS=path; PLAYNET.COM is built first with software/Client/src/playnet/build.py), the
# Windows openMSX build with the MSXPi device, your own SOCCER.ROM (never committed). The test stub (scripted input)
# and its GPF come from software/ROM-Patcher/profiles/soccer/rebuild.py --test-gpf. Environment:
#   SOCCER_ROM    required.        OPENMSX   path to openmsx.exe.     WORK  scratch folder (default $TMP/soccernet-work)
#   ONLY=H        run one node.    FORCE_DELAY=n  fix the delay.      VER2=n  version announced by node C
#   POKEF=n       corrupt the ball on node H at frame n (desync check)    EXITF=n  node C exits at frame n
#   TMAX/NODETMO  emulated / wall seconds before a node is stopped.   RENDERER=SDLGL-PP to watch it
#   EXTRA_TCL=file.tcl  one more openMSX script for node H (measurements)
#   RECORD=file.wav  node H records its sound (openMSX record -audioonly) and node C is muted
#   EXITKEY=n     (chat) node C presses Ctrl+Shift+F5 at frame n; both must return to MCHAT
#   SCENARIO=chat the players meet in MCHAT (against a local IRC server), alice invites bob to play, and the
#                 chat starts the game itself. Needs software/target/mchat.com. PLAY_AT / ACCEPT_AT: emulated seconds.
# Results: $WORK/np/{H,C}.trace (+.ticks, .screen); the script prints the comparison.
LAGMS=${1:-0}; LOSS=${2:-0}; STOPF=${3:-1500}; JIT=${4:-0}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)               # repository root
RW=$(cd "$ROOT" && pwd -W 2>/dev/null || echo "$ROOT")
SRC="$ROOT/software/Client/src/playnet"
ASM=${SJASMPLUS:-C:/Users/roniv/Dev/bin/sjasmplus.exe}
SRCW=$(cd "$SRC" && pwd -W 2>/dev/null || echo "$SRC")
SERVER="$ROOT/software/Server/Python/src"
OMX=${OPENMSX:-C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe}
HARNESS="$RW/software/UNAPI/harness/lib/harness.tcl"
[ -f "$SOCCER_ROM" ] || { echo "set SOCCER_ROM to your own SOCCER.ROM"; exit 1; }
[ "$SCENARIO" != chat ] || [ -f "$ROOT/software/target/mchat.com" ] || { echo "no software/target/mchat.com"; exit 1; }
WORK=${WORK:-${TMP:-/tmp}/soccernet-work}
mkdir -p "$WORK"; WORKW=$(cd "$WORK" && pwd -W 2>/dev/null || echo "$WORK")
python "$SRC/build.py" --assembler "$ASM" || exit 1
python "$ROOT/software/ROM-Patcher/profiles/soccer/rebuild.py" --assembler "$ASM" \
  --test-gpf "$WORK/SOCCER.GPF" --test-syms "$WORK/stub_syms.tcl" || exit 1

sh "$HERE/kill_nodes.sh"
touch "$WORK/stop_servers"
for port in 8115 8116 ${IRC_PORT:-6671}; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  [ -n "$pid" ] && taskkill //F //PID $pid > /dev/null 2>&1
done
sleep 3
# fresh server homes with their own copies of the boot and tools disks (written while the servers are stopped)
for n in 1 2; do
  H="$WORK/msxhome$n"; rm -rf "$H"; mkdir -p "$H/disks" "$H/tmp" "$H/games"
  cp "$WORK/SOCCER.GPF" "$H/games/SOCCER.GPF"
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
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$SOCCER_ROM" SOCCER.ROM > /dev/null
  [ "$SCENARIO" != chat ] || python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$ROOT/software/target/mchat.com" MCHAT.COM > /dev/null
done
rm -f "$WORK/stop_servers"
IRC_PORT=${IRC_PORT:-6671}
if [ "$SCENARIO" = chat ]; then
  netenv="PCHESS_IRC_HOST=127.0.0.1 PCHESS_IRC_PORT=$IRC_PORT PCHESS_IRC_TLS=0 MSXPI_NETPLAY_LAN=127.0.0.1 MSXPI_NETPLAY_NOSTUN=1"
else
  netenv=""
fi
start() {  # n port local_udp peer_udp version
  ( cd "$SERVER"; while [ ! -f "$WORK/stop_servers" ]; do
      env MSXPI_PORT=$2 MSXPI_HOME="$WORKW/msxhome$1" MSXPI_INI="$WORKW/msxhome$1/msxpi.ini" MSXPI_TMP="$WORKW/msxhome$1/tmp"       $netenv $( [ "$SCENARIO" = chat ] || echo "MSXPI_NETPLAY=$3:127.0.0.1:$4" ) MSXPI_NETPLAY_LAG_MS=$LAGMS MSXPI_NETPLAY_LOSS_PCT=$LOSS MSXPI_NETPLAY_JITTER_MS=$JIT       MSXPI_NETPLAY_DELAY=${FORCE_DELAY:-0} MSXPI_NETPLAY_VERSION=${5:-1}         python -u msxpi-server.py >> "$WORK/server$1.log" 2>&1
      echo "=== server $1 exited, restarting ===" >> "$WORK/server$1.log"
      sleep 1
    done ) > /dev/null 2>&1 &
}
: > "$WORK/server1.log"; : > "$WORK/server2.log"
if [ "$SCENARIO" = chat ]; then
  ( python -u "$HERE/irc_fixture_server.py" $IRC_PORT > "$WORK/irc.log" 2>&1 ) &
  IRC_PID=$!
fi
start 1 8115 5101 5102
start 2 8116 5102 5101 ${VER2:-1}
sleep 15
mkdir -p "$WORK/np"; rm -f "$WORK"/np/*
NODE_TCL=native_node.tcl; [ "$SCENARIO" != chat ] || NODE_TCL=chat_node.tcl
node() {  # role port
  snd=""; [ -n "$RECORD" ] && { [ "$1" = H ] && snd="record start -audioonly $RECORD" || snd="set mute on"; }
  xs=""; [ "$1" = H ] && xs="$EXTRA_TCL"
  NICK=$( [ "$1" = H ] && echo alice || echo bob ) OPPONENT=$( [ "$1" = H ] && echo bob || echo alice ) INVITE=$( [ "$1" = H ] && echo 1 || echo 0 )   PLAY_AT=${PLAY_AT:-75} ACCEPT_AT=${ACCEPT_AT:-95}   PLAYNET_SYMS="$WORKW/stub_syms.tcl" ROLEARG=$1 TRACE=$WORKW/np/$1.trace STOPF=$STOPF \
  MSXPI_HARNESS_OUT=$WORKW/np/$1.result \
  timeout ${NODETMO:-1500} "$OMX" -machine Canon_V-25 -ext ram2mb -ext MSXPi \
    -command "set msxpiserver_port $2" -command "set msxpirom_bank BANK2" \
    -command "set msxpirom_sltsl ON" -command "reset" -command "set renderer ${RENDERER:-none}" ${snd:+-command "$snd"} \
    -script "$HARNESS" -script "$RW/software/Client/tests/soccernet/$NODE_TCL" ${xs:+-script "$xs"} > "$WORK/np/$1.log" 2>&1
}
PROG="PLAYNET soccer"
export PROG
node H 8115 &
NPIDS=$!
if [ -z "$ONLY" ]; then sleep 5; node C 8116 & NPIDS="$NPIDS $!"; fi
wait $NPIDS
python "$HERE/cmp_pair.py" "$WORK/np/H.trace" "$WORK/np/C.trace"
grep -h "desync=" "$WORK/np/H.trace" "$WORK/np/C.trace"
grep -h "netplay: [a-z]" "$WORK/server1.log" "$WORK/server2.log" | grep -v "{" | tail -12
if [ -n "$EXITKEY" ]; then              # both machines must be back in MCHAT: restore, then "mchat start"
  for n in 1 2; do
    if awk '/-> playnet restore/ { r = 1 } r && /-> mchat start/ { ok = 1 } END { exit !ok }' "$WORK/server$n.log"
    then echo "server $n: back in MCHAT after the game"; else echo "server $n: NOT back in MCHAT"; fi
  done
  grep -h "^# back" "$WORK/np/H.trace" "$WORK/np/C.trace"
fi
touch "$WORK/stop_servers"
for port in 8115 8116 $IRC_PORT; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  [ -n "$pid" ] && taskkill //F //PID $pid > /dev/null 2>&1
done
