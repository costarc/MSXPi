# The hand-off from MCHAT to PLAYNET (EXTRA_TCL, chat scenarios): when PLAYNET.COM starts (its first bytes at 0100h,
# PNCOM = the file), the page-1 segment and slot then, and from 2 s before the start onwards the first 400 writes
# to the MSXPi ports 56h/5Ah with PC and SP. Output: <trace>.launch
set ::lo [open "$::env(TRACE).launch" w]
set f [open $::env(PNCOM) rb]; set ::pnHead [read $f 8]; close $f
set ::ln 0
set ::seen 0
proc lnW {} {
    if {[incr ::ln] > 400} return
    puts $::lo [format "t=%.4f out %02X=%02X PC=%04X SP=%04X [0100]=%s" [machine_info time] $::wp_last_address $::wp_last_value \
        [reg PC] [reg SP] [expr {[debug read_block memory 0x100 8] eq $::pnHead ? "PLAYNET" : "other"}]]
    if {$::ln % 50 == 0} { flush $::lo }
}
proc lnStart {} {
    if {$::seen} return
    set ::seen 1
    puts $::lo [format "PLAYNET start t=%.4f SP=%04X A8=%02X FFFF=%02X" [machine_info time] [reg SP] [debug read ioports 0xA8] [expr {[peek 0xFFFF] ^ 0xFF}]]
    flush $::lo
}
# arm the port log once the chat has been up a while (the launch follows the accept)
after time [expr {$::env(ACCEPT_AT) + 20}] { debug set_watchpoint write_io {0x56 0x5A} {} lnW }
debug set_bp 0x0100 {[debug read_block memory 0x100 8] eq $::pnHead} lnStart
after time [expr {$::env(ACCEPT_AT) + 120}] { puts $::lo "end"; close $::lo }
