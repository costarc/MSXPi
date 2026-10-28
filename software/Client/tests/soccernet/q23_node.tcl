# What the TCP/IP stack does inside an XCHG (PLAYNET-TCPIP-PERFORMANCE.md Q2 and Q3). Load it after native_node.tcl:
#   EXTRA_TCL=q23_node.tcl OVLMAP=.../build/ovl/ovl.map ETHROM=.../ethrom.lst sh run_native.sh ...
# Inside XCHG only (the game's own code can sit at the same addresses), it logs, in order, to $TRACE.q23:
#   X  XCHG entered        Y  XCHG left (the log line carries the emulated time in ms since X)
#   N  the overlay's nc_send      R  its nc_recv     T  a run of MSX-DOS's H.TIMI hook (the stack's timer)
#   S  the Ethernet driver's ETH_SEND_FRAME   G  ETH_GET_FRAME   I  ETH_IN_STATUS
# for QFRAMES frames (default 150) from QFROM (default 600). q23_analyze.py reads it.
set ::q_from 600
if {[info exists ::env(QFROM)]} { set ::q_from $::env(QFROM) }
set ::q_n 150
if {[info exists ::env(QFRAMES)]} { set ::q_n $::env(QFRAMES) }
set ::q_frames 0; set ::q_inx 0; set ::q_log {}; set ::q_g3 -1; set ::q_t0 0.0; set ::q_done 0

proc q_sym {path name} {
    set f [open $path r]; set text [read $f]; close $f
    if {[regexp "\\n\\s*0*(\[0-9A-Fa-f\]+)\\s+$name\\s" $text -> addr]} { return [expr "0x$addr"] }
    error "no $name in $path"
}
proc q_ev {c} {
    if {!$::q_inx || $::q_done || $::q_frames < $::q_from} { return }
    lappend ::q_log "$c [format %.2f [expr {([machine_info time] - $::q_t0) * 1000.0}]]"
}
proc q_xin {} {
    set ::q_inx 1
    if {$::q_g3 < 0} { set ::q_g3 [debug read ioports 0xFF] }
    set ::q_t0 [machine_info time]
    q_ev X
}
proc q_xout {} { q_ev Y; set ::q_inx 0 }
proc q_timi {} {
    if {$::q_g3 >= 0 && [debug read ioports 0xFF] != $::q_g3} { q_ev T }
}
proc q_tick {} {
    incr ::q_frames
    if {$::q_frames == $::q_from + $::q_n && !$::q_done} {
        set ::q_done 1
        set f [open $::env(TRACE).q23 w]
        foreach e $::q_log { puts $f $e }
        close $f
    }
}
proc q_arm {} {
    if {![info exists ::started] || !$::started} { after time 0.05 q_arm; return }
    debug set_bp $::sym(tick.xchg) {} { q_xin }
    debug set_bp [expr {$::sym(tick.xchg) + 6}] {} { q_xout }
    debug set_bp $::s_tickDone {} { q_tick }
    debug set_bp 0xFD9F {} { q_timi }
    debug set_bp [q_sym $::env(OVLMAP) _nc_send] {} { q_ev N }
    debug set_bp [q_sym $::env(OVLMAP) _nc_recv] {} { q_ev R }
    foreach {name code} {FN_SEND_FRAME S FN_GET_FRAME G FN_IN_STATUS I} {
        debug set_bp [q_lst $::env(ETHROM) $name] {} "q_ev $code"
    }
}
# sjasm listing: "  1471  490+  7E8F             FN_SEND_FRAME:"
proc q_lst {path name} {
    set f [open $path r]; set text [read $f]; close $f
    if {[regexp "\\n\[^\\n\]*?(\[0-9A-F\]{4})\\s+$name:" $text -> addr]} { return [expr "0x$addr"] }
    error "no $name in $path"
}
after time 1 q_arm
