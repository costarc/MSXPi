#!/bin/sh
# Differential simulation: v1.6 (MSXPi.vhd) against the v1.3 reference
# (MSXPi_v13_reference.vhd), driven by a model of msxpi-server.py's
# SPI_ByteTransfer().  Phase 1 asserts that legacy mode is cycle-identical to
# v1.3; phases 2-6 cover the /WAIT path, the reset, and the failure modes.
#
#   ./sim.sh          run and report
#   ./sim.sh --wave   also write tb_MSXPi.vcd and open gtkwave
set -e

# v1.6 is the top-level entity "MSXPi"; the testbench needs it under a distinct
# name so both revisions can be elaborated side by side.
sed -e 's/^entity MSXPi is/entity MSXPi_v16 is/' \
    -e 's/^end MSXPi;/end MSXPi_v16;/' \
    -e 's/^architecture rtl of MSXPi is/architecture rtl of MSXPi_v16 is/' \
    MSXPi.vhd > MSXPi_v16.gen.vhd

ghdl -a --std=08 MSXPi_package.vhd
ghdl -a --std=08 MSXPi_v13_reference.vhd
ghdl -a --std=08 MSXPi_v16.gen.vhd
ghdl -a --std=08 tb_MSXPi.vhd
ghdl -e --std=08 tb_MSXPi

if [ "$1" = "--wave" ]; then
    ghdl -r --std=08 tb_MSXPi --vcd=tb_MSXPi.vcd --stop-time=20ms
    gtkwave tb_MSXPi.vcd
else
    ghdl -r --std=08 tb_MSXPi --stop-time=20ms
fi
