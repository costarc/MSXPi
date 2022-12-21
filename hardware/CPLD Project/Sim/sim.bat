rem PATH=C:\Users\alpha\Documents\Dev\ghdl\bin;%PATH%
ghdl -a ..\msxpi.vhd
ghdl -a msxpi_tb.vhd
ghdl -e msxpi_tb

.\msxpi_tb --stop-time=200ps --vcd=msxpi_tb.vcd

