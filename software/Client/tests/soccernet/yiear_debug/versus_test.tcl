# EXTRA_TCL and EXTRA_TCL_C for run_yiear.sh with MODE=2 (Versus). The same ticks on both nodes:
#   first match: the opponent is beaten (E00Bh = 1) at ticks 500, 900 and 1300: player 2 loses its three lives, player 1 must win;
#   second match: from tick WIN2 (default 3000) Oolong is killed (E053h = 0) every 250 ticks until REST is 0: player 2 must win.
# Logs a line a second to $TRACE.vs: state, the mode, tWin, REST, player 2's lives, the opponent.
if {![info exists ::env(WIN2)]} { set ::env(WIN2) 3000 }
set ::tk 0
set ::f [open $::env(TRACE).vs w]
debug set_bp $::sym(tickDone) {} {
    incr ::tk
    if {[lsearch {500 900 1300} $::tk] >= 0 && [peek 0xE000] == 5} { poke 0xE00B 1; puts $::f "$::tk beat the opponent" }
    if {$::tk > $::env(WIN2) && $::tk % 250 == 100 && [peek 0xE000] == 5} { poke 0xE053 0; puts $::f "$::tk killed" }
    if {$::tk % 60 == 0} {
        puts $::f [format "%d st=%d/%d mode=%d win=%d REST=%02X lives2=%d opp=%d" $::tk             [peek 0xE000] [peek 0xE001] [peek $::sym(tMode)] [peek $::sym(tWin)] [peek 0xE050] [peek $::sym(tLives2)] [peek 0xE054]]
        flush $::f
    }
}
