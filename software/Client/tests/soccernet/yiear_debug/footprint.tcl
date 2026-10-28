# Yie Ar Kung-Fu on the cartridge: where does it write outside E000h-E3FFh, how deep does the stack go, and how often
# do the hook sites run? (documents/YIEAR-DESIGN.md 3.6, plan step 1.)
#   openmsx -machine Canon_V-25 -carta kung-fu.rom -script footprint.tcl
# Environment: DBGOUT = output folder (default: the current folder), TMAX = emulated seconds (default 600),
# SEED = random play seed, LIVES=1 keeps REST topped up so the random play lasts.
if {[info exists ::env(DBGOUT)]} { set dir $::env(DBGOUT) } else { set dir . }
if {![info exists ::env(TMAX)]} { set ::env(TMAX) 600 }
expr {srand([expr {[info exists ::env(SEED)] ? $::env(SEED) : 1}])}
set ::w [dict create]         ;# "PC lo hi" per area
set ::hits [dict create]
set ::spmin 0xFFFF
set ::frames 0
set ::lastBeat 0
set ::stages {}
set ::go 0
# the BIOS (the MSX2 main ROM is mapped at 4000h-7FFFh until the cartridge is selected) writes too: only record from the game's INIT on
debug set_bp 0x4010 {[peek 0x4000] == 0x41 && [peek 0x4001] == 0x42} { set ::go 1 }
proc rec {area} {
    if {!$::go} return
    set pc [reg PC]; set a $::wp_last_address
    set k [format "%s %04X" $area $pc]
    if {[dict exists $::w $k]} {
        lassign [dict get $::w $k] n lo hi
        if {$a < $lo} { set lo $a }; if {$a > $hi} { set hi $a }
        dict set ::w $k [list [incr n] $lo $hi]
    } else { dict set ::w $k [list 1 $a $a] }
}
debug set_watchpoint write_mem {0x4000 0x7FFF} {} { rec rom }
debug set_watchpoint write_mem {0x8000 0xDFFF} {} { rec low }
debug set_watchpoint write_mem {0xE400 0xF37F} {} { rec high }
proc hit {name} {
    dict incr ::hits $name
    set sp [reg SP]
    if {$sp < $::spmin} { set ::spmin $sp; set ::spat $name }
}
foreach {name addr} {tick 0x4053 irq 0x4047 catch 0x4062 disp 0x409C key2 0x4583 ai 0x6B42 snd 0x7C5C} {
    debug set_bp $addr {} [list hit $name]
}
# the game's state, for the log
proc state {} {
    lappend ::stages [format "t=%d st=%d/%d opp=%d lvl=%d rest=%d bonus=%d" [expr {int([machine_info time])}] \
        [peek 0xE000] [peek 0xE001] [peek 0xE054] [peek 0xE056] [peek 0xE050] [peek 0xE058]]
    after time 10 state
}
proc key {bit secs} { keymatrixdown 8 [expr {1 << $bit}]; after time $secs [list keymatrixup 8 [expr {1 << $bit}]] }
proc play {} {
    foreach b {4 5 6 7} { keymatrixup 8 [expr {1 << $b}] }
    set d [lindex {4 5 6 7 5 6 7 7} [expr {int(rand() * 8)}]]
    keymatrixdown 8 [expr {1 << $d}]
    if {rand() < 0.7} { key 0 0.15 }
    if {[info exists ::env(LIVES)]} { poke 0xE050 9 }
    # a fight that lasts: the opponent is beaten (E00Bh non-zero, 41C1h), every BEAT seconds
    if {[info exists ::env(BEAT)] && [peek 0xE000] == 5 && [machine_info time] - $::lastBeat > $::env(BEAT)} {
        set ::lastBeat [machine_info time]; poke 0xE00B 1
    }
    after time 0.25 play
}
proc finish {} {
    set f [open "$::dir/footprint.txt" w]
    puts $f "SP min [format %04X $::spmin] at $::spat"
    puts $f "hits: $::hits"
    dict for {k v} $::w { puts $f [format "%s n=%d %04X-%04X" $k {*}$v] }
    puts $f [join $::stages "\n"]
    close $f
    exit
}
set ::dir $dir
set throttle off
after time 6 { key 0 0.3 }
after time 8 play
after time 10 state
after time $::env(TMAX) finish
