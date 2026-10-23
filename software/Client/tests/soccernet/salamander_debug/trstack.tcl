# How deep the trampoline's stack goes (it ends at TRAMP_SP = C100h): every write to C000h-C0FFh made while SP is
# in that page, with PC and SP: ENASLT, INIT32 and the interrupts they let through. EXTRA_TCL (and EXTRA_TCL_C).
# Output: <trace>.trstack, a "low" line each time a deeper byte is written.
set ::tso [open "$::env(TRACE).trstack" w]
set ::tsLo 0x10000
set ::tsN 0
proc tsW {} {
    set a $::wp_last_address
    if {$a < $::tsLo} { set ::tsLo $a; puts $::tso [format "low %04X PC=%04X SP=%04X iff=%s t=%.5f" $a [reg PC] [reg SP] [reg iff] [machine_info time]]; flush $::tso }
    if {[incr ::tsN] <= 300} { puts $::tso [format "W %04X v=%02X PC=%04X SP=%04X iff=%s" $a $::wp_last_value [reg PC] [reg SP] [reg iff]] }
}
debug set_watchpoint write_mem {0xC000 0xC0FF} {[reg SP] <= 0xC100 && [reg SP] > 0xC000} tsW
