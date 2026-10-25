# One openMSX run for tpatop.sh: boot to the prompt, run the ";"-separated commands in SEQ, and after each TPATOP
# record the "TPATOP=xxxx" line the screen shows. Result: $MSXPI_HARNESS_OUT.top (one line per TPATOP).
#   SEQ=<cmds>  BOOT=nextor|dos
harness::init "tpatop"
# HOLD_CTRL=1: CTRL held down while MSX-DOS 1 boots (the kernel then leaves out the second drive and frees its buffers)
if {[info exists ::env(HOLD_CTRL)] && $::env(HOLD_CTRL) ne ""} {
    keymatrixdown 6 0x02
    after time [expr {[info exists ::env(HOLD_CTRL_S)] ? $::env(HOLD_CTRL_S) : 8}] { keymatrixup 6 0x02 }
}
set ::tops {}
proc finish {} {
    set fh [open "$::env(MSXPI_HARNESS_OUT).top" w]
    foreach t $::tops { puts $fh $t }
    close $fh
    set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
    foreach l [harness::screen_lines] { puts $fh "|$l" }
    close $fh
    harness::done
}
proc step {cmds done} {
    if {[llength $cmds] == 0} { finish; return }
    set c [lindex $cmds 0]
    harness::run_cmd $c 90 [list apply {{c rest done} {
        lappend done $c
        set fh [open "$::env(MSXPI_HARNESS_OUT).step[llength $done]" w]
        foreach l [harness::screen_lines] { puts $fh "|$l" }
        close $fh
        if {[string match -nocase "TPATOP*" $c]} {
            set last none
            foreach l [harness::screen_lines] {
                if {[regexp {TPATOP=([0-9A-F]{4})} $l -> v]} { set last $v }
            }
            lappend ::tops "[join $done {,}] $last"
        }
        step $rest $done
    }} $c [lrange $cmds 1 end] $done]
}
set ::seq [split $::env(SEQ) ";"]
set body {step $::seq {}}
if {[info exists ::env(BOOT)] && $::env(BOOT) eq "nextor"} {
    harness::at_nextor_prompt $body
} else {
    harness::at_dos_prompt $body
}
# progress for a run that never reaches finish: the screen at emulated 40 s and 120 s
foreach t {40 100 140 180 240} {
    after time $t [list apply {{t} {
        set fh [open "$::env(MSXPI_HARNESS_OUT).t$t" w]
        foreach l [harness::screen_lines] { puts $fh "|$l" }
        close $fh
    }} $t]
}
