# One lockstep node. The "network" is a pair of files; this script is the
# transport: it moves packets between the stub's mailboxes and the files, with
# optional delay (emulated seconds) and loss (percent) on the way IN.
#   ROLEARG=H|C  START=<s>  OUT=<file> IN=<file> TRACE=<file>
#   LAG=<s> DROP=<pct> STOPF=<frame>
# One lockstep node over the MSXPi transport (PLAYNET.COM on B:, started without the chat: PROG="PLAYNET soccer").
# The machine is started by the caller with -ext MSXPi; the harness (-script harness.tcl)
# boots DOS from the MSXPi server. Network = the two servers (msxpi_server_np.py).
#   ROLEARG=H|C  TRACE=<file>  STOPF=<frame>  TMAX=<emulated s>
# PLAYNET_SYMS = the test stub's symbols (stub_syms.tcl, the stub itself beside it as stub_syms.bin)
set srcerr [catch {source $::env(PLAYNET_SYMS)} srcmsg]
set roleArg $::env(ROLEARG)
set stopf   $::env(STOPF)
set lag 0; set drop 0; set start 0
if {![info exists ::env(TMAX)]} { set ::env(TMAX) 900 }
foreach n {stubEnd desync desyncF pnDelay nf txbuf rxbuf remRing ownVal rxSeen tickDone pad1c started PN_TICK} { set ::s_$n $sym($n) }
set tx $::s_txbuf
set rx $::s_rxbuf
set ::poked 0
set lastTx 0
set inPos 0
set started 0
set ::ended 0
set ::pressed 0
set frames 0
set prevNf -1
set tf [open $::env(TRACE) w]
set tlf [open $::env(TRACE).ticks w]
set tickN 0
puts $tf "# source: $srcerr $srcmsg size=[array size ::sym]"
set armCount 0
set pollErrs 0
set junkLog 0
set polls 0
set sent 0; set dropped 0; set got 0

proc codeDiff {} {
    set f [open [file rootname $::env(PLAYNET_SYMS)].bin rb]; set img [read $f]; close $f
    binary scan $img c* bytes
    set d {}
    # the engine's code, from PN_TICK to its variables (the header's seat and delay are the loader's)
    for {set a $::s_PN_TICK} {$a < $::s_started} {incr a} {
        if {[peek $a] != ([lindex $bytes [expr {$a - 0xF000}]] & 255)} { lappend d [format %X $a] }
    }
    return $d
}
proc line {} {
    global tf sym started frames prevNf stopf
    if {$::ended} { return }
    set nf [peek $::s_nf]
    if {!$started} { return }
    if {$nf == 255 && $prevNf < 0} { return }   ;# INIT's RAM clear, before the first tick
    if {$nf < $prevNf} { incr frames 256 }
    set prevNf $nf
    set f [expr {$frames + $nf}]
    set b {}
    for {set i 0} {$i < 16} {incr i} { append b [format %02X [peek [expr {0xE2A0 + $i}]]] }
    puts $tf "$f [peek 0xE000] [peek 0xE001] $b [format %02X [peek 0xE52B]] [format %02X [peek 0xE007]] [format %02X [peek 0xE009]]"
    if {[info exists ::env(POKEF)] && $::roleArg eq "H" && $f >= $::env(POKEF) && !$::poked} { set ::poked 1; poke 0xE2A0 [expr {[peek 0xE2A0] ^ 0x10}]; puts $tf "# poked ball at frame $f" }
    if {[info exists ::env(EXITF)] && $::roleArg eq "C" && $f >= $::env(EXITF)} { exit }
    if {[info exists ::env(EXITKEY)] && $::roleArg eq "C" && $f >= $::env(EXITKEY) && !$::pressed} {
        set ::pressed 1
        puts $tf "# exit key pressed at frame $f"
        keymatrixdown 6 0x03; keymatrixdown 7 0x02           ;# SHIFT + CTRL, F5
        after time 1 { keymatrixup 6 0x03; keymatrixup 7 0x02 }
    }
    if {$f >= $stopf} {
        global sent dropped got
        puts $tf "# desync=[peek $::s_desync] desyncF=[peek $::s_desyncF] delay=[peek $::s_pnDelay] lowest_stack_write=[format %04X $::minw] foreign_writes=$::gw"
        close $tf
        exit
    }
}

