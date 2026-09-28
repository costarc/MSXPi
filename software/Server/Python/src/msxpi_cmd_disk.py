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
import os
import platform
import threading

# Third-party imports
import mmap

logger = logging.getLogger("msxpi")

from msxpi_const import (
    CommandResult,
    RC_FAILED,
    RC_SUCCESS,
    SECTORSIZE,
)
from msxpi_blocks import recvdata2, sendmultiblock
from msxpi_settings import getMSXPiVar
from msxpi_transport import _PROFILE

msxdos1boot = False


def msxdos_inihrd(filename, access=mmap.ACCESS_WRITE):
    """Map a disk image for the MSX drives. The mapping is of the image file
    itself, so the MSX's sector writes (dskiow) land directly in the file and
    survive however the server stops.

    This used to map a private staging copy instead, so that on Windows the
    image could be overwritten while mounted; but the copy was only synced
    back on Ctrl+C, so any other stop silently lost everything the MSX had
    saved. On Windows a mounted image cannot be replaced by another program -
    remount it (pset DriveA / reload A:) or stop the server to rebuild it."""
    if not filename or not os.path.exists(filename):
        return RC_FAILED, ""

    size = os.path.getsize(filename)
    if size <= 0:
        return RC_FAILED, ""

    fd = os.open(filename, os.O_RDWR | getattr(os, "O_BINARY", 0))
    try:
        disk = mmap.mmap(fd, size, access=access)
    finally:
        os.close(fd)  # the mapping keeps its own handle
    return RC_SUCCESS, disk


def unmount_drive(disk):
    """Flush and release a mapping returned by msxdos_inihrd(), so a remount
    does not keep the previous image file open."""
    if disk and disk != "":
        try:
            disk.flush()
            disk.close()
        except Exception as e:
            print(f"unmount_drive(): {e}")


def dosinit(parms: Optional[str] = None) -> CommandResult:
    global msxdos1boot

    rc, data = recvdata2()
    if rc == RC_SUCCESS:
        flag = data.decode().split("\x00")[0]
        if flag == "1":
            dskioini()
        else:
            msxdos1boot = False

    return rc


def dskioini(parms: Optional[str] = None) -> CommandResult:

    global msxdos1boot, sectorInfo, drive0Data, drive1Data

    # Initialize disk system parameters
    msxdos1boot = True
    sectorInfo = [0, 0, 0, 0]
    # Load the disk images into a memory mapped variable
    rc, drive0Data = msxdos_inihrd(getMSXPiVar("DriveA"))
    rc, drive1Data = msxdos_inihrd(getMSXPiVar("DriveB"))


def reload(parms: Optional[str] = None) -> CommandResult:
    """Re-opens the DriveA/DriveB disk image file (mmap) from its
    current path, without needing to restart the server. Mirrors what
    'pset DriveA <path>' already does when the variable is (re)assigned
    (msxdos_inihrd() re-mmaps the file) - useful after rebuilding a disk
    image on disk, since the existing mmap otherwise keeps the file
    handle open and doesn't pick up changes (and blocks overwriting the
    file from outside). Usage: reload A:  or  reload B:
    """
    global drive0Data, drive1Data

    driveLetter = (parms or "").strip().upper().rstrip(":").rstrip("\x00")

    if driveLetter == "A":
        varname, varname_upper = "DriveA", "A"
    elif driveLetter == "B":
        varname, varname_upper = "DriveB", "B"
    else:
        return sendmultiblock(b"Pi:Error - usage: reload A: or reload B:")

    path = getMSXPiVar(varname)
    if not path:
        return sendmultiblock(f"Pi:Error - {varname} is not set".encode())

    # Windows will not let the image be replaced while it is mapped, so a
    # remap in place would only pick up the same file again.
    if platform.system() == "Windows":
        return reload_delayed(varname_upper, path)

    rc, data = msxdos_inihrd(path)
    if rc != RC_SUCCESS:
        return sendmultiblock(f"Pi:Error - failed to reload {path}".encode())

    # Release the previous mapping only once the new one is in place, so a
    # failed reload leaves the drive usable.
    if varname_upper == "A":
        unmount_drive(drive0Data)
        drive0Data = data
    else:
        unmount_drive(drive1Data)
        drive1Data = data

    print(f"reload(): {varname} reloaded from {path}")
    return sendmultiblock(
        f"Pi:Ok - Drive {varname_upper}: reloaded from {path}".encode()
    )


# Windows only: how long 'reload' leaves a drive released for the image to be
# replaced, and the drives currently in that window (drive number -> Event set
# once the image is mapped again).
RELOAD_DELAY = 10
_remount_pending = {}


