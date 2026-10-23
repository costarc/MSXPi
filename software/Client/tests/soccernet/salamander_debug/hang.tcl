set ::hgo [open "C:/Users/roniv/AppData/Local/Temp/claude/C--Users-roniv-Dev-github-MSXPi/27a8e5c2-d333-40d0-97f1-3836cb720ed8/scratchpad/hang_$::env(ROLEARG).txt" w]
proc hx {a n} { set s ""; for {set i 0} {$i < $n} {incr i} { append s [format %02X [peek [expr {($a+$i) & 0xFFFF}]]] }; return $s }
proc hgDump {tag} {
    set sp [reg SP]
    puts $::hgo [format "%s t=%.2f PC=%04X SP=%04X AF=%04X BC=%04X DE=%04X HL=%04X IX=%04X IY=%04X A8=%02X sub=%02X nf=%02X E200=%02X" $tag [machine_info time] [reg PC] $sp [reg AF] [reg BC] [reg DE] [reg HL] [reg IX] [reg IY] [debug read ioports 0xA8] [expr {[peek 0xFFFF] ^ 0xFF}] [peek $::sym(nf)] [peek 0xE200]]
    puts $::hgo "stack [hx $sp 48]"
    set pc [reg PC]
    set d ""
    set a [expr {$pc - 16}]
    for {set i 0} {$i < 14} {incr i} { set r [debug disasm $a]; append d [format "%04X %s | " $a [lindex $r 0]]; incr a [expr {[llength $r] - 1}] }
    puts $::hgo $d
    puts $::hgo "mapper FC-FF: [debug read ioports 0xFC] [debug read ioports 0xFD] [debug read ioports 0xFE] [debug read ioports 0xFF] block=[hx $::sym(MK_BLOCK) 10]"
    flush $::hgo
}
proc hgWatch {} {
    if {$::started && [peek $::sym(nf)] == 0xFF} {
        incr ::hgN
        if {$::hgN == 40 || $::hgN == 41 || $::hgN == 60} { hgDump hang }
    }
    after time 0.5 hgWatch
}
set ::hgN 0
after time 5 hgWatch
proc hgInit {} { if {$::started} { hgDump init } }
