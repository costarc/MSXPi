#!/usr/bin/env bash
# Linux equivalent of make.bat. Build a client without deploying disk images.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
prog="${1:?Usage: make.sh program [output-directory]}"
[[ "$prog" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid program name" >&2; exit 1; }
out="${2:-$here/target}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
fusion="${FUSION_C:-$here/../../../MSX-C/WorkingFolder/fusion-c}"
fusion="$(cd "$fusion" && pwd)"
# The distro's SDCC 4.2 standard library uses ABI 1 even with --sdcccall 0.
# Use the ABI-0 runtime shipped with the existing Windows SDCC 4.0 toolchain.
legacy="${SDCC_ABI0_LIB:-/mnt/c/Apps/SDCC/lib/z80/z80.lib}"
[[ -f "$legacy" ]] || { echo "Set SDCC_ABI0_LIB to an SDCC ABI-0 z80.lib" >&2; exit 1; }
for tool in sdcc sdar objcopy; do command -v "$tool" >/dev/null; done
scratch="$(mktemp -d "$out/.${prog}-build.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Fusion-C's prebuilt library and the BIOS's naked routines take stack
# arguments. SDCC 4.2 defaults to register arguments, so select ABI 0.
sdcc -mz80 --sdcccall 0 -c "$here/C-common/lib/msxpi-bios.c" \
    -o "$scratch/msxpi-bios.rel"
sdar -rc "$scratch/msxpi-bios.lib" "$scratch/msxpi-bios.rel"
sdcc -mz80 --sdcccall 0 --code-loc 0x106 --data-loc 0x0 \
    --disable-warning 196 --no-std-crt0 --opt-code-size \
    fusion.lib msxpi-bios.lib "$legacy" -L "$fusion/lib" -L "$scratch" \
    "$fusion/include/crt0_msxdos.rel" "$here/Client/src/$prog.c" \
    -o "$scratch/$prog.ihx"
objcopy -I ihex -O binary --gap-fill 0xff "$scratch/$prog.ihx" "$scratch/$prog.com"
cp "$scratch/$prog.com" "$out/$prog.com"
echo "Built $out/$prog.com"
