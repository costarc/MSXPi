# writes into the bank windows (4000h-BFFFh) from outside the stub, once the game runs; RAM dumps near frame DUMPF
set ::wro [open "C:/Users/roniv/AppData/Local/Temp/claude/C--Users-roniv-Dev-github-MSXPi/27a8e5c2-d333-40d0-97f1-3836cb720ed8/scratchpad/wr_$::env(ROLEARG).txt" w]
array set ::wseen {}
proc wrHit {} {
    if {!$::started} return
    set pc [reg PC]
    if {$pc >= 0xD000 && $pc < 0xD800} return
    set a $::wp_last_address
    set k [format "%04X>%04X" $pc [expr {$a & 0xFFF0}]]
    if {[info exists ::wseen($k)]} { incr ::wseen($k); return }
    set ::wseen($k) 1
    set b $::sym(MK_BLOCK)
    puts $::wro [format "f=%d pc=%04X addr=%04X val=%02X banks=%02X%02X%02X%02X segs=%02X%02X E200=%02X" [expr {$::frames + [peek $::sym(nf)]}] $pc $a $::wp_last_value [peek [expr {$b+4}]] [peek [expr {$b+5}]] [peek [expr {$b+6}]] [peek [expr {$b+7}]] [peek [expr {$b+8}]] [peek [expr {$b+9}]] [peek 0xE200]]
    flush $::wro
}
debug set_watchpoint write_mem {0x4000 0xBFFF} {} wrHit
