r"""Fault injection over the MSXPi link: does MSX-DOS + MSXPi recover?

Boots Canon_V-25 + MSXPi (MSX-DOS from the server's msxpiboot.dsk, a scratch
copy) against fault_server.py, which flips random bits on the link. Then runs
FI.BAT: pcopy three files from the Pi into A: - sector reads (bursts), pcopy's
own block downloads and sector writes - and MCHAT.COM back up to the Pi
(pcopy's block uploads), then "p date" to see that the command
channel still works. "Abort, Retry or Ignore" prompts are answered with R and
counted. Afterwards the copied files are extracted from the image and compared
with their sources.

    python fault_inject_openmsx.py --rate 0.0005 --seed 1 [--seed 2 ...]
        [--rom path\to\msxpi32k.rom] [--server-retries N] [--pcopy PCOPY.COM] [--timeout 600] [--dir both|rx|tx]

Outcome per run: PASS (all files identical), CORRUPT (finished, a file
differs), FAILED (finished with errors, files missing - detected, not silent),
HUNG (no FIDONE before the timeout: a desync the MSX did not get out of).
Windows Python and the openMSX MSXPi build; port 5046 must be free.
Artefacts go to <repo>/../work/fault-*/.
"""
import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOFTWARE = HERE.parents[2]
OPENMSX = os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe')
PORT = int(os.environ.get('MSXPI_TEST_PORT', '5046'))
FILES = {'FI1.COM': 'msxarch.com', 'FI2.COM': 'ssh.com', 'FI3.COM': 'pchess1.com'}
SRCDIR = Path('C:/tmp/fi')        # short: the MSX types /tmp/fi/<name>
UPLOAD = SRCDIR / 'up.com'        # where FI.BAT uploads MCHAT.COM to


