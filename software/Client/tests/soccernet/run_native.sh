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
#   HYBRID=1      (with SCENARIO=mixed) the TCP/IP node(s) play through their MSXPi (PLAYNET /T /H, link 2)
#   EXTRA_TCL=file.tcl  one more openMSX script for node H (measurements); EXTRA_TCL_C for node C
#   RECORD=file.wav  node H records its sound (openMSX record -audioonly) and node C is muted
#   EXITKEY=n     (chat) node C presses Ctrl+Shift+F5 at frame n; both must return to MCHAT
#   BOOT=nextor   (chat) Nextor (MSX-DOS 2) on a MegaFlashROM SCC+ SD instead of MSX-DOS 1 from the MSXPi. NEXTORHD =
#                 a hard-disk image (UNAPI/harness/mknextorhd.sh) with C:\PLAYNET holding PLAYNET.COM, MCHAT.COM, SOCCER.ROM
#   SCENARIO=chat the players meet in MCHAT (against a local IRC server), alice invites bob to play, and the
#                 chat starts the game itself. Needs software/target/mchat.com. PLAY_AT / ACCEPT_AT: emulated seconds.
#   SCENARIO=mixed  node H over the MSXPi, node C over the TCP/IP UNAPI: MSR I, INL I (on its server's
#                 user-mode UDP link, msxpi_ethnat.py, as 10.0.2.15), then PLAYNET /T soccer C 5102 10.0.2.2:5101.
#                 Both=1: both nodes over TCP/IP (H: PLAYNET /T soccer H 5101 10.0.2.2:5102).
#   SCENARIO=tcp  the chat scenario over TCP/IP on both nodes: MSR I, INL I, MCHAT /1 /T (this checkout's,
#                 built with build_client.py) against the IRC fixture at 10.0.2.2; /play and /accept, MCHAT
#                 writes PLAYNET.SES and types PLAYNET /T, which goes back to MCHAT /T on the same IRC
#                 connection (with EXITKEY: the IRC log must show each nick's NAMES after the game). The IRC
#                 server pings every IRC_PING s (3) and drops a client silent for IRC_TIMEOUT s (60, wall clock), so the
#                 connection survives only if PLAYNET answers during the game.
#   GAMELINK1=1   (tcp) MCHAT.INI GAMELINK=1: the game over TCP/IP (link 1); without it MCHAT /T asks its MSXPi first (link 2)
#   PLAININI=1    (tcp) MCHAT.INI without GAMEPORT/GAMEADDR, as a user writes it: the game cannot connect through the
#                 rig's NAT, but the chat must survive /play and /accept (the FFh globals of make.bat's build)
# Results: $WORK/np/{H,C}.trace (+.ticks, .screen); the script prints the comparison.
LAGMS=${1:-0}; LOSS=${2:-0}; STOPF=${3:-1500}; JIT=${4:-0}
HERE=$(cd "$(dirname "$0")" && pwd)
python "$HERE/rig_preflight.py" || exit 1   # the ROM openMSX loads must be this branch's (A1)
ROOT=$(cd "$HERE/../../../.." && pwd)               # repository root
RW=$(cd "$ROOT" && pwd -W 2>/dev/null || echo "$ROOT")
SRC="$ROOT/software/Client/src/playnet"
ASM=${SJASMPLUS:-C:/Users/roniv/Dev/bin/sjasmplus.exe}
SRCW=$(cd "$SRC" && pwd -W 2>/dev/null || echo "$SRC")
SERVER="$ROOT/software/Server/Python/src"
OMX=${OPENMSX:-C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.7.0/openmsx.exe}
HARNESS="$RW/software/UNAPI/harness/lib/harness.tcl"
[ -f "$SOCCER_ROM" ] || { echo "set SOCCER_ROM to your own SOCCER.ROM"; exit 1; }
[ "$SCENARIO" != chat ] || [ -f "$ROOT/software/target/mchat.com" ] || { echo "no software/target/mchat.com"; exit 1; }
CHAT=; case "$SCENARIO" in chat|tcp) CHAT=1;; esac
TCPN=; case "$SCENARIO" in mixed|tcp) TCPN=1;; esac
[ "$SCENARIO" != tcp ] || BOTH=1
WORK=${WORK:-${TMP:-/tmp}/soccernet-work}
mkdir -p "$WORK"; WORKW=$(cd "$WORK" && pwd -W 2>/dev/null || echo "$WORK")
[ "$SCENARIO" != tcp ] || python "$HERE/build_client.py" mchat "$WORK/mchat" || exit 1
python "$SRC/build.py" --assembler "$ASM" || exit 1
python "$ROOT/software/ROM-Patcher/profiles/soccer/rebuild.py" --assembler "$ASM" \
  --test-gpf "$WORK/SOCCER.GPF" --test-syms "$WORK/stub_syms.tcl" || exit 1

