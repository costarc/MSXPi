# MSXPi Interface
# Version 1.6.1
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

from typing import List, Optional

# Standard library imports
import glob
import logging
import os
import posixpath
import datetime
import re
from subprocess import Popen, PIPE
from html.parser import HTMLParser
from urllib.request import urlopen

# Third-party imports
import requests

from msxpi_settings import TMPDIR

logger = logging.getLogger("msxpi")

from msxpi_const import (
    CommandResult,
    BLKSIZE,
    HTTP_TIMEOUT,
    MAXBUFSIZE,
    RC_CONNERR,
    RC_FAILED,
    RC_FILENOTFOUND,
    RC_INVALIDCOMMAND,
    RC_READY,
    RC_SUCCESS,
)
import msxpi_transport as transport
from msxpi_blocks import (
    pcopy_handshake,
    recvdata2_oneblock,
    senddata_oneblock,
    sendmultiblock,
)
from msxpi_settings import getMSXPiVar, setMSXPiVar


# create a subclass and override the handler methods
class MyHTMLParser(HTMLParser):
    def __init__(self):
        self.reset()
        self.NEWTAGS = []
        self.NEWATTRS = []
        self.HTMLDATA = []

    def handle_starttag(self, tag, attrs):
        self.NEWTAGS.append(tag)
        self.NEWATTRS.append(attrs)

    def handle_data(self, data):
        self.HTMLDATA.append(data)

    def clean(self):
        self.NEWTAGS = []
        self.NEWATTRS = []
        self.HTMLDATA = []

    def convert_charrefs(self, data):
        print("MyHTMLParser: convert_charrefs found :", data)


def pathExpander(path: str, basepath: str = "") -> List:

    path = path.strip().rstrip(" \t\n\0")

    if len(path) == 0 or path == "" or path.strip() == "." or path.strip() == "*":
        path = basepath
        basepath = ""
    if path.startswith("/"):
        urltype = 0  # this is an absolute local path
        newpath = path
    elif path.lower().startswith("m:"):
        urltype = 1  # this is a network path
        newpath = getMSXPiVar("DriveM") + "/" + path.split(":")[1]
    elif path.lower().startswith("r1:"):
        urltype = 1  # this is a network path
        newpath = getMSXPiVar("DriveR1") + "/" + path.split(":")[1]
    elif path.lower().startswith("r2:"):
        urltype = 1  # this is a network path
        newpath = getMSXPiVar("DriveR2") + "/" + path.split(":")[1]
    elif (
        path.lower().startswith("http")
        or path.lower().startswith("ftp")
        or path.lower().startswith("nfs")
        or path.lower().startswith("smb")
    ):
        urltype = 1  # this is a network path
        newpath = path
    elif basepath.startswith("/"):
        urltype = 0  # this is a local path
        newpath = normalize_path(basepath + "/" + path)
    else:
        urltype = 1  # this is a network path
        newpath = normalize_path(basepath.rstrip("/") + "/" + path)
    return [urltype, newpath]


def dos83format(fname):
    name = "        "
    ext = "   "

    finfo = fname.split(".")

    name = str(finfo[0]).ljust(8)
    if len(finfo) == 2:
        ext = str(finfo[1]).ljust(3)

    return name + ext


def ini_fcb(fname, fsize):

    fpath = fname.split(":")
    if len(fpath) == 1:
        msxfile = str(fpath[0])
        msxdrive = 0
    else:
        msxfile = str(fpath[1])
        drvletter = str(fpath[0]).upper()
        msxdrive = ord(drvletter) - 64

    # convert filename to 8.3 format using all 11 positions required for the FCB
    msxfcbfname = dos83format(msxfile)

    # send FCB structure to MSX
    buf = bytearray()
    buf.extend(msxdrive.to_bytes(1, "little"))
    buf.extend(msxfcbfname.encode())
    rc = sendmultiblock(buf)
    return rc


