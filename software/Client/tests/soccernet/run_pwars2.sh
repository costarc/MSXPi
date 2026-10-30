#!/bin/sh
# Two openMSX (Canon V-25 + MSXPi + a 2 MB memory mapper) play Penguin-kun Wars 2 in versus (player 2 is the opponent)
# with PLAYNET.COM (image host mapper-ram, ASCII16) through two stock msxpi-server.py that relay the stub's packets
# over UDP on localhost; with TCP=1 one or both nodes play over the TCP/IP UNAPI instead (link 1, the bridged
# transport). Link 2 (HYBRID) is not possible for this game: its transport area is above every TPA top.
#
#   PWARS2_ROM=/path/to/P-WARS2.ROM sh run_pwars2.sh [frames] [lag_ms] [loss_pct]
#
# Needs sjasmplus (SJASMPLUS=path), the Windows openMSX build with the MSXPi device and your own P-WARS2.ROM (never
# committed). The release stub and its GPF come from software/ROM-Patcher/profiles/pwars2/rebuild.py. Environment:
#   OPENMSX  path to openmsx.exe.   WORK  scratch folder (default $TMP/pwars2-work)
#   ONLY=P1  run one node.          EXT2=... the second node's memory instead of ram2mb (ram512k: the smallest that fits)
#   TMAX/NODETMO  emulated / wall seconds before a node is stopped.   RENDERER=SDLGL-PP to watch it
#   TCP=1    P2 over the TCP/IP UNAPI: Nextor on a MegaFlashROM SCC+ SD (its own memory mapper), from a copy of NEXTORHD
#            (UNAPI/harness/mknextorhd.sh; default C:/Users/roniv/Dev/MSX/NextorHD.dsk) with C:\PLAYNET added through
#            WSL's openMSX (nextor_folder.sh); RAMHELPR I, INL I on its server's user-mode UDP link (10.0.2.15), then
#            PLAYNET /T pwars2 P2 $UDP2 10.0.2.2:$UDP1. Its memory: EXT2 (ram2mb) behind a slot expander.
#   BOTH=1   (with TCP=1) P1 too over the TCP/IP UNAPI (its own Nextor image; EXT1 = its memory, default ram2mb).
#   CHAT=1 with TCP=1 BOTH=1: MCHAT /T on Nextor against the IRC fixture at 10.0.2.2 (GAMELINK=1: the game over TCP/IP).
#   EXITKEY=n  P2 presses the exit key (Ctrl+Shift+F5) at frame n: both games end; with CHAT both must be back in
#            MCHAT (each MSXPi saw "playnet restore", then "mchat start"). Set the frames above n.
#   CHAT=1   the players meet in MCHAT (software/target/mchat.com, against a local IRC server): alice (P1) invites bob
#            with "/play bob pwars2", bob accepts, and the chat starts PLAYNET itself. PLAY_AT / ACCEPT_AT: emulated s.
# Results: $WORK/np/{P1,P2}.trace (+ .screen and screenshots); the script prints the comparison.
STOPF=${1:-3000}; LAGMS=${2:-0}; LOSS=${3:-0}
HERE=$(cd "$(dirname "$0")" && pwd)
python "$HERE/rig_preflight.py" || exit 1   # the ROM openMSX loads must be this branch's (A1)
ROOT=$(cd "$HERE/../../../.." && pwd)
RW=$(cd "$ROOT" && pwd -W 2>/dev/null || echo "$ROOT")
SRC="$ROOT/software/Client/src/playnet"
PKG="$ROOT/software/ROM-Patcher/profiles/pwars2"
ASM=${SJASMPLUS:-C:/Users/roniv/Dev/bin/sjasmplus.exe}
SERVER="$ROOT/software/Server/Python/src"
OMX=${OPENMSX:-C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.7.0/openmsx.exe}
HARNESS="$RW/software/UNAPI/harness/lib/harness.tcl"
[ -f "$PWARS2_ROM" ] || { echo "set PWARS2_ROM to your own P-WARS2.ROM"; exit 1; }
WORK=${WORK:-${TMP:-/tmp}/pwars2-work}
IRC_PORT=${IRC_PORT:-6691}
# ports of its own (other games' rigs use 8115/8116, 8125/8126, 5101/5102, 5121/5122, 5131/5132, 6671, 6681): the two servers, the two game UDP ports
SPORT1=${SPORT1:-8145}; SPORT2=${SPORT2:-8146}; UDP1=${UDP1:-5141}; UDP2=${UDP2:-5142}
[ -z "$CHAT" ] || [ -f "$ROOT/software/target/mchat.com" ] || { echo "no software/target/mchat.com"; exit 1; }
mkdir -p "$WORK"; WORKW=$(cd "$WORK" && pwd -W 2>/dev/null || echo "$WORK")
python "$SRC/build.py" --assembler "$ASM" || exit 1
python "$PKG/rebuild.py" --assembler "$ASM" --syms "$WORK/stub_syms.tcl" || exit 1
rm -f "$WORK/PWARS2.GPF"
python "$ROOT/software/ROM-Patcher/patch_rom.py" --profile "$PKG/profile.json" --gpf "$WORK/PWARS2.GPF" "$PWARS2_ROM" || exit 1

