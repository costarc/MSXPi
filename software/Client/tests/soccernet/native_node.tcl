# One lockstep node. The "network" is a pair of files; this script is the
# transport: it moves packets between the stub's mailboxes and the files, with
# optional delay (emulated seconds) and loss (percent) on the way IN.
#   ROLEARG=H|C  START=<s>  OUT=<file> IN=<file> TRACE=<file>
#   LAG=<s> DROP=<pct> STOPF=<frame>
# One lockstep node over the MSXPi-native transport (SOCNAT.COM on B:).
# The machine is started by the caller with -ext MSXPi; the harness (-script harness.tcl)
# boots DOS from the MSXPi server. Network = the two servers (msxpi_server_np.py).
#   ROLEARG=H|C  TRACE=<file>  STOPF=<frame>  TMAX=<emulated s>
# SOCCERNET_SRC = software/Client/src/soccernet (stub_nat.bin), SOCCERNET_BUILD = its build/ folder
set srcerr [catch {source $::env(SOCCERNET_BUILD)/stub_syms_nat.tcl} srcmsg]
set roleArg $::env(ROLEARG)
set stopf   $::env(STOPF)
set lag 0; set drop 0; set start 0
if {![info exists ::env(TMAX)]} { set ::env(TMAX) 900 }
foreach n {stubEnd desync desyncF delay stState dead nf txbuf rxbuf cur1 cur2 recv haveRem remTag remVal ownVal rxSeen tickDone pad1c} { set ::s_$n $sym($n) }
set tx $::s_txbuf
set rx $::s_rxbuf
set ::poked 0
set lastTx 0
set inPos 0
set started 0
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
    set f [open $::env(SOCCERNET_SRC)/stub_nat.bin rb]; set img [read $f]; close $f
    binary scan $img c* bytes
    set n [expr {$::s_nf - $::s_pad1c}]
    set d {}
    for {set i 0} {$i < $n} {incr i} {
        if {[peek [expr {$::s_pad1c + $i}]] != ([lindex $bytes $i] & 255)} { lappend d [format %X $i] }
    }
    return $d
}
proc line {} {
    global tf sym started frames prevNf stopf
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
    if {$f >= $stopf} {
        global sent dropped got
        puts $tf "# desync=[peek $::s_desync] desyncF=[peek $::s_desyncF] delay=[peek $::s_delay] state=[peek $::s_stState] lowest_write_above_stub=[format %04X $::minw]"
        close $tf
        exit
    }
}

# one record per completed network tick: the inputs the game will be given
proc tlog {} {
    global tlf tickN
    set nf [peek $::s_nf]
    set f $nf
    puts $tlf "$tickN [format %02X $nf] rem=[format %02X [peek [expr {$::s_remVal + ($nf & 15)}]]] own=[format %02X [peek [expr {$::s_ownVal + ($nf & 15)}]]] rxbuf=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10} {format %02X [peek [expr {$::s_rxbuf + $i}]]}] {}]"
    if {($nf & 31) == 0} {
        set h ""
        for {set i 0} {$i < 512} {incr i} { append h [format %02X [peek [expr {0xE100 + $i}]]] }
        puts $tlf "REGION nf=$nf $h"
    }
    incr tickN
    if {$tickN % 50 == 0} { flush $tlf }
}
# diagnostic: how deep does the stack go? Lowest address written above the stub.
set ::minw 0xFFFF
proc minw {} {
    if {[catch {set a $::wp_last_address} e]} { return }
    if {$a < $::minw} { set ::minw $a }
}
# does game code (PC 4000-BFFF) ever write into ED30-F174, where the stub lives?
set ::gw 0
proc gwlog {} {
    global tf
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
    if {[peek $::s_pad1c] == 0x3A && [peek $::s_nf] == 0xFF && [peek $::s_txbuf] == 0 && [peek [expr {$::s_txbuf + 1}]] == 0 && [peek $::s_rxbuf] == 0} {
        set started 1
        debug set_bp $::s_tickDone {} { tlog }
        debug set_watchpoint write_mem [list $::s_stubEnd 0xF37F] {} { minw }
        debug set_watchpoint write_mem {0xED30 0xF174} {[reg PC] >= 0x4000 && [reg PC] < 0xC000} { gwlog }
        debug set_watchpoint write_mem 0xE003 {[reg PC] == 0x40CC || [reg PC] == 0x40CB} { line }   ;# only the frame increment
        return
    }
    after time 0.002 arm
}

proc dumpscreen {} {
    after time 20 dumpscreen
    set fh [open "$::env(TRACE).screen" a]
    puts $fh "---- t=[expr {int([machine_info time])}] PC=[format %04X [reg PC]] SP=[format %04X [reg SP]] nf=[format %02X [peek $::s_nf]] f000=[format %02X [peek 0xF000]] scene=[peek 0xE000] ie=[debug read {CPU regs} 0x10] st=[peek $::s_stState] dl=[peek $::s_delay] dead=[peek $::s_dead]"
    catch { foreach l [harness::screen_lines] { if {[string trim $l] ne ""} { puts $fh "|$l" } } }
    close $fh
}
after time 20 dumpscreen
after time 60 { catch { screenshot $::env(TRACE).png } }
harness::init "np_$roleArg"
harness::at_dos_prompt {
    harness::run_cmd "B:" 30 {
        type "$::env(PROG) $::roleArg\r"
        after time 3 arm
    }
} 200
after time $::env(TMAX) { puts $tf "# codeDiff=[codeDiff]"; puts $tf "# timeout  nfNow=[peek $::s_nf] rxSeen=[peek $::s_rxSeen] tags=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15} {format %02X [peek [expr {$::s_remTag + $i}]]}] ,] vals=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15} {format %02X [peek [expr {$::s_remVal + $i}]]}] ,] rxbuf=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10} {format %02X [peek [expr {$::s_rxbuf + $i}]]}] ""] PC=[format %04X [reg PC]]"; close $tf; exit }
