# Where a frame's time goes, per 10 s (emulated): ticks (game frames), PN_TICK up to tickDone (the exchange, with any
# wait for the opponent), the C9 transactions in it (count and time: XCHG entry -> back in tick), the sound ticks
# (tickDone -> back at tickSite), bank switches by kind (calls; mkPage = a pair the map did not know), and a PC
# histogram (16-byte buckets, every 0.7 ms) of the play states (E200h = 04h/05h). The cartridge spends 31% of play in
# its idle loop at 4120h (salamander_debug/cartridge_fps.tcl for its frame rate). EXTRA_TCL.
# Output: <trace>.prof (per 10 s) and <trace>.pcs (the histogram, rewritten every 20 s)
set ::pfo [open "$::env(TRACE).prof" w]
array set ::acc {ticks 0 tick 0 snd 0 nx 0 xt 0}
array set ::bk {}
array set ::pch {}
set ::pns 0
set ::tx 0
set ::td 0
set ::tc 0
proc pIn {} { set ::tx [machine_info time]; incr ::acc(ticks) }
proc pDone {} { set ::td [machine_info time]; set ::acc(tick) [expr {$::acc(tick) + $::td - $::tx}] }
proc pBack {} { if {$::td > 0} { set ::acc(snd) [expr {$::acc(snd) + [machine_info time] - $::td}]; set ::td 0 } }
proc pXIn {} { set ::tc [machine_info time]; incr ::acc(nx) }
proc pXOut {} { if {$::tc > 0} { set ::acc(xt) [expr {$::acc(xt) + [machine_info time] - $::tc}]; set ::tc 0 } }
proc pBank {k} { if {[info exists ::bk($k)]} { incr ::bk($k) } else { set ::bk($k) 1 } }
proc pReport {} {
    after time 10 pReport
    puts $::pfo [format "t=%.1f E200=%02X ticks=%d tick=%.3f xchg=%d/%.3f snd=%.3f banks: %s" [machine_info time] \
        [peek 0xE200] $::acc(ticks) $::acc(tick) $::acc(nx) $::acc(xt) $::acc(snd) [lsort -stride 2 [array get ::bk]]]
    flush $::pfo
    array set ::acc {ticks 0 tick 0 snd 0 nx 0 xt 0}
    array unset ::bk
    array set ::bk {}
}
proc pSamp {} {
    set s [peek 0xE200]
    if {$s == 4 || $s == 5} {
        set k [format %04X [expr {[reg PC] & 0xFFF0}]]
        if {[info exists ::pch($k)]} { incr ::pch($k) } else { set ::pch($k) 1 }
        incr ::pns
    }
    after time 0.000713 pSamp
}
proc pPcs {} {
    after time 20 pPcs
    if {!$::pns} return
    set f [open "$::env(TRACE).pcs" w]
    foreach {k v} [lsort -stride 2 -integer -index 1 -decreasing [array get ::pch]] {
        puts $f [format "%s %d %.1f%%" $k $v [expr {100.0 * $v / $::pns}]]
    }
    close $f
}
proc pArm {} {
    if {!$::started} { after time 0.5 pArm; return }
    debug set_bp $::sym(PN_TICK) {} pIn
    debug set_bp $::sym(tickDone) {} pDone
    debug set_bp [expr {$::sym(tickSite) + 3}] {} pBack
    debug set_bp $::sym(PN_TRANSPORT) {} pXIn
    debug set_bp [expr {$::sym(tick.xchg) + 6}] {} pXOut
    foreach k {MK_W0 MK_W1 MK_W2 MK_W3 MK_W23 mkSame mkPage mkBuild} { debug set_bp $::sym($k) {} [list pBank $k] }
    after time 10 pReport
    after time 20 pPcs
    pSamp
}
after time 5 pArm
