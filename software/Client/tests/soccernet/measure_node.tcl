# PLAYNET-DESIGN section 8 measurements on one MSX-DOS machine (run by measure.sh).
# At the prompt, then after each install command in $INSTALL (";"-separated, run from $TOOLS):
#   HIMEM, the TPA top (0006h), the page-3 bytes that changed, H.TIMI and EXTBIO;
# then, with everything installed:
#   8.4  the time spent in H.TIMI per interrupt (what a TCP/IP stack's timer costs the game),
#   8.5  the mapper segments in pages 1-2 at every interrupt while $PROBE runs (a segment other
#        than the TPA's means the interrupt came inside a call into a resident stack).
# Output: $MEASOUT.
set ::out $::env(MEASOUT)
proc say {text} { set f [open $::out a]; puts $f $text; close $f }
proc w16 {a} { return [expr {[peek $a] + 256 * [peek [expr {$a + 1}]]}] }
proc hex5 {a} { set s ""; for {set i 0} {$i < 5} {incr i} { append s [format %02X [peek [expr {$a + $i}]]] }; return $s }
proc snap {} {
    set img {}
    for {set a 0xC000} {$a <= 0xFFFE} {incr a} { lappend img [peek $a] }
    return $img
}
proc state {label} {
    say [format "%-14s HIMEM=%04X H.TIMI=%s H.KEYI=%s EXTBIO=%s A8=%02X" $label \
        [w16 0xFC4A] [hex5 0xFD9F] [hex5 0xFD9A] [hex5 0xFFCA] [debug read ioports 0xA8]]
    # the TPA top (the word at 0006h) is in page 0's RAM: read it at the next BDOS call, when that RAM is mapped
    set ::tpaLabel $label
    set ::tpaBp [debug set_bp 0x0005 {([debug read ioports 0xA8] & 3) == (([debug read ioports 0xA8] >> 6) & 3)} tpaTop]
}
proc tpaTop {} {
    debug remove_bp $::tpaBp
    say [format "%-14s TPA top (0006h) = %04X" $::tpaLabel [w16 0x0006]]
}
proc changed {before after label} {
    # ranges of page 3 that differ, below HIMEM (where a resident stack's code would be)
    set runs {}; set start -1
    for {set i 0} {$i < [llength $before]} {incr i} {
        set d [expr {[lindex $before $i] != [lindex $after $i]}]
        if {$d && $start < 0} { set start $i }
        if {!$d && $start >= 0} { lappend runs [format %04X-%04X [expr {0xC000 + $start}] [expr {0xC000 + $i - 1}]]; set start -1 }
    }
    if {$start >= 0} { lappend runs [format %04X-FFFE [expr {0xC000 + $start}]] }
    say "$label changed: [join $runs { }]"
}

# 8.4: H.TIMI time per interrupt, over 300 interrupts
set ::tN 0; set ::tSum 0.0; set ::tMax 0.0; set ::tIn 0
proc timiIn {} {
    set ::tIn [machine_info time]
    set ret [w16 [reg SP]]
    if {![info exists ::retBp]} { set ::retBp [debug set_bp $ret {} timiOut] }
}
proc timiOut {} {
    if {$::tIn == 0} { return }
    set d [expr {[machine_info time] - $::tIn}]
    set ::tIn 0
    incr ::tN
    set ::tSum [expr {$::tSum + $d}]
    if {$d > $::tMax} { set ::tMax $d }
}
proc timiReport {} {
    if {$::tN} {
        say [format "8.4 H.TIMI: %d interrupts, mean %.1f us, max %.1f us (%.1f%% of a 60 Hz frame)" $::tN \
            [expr {$::tSum / $::tN * 1e6}] [expr {$::tMax * 1e6}] [expr {$::tSum / $::tN * 60 * 100}]]
    } else { say "8.4 H.TIMI: no call seen" }
}

# 8.5: segments in pages 1 and 2 at each interrupt
set ::segs [dict create]
proc irqSeg {} {
    set k "p1=[format %02X [debug read ioports 0xFD]] p2=[format %02X [debug read ioports 0xFE]] pc=[format %04X [w16 [reg SP]]]"
    set k2 [lrange [split $k] 0 1]
    if {[dict exists $::segs $k2]} { dict incr ::segs $k2 } else { dict set ::segs $k2 1; say "8.5 first interrupt with $k" }
}

harness::init "measure"
set ::steps [split $::env(INSTALL) ";"]
proc runSteps {i before} {
    if {$i >= [llength $::steps]} { measure; return }
    set cmd [string trim [lindex $::steps $i]]
    harness::run_cmd $cmd 90 [list afterStep $i $cmd $before]
}
proc afterStep {i cmd before} {
    state "after '$cmd'"
    set f [open $::out.screen a]; foreach l [harness::screen_lines] { if {[string trim $l] ne ""} { puts $f "|$l" } }; puts $f ----; close $f
    set now [snap]
    changed $before $now "  '$cmd'"
    runSteps [expr {$i + 1}] $now
}
proc measure {} {
    debug set_bp 0xFD9F {} timiIn
    after time 6 {
        timiReport
        debug set_bp 0x0038 {} irqSeg
        harness::run_cmd $::env(PROBE) 40 {
            say "8.5 segments at interrupts during '$::env(PROBE)': [dict get $::segs]"
            set f [open $::out.screen a]; foreach l [harness::screen_lines] { if {[string trim $l] ne ""} { puts $f "|$l" } }; close $f
            harness::done
        }
    }
}
set ::atPrompt {
    state "DOS prompt"
    harness::run_cmd "$::env(TOOLS)" 10 { runSteps 0 [snap] }
}
if {[info exists ::env(BOOT)] && $::env(BOOT) eq "nextor"} {
    harness::at_nextor_prompt $::atPrompt
} else {
    harness::at_dos_prompt $::atPrompt 200
}
