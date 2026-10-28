"""End-to-end: MCHAT.COM (MSX1, SCREEN 2) in openMSX through a real MSXPi server.

The emulated MSX (Canon V-25, which is an MSX2, with MSXPi, MSX-DOS 1 from msxpiboot.dsk) starts
"MCHAT /1 alice" (SCREEN 2, the MSX1 screen). Another machine can be set with MCHAT_OPENMSX_MACHINE. The IRC server is pchess_irc_fixture on this host (the MSXPi
server is pointed at it with PCHESS_IRC_* variables) and "bob" is a plain
socket in the fixture. Bob talks in #msxpi and sends alice a private line;
alice answers, joins a second room, switches rooms and scrolls back. The
screen is read back from VRAM: SCREEN 2 text is decoded with the same 4x8
font the program draws with (tools/gen_mchat_font.py).

    python mchat_openmsx.py [path\\to\\mchat.com]

Windows Python and openMSX with the MSXPi extension. Ports 5044 and 6668
must be free. MCHAT_LINK=tcp runs the chat over INL on the server's user-mode network link
(MCHAT_NET=nat, the default: the IRC fixture is 10.0.2.2, no adapter) or over the Windows TAP (MCHAT_NET=tap).
Add MCHAT_FORCE1=1 for the checks below on the Canon (they decode SCREEN 2; without /1 the MSX2 starts in SCREEN 6). Artefacts go to <repo>/../work/mchat-*/.
"""
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[1]
sys.path.insert(0, str(SOFTWARE / 'Server/Python/tests'))
sys.path.insert(0, str(SOFTWARE / 'Client/tools'))
from pchess_irc_fixture import Server  # noqa: E402
import gen_mchat_font  # noqa: E402

OPENMSX = os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe')
MCHAT = Path(sys.argv[1] if len(sys.argv) > 1 else os.environ.get('MCHAT_COM', SOFTWARE / 'target/mchat.com'))
MACHINE = os.environ.get('MCHAT_MACHINE', 'msx1')      # msx1 (Canon V-25) or msx2 (Panasonic FS-A1WSX)
FLOPPY = Path(os.environ.get('FLOPPYA', 'C:/Users/roniv/Dev/MSX/MSXPi/FloppyA'))
MSXPI_PORT = int(os.environ.get('MSXPI_TEST_PORT', '5044'))
IRC_PORT = int(os.environ.get('MCHAT_IRC_PORT', '6667' if os.environ.get('MCHAT_LINK') == 'tcp' else '6668'))

UP, DOWN, TAB, ESC = chr(30), chr(31), chr(9), chr(27)
TIMELINE = [
    (15, 'shot:boot'), (22, 'mchat /1 alice\r'), (30, 'shot:early'), (40, 'dump:start'), (41, 'shot:start'),
    (42, 'hello bob\r'), (50, '/join #second\r'), (60, 'dump:second'),
    (62, 'only here\r'), (68, TAB), (76, 'dump:back'),
    (77, 'ping\r'), (84, 'dump:pong'),
    (85, UP + UP), (93, 'dump:scrolled'),
    (97, ESC), (107, 'quit'),
]
if MACHINE == 'msx2':
    # DOS from FloppyA; no /1, so the MSX2 build starts in SCREEN 6 and /screen goes to SCREEN 2.
    # Slower than the MSX1 script (written when a whole screen took ~7 s to repaint).
    TIMELINE = [(27, 'dump:font'), (22, 'c:\r'), (25, 'dir mchat.com\r'), (30, 'mchat alice\r'),
                (54, 'dump:start'), (56, 'hello bob\r'), (64, '/join #second\r'), (80, 'dump:second'),
                (82, 'only here\r'), (92, TAB), (106, 'dump:back'), (107, 'ping\r'), (115, 'dump:pong'),
                (116, UP + UP), (130, 'dump:scrolled'),
                (134, '/screen\r'), (148, 'dump:switched'), (149, 'shot:switched'), (152, ESC), (160, 'quit')]
MSX2_MACHINE = os.environ.get('MCHAT_MSX2_MACHINE', 'Panasonic_FS-A1WSX')
MSX2_FLOPPY = MSX2_MACHINE == 'Panasonic_FS-A1WSX'
if MACHINE == 'msx2' and not MSX2_FLOPPY:
    # No floppy drive (Canon V-25): MCHAT.COM runs from A:, the MSXPi's msxpiboot.dsk, as on the real one.
    TIMELINE = [(19, 'dump:font'), (22, 'mchat alice\r')] + [(t - 8, a) for t, a in TIMELINE if t > 30]

