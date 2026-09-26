# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

from __future__ import annotations

from typing import Optional


# Standard library imports
import logging
import atexit

# Third-party imports

logger = logging.getLogger('msxpi')

from msxpi_const import (
    CommandResult,
    RC_FAILED,
    RC_SUCCESS,
)
import msxpi_transport as transport
from msxpi_blocks import sendmultiblock
from msxpi_settings import getMSXPiVar, setMSXPiVar


try:
    from msxpi_player import MpvPlayer, PlayerError
except ImportError:
    MpvPlayer = None
    PlayerError = RuntimeError

_music_player = None


def init_player() -> None:
    """Create the mpv backend; mpv itself only starts on the first play.
    Windows uses C:\Apps\mpv\mpv.exe by default; Linux/Raspberry Pi uses
    the mpv executable found on PATH (or /usr/bin/mpv)."""
    global _music_player
    if MpvPlayer is None:
        return
    try:
        _music_player = MpvPlayer(getMSXPiVar('PATH'))
    except Exception as exc:
        print(f"Warning: music player unavailable: {exc}")
        return
    atexit.register(_music_player.close)

def play(data: str) -> CommandResult:
    if not data:
        # Always return bytes and a non-empty payload.  The MSX client waits
        # for this response even when the command has no parameters.
        help_text = (
            "Syntax:\n"
            "pmusic play|loop|pause|resume|stop|getids|getlids|list "
            "<filename|processid|directory|playlist|radio>\n"
            "Examples: pmusic play music.mp3; pmusic loop music.mp3; "
            "pmusic stop\n"
            "p music audio [card [device]|default]\n"
        )
        sendmultiblock(help_text.encode())
        return RC_FAILED
        
    cmd, _, parms = data.partition(" ")
    parms = parms.split("\x00", 1)[0].strip()
    try:
        if _music_player is None:
            raise PlayerError("mpv player is not initialized")
        # PATH is the current MSXPi directory.  It can change after startup
        # through the CD command, so never use the initialization-time value.
        _music_player.set_base_path(getMSXPiVar('PATH'))
        _music_player.audio_device = getMSXPiVar('MUSIC_AUDIO_DEVICE').strip()
        if cmd.lower() == "play":
            result = _music_player.play(parms)
        elif cmd.lower() == "loop":
            result = _music_player.play(parms, loop=True)
        elif cmd.lower() == "pause":
            result = _music_player.pause(parms)
        elif cmd.lower() == "resume":
            result = _music_player.resume(parms)
        elif cmd.lower() == "stop":
            result = _music_player.stop(parms) if parms else _music_player.stop_all()
        elif cmd.lower() == "list":
            # `p play list` is the process control form: return the IDs that
            # can be passed to pause/resume/stop.  Supplying a directory keeps
            # the existing media-file listing behavior.
            result = (_music_player.list_ids() or "No music playing\n") \
                if not parms else _music_player.list_media(parms)
        elif cmd.lower() in ("getids", "getlids"):
            result = _music_player.list_ids()
        elif cmd.lower() == "audio":
            if transport.hostType not in ("RaspberryPi", "Linux"):
                raise PlayerError("Audio card selection requires Linux/ALSA")
            result = _music_player.configure_audio(
                parms, getMSXPiVar('MUSIC_AUDIO_DEVICE'),
                lambda value: setMSXPiVar('MUSIC_AUDIO_DEVICE', value))
        else:
            raise PlayerError(f"Unknown player command: {cmd}")
        sendmultiblock(str(result or "\n").encode())
        return RC_SUCCESS
    except (PlayerError, OSError, ValueError) as exc:
        sendmultiblock(f"Player error: {exc}".encode())
        return RC_FAILED

# `music` is the public command name. Keep `play` above as a compatibility
# alias for existing MSX software and scripts.
def music(data: str) -> CommandResult:
    return play(data)
    
def vol(data: Optional[str] = None) -> CommandResult:

    try:
        if _music_player is None:
            raise PlayerError("mpv player is not initialized")
        sendmultiblock(_music_player.volume(data).encode())
        return RC_SUCCESS
    except (PlayerError, ValueError) as exc:
        sendmultiblock(f"Player error: {exc}".encode())
        return RC_FAILED
