# The mapper-ram ROM load (mLoad): at each chunk (mAt, right after the read and the CRC), the 2 KB in BOUNCE compared
# with the ROM file at mOff; at the end, the CRC. EXTRA_TCL; needs ROMFILE (the ROM) and PLAYNET's symbols from
# software/Client/src/playnet/build/playnet.sym (BOUNCE 3400h, mAt, mOff, mLoad.done: edit when they move).
# Output: <trace>.romread. Breakpoints are gated on the code being PLAYNET's (the bytes at mAt, from PLAYNET=the .COM).
set ::rrBounce 0x3400; set ::rrAt 0x263B; set ::rrOff 0x27C0; set ::rrDone 0x2628; set ::rrCrc 0x221A; set ::rrSrc 0x2189
set ::rro [open "$::env(TRACE).romread" w]
set f [open $::env(ROMFILE) rb]; set ::rrRom [read $f]; close $f
set ::rrBad 0
set ::rrSig ""
proc rrOk {} { expr {[peek 0x0005] == 0xC3 && [string length $::rrSig] && [debug read_block memory $::rrAt 4] eq $::rrSig} }
proc rrChunk {} {
    set off [expr {[peek $::rrOff] + 256 * [peek [expr {$::rrOff + 1}]] + 65536 * [peek [expr {$::rrOff + 2}]]}]
    set have [debug read_block memory $::rrBounce 2048]
    set want [string range $::rrRom $off [expr {$off + 2047}]]
    if {$have ne $want} {
        binary scan $have cu* h; binary scan $want cu* w
        set n 0; set first -1
        for {set i 0} {$i < 2048} {incr i} { if {[lindex $h $i] != [lindex $w $i]} { incr n; if {$first < 0} { set first $i } } }
        puts $::rro [format "chunk %05X: %d bytes differ, first at +%03X have %s want %s t=%.3f" $off $n $first \
            [join [lmap x [lrange $h $first [expr {$first + 15}]] {format %02X $x}] ""] \
            [join [lmap x [lrange $w $first [expr {$first + 15}]] {format %02X $x}] ""] [machine_info time]]
        incr ::rrBad
    } elseif {$off % 0x4000 == 0} { puts $::rro [format "chunk %05X ok" $off] }
    flush $::rro
}
proc rrArm {} {
    debug set_bp $::rrAt {[rrOk]} rrChunk
    debug set_bp $::rrDone {[rrOk]} { puts $::rro [format "done crc %s want %s bad=%d" [join [lmap i {0 1 2 3} {format %02X [peek [expr {$::rrCrc + $i}]]}] ""] [join [lmap i {0 1 2 3} {format %02X [peek [expr {$::rrSrc + $i}]]}] ""] $::rrBad]; flush $::rro }
}
# the signature: PLAYNET.COM's own bytes at mAt (PLAYNET env: the .COM)
set f [open $::env(PLAYNET) rb]; set c [read $f]; close $f
set ::rrSig [string range $c [expr {$::rrAt - 0x100}] [expr {$::rrAt - 0x100 + 3}]]
rrArm
