r"""Smoke test for one MSX-DOS client against a real MSXPi server in openMSX.

Injects a .com into a scratch copy of msxpiboot.dsk, boots Canon_V-25 + MSXPi + RAM 4MB (no floppy:
A: is the MSXPi's msxpiboot.dsk, as on the real machine), types a command line, and checks that the
text screen (SCREEN 0, read back from VRAM) contains the expected strings. Used for the SDCC 4.6
port (documents/SDCC46-PORT-HANDOVER.md) to run one program at a time.

    python client_smoke_openmsx.py path\to\prog.com "prog args" "expected text" ["more text" ...]
        [--name PROG.COM] [--at 22] [--wait 15] [--extra file.com ...]

Windows Python and openMSX with the MSXPi extension; port 5044 must be free.
Artefacts go to <repo>/../work/smoke-*/ (screen.txt is the final text screen).
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
SOFTWARE = HERE.parents[1]
OPENMSX = os.environ.get('OPENMSX', 'C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6.1/openmsx.exe')
PORT = int(os.environ.get('MSXPI_TEST_PORT', '5044'))
MACHINE = os.environ.get('SMOKE_MACHINE', 'Canon_V-25')


# ssh stand-in for --fake-ssh: a line echo with a VT100 banner; "quit" ends the session.
FAKE_SSH = '''#!/usr/bin/env python3
import sys
sys.stdout.write("@x1b[2J@x1b[HFAKE SSH READY@r@n> ")
sys.stdout.flush()
for line in sys.stdin:
    line = line.strip()
    if line == "quit":
        break
    sys.stdout.write("GOT:" + line + "@r@n> ")
    sys.stdout.flush()
'''.replace('@', chr(92))


def tcl_string(text):
    return ''.join(c if c.isalnum() or c == ' ' else '\\x%02x' % ord(c) for c in text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('com')
    ap.add_argument('command')
    ap.add_argument('expect', nargs='*')
    ap.add_argument('--name', help='8.3 name on the disk (default: the file name)')
    ap.add_argument('--at', type=int, default=22, help='emulated second to type the command')
    ap.add_argument('--wait', type=int, default=15, help='seconds to let it run before reading the screen')
    ap.add_argument('--floppy', action='store_true', help='also put the files in a directory-as-disk on drive A: (machines with a drive)')
    ap.add_argument('--ext', nargs='*', default=['ram4mb', 'MSXPi'], help='openMSX extensions')
    ap.add_argument('--wsl-server', action='store_true', help='run the MSXPi server in WSL (a PTY, for the ssh command)')
    ap.add_argument('--fake-ssh', action='store_true', help='with --wsl-server: an ssh stand-in that echoes lines (no sshd needed)')
    ap.add_argument('--also-at', type=int, nargs='*', default=[], help='more screen dumps, seconds after --at; the checks look at all of them')
    ap.add_argument('--probe', help='a Tcl expression added to the final dump as "PROBE <value>" (e.g. [format %%04X [reg PC]])')
    ap.add_argument('--hold-ctrl', type=int, default=0, help='hold CTRL from power-on until this emulated second (frees memory on machines with a drive)')
    ap.add_argument('--shots', type=int, nargs='*', default=[], help='screenshots at these emulated seconds (turns the renderer on)')
    ap.add_argument('--extra', nargs='*', default=[], help='more files to put on the disk')
    a = ap.parse_args()

    root = SOFTWARE.parent / 'work'
    root.mkdir(exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='smoke-', dir=root))
    (work / 'home/disks').mkdir(parents=True)
    shutil.copy(SOFTWARE / 'target/disks/msxpiboot.dsk', work / 'home/disks/msxpiboot.dsk')
    shutil.copy(SOFTWARE / 'target/disks/tools.dsk', work / 'home/disks/tools.dsk')
    for src, name in [(a.com, a.name or Path(a.com).name.upper())] + [(e, Path(e).name.upper()) for e in a.extra]:
        shutil.copy(src, work / 'inject.bin')
        subprocess.run([sys.executable, str(SOFTWARE / 'dsktool.py'), 'copy', 'inject.bin',
                        f'home/disks/msxpiboot.dsk:{name}'], cwd=work, check=True, stdout=subprocess.DEVNULL)
    if a.floppy:
        (work / 'floppy').mkdir()
        shutil.copy(a.com, work / 'floppy' / (a.name or Path(a.com).name.upper()))
        for e in a.extra:
            shutil.copy(e, work / 'floppy' / Path(e).name.upper())
    screen = work / 'screen.txt'
    t0, t1 = a.at, a.at + a.wait + 4 * a.command.count('|')
    script = work / 'smoke.tcl'
    script.write_text('\n'.join([
        'set save_settings_on_exit off', f'set msxpiserver_port {PORT}', 'set speed 100', 'set power on',
        *(['keymatrixdown 6 0x02', f'after time {a.hold_ctrl} {{keymatrixup 6 0x02}}'] if a.hold_ctrl else []),
        'proc dump {name} {',
        '    set f [open "' + screen.parent.as_posix() + '/$name" w]',
        '    catch {puts $f [get_screen]}',
        *(['    puts $f "PROBE ' + a.probe + '"'] if a.probe else []),
        '    close $f }',
        *[f'after time {t0 + 4 * i} {{type_via_keybuf "{tcl_string(c.strip() + chr(13))}"}}' for i, c in enumerate(a.command.split('|'))],
        f'after time {t1} {{dump screen.txt}}', *[f'after time {a.at + x} {{dump screen{x}.txt}}' for x in a.also_at], *[f'after time {x} {{screenshot {screen.parent.as_posix()}/shot{x}.png}}' for x in a.shots], f'after time {t1 + 1} exit']) + '\n')

    env = dict(os.environ, MSXPI_HOME=str(work / 'home'), MSXPI_PORT=str(PORT))
    server_log = (work / 'server.log').open('w')
    srcdir = SOFTWARE / 'Server/Python/src'
    if a.wsl_server:
        def wslpath(p):
            return subprocess.run(['wsl', 'wslpath', '-a', p.as_posix()], capture_output=True, text=True).stdout.strip()
        fake = ''
        if a.fake_ssh:
            (work / 'fakebin').mkdir()
            (work / 'fakebin/ssh').write_bytes(FAKE_SSH.encode())
            fake = f'chmod +x {wslpath(work / "fakebin/ssh")}; PATH={wslpath(work / "fakebin")}:$PATH '
        cmd = (f'cd {wslpath(srcdir)} && {fake}MSXPI_HOME={wslpath(work / "home")} MSXPI_PORT={PORT} '
               f'python3 -u msxpi-server.py')
        server = subprocess.Popen(['wsl', '-e', 'sh', '-c', cmd], stdout=server_log, stderr=subprocess.STDOUT)
    else:
        server = subprocess.Popen([sys.executable, '-u', 'msxpi-server.py'], env=env,
                                  cwd=srcdir, stdout=server_log, stderr=subprocess.STDOUT)
    try:
        time.sleep(3)
        with (work / 'openmsx.log').open('w') as out:
            subprocess.run([OPENMSX, '-machine', MACHINE] + [x for e in a.ext for x in ('-ext', e)] +
                           (['-diska', str(work / 'floppy')] if a.floppy else []) + [
                            '-command', 'set speed 100' if a.shots else 'set renderer none', '-script', str(script)],
                           stdout=out, stderr=subprocess.STDOUT, timeout=120)
    finally:
        server.terminate()
        server.wait()
        server_log.close()

    text = ''.join(f.read_text(encoding='latin-1') + chr(10) for f in sorted(work.glob('screen*.txt')))
    print(text.encode('ascii', 'replace').decode())
    flat = ''.join(text.split())          # the screen wraps lines: compare without white space
    failed = [e for e in a.expect if ''.join(e.split()) not in flat]
    for e in a.expect:
        print(('PASS: ' if e not in failed else 'FAIL: ') + repr(e))
    if not text:
        print('FAIL: no screen dump')
    print('artifacts:', work)
    sys.exit(1 if failed or not text else 0)


if __name__ == '__main__':
    main()
