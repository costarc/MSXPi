# Timing of one node, in emulated time (PLAYNET-TCPIP-PERFORMANCE.md step 0). Load it after native_node.tcl:
#   EXTRA_TCL=perf_node.tcl EXTRA_TCL_C=perf_node.tcl sh run_native.sh ...
# It waits for native_node's "started" (the stub is running) and then counts, per node:
#   frames, XCHG calls (the first of a frame is the exchange, the others are stall polls), the emulated time
#   spent in XCHG, the MSXPi link bytes (ports 5Ah: C9 transactions and Ethernet frames alike), and the runs
#   of MSX-DOS's H.TIMI hook (= the TCP/IP stack's timer; the game's own page 3 is told apart by the mapper).
# PERF_PROF=1 also samples the PC every 0.5 ms of emulated time while inside XCHG and writes the histogram, by 256-byte
# block, slot register and page 1/2 mapper segments, to $TRACE.prof: where the time of an exchange goes.
# $TRACE.perf is rewritten every 100 frames: key value lines, read by cmp_perf.py.
# Frames before PERF_FROM (default 500: the set-up screens) are left out of the rates.
set ::pf_from 500
if {[info exists ::env(PERF_FROM)]} { set ::pf_from $::env(PERF_FROM) }
set ::pf_frames 0
set ::pf_calls 0; set ::pf_stalled 0; set ::pf_inFrame 0
set ::pf_xt 0.0; set ::pf_tin 0.0
set ::pf_bout 0; set ::pf_bin 0; set ::pf_timi 0
set ::pf_g3 -1
set ::pf_t0 0.0; set ::pf_c0 0; set ::pf_s0 0; set ::pf_x0 0.0; set ::pf_bo0 0; set ::pf_bi0 0; set ::pf_ti0 0; set ::pf_xf0 0

proc pf_write {} {
    set f [open $::env(TRACE).perf w]
    set t [machine_info time]
    puts $f "role $::roleArg"
    puts $f "from $::pf_from"
    puts $f "frames [expr {$::pf_frames - $::pf_from}]"
    puts $f "seconds [format %.3f [expr {$t - $::pf_t0}]]"
    puts $f "xchg_calls [expr {$::pf_calls - $::pf_c0}]"
    puts $f "stalled_frames [expr {$::pf_stalled - $::pf_s0}]"
    puts $f "xchg_seconds [format %.4f [expr {$::pf_xt - $::pf_x0}]]"
    puts $f "link_out [expr {$::pf_bout - $::pf_bo0}]"
    puts $f "link_in [expr {$::pf_bin - $::pf_bi0}]"
    puts $f "timi_runs [expr {$::pf_timi - $::pf_ti0}]"
    close $f
}
set ::pf_inx 0
array set ::pf_hist {}
proc pf_sample {} {
    after time 0.0005 pf_sample
    if {!$::pf_inx} { return }
    set k [format "%02X00 A8=%02X P1=%02X P2=%02X" [expr {[reg PC] >> 8}] [debug read ioports 0xA8] [debug read ioports 0xFD] [debug read ioports 0xFE]]
    if {[info exists ::pf_hist($k)]} { incr ::pf_hist($k) } else { set ::pf_hist($k) 1 }
}
proc pf_dump {} {
    set f [open $::env(TRACE).prof w]
    foreach k [array names ::pf_hist] { puts $f "$::pf_hist($k) $k" }
    close $f
}
proc pf_xchgIn {} {
    set ::pf_inx 1
    if {$::pf_g3 < 0} { set ::pf_g3 [debug read ioports 0xFF] }
    incr ::pf_calls; incr ::pf_inFrame
    set ::pf_tin [machine_info time]
}
proc pf_xchgOut {} { set ::pf_inx 0; set ::pf_xt [expr {$::pf_xt + [machine_info time] - $::pf_tin}] }
proc pf_tick {} {
    incr ::pf_frames
    if {$::pf_inFrame > 1} { incr ::pf_stalled }
    set ::pf_inFrame 0
    if {$::pf_frames == $::pf_from} {            ;# the measured window starts here
        set ::pf_t0 [machine_info time]; set ::pf_c0 $::pf_calls; set ::pf_s0 $::pf_stalled
        set ::pf_x0 $::pf_xt; set ::pf_bo0 $::pf_bout; set ::pf_bi0 $::pf_bin; set ::pf_ti0 $::pf_timi
    }
    if {$::pf_frames % 100 == 0 && $::pf_frames > $::pf_from} { pf_write; if {[info exists ::env(PERF_PROF)]} { pf_dump } }
}
proc pf_timi {} {
    if {$::pf_g3 >= 0 && [debug read ioports 0xFF] != $::pf_g3} { incr ::pf_timi }
}
proc pf_arm {} {
    if {![info exists ::started] || !$::started} { after time 0.05 pf_arm; return }
    debug set_bp $::sym(tick.xchg) {} { pf_xchgIn }
    debug set_bp [expr {$::sym(tick.xchg) + 6}] {} { pf_xchgOut }
    debug set_bp $::s_tickDone {} { pf_tick }
    debug set_bp 0xFD9F {} { pf_timi }
    if {[info exists ::env(PERF_PROF)]} { after time 0.0005 pf_sample }
    debug set_watchpoint write_io 0x5A {} { incr ::pf_bout }
    debug set_watchpoint read_io 0x5A {} { incr ::pf_bin }
}
after time 1 pf_arm
