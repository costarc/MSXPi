ghdl -a msxpi.vhd
ghdl -a msxpi_tb.vhd
ghdl -e msxpi_tb
./msxpi_tb --stop-time=200ps --vcd=msxpi_tb.vcd

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/MacGPG2/bin:/Users/ronivon/Dev/SDCC/bin:/Users/ronivon/Dev/Z80/pasmo-0.5.4.beta2:/Users/ronivon/Desktop/nand2tetris/tools:/Applications/gtkwave.app/Contents/Resources/bin

gtkwave msxpi_tb.vcd
