transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vcom -93 -work work {C:/Users/alpha/Documents/Dev/MSXPi/hardware/CPLD Project/MSXPi.vhd}

vcom -93 -work work {C:/Users/alpha/Documents/Dev/MSXPi/hardware/CPLD Project/simulation/modelsim/msxpi_tb.vhd}

vsim -t 1ps -L altera -L lpm -L sgate -L altera_mf -L altera_lnsim -L max -L rtl_work -L work -voptargs="+acc"  msxpi_tb

add wave *
view structure
view signals
run -all
