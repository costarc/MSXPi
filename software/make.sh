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

# Linux equivalent of make.bat. Build a client without deploying disk images.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
python3 "$here/asm-common/transport/generate.py" --check
prog="${1:?Usage: make.sh program [output-directory]}"
[[ "$prog" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid program name" >&2; exit 1; }
# Programs already ported to SDCC 4.6's own calling convention (sdcccall 1); keep in step with
# ABI1_PROGRAMS in make.bat. Any other program still mixes conventions and the link guard below
# refuses it unless SDCC_ALLOW_ABI_MIX=1 (only for software/tools/abi_bytecmp.py).
ABI1_PROGRAMS="templatc mchat"
abi1=0
for p in $ABI1_PROGRAMS; do [[ "$p" == "$prog" ]] && abi1=1; done
out="${2:-$here/target}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
fusion="${FUSION_C:-$here/../../../MSX/MSX-C/WorkingFolder/fusion-c}"
fusion="$(cd "$fusion" && pwd)"
# The distro's SDCC 4.2 standard library uses ABI 1 even with --sdcccall 0.
# Use the ABI-0 runtime shipped with the existing Windows SDCC 4.0 toolchain.
legacy="${SDCC_ABI0_LIB:-/mnt/c/Apps/SDCC/lib/z80/z80.lib}"
[[ -f "$legacy" ]] || { echo "Set SDCC_ABI0_LIB to an SDCC ABI-0 z80.lib" >&2; exit 1; }
for tool in sdcc sdar objcopy; do command -v "$tool" >/dev/null; done
sdcc --version | grep -q ' 4\.6\.0 ' || { echo "SDCC 4.6.0 is required" >&2; exit 1; }
scratch="$(mktemp -d "$out/.${prog}-build.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

if [[ $abi1 == 1 ]]; then
    abiflags=()
    stdlib=()
    fusionlib=()
else
    # Fusion-C's prebuilt library and the BIOS's naked routines take stack
    # arguments. SDCC 4.2+ defaults to register arguments, so select ABI 0.
    abiflags=(--sdcccall 0)
    stdlib=(--nostdlib "$legacy")
    fusionlib=(fusion.lib)
fi
sdcc -mz80 "${abiflags[@]}" -c "$here/C-common/lib/msxpi-bios.c" \
    -o "$scratch/msxpi-bios.rel"
sdar -rc "$scratch/msxpi-bios.lib" "$scratch/msxpi-bios.rel"
# PChess is near the MSX-DOS memory limit: make.bat gives it the larger register
# allocation search (about 2.4 KB smaller, a build of about 3 minutes).
optx=()
[[ "$prog" == pchess ]] && optx=(--max-allocs-per-node 100000)
sdcc -mz80 "${abiflags[@]}" --code-loc 0x106 --data-loc 0x0 \
    --disable-warning 196 --no-std-crt0 --opt-code-size "${optx[@]}" \
    "${fusionlib[@]}" msxpi-bios.lib "${stdlib[@]}" -L "$fusion/lib" -L "$scratch" \
    "$fusion/include/crt0_msxdos.rel" "$here/Client/src/$prog.c" \
    -o "$scratch/$prog.ihx" 2>&1 | tee "$scratch/link.log"
if grep -q 'Conflicting sdcc options' "$scratch/link.log" && [[ -z "${SDCC_ALLOW_ABI_MIX:-}" ]]; then
    echo "ERROR: $prog mixes calling conventions (linker: Conflicting sdcc options)." >&2
    echo "       Port it to sdcccall 1 and add it to ABI1_PROGRAMS, or set SDCC_ALLOW_ABI_MIX=1." >&2
    exit 1
fi
if grep -q 'Undefined Global' "$scratch/link.log"; then
    echo "ERROR: $prog has undefined symbols (linker: Undefined Global)." >&2
    exit 1
fi
objcopy -I ihex -O binary --gap-fill 0xff "$scratch/$prog.ihx" "$scratch/$prog.com"
cp "$scratch/$prog.com" "$out/$prog.com"
echo "Built $out/$prog.com"
