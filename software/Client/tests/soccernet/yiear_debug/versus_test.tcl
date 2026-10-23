# EXTRA_TCL and EXTRA_TCL_C for run_yiear.sh, Versus: the scripted player 1 presses "down" once in the menu, so the cursor is
# put on TURN's neighbour (E481h = 1) when the menu starts and VERSUS is chosen. Then: at tick 900 the fifth opponent is
# beaten (E054h = 4, E00Bh = 1): player 1 must win; later Oolong is killed every 250 ticks (E053h = 0) until player 2 wins.
# Logs a line a second to $TRACE.vs.
set ::tk 0
set ::seen 0
set ::f [open $::env(TRACE).vs w]
debug set_bp $::sym(menu) {[peek 0xE000] == 9 && [peek 0xE001] == 1} {
    if {!$::seen} { poke 0xE481 1; set ::seen 1 }
}
debug set_bp $::sym(menu) {[peek 0xE000] == 9 && [peek 0xE001] == 0} { set ::seen 0 }
debug set_bp $::sym(tickDone) {} {
    incr ::tk
    if {$::tk == 900 && [peek 0xE000] == 5} { poke 0xE054 4; poke 0xE00B 1; puts $::f "$::tk beat the fifth" }
    if {$::tk > 1400 && $::tk % 250 == 100 && [peek 0xE000] == 5} { poke 0xE053 0; puts $::f "$::tk killed" }
    if {$::tk % 60 == 0} {
        puts $::f [format "%d st=%d/%d mode=%d win=%d REST=%02X opp=%d oolong=%02X opx=%02X E16A=%02X E16B=%02X anim=%02X" $::tk \
            [peek 0xE000] [peek 0xE001] [peek $::sym(tMode)] [peek $::sym(tWin)] [peek 0xE050] [peek 0xE054] [peek 0xE161] [peek 0xE181] \
            [peek 0xE16A] [peek 0xE16B] [peek 0xE184]]
        flush $::f
    }
}
