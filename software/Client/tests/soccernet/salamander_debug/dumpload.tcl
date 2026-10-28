# When "Loading the ROM" shows: 2400h-27FFh (PLAYNET's mapper-ram loader) and 4000h-43FFh (its copy, PLAYNET /T)
# into <trace>.m2400 and <trace>.m4000, to compare with PLAYNET.COM (offset 2300h). EXTRA_TCL.
proc dlWait {} {
    if {![catch {set l [harness::screen_lines]}] && [string match "*Loading the ROM*" [join $l]]} {
        foreach {a n} {0x2400 m2400 0x4000 m4000} {
            set f [open "$::env(TRACE).$n" wb]; puts -nonewline $f [debug read_block memory $a 1024]; close $f
        }
        return
    }
    after time 0.05 dlWait
}
dlWait
