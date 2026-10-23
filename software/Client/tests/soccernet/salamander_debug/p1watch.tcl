# Writes to 4000h-43FFh (where PLAYNET /T sets the mapper-ram loader aside while PLAYNET.OVL passes through
# 2400h-3FFFh) from PLAYNET's banner on: PC, SP, the value. EXTRA_TCL. Output: <trace>.p1watch (first 400, not the save's own at PC=1C45; then a count per PC every 5 s).
set ::pwo [open "$::env(TRACE).p1watch" w]
set ::pwN 0
array set ::pwPc {}
proc pwW {} {
    if {[reg PC] == 0x1C45} { return }
    set k [format %04X [reg PC]]
    if {![info exists ::pwPc($k)]} { set ::pwPc($k) 0 }
    incr ::pwPc($k)
    if {[incr ::pwN] > 400} { return }
    puts $::pwo [format "W %04X=%02X PC=%04X SP=%04X t=%.4f" $::wp_last_address $::wp_last_value [reg PC] [reg SP] [machine_info time]]
    flush $::pwo
}
proc pwWait {} {
    if {![catch {set l [harness::screen_lines]}] && [string match "*PLAYNET 3*" [join $l]]} {
        puts $::pwo [format "armed t=%.4f 4000h=%s" [machine_info time] [join [lmap i {0 1 2 3 4 5 6 7} {format %02X [peek [expr {0x4000 + $i}]]}] ""]]
        debug set_watchpoint write_mem {0x4000 0x43FF} {} pwW
        return
    }
    after time 0.1 pwWait
}
pwWait
proc pwSum {} { puts $::pwo "counts: [lsort -stride 2 [array get ::pwPc]]"; flush $::pwo; after time 5 pwSum }
after time 60 pwSum
