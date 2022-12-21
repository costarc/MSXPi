onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /msxpi/d
add wave -noupdate /msxpi/a
add wave -noupdate /msxpi/iorq_n
add wave -noupdate /msxpi/rd_n
add wave -noupdate /msxpi/wr_n
add wave -noupdate /msxpi/busdir_n
add wave -noupdate /msxpi/wait_n
add wave -noupdate /msxpi/spi_cs
add wave -noupdate /msxpi/spi_sclk
add wave -noupdate /msxpi/spi_mosi
add wave -noupdate /msxpi/spi_miso
add wave -noupdate /msxpi/spi_rdy
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {305 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {1 us}
view wave 
wave clipboard store
wave create -pattern none -portmode inout -language vhdl -range 7 0 /msxpi/D 
wave create -pattern none -portmode in -language vhdl -range 7 0 /msxpi/A 
wave create -pattern none -portmode in -language vhdl /msxpi/IORQ_n 
wave create -pattern none -portmode in -language vhdl /msxpi/RD_n 
wave create -pattern none -portmode in -language vhdl /msxpi/WR_n 
wave create -pattern none -portmode out -language vhdl /msxpi/BUSDIR_n 
wave create -pattern none -portmode out -language vhdl /msxpi/WAIT_n 
wave create -pattern none -portmode out -language vhdl /msxpi/SPI_CS 
wave create -pattern none -portmode in -language vhdl /msxpi/SPI_SCLK 
wave create -pattern none -portmode out -language vhdl /msxpi/SPI_MOSI 
wave create -pattern none -portmode in -language vhdl /msxpi/SPI_MISO 
wave create -pattern none -portmode in -language vhdl /msxpi/SPI_RDY 
wave modify -driver freeze -pattern constant -value 0 -starttime 0ns -endtime 1000ns NewSig:/msxpi/iorq_n 
wave modify -driver freeze -pattern constant -value 0 -starttime 0ns -endtime 1000ns NewSig:/msxpi/rd_n 
wave modify -driver freeze -pattern constant -value 0 -starttime 0ns -endtime 1000ns NewSig:/msxpi/wr_n 
wave modify -driver expectedOutput -pattern constant -value Z -starttime 0ns -endtime 1000ns NewSig:/msxpi/wait_n 
wave modify -driver expectedOutput -pattern constant -value 1 -starttime 0ns -endtime 1000ns NewSig:/msxpi/spi_cs 
wave modify -driver freeze -pattern clock -initialvalue 0 -period 100ns -dutycycle 50 -starttime 0ns -endtime 1000ns NewSig:/msxpi/spi_sclk 
wave modify -driver expectedOutput -pattern clock -initialvalue 0 -period 100ns -dutycycle 50 -starttime 100ns -endtime 1000ns NewSig:/msxpi/spi_mosi 
wave modify -driver freeze -pattern constant -value 0 -starttime 100ns -endtime 1000ns NewSig:/msxpi/spi_miso 
wave modify -driver freeze -pattern constant -value 0 -starttime 50ns -endtime 1000ns NewSig:/msxpi/spi_rdy 
{wave export -file {C:/Users/alpha/Documents/Dev/MSXPi/hardware/CPLD Project/simulation/modelsim/msxpi_tb} -starttime 0 -endtime 1000 -format vhdl -designunit msxpi} 
WaveCollapseAll -1
wave clipboard restore
