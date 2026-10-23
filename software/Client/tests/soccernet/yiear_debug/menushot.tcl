set ::shots 0
debug set_bp $::sym(menu) {[peek 0xE001] == 1 && [peek 0xE000] == 9} {
    incr ::shots
    if {$::shots == 4 || $::shots == 12} {
        set f [open $::env(DBGOUT)/vram$::shots.txt w]
        binary scan [debug read_block VRAM 0x3800 768] cu* b
        puts $f $b; close $f
    }
}
