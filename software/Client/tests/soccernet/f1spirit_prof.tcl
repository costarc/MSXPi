# Where a frame's time goes, F1 Spirit (load after f1spirit_node.tcl: EXTRA_TCL=f1spirit_prof.tcl sh run_f1spirit.sh ...).
# Between frames PROF_FROM (default 1200) and PROF_TO (3000), in emulated time, per frame:
#   frame    40A4h (the TICK site) -> 40AFh (the frame's end)
#   tick     PN_TICK (tickSite -> tickSite+3): xchg (XCHG calls, the first is the exchange, the others stall polls),
#            snd (tickDone -> tickSite+3: the T sound ticks), the rest is the engine's own work
#   game     tickSite+3 -> 40AFh: the game's frame logic, with the bank engine's calls (mk: MK_W*/MK_W23 calls)
#   period   one frame start to the next, in interrupts (F0FCh at the next start + 1), as a histogram
#   late     F0FCh at the frame's end (3 or more: the frame overran the 3-interrupt gate)
# $TRACE.prof is rewritten every 300 frames.
set ::pr_from [expr {[info exists ::env(PROF_FROM)] ? $::env(PROF_FROM) : 1200}]
set ::pr_to   [expr {[info exists ::env(PROF_TO)] ? $::env(PROF_TO) : 3000}]
foreach v {n frame tick xchg xcalls snd sndN game mk irqs} { set ::pr_$v 0 }
array set ::pr_late {}
array set ::pr_per {}
set ::pr_t40 0; set ::pr_tT 0; set ::pr_tX 0; set ::pr_tD 0; set ::pr_tG 0
set ::pr_on 0; set ::pr_inx 0; set ::pr_ing 0; set ::pr_lastStart 0
proc pr_f {} { return [expr {$::frames + [peek $::s_nf]}] }
proc pr_start {} {
    if {$::pr_inx} { return }
    set t [machine_info time]
    set f [pr_f]
    set ::pr_on [expr {$f >= $::pr_from && $f < $::pr_to}]
    if {$::pr_on && $::pr_lastStart > 0} {
        set p [format %.0f [expr {($t - $::pr_lastStart) * 60.0}]]
        if {[info exists ::pr_per($p)]} { incr ::pr_per($p) } else { set ::pr_per($p) 1 }
    }
    set ::pr_lastStart $t
    set ::pr_t40 $t
}
proc pr_tickIn {} { set ::pr_tT [machine_info time] }
proc pr_xIn {} { set ::pr_inx 1; set ::pr_tX [machine_info time]; if {$::pr_on} { incr ::pr_xcalls } }
proc pr_xOut {} { set ::pr_inx 0; if {$::pr_on} { set ::pr_xchg [expr {$::pr_xchg + [machine_info time] - $::pr_tX}] } }
proc pr_done {} { set ::pr_tD [machine_info time] }
proc pr_snd {} { if {$::pr_on} { incr ::pr_sndN } }
proc pr_tickOut {} {
    set t [machine_info time]; set ::pr_tG $t; set ::pr_ing 1
    if {!$::pr_on} { return }
    set ::pr_tick [expr {$::pr_tick + $t - $::pr_tT}]
    set ::pr_snd [expr {$::pr_snd + $t - $::pr_tD}]
}
proc pr_mk {} { if {$::pr_on && $::pr_ing} { incr ::pr_mk } }
proc pr_end {} {
    set ::pr_ing 0
    if {$::pr_inx || !$::pr_on} { return }
    set t [machine_info time]
    incr ::pr_n
    set ::pr_frame [expr {$::pr_frame + $t - $::pr_t40}]
    set ::pr_game [expr {$::pr_game + $t - $::pr_tG}]
    set l [peek 0xF0FC]
    if {[info exists ::pr_late($l)]} { incr ::pr_late($l) } else { set ::pr_late($l) 1 }
    if {$::pr_n % 300 == 0} { pr_write }
}
proc pr_write {} {
    set n [expr {$::pr_n > 0 ? $::pr_n : 1}]
    set f [open $::env(TRACE).prof w]
    puts $f "role $::roleArg frames $::pr_n"
    foreach v {frame tick xchg snd game} { puts $f [format "%-6s %7.2f ms/frame" $v [expr {1000.0 * [set ::pr_$v] / $n}]] }
    puts $f [format "engine %7.2f ms/frame (tick - xchg - snd)" [expr {1000.0 * ($::pr_tick - $::pr_xchg - $::pr_snd) / $n}]]
    puts $f [format "xcalls %7.2f /frame  sndT %5.2f /frame  mk %6.1f /frame" [expr {double($::pr_xcalls) / $n}] \
        [expr {double($::pr_sndN) / $n}] [expr {double($::pr_mk) / $n}]]
    puts $f "late (F0FCh at the end): [lmap k [lsort -integer [array names ::pr_late]] {format %s:%d $k $::pr_late($k)}]"
    puts $f "period (interrupts):      [lmap k [lsort -integer [array names ::pr_per]] {format %s:%d $k $::pr_per($k)}]"
    close $f
}
proc pr_go {} {
    if {!$::started} { after time 0.05 pr_go; return }
    debug set_bp 0x40A4 {} { pr_start }
    debug set_bp 0x40AF {} { pr_end }
    debug set_bp $::sym(tickSite) {} { pr_tickIn }
    debug set_bp [expr {$::sym(tickSite) + 3}] {} { pr_tickOut }
    debug set_bp $::sym(tick.xchg) {} { pr_xIn }
    debug set_bp [expr {$::sym(tick.xchg) + 6}] {} { pr_xOut }
    debug set_bp $::s_tickDone {} { pr_done }
    debug set_bp $::sym(sndTick) {} { pr_snd }
    foreach w {MK_W0 MK_W1 MK_W2 MK_W3 MK_W23} { debug set_bp $::sym($w) {} { pr_mk } }
}
after time 1 pr_go
# PROF_PC=1: sample the PC every 0.25 ms of emulated time inside the game part and the sound ticks; histogram by part, 256-byte
# block and page 1/2 segments in $TRACE.pc
array set ::pr_pc {}
proc pr_sample {} {
    after time 0.00025 pr_sample
    if {!$::pr_on} { return }
    if {$::pr_ing} { set part G } elseif {$::pr_tD > $::pr_tT && [machine_info time] >= $::pr_tD && !$::pr_inx && $::pr_tG < $::pr_tD} { set part S } else { return }
    set k [format "%s %02X00 P1=%02X P2=%02X" $part [expr {[reg PC] >> 8}] [debug read ioports 0xFD] [debug read ioports 0xFE]]
    if {[info exists ::pr_pc($k)]} { incr ::pr_pc($k) } else { set ::pr_pc($k) 1 }
    if {$::pr_n % 300 == 299} { set f [open $::env(TRACE).pc w]; foreach k [array names ::pr_pc] { puts $f "$::pr_pc($k) $k" }; close $f }
}
if {[info exists ::env(PROF_PC)]} { after time 2 pr_sample }
