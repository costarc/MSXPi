set ::dbgOut "C:/Users/roniv/AppData/Local/Temp/claude/C--Users-roniv-Dev-github-MSXPi/27a8e5c2-d333-40d0-97f1-3836cb720ed8/scratchpad/dbgload.txt"
set f [open "C:/Users/roniv/Dev/github/MSXPi-salamander/software/Client/src/playnet/build/playnet.sym"]
foreach l [split [read $f] "\n"] { if {[regexp {^([\w.]+): EQU 0x([0-9A-F]+)} $l -> n v]} { set ::ps($n) [expr 0x$v] } }
close $f
set ::dbf [open $::dbgOut w]
array set ::cnt {}
proc hexs {a n} { set s ""; for {set i 0} {$i < $n} {incr i} { append s [format %02X [peek [expr {$a+$i}]]] }; return $s }
proc dbgRegs {tag} {
    if {[info exists ::cnt($tag)]} { incr ::cnt($tag) } else { set ::cnt($tag) 1 }
    if {$::cnt($tag) > 6} return
    puts $::dbf [format "%s #%d t=%.2f PC=%04X AF=%04X BC=%04X DE=%04X HL=%04X SP=%04X mOff=%s" $tag $::cnt($tag) [machine_info time] [reg PC] [reg AF] [reg BC] [reg DE] [reg HL] [reg SP] [hexs $::ps(mOff) 3]]
    flush $::dbf
}
foreach n {mLoad mLoad.chunk mLoad.done mAt mPatch mPatch.differ mPatch.bad mBuild mBuild.copy mUnmap connect romErr badPkg exitResult install} {
    if {[info exists ::ps($n)]} { debug set_bp $::ps($n) {[reg SP] > 0xC000} [list dbgRegs $n] }
}
debug set_bp 0x0038 {[reg SP] < 0xC000 && [reg SP] > 0x4000} {dbgRegs int_low_sp}
