"""Windows two-server/two-openMSX multiplayer test; owns all spawned PIDs.

Run with Windows Python. Requires chess on PYTHONPATH or installed.
"""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import threading
import secrets
import json
from pchess_irc_fixture import Server

software=Path(__file__).resolve().parents[3]
work=Path(tempfile.mkdtemp(prefix='pchess-dual-',dir=software.parent/'work'))
exe=Path('C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.6/openmsx.exe')
floppy=Path('C:/Users/roniv/Dev/MSX/MSXPi/FloppyA')
real_irc='--real-irc' in sys.argv
config_paths=[os.environ.get('PCHESS_TEST_INI_1'),os.environ.get('PCHESS_TEST_INI_2')]
def read_nick(path):
    for line in Path(path).read_text().splitlines():
        if line.startswith('var IRCNICK='): return line.split('=',1)[1].strip()
    raise ValueError('Test INI needs IRCNICK')
irc='--irc' in sys.argv or real_irc
nicks=['pch'+secrets.token_hex(2)+suffix for suffix in ('a','b')] if real_irc else ['alice','bob']
if real_irc and all(config_paths): nicks=[read_nick(path) for path in config_paths]
ports=(5041,5042,5081)
for port in ports:
    with socket.socket() as probe:
        if hasattr(socket,'SO_EXCLUSIVEADDRUSE'):
            probe.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
        probe.bind(('127.0.0.1',port))
processes=[]
logs=[]
fixture=None
def start(args,env=None):
    log=(work/f'process-{len(processes)}.log').open('w')
    logs.append(log)
    proc=subprocess.Popen(args,cwd=software/'Server/Python/src',env=env,
                          stdout=log,stderr=subprocess.STDOUT)
    processes.append(proc)
    (work/'owned-processes.json').write_text(json.dumps([
        {'pid':p.pid,'args':p.args} for p in processes],indent=2))
    return proc

