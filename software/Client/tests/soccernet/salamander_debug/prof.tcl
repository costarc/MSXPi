# time spent (emulated) per frame in: the exchange (PN_TICK entry -> tickDone), the sound ticks (tickDone -> PN_TICK's ret,
# approximated by sndTick calls), the bank engine (MK_Wn entry -> mkOut ret)
set ::pfo [open "C:/Users/roniv/AppData/Local/Temp/claude/C--Users-roniv-Dev-github-MSXPi/27a8e5c2-d333-40d0-97f1-3836cb720ed8/scratchpad/prof_$::env(ROLEARG).txt" w]
array set ::acc {xchg 0 snd 0 bank 0 nb 0 nsnd 0}
set ::tx 0; set ::ts 0; set ::tb 0; set ::pf0 -1; set ::pt0 0
proc pIn {} { set ::tx [machine_info time] }
proc pDone {} { set ::acc(xchg) [expr {$::acc(xchg) + [machine_info time] - $::tx}] }
proc sIn {} { set ::ts [machine_info time]; incr ::acc(nsnd) }
proc bIn {} { set ::tb [machine_info time]; incr ::acc(nb) }
proc bOut {} { set ::acc(bank) [expr {$::acc(bank) + [machine_info time] - $::tb}] }
proc pReport {} {
    after time 10 pReport
    if {![info exists ::sym(PN_TICK)]} return
    set f [expr {[peek $::sym(nf)]}]
    set now [machine_info time]
    puts $::pfo [format "t=%.1f E200=%02X xchg=%.3f bank=%.3f switches=%d sndTicks=%d (per 10 s)" $now [peek 0xE200] $::acc(xchg) $::acc(bank) $::acc(nb) $::acc(nsnd)]
    flush $::pfo
    array set ::acc {xchg 0 snd 0 bank 0 nb 0 nsnd 0}
}
proc pArm {} {
    if {!$::started} { after time 0.5 pArm; return }
    debug set_bp $::sym(PN_TICK) {} pIn
    debug set_bp $::sym(tickDone) {} pDone
    debug set_bp $::sym(sndTick) {} sIn
    foreach w {MK_W0 MK_W1 MK_W2 MK_W3} { debug set_bp $::sym($w) {} bIn }
    debug set_bp $::sym(mkOut) {} bOut
    after time 10 pReport
}
after time 5 pArm
