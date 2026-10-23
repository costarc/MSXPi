# The way back to MSX-DOS after the game (EXTRA_TCL, with EXITKEY): the TPA top and PLAYNET's saved area at the
# start of the game (saveDos's result), then from pnBack's jp 0 (MSX-DOS's warm start) the first 300 writes to the
# MSXPi ports 56h/5Ah with their PC, and the PC every 2 ms for 2 s. Needs PNSYM (build/playnet.sym of PLAYNET.COM).
# Output: <trace>.back
set ::bko [open "$::env(TRACE).back" w]
set ::pns {}
set f [open $::env(PNSYM)]; foreach l [split [read $f] \n] { if {[regexp {^([\w.]+): EQU 0x([0-9A-F]+)} $l -> n a]} { set ::pn($n) [expr 0x$a] } }; close $f
set ::bkN 0
proc bkW {} {
    if {[incr ::bkN] > 300} return
    puts $::bko [format "out %02X=%02X PC=%04X SP=%04X t=%.4f" $::wp_last_address $::wp_last_value [reg PC] [reg SP] [machine_info time]]
}
set ::bkS 0
proc bkSamp {} {
    if {[incr ::bkS] > 1000} { flush $::bko; return }
    puts $::bko [format "pc %04X SP=%04X" [reg PC] [reg SP]]
    after time 0.002 bkSamp
}
proc bkDos {} {
    puts $::bko [format "jp 0 at t=%.4f: TPA top %04X svStart %04X svLen %04X" [machine_info time] \
        [expr {[peek 6] + 256 * [peek 7]}] [expr {[peek $::pn(svStart)] + 256 * [peek [expr {$::pn(svStart) + 1}]]}] \
        [expr {[peek $::pn(svLen)] + 256 * [peek [expr {$::pn(svLen) + 1}]]}]]
    debug set_watchpoint write_io {0x56 0x5A} {} bkW
    bkSamp
}
proc bkSave {} {
    puts $::bko [format "saveDos at t=%.4f: TPA top %04X HIMEM %04X" [machine_info time] [expr {[peek 6] + 256 * [peek 7]}] \
        [expr {[peek 0xFC4A] + 256 * [peek 0xFC4B]}]]
    flush $::bko
}
# gated on PLAYNET.COM being the program at 0100h (its first bytes)
set f [open $::env(PNCOM) rb]; set ::pnHead [read $f 8]; close $f
proc bkIsPn {} { expr {[debug read_block memory 0x100 8] eq $::pnHead} }
debug set_bp $::pn(saveDos) {[bkIsPn]} bkSave
debug set_bp $::pn(pnBack.dos) {[bkIsPn]} bkDos