# only this rig's own emulators (kill_nodes.sh would also stop other games' rigs)
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.Name -eq 'openmsx.exe' -and \$_.CommandLine -match 'pwars2_node' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" > /dev/null 2>&1
touch "$WORK/stop_servers"
for port in $SPORT1 $SPORT2 $IRC_PORT; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  if [ -n "$pid" ]; then taskkill //F //PID $pid > /dev/null 2>&1; fi
done
sleep 3
for n in 1 2; do
  H="$WORK/msxhome$n"; rm -rf "$H"; mkdir -p "$H/disks" "$H/tmp" "$H/games"
  cp "$WORK/PWARS2.GPF" "$H/games/PWARS2.GPF"
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
  python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$PWARS2_ROM" P-WARS2.ROM > /dev/null || exit 1
  [ -z "$CHAT" ] || python "$HERE/fat12_add.py" "$H/disks/tools.dsk" "$ROOT/software/target/mchat.com" MCHAT.COM > /dev/null || exit 1
done
# the TCP/IP nodes' hard disks: C:\PLAYNET (P2; also P1 with BOTH=1)
for n in 2 1; do
  [ -n "$TCP" ] || break
  [ $n = 2 ] || [ -n "$BOTH" ] || continue
  D="$WORK/hdplaynet$n"; rm -rf "$D"; mkdir -p "$D"
  cp "$SRC/build/PLAYNET.COM" "$SRC/build/PLAYNET.OVL" "$WORK/PWARS2.GPF" "$ROOT/software/UNAPI/bin/INL.COM" \
    "$ROOT/software/UNAPI/bin/RAMHELPR.COM" "$ROOT/software/target/ETHUNAPI.COM" "$D/"
  cp "$PWARS2_ROM" "$D/P-WARS2.ROM"
  if [ -n "$CHAT" ]; then               # the chat over TCP/IP: MCHAT /T in C:\PLAYNET with its INI (the IRC fixture is the host)
    cp "$ROOT/software/target/mchat.com" "$D/MCHAT.COM"
    nick=$( [ $n = 1 ] && echo alice || echo bob )
    gl='GAMELINK=1\r\n'; [ -z "$HYBRID" ] || gl=""      # link 1: the game's packets over TCP/IP; link 2: through the MSXPi
    printf 'IRCADDR=10.0.2.2\r\nIRCPORT=%s\r\nIRCNICK=%s\r\nMCHATROOM=#msxpi\r\nGAMEPORT=514%s\r\nGAMEADDR=10.0.2.2\r\n%b\032' \
      "$IRC_PORT" $nick $n "$gl" > "$D/MCHAT.INI"
  fi
  printf 'ip d 0\r\nip l 10.0.2.15\r\nip m 255.255.255.0\r\nip g 10.0.2.2\r\nip p 10.0.2.2\r\n\032' > "$D/INL.CFG"
  sh "$HERE/nextor_folder.sh" "${NEXTORHD:-C:/Users/roniv/Dev/MSX/NextorHD.dsk}" "$WORKW/nextor_P$n.dsk" \
    "$(cd "$D" && pwd -W)" PLAYNET || exit 1
