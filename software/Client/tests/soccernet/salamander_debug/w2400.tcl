# Writes to 2400h-27FFh (the mapper-ram loader) from PLAYNET's banner on: every write to 2400h, 2500h, 27FFh logged,
# the rest counted per PC (every 5 s). EXTRA_TCL. Output: <trace>.w2400.
set ::pwo [open "$::env(TRACE).w2400" w]
set ::pwN 0
array set ::pwPc {}
proc pwW {} {
    set k [format %04X [reg PC]]
    if {![info exists ::pwPc($k)]} {
        set sp [reg SP]
        puts $::pwo [format "new writer PC=%s at %04X t=%.4f SP=%04X stack=%s slots A8=%02X" $k $::wp_last_address [machine_info time] $sp             [join [lmap i {0 2 4 6 8 10 12 14} {format %04X [expr {[peek [expr {$sp + $i}]] + 256 * [peek [expr {$sp + $i + 1}]]}]}] " "] [debug read ioports 0xA8]]
        flush $::pwo
    }
    if {$::wp_last_address != 0x2400 && $::wp_last_address != 0x2500 && $::wp_last_address != 0x27FF} { if {![info exists ::pwPc($k)]} { set ::pwPc($k) 0 }; incr ::pwPc($k); return }
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
        debug set_watchpoint write_mem {0x2400 0x27FF} {} pwW
        return
    }
    after time 0.1 pwWait
}
pwWait
proc pwSum {} { puts $::pwo "counts: [lsort -stride 2 [array get ::pwPc]]"; flush $::pwo; after time 5 pwSum }
after time 58 pwSum
