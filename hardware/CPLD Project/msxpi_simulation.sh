ghdl -a MSXInterface.vhd
ghdl -a MSXInterface_tb.vhd
ghdl -e MSXInterface_tb
./MSXInterface_tb --stop-time=200ps --vcd=MSXInterface.vcd

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/MacGPG2/bin:/Users/ronivon/Dev/SDCC/bin:/Users/ronivon/Dev/Z80/pasmo-0.5.4.beta2:/Users/ronivon/Desktop/nand2tetris/tools:/Applications/gtkwave.app/Contents/Resources/bin

gtkwave MSXInterface.vcd
