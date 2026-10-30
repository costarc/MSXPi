# One Penguin-kun Wars 2 lockstep node over the MSXPi transport (PLAYNET.COM on B:, started without the chat:
# "PLAYNET pwars2 P1|P2", or from MCHAT with CHAT). Started by run_pwars2.sh with -ext MSXPi -ext ram2mb; the
# harness boots MSX-DOS from the MSXPi server. With BOOT=nextor (run_pwars2.sh TCP=1) the node boots Nextor and plays
# over the TCP/IP UNAPI (PLAYNET /T, or MCHAT /T with CHAT).
#   ROLEARG=P1|P2  TRACE=<file>  STOPF=<tick>  TMAX=<emulated s>  PLAYNET_SYMS=<stub symbols, Tcl>  STUB_BIN=<the stub>
#   EXITKEY=<tick>: P2 presses Ctrl+Shift+F5 there (the exit key); both games end, and with CHAT both players are
#   back in MCHAT (run_pwars2.sh checks the MSXPi logs). Set STOPF above it.
# Bots: P1 starts the game (space), walks up the map to the first house, and in a match walks to the nearest free
# ball on its side, picks it up, charges and throws; P2 does the same with the opponent (player 2's in versus).
# Trace: one line per TICK, "<tick> <state of the opponent> <of the penguin> <sum of B000h-B1FFh> <page-1 bank>",
# so cmp_pair.py can compare the two nodes tick by tick.
source $::env(PLAYNET_SYMS)
set roleArg $::env(ROLEARG)
set stopf   $::env(STOPF)
if {![info exists ::env(TMAX)]} { set ::env(TMAX) 900 }
foreach n {nf started PN_TICK tickDone tickInc MK_BLOCK desync desyncF pnDelay PN_ORG} { set ::s_$n $sym($n) }
set tf [open $::env(TRACE) w]
set ::started 0
set ::ended 0
set ::pressed 0
set ::frames 0
set ::prevNf -1
set ::t0 0
set ::matchAt -10

