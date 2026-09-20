set ::cc_dir "C:/Users/roniv/Dev/github/MSXPi/Documents/loader-handover"
proc cc_poll {} {
    set f "$::cc_dir/cmd.tcl"
    if {[file exists $f]} {
        set h [open $f r]; set c [read $h]; close $h
        file delete $f
        if {[catch {uplevel #0 $c} r]} { set r "ERROR: $r" }
        set h [open "$::cc_dir/res.tmp" w]; puts -nonewline $h $r; close $h
        file rename -force "$::cc_dir/res.tmp" "$::cc_dir/res.txt"
    }
    after realtime 0.2 cc_poll
}
cc_poll
