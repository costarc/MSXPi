r"""LINK2 on the MSX side, in openMSX (documents/LINK2-TEST-PLAN.md, T4 and T5).

Boots Canon_V-25 (MSX2, no floppy) with the BIOS-only half of an msxpi32k.rom
(`set msxpirom_bank BANK1`) through the MSXPiTest extension, against fault_server.py,
types CALL MSXPI statements at the BASIC prompt, and checks what lands in memory.

    python link2_openmsx.py [--rom target/msxpi32k.rom] [--rate 0] [--seed 1] [--dir both|rx|tx]
                            [--server-src DIR] [--timeout 300] [--tests ver,pat,...]

Tests (default: all):
  ver    CALL MSXPIVER, CALL MSXPI("1,..,ver"), CALL MSXPI("0,..,ver")
  pat    CALL MSXPI("2,addr,l2test pat N SEED") for N in 0.. 32 KB, buffers in pages 2 and 3 (page 1 is ROM there: BASIC's RAM starts at 8000h);
         the memory is compared with the pattern
  bin    L2TEST.BIN downloaded by CALL MSXPI, then run with DEFUSR: bulk MSX -> Pi sends
         (the server checks them and the MSX prints its verdict)

Verdicts per test: PASS, FAIL (wrong data or text), HUNG (no BASIC prompt before the
timeout).  Windows Python and the openMSX MSXPi build; port 5046 must be free.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[2]
OPENMSX = os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe')
PORT = int(os.environ.get('MSXPI_TEST_PORT', '5046'))
SRCDIR = Path('C:/tmp/fi')  # MSXPiTest.xml loads C:/tmp/fi/msxpitest.rom


def pattern(n, seed):
    return bytes((i * 13 + (i >> 8) * 7 + seed) & 0xFF for i in range(n))


def tcl_str(text):
    """Tcl double-quoted string for text typed at the BASIC prompt."""
    return '"' + ''.join(c if c.isalnum() or c in ' ,.:=' else '\\x%02x' % ord(c) for c in text) + '"'


class Step:
    """One BASIC line, the text that ends it, and what to dump afterwards."""

    def __init__(self, name, line, wait, dump=None, pre=None, check=None):
        # pre: [(address, bytes)] written to MSX memory before the line is typed;
        # check: ('l2t', n) the L2TEST summary line must show n OK and no failure
        self.name, self.line, self.wait, self.dump, self.pre, self.check = name, line, wait, dump, pre or [], check


def build_steps(tests, sizes=None):
    steps = []
    if 'ver' in tests:
        steps += [
            Step('ver-call', 'CLS:CALL MSXPIVER', r'Server Version.*\n\s*Ok'),
            Step('ver-print', 'CLS:CALL MSXPI("1,C000,ver")', r'Server Version.*\n\s*Ok'),
            Step('ver-discard', 'CLS:CALL MSXPI("0,C000,ver"):PRINT "DO";"NE0"', r'DONE0'),
        ]
    if 'pat' in tests:
        for n in (1, 255, 256, 300, 512, 1000, 8192, 8193, 16384):
            for addr in (0xA000, 0xC000):
                if addr + n + 3 > 0xF000:
                    continue
                steps.append(Step(f'pat-{n}-{addr:04X}',
                                  f'CLS:CALL MSXPI("2,{addr:04X},l2test pat {n} 7"):PRINT "DO";"NE"',
                                  r'DONE|rror', dump=(addr, n + 3)))
    if 'bin' in tests:
        binfile = SOFTWARE / 'target/L2TEST.BIN'
        size = binfile.stat().st_size
        steps.append(Step('bin-load', 'CLS:CALL MSXPI("2,C000,l2test bin"):DEFUSR=&HC003:PRINT "LOAD";"ED"',
                          r'LOADED|rror', dump=(0xC000, size + 3)))
        binary = binfile.read_bytes()
        for n, addr, reps in ((1, 0x9000, 1), (255, 0x9000, 1), (256, 0x9000, 1), (300, 0x9000, 1),
                              (512, 0x9000, 1), (1000, 0x9000, 1), (4096, 0x9800, 1), (8192, 0x9000, 1),
                              (8193, 0x9000, 1), (12000, 0x9000, 1), (512, 0x9000, 50)):
            if sizes and n not in sizes:
                continue
            cmd = f'l2test sink {n} 5'.encode() + b'\x00'
            # the program is written again for every run, so a download that a fault spoiled
            # does not take the later tests down with it
            pre = [(0xC003, binary), (0xE000, cmd),
                   (0xE040, n.to_bytes(2, 'little') + bytes([5]) + b'\x00'
                    + addr.to_bytes(2, 'little') + reps.to_bytes(2, 'little'))]
            steps.append(Step(f'bin-send-{n}-{addr:04X}-x{reps}', 'CLS:DEFUSR=&HC003:A=USR(0)',
                              r'F=[0-9A-F]+ T=[0-9A-F]+|rror', pre=pre, check=('l2t', reps)))
    return steps


def write_script(work, steps, timeout, log):
    lines = [f'''set save_settings_on_exit off
set msxpiserver_port {PORT}
set throttle on
set msxpirom_bank BANK1
set power on
set l2Log [open "{log}" w]
set l2I 0
set l2Typed 0
set l2T0 [clock seconds]
proc note {{msg}} {{ global l2Log; puts $l2Log "[clock seconds] $msg"; flush $l2Log }}
proc dumpscreen {{name}} {{
    set f [open "{work.as_posix()}/$name" w]
    catch {{puts $f [get_screen]}}
    close $f }}
proc dumpmem {{name addr len}} {{
    set f [open "{work.as_posix()}/$name" wb]
    puts -nonewline $f [debug read_block memory $addr $len]
    close $f }}
''']
    lines.append('set l2Steps [list \\')
    for s in steps:
        dump = f'{s.dump[0]} {s.dump[1]}' if s.dump else '0 0'
        pre = ' '.join(f'{a} {b.hex() or "00"}' for a, b in s.pre)
        lines.append(f'  [list {s.name} {tcl_str(s.line)} {{{s.wait}}} {dump} {{{pre}}}] \\')
    lines.append(']')
    lines.append(f'''
proc poll {{}} {{
    global l2I l2Typed l2Steps l2T0
    if {{[expr {{[clock seconds] - $l2T0}}] > {timeout}}} {{ note "TIMEOUT step $l2I PC=[format %04X [reg PC]] SP=[format %04X [reg SP]] HL=[format %04X [reg HL]]"; dumpscreen screen-timeout.txt; exit }}
    set s ""
    catch {{set s [get_screen]}}
    if {{$l2I >= [llength $l2Steps]}} {{ note ALLDONE; exit }}
    dumpscreen screen-last.txt
    lassign [lindex $l2Steps $l2I] name line wait addr len pre
    if {{!$l2Typed}} {{
        # the BASIC prompt first: Ok alone on a line
        if {{[regexp -line {{^\\s*Ok\\s*$}} $s]}} {{
            set l2Typed 1
            note "step $name: typing"
            foreach {{a hex}} $pre {{ debug write_block memory $a [binary format H* $hex] }}
            type_via_keybuf "$line\\r"
        }}
    }} else {{
        if {{[regexp -- $wait $s]}} {{
            dumpscreen "screen-$name.txt"
            if {{$len > 0}} {{ dumpmem "mem-$name.bin" $addr $len }}
            note "step $name: done"
            set l2Typed 0
            incr l2I
            # let the prompt come back before the next line
            after time 1 poll
            return
        }}
    }}
    after time 1 poll
}}
proc sample {{}} {{
    global l2Typed
    if {{$l2Typed}} {{ note "PC=[format %04X [reg PC]] SP=[format %04X [reg SP]]" }}
    after time 1 sample
}}
after time 1 sample
after time 8 poll
''')
    path = work / 'l2.tcl'
    path.write_text('\n'.join(lines))
    return path


def run(a):
    root = SOFTWARE.parent / 'work'
    root.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix=f'l2-s{a.seed_now}-', dir=root))
    home = work / 'home'
    (home / 'disks').mkdir(parents=True)
    (home / 'msxpi.ini').write_text(f'var PATH={home.as_posix()}\n')
    SRCDIR.mkdir(parents=True, exist_ok=True)
    # (not while another run of the same ROM has it open: Windows refuses the copy)
    if not (SRCDIR / 'msxpitest.rom').exists() or (SRCDIR / 'msxpitest.rom').read_bytes() != Path(a.rom).read_bytes():
        shutil.copy(a.rom, SRCDIR / 'msxpitest.rom')
    if (SOFTWARE / 'target/L2TEST.BIN').exists():
        shutil.copy(SOFTWARE / 'target/L2TEST.BIN', home / 'l2test.bin')
    steps = build_steps(a.tests.split(','), [int(x) for x in a.sizes.split(',')] if a.sizes else None)
    log = work / 'events.txt'
    script = write_script(work, steps, a.timeout, log.as_posix())
    env = dict(os.environ, MSXPI_HOME=str(home), MSXPI_PORT=str(PORT), FAULT_RATE=str(a.rate),
               FAULT_SEED=str(a.seed_now), FAULT_DIR=a.dir, FAULT_SRC=a.server_src or '')
    server_log = (work / 'server.log').open('w')
    server = subprocess.Popen([sys.executable, '-u', str(HERE / 'fault_server.py')], env=env,
                              stdout=server_log, stderr=subprocess.STDOUT)
    try:
        time.sleep(3)
        with (work / 'openmsx.log').open('w') as out:
            subprocess.run([OPENMSX, '-machine', 'Canon_V-25', '-ext', 'MSXPiTest',
                            '-command', 'set renderer none', '-script', str(script)],
                           stdout=out, stderr=subprocess.STDOUT, timeout=a.timeout * 3 + 120)
    except subprocess.TimeoutExpired:
        log.open('a').write('openMSX killed: wall-clock timeout\n')
    finally:
        server.terminate()
        server.wait()
        server_log.close()
    events = log.read_text() if log.exists() else ''
    slog = (work / 'server.log').read_text(errors='replace')
    # Verdicts: PASS (right data), ABORT (BASIC reported an error and nothing wrong was
    # delivered: what a fault may cost), CORRUPT (wrong data accepted, or the server was
    # sent wrong data and said so), HUNG (the step never ended), NOTRUN (after a HUNG).
    import re
    results = {}
    hung = False
    corrupt_on_server = slog.count('L2TEST BAD')
    for s in steps:
        if hung:
            results[s.name] = 'NOTRUN'
            continue
        if f'step {s.name}: done' not in events:
            results[s.name] = 'HUNG'
            hung = True
            continue
        screen = (work / f'screen-{s.name}.txt').read_text(errors='replace')
        reported = 'rror' in screen
        if s.name.startswith('ver'):
            v = 'ABORT' if reported else ('PASS' if ('Server Version' in screen or s.name == 'ver-discard') else 'CORRUPT')
        elif s.check:
            m = re.search(r'OK=([0-9A-F]+) F=([0-9A-F]+)', screen)
            v = 'ABORT' if (reported or not m) else (
                'PASS' if int(m[1], 16) == s.check[1] and int(m[2], 16) == 0 else 'ABORT')
        elif s.name == 'bin-load':
            mem = (work / f'mem-{s.name}.bin').read_bytes()
            v = 'ABORT' if reported else ('PASS' if mem[3:] == (SOFTWARE / 'target/L2TEST.BIN').read_bytes() else 'CORRUPT')
        else:
            mem = (work / f'mem-{s.name}.bin').read_bytes()
            n = s.dump[1] - 3
            good = mem[0] == 0xE0 and mem[1] | (mem[2] << 8) == n and mem[3:3 + n] == pattern(n, 7)
            v = 'PASS' if good and not reported else ('ABORT' if reported or mem[0] != 0xE0 else 'CORRUPT')
        results[s.name] = v
    if corrupt_on_server:
        results['server-saw-bad-data'] = 'CORRUPT'
    for k, v in results.items():
        print(f'  {v:6} {k}')
    faults = slog.count('FAULT #')
    bursts = sum(1 for line in slog.splitlines() if line.startswith('BURST '))
    summary = {v: list(results.values()).count(v) for v in sorted(set(results.values()))}
    print(f'seed {a.seed_now}: {summary} faults={faults} bursts={bursts} [{work}]', flush=True)
    return summary


def main():
    global PORT
    ap = argparse.ArgumentParser()
    ap.add_argument('--rom', default=str(SOFTWARE / 'target/msxpi32k.rom'))
    ap.add_argument('--rate', type=float, default=0.0)
    ap.add_argument('--seed', type=int, nargs='+', default=[1])
    ap.add_argument('--dir', default='both', choices=['both', 'rx', 'tx'])
    ap.add_argument('--timeout', type=int, default=600, help='seconds of wall time before a run counts as hung')
    ap.add_argument('--tests', default='ver,pat,bin')
    ap.add_argument('--sizes', help='only these L2TEST send sizes, e.g. 256,512')
    ap.add_argument('--server-src')
    ap.add_argument('--port', type=int, help='server port (default MSXPI_TEST_PORT or 5046)')
    a = ap.parse_args()
    if a.port:
        PORT = a.port
    total = {}
    for seed in a.seed:
        a.seed_now = seed
        for k, v in run(a).items():
            total[k] = total.get(k, 0) + v
    print('summary:', total)
    # a clean run must be all PASS; a faulted one may ABORT, but never CORRUPT or HUNG
    bad = total.get('CORRUPT', 0) + total.get('HUNG', 0) + (0 if a.rate else total.get('ABORT', 0))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
