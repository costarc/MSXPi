#!/bin/sh
# Build the Konami's Soccer netplay loader (SOCCERNET) and its resident stub.
#
#   sh build.sh            -> build/SOCCERNET.COM  mailbox transport, scripted input (test rig only)
#                             build/SOCCERNR.COM   same, original R-register coin flips (determinism control)
#                             build/SOCNAT.COM     MSXPi-native transport, scripted input (test rig)
#                             build/stub_syms_nat.tcl   stub symbols for the openMSX test rig
#
# Needs sjasmplus (SJASMPLUS=/path/to/sjasmplus) and Python 3. The generated stub*.{asm,bin,inc,sym}
# files stay in this folder and are not committed. SOCCER.ROM is never part of the repository.
cd "$(dirname "$0")" || exit 1
ASM=${SJASMPLUS:-sjasmplus}
OUT=${OUT:-build}
mkdir -p "$OUT"
python gen_stub.py || exit 1
$ASM -DSCRIPTED --raw=stub.bin --sym=stub.sym stub.asm || exit 1
python gen_inc.py stub.sym stub.inc "$OUT/stub_syms.tcl" || exit 1
$ASM --raw="$OUT/SOCCERNET.COM" soccernet.asm || exit 1
$ASM -DNORNG --raw="$OUT/SOCCERNR.COM" soccernet.asm || exit 1
# MSXPi-native transport
$ASM -DSCRIPTED -DNATIVE --raw=stub_nat.bin --sym=stub_nat.sym stub.asm || exit 1
python gen_inc.py stub_nat.sym stub_nat.inc "$OUT/stub_syms_nat.tcl" || exit 1
$ASM -DNATIVE --raw="$OUT/SOCNAT.COM" soccernet.asm || exit 1
