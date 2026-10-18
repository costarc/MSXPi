#!/bin/sh
# Build the Konami's Soccer netplay loader (SOCCERNET) and its resident stub (MSXPi-native transport).
#
#   build/prod/SOCCERNET.COM  real joystick input         (the program players run; not yet tested)
#   build/test/SOCCERNET.COM  scripted input, for the openMSX test rigs, + stub_syms_nat.tcl
#
# Needs sjasmplus (SJASMPLUS=/path/to/sjasmplus) and Python 3. Generated stub files stay under build/
# (and stub.asm here) and are not committed. SOCCER.ROM is never part of the repository.
cd "$(dirname "$0")" || exit 1
ASM=${SJASMPLUS:-sjasmplus}
python gen_stub.py || exit 1
for flavour in prod test; do
  d=build/$flavour
  mkdir -p $d
  if [ $flavour = test ]; then defs="-DNATIVE -DSCRIPTED"; else defs="-DNATIVE"; fi
  $ASM $defs --raw=$d/stub_nat.bin --sym=$d/stub_nat.sym stub.asm || exit 1
  python gen_inc.py $d/stub_nat.sym $d/stub_nat.inc $d/stub_syms_nat.tcl || exit 1
  $ASM --inc=$d --raw=$d/SOCCERNET.COM soccernet.asm || exit 1
done