done
PROFHASH=$(python -c "import struct,sys; print('%08x' % struct.unpack('<I', open(sys.argv[1],'rb').read()[8:12])[0])" "$WORK/PWARS2.GPF")
rm -f "$WORK/stop_servers"
start() {  # n port local_udp peer_udp
  net="MSXPI_NETPLAY=$3:127.0.0.1:$4 MSXPI_NETPLAY_PROFILE=$PROFHASH"   # TCP=1: P2's server is INL's network link
  # a TCP/IP node's server is INL's network link; with HYBRID=1 it also runs the node's own session (link 2)
  [ -n "$TCP" ] && { [ $1 = 2 ] || [ -n "$BOTH" ]; } && { net="MSXPI_ETH_LINK=udpnat"; [ -z "$HYBRID" ] || net="$net MSXPI_NETPLAY=$3:127.0.0.1:$4 MSXPI_NETPLAY_PROFILE=$PROFHASH"; }
  if [ -n "$CHAT" ]; then
    net="PCHESS_IRC_HOST=127.0.0.1 PCHESS_IRC_PORT=$IRC_PORT PCHESS_IRC_TLS=0 MSXPI_NETPLAY_LAN=127.0.0.1 MSXPI_NETPLAY_NOSTUN=1"
    [ -z "$TCP" ] || net="$net MSXPI_ETH_LINK=udpnat"
  fi
  ( cd "$SERVER"; while [ ! -f "$WORK/stop_servers" ]; do
      env MSXPI_PORT=$2 MSXPI_HOME="$WORKW/msxhome$1" MSXPI_INI="$WORKW/msxhome$1/msxpi.ini" MSXPI_TMP="$WORKW/msxhome$1/tmp" \
        $net MSXPI_NETPLAY_LAG_MS=$LAGMS MSXPI_NETPLAY_LOSS_PCT=$LOSS \
        MSXPI_NETPLAY_DELAY=0 MSXPI_NETPLAY_VERSION=${VER:-2} python -u msxpi-server.py >> "$WORK/server$1.log" 2>&1
      echo "=== server $1 exited, restarting ===" >> "$WORK/server$1.log"
      sleep 1
    done ) > /dev/null 2>&1 &
}
: > "$WORK/server1.log"; : > "$WORK/server2.log"
pings=""; [ -z "$TCP" ] || pings="${IRC_PING:-3} ${IRC_TIMEOUT:-60}"   # PING every 3 s, drop after 60 s of silence (wall clock)
[ -z "$CHAT" ] || { ( python -u "$HERE/irc_fixture_server.py" $IRC_PORT $pings > "$WORK/irc.log" 2>&1 ) & }
start 1 $SPORT1 $UDP1 $UDP2
start 2 $SPORT2 $UDP2 $UDP1
sleep 15
mkdir -p "$WORK/np"; rm -f "$WORK"/np/*
node() {  # role port ext
  hw="-ext $3"; hd="set mute on"; boot=
  cmd=
  if [ -n "$TCP" ] && { [ $1 = P2 ] || [ -n "$BOTH" ]; }; then
    ext=$([ $1 = P2 ] && echo "${EXT2:-ram2mb}" || echo "${EXT1:-ram2mb}")
    hw="-ext MegaFlashROM_SCC+_SD -ext slotexpander -ext $ext"; hd="hdb {$WORKW/nextor_$1.dsk}"; boot=nextor
    if [ -n "$HYBRID" ]; then cmd="PLAYNET /T /H $PNOPTS pwars2 $1"       # link 2: the game's packets through the node's MSXPi
    elif [ $1 = P2 ]; then cmd="PLAYNET /T $PNOPTS pwars2 P2 $UDP2 10.0.2.2:$UDP1"
    else cmd="PLAYNET /T $PNOPTS pwars2 P1 $UDP1 10.0.2.2:$UDP2"; fi
  fi
  CMD="$cmd" EXITKEY=$EXITKEY CHAT=$CHAT PLAY_AT=${PLAY_AT:-60} ACCEPT_AT=${ACCEPT_AT:-75} BOOT=$boot PLAYNET_SYMS="$WORKW/stub_syms.tcl" STUB_BIN="$(cd "$PKG" && pwd -W 2>/dev/null || echo "$PKG")/assets/stub.bin" \
  ROLEARG=$1 TRACE=$WORKW/np/$1.trace STOPF=$STOPF SEED=${SEED:-0} MSXPI_HARNESS_OUT=$WORKW/np/$1.result \
  timeout ${NODETMO:-1800} "$OMX" -machine Canon_V-25 $hw -ext MSXPi -command "$hd" \
    -command "set msxpiserver_port $2" -command "set msxpirom_bank BANK2" \
    -command "set msxpirom_sltsl ON" -command "reset" -command "set renderer ${RENDERER:-none}" -command "set mute on" \
    -script "$HARNESS" -script "$RW/software/Client/tests/soccernet/pwars2_node.tcl" ${EXTRA_TCL:+-script "$EXTRA_TCL"} > "$WORK/np/$1.log" 2>&1
}
node P1 $SPORT1 ram2mb &
NPIDS=$!
if [ -z "$ONLY" ]; then sleep 5; node P2 $SPORT2 ${EXT2:-ram2mb} & NPIDS="$NPIDS $!"; fi
wait $NPIDS
CMP_DROP_LAST=${TCP:+1} python "$HERE/cmp_pair.py" "$WORK/np/P1.trace" "$WORK/np/P2.trace"
grep -h "^#" "$WORK/np/P1.trace" "$WORK/np/P2.trace"
grep -h "netplay: [a-z]" "$WORK/server1.log" "$WORK/server2.log" | grep -v "{" | tail -8
if [ -n "$EXITKEY" ] && [ -n "$CHAT" ] && [ -n "$TCP" ]; then   # MCHAT /T quits IRC before the game and connects again after it
  for nick in alice bob; do
    if awk -v n="$nick" '$2 == n && /:MSXG1 (GO|ACCEPT) / { g = 1 } g && $2 == n && / QUIT / { q = 1 } END { exit !q }' "$WORK/irc.log"
    then echo "$nick: sent QUIT after the launch"; else echo "$nick: NO QUIT after the launch"; fi
    c=$(awk -v n="$nick" '$2 == n && /:MSXG1 (GO|ACCEPT) / { c = $1 } END { print c }' "$WORK/irc.log")
    if awk -v n="$nick" -v c="$c" '$2 == n && $1 > c && / JOIN #/ { ok = 1 } END { exit !ok }' "$WORK/irc.log"
    then echo "$nick: back in MCHAT /T on a new IRC connection"; else echo "$nick: NOT back in MCHAT /T"; fi
  done
  grep -c "^conn" "$WORK/irc.log" | sed 's/^/IRC connections opened: /'
elif [ -n "$EXITKEY" ] && [ -n "$CHAT" ]; then  # both back in MCHAT: restore, then "mchat start"
  for n in 1 2; do
    if awk '/-> playnet restore/ { r = 1 } r && /-> mchat start/ { ok = 1 } END { exit !ok }' "$WORK/server$n.log"
    then echo "server $n: back in MCHAT after the game"; else echo "server $n: NOT back in MCHAT"; fi
  done
  grep -h "playnet result" "$WORK/server1.log" "$WORK/server2.log"
fi
touch "$WORK/stop_servers"
for port in $SPORT1 $SPORT2 $IRC_PORT; do
  pid=$(netstat -ano | grep -E ":$port .*LISTENING" | awk '{print $5}' | head -1)
  if [ -n "$pid" ]; then taskkill //F //PID $pid > /dev/null 2>&1; fi
done
