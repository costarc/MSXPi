#!/bin/sh
# A copy of the Nextor hard-disk image (UNAPI/harness/mknextorhd.sh) with one more folder, for a test node:
#
#   sh nextor_folder.sh <image> <copy> <folder on the PC> <FOLDER on the disk>
#
# The Windows openMSX cannot write hard-disk images (diskmanipulator does not know hdb), so this runs the openMSX
# in WSL (DISTRO, OPENMSX_WSL), as mknextorhd.sh does. The content goes in partition 2 (Nextor's C:). No spaces
# in the paths: diskmanipulator splits its arguments on them.
set -eu
IMG=$1; OUT=$2; DIR=$3; NAME=$4
DISTRO=${DISTRO:-Ubuntu-24.04}
OPENMSX=${OPENMSX_WSL:-/opt/openMSX/bin/openmsx}
wsl() { printf '%s' "$1" | sed -E 's#^([A-Za-z]):#/mnt/\L\1#; s#^/([A-Za-z])/#/mnt/\L\1/#'; }
cp "$IMG" "$OUT"
LOG="$OUT.log"; TCL="$OUT.tcl"
rm -f "$LOG"
cat > "$TCL" <<EOF
set f [open "$(wsl "$LOG")" w]
if {[catch {hdb "$(wsl "$OUT")"; diskmanipulator mkdir hdb2 $NAME; diskmanipulator chdir hdb2 $NAME
            diskmanipulator import hdb2 "$(wsl "$DIR")"} e]} { puts \$f "FAIL: \$e" } else { puts \$f "imported" }
catch {diskmanipulator dir hdb2} listing
puts \$f \$listing
close \$f
after realtime 1 exit
EOF
MSYS_NO_PATHCONV=1 wsl.exe -d "$DISTRO" -- timeout 120 "$OPENMSX" -machine Canon_V-25 -ext MegaFlashROM_SCC+_SD \
  -command 'set renderer none' -script "$(wsl "$TCL")" > /dev/null 2>&1 || true
grep -q "^imported" "$LOG" 2>/dev/null || { echo "nextor_folder: import failed, see $LOG"; cat "$LOG" 2>/dev/null; exit 1; }
