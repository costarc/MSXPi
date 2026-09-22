#!/bin/sh
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
#
# Bring msxpi-server.py up to date TOGETHER with the files it depends on, and
# rebuild the native GPIO engine for this Pi.
#
# Updating the server alone is not enough, and doing only that is exactly how
# a Pi broke: it imports mapper_detect.py, msxpi_eth.py and msxpi_gpio_native.py
# from beside itself, and the native engine is C compiled on the Pi. A new
# server with an old msxpi_gpio_native.py (no read_burst) failed every COPY to
# an MSXPi drive with "Disk error writing".
#
# Run by the MSX updater (msxpirfh.bat: prun sh update.sh) and by
# msxpi-setup.sh. Each file is downloaded to a temporary name and only moved
# into place once it arrived non-empty, so a failed download keeps the old one.
# Short output lines: under prun they are printed on the MSX screen.
#
# MSXPI_UPDATE_BASE overrides where the server files come from, and
# MSXPI_UPDATE_SETUP_BASE where msxpi-tcpip-setup.sh comes from: a URL or a
# directory (testing, and msxpi-setup.sh run from a checkout).

set -u
BASE="${MSXPI_UPDATE_BASE:-https://raw.githubusercontent.com/costarc/MSXPi/master/software/Server/Python/src}"
# Where the helper scripts live. Follows BASE unless told otherwise.
SETUP_BASE="${MSXPI_UPDATE_SETUP_BASE:-${BASE%/Python/src}/Setup}"
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR" || exit 1
mkdir -p native

# get <base> <file>: BASE is a URL, or a directory (msxpi-setup.sh run from a
# checkout). Either way the file is only replaced when the copy is complete.
get() {
    case "$1" in
        http://*|https://*) wget -q -O "$2.new" "$1/$2" ;;
        *)                  cp "$1/$2" "$2.new" ;;
    esac && [ -s "$2.new" ]
}

rc=0
for f in msxpi-server.py mapper_detect.py msxpi_eth.py msxpi_gpio_native.py \
         native/gpio_transfer.c native/build.sh; do
    if get "$BASE" "$f"; then
        mv -f "$f.new" "$f"
        echo "ok   $f"
    else
        rm -f "$f.new"
        echo "FAIL $f (old kept)"
        rc=1
    fi
done
# Run by msxpi-monitor at every start to give the MSX its network. Older setups
# never installed it, so on those it arrives with the first update.
f=msxpi-tcpip-setup.sh
if get "$SETUP_BASE" "$f"; then
    mv -f "$f.new" "$f"
    echo "ok   $f"
else
    rm -f "$f.new"
    echo "FAIL $f (old kept)"
    rc=1
fi
chmod 755 msxpi-server.py msxpi-tcpip-setup.sh 2>/dev/null

# The server works without the native engine (it falls back to Python GPIO),
# so a missing compiler is a warning, not a failure.
if command -v "${CC:-cc}" >/dev/null 2>&1; then
    if bash native/build.sh >/dev/null 2>&1; then
        echo "ok   native GPIO engine built"
    else
        echo "FAIL native build (Python GPIO)"
        rc=1
    fi
else
    echo "skip native build: no C compiler"
fi

# msxpi-setup.sh runs this as root; the server runs as the directory's owner.
if [ "$(id -u)" = 0 ]; then
    owner="$(stat -c %U:%G "$DIR")"
    chown "$owner" msxpi-server.py mapper_detect.py msxpi_eth.py msxpi_gpio_native.py \
        msxpi-tcpip-setup.sh 2>/dev/null
    chown -R "$owner" native 2>/dev/null
fi

exit $rc
