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

set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp "$here/.libmsxpi_gpio.XXXXXX.so")"
trap 'rm -f "$tmp"' EXIT
"${CC:-cc}" -std=c11 -O2 -Wall -Wextra -Werror -fPIC -shared \
    "$here/gpio_transfer.c" -o "$tmp"
# Refuse an old source/library before replacing the installed engine.
if ! "${NM:-nm}" -D --defined-only "$tmp" | awk '
    $3 == "msxpi_gpio_transfer" { ordinary=1 }
    $3 == "msxpi_gpio_burst" { burst=1 }
    END { exit !(ordinary && burst) }
'; then
    echo "Native build is missing required exports. Copy the updated native/gpio_transfer.c and rebuild." >&2
    exit 1
fi
mv -f "$tmp" "$here/libmsxpi_gpio.so"
echo "Built $here/libmsxpi_gpio.so for $(uname -m) (transfer + burst exports verified)"
