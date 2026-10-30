# (Named *_rig.tcl, not *_node.tcl: kill_nodes.sh, which other rigs run at their start, stops every *node.tcl emulator.)
# One Bubble Bobble lockstep node over the MSXPi transport (PLAYNET.COM on B:, started without the chat:
# "PLAYNET bubble P1|P2"). Started by run_bubble.sh with -ext MSXPi -ext ram2mb; the harness boots MSX-DOS
# from the MSXPi server.
#   ROLEARG=P1|P2  TRACE=<file>  STOPF=<frame>  TMAX=<emulated s>  PLAYNET_SYMS=<stub symbols, Tcl>
#   STUB_BIN=<the stub>
#   EXITKEY=<frame>: P2 presses Ctrl+Shift+F5 there (the exit key); both games end, and with CHAT both players are
#   back in MCHAT (run_bubble.sh checks the MSXPi logs). Set STOPF above it.
# Trace: one line per game frame, "<frame> <P1 input> <P2 input> <sum and XOR of the words of D030h-E65Fh and EF80h-F2EFh> <banks of W0-W3>
# <page segments>", so cmp_pair.py can compare the two nodes frame by frame. The task stacks C000h-C94Fh and the main
# stack F2F0h-F37Fh are left out, and D063h-D064h (the scheduler's copy of SP): an interrupt that comes while a frame waits for the network pushes there, at a
# different moment on each machine.
source $::env(PLAYNET_SYMS)
set roleArg $::env(ROLEARG)
set stopf   $::env(STOPF)
if {![info exists ::env(TMAX)]} { set ::env(TMAX) 900 }
foreach n {nf started PN_TICK tickDone MK_BLOCK mkBuild desync desyncF pnDelay} { set ::s_$n $sym($n) }
set ::builds 0
set tf [open $::env(TRACE) w]
set ::started 0
set ::ended 0
set ::pressed 0
set ::frames 0
set ::prevNf -1
set ::t0 0
expr {srand(([string equal $roleArg P1] ? 11 : 23) + 1000 * ([info exists ::env(SEED)] ? $::env(SEED) : 0))}

