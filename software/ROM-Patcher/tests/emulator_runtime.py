#!/usr/bin/env python3
"""Execute the injected Z80 code in isolated openMSX, without a live server.

Tests use CPU breakpoints as a command-boundary test double. Offline mode
uses the actual transport with no MSXPi attached. Always runs at speed 100.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import patch_rom


def hostpath(path, windows):
    value = str(Path(path).resolve())
    if windows and value.startswith('/mnt/'):
        return value[5].upper() + ':' + value[6:]
    return value


def run(args):
    profile, assets = patch_rom.load_profile(ROOT/'profiles/goonies/profile.json')
    config = {'tracks': {'first': {'filename': 'x2ab.mp3', 'mode': 'play'},
                         'second': {'filename': 'stage.mp3', 'mode': 'loop'}},
              'sounds': {'24': 'first', '25': 'second'}}
    data, manifest = patch_rom.build(args.rom.read_bytes(), profile, assets, config)
    args.work.mkdir(parents=True, exist_ok=True)
    rom = args.work/'runtime-test.rom'
    rom.write_bytes(data)
    symbols = profile['symbols']
    windows = args.openmsx.suffix.lower() == '.exe'
    for mode in ('mock', 'invalid', 'offline'):
        log = args.work/f'runtime-{mode}.log'
        script = args.work/f'runtime-{mode}.tcl'
        tcl = r'''
set throttle on
set speed 100
set pause_on_lost_focus false
set pause off
set power on
set audit [open {@LOG@} w]
array set s {@SYMBOLS@}
set audit_mode @MODE@
set calls 0
set commands {}
set next_pid 100
proc record {message} {puts $::audit $message; flush $::audit}
proc bgerror {message} {record "FAIL $message"; close $::audit; exit}
proc check {expression message} {if {![uplevel 1 [list expr $expression]]} {error $message}}
proc text_at {address} {
    set value ""
    for {set i 0} {$i < 257} {incr i} {
        set ch [peek [expr {$address+$i}]]
        if {$ch == 0} {return $value}
        append value [format %c $ch]
    }
    error "unterminated string"
}
proc return_call {} {
    set stack [reg SP]
    reg PC [expr {[peek $stack]+256*[peek [expr {$stack+1}]]}]
    reg SP [expr {$stack+2}]
}
proc exchange_test {} {
    incr ::calls
    if {$::audit_mode eq "offline"} {debug cont; return}
    set cmd [text_at [reg DE]]
    lappend ::commands $cmd
    record "COMMAND $cmd"
    if {[string match {music stop *} $cmd]} {
        set reply "Ok"
    } elseif {$::audit_mode eq "invalid"} {
        set reply "123invalid" ; numeric prefix must not become an owned PID
    } else {
        set reply [incr ::next_pid]
    }
    set address $::s(response)
    foreach ch [split $reply ""] {poke $address [scan $ch %c]; incr address}
    poke $address 0
    reg F [expr {[reg F]&254}]
    return_call
    debug cont
}
proc channel {id} {
    poke 0xe07f 0
    poke 0xe012 $id
    poke 0xe020 0
    poke 0xe02e 0
}
proc invoke {label callback} {
    set ::callback $callback
    reg IFF 0
    reg SP 0xe5e0
    poke 0xe5e0 0
    poke 0xe5e1 0xe6
    reg PC $::s($label)
    debug cont
}
proc returned {} {uplevel #0 $::callback}
debug set_bp 0xe600 {} {returned}
debug set_bp $s(exchange) {} {exchange_test}
proc start {} {
    record "BEGIN runtime test PC=[reg PC]"
    debug remove_bp $::start_bp
    channel 0xa4
    invoke service first_done
}
proc first_done {} {
    if {$::audit_mode ne "mock"} {
        check {[peek $::s(link_failed)] == 1} "failure did not enable fallback"
        check {[text_at $::s(pid)] eq ""} "failure accepted a PID"
        check {$::calls == 1} "unexpected first-call count"
        invoke service failure_repeat
        return
    }
    check {[text_at $::s(pid)] eq "101"} "PID not captured"
    check {[lindex $::commands 0] eq "music play x2ab.mp3"} "wrong play command / filename decoding"
    invoke service duplicate_done
}
proc failure_repeat {} {
    check {$::calls == 1} "retried failed connection"
    reg IX 0xe010
    reg C 1
    reg H 9
    invoke volume_hook fallback_volume
}
proc fallback_volume {} {
    check {[debug read {PSG regs} 8] == 9} "native music volume lost on fallback"
    record "PASS $::audit_mode: first-call fallback, no retry, native PSG preserved"
    close $::audit
    exit
}
proc duplicate_done {} {
    check {$::calls == 1} "duplicate event restarted music"
    reg IX 0xe010
    reg C 1
    reg H 9
    invoke volume_hook muted_done
}
proc muted_done {} {
    check {[debug read {PSG regs} 8] == 0} "mapped music not muted"
    poke 0xe012 2
    reg IX 0xe010
    reg C 1
    reg H 9
    invoke volume_hook effect_done
}
proc effect_done {} {
    check {[debug read {PSG regs} 8] == 9} "effect volume suppressed"
    channel 0xa5
    invoke service changed_done
}
proc changed_done {} {
    check {[lindex $::commands 1] eq "music stop 101"} "old PID not stopped"
    check {[lindex $::commands 2] eq "music loop stage.mp3"} "wrong loop command"
    check {[text_at $::s(pid)] eq "102"} "second PID not captured"
    channel 0
    poke $::s(silence_frames) 1
    invoke service grace_done
}
proc grace_done {} {
    check {$::calls == 3} "short gap stopped music"
    invoke service stopped_done
}
proc stopped_done {} {
    check {[lindex $::commands 3] eq "music stop 102"} "silence did not stop owned PID"
    check {[peek $::s(current)] == 0 && [peek $::s(pid)] == 0} "stop state not cleared"
    record "PASS mock: play/loop, change, PID ownership, dedup, grace, stop, selective PSG"
    close $::audit
    exit
}
set start_bp [debug set_bp $s(idle) {} {start}]
record "START $audit_mode PC=[reg PC]"
after time 10 {record "CHECKPOINT PC=[reg PC] SP=[reg SP]"}
after realtime 55 {record "FAIL watchdog PC=[reg PC]"; close $::audit; exit}
'''
        tcl = tcl.replace('@LOG@', hostpath(log, windows)).replace('@MODE@', mode)
        tcl = tcl.replace('@SYMBOLS@', ' '.join(f'{k} {v}' for k, v in symbols.items()))
        tcl = 'if {[catch {\n' + tcl + '\n} setup_error]} {puts $::audit "FAIL setup: $setup_error"; flush $::audit; exit}\n'
        script.write_text(tcl, encoding='utf-8')
        log.unlink(missing_ok=True)
        subprocess.run([str(args.openmsx), '-machine', 'Canon_V-25', '-cart', hostpath(rom, windows),
                        '-romtype', 'ASCII16', '-script', hostpath(script, windows)], timeout=65, check=True)
        result = log.read_text()
        print(result)
        if 'PASS' not in result or 'FAIL' in result:
            raise RuntimeError(f'{mode} runtime test failed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom', type=Path, required=True)
    parser.add_argument('--openmsx', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    run(parser.parse_args())
