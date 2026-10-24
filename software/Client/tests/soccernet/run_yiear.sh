#!/bin/sh
# Two openMSX (Canon V-25 + MSXPi) play Konami's Yie Ar Kung-Fu with PLAYNET.COM through two stock msxpi-server.py that
# relay the stub's packets over UDP on localhost (MSXPi transport, no TAP adapters, no mapper). From run_native.sh.
#
#   [MODE=0|1|2] YIEAR_ROM=/path/to/kung-fu.rom sh run_yiear.sh <lag_ms> <loss_pct> [frames] [jitter_ms]
#
# Needs sjasmplus (SJASMPLUS=path), the Windows openMSX build with the MSXPi device and your own kung-fu.rom (never
# committed). The player is Tcl key presses (yiear_node.tcl: MODE = the menu choice, 0 Single, 1 Turn, 2 Versus; KEYSEED); the
# GPF is the release stub's, built by profiles/yiear/rebuild.py --keys --test-gpf. Environment:
#   OPENMSX  path to openmsx.exe.   WORK  scratch folder (default $TMP/yiear-work)   ONLY=P1  run one node
#   FORCE_DELAY=n  fix the delay.   POKEF=n  corrupt Oolong on P1 at frame n (desync check)   EXITF=n  P2 exits at frame n
#   EXITKEY=n  P2 presses Ctrl+Shift+F5 at frame n.   TMAX/NODETMO  emulated / wall seconds before a node is stopped
#   RENDERER=SDLGL-PP to watch it.   EXTRA_TCL / EXTRA_TCL_C  one more script for P1 / P2
#   SCENARIO=tcp   the chat over TCP/IP on both nodes (MSR I, INL I, MCHAT /1 /T) against the IRC fixture at 10.0.2.2; with an MSXPi
#                 on each machine the game itself runs over the MSXPi (link 2).
#   SCENARIO=both  no chat: both machines over TCP/IP (MSR I, INL I, then PLAYNET /T yiear P1 .. 10.0.2.2:..), the game packets over
#                 the server's user-mode UDP link. PNOPTS = more PLAYNET /T options.
#   SCENARIO=chat  the players meet in MCHAT (against a local IRC server): P1 invites P2 (/play bob yiear), P2 accepts, and the chat
#                 starts the game itself. EXITKEY=n then also checks that both machines are back in MCHAT. Needs software/target/mchat.com.
#                 PLAY_AT / ACCEPT_AT: emulated seconds. IRC_PORT (6637).
# Not here: a mixed pair (one MSXPi node, one TCP/IP node).
# Results: $WORK/np/{P1,P2}.trace; the script prints the comparison.
LAGMS=${1:-0}; LOSS=${2:-0}; STOPF=${3:-1500}; JIT=${4:-0}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)               # repository root
RW=$(cd "$ROOT" && pwd -W 2>/dev/null || echo "$ROOT")
SRC="$ROOT/software/Client/src/playnet"
ASM=${SJASMPLUS:-C:/Users/roniv/Dev/bin/sjasmplus.exe}
SERVER="$ROOT/software/Server/Python/src"
OMX=${OPENMSX:-C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe}
HARNESS="$RW/software/UNAPI/harness/lib/harness.tcl"
case "$SCENARIO" in chat) [ -f "$ROOT/software/target/mchat.com" ] ;; *) true ;; esac || { echo "no software/target/mchat.com"; exit 1; }
CHAT=; case "$SCENARIO" in chat|tcp) CHAT=1;; esac
TCPN=; case "$SCENARIO" in tcp|both) TCPN=1;; esac
# own ports (other sessions run the Soccer, Ping Pong and Salamander rigs on 8115/8116, 5101/5102, 6671): override with P1PORT/P2PORT/UDP1/UDP2/IRC_PORT
P1PORT=${P1PORT:-8137}; P2PORT=${P2PORT:-8138}; UDP1=${UDP1:-5137}; UDP2=${UDP2:-5138}
IRC_PORT=${IRC_PORT:-6637}
[ -f "$YIEAR_ROM" ] || { echo "set YIEAR_ROM to your own kung-fu.rom"; exit 1; }
WORK=${WORK:-${TMP:-/tmp}/yiear-work}
mkdir -p "$WORK"; WORKW=$(cd "$WORK" && pwd -W 2>/dev/null || echo "$WORK")
python "$SRC/build.py" --assembler "$ASM" || exit 1
[ "$SCENARIO" != tcp ] || python "$HERE/build_client.py" mchat "$WORK/mchat" || exit 1
python "$ROOT/software/ROM-Patcher/profiles/yiear/rebuild.py" --assembler "$ASM" --rom "$YIEAR_ROM" \
  --keys --test-gpf "$WORK/YIEAR.GPF" --test-syms "$WORK/stub_syms.tcl" || exit 1