# own ports (P1PORT/P2PORT = the servers, UDP1/UDP2 = the game packets): other rigs may run on the defaults
P1PORT=${P1PORT:-8115}; P2PORT=${P2PORT:-8116}; UDP1=${UDP1:-5101}; UDP2=${UDP2:-5102}
# stop only this rig's own leftovers: an openMSX whose command line sets one of its server ports (kill_nodes.sh would stop
# every rig's emulators)
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.Name -eq 'openmsx.exe' -and \$_.CommandLine -match 'msxpiserver_port ($P1PORT|$P2PORT)' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" > /dev/null 2>&1
touch "$WORK/stop_servers"
for port in $P1PORT $P2PORT ${IRC_PORT:-6671}; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  if [ -n "$pid" ]; then taskkill //F //PID $pid > /dev/null 2>&1; fi
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
  if [ -n "$TCPN" ] && { [ $n = 2 ] || [ -n "$BOTH" ]; }; then   # a TCP/IP node
    printf 'ip d 0\r\nip l 10.0.2.15\r\nip m 255.255.255.0\r\nip g 10.0.2.2\r\nip p 10.0.2.2\r\n\032' > "$WORK/INL.CFG"
    for f in MSR.COM INL.COM; do python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$ROOT/software/UNAPI/bin/$f" $f > /dev/null; done
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/INL.CFG" INL.CFG > /dev/null
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$SRC/build/PLAYNET.OVL" PLAYNET.OVL > /dev/null
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/SOCCER.GPF" SOCCER.GPF > /dev/null
  fi
  if [ "$SCENARIO" = tcp ]; then        # the chat over TCP/IP: its INI (the IRC fixture is the host, 10.0.2.2)
    nick=$( [ $n = 1 ] && echo alice || echo bob )
    if [ -n "$PLAININI" ]; then
      printf 'IRCADDR=10.0.2.2\r\nIRCPORT=%s\r\nIRCNICK=%s\r\nMCHATROOM=#msxpi\r\n\032' "${IRC_PORT:-6671}" $nick > "$WORK/MCHAT$n.INI"
    else
      printf 'IRCADDR=10.0.2.2\r\nIRCPORT=%s\r\nIRCNICK=%s\r\nMCHATROOM=#msxpi\r\nGAMEPORT=510%s\r\nGAMEADDR=10.0.2.2\r\n%b\032' \
        "${IRC_PORT:-6671}" $nick $n "${GAMELINK1:+GAMELINK=1\r\n}" > "$WORK/MCHAT$n.INI"
    fi
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/MCHAT$n.INI" MCHAT.INI > /dev/null
    python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$WORK/mchat/MCHAT.COM" MCHAT.COM > /dev/null
  fi
done
# the profile hash a TCP/IP node announces (the GPF's): an MSXPi node's server must announce the same
PROFHASH=$(python -c "import struct,sys; print('%08x' % struct.unpack('<I', open(sys.argv[1],'rb').read()[8:12])[0])" "$WORK/SOCCER.GPF")
rm -f "$WORK/stop_servers"
IRC_PORT=${IRC_PORT:-6671}
if [ -n "$CHAT" ]; then
  netenv="PCHESS_IRC_HOST=127.0.0.1 PCHESS_IRC_PORT=$IRC_PORT PCHESS_IRC_TLS=0 MSXPI_NETPLAY_LAN=127.0.0.1 MSXPI_NETPLAY_NOSTUN=1"
else
  netenv=""
fi
start() {  # n port local_udp peer_udp version
  nat=""; [ -n "$TCPN" ] && { [ $1 = 2 ] || [ -n "$BOTH" ]; } && nat="MSXPI_ETH_LINK=udpnat"
  np=""      # the Pi's own session: an MSXPi node always; a TCP/IP node only for HYBRID=1 (its game packets go through the MSXPi)
  if [ -z "$CHAT" ]; then
    if [ -z "$nat" ] || [ -n "$HYBRID" ]; then np="MSXPI_NETPLAY=$3:127.0.0.1:$4 MSXPI_NETPLAY_PROFILE=$PROFHASH"; fi
  fi
  ( cd "$SERVER"; while [ ! -f "$WORK/stop_servers" ]; do
      env MSXPI_PORT=$2 MSXPI_HOME="$WORKW/msxhome$1" MSXPI_INI="$WORKW/msxhome$1/msxpi.ini" MSXPI_TMP="$WORKW/msxhome$1/tmp"       $netenv $nat $np MSXPI_NETPLAY_LAG_MS=$LAGMS MSXPI_NETPLAY_LOSS_PCT=$LOSS MSXPI_NETPLAY_JITTER_MS=$JIT       MSXPI_NETPLAY_DELAY=${FORCE_DELAY:-0} MSXPI_NETPLAY_VERSION=${5:-2}         python -u msxpi-server.py >> "$WORK/server$1.log" 2>&1
      echo "=== server $1 exited, restarting ===" >> "$WORK/server$1.log"
      sleep 1
    done ) > /dev/null 2>&1 &
}
: > "$WORK/server1.log"; : > "$WORK/server2.log"
if [ -n "$CHAT" ]; then
  pings=""; [ "$SCENARIO" != tcp ] || pings="${IRC_PING:-3} ${IRC_TIMEOUT:-60}"   # PING every 3 s, drop after 60 s of silence (wall clock)
  ( python -u "$HERE/irc_fixture_server.py" $IRC_PORT $pings > "$WORK/irc.log" 2>&1 ) &
  IRC_PID=$!