proc sumState {} {
    set d [debug read_block memory 0xD030 [expr {0xE660 - 0xD030}]]
    set d [string replace $d 0x33 0x34 "\0\0"]           ;# D063h: the scheduler's saved SP (an interrupt can nest deeper)
    append d [debug read_block memory 0xEF80 [expr {0xF2F0 - 0xEF80}]]
    binary scan $d iu* w                                ;# openMSX's Tcl has no zlib: a sum and an XOR of the words
    return [format %08X%08X [expr {[::tcl::mathop::+ {*}$w] & 0xFFFFFFFF}] [::tcl::mathop::^ {*}$w]]
}
proc npTick {} {
    global tf
    if {$::ended} { return }
    set nf [peek $::s_nf]
    if {$nf < $::prevNf} { incr ::frames 256 }
    set ::prevNf $nf
    set ::lastTick [machine_info time]
    set f [expr {$::frames + $nf}]
    set b $::s_MK_BLOCK
    puts $tf [format "%d %02X %02X %s %02X%02X%02X%02X %02X%02X" $f [peek $::sym(PN_P1)] [peek $::sym(PN_P2)] [sumState] \
        [peek [expr {$b + 4}]] [peek [expr {$b + 5}]] [peek [expr {$b + 6}]] [peek [expr {$b + 7}]] \
        [peek [expr {$b + 8}]] [peek [expr {$b + 9}]]]
    if {$f % 600 == 0} {
        puts $tf [format "# f=%d t=%.2f builds=%d segs=%d" $f [machine_info time] $::builds [peek [expr {$b + 10 + 32 + 3}]]]
        flush $tf
    }
    if {[info exists ::env(EXITKEY)] && $::env(EXITKEY) ne "" && $::roleArg eq "P2" && $f >= $::env(EXITKEY) && !$::pressed} {
        set ::pressed 1
        puts $tf "# exit key pressed at frame $f"
        keymatrixdown 6 0x03; keymatrixdown 7 0x02           ;# SHIFT + CTRL, F5
        after time 1 { keymatrixup 6 0x03; keymatrixup 7 0x02 }
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
        if {[peek $a] != [lindex $bytes [expr {$a - $::sym(PN_ORG)}]]} { return 0 }
    }
    return 1
}
proc waitStub {} {
    if {[stubHere] && [peek $::s_nf] == 0xFF && [peek $::s_started] == 0} {
        set ::started 1
        set ::t0 [machine_info time]
        set ::lastTick $::t0
        puts $::tf "# stub in place t=[format %.1f $::t0] block=[join [lmap i {0 1 2 3 4 5 6 7 8 9} {format %02X [peek [expr {$::s_MK_BLOCK + $i}]]}] {}]"
        flush $::tf
        debug set_bp $::s_tickDone {} { npTick }
        debug set_bp $::s_mkBuild {} { incr ::builds }
        schedule
        return
    }
    if {!$::started} { after time 0.05 waitStub }
}
# and at the game's INIT (4054h), in case the polling misses the moment (it did in the chat flow)
debug set_bp 0x4054 {!$::started} { if {[stubHere]} { waitStub } }
# with EXITKEY: once the ticks stop (the game ended), 40 s (BACKWAIT) for the way back (MCHAT), a screenshot, the end
set ::lastTick 0
proc npWatch {} {
    if {$::started && !$::ended && [machine_info time] - $::lastTick > 5} {
        set ::ended 1
        puts $::tf [format "# ticks stopped at frame %d t=%.1f PC=%04X" [expr {$::frames + [peek $::s_nf]}] [machine_info time] [reg PC]]
        flush $::tf
        after time [expr {[info exists ::env(BACKWAIT)] ? $::env(BACKWAIT) : 40}] { catch { screenshot $::env(TRACE).back.png }; puts $::tf "# back t=[format %.1f [machine_info time]]"; close $::tf; after time 1 exit }
        return
    }
    after time 1 npWatch
}
if {[info exists ::env(EXITKEY)] && $::env(EXITKEY) ne ""} { after time 30 npWatch }
proc npKey {row bit secs} {
    keymatrixdown $row [expr {1 << $bit}]
    after time $secs [list keymatrixup $row [expr {1 << $bit}]]
}
proc npAt {secs body} { after time $secs $body }
# Both players press random keys every half second from the first frame: cursors, space (trigger A) and GRAPH
# (trigger B). That gets through the title and the play select (1P or 2P START; in 1P the second player joins with
# a trigger, as on the cartridge) and plays.
proc schedule {} {
    npAt 2 npPlay
    foreach t {6 11 20 40 80 160 320} { npAt $t [list catch [list screenshot $::env(TRACE).$t.png]] }
}
proc npPlay {} {
    if {$::ended} { return }
    foreach b {0 4 5 6 7} { keymatrixup 8 [expr {1 << $b}] }
    keymatrixup 6 0x04
    set d [lindex {4 5 6 7 7 4 -1} [expr {int(rand() * 7)}]]
    if {$d >= 0} { keymatrixdown 8 [expr {1 << $d}] }
    if {rand() < 0.5} { npKey 8 0 0.2 }
    if {rand() < 0.3} { npKey 6 2 0.2 }
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
if {[info exists ::env(BOOT)] && $::env(BOOT) eq "nextor"} {
    # P2 over TCP/IP (run_bubble.sh TCP=1): Nextor, the tools in C:\PLAYNET
    harness::at_nextor_prompt {
        # RAMHELPR I reloads COMMAND2, which comes back on A:
        harness::run_cmd "C:" 10 { harness::run_cmd "CD PLAYNET" 10 { harness::run_cmd "RAMHELPR I" 30 {
            harness::run_cmd "C:" 10 { harness::run_cmd "ETHUNAPI" 30 { harness::run_cmd "INL I" 90 {
                if {[info exists ::env(CHAT)] && $::env(CHAT) ne ""} {
                    # links 1 and 2 from the chat: MCHAT /T, alice invites bob, the chat types PLAYNET itself
                    if {$::roleArg eq "P1"} {
                        type "MCHAT /1 /T alice\r"
                        after time $::env(PLAY_AT) { type "/play bob bubble\r" }
                    } else {
                        type "MCHAT /1 /T bob\r"
                        after time $::env(ACCEPT_AT) { type "/accept\r" }
                    }
                } elseif {[info exists ::env(CMD)] && $::env(CMD) ne ""} { type "$::env(CMD)\r" } else { type "PLAYNET /T bubble $::roleArg 5102 10.0.2.2:5101\r" }
                after time 3 waitStub
            } } } } } }
    }
} elseif {[info exists ::env(CHAT)] && $::env(CHAT) ne ""} {
    # the full player flow: MCHAT, P1 (alice) invites P2 (bob), the chat types PLAYNET itself
    harness::at_dos_prompt {
        harness::run_cmd "B:" 30 {
            if {$::roleArg eq "P1"} {
                type "MCHAT /1 alice\r"
                after time $::env(PLAY_AT) { type "/play bob bubble\r" }
            } else {
                type "MCHAT /1 bob\r"
                after time $::env(ACCEPT_AT) { type "/accept\r" }
            }
            after time 3 waitStub
        }
    } 200
} else {
    harness::at_dos_prompt {
        harness::run_cmd "B:" 30 {
            type "PLAYNET bubble $::roleArg\r"
            after time 3 waitStub
        }
    } 200
}
after time $::env(TMAX) { puts $tf "# timeout nf=[peek $::s_nf] started=$::started PC=[format %04X [reg PC]]"; close $tf; exit }
