#!/usr/bin/env bash
# =============================================================================
# Build the MSXPi Ethernet UNAPI driver and install it on the served disk.
# =============================================================================
#   ./build.sh            assemble, then copy ETHUNAPI.COM onto DriveA
#   ./build.sh --no-copy  assemble only
#
# The resident code (ethseg.asm) is assembled separately at 4000h and INCBIN'd
# by the installer: sjasm 0.39j has no phase/disp directive, so code that runs
# at one address cannot be assembled inline at another.  The installer picks up
# the addresses it has to patch from the export file sjasm writes.
#
# NOTE: msxpi-server.py mmaps the disk image and holds it open, so stop the
# server (or let the harness stop it) before copying, or the write is lost.
# =============================================================================
set -eu

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/src"
SJASM="${SJASM:-C:/Users/roniv/Dev/bin/sjasm.exe}"
# The server resolves its Linux-style default paths against the current drive
# on Windows, so /home/pi/msxpi/... really is C:\home\pi\msxpi\...
DISK="${DISK:-C:/home/pi/msxpi/disks/msxpiboot.dsk}"
DSKTOOL="$HERE/../dsktool.py"

cd "$SRC"

echo "--- assembling resident segment"
"$SJASM" ethseg.asm ethseg.bin ethseg.lst ethseg.exp

echo "--- assembling installer"
"$SJASM" ethunapi.asm ETHUNAPI.COM ethunapi.lst

echo "--- assembling discovery test client"
"$SJASM" ethtest.asm ETHTEST.COM ethtest.lst

size_seg=$(wc -c < ethseg.bin)
size_com=$(wc -c < ETHUNAPI.COM)
echo "    ethseg.bin   $size_seg bytes"
echo "    ETHUNAPI.COM $size_com bytes"

if [ "${1:-}" = "--no-copy" ]; then
    exit 0
fi

if [ ! -f "$DISK" ]; then
    echo "!! disk image not found at $DISK - skipping copy"
    exit 0
fi

# The UNAPI RAM helper must be on the disk too: the driver refuses to install
# without it.  This is Konamiman's stock RAMHELPR.COM, not something we build.
RAMHELPR="${RAMHELPR:-C:/Users/roniv/Dev/github/Multicore/Computers/SM-X/sdcreate/network/UNAPI/RAMHELPR.COM}"

echo "--- copying to $(basename "$DISK")"
# dsktool.py splits its target on the FIRST ':', which on Windows would eat the
# drive letter of an absolute path.  Run from the image's own directory and
# pass a bare filename so the only colon is the intended separator.
DSK="$(basename "$DISK")"
cd "$(dirname "$DISK")"
python "$DSKTOOL" copy "$SRC/ETHUNAPI.COM" "$DSK:ETHUNAPI.COM"
python "$DSKTOOL" copy "$SRC/ETHTEST.COM"  "$DSK:ETHTEST.COM"
if [ -f "$RAMHELPR" ]; then
    python "$DSKTOOL" copy "$RAMHELPR" "$DSK:RAMHELPR.COM"
else
    echo "!! RAMHELPR.COM not found at $RAMHELPR - the driver will not install"
fi
echo "done"