# stop only this rig's own leftovers (an openMSX running yiear_node.tcl from this WORK folder, and what listens on its ports); a port in use by
# anything else is not touched: the run stops instead
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.Name -eq 'openmsx.exe' -and \$_.CommandLine -match 'yiear_node\.tcl' -and \$_.CommandLine -like '*yiear*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" > /dev/null 2>&1
touch "$WORK/stop_servers"
for port in $P1PORT $P2PORT $IRC_PORT; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  if [ -n "$pid" ]; then
    cmd=$(powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter 'ProcessId=$pid').CommandLine" 2>/dev/null)
    case "$cmd" in
      *msxpi-server*|*irc_fixture_server*) taskkill //F //PID $pid > /dev/null 2>&1 ;;     # this rig's own leftover (a server or the IRC fixture)
      *) echo "port $port is in use by another program (pid $pid): $cmd"; echo "set P1PORT, P2PORT or IRC_PORT"; exit 1 ;;
    esac
  fi
done
sleep 3
# fresh server homes with their own copies of the boot and tools disks (written while the servers are stopped)
for n in 1 2; do
  H="$WORK/msxhome$n"; rm -rf "$H"; mkdir -p "$H/disks" "$H/tmp" "$H/games"
  cp "$WORK/YIEAR.GPF" "$H/games/YIEAR.GPF"
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
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$YIEAR_ROM" KUNG-FU.ROM > /dev/null
  [ "$SCENARIO" != chat ] || python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$ROOT/software/target/mchat.com" MCHAT.COM > /dev/null
  if [ -n "$TCPN" ]; then                # both nodes over TCP/IP: INL on the server's user-mode UDP link (10.0.2.15), the chat over TCP/IP
    printf 'ip d 0\r\nip l 10.0.2.15\r\nip m 255.255.255.0\r\nip g 10.0.2.2\r\nip p 10.0.2.2\r\n\032' > "$WORK/INL.CFG"
    for f in MSR.COM INL.COM; do python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$ROOT/software/UNAPI/bin/$f" $f > /dev/null; done
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/INL.CFG" INL.CFG > /dev/null
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$SRC/build/PLAYNET.OVL" PLAYNET.OVL > /dev/null
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/YIEAR.GPF" YIEAR.GPF > /dev/null
    nick=$( [ $n = 1 ] && echo alice || echo bob )
    if [ "$SCENARIO" = tcp ]; then
    printf 'IRCADDR=10.0.2.2\r\nIRCPORT=%s\r\nIRCNICK=%s\r\nMCHATROOM=#msxpi\r\nGAMEPORT=51%s\r\nGAMEADDR=10.0.2.2\r\n\032' "$IRC_PORT" $nick $((37 + n)) > "$WORK/MCHAT$n.INI"
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/MCHAT$n.INI" MCHAT.INI > /dev/null
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/mchat/MCHAT.COM" MCHAT.COM > /dev/null
    fi
  fi
done
# the profile hash the servers announce: the GPF's
PROFHASH=$(python -c "import struct,sys; print('%08x' % struct.unpack('<I', open(sys.argv[1],'rb').read()[8:12])[0])" "$WORK/YIEAR.GPF")
rm -f "$WORK/stop_servers"
netenv=""
[ -z "$CHAT" ] || netenv="PCHESS_IRC_HOST=127.0.0.1 PCHESS_IRC_PORT=$IRC_PORT PCHESS_IRC_TLS=0 MSXPI_NETPLAY_LAN=127.0.0.1 MSXPI_NETPLAY_NOSTUN=1"
start() {  # n port local_udp peer_udp version
  nat=""; [ -n "$TCPN" ] && nat="MSXPI_ETH_LINK=udpnat"
  np=""; [ -n "$CHAT" ] || np="MSXPI_NETPLAY=$3:127.0.0.1:$4 MSXPI_NETPLAY_PROFILE=$PROFHASH"
  ( cd "$SERVER"; while [ ! -f "$WORK/stop_servers" ]; do
      env MSXPI_PORT=$2 MSXPI_HOME="$WORKW/msxhome$1" MSXPI_INI="$WORKW/msxhome$1/msxpi.ini" MSXPI_TMP="$WORKW/msxhome$1/tmp" \
        $netenv $nat $np \
        MSXPI_NETPLAY_LAG_MS=$LAGMS MSXPI_NETPLAY_LOSS_PCT=$LOSS MSXPI_NETPLAY_JITTER_MS=$JIT \
        MSXPI_NETPLAY_DELAY=${FORCE_DELAY:-0} MSXPI_NETPLAY_VERSION=${5:-2} \
        python -u msxpi-server.py >> "$WORK/server$1.log" 2>&1
      echo "=== server $1 exited, restarting ===" >> "$WORK/server$1.log"
      sleep 1
    done ) > /dev/null 2>&1 &
}
: > "$WORK/server1.log"; : > "$WORK/server2.log"
if [ -n "$CHAT" ]; then
  pings=""; [ -z "$TCPN" ] || pings="${IRC_PING:-3} ${IRC_TIMEOUT:-60}"
  ( python -u "$HERE/irc_fixture_server.py" $IRC_PORT $pings > "$WORK/irc.log" 2>&1 ) &
