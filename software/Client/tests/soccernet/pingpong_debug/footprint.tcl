# Konami's Ping Pong on the cartridge: where does it write outside E000h-E3FFh, how deep does the stack go, how often do
# the hook sites run?
#   openmsx -machine Canon_V-20 -carta PINGPONG.ROM -script footprint.tcl
# Environment: DBGOUT = output folder, TMAX = emulated seconds (default 240), SEED, PLAYERS=1|2 (default 2),
# P2KEYS=1 also drives player 2's keyboard keys (rows 6, 3, 2, 5).
if {[info exists ::env(DBGOUT)]} { set dir $::env(DBGOUT) } else { set dir . }
if {![info exists ::env(TMAX)]} { set ::env(TMAX) 240 }
expr {srand([expr {[info exists ::env(SEED)] ? $::env(SEED) : 1}])}
set players [expr {[info exists ::env(PLAYERS)] ? $::env(PLAYERS) : 2}]
set ::w [dict create]
set ::hits [dict create]
set ::spmin 0xFFFF
set ::go 0
set ::stages {}
debug set_bp 0x4010 {[peek 0x4000] == 0x41 && [peek 0x4001] == 0x42} { set ::go 1 }
proc rec {area} {
    if {!$::go} return
    set pc [reg PC]; set a $::wp_last_address
    set k [format "%s %04X" $area $pc]
    if {[dict exists $::w $k]} {
        lassign [dict get $::w $k] n lo hi
        if {$a < $lo} { set lo $a }; if {$a > $hi} { set hi $a }
        dict set ::w $k [list [incr n] $lo $hi]
    } else { dict set ::w $k [list 1 $a $a] }
}
debug set_watchpoint write_mem {0x4000 0x7FFF} {} { rec rom }
debug set_watchpoint write_mem {0x8000 0xDFFF} {} { rec low }
debug set_watchpoint write_mem {0xE400 0xF37F} {} { rec high }
proc hit {name} {
    dict incr ::hits $name
    set sp [reg SP]
    if {$sp < $::spmin} { set ::spmin $sp; set ::spat $name }
}
foreach {name addr} {tick 0x4033 irq 0x401D catch 0x404A disp 0x409F menu1 0x42AB menu2 0x43A7 ai 0x5B6E demo 0x709D} {
    debug set_bp $addr {} [list hit $name]
}
proc state {} {
    lappend ::stages [format "t=%d st=%d/%d e002=%02X e042=%d e049=%d" [expr {int([machine_info time])}] \
        [peek 0xE000] [peek 0xE001] [peek 0xE002] [peek 0xE042] [peek 0xE049]]
    after time 10 state
}
proc key {row bit secs} { keymatrixdown $row [expr {1 << $bit}]; after time $secs [list keymatrixup $row [expr {1 << $bit}]] }
proc play {} {
    foreach b {4 5 6 7} { keymatrixup 8 [expr {1 << $b}] }
    set d [lindex {4 5 6 7 5 6 7 7} [expr {int(rand() * 8)}]]
    keymatrixdown 8 [expr {1 << $d}]
    if {rand() < 0.5} { key 8 0 0.15 }
    if {[info exists ::env(P2KEYS)]} { foreach r {6 3 2 5} { keymatrixup $r 0xFF }
        keymatrixdown [lindex {6 3 2 5} [expr {int(rand()*4)}]] [expr {1 << int(rand()*8)}] }
    after time 0.25 play
}
proc finish {} {
    set f [open "$::dir/footprint.txt" w]
    puts $f "SP min [format %04X $::spmin] at $::spat"
    puts $f "hits: $::hits"
    dict for {k v} $::w { puts $f [format "%s n=%d %04X-%04X" $k {*}$v] }
    puts $f [join $::stages "\n"]
    close $f
    exit
}
set ::dir $dir
set throttle off
if {$players == 2} { after time 7 { key 8 6 0.2 } }
after time 8 { key 8 0 0.3 }
after time 10 play
after time 10 state
after time $::env(TMAX) finish
