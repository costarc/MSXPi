#!/usr/bin/env bash
# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

# =============================================================================
# Build the Nextor hard-disk image used by the HW=nextor profile.
# =============================================================================
#   ./mknextorhd.sh            rebuild from the default source folder
#   SRC=... OUT=... ./mknextorhd.sh
#
# The DOS2 test setup is a Canon V-25 with the MegaFlashROM SCC+SD in slot 1
# and MSXPi in slot 2, booting Nextor.  openMSX cannot mount a host FOLDER as a
# hard disk - that only works for floppy drives - so the folder has to be baked
# into an image, and re-baked whenever the tools in it change.  This is that
# step.
#
# Everything here was arrived at empirically; the traps, in order:
#
#  - The Windows openMSX in this tree does not know `hda`/`hdb` in
#    diskmanipulator at all ("Unknown drive"), so the image MUST be built with
#    the newer build in WSL.  Attaching it at boot works in either.
#  - `create <img> -nextor 64M` is rejected silently by this build: its usage
#    is `create <fn> <sz> [<sz> ...]` and there is no -nextor flag.  It
#    reported success and produced an image with no partition table.
#  - A single size produces an UNPARTITIONED image, and `hdb1` then fails with
#    "No (or invalid) partition table".  Two sizes are what creates the
#    partition table.
#  - The content goes in partition TWO.  Nextor maps this card's second
#    partition to drive B:, and partition one to nothing visible - importing
#    into hdb1 gives a B: that is present, empty and 32744K free, which looks
#    like the import silently failed.
#  - `diskmanipulator import` re-splits its arguments on spaces regardless of
#    Tcl quoting, so a source path containing a space ("Boot Nextor") arrives
#    truncated.  Hence the space-free symlink.
# =============================================================================
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-/mnt/c/Users/roniv/Dev/MSX/Boot Nextor}"
OUT="${OUT:-/mnt/c/Users/roniv/Dev/MSX/NextorHD.dsk}"
DISTRO="${DISTRO:-Ubuntu-24.04}"
OPENMSX="${OPENMSX_WSL:-/opt/openMSX/bin/openmsx}"

# Written where both sides can see it, since the script runs under WSL but the
# report is read from Windows.
LOG_WIN="$HERE/out/mknextorhd.log"
LOG_WSL="$(printf '%s' "$HERE/out/mknextorhd.log" \
    | sed -E 's#^([A-Za-z]):#/mnt/\L\1#' | sed -E 's#^/([A-Za-z])/#/mnt/\1/#')"
TCL_WIN="$HERE/out/mknextorhd.tcl"
TCL_WSL="${LOG_WSL%.log}.tcl"

mkdir -p "$HERE/out"

cat > "$TCL_WIN" <<TCLEOF
set f [open "$LOG_WSL" w]
proc note {f m} { puts \$f \$m; flush \$f }
set img "$OUT"
file delete \$img
if {[catch {diskmanipulator create \$img 32M 32M} e]} { note \$f "CREATE-FAIL: \$e"; close \$f; exit 1 }
note \$f "created \$img"
if {[catch {hdb \$img} e]} { note \$f "ATTACH-FAIL: \$e"; close \$f; exit 1 }
if {[catch {diskmanipulator import hdb2 /tmp/bootnextor} e]} { note \$f "IMPORT-FAIL: \$e"; close \$f; exit 1 }
note \$f "imported"
catch {diskmanipulator dir hdb2} listing
note \$f "--- hdb2 ---"
note \$f \$listing
close \$f
after time 2 exit
TCLEOF

rm -f "$LOG_WIN"
wsl.exe -d "$DISTRO" -- bash -c \
  "rm -f /tmp/bootnextor && ln -s '$SRC' /tmp/bootnextor && \
   timeout 180 '$OPENMSX' -machine Canon_V-25 -ext 'MegaFlashROM_SCC+_SD' \
     -ext MSXPi -command 'set renderer none' -script '$TCL_WSL'" >/dev/null 2>&1 || true

if ! grep -q "^imported" "$LOG_WIN" 2>/dev/null; then
    echo "!! Nextor HD build FAILED - see $LOG_WIN"
    cat "$LOG_WIN" 2>/dev/null
    exit 1
fi
sed -n '1,6p' "$LOG_WIN"
echo "ok - $(grep -c '^' "$LOG_WIN") lines in $(basename "$LOG_WIN")"
