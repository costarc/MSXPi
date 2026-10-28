# every frame up to DUMPN: C000h-CFFFh, E000h-F0FFh into ramdump_<role>/<frame>.bin (at tickDone: the inputs for the frame are known)
set ::rdDir "C:/Users/roniv/AppData/Local/Temp/claude/C--Users-roniv-Dev-github-MSXPi/27a8e5c2-d333-40d0-97f1-3836cb720ed8/scratchpad/ramdump_$::env(ROLEARG)"
file mkdir $::rdDir
set ::rdN 0
proc rdTick {} {
    if {$::rdN > 250} return
    set nf [peek $::sym(nf)]
    if {[file exists "$::rdDir/[format %03d $nf].bin"]} return
    set f [open "$::rdDir/[format %03d $nf].bin" wb]
    puts -nonewline $f [debug read_block memory 0xC000 0x1000]
    puts -nonewline $f [debug read_block memory 0xE000 0x1100]
    puts -nonewline $f [debug read_block memory $::sym(PN_P1) 4]
    close $f
    incr ::rdN
}
proc rdArm {} {
    if {!$::started} { after time 0.01 rdArm; return }
    debug set_bp $::sym(tickDone) {} rdTick
}
after time 5 rdArm