fi
start 1 $P1PORT $UDP1 $UDP2
start 2 $P2PORT $UDP2 $UDP1 ${VER2:-2}
sleep 15
mkdir -p "$WORK/np"; rm -f "$WORK"/np/*
[ -z "$TCPN" ] || export PRE_P1="MSR I;INL I" PRE_P2="MSR I;INL I"
[ "$SCENARIO" != tcp ] || export CHAT_TCP=1
if [ "$SCENARIO" = both ]; then          # no chat: each machine types the start line (PLAYNET /T game role port peer), its game over TCP/IP
  export CMD_P1="PLAYNET /T $PNOPTS yiear P1 $UDP1 10.0.2.2:$UDP2" CMD_P2="PLAYNET /T $PNOPTS yiear P2 $UDP2 10.0.2.2:$UDP1"
fi
node() {  # role port
  xs=""; [ "$1" = P1 ] && xs="$EXTRA_TCL"; [ "$1" = P2 ] && xs="$EXTRA_TCL_C"
  NICK=$( [ "$1" = P1 ] && echo alice || echo bob ) OPPONENT=$( [ "$1" = P1 ] && echo bob || echo alice ) INVITE=$( [ "$1" = P1 ] && echo 1 || echo 0 ) \
  PLAY_AT=${PLAY_AT:-75} ACCEPT_AT=${ACCEPT_AT:-95} CHAT=$CHAT MODE=${MODE:-0} KEYSEED=${KEYSEED:-1} PLAYNET_SYMS="$WORKW/stub_syms.tcl" ROLEARG=$1 TRACE=$WORKW/np/$1.trace STOPF=$STOPF PROG="PLAYNET yiear" \
  MSXPI_HARNESS_OUT=$WORKW/np/$1.result \
  timeout ${NODETMO:-1500} "$OMX" -machine Canon_V-25 -ext ram2mb -ext MSXPi -command "set renderer none" \
    -command "set msxpiserver_port $2" -command "set msxpirom_bank BANK2" \
    -command "set msxpirom_sltsl ON" -command "reset" -command "set renderer ${RENDERER:-none}" \
    -script "$HARNESS" -script "$RW/software/Client/tests/soccernet/yiear_node.tcl" ${xs:+-script "$xs"} > "$WORK/np/$1.log" 2>&1
}
node P1 $P1PORT &
NPIDS=$!
if [ -z "$ONLY" ]; then sleep 5; node P2 $P2PORT & NPIDS="$NPIDS $!"; fi
wait $NPIDS
python "$HERE/cmp_pair.py" "$WORK/np/P1.trace" "$WORK/np/P2.trace"
grep -h "desync=" "$WORK/np/P1.trace" "$WORK/np/P2.trace"
grep -h "netplay: [a-z]" "$WORK/server1.log" "$WORK/server2.log" | grep -v "{" | tail -12
if [ -n "$EXITKEY" ] && [ "$SCENARIO" = tcp ]; then   # back in MCHAT /T on the same IRC connection: NAMES after GO
  for nick in alice bob; do
    if awk -v n="$nick" '$2 == n && /:MSXG1 (GO|ACCEPT) / { c = $1 } c != "" && $1 == c && /NAMES #/ { ok = 1 } END { exit !ok }' "$WORK/irc.log"
    then echo "$nick: back in MCHAT /T on the same IRC connection"; else echo "$nick: NOT back in MCHAT /T"; fi
  done
  grep -c "^conn" "$WORK/irc.log" | sed 's/^/IRC connections opened: /'
  grep "^drop" "$WORK/irc.log" || echo "no IRC client dropped for silence"
fi
if [ -n "$EXITKEY" ] && [ "$SCENARIO" = chat ]; then   # both must be back in MCHAT: restore, then "mchat start"
  for n in 1 2; do
    if awk '/-> playnet restore/ { r = 1 } r && /-> mchat start/ { ok = 1 } END { exit !ok }' "$WORK/server$n.log"
    then echo "server $n: back in MCHAT after the game"; else echo "server $n: NOT back in MCHAT"; fi
  done
fi
[ -z "$EXITKEY" ] || grep -h -E "^# (xend|back|result)" "$WORK/np/P1.trace" "$WORK/np/P2.trace"
touch "$WORK/stop_servers"
for port in $P1PORT $P2PORT $IRC_PORT; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  if [ -n "$pid" ]; then taskkill //F //PID $pid > /dev/null 2>&1; fi
done