# one record per completed network tick: the inputs the game will be given
proc tlog {} {
    global tlf tickN
    set nf [peek $::s_nf]
    set f $nf
    puts $tlf "$tickN [format %02X $nf] rem=[format %02X [peek [expr {$::s_remRing + ($nf & 15) * 3 + 1}]]] own=[format %02X [peek [expr {$::s_ownVal + ($nf & 15) * 2}]]] rxbuf=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21} {format %02X [peek [expr {$::s_rxbuf + $i}]]}] {}]"
    if {($nf & 31) == 0} {
        set h ""
        for {set i 0} {$i < 512} {incr i} { append h [format %02X [peek [expr {0xE100 + $i}]]] }
        puts $tlf "REGION nf=$nf $h"
    }
    incr tickN
    if {$tickN % 50 == 0} { flush $tlf }
}
# diagnostic: how deep does the stack go? Lowest address written in F200-F37F.
set ::minw 0xFFFF
proc minw {} {
    if {$::ended} { return }
    if {[catch {set a $::wp_last_address} e]} { return }
    if {$a < $::minw} { set ::minw $a }
}
# does anything but the stub and the transport write into C100-C5FF, where they live?
# is C000-DFFF ever written once the game runs (anyone: game, BIOS, interrupts)? Counts, and the first 10
set ::c0 0
set ::c0lo 0xFFFF
set ::c0hi 0
proc c0log {} {
    global tf
    set a 0
    catch {set a $::wp_last_address}
    incr ::c0
    if {$a < $::c0lo} { set ::c0lo $a }
    if {$a > $::c0hi} { set ::c0hi $a }
    if {$::c0 <= 10} { puts $tf [format "# C000WRITE pc=%04X addr=%04X" [reg PC] $a]; flush $tf }
}
set ::gw 0
proc gwlog {} {
    global tf
    if {$::ended} { return }
    if {$::gw >= 20} { return }
    incr ::gw
    set a ?
    catch {set a [format %04X $::wp_last_address]}
    puts $tf [format "# GAMEWRITE pc=%04X addr=%s scene=%d" [reg PC] $a [peek 0xE000]]
    flush $tf
}
proc arm {} {
    if {[catch {arm_ } err]} { global tf; puts $tf "# arm error: $err | exists=[info exists ::sym(nf)] size=[array size ::sym] names=[lrange [array names ::sym] 0 5] | $::errorInfo"; flush $tf }
}
proc arm_ {} {
    global sym started prevNf tf armCount
    incr armCount
    if {$armCount % 1000 == 1} { puts $tf "# arm pad1c=[format %02X [peek $::s_pad1c]] nf=[format %02X [peek $::s_nf]] PC=[format %04X [reg PC]]"; flush $tf }
    # the stub is in place and no tick has run yet: nf is still FF
    if {[peek $::s_pad1c] == 0x3A && [peek $::s_nf] == 0xFF && [peek $::s_started] == 0 && [peek $::s_txbuf] == 0x10} {
        set started 1
        debug set_bp $::s_tickDone {} { tlog }
        debug set_bp 0xC503 {!$::ended} { xendHit }
        debug set_watchpoint write_mem {0xF200 0xF37F} {} { minw }
        debug set_watchpoint write_mem {0xC100 0xC5FF} {[reg PC] < 0xC000 || [reg PC] >= 0xC700} { gwlog }
        debug set_watchpoint write_mem 0xE003 {[reg PC] == 0x40CC || [reg PC] == 0x40CB} { line }   ;# only the frame increment
        return
    }
    after time 0.002 arm
}

proc xendHit {} {
    global tf
    set ::ended 1
    puts $tf "# xend result=[reg A] frame=[expr {$::frames + [peek $::s_nf]}] desync=[peek $::s_desync] desyncF=[peek $::s_desyncF] delay=[peek $::s_pnDelay] lowest_stack_write=[format %04X $::minw] foreign_writes=$::gw"
    flush $tf
    after time 40 backCheck
}
# back at the MSX-DOS prompt (the loader typed MCHAT, which this disk may not have): the last lines
proc backCheck {} {
    global tf
    set lines {}
    foreach l [harness::screen_lines] { if {[string trim $l] ne ""} { lappend lines [string trim $l] } }
    puts $tf "# back: [join [lrange $lines end-3 end] { | }] (t=[expr {int([machine_info time])}])"
    close $tf
    after time 1 exit
}
proc dumpscreen {} {
    after time 20 dumpscreen
    set fh [open "$::env(TRACE).screen" a]
    puts $fh "---- t=[expr {int([machine_info time])}] PC=[format %04X [reg PC]] SP=[format %04X [reg SP]] nf=[format %02X [peek $::s_nf]] f000=[format %02X [peek 0xF000]] scene=[peek 0xE000] ie=[debug read {CPU regs} 0x10] dl=[peek $::s_pnDelay] started=[peek $::s_started]"
    catch { foreach l [harness::screen_lines] { if {[string trim $l] ne ""} { puts $fh "|$l" } } }
    close $fh
}
after time 20 dumpscreen
after time 60 { catch { screenshot $::env(TRACE).png } }
harness::init "np_$roleArg"
# PRE_<role>: commands run first, ";"-separated, each to the prompt (MSR I;INL I for a TCP/IP node);
# CMD_<role>: the start line instead of "$PROG <role>" (PLAYNET /T ... for a TCP/IP node)
proc runPre {cmds body} {
    if {![llength $cmds]} { uplevel #0 $body; return }
    harness::run_cmd [string trim [lindex $cmds 0]] 90 [list runPre [lrange $cmds 1 end] $body]
}
harness::at_dos_prompt {
    harness::run_cmd "B:" 30 {
        set pre {}
        if {[info exists ::env(PRE_$::roleArg)]} { set pre [split $::env(PRE_$::roleArg) ";"] }
        runPre $pre {
            if {[info exists ::env(CMD_$::roleArg)]} { type "$::env(CMD_$::roleArg)\r" } else { type "$::env(PROG) $::roleArg\r" }
            after time 3 arm
        }
    }
} 200
after time $::env(TMAX) { puts $tf "# codeDiff=[codeDiff]"; puts $tf "# timeout  nfNow=[peek $::s_nf] rxSeen=[peek $::s_rxSeen] tags=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15} {format %02X [peek [expr {$::s_remRing + $i * 3}]]}] ,] vals=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15} {format %02X [peek [expr {$::s_remRing + $i * 3 + 1}]]}] ,] rxbuf=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21} {format %02X [peek [expr {$::s_rxbuf + $i}]]}] ""] PC=[format %04X [reg PC]]"; close $tf; exit }
