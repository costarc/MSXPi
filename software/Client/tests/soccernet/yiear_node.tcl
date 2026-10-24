# One lockstep node. The "network" is a pair of files; this script is the
# transport: it moves packets between the stub's mailboxes and the files, with
# optional delay (emulated seconds) and loss (percent) on the way IN.
#   ROLEARG=P1|P2  START=<s>  OUT=<file> IN=<file> TRACE=<file>
#   LAG=<s> DROP=<pct> STOPF=<frame>
# One Yie Ar Kung-Fu lockstep node over the MSXPi transport (PLAYNET.COM on B:, started without the chat: PROG="PLAYNET yiear"); from native_node.tcl.
# The machine is started by the caller with -ext MSXPi; the harness (-script harness.tcl)
# boots DOS from the MSXPi server. Network = the two servers (msxpi_server_np.py).
#   ROLEARG=P1|P2  TRACE=<file>  STOPF=<frame>  TMAX=<emulated s>
# PLAYNET_SYMS = the test stub's symbols (stub_syms.tcl, the stub itself beside it as stub_syms.bin)
set srcerr [catch {source $::env(PLAYNET_SYMS)} srcmsg]
set roleArg $::env(ROLEARG)
set stopf   $::env(STOPF)
set lag 0; set drop 0; set start 0
if {![info exists ::env(TMAX)]} { set ::env(TMAX) 900 }
foreach n {stubEnd desync desyncF pnDelay nf txbuf rxbuf remRing ownVal rxSeen tickDone key1 started PN_TICK} { set ::s_$n $sym($n) }
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
        if {[peek $a] != ([lindex $bytes [expr {$a - 0xC100}]] & 255)} { lappend d [format %X $a] }
    }
    return $d
}

# ---- the player: Tcl key presses on the keyboard matrix (the cursor keys and space are the game's joystick 1 on row 8),
# chosen from the game's own state, so the same run drives every mode. MODE = the menu choice (0 Single, 1 Turn, 2 Versus),
# KEYSEED = the play seed. Row 8: bit 0 space, 4 left, 5 up, 6 down, 7 right; row 7 bit 6 = SELECT (the second button).
if {![info exists ::env(MODE)]} { set ::env(MODE) 0 }
if {![info exists ::env(KEYSEED)]} { set ::env(KEYSEED) 1 }
set ::keyMask 0
set ::keyMask7 0
set ::menuStep 0
set ::menuUntil 0
proc rnd {f} { return [expr {(($f * 1103515245 + 12345 + $::env(KEYSEED) * 7919 + ($::roleArg eq "P2" ? 99991 : 0)) >> 8) & 0xFFFF}] }
proc setKeys {m8 m7} {
    foreach {row old new} [list 8 $::keyMask $m8 7 $::keyMask7 $m7] {
        set up [expr {$old & ~$new}]; set dn [expr {$new & ~$old}]
        if {$up} { keymatrixup $row $up }
        if {$dn} { keymatrixdown $row $dn }
    }
    set ::keyMask $m8; set ::keyMask7 $m7
}
proc drive {f} {
    set st [peek 0xE000]; set sub [peek 0xE001]
    set m8 0; set m7 0
    if {$st != 9} { set ::menuStep 0 }
    if {$st == 1 || $st == 0 || $st == 2} {
        # the title or the demo: a tap on space now and then (player 1 only; the demo returns to the title by a key)
        if {$::roleArg eq "P1" && ($f % 90) < 4} { set m8 1 }
    } elseif {$st == 9} {
        if {$::roleArg eq "P1" && $sub > 0} {
            # the menu: tap down MODE times, then space; one tap = 4 frames down, 8 up
            set phase [expr {$f % 12}]
            if {$::menuStep < $::env(MODE)} {
                if {$phase < 4} { set m8 64 } elseif {$phase == 4 && $::menuLast != 4} { incr ::menuStep }
            } elseif {$phase < 4} { set m8 1 }
            set ::menuLast $phase
        }
    } elseif {$st == 5} {
        # a fight: a direction held for 6 frames at a time, the button or SELECT now and then
        set r [rnd [expr {$f / 6}]]
        set d [lindex {0 16 32 64 128 128 16 0 128 32} [expr {$r % 10}]]
        set m8 $d
        if {(($r >> 4) % 3) == 0 && ($f % 6) < 3} { set m8 [expr {$m8 | 1}] }
        if {(($r >> 6) % 7) == 0 && ($f % 6) < 3} { set m7 64 }
    }
    if {$m8 != $::keyMask || $m7 != $::keyMask7} { setKeys $m8 $m7 }
}
set ::menuLast -1

