"""On-demand NitrOS-9/Becker console. No emulator is started on import.

The supported DriveWire subset serves raw 256-byte-sector OS-9 disks and
virtual channels 0 (console) and 1 (explicit guest shutdown). See the NitrOS-9 for MSX user guide.
"""
from __future__ import annotations

import atexit
from collections import deque
from datetime import datetime
import json
import os
from pathlib import Path
import re
import shlex
import signal
import socket
import subprocess
import threading
import time

PACKET_SIZE = 256
PAYLOAD_SIZE = 248
QUEUE_LIMIT = 65536


def lock_image(image):
    """Take an exclusive, non-blocking lock on a disk image on either OS."""
    image.seek(0)
    try:
        import fcntl

        fcntl.flock(image, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except ImportError:  # Windows
        import msvcrt

        msvcrt.locking(image.fileno(), msvcrt.LK_NBLCK, 1)


def packet(state, data=b''):
    data = data[:PAYLOAD_SIZE]
    return b'NTR1' + bytes((state, len(data))) + b'\0\0' + data.ljust(PAYLOAD_SIZE, b'\0')


def receive(sock, size):
    data = bytearray()
    while len(data) < size:
        part = sock.recv(size - len(data))
        if not part:
            raise EOFError('XRoar disconnected')
        data.extend(part)
    return bytes(data)


class DriveWire:
    """One session, one Becker connection; never exposes host paths to guest."""
    def __init__(self, images):
        self.images = images
        self.sectors = []
        for image in images:
            image.seek(0)
            self.sectors.append(int.from_bytes(image.read(3), 'big'))
        self.keys = deque()
        self.output = deque()
        self.lock = threading.Lock()
        self.exit_requested = False
        self.control = bytearray()

    def write_console(self, channel, data):
        with self.lock:
            if channel == 0:
                if len(self.output) + len(data) > QUEUE_LIMIT:
                    raise ValueError('Console overflow; session stopped')
                self.output.extend(data)
            elif channel == 1:
                self.control.extend(data)
                if len(self.control) > 64:
                    raise ValueError('Invalid guest control message')
                if self.control == b'MSXPI-EXIT\r':
                    self.exit_requested = True

    def sector(self, drive, lsn, data=None):
        if drive >= len(self.images):
            return 246, bytes(256)  # E$NotRdy
        image = self.images[drive]
        if lsn >= self.sectors[drive]:
            return 211, bytes(256)  # E$EOF
        image.seek(lsn * 256)
        if data is None:
            return 0, image.read(256).ljust(256, b'\0')
        image.write(data)
        image.flush()
        return 0, b''

    def serve(self, sock, stop):
        while not stop.is_set() and not self.exit_requested:
            op = receive(sock, 1)[0]
            if op in (0, 0x49, 0x54, 0xF8, 0xFE, 0xFF):
                continue
            if op == 0x5A:
                receive(sock, 1)
                sock.sendall(b'\x04')  # Standard DriveWire 4
            elif op == 0x23:
                now = datetime.now()
                sock.sendall(bytes((now.year - 1900, now.month, now.day,
                                    now.hour, now.minute, now.second)))
            elif op in (0xD2, 0xF2):  # READEX, REREADEX
                header = receive(sock, 4)
                rc, block = self.sector(header[0], int.from_bytes(header[1:], 'big'))
                sock.sendall(block)
                checksum = int.from_bytes(receive(sock, 2), 'big')
                sock.sendall(bytes((rc or (0 if checksum == sum(block) else 243),)))
            elif op in (0x57, 0x77):
                header = receive(sock, 4)
                block = receive(sock, 256)
                checksum = int.from_bytes(receive(sock, 2), 'big')
                rc = 243
                if checksum == sum(block):
                    rc, _ = self.sector(header[0], int.from_bytes(header[1:], 'big'), block)
                sock.sendall(bytes((rc,)))
            elif op in (0x47, 0x53):  # disk Get/SetStat: drive, status
                receive(sock, 2)
            elif op in (0x45, 0xC5):
                channel = receive(sock, 1)[0]
                if channel == 1 and op == 0x45:
                    self.control.clear()
            elif op in (0x44, 0xC4):
                channel, code = receive(sock, 2)
                if op == 0x44 and code == 0x27:  # SS.KySns
                    sock.sendall(b'\0')  # no CoCo modifier keys held
                if op == 0xC4 and code == 0x28:
                    receive(sock, 26)
            elif op == 0x43:
                with self.lock:
                    if len(self.keys) >= 3:
                        answer = bytes((17, min(255, len(self.keys))))
                    else:
                        answer = bytes((1, self.keys.popleft())) if self.keys else b'\0\0'
                sock.sendall(answer)
            elif op == 0x63:
                channel, count = receive(sock, 2)
                with self.lock:
                    if channel != 0 or count > len(self.keys):
                        raise ValueError('Invalid console read')
                    data = bytes(self.keys.popleft() for _ in range(count))
                sock.sendall(data)
            elif op == 0xC3:
                channel, char = receive(sock, 2)
                self.write_console(channel, bytes((char,)))
            elif 0x80 <= op <= 0x8F:
                self.write_console(op - 0x80, receive(sock, 1))
            elif op == 0x64:
                channel, count = receive(sock, 2)
                self.write_console(channel, receive(sock, count))
            else:
                raise ValueError('Unsupported DriveWire opcode %02x' % op)


class Session:
    def __init__(self):
        self.lock = threading.RLock()
        self.process = None
        self.listener = None
        self.connection = None
        self.worker = None
        self.images = []
        self.log = None
        self.stop_event = threading.Event()
        self.bridge = None
        self.error = ''
        self.last_poll = 0
        self.lease = 15

    def start(self, config):
        with self.lock:
            if self.process is not None:
                raise ValueError('NitrOS-9 is already running')
            self.error = ''
            self.stop_event = threading.Event()
            try:
                self.lease = max(5, min(120, float(config.get('lease_seconds', 15))))
                for name in ('boot_disk', 'exchange_disk'):
                    image = open(config[name], 'r+b')
                    self.images.append(image)
                    # Protect against a second MSXPi server or exchange tool.
                    lock_image(image)
                    if os.fstat(image.fileno()).st_size % 256:
                        raise ValueError('Disk size must be a multiple of 256')
                self.bridge = DriveWire(self.images)
                self.listener = socket.socket()
                self.listener.bind(('127.0.0.1', 0))
                self.listener.listen(1)
                self.listener.settimeout(0.2)
                port = self.listener.getsockname()[1]
                command = config['xroar']
                if not isinstance(command, list) or not command or not all(isinstance(x, str) for x in command):
                    raise ValueError('xroar must be a nonempty JSON argument list')
                command = command + ['-becker-ip', '127.0.0.1', '-becker-port', str(port)]
                self.log = open(config.get('log', str(Path(config['boot_disk']).with_suffix('.log'))), 'ab')
                process_options = (
                    {'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP}
                    if os.name == 'nt' else {'start_new_session': True}
                )
                self.process = subprocess.Popen(
                    command, stdin=subprocess.DEVNULL, stdout=self.log,
                    stderr=self.log, **process_options
                )
                self.last_poll = time.monotonic()
                self.worker = threading.Thread(target=self._run, args=(self.listener, self.bridge, self.stop_event), daemon=True)
                self.worker.start()
                threading.Thread(target=self._watch, args=(self.stop_event,), daemon=True).start()
            except Exception:
                self.close()
                raise

    def _run(self, listener, bridge, event):
        try:
            while not event.is_set():
                try:
                    connection, _ = listener.accept()
                    break
                except socket.timeout:
                    continue
            else:
                return
            self.connection = connection
            if event.is_set():
                connection.close()
                return
            bridge.serve(connection, event)
        except (OSError, EOFError, ValueError) as exc:
            if not event.is_set():
                self.error = str(exc)
        finally:
            event.set()

    def _watch(self, event):
        # This watchdog owns cleanup even when the MSX resets or disconnects.
        while not event.wait(0.2):
            with self.lock:
                if self.stop_event is not event or self.process is None:
                    return
                if self.process.poll() is not None:
                    self.error = 'XRoar exited; check the session log'
                    break
                if time.monotonic() - self.last_poll > self.lease:
                    self.error = 'MSX console disconnected (lease expired)'
                    break
        with self.lock:
            if self.stop_event is event:
                self.close()

    def poll(self, keys=b''):
        with self.lock:
            self.last_poll = time.monotonic()
            if len(keys) > 32:
                raise ValueError('At most 32 keys per poll')
            data = b''
            if self.bridge:
                with self.bridge.lock:
                    if len(self.bridge.keys) + len(keys) > 1024:
                        raise ValueError('Keyboard queue full')
                    self.bridge.keys.extend(keys)
                    data = bytes(self.bridge.output.popleft()
                                 for _ in range(min(PAYLOAD_SIZE, len(self.bridge.output))))
            running = self.process is not None and not self.stop_event.is_set()
            if data:
                return packet(1 if running else 2, data)
            return packet(1 if running else (3 if self.error else 0), self.error.encode('ascii', 'replace'))

    def close(self):
        with self.lock:
            self.stop_event.set()
            if self.process is not None:
                if self.process.poll() is None:
                    try:
                        if os.name == 'nt':
                            self.process.terminate()
                        else:
                            os.killpg(self.process.pid, signal.SIGTERM)
                        self.process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        if os.name == 'nt':
                            self.process.kill()
                        else:
                            os.killpg(self.process.pid, signal.SIGKILL)
                        self.process.wait(timeout=3)
                    except ProcessLookupError:
                        self.process.wait(timeout=3)
                self.process = None
            if self.connection:
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                self.connection.close()
                self.connection = None
            if self.listener:
                self.listener.close()
                self.listener = None
            worker = self.worker
            self.worker = None
            if worker and worker is not threading.current_thread():
                worker.join(timeout=2)
            for image in self.images:
                image.flush()
                os.fsync(image.fileno())
                image.close()
            self.images = []
            if self.log:
                self.log.close()
                self.log = None


session = Session()
atexit.register(session.close)


def load_config():
    # Use the existing MSXPi p set configuration so the host-side NitrOS
    # runtime can be selected from the MSX. This is a path to the detailed
    # JSON runtime config, stored alongside the other MSXPi variables.
    from msxpi_settings import getMSXPiVar, MSXPIHOME

    path = getMSXPiVar('NITROS_CONFIG') or str(Path(MSXPIHOME) / 'nitros' / 'nitros.json')
    path = Path(path).resolve()
    config = json.loads(path.read_text())
    for name in ('boot_disk', 'exchange_disk', 'exchange_dir', 'log'):
        if name in config:
            config[name] = str((path.parent / config[name]).resolve())
    return config


def exchange(config, action, args):
    """Binary-safe transfer via ToolShed, with the guest image locked offline."""
    if session.process is not None:
        raise ValueError('Close NitrOS-9 before exchanging files')
    root = Path(config['exchange_dir']).resolve()
    root.mkdir(parents=True, exist_ok=True)
    page = 0
    if action == 'list':
        if len(args) > 1 or (args and not args[0].isdigit()):
            raise ValueError('Use list [page-number]')
        page = int(args[0]) if args else 0
        command = [config.get('os9', 'os9'), 'dir', config['exchange_disk'] + ',']
    else:
        if len(args) != 2 or any(not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]{0,28}', x) for x in args):
            raise ValueError('Use two plain filenames (no directories)')
        host, guest = args if action == 'put' else args[::-1]
        hostpath = root / host
        if hostpath.is_symlink():
            raise ValueError('Symlinks are not supported')
        if action == 'get' and hostpath.exists():
            raise ValueError('Destination already exists')
        diskpath = config['exchange_disk'] + ',' + guest
        endpoints = [str(hostpath), diskpath] if action == 'put' else [diskpath, str(hostpath)]
        command = [config.get('os9', 'os9'), 'copy'] + endpoints
    with open(config['exchange_disk'], 'r+b') as image:
        lock_image(image)
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    if result.returncode:
        raise ValueError(result.stdout.decode('ascii', 'replace')[:200])
    if action == 'list':
        start = page * 210
        data = result.stdout[start:start+210]
        if start + 210 < len(result.stdout):
            data += ('\r\nMore: NITROS list %d\r\n' % (page + 1)).encode()
        return data or b'End of directory\r\n'
    return b'File copied\r\n'


def handle_command(arguments):
    try:
        args = shlex.split(arguments or '')
        action = args.pop(0).lower() if args else 'start'
        if action == 'start' and not args:
            session.start(load_config())
            return session.poll()
        if action == 'poll' and len(args) <= 1:
            return session.poll(bytes.fromhex(args[0]) if args else b'')
        if action == 'stop' and not args:
            session.close()
            return packet(0, b'NitrOS-9 closed\r\n')
        if action in ('put', 'get', 'list'):
            return packet(0, exchange(load_config(), action, args))
        raise ValueError('Use start, poll, stop, put HOST GUEST, get GUEST HOST, list')
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        return packet(3, str(exc).encode('ascii', 'replace'))


def nitros(arguments=None):
    from msxpi_blocks import sendmultiblock
    return sendmultiblock(handle_command(arguments))