fi
start 1 $P1PORT $UDP1 $UDP2
start 2 $P2PORT $UDP2 $UDP1 ${VER2:-2}
sleep 15
mkdir -p "$WORK/np"; rm -f "$WORK"/np/*
NODE_TCL=native_node.tcl; [ -z "$CHAT" ] || NODE_TCL=chat_node.tcl
[ "$SCENARIO" != tcp ] || export PRE_H="MSR I;INL I" PRE_C="MSR I;INL I" CHAT_TCP=1
if [ "$SCENARIO" = mixed ]; then        # what the TCP/IP node(s) type
  export PRE_C="MSR I;INL I" CMD_C="PLAYNET /T $PNOPTS soccer C $UDP2 10.0.2.2:$UDP1"
  [ -z "$BOTH" ] || export PRE_H="MSR I;INL I" CMD_H="PLAYNET /T $PNOPTS soccer H $UDP1 10.0.2.2:$UDP2"
  if [ -n "$HYBRID" ]; then              # link 2: the game's packets through the node's MSXPi, the stack kept for the chat
    export CMD_C="PLAYNET /T /H soccer C"
    [ -z "$BOTH" ] || export CMD_H="PLAYNET /T /H soccer H"
  fi
fi
node() {  # role port
  snd=""; [ -n "$RECORD" ] && { [ "$1" = H ] && snd="record start -audioonly $RECORD" || snd="set mute on"; }
  xs=""; [ "$1" = H ] && xs="$EXTRA_TCL"; [ "$1" = C ] && xs="$EXTRA_TCL_C"
  hw="-ext ram2mb"; hd="set renderer none"
  if [ "$BOOT" = nextor ]; then          # each node gets its own copy: openMSX writes to the image
    cp "$NEXTORHD" "$WORK/nextor_$1.dsk"
    hw="-ext MegaFlashROM_SCC+_SD"; hd="hdb {$WORKW/nextor_$1.dsk}"
  fi
  NICK=$( [ "$1" = H ] && echo alice || echo bob ) OPPONENT=$( [ "$1" = H ] && echo bob || echo alice ) INVITE=$( [ "$1" = H ] && echo 1 || echo 0 )   PLAY_AT=${PLAY_AT:-75} ACCEPT_AT=${ACCEPT_AT:-95}   PLAYNET_SYMS="$WORKW/stub_syms.tcl" ROLEARG=$1 TRACE=$WORKW/np/$1.trace STOPF=$STOPF \
  MSXPI_HARNESS_OUT=$WORKW/np/$1.result \
  BOOT=$BOOT timeout ${NODETMO:-1500} "$OMX" -machine Canon_V-25 $hw -ext MSXPi -command "$hd" \
    -command "set msxpiserver_port $2" -command "set msxpirom_bank BANK2" \
    -command "set msxpirom_sltsl ON" -command "reset" -command "set renderer ${RENDERER:-none}" ${snd:+-command "$snd"} \
    -script "$HARNESS" -script "$RW/software/Client/tests/soccernet/$NODE_TCL" ${xs:+-script "$xs"} > "$WORK/np/$1.log" 2>&1
}
PROG="PLAYNET soccer"
export PROG
node H $P1PORT &
NPIDS=$!
if [ -z "$ONLY" ]; then sleep 5; node C $P2PORT & NPIDS="$NPIDS $!"; fi
wait $NPIDS
python "$HERE/cmp_pair.py" "$WORK/np/H.trace" "$WORK/np/C.trace"
grep -h "desync=" "$WORK/np/H.trace" "$WORK/np/C.trace"
grep -h "netplay: [a-z]" "$WORK/server1.log" "$WORK/server2.log" | grep -v "{" | tail -12
if [ -n "$EXITKEY" ] && [ "$SCENARIO" = tcp ]; then   # MCHAT /T quits IRC before the game and connects again after it
  for nick in alice bob; do
    if awk -v n="$nick" '$2 == n && /:MSXG1 (GO|ACCEPT) / { g = 1 } g && $2 == n && / QUIT / { q = 1 } END { exit !q }' "$WORK/irc.log"
    then echo "$nick: sent QUIT after the launch"; else echo "$nick: NO QUIT after the launch"; fi
    c=$(awk -v n="$nick" '$2 == n && /:MSXG1 (GO|ACCEPT) / { c = $1 } END { print c }' "$WORK/irc.log")
    if awk -v n="$nick" -v c="$c" '$2 == n && $1 > c && / JOIN #/ { ok = 1 } END { exit !ok }' "$WORK/irc.log"
    then echo "$nick: back in MCHAT /T on a new IRC connection"; else echo "$nick: NOT back in MCHAT /T"; fi
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
[ -z "$EXITKEY" ] || grep -h -E "^# (xend|back)" "$WORK/np/H.trace" "$WORK/np/C.trace"
touch "$WORK/stop_servers"
for port in $P1PORT $P2PORT $IRC_PORT; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  if [ -n "$pid" ]; then taskkill //F //PID $pid > /dev/null 2>&1; fi
done