TIMING = os.environ.get('MCHAT_TIMING')            # 1: report VRAM write bursts per action; check: also fail if slow
WATCH = [int(a) for a in os.environ.get('MCHAT_WATCH', '').split(',') if a]   # VRAM addresses to log in poll.log when VRAM changes
TRACE = os.environ.get('MCHAT_TRACE')               # VRAM address: log each change of that byte with PC and stack (vram/trace.log)
TRACE_BP = os.environ.get('MCHAT_TRACE_BP')         # addr,lo,hi: log calls of the routine at addr whose 2nd argument is in lo..hi (vram/trace.log)
LINK = os.environ.get('MCHAT_LINK', 'msxpi')      # msxpi (the MSXPi server) or tcp (TCP/IP UNAPI, INL)
NET = os.environ.get('MCHAT_NET', 'nat')          # tcp only: nat (the server's user-mode link, host = 10.0.2.2) or tap
IRC_HOST_IP = '10.0.2.2' if NET == 'nat' else '192.168.99.1'
if LINK == 'tcp':
    # MSR I and INL I give the Canon a TCP/IP stack; the MSX reaches the IRC fixture on this host. nat (default): the
    # MSXPi server's user-mode UDP/TCP link (msxpi_ethnat.py) makes the host 10.0.2.2, no adapter needed. tap: the
    # fixture is at 192.168.99.1 through the Windows TAP (msxpi-tcpip-setup.ps1).
    TIMELINE = [(20, 'MSR I\r'), (32, 'INL I\r'), (46, 'memtop\r'), (49, 'shot:memtop'), (49, 'dump:font'), (50, os.environ.get('MCHAT_CMD', 'mchat /t alice') + '\r')] + [
        (int(58 + (t - 30) * 1.5), a) for t, a in TIMELINE if t >= 30]   # the TCP/IP link is slower
    if os.environ.get('MCHAT_FORCE1'):
        TIMELINE = [(t, a.replace('mchat /t', 'mchat /1 /t')) for t, a in TIMELINE]

SHOTS = [int(t) for t in os.environ.get('MCHAT_SHOTS', '').split(',') if t]   # extra screenshots (emulated seconds)
TIMELINE = sorted(TIMELINE + [(t, f'shot:t{t}') for t in SHOTS], key=lambda e: e[0])

GLYPH_ROWS = {}
for _i, _g in enumerate(gen_mchat_font.GLYPHS):
    GLYPH_ROWS[tuple(int(r, 16) for r in _g)] = chr(32 + _i)


