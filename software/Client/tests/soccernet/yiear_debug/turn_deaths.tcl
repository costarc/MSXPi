# EXTRA_TCL and EXTRA_TCL_C for run_yiear.sh: kills Oolong (E053h = 0, the fight's "player lost" flag) every DEATH_EVERY ticks
# (default 300) while a fight runs, the same ticks on both nodes, and logs the Turn state (mode, current player, REST,
# stage, score, out flags) once a second to $TRACE.turn.
if {![info exists ::env(DEATH_EVERY)]} { set ::env(DEATH_EVERY) 300 }
set ::tk 0
set ::tf2 [open $::env(TRACE).turn w]
debug set_bp $::sym(tickDone) {} {
    incr ::tk
    if {$::tk % $::env(DEATH_EVERY) == 200 && [peek 0xE000] == 5} { poke 0xE053 0; puts $::tf2 "$::tk killed" }
    if {$::tk % 60 == 0} {
        puts $::tf2 [format "%d st=%d/%d mode=%d cur=%d out=%d%d REST=%02X stage=%02X opp=%d score=%02X%02X%02X" $::tk \
            [peek 0xE000] [peek 0xE001] [peek $::sym(tMode)] [peek $::sym(tCur)] [peek $::sym(tOut)] [peek [expr {$::sym(tOut) + 1}]] \
            [peek 0xE050] [peek 0xE051] [peek 0xE054] [peek 0xE04B] [peek 0xE04A] [peek 0xE049]]
        flush $::tf2
    }
}
