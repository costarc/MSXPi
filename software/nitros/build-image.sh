#!/usr/bin/env bash
# Build in an expendable, pinned upstream checkout; tools must be on PATH.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
: "${NITROS9DIR:?Set NITROS9DIR to a NitrOS-9 source checkout}"
out="${1:?Usage: build-image.sh NEW-output-directory}"
[[ ! -e "$out" ]] || { echo "Output exists; refusing to overwrite guest disks" >&2; exit 1; }
for tool in lwasm lwlink lwar os9 make python3; do command -v "$tool" >/dev/null; done
mkdir -p "$out"
out="$(cd "$out" && pwd)"
recipe="$NITROS9DIR/recipes/coco/dw"
make -C "$recipe" clean
make -C "$recipe" -f makefile -f "$here/console.mak" \
    SCF='scf scdwv term_scdwv n1_scdwv' AFLAGS_EXTRA=-DBECKER=1 \
    CMDS_BASE='shell_21 dir list copy echo tmode date del makdir attr free' CMDS_EXTRA=
cp "$recipe/l1_coco_dw.dsk" "$out/boot.dsk"
lwasm --format=os9 --pragma=pcaspcr,nosymbolcase,condundefzero \
    -I"$recipe" -I"$NITROS9DIR/defs" -Dcoco1=1 \
    -o"$out/msxexit" "$here/msxexit.asm"
os9 copy "$out/msxexit" "$out/boot.dsk,CMDS/msxexit"
os9 attr -q -e -pe "$out/boot.dsk,CMDS/msxexit"
os9 format -q -t80 -ds -dd "$out/exchange.dsk" -nMSXExchange
mkdir "$out/files"
# XRoar loads this DECB binary at the normal CoCo boot-track address and
# jumps to REL. All subsequent reads/writes go through our DriveWire server.
python3 - "$recipe/kerneltrack" "$out/boot.bin" <<'PY'
import pathlib, struct, sys
kernel = pathlib.Path(sys.argv[1]).read_bytes()
pathlib.Path(sys.argv[2]).write_bytes(struct.pack('>BHH', 0, len(kernel), 0x2600)
                                    + kernel + struct.pack('>BHH', 255, 0, 0x2602))
PY
printf 'Built NitrOS-9 disks in %s\n' "$out"