def pattern_bit(vram, x, y):
    return vram[((y // 8) * 32 + x // 8) * 8 + y % 8] >> (7 - x % 8) & 1


def screen_text(vram):
    """The 24 rows of 51 characters, decoded from the pattern table."""
    lines = []
    for r in range(24):
        line = ''
        for c in range(51):
            rows = []
            for y in range(8):
                rows.append(sum(pattern_bit(vram, c * 5 + x, r * 8 + y) << (3 - x) for x in range(4)))
            line += GLYPH_ROWS.get(tuple(rows), '?')
        lines.append(line)
    return lines


def screen_text6(vram, font):
    """SCREEN 6 (2 bits a pixel, 128 bytes a line): 85 x 26 cells of 6x8 pixels, BIOS font."""
    glyphs = {}
    for ch in range(32, 127):
        glyphs[tuple(font[ch * 8 + r] >> 2 for r in range(8))] = chr(ch)
    def pixel(x, y):
        return vram[y * 128 + x // 4] >> (6 - 2 * (x % 4)) & 3
    lines = []
    for r in range(26):
        line = ''
        for c in range(85):
            px = [[pixel(c * 6 + x, r * 8 + y) for x in range(6)] for y in range(8)]
            flat = [v for row in px for v in row]
            bg = max(set(flat), key=flat.count)
            rows = tuple(sum((px[y][x] != bg) << (5 - x) for x in range(6)) for y in range(8))
            line += glyphs.get(rows, '?') if any(rows) else ' '
        lines.append(line)
    return lines


def tcl_string(text):
    return ''.join(c if c.isalnum() or c in ' ' else '\\x%02x' % ord(c) for c in text)


def write_script(path, dumps):
    lines = ['set save_settings_on_exit off', f'set msxpiserver_port {MSXPI_PORT}',
             'set speed 100', 'set power on',
             'proc dump {name} {',
             f'    set f [open "{dumps.as_posix()}/$name.vram" w]',
             '    fconfigure $f -translation binary',
             '    puts -nonewline $f [debug read_block VRAM 0 ' + ('32768' if MACHINE == 'msx2' else '16384') + ']',
             '    close $f', '}']
    if TIMING:
        nbytes = '32768' if MACHINE == 'msx2' else '16384'
        lines += ['set lastv ""', f'set plog [open "{dumps.as_posix()}/poll.log" w]',
                  'proc poll {} {', '  global lastv plog',
                  f'  set v [debug read_block VRAM 0 {nbytes}]',
                  '  if {$v ne $lastv} {', '    set n 0',
                  '    if {$lastv ne ""} { binary scan $v c* a; binary scan $lastv c* b; foreach x $a y $b { if {$x != $y} {incr n} } }',
                  '    puts $plog "[format %.3f [machine_info time]] $n"; flush $plog',
                  *[f'    set w [binary scan [string index $v {a}] c wv{i}]; puts $plog "  watch {a} [expr {{$wv{i} & 255}}]"' for i, a in enumerate(WATCH)],
                  '    set lastv $v }',
                  '  after time 0.04 poll }', 'after time 20 poll']
    if TRACE_BP:
        addr, lo, hi = TRACE_BP.split(',')
        lines += [f'set tlog [open "{dumps.as_posix()}/trace.log" w]',
                  f'debug set_bp {addr} {{}} {{set sp [reg SP]; set dst [peek16 [expr $sp+4]]; if {{$dst >= {lo} && $dst < {hi}}} {{ set src [peek16 [expr $sp+2]]; set b {{}}; for {{set i 0}} {{$i < 6}} {{incr i}} {{ append b [format %02X [peek [expr $src+$i]]] " " }}; puts $tlog "CALL [format %.4f [machine_info time]] dst=$dst len=[peek16 [expr $sp+6]] ret=[format %04X [peek16 $sp]] src=$b"; flush $tlog }} }}']
    if TRACE:
        lines += [f'set tb [debug read VRAM {TRACE}]', f'set tlog [open "{dumps.as_posix()}/trace.log" w]', 'proc trace {} {', '  global tb tlog',
                  f'  set b [debug read VRAM {TRACE}]',
                  '  if {$b != $tb} { puts $tlog "TRACE [format %.4f [machine_info time]] $tb -> $b PC=[format %04X [reg PC]] SP=[format %04X [reg SP]] stack=[debug read_block memory [reg SP] 24]"; flush $tlog; set tb $b }',
                  '  after time 0.0003 trace }', 'after time 20 trace']
    if os.environ.get('MCHAT_EXTRA_TCL'):          # a Tcl file appended to the script (debugging)
        lines += Path(os.environ['MCHAT_EXTRA_TCL']).read_text().splitlines()
    for when, action in TIMELINE:
        if action == 'quit':
            lines.append(f'after time {when} {{exit}}')
        elif action.startswith('dump:'):
            lines.append(f'after time {when} {{dump {action[5:]}}}')
        elif action.startswith('shot:'):
            lines.append(f'after time {when} {{screenshot "{dumps.as_posix()}/{action[5:]}.png"}}')
        else:
            lines.append(f'after time {when} {{type_via_keybuf "{tcl_string(action)}"}}')
    path.write_text('\n'.join(lines) + '\n')


class Bob(threading.Thread):
    """A second IRC user in the fixture."""

    def __init__(self, fixture):
        super().__init__(daemon=True)
        self.fixture = fixture
        self.sock = socket.create_connection(('127.0.0.1', IRC_PORT))
        self.done = False
        self.ponged = False

    def send(self, line):
        self.sock.sendall((line + '\r\n').encode())

    def run(self):
        self.send('NICK bob')
        self.send('USER bob 0 * :bob')
        self.send('JOIN #msxpi')
        end = time.time() + 120
        while time.time() < end and 'alice' not in self.fixture.clients:
            time.sleep(.1)
        time.sleep(4)
        self.send('PRIVMSG #msxpi :hello everyone')
        time.sleep(.5)
        self.send('PRIVMSG alice :psst alice')
        # The filler comes once alice has spoken, so the first screen shows the rest.
        while time.time() < end and not any(m == 'hello bob' for _, _, m in self.fixture.transcript):
            time.sleep(.1)
        time.sleep(2)
        for i in range(1, 31):
            self.send(f'PRIVMSG #msxpi :filler line {i}')
            time.sleep(.05)
        while not self.done:
            if ('alice', '#msxpi', 'ping') in self.fixture.transcript and not self.ponged:
                self.ponged = True
                self.send('PRIVMSG #msxpi :pong')      # one new line while alice follows the chat live
            time.sleep(.05)


def bursts(path):
    """(start, duration, changed bytes) of the VRAM changes in poll.log; changes <= 0.25 s apart are one burst."""
    out = []
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith(" "):
            continue
        t, n = line.split()
        t, n = float(t), int(n)
        if out and t - out[-1][3] <= 0.25:
            out[-1][3] = t
            out[-1][2] += n
        else:
            out.append([t, t, n, t])
    return [(b[0], b[3] - b[0], b[2]) for b in out]


def timing_report(dumps, failures):
    """Per action of TIMELINE: the bursts that follow it. Time resolution is +-0.1 s (the poll period)."""
    log = dumps / 'poll.log'
    if not log.exists():
        return
    bs = bursts(log)
    typing = [t for t, a in TIMELINE if a == 'hello bob\r']
    print('--- VRAM write bursts (emulated seconds: start, duration, changed bytes) ---')
    marks = [(t, a) for t, a in TIMELINE if not a.startswith(('shot:', 'dump:')) and a != 'quit']
    for i, (t, a) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else t + 10
        mine = [b for b in bs if t <= b[0] < end and b[2] > 3]
        print(f'{t:5.0f}s {a!r}: ' + ', '.join(f'{s:.1f}s/{d:.2f}s/{n}B' for s, d, n in mine[:8]))
    if TIMING == 'check' and typing:
        # The typed word must be on screen about as fast as it is typed (10 keys, injected ~60 ms apart).
        first = [b for b in bs if b[0] >= typing[0]][:1]
        elapsed = max((s + d for s, d, _ in first), default=typing[0] + 99) - typing[0]
        limit = 1.0
        ok = elapsed < limit
        print(('PASS: ' if ok else 'FAIL: ') + f'typed word fully echoed {elapsed:.2f}s after the first key (limit {limit}s)', flush=True)
        if not ok:
            failures.append('typing echo too slow')
    ping = [t for t, a in TIMELINE if a == 'ping\r']
    if TIMING == 'check' and ping:
        # "ping" typed, sent, bob's one-line answer fetched and scrolled in: everything has stopped moving
        # this long after the first key (typing ~0.3 s + two server round trips ~1 s are in it).
        mine = [b for b in bs if ping[0] <= b[0] < ping[0] + 8 and b[2] > 3]
        total = max((s + d for s, d, _ in mine), default=ping[0] + 99) - ping[0]
        limit = 2.0
        ok = total < limit
        print(('PASS: ' if ok else 'FAIL: ') + f'ping typed and pong painted within {total:.2f}s (limit {limit}s)', flush=True)
        if not ok:
            failures.append('new line too slow')


def main():
    (SOFTWARE.parent / 'work').mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='mchat-', dir=SOFTWARE.parent / 'work'))
    home, dumps = work / 'home', work / 'vram'
    (home / 'disks').mkdir(parents=True)
    dumps.mkdir()
    shutil.copy(SOFTWARE / 'target/disks/msxpiboot.dsk', home / 'disks/msxpiboot.dsk')
    shutil.copy(SOFTWARE / 'target/disks/tools.dsk', home / 'disks/tools.dsk')
    shutil.copy(MCHAT, work / 'mchat.com')
    subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', 'mchat.com',
                    'home/disks/msxpiboot.dsk:MCHAT.COM'], cwd=work, check=True, stdout=subprocess.DEVNULL)
    if MACHINE == 'msx2':
        shutil.copytree(FLOPPY, work / 'floppy')
        shutil.copy(MCHAT, work / 'floppy/mchat.com')
    if LINK == 'tcp':
        shutil.copy(SOFTWARE / 'target/memtop.com', work / 'memtop.com')
        subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', 'memtop.com',
                        'home/disks/msxpiboot.dsk:MEMTOP.COM'], cwd=work, check=True, stdout=subprocess.DEVNULL)
        (work / 'MCHAT.INI').write_bytes(b'IRCADDR=%s\r\nIRCPORT=%d\r\n' % (IRC_HOST_IP.encode(), IRC_PORT))
        if NET == 'nat':     # INL I reads INL.CFG from the current drive: the user-mode link's addresses
            (work / 'INL.CFG').write_bytes(b'ip d 0\r\nip l 10.0.2.15\r\nip m 255.255.255.0\r\nip g 10.0.2.2\r\nip p 10.0.2.2\r\n\x1a')
            subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', 'INL.CFG',
                            'home/disks/msxpiboot.dsk:INL.CFG'], cwd=work, check=True, stdout=subprocess.DEVNULL)
        subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', 'MCHAT.INI',
                        'home/disks/msxpiboot.dsk:MCHAT.INI'], cwd=work, check=True, stdout=subprocess.DEVNULL)
    script = work / 'mchat.tcl'
    write_script(script, dumps)

    fixture = Server(('0.0.0.0' if LINK == 'tcp' and NET == 'tap' else '127.0.0.1', IRC_PORT))
    threading.Thread(target=fixture.serve_forever, daemon=True).start()
    bob = Bob(fixture)
    env = dict(os.environ, MSXPI_HOME=str(home), MSXPI_PORT=str(MSXPI_PORT), PCHESS_IRC_HOST='127.0.0.1',
               PCHESS_IRC_PORT=str(IRC_PORT), PCHESS_IRC_TLS='0')
    if LINK == 'tcp' and NET == 'nat':
        env['MSXPI_ETH_LINK'] = 'udpnat'
    server_log = (work / 'server.log').open('w')
    server = subprocess.Popen([sys.executable, '-u', 'msxpi-server.py'], env=env,
                              cwd=SOFTWARE / 'Server/Python/src', stdout=server_log, stderr=subprocess.STDOUT)
    failures = []

    def check(ok, message):
        print(('PASS: ' if ok else 'FAIL: ') + message, flush=True)
        if not ok:
            failures.append(message)

    try:
        time.sleep(3)
        bob.start()
        with (work / 'openmsx.log').open('w') as out:
            machine = (['-machine', MSX2_MACHINE, '-ext', 'MSXPi', '-ext', 'ram4mb'] + (['-diska', str(work / 'floppy')] if MSX2_FLOPPY else [])
                       if MACHINE == 'msx2' else ['-machine', os.environ.get('MCHAT_OPENMSX_MACHINE', 'Canon_V-25'), '-ext', 'ram2mb', '-ext', 'MSXPi'])
            subprocess.run([OPENMSX, *machine,
                            '-command', 'set renderer none' if not os.environ.get('MCHAT_SHOW') else 'set speed 100', '-script', str(script)],
                           stdout=out, stderr=subprocess.STDOUT, timeout=600)
    finally:
        bob.done = True
        server.terminate()
        server.wait()
        server_log.close()

    screens = {}
    font = (dumps / 'font.vram').read_bytes() if (dumps / 'font.vram').exists() else None
    for name in ('start', 'second', 'back', 'pong', 'scrolled', 'switched'):
        path = dumps / f'{name}.vram'
        if path.exists():
            screens[name] = (screen_text6(path.read_bytes(), font) if MACHINE == 'msx2' and name != 'switched'
                             else screen_text(path.read_bytes()))
            print(f'[{name}]')
            print('\n'.join(line.rstrip() for line in screens[name]), flush=True)
    start = '\n'.join(screens.get('start', []))
    check('#MSXPI' in start.upper() or '#msxpi' in start, 'room tab is shown')
    later = '\n'.join(screens.get('second', []))
    check('bob: hello everyone' in start or 'bob: hello everyone' in later, 'bob\'s public line is shown')
    check('*bob* psst alice' in start or '*bob* psst alice' in later, 'private line is shown')
    check('USERS' in start and 'bob' in start.split('\n')[2] + start.split('\n')[3], 'user list shows bob')
    check(any(m == 'hello bob' for _, t, m in fixture.transcript), 'alice\'s line reached the IRC server')
    second = '\n'.join(screens.get('second', []))
    check('#second' in second, 'second room tab appears')
    check(('alice', '#second', 'only here') in fixture.transcript, 'line went to the second room')
    back = '\n'.join(screens.get('back', []))
    check('#msxpi' in back and 'filler line 30' in back, 'TAB returns to #msxpi at the latest line')
    check('bob: pong' in '\n'.join(screens.get('pong', [])), 'a single new line shows up while following the chat')
    scrolled = '\n'.join(screens.get('scrolled', []))
    check('SCROLLED' in scrolled and 'filler line 30' not in scrolled, 'UP scrolls back through history')
    if MACHINE == 'msx2':
        switched = chr(10).join(screens.get('switched', []))
        check('#msxpi' in switched and 'bob: filler line' in switched, '/screen switched to SCREEN 2 and kept the chat')
        check(any(line.find('bob: filler line') == 16 for line in screens.get('back', [])), 'SCREEN 6 uses the 85 column layout (chat from column 16)')
    if TIMING:
        timing_report(dumps, failures)
    print('Test artifacts:', work, flush=True)
    fixture.shutdown()
    fixture.server_close()
    if failures:
        sys.exit(1)


if __name__ == '__main__':
    main()