def run(cmd: str = "") -> CommandResult:

    if cmd.strip() == "" or len(cmd.strip()) == 0:
        rc = sendmultiblock(
            "Syntax: run <command> <::> command. To  pipe a command to other, use :: instead of |"
        )
        return RC_FAILED

    cmd = cmd.replace("::", "|")
    rc = RC_SUCCESS

    try:
        if transport.hostType == "Windows" and "http" not in cmd:
            cmd = cmd.replace("/", "\\")

        p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
        buf = p.stdout.read().decode()
        err = p.stderr.read().decode()
        if len(err) > 0 and not (
            "0K ...." in err
        ):  # workaround for wget false positive
            rc = RC_FAILED
            buf = "Pi:Error - " + str(err)
        elif len(buf) == 0:
            rc = RC_SUCCESS
            buf = "Pi:Ok"
        sendmultiblock(buf.encode())
        return rc
    except Exception as e:
        print("run: exception:" + str(e))
        sendmultiblock(("Pi:Error - " + str(e)).encode())
        return rc


def dir(data: str) -> CommandResult:

    basepath = getMSXPiVar("PATH")

    if not data:
        userPath = ""
    else:
        userPath = data
    pathType, path = pathExpander(userPath, basepath)
    try:
        if pathType == 0:
            if transport.hostType == "Windows":
                run("dir " + path)
            else:
                run("ls -l " + path)
        else:
            parser = MyHTMLParser()
            # Bounded: an unreachable host otherwise blocks here for ever, with
            # the MSX waiting for a reply and nothing in the log.
            # requests, not urlopen: urlopen trusts only the OS certificate
            # store, and on hosts with an outdated store sites such as
            # msxarchive.nl fail with CERTIFICATE_VERIFY_FAILED (expired
            # root).  requests verifies against certifi's current bundle,
            # which is why p copy over https already worked here.
            resp = requests.get(path, timeout=HTTP_TIMEOUT)
            resp.raise_for_status()
            htmldata = resp.text
            parser = MyHTMLParser()
            parser.feed(htmldata)
            buf = " ".join(parser.HTMLDATA)
            rc = sendmultiblock(buf.encode())
    except Exception as e:
        sendmultiblock(("Pi:Error - " + str(e)).encode())

    return RC_SUCCESS


def normalize_path(path: str) -> str:
    """Collapse '.', '..', doubled and trailing slashes in a PATH value, local
    or URL, never climbing above its root ('/' or the URL's host)."""
    m = re.match(r"^([a-z][a-z0-9+.-]*://[^/]*)(.*)$", path, re.I)
    root, rest = (m.group(1), m.group(2)) if m else ("", path)
    rest = "/" + posixpath.normpath("/" + rest).lstrip("/")
    return root + rest


def cd(data: str) -> CommandResult:

    rc = RC_SUCCESS
    basepath = getMSXPiVar("PATH")
    userPath = (data or "").strip().rstrip("\0").strip()
    try:
        if userPath in ("", "."):
            rc = sendmultiblock(basepath.encode())
        else:
            # pathExpander joins relative paths as they come; normalising the
            # result is what makes '..', '../dir' and './dir' land properly.
            pathType, path = pathExpander(userPath, basepath)
            path = normalize_path(path)
            if pathType == 0:
                if os.path.isdir(path):
                    setMSXPiVar("PATH", path)
                    rc = sendmultiblock(path.encode())
                else:
                    sendmultiblock("Pi:Error - not a folder".encode())
            else:
                setMSXPiVar("PATH", path)
                rc = sendmultiblock(path.encode())
    except Exception as e:
        print("pcd:" + str(e))
        sendmultiblock(("Pi:Error - " + str(e)).encode())

    return RC_SUCCESS


PCOPY_CACHE = TMPDIR + "/pcopy_session.bin"
PCOPY_STATE = TMPDIR + "/pcopy_state.txt"
PCOPY_PUT_STATE = TMPDIR + "/pcopy_put_state.txt"
# Upload in progress: (target, temp).  Held in memory so a block does not cost
# a filesystem read; PCOPY_PUT_STATE is the fallback after a restart.
_pcopy_put_paths = None


def _pcopy_read_state():
    """(target, temp) from the state file, or None if there is no session."""
    try:
        if not os.path.exists(PCOPY_PUT_STATE):
            return None
        with open(PCOPY_PUT_STATE, "r") as f:
            parts = [x.strip() for x in f.read().split("\n") if x.strip()]
        if not parts:
            return None
        return (parts[0], parts[1] if len(parts) > 1 else parts[0])
    except OSError:
        return None


