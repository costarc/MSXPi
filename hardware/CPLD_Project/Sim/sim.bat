ghdl -a ..\msxpi.vhd
ghdl -a msxpi_tb.vhd
ghdl -e msxpi_tb
ghdl -r msxpi_tb --stop-time=200ns --vcd=msxpi_tb.vcd
gtkwave -a msxpi_tb.gtkw msxpi_tb.vcd