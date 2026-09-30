"""Real-emulator integration test (Ubuntu/WSL or Pi).

Usage: python3 nitros_xroar.py /absolute/path/nitros.json
Uses temporary copies of both guest disks; does not alter installed images.
"""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from msxpi_nitros import Session, exchange

configpath = Path(sys.argv[1]).resolve()
config = json.loads(configpath.read_text())
for name in ('boot_disk', 'exchange_disk'):
    config[name] = str((configpath.parent / config[name]).resolve())

with tempfile.TemporaryDirectory(prefix='nitros-xroar-') as tmp:
    root = Path(tmp)
    for name in ('boot_disk', 'exchange_disk'):
        shutil.copyfile(config[name], root / name)
        config[name] = str(root / name)
    config['exchange_dir'] = str(root / 'files')
    config['log'] = str(root / 'xroar.log')
    (root/'files').mkdir()
    binary = bytes(range(256)) * 5 + b'\x00\xff\x1a\r\n'
    (root/'files'/'INPUT.BIN').write_bytes(binary)
    exchange(config, 'put', ['INPUT.BIN', 'INPUT.BIN'])
    session = Session()
    transcript = bytearray()

    def until(marker, timeout=30):
        start = len(transcript)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            reply = session.poll()
            transcript.extend(reply[8:8+reply[5]])
            if marker in transcript[start:]:
                return
            if reply[4] in (0, 3):
                raise AssertionError('Session stopped: ' + session.error)
            time.sleep(.02)
        raise AssertionError('Timed out waiting for ' + repr(marker))

    def command(text):
        encoded = text.encode('ascii') + b'\r'
        for pos in range(0, len(encoded), 32):
            reply = session.poll(encoded[pos:pos+32])
            transcript.extend(reply[8:8+reply[5]])
        until(b'OS9:')

    try:
        session.start(config)
        process = session.process
        until(b'OS9:')
        command('echo MSXPI-BOOT-OK')
        assert b'\r\nMSXPI-BOOT-OK\r\n' in transcript
        command('copy /x1/INPUT.BIN /x1/OUTPUT.BIN')
        # Close inside NitrOS-9, through the dedicated guest control channel.
        session.poll(b'msxexit\r')
        deadline = time.monotonic() + 15
        while session.process is not None and time.monotonic() < deadline:
            session.poll()
            time.sleep(.02)
        assert process.poll() is not None, 'Guest exit left XRoar running'
        assert not session.error, session.error
        session.close()  # synchronize disk unlock before ToolShed accesses it
        exchange(config, 'get', ['OUTPUT.BIN', 'RETURN.BIN'])
        assert (root/'files'/'RETURN.BIN').read_bytes() == binary
        session.start(config)
        until(b'OS9:')
        process = session.process
        session.close()
        assert process.poll() is not None, 'MSX close left XRoar running'
        print('PASS: boot, keyboard, shell, guest exit, binary file round trip, restart, MSX close')
    except Exception:
        print(transcript.decode('ascii', 'replace'))
        print((root/'xroar.log').read_text(errors='replace'))
        raise
    finally:
        session.close()
