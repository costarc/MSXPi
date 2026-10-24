# Yie Ar Kung-Fu on the cartridge: what each opponent's actions look like (documents/YIEAR-DESIGN.md 3.5, plan step 6).
#   openmsx -machine Canon_V-25 -carta kung-fu.rom -script moves.tcl
# At the opponents' shared decision point (7338h) the script starts action 0, 1, ... in turn (7429h with A = the action,
# as the AI's own starters do) and takes a raw screenshot at each pose change (E184h). After the last action the
# opponent is beaten (E00Bh) and the next one is done. Output in DBGOUT: opp<k>_act<i>_<n>.png and moves.txt (the pose
# codes, E16Ah/E16Bh, positions). Oolong stands still; REST is kept topped up.
if {[info exists ::env(DBGOUT)]} { set ::dir $::env(DBGOUT) } else { set ::dir . }
if {[info exists ::env(ACTIONS)]} { set ::nact $::env(ACTIONS) } else { set ::nact 9 }
set ::log [open "$::dir/moves.txt" w]
set ::opp -1          ;# the opponent being recorded
set ::act -1          ;# the action being shown, -1 = none yet
set ::shot 0
set ::lastPose -1
set ::go 0
set ::waitBeat 0
debug set_bp 0x4010 {[peek 0x4000] == 0x41 && [peek 0x4001] == 0x42} { set ::go 1 }
proc say {text} { puts $::log $text; flush $::log }
proc mvDecide {} {
    if {!$::go || [peek 0xE058]} return
    set k [peek 0xE054]
    if {$k != $::opp} {
        if {$k < $::opp || $::waitBeat == 0 && $::opp >= 0} return
        set ::opp $k; set ::act -1; set ::waitBeat 0
        say "== opponent $k"
    }
    if {$::waitBeat} return
    incr ::act
    if {$::act >= $::nact} {
        say "   beaten"
        set ::waitBeat 1
        poke 0xE00B 1
        if {$k == 4} { after time 3 mvDone }
        return
    }
    set ::shot 0; set ::lastPose -1
    say [format "-- action %d at x=%02X (Oolong %02X), facing %d" $::act [peek 0xE181] [peek 0xE161] [peek 0xE185]]
    reg A $::act
    reg PC 0x7429
}
proc mvPoll {} {
    if {$::act >= 0 && !$::waitBeat && [peek 0xE054] == $::opp && [peek 0xE000] == 5} {
        set pose [peek 0xE184]
        if {$pose != $::lastPose && $::shot < 6} {
            set ::lastPose $pose
            screenshot -raw [format "%s/opp%d_act%d_%d.png" $::dir $::opp $::act $::shot]
            say [format "   shot %d: pose %02X E16A=%02X E16B=%02X x=%02X y=%02X E129=%02X E132=%02X" $::shot $pose \
                [peek 0xE16A] [peek 0xE16B] [peek 0xE181] [peek 0xE180] [peek 0xE129] [peek 0xE132]]
            incr ::shot
        }
    }
    poke 0xE050 9
    after time 0.017 mvPoll
}
proc mvDone {} { close $::log; exit }
debug set_bp 0x7338 {} mvDecide
set throttle off
after time 6 { keymatrixdown 8 1; after time 0.3 { keymatrixup 8 1 } }
after time 7 mvPoll
after time 900 mvDone
