set ::ino [open "C:/Users/roniv/AppData/Local/Temp/claude/C--Users-roniv-Dev-github-MSXPi/27a8e5c2-d333-40d0-97f1-3836cb720ed8/scratchpad/init_$::env(ROLEARG).txt" w]
proc inLog {tag} {
    if {[peek 0x4000] != 0x41 || [peek 0xD000] != 1 || [peek $::sym(MK_BLOCK)] != 1 || [peek [expr {$::sym(MK_BLOCK)+1}]] != 0x0F} return
    incr ::inN
    if {$::inN > 3000} return
    puts $::ino [format "%s t=%.4f PC=%04X SP=%04X AF=%04X BC=%04X DE=%04X HL=%04X IFF=%s st=%02X%02X" $tag [machine_info time] [reg PC] [reg SP] [reg AF] [reg BC] [reg DE] [reg HL] [reg iff] [peek [expr {[reg SP]}]] [peek [expr {[reg SP]+1}]]]
    flush $::ino
}
set ::inN 0
foreach a {0x40DA 0x40DB 0x40DD 0x40E8 0x412F 0x414F 0x40EB 0x40EE 0x40F1 0x410B 0x410E 0x411F 0x4122 0x4125 0x4129 0x412C 0x4069 0x40AC 0x40B5} { debug set_bp $a {} [list inLog [format %04X $a]] }
foreach n {clrRam probeOff tickSite MK_W0 MK_W1 MK_W2 MK_W3 mkOut mkBuild sndTick} { debug set_bp $::sym($n) {} [list inLog $n] }