def fat12_files(image):
    """{NAME.EXT: bytes} from the root directory of an MSX-DOS FAT12 image."""
    d = Path(image).read_bytes()
    bps, spc, res, nfat, nroot = struct.unpack_from('<HBHBH', d, 11)
    spf = struct.unpack_from('<H', d, 22)[0]
    fat = d[res * bps:(res + spf) * bps]
    root = (res + nfat * spf) * bps
    data = root + nroot * 32
    out = {}
    for i in range(nroot):
        e = d[root + i * 32:root + i * 32 + 32]
        if e[0] in (0, 0xE5) or e[11] & 0x18:
            continue
        name = e[:8].decode('latin-1').rstrip() + '.' + e[8:11].decode('latin-1').rstrip()
        cl, size = struct.unpack_from('<HI', e, 26)
        buf = bytearray()
        while 2 <= cl < 0xFF0 and len(buf) < size:
            off = data + (cl - 2) * spc * bps
            buf += d[off:off + spc * bps]
            v = struct.unpack_from('<H', fat, cl * 3 // 2)[0]
            cl = v >> 4 if cl & 1 else v & 0xFFF
        out[name] = bytes(buf[:size])
    return out


def tcl_keys(text):
    return ''.join(c if c.isalnum() or c == ' ' else '\\x%02x' % ord(c) for c in text)


def one_run(a, seed):
    root = SOFTWARE.parent / 'work'
    root.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix=f'fault-s{seed}-', dir=root))
    home = work / 'home'
    (home / 'disks').mkdir(parents=True)
    image = home / 'disks/msxpiboot.dsk'
    shutil.copy(SOFTWARE / 'target/disks/msxpiboot.dsk', image)
    shutil.copy(SOFTWARE / 'target/disks/tools.dsk', home / 'disks/tools.dsk')
    (home / 'msxpi.ini').write_text(
        f'var PATH={home.as_posix()}\nvar DriveA={image.as_posix()}\n'
        f'var DriveB={(home / "disks/tools.dsk").as_posix()}\n')
    UPLOAD.unlink(missing_ok=True)
    bat = (''.join(f'pcopy /tmp/fi/{n.lower()}\r\n' for n in FILES) + 'pcopy A:MCHAT.COM /tmp/fi/up.com\r\n'
           + 'p date\r\nFIDONE\r\n')  # no ECHO in COMMAND 1.21: "? FIDONE" marks the end
    (work / 'FI.BAT').write_bytes(bat.encode())
    subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', 'FI.BAT',
                    'home/disks/msxpiboot.dsk:FI.BAT'], cwd=work, check=True, stdout=subprocess.DEVNULL)
    if a.pcopy:
        shutil.copy(a.pcopy, work / 'PCOPY.COM')
        subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', 'PCOPY.COM',
                        'home/disks/msxpiboot.dsk:PCOPY.COM'], cwd=work, check=True, stdout=subprocess.DEVNULL)

    log = (work / 'events.txt').as_posix()
    script = work / 'fault.tcl'
    script.write_text(f'''set save_settings_on_exit off
set msxpiserver_port {PORT}
set throttle on
set power on
set fiLog [open "{log}" w]
set fiStarted 0
set fiRetries 0
set fiLastRetry -10
set fiTick 0
set fiAnswered ""
proc fiNote {{msg}} {{ global fiLog; puts $fiLog "[clock seconds] $msg"; flush $fiLog }}
proc fiDump {{name}} {{
    set f [open "{work.as_posix()}/$name" w]
    catch {{puts $f [get_screen]}}
    close $f }}
proc fiPoll {{}} {{
    global fiStarted fiRetries fiLastRetry fiAnswered fiTick
    set s ""
    catch {{set s [get_screen]}}
    if {{[regexp {{Enter new (date|time)}} $s] && $s ne $fiAnswered}} {{
        set fiAnswered $s
        type_via_keybuf "\\r"
    }}
    if {{!$fiStarted && [regexp -line {{^\\s*A[:>]\\\\?\\s*$}} $s]}} {{
        set fiStarted 1
        fiNote "prompt: typing FI"
        type_via_keybuf "FI\\r"
    }}
    # only a prompt still waiting (once answered its line reads "Ignore? r"),
    # and not again within 2 s: a new prompt can scroll to an identical screen
    incr fiTick
    if {{[regexp {{Abort, Retry, Ignore\\?\\s*$}} [string trimright $s]] && $fiTick - $fiLastRetry >= 2}} {{
        incr fiRetries
        set fiLastRetry $fiTick
        fiNote "retry prompt #$fiRetries"
        if {{$fiRetries > 80}} {{ fiNote "too many retry prompts"; fiDump screen.txt; exit }}
        type_via_keybuf "r"
    }}
    if {{[regexp {{\\? FIDONE}} $s]}} {{ fiNote "FIDONE"; fiDump screen.txt; exit }}
    fiDump screen-last.txt
    after time 1 fiPoll
}}
after time 5 fiPoll
after time {a.timeout} {{fiNote "TIMEOUT"; fiDump screen.txt; exit}}
''')

    env = dict(os.environ, MSXPI_HOME=str(home), MSXPI_PORT=str(PORT), FAULT_RATE=str(a.rate),
               FAULT_SEED=str(seed), FAULT_SKIP=str(a.skip), FAULT_DIR=a.dir,
               FAULT_SERVER_RETRIES=str(a.server_retries or ''), FAULT_SRC=a.server_src or '')
    server_log = (work / 'server.log').open('w')
    server = subprocess.Popen([sys.executable, '-u', str(HERE / 'fault_server.py')], env=env,
                              stdout=server_log, stderr=subprocess.STDOUT)
    ext = ['-ext', 'ram4mb', '-ext', 'MSXPiTest' if a.rom else 'MSXPi']
    try:
        time.sleep(3)
        with (work / 'openmsx.log').open('w') as out:
            subprocess.run([OPENMSX, '-machine', 'Canon_V-25'] + ext +
                           ['-command', 'set renderer none', '-script', str(script)],
                           stdout=out, stderr=subprocess.STDOUT, timeout=a.timeout * 3 + 120)
    except subprocess.TimeoutExpired:
        (work / 'events.txt').open('a').write('openMSX killed: wall-clock timeout\n')
    finally:
        server.terminate()
        server.wait()
        server_log.close()

    events = (work / 'events.txt').read_text() if (work / 'events.txt').exists() else ''
    slog = (work / 'server.log').read_text(errors='replace')
    faults = slog.count('FAULT #')
    done = 'FIDONE' in events
    got = fat12_files(image)
    diffs = []
    for name, src in FILES.items():
        want = (SRCDIR / name.lower()).read_bytes()
        have = got.get(name)
        # an aborted pcopy leaves a clean prefix (truncated); wrong bytes are corruption
        diffs.append((name, 'missing' if have is None else 'ok' if have == want else
                      f'truncated({len(have)})' if want.startswith(have) else
                      f'DIFFERS ({len(have)} vs {len(want)} bytes)'))
    # the upload: MCHAT.COM from the image to the Pi (pcopy only renames it into
    # place after the last block, so an aborted upload leaves no file)
    want = got.get('MCHAT.COM')
    have = UPLOAD.read_bytes() if UPLOAD.exists() else None
    if have is not None:
        shutil.copy(UPLOAD, work / 'up.com')    # the next run deletes UPLOAD
    diffs.append(('UP', 'missing' if have is None else 'ok' if have == want else
                  f'DIFFERS ({len(have)} vs {len(want)} bytes)'))
    if not done:
        verdict = 'HUNG'
    elif any(s.startswith('DIFFERS') for _, s in diffs):
        verdict = 'CORRUPT'
    elif any(s == 'missing' or s.startswith('truncated') for _, s in diffs):
        verdict = 'FAILED'
    else:
        verdict = 'PASS'
    retries = events.count('retry prompt #')
    screen = (work / 'screen.txt').read_text(errors='replace') if (work / 'screen.txt').exists() else ''
    errors = sum(1 for line in screen.splitlines() if 'rror' in line or 'abort' in line)
    srv = ' '.join(f'{k}={slog.count(v)}' for k, v in (
        ('mismatch', 'checksum mismatch'), ('hs-fail', 'handshake failed'), ('out-of-step', 'out of step')))
    print(f'seed {seed}: {verdict}  faults={faults} dos-retry-prompts={retries} msx-error-lines={errors} {srv}  '
          + ' '.join(f'{n}:{s}' for n, s in diffs) + f'  [{work}]', flush=True)
    return verdict


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rate', type=float, default=0.0005, help='probability of corrupting each link byte')
    ap.add_argument('--seed', type=int, nargs='+', default=[1])
    ap.add_argument('--skip', type=int, default=0, help='link bytes left clean first')
    ap.add_argument('--dir', default='both', choices=['both', 'rx', 'tx'])
    ap.add_argument('--timeout', type=int, default=600, help='emulated seconds before a run counts as hung')
    ap.add_argument('--rom', help='32 KB ROM to test instead of the installed one (via the MSXPiTest extension)')
    ap.add_argument('--server-retries', type=int, help="override the server's MAX_BLOCK_RETRIES")
    ap.add_argument('--pcopy', help='PCOPY.COM to put on the boot disk instead of the one there')
    ap.add_argument('--server-src', help='run the msxpi-server.py in this folder (e.g. a released copy)')
    a = ap.parse_args()
    SRCDIR.mkdir(parents=True, exist_ok=True)
    for name, src in FILES.items():
        shutil.copy(SOFTWARE / 'target' / src, SRCDIR / name.lower())
    if a.rom:   # MSXPiTest.xml (openMSX share/extensions) loads C:/tmp/fi/msxpitest.rom
        shutil.copy(a.rom, SRCDIR / 'msxpitest.rom')
    results = [one_run(a, s) for s in a.seed]
    print('summary:', {v: results.count(v) for v in sorted(set(results))})


if __name__ == '__main__':
    main()
