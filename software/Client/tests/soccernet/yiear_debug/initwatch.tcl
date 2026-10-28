# EXTRA_TCL for run_yiear.sh SCENARIO=both: does the game start under the TCP/IP transport, and what resets the machine?
# Logs to $TRACE.init: the game's INIT (4010h), its first interrupts, the stub's first bytes, and the PC that led to a reset (0000h).
set ::iw [open $::env(TRACE).init w]
proc iwSay {t} { puts $::iw [format "t=%.2f %s" [machine_info time] $t]; flush $::iw }
set ::hn 0
debug set_bp 0x4010 {[peek 0x4000] == 0x41 && [peek 0x4001] == 0x42 && [machine_info time] > 25} {
    iwSay [format "INIT SP=%04X stub C100=%s C500=%s A8=%02X" [reg SP] [join [lmap i {0 1 2 3 4 5} {format %02X [peek [expr {0xC100 + $i}]]}] ""] [join [lmap i {0 1 2 3 4 5} {format %02X [peek [expr {0xC500 + $i}]]}] ""] [debug read ioports 0xA8]]
}
debug set_bp 0x4043 {[peek 0x4000] == 0x41 && [peek 0x4001] == 0x42 && [machine_info time] > 25} {
    incr ::hn
    if {$::hn <= 3} { iwSay [format "handler #%d SP=%04X" $::hn [reg SP]] }
}
debug set_bp 0x0000 {$::hn > 0 || [machine_info time] > 22} { iwSay [format "reset: SP=%04X stack top=%s" [reg SP] [join [lmap i {0 1 2 3 4 5 6 7} {format %02X [peek [expr {[reg SP] + $i}]]}] " "]] }
# the text screen at the first reset (what PLAYNET printed before it gave up)
set ::shots 0
debug set_bp 0x0000 {[machine_info time] > 22 && $::shots < 2} {
    incr ::shots
    catch { foreach l [harness::screen_lines] { if {[string trim $l] ne ""} { iwSay "|$l" } } }
}
