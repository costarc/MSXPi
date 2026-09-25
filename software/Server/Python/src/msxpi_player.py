"""Cross-platform mpv music-player controller for MSXPi.

Each play request owns an independent mpv process. The process ID returned to
the MSX is the handle for pause, resume, and stop.
"""

import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
from urllib.parse import urljoin


class PlayerError(RuntimeError):
    pass


class MpvPlayer:
    def __init__(self, base_path, executable=None):
        self.base_path = Path(base_path)
        self.executable = executable or self._default_executable()
        self.players = {}
        self._counter = 0

    @staticmethod
    def _default_executable():
        if os.name == "nt":
            bundled = Path(r"C:\Apps\mpv\mpv.exe")
            return str(bundled) if bundled.exists() else "mpv.exe"
        return shutil.which("mpv") or "/usr/bin/mpv"

    def _new_endpoint(self):
        self._counter += 1
        if os.name == "nt":
            return rf"\\.\pipe\msxpi-mpv-{os.getpid()}-{self._counter}"
        path = Path(tempfile.gettempdir()) / f"msxpi-mpv-{os.getpid()}-{self._counter}.sock"
        try:
            path.unlink()
        except FileNotFoundError:
            pass
        return str(path)

    def _connect(self, endpoint):
        deadline = time.monotonic() + 10
        if os.name == "nt":
            while time.monotonic() < deadline:
                try:
                    return open(endpoint, "r+b", buffering=0)
                except OSError:
                    time.sleep(0.05)
            raise PlayerError("Timed out connecting to mpv named pipe")
        while time.monotonic() < deadline:
            try:
                io = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                io.connect(endpoint)
                return io
            except OSError:
                time.sleep(0.05)
        raise PlayerError("Timed out connecting to mpv socket")

    @staticmethod
    def _send(io, command):
        payload = (json.dumps({"command": command}) + "\n").encode()
        if os.name == "nt":
            io.write(payload)
        else:
            io.sendall(payload)

    def _target(self, media):
        if media.startswith(("http://", "https://")):
            return media
        if str(self.base_path).startswith(("http://", "https://")):
            return urljoin(str(self.base_path).rstrip("/") + "/", media)
        target = Path(media)
        if not target.is_absolute():
            target = self.base_path / target
        if not target.is_file():
            raise PlayerError(f"File not found: {target}")
        return str(target)

    def set_base_path(self, base_path):
        self.base_path = (base_path if str(base_path).startswith(("http://", "https://"))
                          else Path(base_path))

    def play(self, media, loop=False):
        if not media:
            raise PlayerError("A music filename is required")
        endpoint = self._new_endpoint()
        args = [self.executable, "--idle=yes", "--no-video", "--force-window=no",
                "--really-quiet", f"--input-ipc-server={endpoint}"]
        process = None
        io = None
        try:
            process = subprocess.Popen(args, stdin=subprocess.DEVNULL)
            io = self._connect(endpoint)
            pid = process.pid
            self.players[pid] = (process, io)
            self._send(io, ["loadfile", self._target(media), "replace"])
            self._send(io, ["set_property", "loop-file", "inf" if loop else "no"])
            return str(pid)
        except Exception:
            if io is not None:
                io.close()
            if process is not None:
                process.terminate()
            raise

    def _player(self, pid):
        try:
            pid = int(pid)
        except (TypeError, ValueError) as exc:
            raise PlayerError("A numeric process ID is required") from exc
        player = self.players.get(pid)
        if player is None:
            raise PlayerError(f"Unknown music process: {pid}")
        return pid, player

    def _command_for(self, pid, command):
        _, (_, io) = self._player(pid)
        self._send(io, command)
        return "Ok"

    def pause(self, pid):
        return self._command_for(pid, ["set_property", "pause", True])

    def resume(self, pid):
        return self._command_for(pid, ["set_property", "pause", False])

    def stop(self, pid):
        pid, (process, io) = self._player(pid)
        try:
            self._send(io, ["quit"])
        finally:
            io.close()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
            self.players.pop(pid, None)
        return "Ok"

    def stop_all(self):
        for pid in list(self.players):
            self.stop(pid)
        return "Ok"

    def volume(self, value, pid=None):
        value = max(0, min(100, int(value)))
        if pid is not None:
            return self._command_for(pid, ["set_property", "volume", value])
        for process, io in list(self.players.values()):
            self._send(io, ["set_property", "volume", value])
        return "Ok"

    def list_ids(self):
        return "\n".join(str(pid) for pid in self.players)

    def list_media(self, directory="."):
        if str(self.base_path).startswith(("http://", "https://")):
            raise PlayerError("Cannot list a remote MSXPi path")
        target = self.base_path / directory
        extensions = {".mp3", ".wav", ".ogg", ".flac", ".m4a", ".aac"}
        return "\n".join(sorted(item.name for item in target.iterdir()
                                  if item.is_file() and item.suffix.lower() in extensions))

    def close(self):
        for pid in list(self.players):
            try:
                self.stop(pid)
            except Exception:
                process, io = self.players.pop(pid)
                try:
                    io.close()
                finally:
                    process.kill()
