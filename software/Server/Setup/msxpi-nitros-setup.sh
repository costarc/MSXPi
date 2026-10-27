#!/bin/sh
# msxpi-nitros-setup.sh - install XRoar and ToolShed (os9), which NitrOS-9 needs on the Pi.
#
# Raspberry Pi OS 13 (trixie) has neither package, so when apt cannot supply them they
# are built from the upstream sources into /usr/local. Run once, on the Pi:
#     sh ~/msxpi/msxpi-nitros-setup.sh
# The CoCo ROMs (bas13.rom, extbas11.rom, disk11.rom) are not included and cannot be
# shipped: put them in the -rompath folder of ~/msxpi/nitros/nitros.json.
#
# Versions are the ones this port was tested with (documents/NITROS-build.md).
XROAR_VERSION=1.12.1
TOOLSHED_VERSION=2.6.1

set -u
as_root() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }
apt_try() {
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" >/dev/null 2>&1
}
fail() { echo "FAIL $*" >&2; exit 1; }

have apt-get || fail "this script needs a Debian-based system"
as_root apt-get update -qq >/dev/null 2>&1

if ! have xroar; then
    apt_try xroar && echo "ok   xroar (apt)"
fi
if ! have os9; then
    apt_try toolshed && echo "ok   toolshed (apt)"
fi

WORK="$(mktemp -d)" || fail "no temporary folder"
trap 'rm -rf "$WORK"' EXIT

if ! have os9; then
    echo "building ToolShed $TOOLSHED_VERSION ..."
    apt_try build-essential wget ca-certificates || fail "build tools"
    ( cd "$WORK" &&
      wget -q -O toolshed.tgz "https://github.com/nitros9project/toolshed/archive/refs/tags/v$TOOLSHED_VERSION.tar.gz" &&
      tar xzf toolshed.tgz &&
      cd "toolshed-$TOOLSHED_VERSION" &&
      make -C build/unix >"$WORK/toolshed.log" 2>&1 &&
      as_root install -m 755 build/unix/os9/os9 build/unix/decb/decb /usr/local/bin >>"$WORK/toolshed.log" 2>&1
    ) || { tail -20 "$WORK/toolshed.log" 2>/dev/null; fail "ToolShed build"; }
    have os9 || fail "ToolShed built, but os9 is not on PATH (look in /usr/local/bin, /usr/bin)"
    echo "ok   toolshed (built)"
fi

if ! have xroar; then
    echo "building XRoar $XROAR_VERSION (a few minutes on a Pi) ..."
    apt_try build-essential wget ca-certificates libsdl2-dev || fail "build tools"
    ( cd "$WORK" &&
      wget -q -O xroar.tgz "https://www.6809.org.uk/xroar/dl/xroar-$XROAR_VERSION.tar.gz" &&
      tar xzf xroar.tgz &&
      cd "xroar-$XROAR_VERSION" &&
      ./configure >"$WORK/xroar.log" 2>&1 &&
      make -j"$(nproc)" >>"$WORK/xroar.log" 2>&1 &&
      as_root make install >>"$WORK/xroar.log" 2>&1
    ) || { tail -20 "$WORK/xroar.log" 2>/dev/null; fail "XRoar build"; }
    have xroar || fail "XRoar built, but xroar is not on PATH"
    echo "ok   xroar (built)"
fi

echo "xroar: $(command -v xroar)    os9: $(command -v os9)"
echo "Done. Next: the CoCo ROMs in the -rompath folder of ~/msxpi/nitros/nitros.json."