def reload_delayed(drive, path):
    """Windows 'reload': release the drive's image so it can be replaced,
    then map it again RELOAD_DELAY seconds later. The MSX cannot be asked
    to issue a second command (it may have booted from this very drive), so
    the remount runs on a timer, and dskior/dskiow hold any access to the
    drive until it is done instead of failing it."""
    global drive0Data, drive1Data

    drivenum = 0 if drive == "A" else 1
    if drivenum in _remount_pending:
        return sendmultiblock(
            f"Pi:Error - Drive {drive}: is already re-mounting".encode()
        )

    done = threading.Event()
    _remount_pending[drivenum] = done
    if drivenum == 0:
        unmount_drive(drive0Data)
        drive0Data = ""
    else:
        unmount_drive(drive1Data)
        drive1Data = ""
    print(f"reload(): Drive {drive}: released - replace {path} now")

    def remount():
        global drive0Data, drive1Data
        # The replacement may still be being copied (locked, or not there
        # yet): keep trying rather than leave the MSX without its drive.
        try:
            rc, data = msxdos_inihrd(path)
        except OSError as e:
            rc, data = RC_FAILED, str(e)
        if rc != RC_SUCCESS:
            print(f"reload(): cannot map {path} yet ({data or 'missing'}), retrying")
            t = threading.Timer(1, remount)
            t.daemon = True
            t.start()
            return
        if drivenum == 0:
            drive0Data = data
        else:
            drive1Data = data
        del _remount_pending[drivenum]
        done.set()
        print(f"reload(): Drive {drive}: re-mounted from {path}")

    t = threading.Timer(RELOAD_DELAY, remount)
    t.daemon = True
    t.start()

    return sendmultiblock(
        f"Pi:Ok - Drive {drive}: released, re-mounting in {RELOAD_DELAY} seconds".encode()
    )


def wait_remount(drivenum):
    """Block a disk access until a pending Windows 'reload' has re-mapped
    the drive; returns at once otherwise."""
    done = _remount_pending.get(drivenum)
    if done:
        print(f"Drive {'AB'[drivenum]}: access waiting for re-mount")
        done.wait()


def dskior(parms: Optional[str] = None) -> CommandResult:

    if not msxdos1boot:
        dskioini()
    wait_remount(sectorInfo[0])

    initdataindex = sectorInfo[3] * SECTORSIZE
    numsectors = sectorInfo[1]
    sectorcnt = 0

    # Multi-sector reads are the interesting case: MSX-DOS asks for one sector
    # at a time for directory and FAT access, but uses B>1 for the body of a
    # large file, so a defect in the per-sector handshake only shows up on big
    # programs. Off by default - a line per sector buries everything else in
    # the log during a copy - so turn it on when chasing one:
    #     MSXPI_PROFILE=1 python3 msxpi-server.py
    if _PROFILE:
        print(
            "dskiords: drive=%d sector=%d count=%d"
            % (sectorInfo[0], sectorInfo[3], numsectors)
        )

    while sectorcnt < numsectors:
        if sectorInfo[0] == 0:
            buf = drive0Data[
                initdataindex
                + (sectorcnt * SECTORSIZE) : initdataindex
                + SECTORSIZE
                + (sectorcnt * SECTORSIZE)
            ]
        else:
            buf = drive1Data[
                initdataindex
                + (sectorcnt * SECTORSIZE) : initdataindex
                + SECTORSIZE
                + (sectorcnt * SECTORSIZE)
            ]

        rc = sendmultiblock(buf)
        sectorcnt += 1

        if rc == RC_SUCCESS:
            pass
        else:
            # WHICH sector failed, not merely that one did: the distinction
            # between "the first sector of a multi-sector call" and "a later
            # one" separates a transport-timing fault from a handshake that
            # cannot survive more than one sector per call.
            print(
                "dskiords: checksum error on sector %d of %d (abs %d), rc=%s"
                % (sectorcnt, numsectors, sectorInfo[3] + sectorcnt - 1, rc)
            )
            break


def dskiow(parms: Optional[str] = None) -> CommandResult:

    if not msxdos1boot:
        dskioini()
    wait_remount(sectorInfo[0])

    initdataindex = sectorInfo[3] * SECTORSIZE
    numsectors = sectorInfo[1]
    sectorcnt = 0

    while sectorcnt < numsectors:
        rc, buf = recvdata2()
        if rc == RC_SUCCESS:
            if sectorInfo[0] == 0:
                drive0Data[
                    initdataindex
                    + (sectorcnt * SECTORSIZE) : initdataindex
                    + SECTORSIZE
                    + (sectorcnt * SECTORSIZE)
                ] = buf
            else:
                drive1Data[
                    initdataindex
                    + (sectorcnt * SECTORSIZE) : initdataindex
                    + SECTORSIZE
                    + (sectorcnt * SECTORSIZE)
                ] = buf
            sectorcnt += 1
        else:
            print("dskiowrs: checksum error")
            break

    # The drive maps the image file itself; push the MSX's writes to disk
    # now rather than whenever the OS gets round to it.
    disk = drive0Data if sectorInfo[0] == 0 else drive1Data
    if sectorcnt > 0 and disk and disk != "":
        disk.flush()


def dskios(parms: Optional[str] = None) -> CommandResult:

    if not msxdos1boot:
        dskioini()

    rc, buf = recvdata2(5)
    sectorInfo[0] = buf[0]
    sectorInfo[1] = buf[1]
    sectorInfo[2] = buf[2]
    byte_lsb = buf[3]
    byte_msb = buf[4]
    sectorInfo[3] = byte_lsb + 256 * byte_msb
    if rc == RC_SUCCESS:
        pass
    else:
        print("dskiosct: checksum error")


# The v1.6 driver sends the short names; every ROM before it sends these.
# Keeping both costs three lines and lets a server upgraded ahead of the EEPROM
# - the usual order, since one is a file copy and the other is a reflash - go on
# serving an older ROM. The reverse pairing cannot be rescued from here: a v1.6
# ROM against a pre-1.6 server fails on the name, which is a better failure than
# the silent one it would otherwise hit (that server reads the burst request as
# a 33280-byte buffer and answers with an ordinary block).
dskiords = dskior
dskiowrs = dskiow
dskiosct = dskios
