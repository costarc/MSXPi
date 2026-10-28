# EXTRA_TCL for run_yiear.sh: what is on the screen (the strings are drawn into the name table at 3800h, 32 columns a row, in the
# game's own encoding: A-Z = 21h-3Ah, digits = 10h-19h, space = 00h). Every 15 ticks the rows where the extension prints are
# decoded and each distinct line is written once to $TRACE.vram with the tick, the game state and the rows' number.
# VRAM_ALSO=<script>: another EXTRA_TCL script to run as well (versus_test.tcl, turn_deaths.tcl).
if {[info exists ::env(VRAM_ALSO)]} { source $::env(VRAM_ALSO) }
set ::vf [open $::env(TRACE).vram w]
set ::vseen [dict create]
set ::vtk 0
proc vrow {r} {
    set s ""
    for {set c 0} {$c < 32} {incr c} {
        set b [vpeek [expr {0x3800 + $r * 32 + $c}]]
        if {$b == 0} { append s " " } elseif {$b >= 0x21 && $b <= 0x3A} { append s [format %c [expr {65 + $b - 0x21}]] } \
        elseif {$b >= 0x10 && $b <= 0x19} { append s [format %c [expr {48 + $b - 0x10}]] } else { append s "." }
    }
    return [string trim $s]
}
debug set_bp $::sym(tickDone) {} {
    incr ::vtk
    if {$::vtk % [expr {[info exists ::env(VRAM_EVERY)] ? $::env(VRAM_EVERY) : 15}] != 0} return
    set st [peek 0xE000]
    foreach r {2 3 13 14 15 17 19} {
        set line [vrow $r]
        if {$line eq "" || [regexp {^[. ]+$} $line]} continue
        set key "$st/$r/$line"
        if {![dict exists $::vseen $key]} {
            dict set ::vseen $key 1
            puts $::vf [format "tick %d state %d row %d: %s" $::vtk $st $r $line]
            flush $::vf
        }
    }
}
