ghdl -a $1_package.vhd
ghdl -a $1.vhd
ghdl -a tb_$1.vhd
ghdl -e tb_$1
ghdl -r tb_$1 --vcd=tb_$1.vcd --stop-time=2us
gtkwave tb_$1.vcd
