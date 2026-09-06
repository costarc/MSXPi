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
# The disk image that gets these files is the one in the repo, target/disks -
# that is the artifact people copy to the Pi.  ../../build regenerates it from
# target/ and then installs it to the served location; anything added only to
# the served copy is invisible to everyone else and is lost on the next build,
# which is exactly what used to happen to every tool below.
#
# SERVED is where msxpi-server.py reads from.  It resolves its Linux-style
# default paths against the current drive on Windows, so /home/pi/msxpi/...
# really is C:\home\pi\msxpi\...
DISK="${DISK:-$HERE/../target/disks/msxpiboot.dsk}"
SERVED="${SERVED:-C:/home/pi/msxpi/disks/msxpiboot.dsk}"
DSKTOOL="$HERE/../dsktool.py"

cd "$SRC"

echo "--- assembling resident segment (RAM variant)"
"$SJASM" ethseg.asm ethseg.bin ethseg.lst ethseg.exp

# The ROM variant shares ethtrans/ethops/ethcore with the RAM one and differs
# only in ethrom.asm, so building it here is what stops the two from drifting:
# a change that breaks the ROM build is caught now rather than at the next
# full ../../build.  That build assembles it again, into
# ROM/src/MSX-DOS/ethrom.bin where msxpi-driver.mac INCBINs it; this copy is
# only for the size report below.
echo "--- assembling driver (ROM variant)"
"$SJASM" ethrom.asm ethrom.bin ethrom.lst

echo "--- assembling installer"
"$SJASM" ethunapi.asm ETHUNAPI.COM ethunapi.lst

echo "--- assembling discovery test client"
"$SJASM" ethtest.asm ETHTEST.COM ethtest.lst

echo "--- assembling transport benchmark"
"$SJASM" ethbench.asm ETHBENCH.COM ethbench.lst

echo "--- assembling transport mode tool"
"$SJASM" ethmode.asm ETHMODE.COM ethmode.lst

size_seg=$(wc -c < ethseg.bin)
size_rom=$(wc -c < ethrom.bin)
size_com=$(wc -c < ETHUNAPI.COM)
echo "    ethseg.bin   $size_seg bytes"
echo "    ethrom.bin   $size_rom bytes"
echo "    ETHUNAPI.COM $size_com bytes"

# How much room is left in the ROM.  The build-time ASSERTs in
# msxpi-driver.mac are what actually enforce this; the number is here so the
# margin is visible before it runs out.
# Cut the comment off first: the line carries prose that can itself contain a
# hex literal (it records the previous org), and grep -oE would then yield two
# numbers and turn the arithmetic below into a syntax error.
unapi_org=$(grep '^UNAPI_ORG' "$HERE/../asm-common/include/unapi_wrk.inc" |
            sed 's/;.*//' | grep -oE '0[0-9A-Fa-f]+H' | head -1 | tr -d 'H')
if [ -n "$unapi_org" ]; then
    echo "    ROM space    $(( 0x8000 - 0x$unapi_org - size_rom )) bytes free below 8000h (org ${unapi_org}h)"
fi

if [ "${1:-}" = "--no-copy" ]; then
    exit 0
fi

if [ ! -f "$DISK" ]; then
    echo "!! disk image not found at $DISK - skipping copy"
    exit 0
fi

echo "--- copying to $(basename "$DISK")"
# dsktool.py splits its target on the FIRST ':', which on Windows would eat the
# drive letter of an absolute path.  Run from the image's own directory and
# pass a bare filename so the only colon is the intended separator.
DSK="$(basename "$DISK")"
cd "$(dirname "$DISK")"
python "$DSKTOOL" copy "$SRC/ETHUNAPI.COM" "$DSK:ETHUNAPI.COM"
python "$DSKTOOL" copy "$SRC/ETHTEST.COM"  "$DSK:ETHTEST.COM"
python "$DSKTOOL" copy "$SRC/ETHBENCH.COM" "$DSK:ETHBENCH.COM"
python "$DSKTOOL" copy "$SRC/UCOUNT.COM"   "$DSK:UCOUNT.COM"
python "$DSKTOOL" copy "$SRC/ETHMODE.COM"  "$DSK:ETHMODE.COM"

# Everything in bin/ as well.  These are third-party binaries we do not build -
# Konamiman's RAMHELPR and MSR, InterNestor Lite, the telnet clients - vendored
# so they exist on any machine that has this repo, notably the Pi.  They belong
# here because ../../build regenerates msxpiboot.dsk from target/ and drops
# everything that is not built from this repo; without this loop they have to
# be copied back by hand after every full build, which is easy to forget and
# shows up as "Bad command or file name" in the middle of a test.
for f in "$HERE"/bin/*.COM "$HERE"/bin/*.com; do
    [ -e "$f" ] || continue
    python "$DSKTOOL" copy "$f" "$DSK:$(basename "$f")"
done

# InterNestor Lite reads INL.CFG at install time, from the current drive.  With
# no INL.CFG, `INL I` installs with no IP configuration at all and reports no
# error - telnet then fails much later, looking like a network problem.
# INL.CFG must have CRLF line endings AND a trailing Ctrl-Z; crlf.py applies
# both and explains why in detail.  Either one missing produces the identical
# symptom - "Cannot execute this command from a configuration file" once, then
# INL's banner repeating for ever - which looks exactly like a driver hang and
# has now cost two long detours.  The Ctrl-Z one is MSX-DOS 1 only, so it hides
# completely behind any test that boots DOS 2.
#
# Converted here rather than trusting the file in the repo, because git's
# line-ending handling can rewrite it on checkout.
CFGTMP="$HERE/pi-setup/.INL.CFG.crlf"
python "$HERE/crlf.py" "$HERE/pi-setup/INL.CFG" "$CFGTMP"
python "$DSKTOOL" copy "$CFGTMP" "$DSK:INL.CFG"
rm -f "$CFGTMP"

# Install the finished image where the server reads it, the same way
# ../../build does.  Skipped when DISK was overridden to the served copy
# already, or when there is nowhere to install to.
if [ -n "$SERVED" ] && [ "$SERVED" != "$DISK" ] && [ -d "$(dirname "$SERVED")" ]; then
    cp "$DISK" "$SERVED"
    echo "installed $(basename "$DISK") to $(dirname "$SERVED")"
fi
echo "done"
