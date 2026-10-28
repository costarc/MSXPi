# Sound tempo and game speed during a fight (documents/YIEAR-TEST-PLAN.md T4, T1.2): how many times the sound driver (7C5Ch) and the
# frame counter (407Eh) run per emulated second while the game is in state 5, over TEMPO_WIN seconds (default 20) that start
# TEMPO_SKIP seconds (default 4) after the fight begins. The same script runs on the bare cartridge and as EXTRA_TCL of the rig
# (then the numbers include the lockstep engine, which ticks the driver itself, and any stall waiting for the network).
#   openmsx -machine Canon_V-25 -carta kung-fu.rom -script tempo.tcl      (TEMPO_OUT = result file; TEMPO_CART=1 plays by itself)
if {![info exists ::env(TEMPO_WIN)]} { set ::env(TEMPO_WIN) 20 }
if {![info exists ::env(TEMPO_SKIP)]} { set ::env(TEMPO_SKIP) 4 }
set ::lastTap 0; set ::leftAt -1; set ::tm 0; set ::sn 0; set ::fr 0; set ::t0 -1; set ::tA -1; set ::done 0
proc tmHit {what} {
    if {$::t0 < 0 || $::done} return
    if {$what eq "snd"} { incr ::sn } else { incr ::fr }
}
proc tmPoll {} {
    if {$::done} return
    set now [machine_info time]
    if {[peek 0x4000] == 0x41 && [peek 0xE000] == 5} {
        if {$::tA < 0} { set ::tA $now }
        if {$::t0 < 0 && $now - $::tA >= $::env(TEMPO_SKIP)} { set ::t0 $now; set ::sn 0; set ::fr 0 }
    } elseif {$::t0 >= 0 && !$::done} {
        # the fight is over (or the game is between two states): report only when it stays out for more than 2 s
        if {$::leftAt < 0} { set ::leftAt $now } elseif {$now - $::leftAt > 2} { tmReport $::leftAt; return }
    }
    if {$::t0 >= 0 && [peek 0xE000] == 5} { set ::leftAt -1 }
    if {$::t0 >= 0 && $now - $::t0 >= $::env(TEMPO_WIN)} { tmReport $now; return }
    if {[info exists ::env(TEMPO_CART)]} {
        poke 0xE050 9
        # the cartridge on its own: a tap on space while the title is up (state 1), every 2 s
        if {[peek 0xE000] == 1 && $now - $::lastTap > 2} { set ::lastTap $now; keymatrixdown 8 1; after time 0.3 { keymatrixup 8 1 } }
    }
    after time 0.1 tmPoll
}
proc tmReport {now} {
    set ::done 1
    set dt [expr {$now - $::t0}]
    set out $::env(TEMPO_OUT)
    if {[info exists ::env(ROLEARG)]} { append out .$::env(ROLEARG) }      ;# in the rig: one file per node
    set f [open $out w]
    puts $f [format "window %.2f s: sound driver %d calls (%.2f/s), frames %d (%.2f/s), machine %s" $dt $::sn [expr {$::sn / $dt}] $::fr [expr {$::fr / $dt}] [machine_info type]]
    close $f
    if {[info exists ::env(TEMPO_CART)]} { exit }
}
debug set_bp 0x7C5C {[peek 0x4000] == 0x41} { tmHit snd }
debug set_bp 0x407E {[peek 0x4000] == 0x41} { tmHit frm }
if {[info exists ::env(TEMPO_CART)]} {
    # the cartridge on its own: start the game from the title, then stand still (REST kept up)
    set throttle off                 ;# the numbers are per emulated second, so the speed of the host does not matter
    after time 120 { if {!$::done} { set f [open $::env(TEMPO_OUT) w]; puts $f [format "no fight seen: state %d/%d t0=%s" [peek 0xE000] [peek 0xE001] $::t0]; close $f }; exit }
}
after time 1 tmPoll
