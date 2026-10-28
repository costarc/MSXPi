set ::sto [open "C:/Users/roniv/AppData/Local/Temp/claude/C--Users-roniv-Dev-github-MSXPi/27a8e5c2-d333-40d0-97f1-3836cb720ed8/scratchpad/step_$::env(ROLEARG).txt" w]
set ::stN 0
set ::stOn 0
proc stLog {} {
    incr ::stN
    if {$::stN > 400} { debug remove_condition $::stCond; set ::stOn 0; close $::sto; return }
    set pc [reg PC]
    puts $::sto [format "%04X %-18s SP=%04X AF=%04X BC=%04X DE=%04X HL=%04X IFF=%s im=%s" $pc [lindex [debug disasm $pc] 0] [reg SP] [reg AF] [reg BC] [reg DE] [reg HL] [reg iff] [reg im]]
}
proc stArm {} {
    if {$::stOn || [peek $::sym(PN_ORG)] != 1 || [peek $::sym(MK_BLOCK)] != 1} return
    set ::stOn 1
    set ::stCond [debug set_condition {} stLog]
}
debug set_bp $::sym(clrRam) {} stArm
