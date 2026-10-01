"""Interactive SSH terminal bridged to an MSXPi client."""
from __future__ import annotations
import atexit, errno, os, select, shlex, shutil, signal, subprocess, sys
try:
    import pty
except ImportError:
    pty = None

PAYLOAD_SIZE = 248

def packet(state, data=b''):
    data = data[:PAYLOAD_SIZE]
    return b'SSH1' + bytes((state, len(data))) + b'\0\0' + data.ljust(PAYLOAD_SIZE, b'\0')

class Session:
    def __init__(self):
        self.process = self.fd = None
        self.pending = bytearray()
    def start(self, arguments):
        if pty is None: raise ValueError('Interactive SSH requires a Unix host with a PTY')
        if self.process is not None: raise ValueError('SSH is already running')
        args = shlex.split(arguments or '')
        terminal = 'dumb'
        if args and args[0] == '--vt100':
            terminal = 'vt100'
            args.pop(0)
        if not args or len(args) > 2: raise ValueError('Use ssh USER@HOST [PORT]')
        if args[0].startswith('-') or any(c.isspace() or ord(c)<32 for c in args[0]):
            raise ValueError('Invalid SSH destination')
        if len(args) == 2 and (not args[1].isdigit() or not 1 <= int(args[1]) <= 65535):
            raise ValueError('Port must be 1..65535')
        executable = shutil.which('ssh')
        if executable is None: raise ValueError('Install the OpenSSH client on the server host')
        command = [executable, '-tt', '-o', 'EscapeChar=none', '-o', 'ConnectTimeout=15',
                   '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3']
        command += (['-p', args[1]] if len(args) == 2 else []) + ['--', args[0]]
        # Acquire the controlling terminal in a fresh interpreter, avoiding
        # preexec_fn in the potentially threaded server. SSH passwords use
        # /dev/tty, which connecting stdin/stdout to a PTY alone cannot supply.
        launcher = ('import fcntl,os,struct,sys,termios; '
                    'fcntl.ioctl(0,termios.TIOCSCTTY,0); '
                    'fcntl.ioctl(0,termios.TIOCSWINSZ,struct.pack("HHHH",24,80,0,0)); '
                    'os.execv(sys.argv[1],sys.argv[1:])')
        self.fd, slave = pty.openpty()
        try:
            self.process = subprocess.Popen([sys.executable, '-c', launcher] + command,
                                            stdin=slave, stdout=slave, stderr=slave,
                                            env=dict(os.environ, TERM=terminal),
                                            start_new_session=True, close_fds=True)
            os.set_blocking(self.fd, False)
        except BaseException:
            self.close()
            raise
        finally: os.close(slave)
    def poll(self, incoming=b''):
        if self.process is None: raise ValueError('SSH is not running')
        if len(incoming)>30 or len(self.pending)+len(incoming)>4096:
            raise ValueError('SSH input buffer full')
        self.pending.extend(incoming)
        if self.pending:
            try:
                count = os.write(self.fd, self.pending)
                del self.pending[:count]
            except BlockingIOError: pass
            except OSError as exc:
                if exc.errno != errno.EIO: raise
        data = bytearray()
        eof = False
        while len(data) < PAYLOAD_SIZE:
            ready, _, _ = select.select([self.fd], [], [], 0)
            if not ready: break
            try: chunk = os.read(self.fd, PAYLOAD_SIZE-len(data))
            except BlockingIOError: break
            except OSError as exc:
                if exc.errno != errno.EIO: raise
                chunk = b''
            if not chunk:
                eof = True
                break
            data.extend(chunk)
        if eof:
            self.close(); return packet(3, bytes(data) or b'SSH closed\r\n')
        return packet(1, bytes(data))
    def close(self):
        process, fd = self.process, self.fd
        self.process = self.fd = None
        self.pending.clear()
        if process is not None:
            try: os.killpg(process.pid, signal.SIGHUP)
            except ProcessLookupError: pass
            try: process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        if fd is not None: os.close(fd)

session = Session()
atexit.register(session.close)

def handle_command(arguments):
    try:
        args = shlex.split(arguments or '')
        action = args.pop(0).lower() if args else 'start'
        if action == 'start': session.start(' '.join(shlex.quote(x) for x in args)); return session.poll()
        if action == 'poll' and len(args) <= 1: return session.poll(bytes.fromhex(args[0]) if args else b'')
        if action == 'stop' and not args: session.close(); return packet(3, b'SSH closed\r\n')
        raise ValueError('Use start USER@HOST [PORT], poll [hex], stop')
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        session.close(); return packet(3, str(exc).encode('ascii', 'replace'))

def ssh(arguments=None):
    from msxpi_blocks import sendmultiblock
    # This handler owns the response transfer. Return None so the generic
    # command dispatcher never attempts a second reply after sendmultiblock.
    sendmultiblock(handle_command(arguments))
