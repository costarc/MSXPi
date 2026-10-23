# Who writes D000h-D7FFh (stub + transport) and the mapper ports, and is the stub intact when INIT reaches clrRam?
# EXTRA_TCL for run_salamander.sh. Output: $DBGOUT/ww_<role>.txt (DBGOUT defaults to the trace folder).
if {[info exists ::env(DBGOUT)]} { set wwDir $::env(DBGOUT) } else { set wwDir [file dirname $::env(TRACE)] }
set ::wwo [open "$wwDir/ww_$::env(ROLEARG).txt" w]
set ::wwAgg [dict create]
set ::wwN 0
set ::wwDone 0
set ::wwPorts 0
proc wwSeg {} { return [format "%02X%02X%02X%02X A8=%02X" [debug read ioports 0xFC] [debug read ioports 0xFD] [debug read ioports 0xFE] [debug read ioports 0xFF] [debug read ioports 0xA8]] }
proc wwMem {} {
    set pc [reg PC]; set a $::wp_last_address; set v $::wp_last_value
    if {!$::started} {
        if {[dict exists $::wwAgg $pc]} {
            lassign [dict get $::wwAgg $pc] n lo hi
            if {$a < $lo} { set lo $a }; if {$a > $hi} { set hi $a }
            dict set ::wwAgg $pc [list [incr n] $lo $hi]
        } else { dict set ::wwAgg $pc [list 1 $a $a] }
        return
    }
    if {$::wwDone || [incr ::wwN] > 4000} return
    puts $::wwo [format "W t=%.5f PC=%04X a=%04X v=%02X SP=%04X iff=%s seg=%s" [machine_info time] $pc $a $v [reg SP] [reg iff] [wwSeg]]
}
proc wwPort {} {
    if {!$::started} {
        set k [format "port%02X@%04X" $::wp_last_address [reg PC]]
        if {[dict exists $::wwAgg $k]} { dict set ::wwAgg $k [list [expr {[lindex [dict get $::wwAgg $k] 0] + 1}] 0 $::wp_last_value] } else { dict set ::wwAgg $k [list 1 0 $::wp_last_value] }
        return
    }
    if {$::wwDone || [incr ::wwPorts] > 6000} return
    puts $::wwo [format "P t=%.5f PC=%04X port=%02X v=%02X SP=%04X iff=%s st=%d" [machine_info time] [reg PC] $::wp_last_address $::wp_last_value [reg SP] [reg iff] $::started]
}
proc wwAggDump {} {
    puts $::wwo "-- writes to D000-D7FF before the stub was seen in place (PC count lo hi):"
    dict for {pc v} $::wwAgg {
        lassign $v n lo hi
        if {[string is integer $pc]} { puts $::wwo [format "  %04X %6d %04X %04X" $pc $n $lo $hi] } else { puts $::wwo [format "  %s %6d last=%02X" $pc $n $hi] }
    }
    set ::wwAgg [dict create]
    flush $::wwo
}
proc wwClr {} {
    if {$::wwDone || [peek 0xD000] != 1 || [peek $::sym(MK_BLOCK)] != 1} return
    set ::wwDone 1
    wwAggDump
    set f [open $::env(STUB_BIN) rb]; set img [read $f]; close $f
    binary scan $img cu* bytes
    set diff {}
    for {set a 0xD355} {$a < 0xD000 + [llength $bytes]} {incr a} {
        set want [lindex $bytes [expr {$a - 0xD000}]]
        if {[peek $a] != $want} { lappend diff [format "%04X:%02X/%02X" $a [peek $a] $want] }
    }
    puts $::wwo [format "clrRam t=%.5f PC=%04X SP=%04X iff=%s seg=%s diffs(have/want, D355-end)=%d" [machine_info time] [reg PC] [reg SP] [reg iff] [wwSeg] [llength $diff]]
    puts $::wwo [lrange $diff 0 80]
    flush $::wwo
}
proc wwArmAgg {} {
    if {$::started} { wwAggDump; return }
    after time 0.2 wwArmAgg
}
debug set_watchpoint write_mem {0xD000 0xD7FF} {} wwMem
debug set_watchpoint write_io {0xFC 0xFF} {} wwPort
debug set_bp $::sym(clrRam) {} wwClr
after time 1 wwArmAgg
after time 100 { flush $::wwo }
