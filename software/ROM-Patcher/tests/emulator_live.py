#!/usr/bin/env python3
"""Live msxarch load/music/keyboard-exit test. Requires an idle MSXPi server.

Stage the generated ROM in the server's archive and supply its menu index.
This test neither starts/stops the host server nor changes the boot disk.
"""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import patch_rom
from emulator_runtime import hostpath


def run(args):
    profile, _ = patch_rom.load_profile(ROOT/'profiles/goonies/profile.json')
    args.work.mkdir(parents=True, exist_ok=True)
    script = args.work/'live.tcl'
    log = args.work/'live.log'
    windows = args.openmsx.suffix.lower() == '.exe'
    tcl = r'''
set throttle on
set speed 100
set pause_on_lost_focus false
set pause off
set power on
set audit [open {@LOG@} w]
array set s {@SYMBOLS@}
set owned_pid ""
set exiting_game false
set boot_count 0
set observed_commands {}
proc record {message} {puts $::audit $message; flush $::audit}
proc bgerror {message} {record "FAIL $message"; close $::audit; exit}
proc check {expression message} {
    if {![uplevel 1 [list expr $expression]]} {
        record "FAIL $message"
        close $::audit
        exit
    }
}
proc text_at {address} {
    set value ""
    for {set i 0} {$i < 140} {incr i} {
        set ch [peek [expr {$address+$i}]]
        if {$ch == 0} {return $value}
        append value [format %c $ch]
    }
    return $value
}
proc screen {label} {record "$label [harness::screen_text]"}
source {@HARNESS@}
ext MSXPi
ext ram4mb
reset
debug set_bp $s(resident_boot) {[peek $::s(resident_boot)] == 243 && [peek [expr {$::s(resident_boot)+1}]] == 205} {
    incr ::boot_count
    record "GAME BOOT count=$::boot_count"
    debug cont
}
debug set_bp $s(exchange) {} {
    set command_text [text_at [reg DE]]
    lappend ::observed_commands $command_text
    record "COMMAND $command_text time=[machine_info time]"
    debug cont
}
debug set_bp 0 {$::exiting_game} {
    record "RESET header=[peek 0x4000],[peek 0x4001] pid=[text_at $::s(pid)]"
    check {[peek 0x4000] == 0 && [peek 0x4001] == 0} "bootstrap AB not cleared"
    check {[text_at $::s(pid)] eq ""} "exit did not consume stop reply"
    set ::exiting_game false
    debug cont
}
proc loaded {} {
    record "SELECT ROM @INDEX@"
    type "@INDEX@\r"
    after time 23 {
        screen GAME_23S
        screenshot -raw {@WORK@/game.png}
        set ::owned_pid [text_at $::s(pid)]
        record "GAME pid=$::owned_pid current=[peek $::s(current)] failed=[peek $::s(link_failed)]"
        check {[regexp {^[1-9][0-9]*$} $::owned_pid]} "no valid live playback ID"
        check {[peek $::s(link_failed)] == 0} "live transport failed"
        check {$::boot_count == 1} "wrong cartridge loaded"
        # Verified at original 43E7: input while state !=1 returns to title;
        # another trigger while state==1 sets state3 and player flag bit6.
        keymatrixdown 8 1
        after time 0.2 {keymatrixup 8 1}
        after time 1 {keymatrixdown 8 1}
        after time 1.2 {keymatrixup 8 1}
        after time 12 {exit_with_keys}
    }
}
proc exit_with_keys {} {
    set ::owned_pid [text_at $::s(pid)]
    record "BEFORE EXIT pid=$::owned_pid"
    record "GAME STATE [peek 0xe000],[peek 0xe001] channels=[peek 0xe012],[peek 0xe020],[peek 0xe02e]"
    screenshot -raw {@WORK@/before-exit.png}
    check {[peek 0xe000] >= 3 && ([peek 0xe002] & 64)} "not in player-controlled gameplay"
    check {[regexp {^[1-9][0-9]*$} $::owned_pid]} "music not active during gameplay"
    set ::exiting_game true
    keymatrixdown 6 3
    keymatrixdown 7 2
    after time 0.3 {keymatrixup 6 3; keymatrixup 7 2}
    harness::at_dos_prompt {
        screen RETURNED_TO_DOS
        check {$::boot_count == 1} "reset re-entered the game"
        check {[lindex $::observed_commands end] eq "music stop $::owned_pid"} "exit stopped wrong PID"
        harness::run_cmd "p music getids" 45 {
            screen PLAYERS_AFTER_EXIT
            set lines [harness::screen_text]
            check {[string first $::owned_pid $lines] < 0} "owned player survived exit"
            screenshot -raw {@WORK@/after-exit.png}
            record "PASS live: msxarch load, loop PID, gameplay, keyboard exit, cleared AB, DOS, player stopped"
            close $::audit
            exit
        }
    } 60
}
proc begin_archive {} {
    type "msxarch\r"
    harness::wait_for "gameroms" 45 {
        type "@REPO@"
        harness::wait_for "Game Number to load" 90 {screen ARCHIVE; loaded}
    }
}
harness::at_dos_prompt {
    if {@CLEANUP@ > 0} {
        harness::run_cmd "p music stop @CLEANUP@" 45 {screen CLEANUP; begin_archive}
    } else {begin_archive}
} 60
after realtime 240 {record "FAIL live watchdog PC=[reg PC]"; close $::audit; exit}
record "START live speed=100 Canon_V-25 + MSXPi + ram4mb"
'''
    values = {'LOG': hostpath(log, windows), 'HARNESS': hostpath(args.harness, windows),
              'WORK': hostpath(args.work, windows), 'INDEX': str(args.index), 'REPO': str(args.repository),
              'CLEANUP': str(args.cleanup_pid),
              'SYMBOLS': ' '.join(f'{k} {v}' for k, v in profile['symbols'].items())}
    for key, value in values.items():
        tcl = tcl.replace('@'+key+'@', value)
    tcl = 'if {[catch {\n'+tcl+'\n} setup_error]} {puts $::audit "FAIL setup: $setup_error"; flush $::audit; exit}\n'
    script.write_text(tcl, encoding='utf-8')
    log.unlink(missing_ok=True)
    subprocess.run([str(args.openmsx), '-machine', 'Canon_V-25', '-script', hostpath(script, windows)],
                   timeout=255, check=True)
    result = log.read_text()
    print(result)
    if 'PASS live:' not in result or 'FAIL' in result:
        raise RuntimeError('Live test failed; see log and owned PID before cleanup')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openmsx', type=Path, required=True)
    parser.add_argument('--harness', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--index', type=int, required=True)
    parser.add_argument('--repository', type=int, default=5)
    parser.add_argument('--cleanup-pid', type=int, default=0, help='owned PID from a previous interrupted test')
    run(parser.parse_args())