def pcopy(msxcmd: str = "pcopy") -> CommandResult:

    basepath = getMSXPiVar("PATH")

    # Helper to transmit error block payload to MSX
    def send_error_block(err_msg, err_code):
        print(f"Pi:Error - {err_msg}")
        rc, msx_blocksize = pcopy_handshake()
        if rc == RC_SUCCESS:
            payload = err_msg.encode("ascii", errors="replace")
            senddata_oneblock(payload, msx_blocksize, err_code, 0)
        return err_code

    # 1. Clean input payload and resolve global pcmd fallback
    cmd_str = msxcmd.strip()
    if cmd_str == "" or cmd_str.lower() == "pcopy":
        pcmd_val = str(globals().get("pcmd", "")).strip()
        if pcmd_val and pcmd_val.lower() != "pcopy":
            cmd_str = pcmd_val

    tokens = cmd_str.split()

    # Remove 'pcopy' prefix if present
    if tokens and tokens[0].lower().startswith("pcopy"):
        parms = tokens[1:]
    else:
        parms = tokens

    if len(parms) < 1:
        return send_error_block("Missing parameters", RC_INVALIDCOMMAND)

    subcmd = parms[0].lower()

    # =========================================================================
    # PHASE 2: READBLOCK (Transfers one block and releases server loop)
    # =========================================================================
    if subcmd == "readblock":
        if not os.path.exists(PCOPY_CACHE) or not os.path.exists(PCOPY_STATE):
            return send_error_block("No active transfer session", RC_FAILED)

        try:
            with open(PCOPY_STATE, "r") as f:
                state_parts = f.read().strip().split(",")
                offset = int(state_parts[0])
                block_index = int(state_parts[1])
        except Exception as e:
            return send_error_block(f"State read error: {str(e)}", RC_FAILED)

        rc, msx_blocksize = pcopy_handshake()
        if rc != RC_SUCCESS:
            print("Pi:Error - Handshake failed during readblock")
            return rc

        filesize = os.path.getsize(PCOPY_CACHE)

        with open(PCOPY_CACHE, "rb") as f:
            f.seek(offset)
            chunk = f.read(msx_blocksize)

        new_offset = offset + len(chunk)
        # Signal RC_SUCCESS on final block, RC_READY if more blocks remain
        header_rc = RC_SUCCESS if new_offset >= filesize else RC_READY

        senddata_oneblock(chunk, msx_blocksize, header_rc, block_index)

        if header_rc == RC_SUCCESS:
            # Transfer finished: Clean up session files
            try:
                os.remove(PCOPY_CACHE)
                os.remove(PCOPY_STATE)
            except OSError:
                pass
        else:
            # Advance state for next readblock request
            next_block_index = (block_index + 1) & 0xFF
            with open(PCOPY_STATE, "w") as f:
                f.write(f"{new_offset},{next_block_index}")

        return RC_SUCCESS

    # =========================================================================
    # UPLOAD: MSX -> Pi.   pcopy A:game.rom game.rom
    # =========================================================================
    # Mirrors the download side: "put" opens the destination and reports
    # whether it could be created, "writeblock" takes one block, "putclose"
    # finishes.  A separate close rather than a last-block flag, because the
    # block protocol carries no header byte in this direction.
    #
    # The destination path is resolved against the MSXPi PATH variable exactly
    # as a download source is, so "pcopy A:game.rom game.rom" lands beside the
    # files a plain "pcopy game.rom" would read.  Local filesystem only - a
    # URL target is rejected rather than silently written somewhere odd.
    if subcmd == "put":
        if len(parms) < 2:
            return send_error_block("Missing destination for put", RC_INVALIDCOMMAND)
        tgt_type, tgt_path = pathExpander(parms[1], basepath)
        if tgt_type != 0:
            return send_error_block(
                "Only local paths can be written", RC_INVALIDCOMMAND
            )
        # Write to a temporary name; the rename in putclose is what publishes
        # the file.  Truncating the real target here destroyed a verified good
        # copy when a later attempt failed part way - the file was left short
        # but looked finished, and only its sha1 gave it away.  Creating the
        # temp now still surfaces a permissions or missing-directory error
        # while the MSX is still listening for it.
        tmp_path = tgt_path + ".part"
        try:
            with open(tmp_path, "wb"):
                pass
            with open(PCOPY_PUT_STATE, "w") as f:
                f.write(tgt_path + "\n" + tmp_path)
        except Exception as e:
            return send_error_block(f"Cannot create {tmp_path}: {str(e)}", RC_FAILED)
        globals()["_pcopy_put_paths"] = (tgt_path, tmp_path)

        print(f"pcopy: receiving into {tgt_path}")
        rc, msx_blocksize = pcopy_handshake()
        if rc != RC_SUCCESS:
            return rc
        senddata_oneblock(b"Pi:Ok", msx_blocksize, RC_SUCCESS, 0)
        return RC_SUCCESS

    if subcmd == "writeblock":
        # Paths are cached in memory; the state file is only the fallback for
        # a server restarted mid-transfer.  Re-reading it per block meant one
        # SD-card open for every 8 KB - 64 of them on a 512 KB upload - and
        # any transient filesystem error aborted the whole transfer.
        paths = globals().get("_pcopy_put_paths")
        if paths is None:
            paths = _pcopy_read_state()
            if paths is None:
                return send_error_block("No active upload session", RC_FAILED)
            globals()["_pcopy_put_paths"] = paths
        tmp_path = paths[1]

        # recvdata2_oneblock does its own handshake, matching SENDDATA2 on the
        # MSX side, so nothing is done here before calling it.
        rc, payload = recvdata2_oneblock(MAXBUFSIZE)
        if payload is None:
            print(
                "pcopy: writeblock received nothing (rc=%s)"
                % hex(rc if rc is not None else 0)
            )
            return RC_CONNERR
        # Logged per block on purpose: without it a failed upload shows only a
        # run of identical "pcopy writeblock" lines, with no way to tell how
        # far it got or whether the blocks were full.  One line per 16 KB.
        print("pcopy: writeblock got %d bytes (rc=%s)" % (len(payload), hex(rc)))
        try:
            with open(tmp_path, "ab") as f:
                f.write(payload)
        except Exception as e:
            print(f"Pi:Error - write failed: {str(e)}")
            return RC_FAILED
        return RC_SUCCESS

    if subcmd == "putclose":
        paths = globals().get("_pcopy_put_paths") or _pcopy_read_state()
        if not paths:
            print("pcopy: putclose with no session - nothing to finalise")
        globals()["_pcopy_put_paths"] = None
        try:
            os.remove(PCOPY_PUT_STATE)
        except OSError:
            pass

        # The rename is what publishes the file.  Until it happens the target
        # keeps whatever it held, so a transfer that died part way cannot pass
        # for a good copy.
        if paths:
            tgt_path, tmp_path = paths
            if os.path.exists(tmp_path):
                try:
                    size = os.path.getsize(tmp_path)
                    os.replace(tmp_path, tgt_path)
                    print(f"pcopy: received {size} bytes into {tgt_path}")
                except OSError as e:
                    print(f"Pi:Error - cannot finalise {tgt_path}: {str(e)}")
        rc, msx_blocksize = pcopy_handshake()
        if rc != RC_SUCCESS:
            return rc
        senddata_oneblock(b"Pi:Ok", msx_blocksize, RC_SUCCESS, 0)
        return RC_SUCCESS

    # =========================================================================
    # PHASE 1: INIT (Locates, decompresses, caches file & confirms readiness)
    # =========================================================================
    if subcmd == "init":
        parms = parms[1:]
        if len(parms) < 1:
            return send_error_block("Missing source file for init", RC_INVALIDCOMMAND)

    # 2. Parse paths with smart source/target auto-detection
    # /z must be a whole argument: a substring test also matched paths such
    # as /tmp/zanac.rom, and the target was then read as the source.
    expand = any(p.lower() == "/z" for p in parms)
    parms = [p for p in parms if p.lower() != "/z"]

    src_param = parms[0] if parms else ""
    tgt_param = parms[1] if len(parms) > 1 else ""

    pathType, path = pathExpander(src_param, basepath)

    # Auto-fallback: If src_param doesn't exist on Pi, check if tgt_param does
    if pathType == 0 and not os.path.exists(path) and tgt_param != "":
        alt_type, alt_path = pathExpander(tgt_param, basepath)
        if alt_type == 0 and os.path.exists(alt_path):
            src_param, tgt_param = tgt_param, src_param
            pathType, path = alt_type, alt_path

    # 3. Read source file contents
    if pathType == 0:
        try:
            with open(path, mode="rb") as f:
                buf = f.read()
            filesize = len(buf)
        except Exception as e:
            err_code = RC_FILENOTFOUND if "[Errno 2]" in str(e) else RC_FAILED
            return send_error_block(f"File error: {str(e)}", err_code)
    else:
        try:
            urlhandler = urlopen(path, timeout=HTTP_TIMEOUT)
            buf = urlhandler.read()
            filesize = len(buf)
        except Exception as e:
            return send_error_block(f"URL error: {str(e)}", RC_FAILED)

    if filesize == 0:
        return send_error_block("File size is zero bytes", RC_FAILED)

    # 4. Decompress if /z option was specified
    if expand:
        tmpfn0 = path.split("/")
        tmpfn = tmpfn0[-1]
        extract_dir = TMPDIR + "/msxpi"
        os.makedirs(extract_dir, exist_ok=True)
        for old in glob.glob(extract_dir + "/*"):
            try:
                os.remove(old)
            except OSError:
                pass

        with open(TMPDIR + "/" + tmpfn, "wb") as tmpfile:
            tmpfile.write(buf)

        if ".lzh" in tmpfn:
            tool = "lha" if transport.hostType == "Windows" else "/usr/bin/lhasa"
            cmd = f"{tool} -xfiw={extract_dir} {TMPDIR}/{tmpfn}"
        else:
            cmd = (
                f"7z.exe e {TMPDIR}/{tmpfn} -aoa -o{extract_dir}/"
                if transport.hostType == "Windows"
                else f"/usr/bin/unar -f -o {extract_dir} {TMPDIR}/{tmpfn}"
            )

        p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
        perror = p.stderr.read().decode()
        rc = p.poll()
        if rc is not None and rc != 0:
            return send_error_block(f"Decompression failed: {perror}", RC_FAILED)

        romfiles = [f for f in os.listdir(extract_dir) if f.endswith((".rom", ".ROM"))]
        if romfiles:
            fname1 = extract_dir + "/" + romfiles[0]
            try:
                with open(fname1, mode="rb") as f:
                    buf = f.read()
                filesize = len(buf)
            except Exception as e:
                return send_error_block(f"ROM read error: {str(e)}", RC_FAILED)
        else:
            return send_error_block(f"No ROM file in archive: {perror}", RC_FAILED)

    # 5. Cache processed buffer and state for readblock calls
    with open(PCOPY_CACHE, "wb") as f:
        f.write(buf)

    with open(PCOPY_STATE, "w") as f:
        f.write("0,0")  # initial offset=0, block_index=0

    # 6. Perform handshake and confirm initialization to MSX client
    rc, msx_blocksize = pcopy_handshake()
    if rc != RC_SUCCESS:
        print("Pi:Error - Handshake failed during init")
        return rc

    # Send confirmation block back to MSX
    senddata_oneblock(b"READY", msx_blocksize, RC_SUCCESS, 0)
    return RC_SUCCESS


def formatrsp(rc, lsb, msb, msg, size=BLKSIZE):
    b = bytearray(size)
    b[0] = rc
    b[1] = lsb
    b[2] = msb
    b[3 : len(msg)] = bytearray(msg.encode())
    return b


def date(parms: Optional[str] = None) -> CommandResult:

    pdate = bytearray(8)
    now = datetime.datetime.now()

    # Fill buffer in MSX expected order
    pdate[0] = now.day
    pdate[1] = now.month
    pdate[2] = now.year & 0xFF
    pdate[3] = now.year >> 8
    pdate[4] = now.hour
    pdate[5] = now.minute
    pdate[6] = now.second
    pdate[7] = 0  # hundredths (unused)

    # -----------------------------
    # Debug print (MSX-style)
    # -----------------------------

    year = pdate[2] | (pdate[3] << 8)

    # Now send to MSX
    sendmultiblock(pdate)