proc line {} {
    global tf sym started frames prevNf stopf
    if {$::ended} { return }
    set nf [peek $::s_nf]
    if {!$started} { return }
    if {$nf == 255 && $prevNf < 0} { return }   ;# INIT's RAM clear, before the first tick
    if {$nf < $prevNf} { incr frames 256 }
    set prevNf $nf
    set f [expr {$frames + $nf}]
    drive $f
    puts $tf "$f [peek 0xE000] [peek 0xE001] [peek 0xE054] [format %02X [peek 0xE00A]] [hash512]"
    if {[info exists ::env(POKEF)] && $::roleArg eq "P1" && $f >= $::env(POKEF) && !$::poked} { set ::poked 1; poke 0xE161 [expr {[peek 0xE161] ^ 0x10}]; puts $tf "# poked Oolong at frame $f" }
    if {[info exists ::env(EXITF)] && $::roleArg eq "P2" && $f >= $::env(EXITF)} { exit }
    if {[info exists ::env(EXITKEY)] && $::roleArg eq "P2" && $f >= $::env(EXITKEY) && !$::pressed} {
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

# a hash of the objects (E100h-E2FFh), as the engine's own check region
proc hash512 {} {
    binary scan [debug read_block memory 0xE100 512] cu* bytes
    set s 0
    foreach b $bytes { set s [expr {($s * 31 + $b) & 0xFFFFFF}] }
    return [format %06X $s]
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
# diagnostic: how deep does the stack go? Lowest address written in E200-E3FF (SP = E400h at INIT).
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
    if {$armCount % 1000 == 1} { puts $tf "# arm key1=[format %02X [peek $::s_key1]] nf=[format %02X [peek $::s_nf]] PC=[format %04X [reg PC]]"; flush $tf }
    # the stub is in place and no tick has run yet: nf is still FF
    if {[peek $::s_key1] == 0x3A && [peek $::s_nf] == 0xFF && [peek $::s_started] == 0 && [peek $::s_txbuf] == 0x10} {
        set started 1
        debug set_bp $::s_tickDone {} { tlog }
        debug set_bp 0xC503 {!$::ended} { xendHit }
        debug set_watchpoint write_mem {0xE200 0xE3FF} {} { minw }
        # the extension's own state (tMode .. tBlk, 2 * 23 + 6 bytes) is written by the extension (PC in page 2) on purpose
        debug set_watchpoint write_mem [list 0xC100 [expr {$::sym(tMode) - 1}]] {[reg PC] < 0xC000 || [reg PC] >= 0xC700} { gwlog }
        debug set_watchpoint write_mem [list [expr {$::sym(tBlk) + 46}] 0xC5FF] {[reg PC] < 0xC000 || [reg PC] >= 0xC700} { gwlog }
        debug set_bp $::s_tickDone {} { line }
        return
    }
    after time 0.002 arm
}

proc xendHit {} {
    global tf
    set ::ended 1
    puts $tf "# xend result=[reg A] frame=[expr {$::frames + [peek $::s_nf]}] desync=[peek $::s_desync] desyncF=[peek $::s_desyncF] delay=[peek $::s_pnDelay] lowest_stack_write=[format %04X $::minw] foreign_writes=$::gw"
    flush $tf
    if {[info exists ::env(CHAT)] && $::env(CHAT) ne ""} { after time 45 backShot } else { after time 40 backCheck }
}
# chat: MCHAT draws its own font, so after the return a screenshot, and run_yiear.sh checks the MSXPi's logs; MCHAT keeps its
# last line in its data: "Game with X ended (reason)", looked for in the CPU's view every 5 s
proc backShot {} {
    global tf
    catch { screenshot $::env(TRACE).back.png }
    puts $tf "# back: PC=[format %04X [reg PC]] t=[expr {int([machine_info time])}]"
    flush $tf
    resultLine 12
}
proc resultLine {n} {
    global tf
    set ram [debug read_block memory 0x0100 0xFE00]
    if {[regexp {Game with [^\u0000]{1,16} ended \([^\u0000]+\)} $ram line]} {
        puts $tf "# result line: $line"
    } elseif {$n > 0} {
        after time 5 [list resultLine [expr {$n - 1}]]
        return
    } else {
        puts $tf "# result line: none found"
    }
    close $tf
    after time 1 exit
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
    after time [expr {[info exists ::env(DUMP_EVERY)] ? $::env(DUMP_EVERY) : 20}] dumpscreen
    set fh [open "$::env(TRACE).screen" a]
    puts $fh "---- t=[expr {int([machine_info time])}] PC=[format %04X [reg PC]] SP=[format %04X [reg SP]] nf=[format %02X [peek $::s_nf]] scene=[peek 0xE000] ie=[debug read {CPU regs} 0x10] dl=[peek $::s_pnDelay] started=[peek $::s_started]"
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
if {[info exists ::env(CHAT)] && $::env(CHAT) ne ""} {
    # the players meet in the chat and the chat starts the game: NICK, OPPONENT, INVITE (1 on the inviter = P1), PLAY_AT / ACCEPT_AT
    set ::pre {}
    if {[info exists ::env(PRE_$::roleArg)]} { set ::pre [split $::env(PRE_$::roleArg) ";"] }
    set ::chatOpt ""
    if {[info exists ::env(CHAT_TCP)]} { set ::chatOpt "/T " }
    harness::at_dos_prompt {
        harness::run_cmd "B:" 30 {
          runPre $::pre {
            type "MCHAT /1 $::chatOpt$::env(NICK)[format %c 13]"
            after time 3 arm
            if {$::env(INVITE) eq "1"} {
                after time $::env(PLAY_AT) { type "/play $::env(OPPONENT) yiear[format %c 13]" }
            } else {
                after time $::env(ACCEPT_AT) { type "/accept[format %c 13]" }
            }
          }
        }
    } 200
} else {
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
}
after time $::env(TMAX) { puts $tf "# codeDiff=[codeDiff]"; puts $tf "# timeout  nfNow=[peek $::s_nf] rxSeen=[peek $::s_rxSeen] tags=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15} {format %02X [peek [expr {$::s_remRing + $i * 3}]]}] ,] vals=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15} {format %02X [peek [expr {$::s_remRing + $i * 3 + 1}]]}] ,] rxbuf=[join [lmap i {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21} {format %02X [peek [expr {$::s_rxbuf + $i}]]}] ""] PC=[format %04X [reg PC]]"; close $tf; exit }
