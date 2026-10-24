# does the game read memory outside its ROM (4000h-7FFFh) and RAM (E000h-E3FFh)? A mirror of the ROM at 8000h-BFFFh would
# be missing when the image runs from RAM. Logs the first PCs.
if {[info exists ::env(DBGOUT)]} { set dir $::env(DBGOUT) } else { set dir . }
set ::go 0
set ::r [dict create]
debug set_bp 0x4010 {[peek 0x4000] == 0x41 && [peek 0x4001] == 0x42} { set ::go 1 }
proc rec {} { if {!$::go} return; set k [format "%04X %04X" [reg PC] $::wp_last_address]; dict incr ::r $k }
debug set_watchpoint read_mem {0x8000 0xDFFF} {} rec
debug set_watchpoint read_mem {0xE400 0xF37F} {} rec
proc key {row bit secs} { keymatrixdown $row [expr {1 << $bit}]; after time $secs [list keymatrixup $row [expr {1 << $bit}]] }
expr {srand(3)}
proc play {} {
    foreach b {4 5 6 7} { keymatrixup 8 [expr {1 << $b}] }
    keymatrixdown 8 [expr {1 << [lindex {4 5 6 7 5 6 7 7} [expr {int(rand() * 8)}]]}]
    if {rand() < 0.5} { key 8 0 0.15 }
    after time 0.25 play
}
proc finish {} { set f [open "$::dir/reads.txt" w]; dict for {k v} $::r { puts $f "$k $v" }; close $f; exit }
set ::dir $dir
set throttle off
after time 9 { key 8 0 0.3 }
after time 12 play
after time 90 finish
