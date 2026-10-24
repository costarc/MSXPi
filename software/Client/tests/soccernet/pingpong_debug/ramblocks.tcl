# which 32-byte blocks of E000h-E3FFh does the game write during play, and from how many writes? (picks the desync region)
#   DBGOUT=folder TMAX=secs openmsx -machine Canon_V-20 -carta PINGPONG.ROM -script ramblocks.tcl
if {[info exists ::env(DBGOUT)]} { set dir $::env(DBGOUT) } else { set dir . }
if {![info exists ::env(TMAX)]} { set ::env(TMAX) 90 }
expr {srand(2)}
set ::cnt [dict create]
debug set_watchpoint write_mem {0xE000 0xE3FF} {} {
    set b [expr {($::wp_last_address - 0xE000) / 32}]
    dict incr ::cnt $b
}
proc key {row bit secs} { keymatrixdown $row [expr {1 << $bit}]; after time $secs [list keymatrixup $row [expr {1 << $bit}]] }
proc play {} {
    foreach b {4 5 6 7} { keymatrixup 8 [expr {1 << $b}] }
    keymatrixdown 8 [expr {1 << [lindex {4 5 6 7 5 6 7 7} [expr {int(rand() * 8)}]]}]
    if {rand() < 0.5} { key 8 0 0.15 }
    foreach r {6 3 2 5} { keymatrixup $r 0xFF }
    keymatrixdown [lindex {6 3 2 5} [expr {int(rand()*4)}]] [expr {1 << int(rand()*8)}]
    after time 0.25 play
}
proc finish {} {
    set f [open "$::dir/ramblocks.txt" w]
    foreach b [lsort -integer [dict keys $::cnt]] { puts $f [format "%04X %d" [expr {0xE000 + $b*32}] [dict get $::cnt $b]] }
    close $f; exit
}
set ::dir $dir
set throttle off
after time 10 play
after time $::env(TMAX) finish
