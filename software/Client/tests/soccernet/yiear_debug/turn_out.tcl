# EXTRA_TCL for run_yiear.sh with MODE=1 (Turn): from tick 600, whenever a fight runs, player 1 is marked out (tOut = 1), the same on
# both nodes, so a long fight goes on with one player out: "PLAYER 1 GAME OVER" must be on the screen and the game must keep playing.
# Logs a line every 60 ticks to $TRACE.out.
set ::tk 0
set ::of [open $::env(TRACE).out w]
debug set_bp $::sym(tickDone) {} {
    incr ::tk
    if {$::tk >= 600 && [peek 0xE000] == 5 && [peek $::sym(tOut)] == 0} { poke $::sym(tOut) 1; puts $::of "$::tk tOut poked" }
    if {$::tk % 60 == 0} { puts $::of [format "%d st=%d/%d mode=%d cur=%d out=%d%d" $::tk [peek 0xE000] [peek 0xE001] [peek $::sym(tMode)] [peek $::sym(tCur)] [peek $::sym(tOut)] [peek [expr {$::sym(tOut) + 1}]]]; flush $::of }
}