proc sum512 {} {
    binary scan [debug read_block memory 0xB000 512] cu* bytes
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
    set ::lastTick [machine_info time]
    set f [expr {$::frames + $nf}]
    puts $tf [format "%d %02X %02X %s %02X" $f [peek 0xB134] [peek 0xB10B] [sum512] [expr {[peek [expr {$::s_MK_BLOCK + 4}]] >> 1}]]
    if {$f % 600 == 0} {
        puts $tf [format "# f=%d t=%.2f" $f [machine_info time]]
        flush $tf
    }
    if {[info exists ::env(EXITKEY)] && $::env(EXITKEY) ne "" && $::roleArg eq "P2" && $f >= $::env(EXITKEY) && !$::pressed} {
        set ::pressed 1
        puts $tf "# exit key pressed at frame $f"
        keymatrixdown 6 0x03; keymatrixdown 7 0x02           ;# SHIFT + CTRL, F5
        after time 1 { keymatrixup 6 0x03; keymatrixup 7 0x02 }
    }
    if {$f >= $::stopf} {
        puts $tf "# end desync=[peek $::s_desync] desyncF=[peek $::s_desyncF] delay=[peek $::s_pnDelay] t=[format %.1f [machine_info time]]"
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
        if {[peek $a] != [lindex $bytes [expr {$a - $::s_PN_ORG}]]} { return 0 }
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
        debug set_bp $::s_tickInc {} { set ::matchAt [machine_info time] }
        schedule
        return
    }
    after time 0.05 waitStub
}
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
proc keys {left right up space} {
    foreach {on bit} [list $left 0x10 $right 0x80 $up 0x20 $space 0x01] {
        if {$on} { keymatrixdown 8 $bit } else { keymatrixup 8 $bit }
    }
}
# free balls (record +7 = FFh) on a side: 1 the penguin's (y >= 80h), 2 the opponent's -> their x
proc ballsOn {side} {
    set r {}
    for {set i 0} {$i < 10} {incr i} {
        set b [expr {0xB000 + 16 * $i}]
        if {[peek [expr {$b + 7}]] != 0xFF} continue
        set y [peek [expr {$b + 2}]]
        if {($side == 1 && $y >= 0x80) || ($side == 2 && $y < 0x80)} { lappend r [peek [expr {$b + 1}]] }
    }
    return $r
}
set ::tog 0
set ::hold 0
proc bot {} {
    if {$::ended} { return }
    after time 0.1 bot
    set ::tog [expr {!$::tog}]
    set inMatch [expr {[machine_info time] - $::matchAt < 0.5}]
    if {!$inMatch} {
        # menus and the map are P1's: up (the map's road to the first house) and space now and then
        if {$::roleArg eq "P1"} {
            set bank [expr {[peek [expr {$::s_MK_BLOCK + 4}]] >> 1}]
            keys 0 0 [expr {$bank == 9}] [expr {int([machine_info time] * 10) % 15 < 2}]
        } else { keys 0 0 0 0 }
        return
    }
    if {$::roleArg eq "P1"} {
        set st [peek 0xB10B]; set x [peek 0xB101]; set aim -20; set side 1
        set holding [expr {$st == 0x50 || $st == 0x10 || $st == 0x20}]
    } else {
        set st [peek 0xB134]; set x [peek 0xB121]; set aim [expr {-[peek 0xB129] / 2}]; set side 2
        set holding [expr {$st == 0x30}]
    }
    if {$st == 0} {
        set bs [ballsOn $side]
        if {![llength $bs]} { keys 0 0 0 0; return }
        set best [lindex $bs 0]
        foreach b $bs { if {abs($b + $aim - $x) < abs($best + $aim - $x)} { set best $b } }
        set d [expr {$best + $aim - $x}]
        if {$d > 6} { keys 0 1 0 0 } elseif {$d < -6} { keys 1 0 0 0 } else { keys 0 0 0 $::tog }
        set ::hold 0
    } elseif {$holding} {
        incr ::hold
        if {$::roleArg eq "P1"} { keys 0 0 0 [expr {$::hold < 8}] } else { keys 0 0 0 [expr {$::hold > 6 && $::tog}] }
        if {$::hold > 12} { set ::hold 0 }
    } else { keys 0 0 0 0 }
}
proc schedule {} {
    after time 2 bot
    foreach t {6 20 40 80 160 300} { after time $t [list catch [list screenshot $::env(TRACE).$t.png]] }
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
    # P2 over TCP/IP (run_1942.sh TCP=1): Nextor, the tools in C:\PLAYNET
    harness::at_nextor_prompt {
        # RAMHELPR I reloads COMMAND2, which comes back on A:
        harness::run_cmd "C:" 10 { harness::run_cmd "CD PLAYNET" 10 { harness::run_cmd "RAMHELPR I" 30 {
            harness::run_cmd "C:" 10 { harness::run_cmd "ETHUNAPI" 30 { harness::run_cmd "INL I" 90 {
                if {[info exists ::env(CHAT)] && $::env(CHAT) ne ""} {
                    # links 1 and 2 from the chat: MCHAT /T, alice invites bob, the chat types PLAYNET itself
                    if {$::roleArg eq "P1"} {
                        type "MCHAT /1 /T alice\r"
                        after time $::env(PLAY_AT) { type "/play bob pwars2\r" }
                    } else {
                        type "MCHAT /1 /T bob\r"
                        after time $::env(ACCEPT_AT) { type "/accept\r" }
                    }
                } elseif {[info exists ::env(CMD)] && $::env(CMD) ne ""} { type "$::env(CMD)\r" } else { type "PLAYNET /T pwars2 $::roleArg 5142 10.0.2.2:5141\r" }
                after time 3 waitStub
            } } } } } }
    }
} elseif {[info exists ::env(CHAT)] && $::env(CHAT) ne ""} {
    # the full player flow: MCHAT, P1 (alice) invites P2 (bob), the chat types PLAYNET itself
    harness::at_dos_prompt {
        harness::run_cmd "B:" 30 {
            if {$::roleArg eq "P1"} {
                type "MCHAT /1 alice\r"
                after time $::env(PLAY_AT) { type "/play bob pwars2\r" }
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
            type "PLAYNET pwars2 $::roleArg\r"
            after time 3 waitStub
        }
    } 200
}
after time $::env(TMAX) { puts $tf "# timeout nf=[peek $::s_nf] started=$::started PC=[format %04X [reg PC]]"; close $tf; exit }
