onerror {quit -f}
vlib work
vlog -work work MSXPI.vo
vlog -work work MSXPi.vt
vsim -novopt -c -t 1ps -L max3000a_ver -L altera_ver -L altera_mf_ver -L 220model_ver -L sgate work.MSXPi_vlg_vec_tst
vcd file -direction MSXPi.msim.vcd
vcd add -internal MSXPi_vlg_vec_tst/*
vcd add -internal MSXPi_vlg_vec_tst/i1/*
add wave /*
run -all