try:
    if irc and not real_irc:
        fixture=Server(('127.0.0.1',5081))
        threading.Thread(target=fixture.serve_forever,daemon=True).start()
    elif not irc:
        start([sys.executable,'msxpi_pchess.py','--port','5081'])
    for i,port in enumerate(ports[:2]):
        env=os.environ.copy()
        env.update(MSXPI_PORT=str(port),PCHESS_RELAY_URL='http://127.0.0.1:5081')
        if real_irc and config_paths[i]: env['MSXPI_INI']=config_paths[i]
        if irc:
            env['PCHESS_IRC_NICK']=nicks[i]
            env['PCHESS_IRC_TRACE']='1'
            if not real_irc:
                env.update(PCHESS_IRC_HOST='127.0.0.1',PCHESS_IRC_PORT='5081',PCHESS_IRC_TLS='0')
        start([sys.executable,'-u','msxpi-server.py'],env)
    time.sleep(2)
    emulators=[]
    for i,port in enumerate(ports[:2]):
        # Join order is deterministic; white starts first, black six seconds later.
        script=work/f'client-{i}.tcl'
        script.write_text(f'''
set save_settings_on_exit off
set msxpiserver_port {port}
set speed 100
set power on
set pause off
after time 23 {{type_via_keybuf "c:\\r"}}
after time 25 {{type_via_keybuf "dir pchess.com\\r"}}
after time 28 {{type_via_keybuf "pchess\\r"}}
after time {38+i*6} {{type_via_keybuf "3"}}
after time {40+i*6} {{type_via_keybuf "dualtest\\r"}}
after time {56+i*8} {{type_via_keybuf "{'e2e4' if i==0 else 'e7e5'}\\r"}}
after time 82 {{
    set f [open {{{work.as_posix()}/client-{i}.result}} w]
    set white [debug read VRAM [expr {{116+116*256}}]]
    set black [debug read VRAM [expr {{116+92*256}}]]
    puts $f "white=$white black=$black"
    if {{$white==255 && $black==0}} {{puts $f PASS}} else {{puts $f FAIL}}
    close $f
    screenshot -raw {{{work.as_posix()}/client-{i}.png}}
    type_via_keybuf "1"
    after time 4 {{
        set clean 1
        for {{set x 205}} {{$x<237}} {{incr x}} {{
            if {{[debug read VRAM [expr {{$x+41*256}}]]!=0}} {{set clean 0}}
        }}
        set f [open {{{work.as_posix()}/client-{i}.result}} a]
        if {{$clean}} {{puts $f "PASS: new game clears history"}} else {{puts $f "FAIL: stale history"}}
        close $f
        exit
    }}
}}
''')
        if irc:
            content=script.read_text()
            content=content.replace(f'after time {38+i*6} {{type_via_keybuf "3"}}',
                'after time 38 {type_via_keybuf "4"}')
            content=content.replace(f'after time {40+i*6} {{type_via_keybuf "dualtest\\r"}}',
                ('after time 44 {type_via_keybuf "5"}\n'
                 'after time 48 {type_via_keybuf "6"}\n'
                 'after time 50 {type_via_keybuf "bob\\r"}') if i==0 else
                 'after time 57 {type_via_keybuf "7"}')
            content=content.replace(f'after time {56+i*8}',f'after time {68+i*8}')
            if i==0:
                content=content.replace('type_via_keybuf "e2e4\\r"',
                    'type_via_keybuf " "; after time 0.25 {type_via_keybuf [format "%c" 30]; '
                    'after time 0.25 {type_via_keybuf [format "%c" 30]; '
                    'after time 0.25 {type_via_keybuf " "}}}')
            content=content.replace('after time 82','after time 95')
            content=content.replace('bob\\r',nicks[1]+'\\r')
            if real_irc:
                for old in (95,76,68,57,50,48,44):
                    content=content.replace(f'after time {old} ',f'after time {old+45} ')
            script.write_text(content)
        emulators.append(start([str(exe),'-machine','Panasonic_FS-A1WSX',
            '-ext','MSXPi','-ext','ram4mb','-diska',str(floppy),'-script',str(script)]))
    deadline=time.monotonic()+(300 if real_irc else 180)
    while any(p.poll() is None for p in emulators):
        if real_irc:
            for i in range(2):
                lines=(work/f'process-{i}.log').read_text(errors='replace').splitlines()
                errors=[line.split('PCHESS IRC ERROR ',1)[1] for line in lines
                        if 'PCHESS IRC ERROR ' in line]
                if errors:
                    raise RuntimeError(f'Real IRC client {i}: {errors[-1]}')
        if time.monotonic()>deadline:
            raise RuntimeError('Emulator test timed out')
        time.sleep(.2)
    for i in range(2):
        result=(work/f'client-{i}.result').read_text()
        print(f'Client {i}: {result}',flush=True)
        if 'PASS' not in result or 'FAIL' in result:
            raise RuntimeError('Multiplayer board assertion failed')
    if fixture:
        assert any(text.startswith('PCH1 MOVE') for _,_,text in fixture.transcript)
        assert all(text=='PCH1 SEEK' for _,target,text in fixture.transcript if target=='#msxpi')
        print('PASS: channel discovery only; moves exchanged privately')
    if real_irc:
        for i in range(2):
            trace=(work/f'process-{i}.log').read_text(errors='replace')
            assert 'PCHESS IRC TX '+nicks[1-i]+' :PCH1 MOVE ' in trace
            assert 'PCHESS IRC RX '+nicks[1-i]+' '+nicks[i]+' PCH1 MOVE ' in trace
            public=[line for line in trace.splitlines() if line.startswith('PCHESS IRC TX #')]
            assert all(line=='PCHESS IRC TX #msxpi :PCH1 SEEK' for line in public)
        print('PASS: real IRC private moves in both directions; channel discovery only')
finally:
    for proc in reversed(processes):
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=10)
    for log in logs: log.close()
    if fixture:
        fixture.shutdown(); fixture.server_close()
    print('Test artifacts:',work,flush=True)
