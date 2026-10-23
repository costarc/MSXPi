# One Salamander lockstep node over the MSXPi transport (PLAYNET.COM on B:, started without the chat:
# "PLAYNET salamand P1|P2"). Started by run_salamander.sh with -ext MSXPi -ext ram2mb; the harness boots MSX-DOS
# from the MSXPi server.
#   ROLEARG=P1|P2  TRACE=<file>  STOPF=<frame>  TMAX=<emulated s>  PLAYNET_SYMS=<stub symbols, Tcl>
#   STUB_BIN=<the stub>  MENU=dual|single (P1 picks DUALPLAY or 1PLAYER)
# Trace: one line per game frame, "<frame> <E200h> <E202h> <sum of E300h-E4FFh> <banks of W0-W3> <page segments>",
# so cmp_pair.py can compare the two nodes frame by frame.
source $::env(PLAYNET_SYMS)
set roleArg $::env(ROLEARG)
set stopf   $::env(STOPF)
if {![info exists ::env(TMAX)]} { set ::env(TMAX) 900 }
if {![info exists ::env(MENU)]} { set ::env(MENU) dual }
foreach n {nf started PN_TICK tickDone MK_BLOCK mkBuild desync desyncF pnDelay} { set ::s_$n $sym($n) }
set ::builds 0
set tf [open $::env(TRACE) w]
set ::started 0
set ::ended 0
set ::frames 0
set ::prevNf -1
set ::t0 0
expr {srand(([string equal $roleArg P1] ? 11 : 23) + 1000 * ([info exists ::env(SEED)] ? $::env(SEED) : 0))}

proc sum512 {} {
    binary scan [debug read_block memory 0xE300 512] cu* bytes
    set s 0
    foreach b $bytes { set s [expr {($s * 31 + $b) & 0xFFFFFF}] }
    return [format %06X $s]
}
proc npTick {} {
    global tf
    if {$::ended} { return }
    set nf [peek $::s_nf]
    if {$nf < $::prevNf} { incr ::frames 256 }
    set ::prevNf $nf
    set f [expr {$::frames + $nf}]
    set b $::s_MK_BLOCK
    puts $tf [format "%d %02X %02X %s %02X%02X%02X%02X %02X%02X" $f [peek 0xE200] [peek 0xE202] [sum512] \
        [peek [expr {$b + 4}]] [peek [expr {$b + 5}]] [peek [expr {$b + 6}]] [peek [expr {$b + 7}]] \
        [peek [expr {$b + 8}]] [peek [expr {$b + 9}]]]
    if {$f % 600 == 0} {
        puts $tf [format "# f=%d t=%.2f builds=%d segs=%d" $f [machine_info time] $::builds [peek [expr {$b + 10 + 32 + 3}]]]
        flush $tf
    }
    if {$f >= $::stopf} {
        puts $tf "# end desync=[peek $::s_desync] desyncF=[peek $::s_desyncF] delay=[peek $::s_pnDelay] t=[format %.1f [machine_info time]] builds=$::builds"
        close $tf
        set ::ended 1
        catch { screenshot $::env(TRACE).end.png }
        after time 1 exit
    }
}
# the stub is in place (its code matches the built stub) and no tick has run yet
proc stubHere {} {
    set f [open $::env(STUB_BIN) rb]; set img [read $f]; close $f
    binary scan $img cu* bytes
    for {set a $::s_PN_TICK} {$a < $::s_PN_TICK + 24} {incr a} {
        if {[peek $a] != [lindex $bytes [expr {$a - 0xD000}]]} { return 0 }
    }
    return 1
}
proc waitStub {} {
    if {[stubHere] && [peek $::s_nf] == 0xFF && [peek $::s_started] == 0} {
        set ::started 1
        set ::t0 [machine_info time]
        puts $::tf "# stub in place t=[format %.1f $::t0] block=[join [lmap i {0 1 2 3 4 5 6 7 8 9} {format %02X [peek [expr {$::s_MK_BLOCK + $i}]]}] {}]"
        flush $::tf
        debug set_bp $::s_tickDone {} { npTick }
        debug set_bp $::s_mkBuild {} { incr ::builds }
        schedule
        return
    }
    after time 0.05 waitStub
}
proc npKey {row bit secs} {
    keymatrixdown $row [expr {1 << $bit}]
    after time $secs [list keymatrixup $row [expr {1 << $bit}]]
}
proc npAt {secs body} { after time $secs $body }
# P1: the PLAY SELECT menu (cursor keys and space, as on the cartridge), then both players fly: random
# directions and fire, every half second.
proc schedule {} {
    if {$::roleArg eq "P1"} {
        if {$::env(MENU) eq "dual"} {
            npAt 9.0  { npKey 8 6 0.15 }
            npAt 9.6  { npKey 8 6 0.15 }
        }
        npAt 10.4 { npKey 8 0 0.15 }
    }
    npAt 13 npPlay
    foreach t {6 11 20 40 80 160} { npAt $t [list catch [list screenshot $::env(TRACE).$t.png]] }
}
proc npPlay {} {
    if {$::ended} { return }
    foreach b {4 5 6 7} { keymatrixup 8 [expr {1 << $b}] }
    set d [lindex {4 5 6 7 7 7} [expr {int(rand() * 6)}]]
    keymatrixdown 8 [expr {1 << $d}]
    npKey 8 0 0.2
    after time 0.5 npPlay
}
proc dumpscreen {} {
    after time 20 dumpscreen
    set fh [open "$::env(TRACE).screen" a]
    puts $fh "---- t=[expr {int([machine_info time])}] PC=[format %04X [reg PC]] SP=[format %04X [reg SP]] nf=[format %02X [peek $::s_nf]] started=$::started"
    catch { foreach l [harness::screen_lines] { if {[string trim $l] ne ""} { puts $fh "|$l" } } }
    close $fh
}
after time 20 dumpscreen
harness::init "np_$roleArg"
harness::at_dos_prompt {
    harness::run_cmd "B:" 30 {
        type "PLAYNET salamand $::roleArg\r"
        after time 3 waitStub
    }
} 200
after time $::env(TMAX) { puts $tf "# timeout nf=[peek $::s_nf] started=$::started PC=[format %04X [reg PC]]"; close $tf; exit }
