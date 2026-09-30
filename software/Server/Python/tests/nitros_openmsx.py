"""End-to-end MSX VDP/keyboard test on Linux (including Ubuntu WSL).

xvfb-run -a python3 nitros_openmsx.py /path/to/nitros.json [openmsx] [esc|guest]
Requires an openMSX build with MSXPiDevice, Panasonic_FS-A1WSX ROMs,
and the existing MSXPi server dependencies. Uses temporary guest/MSX disks.
"""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time

software = Path(__file__).resolve().parents[3]
configpath = Path(sys.argv[1]).resolve()
config = json.loads(configpath.read_text())
exe = sys.argv[2] if len(sys.argv) > 2 else 'openmsx'
exit_mode = sys.argv[3] if len(sys.argv) > 3 else 'esc'
assert exit_mode in ('esc', 'guest')
with tempfile.TemporaryDirectory(prefix='nitros-openmsx-') as tmp:
    root = Path(tmp)
    (root/'floppy').mkdir()
    (root/'share/extensions').mkdir(parents=True)
    for name in ('MSXDOS.SYS', 'COMMAND.COM'):
        shutil.copyfile(software/'target/disks'/name, root/'floppy'/name)
    shutil.copyfile(software/'target/nitros.com', root/'floppy/NITROS.COM')
    for name in ('msxpiboot.dsk', 'tools.dsk'):
        shutil.copyfile(software/'target/disks'/name, root/name)
    for name in ('boot_disk', 'exchange_disk'):
        source = (configpath.parent/config[name]).resolve()
        shutil.copyfile(source, root/name)
        config[name] = str(root/name)
    config['log'] = str(root/'xroar.log')
    config['exchange_dir'] = str(root/'files')
    # Record only the PID belonging to this test, then exec the real emulator.
    wrapper = ('import os,sys; from pathlib import Path; '
               'Path(sys.argv[1]).write_text(str(os.getpid())); '
               'os.execvp(sys.argv[2],sys.argv[2:])')
    config['xroar'] = [sys.executable, '-c', wrapper, str(root/'xroar.pid')] + config['xroar']
    (root/'nitros.json').write_text(json.dumps(config))
    xml = (software/'MSXPi.xml.template').read_text()
    xml = xml.replace('<sha1>msxpibiossha</sha1>', '')
    xml = xml.replace('<filename>msxpibios.rom</filename>',
                      f'<filename>{software}/target/msxpibios.rom</filename>')
    (root/'share/extensions/NitrosTest.xml').write_text(xml)
    (root/'msxpi.ini').write_text(
        f'var PATH={root}\nvar DriveA={root}/msxpiboot.dsk\n'
        f'var DriveB={root}/tools.dsk\nvar SPI_HW=False\nvar RPI_SHUTDOWN=none\n'
        f'var NITROS_CONFIG={root}/nitros.json\n')
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    script = '''
set save_settings_on_exit off
set renderer SDLGL-PP
set msxpiserver_port PORT
set speed 100
set power on
set pause off
proc capture {name} {
    set f [open "$::env(NITROS_TEST_WORK)/$name.vram" wb]
    fconfigure $f -translation binary
    puts -nonewline $f [debug read_block VRAM 0 16384]
    close $f
}
after time 20 {capture boot; type_via_keybuf "c:\\r"}
after time 23 {type_via_keybuf "nitros\\r"}
after time 40 {capture nitros; type_via_keybuf "dir\\r"}
after time 48 {capture directory; type_via_keybuf "echo MSX-VDP-OK\\r"}
after time 60 {capture echo; EXIT_ACTION}
after time 70 {capture closed; exit}
'''.replace('PORT', str(port)).replace('EXIT_ACTION',
        'type_via_keybuf "msxexit\\r"' if exit_mode == 'guest'
        else 'type_via_keybuf [format "%c" 27]')
    (root/'test.tcl').write_text(script)
    env = dict(os.environ, MSXPI_HOME=str(root), MSXPI_INI=str(root/'msxpi.ini'),
               MSXPI_PORT=str(port),
               OPENMSX_USER_DATA=str(root/'share'), NITROS_TEST_WORK=str(root),
               SDL_AUDIODRIVER='dummy')
    server = None
    try:
        with (root/'server.log').open('w') as serverlog, (root/'openmsx.log').open('w') as msxlog:
            server = subprocess.Popen([sys.executable, '-u', str(software/'Server/Python/src/msxpi-server.py')],
                                      env=env, stdout=serverlog, stderr=subprocess.STDOUT)
            time.sleep(1)
            assert server.poll() is None, 'MSXPi server failed to start'
            assert not (root/'xroar.pid').exists(), 'Emulator started before MSX launch'
            subprocess.run([exe, '-machine', 'Panasonic_FS-A1WSX', '-ext', 'NitrosTest',
                            '-diska', str(root/'floppy'), '-script', str(root/'test.tcl')],
                           env=env, stdout=msxlog, stderr=subprocess.STDOUT, timeout=150, check=True)
        assert b'OS9:' in (root/'nitros.vram').read_bytes(), 'Guest shell not displayed on VDP'
        assert b'Directory of' in (root/'directory.vram').read_bytes(), 'DIR did not execute after Enter'
        assert (root/'echo.vram').read_bytes().count(b'MSX-VDP-OK') >= 2, 'Guest did not echo the MSX keyboard command'
        closed = (root/'closed.vram').read_bytes()
        if exit_mode == 'esc':
            assert b'NitrOS-9 closed' in closed, 'ESC did not close the client'
        else:
            assert b'OS9:msxexit' in closed, 'MSXEXIT was not submitted'
            assert b'C:' in closed.split(b'OS9:msxexit', 1)[1], 'MSXEXIT did not return to DOS'
        pid = int((root/'xroar.pid').read_text())
        assert not Path('/proc', str(pid)).exists(), f'{exit_mode} left XRoar running'
        print(f'PASS: NITROS.COM launch, DIR and ECHO via Enter, VDP output, {exit_mode} exit, XRoar reaped')
    except Exception:
        for name in ('server.log', 'openmsx.log', 'xroar.log'):
            p = root/name
            if p.exists():
                print(name, '\n'.join(line for line in p.read_text(errors='replace').splitlines() if not line.endswith('-> nitros poll'))[-8000:])
        for p in root.glob('*.vram'):
            import re
            print(p.name, re.findall(rb'[ -~]{8,}', p.read_bytes()))
        raise
    finally:
        if server:
            server.terminate()
            try:
                server.wait(timeout=8)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
