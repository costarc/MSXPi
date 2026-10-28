# Per game frame in the play states (E200h = 04h/05h): how long the CPU is busy, from the interrupt taken in the idle
# loop (412Dh) until it is back there. A frame fits two interrupts (the cartridge's 30 frames/s) when this is under
# 33.4 ms. Works on the cartridge (openmsx -carta SALAMAND.ROM -romtype KonamiSCC -script busy.tcl, with BUSY_OUT and
# BUSY_PLAY=1 to press the keys of cartridge_fps.tcl) and as EXTRA_TCL in the rig (output <trace>.busy).
# Output: a histogram of busy ms (1 ms buckets) every 10 s.
if {[info exists ::env(TRACE)]} { set ::bzOut "$::env(TRACE).busy" } else { set ::bzOut $::env(BUSY_OUT) }
set ::bzf [open $::bzOut w]
set ::busy 0
set ::bt0 0
array set ::bh {}
set ::bn 0
proc bzStart {} {
    set s [peek 0xE200]
    if {$s != 4 && $s != 5} return
    set ::bt0 [machine_info time]
    set ::busy 1
}
proc bzEnd {} {
    set ::busy 0
    set ms [expr {int(([machine_info time] - $::bt0) * 1000)}]
    if {[info exists ::bh($ms)]} { incr ::bh($ms) } else { set ::bh($ms) 1 }
    incr ::bn
}
proc bzRep {} {
    after time 10 bzRep
    if {!$::bn} return
    set fit 0
    set sum 0
    foreach {k v} [array get ::bh] { if {$k < 33} { incr fit $v }; incr sum [expr {$k * $v}] }
    puts $::bzf [format "t=%.0f frames=%d mean=%.1fms under33=%d%% hist=%s" [machine_info time] $::bn \
        [expr {double($sum) / $::bn}] [expr {100 * $fit / $::bn}] [lsort -integer -stride 2 [array get ::bh]]]
    flush $::bzf
    array unset ::bh
    array set ::bh {}
    set ::bn 0
}
proc bzArm {} {
    if {[info exists ::started] && !$::started} { after time 0.5 bzArm; return }
    debug set_bp 0x0038 {[peek [reg SP]] == 0x2D && [peek [expr {[reg SP] + 1}]] == 0x41} bzStart
    debug set_bp 0x412D {$::busy} bzEnd
    after time 10 bzRep
}
after time 5 bzArm
if {[info exists ::env(BUSY_PLAY)]} {
    proc kd {r b} { keymatrixdown $r $b }
    proc ku {r b} { keymatrixup $r $b }
    proc tap {r b} { kd $r $b; after time 0.12 "ku $r $b" }
    after time 13 {tap 8 6}
    after time 13.5 {tap 8 6}
    after time 14.5 {tap 8 0}
    proc wig {n} {
        if {$n <= 0} return
        kd 8 0
        if {$n % 2} { ku 8 5; kd 8 6 } else { ku 8 6; kd 8 5 }
        after time 0.5 "wig [expr {$n-1}]"
    }
    after time 18 {wig 400}
    after time 120 {close $::bzf; exit}
    set throttle off
}
