set ::out "C:/Users/roniv/AppData/Local/Temp/claude/C--Users-roniv-Dev-github-MSXPi/27a8e5c2-d333-40d0-97f1-3836cb720ed8/scratchpad/sal/fps.txt"
set ::n 0
proc fr {} { incr ::n }
debug set_watchpoint write_mem 0xE203 {} fr
proc kd {r b} { keymatrixdown $r $b }
proc ku {r b} { keymatrixup $r $b }
proc tap {r b} { kd $r $b; after time 0.12 "ku $r $b" }
after time 13 {tap 8 6}
after time 13.5 {tap 8 6}
after time 14.5 {tap 8 0}
proc wig {n} {
  if {$n <= 0} return
  kd 8 0
  if {$n % 2} { ku 8 5; kd 8 6 } else { ku 8 6; kd 8 5 }
  after time 0.5 "wig [expr {$n-1}]"
}
after time 18 {wig 400}
set ::f [open $::out w]
proc mark {} { puts $::f [format "t=%.1f frames=%d E200=%02X" [machine_info time] $::n [peek 0xE200]]; flush $::f; after time 10 mark }
after time 10 mark
after time 120 {close $::f; exit}
set throttle off
