#!/usr/bin/env bash
# MSXPi Interface
# Version 1.7.0
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

# Linux equivalent of make.bat. Build a client without deploying disk images.
# Needs SDCC 4.6.0 (the distro's 4.2 is refused): put it on PATH or set SDCC_BIN=<its bin directory>.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
[[ -z "${SDCC_BIN:-}" ]] || PATH="$SDCC_BIN:$PATH"
python3 "$here/asm-common/transport/generate.py" --check
prog="${1:?Usage: make.sh program [output-directory]}"
[[ "$prog" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid program name" >&2; exit 1; }
out="${2:-$here/target}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
fusion="${FUSION_C:-$here/../../../MSX/MSX-C/WorkingFolder/fusion-c}"
fusion="$(cd "$fusion" && pwd)"
for tool in sdcc sdar sdasz80 objcopy; do command -v "$tool" >/dev/null || { echo "$tool not found" >&2; exit 1; }; done
sdcc --version | grep -q ' 4\.6\.0 ' || { echo "SDCC 4.6.0 is required (set SDCC_BIN)" >&2; exit 1; }
scratch="$(mktemp -d "$out/.${prog}-build.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

python3 "$here/tools/build_fusion46.py" "$scratch" --fusion-c "$fusion"
sdcc -mz80 -c "$here/C-common/lib/msxpi-bios.c" -o "$scratch/msxpi-bios.rel"
sdar -rc "$scratch/msxpi-bios.lib" "$scratch/msxpi-bios.rel"
sdcc -mz80 --code-loc 0x106 --data-loc 0x0     --disable-warning 196 --no-std-crt0 --opt-code-size     fusion46.lib msxpi-bios.lib -L "$scratch"     "$fusion/include/crt0_msxdos.rel" "$here/Client/src/$prog.c"     -o "$scratch/$prog.ihx" 2>&1 | tee "$scratch/link.log"
# Permanent link guards, as in make.bat.
if grep -q 'Conflicting sdcc options' "$scratch/link.log"; then
    echo "ERROR: $prog mixes calling conventions (linker: Conflicting sdcc options)." >&2
    exit 1
fi
if grep -q 'Undefined Global' "$scratch/link.log"; then
    echo "ERROR: $prog has undefined symbols (linker: Undefined Global)." >&2
    exit 1
fi
objcopy -I ihex -O binary --gap-fill 0xff "$scratch/$prog.ihx" "$scratch/$prog.com"
cp "$scratch/$prog.com" "$out/$prog.com"
echo "Built $out/$prog.com"
