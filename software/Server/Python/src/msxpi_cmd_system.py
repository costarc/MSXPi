# MSXPi Interface
# Version 1.7.0
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

from typing import List, Optional, Tuple

# Standard library imports
import re
import shlex
import sys
import time
import subprocess
import logging
import os
import platform
from subprocess import PIPE, STDOUT

# Third-party imports

logger = logging.getLogger("msxpi")

from msxpi_const import (
    CommandResult,
    BUILD_ID,
    RC_SUCCESS,
    VERSION,
)
import msxpi_ethglue as ethglue
import msxpi_link2
import msxpi_cmd_disk as disk
import msxpi_settings as settings
import msxpi_transport as transport
from msxpi_blocks import link_recv, link_send
from msxpi_cmd_disk import msxdos_inihrd, unmount_drive
from msxpi_cmd_files import run
from msxpi_ethglue import _eth_release, _eth_relink
from msxpi_settings import getMSXPiVar, setMSXPiVar, shown_value
from msxpi_transport import release_gpio


def pset(data: str) -> CommandResult:

    # Normalize input
    data = data.strip()

    # ---------------------------------------------------------
    # 0. No arguments → list all variables
    # ---------------------------------------------------------
    if not data:
        out = ""
        for name, value in settings._config.items():
            out += f"{name}={shown_value(name, value)}\n"
        return link_send(out.encode())

    # Split into tokens
    parts = data.split()
    cmd = parts[0].lower()

    # ---------------------------------------------------------
    # 1. Global help:  set /h   set /he   set /help
    # ---------------------------------------------------------
    if cmd in ("/h", "/help"):
        helptext = (
            "Syntax:\n"
            "set                     List all variables\n"
            "set varname             Show a single variable\n"
            "set varname value       Set or update variable\n"
            "set varname /d          Delete variable\n"
            "set /h                  Show this help"
        )
        return link_send(helptext.encode())

    # Now treat first token as variable name
    varname = parts[0]
    varname_upper = varname.upper()

    # ---------------------------------------------------------
    # 2. Single variable display:  set wifi
    # ---------------------------------------------------------
    if len(parts) == 1:
        for name, value in settings._config.items():
            if name.upper() == varname_upper:
                return link_send(f"{name}={shown_value(name, value)}".encode())
        return link_send(f"{varname} not found".encode())

    # ---------------------------------------------------------
    # 3. Per-variable help:  set wifi /h
    # ---------------------------------------------------------
    if parts[1].lower() in ("/h", "/he", "/help"):
        helptext = (
            f"Help for variable '{varname}':\n"
            "set varname             Show variable\n"
            "set varname value       Set variable\n"
            "set varname /d          Delete variable\n"
        )
        return link_send(helptext.encode())

    # ---------------------------------------------------------
    # 4. Delete variable:  set wifi /d
    # ---------------------------------------------------------
    if parts[1].lower() in ("/d", "/delete"):
        print(f"Deleting variable {varname}")
        rc = setMSXPiVar(varname, "")  # empty value = delete
        return link_send("Pi:Ok".encode())

    # ---------------------------------------------------------
    # 5. Set or update variable:  set wifi MYSSID
    # ---------------------------------------------------------
    varvalue = data[len(varname) :].strip()

    print(f"Setting variable {varname}")
    rc = setMSXPiVar(varname, varvalue)

    # Special cases for drives
    if rc == RC_SUCCESS:
        if varname_upper == "DRIVEA":
            old = disk.drive0Data
            rc, disk.drive0Data = msxdos_inihrd(varvalue)
            unmount_drive(old)

        elif varname_upper == "DRIVEB":
            old = disk.drive1Data
            rc, disk.drive1Data = msxdos_inihrd(varvalue)
            unmount_drive(old)

        return link_send("Pi:Ok".encode())

    return link_send("Pi:Error".encode())


def interfaces_report():
    """One line per interface: name, state, IPv4 address - for a 40-column MSX.

    This used to be `ip a` filtered through
    `grep '^1\\|^2\\|^3\\|^4\\|inet' | grep -v inet6`, which keeps the header
    line only for interfaces numbered 1 to 4. msxpi0 is recreated every time
    the TAP is rebuilt, and its index climbs with each one, so once it passed 4
    its header vanished while its "inet" line stayed - leaving an address
    hanging under the previous interface, which reads as corrupted output.
    Nothing about an interface's index says anything useful anyway.

    `ip -o` keeps each record on ONE line, so there is nothing to reassemble
    and no wrapped line to mis-parse.
    """

    def ip_out(args):
        try:
            done = subprocess.run(
                ["ip", "-o"] + args, stdout=PIPE, stderr=STDOUT, text=True, timeout=10
            )
            return done.stdout if done.returncode == 0 else ""
        except Exception as exc:
            print(f"interfaces_report: {exc}")
            return ""

    state = {}
    for line in ip_out(["link", "show"]).splitlines():
        # "2: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ..."
        parts = line.split(":", 2)
        if len(parts) < 3:
            continue
        name = parts[1].strip().split("@")[0]
        flags = parts[2]
        state[name] = "up" if ",UP" in flags or "<UP" in flags else "down"

    addrs = {}
    for line in ip_out(["-4", "addr", "show"]).splitlines():
        # "2: wlan0    inet 192.168.1.239/24 brd ... scope global wlan0\"
        fields = line.split()
        if len(fields) < 4 or fields[2] != "inet":
            continue
        addrs.setdefault(fields[1].split("@")[0], []).append(fields[3])

    if not state and not addrs:
        return "Pi:could not read the interfaces"

    report = []
    for name in state or addrs:
        for addr in addrs.get(name, ["-"]):
            report.append(f"{name:<8.8} {state.get(name, '?'):<4} {addr}")
    return "\r\n".join(report)


def wifi(cmd: str) -> CommandResult:
    wifissid = getMSXPiVar("WIFISSID")
    wifipass = getMSXPiVar("WIFIPWD")
    wificountry = getMSXPiVar("WIFICOUNTRY")

    if cmd[:2] == "/h":
        link_send("Pi:Usage:\npwifi display | set".encode())
        return RC_SUCCESS

    if cmd[:1] == "s" or cmd[:1] == "S":
        if transport.hostType == "RaspberryPi":
            # A saved profile for this SSID that lacks key-mgmt (left by an
            # earlier attempt, or by the imager) makes "wifi connect" fail with
            # "802-11-wireless-security.key-mgmt: property is missing".
            # Dropping it first lets nmcli build a complete one; the delete
            # failing because there is no such profile is fine.
            q = shlex.quote
            wifisetcmd = (
                f"sudo nmcli connection delete id {q(wifissid)} >/dev/null 2>&1; "
                f"sudo nmcli device wifi connect {q(wifissid)} password {q(wifipass)}"
            )
            run(wifisetcmd)
        else:
            link_send(b"Parameter not supported in this platform")
    else:
        if transport.hostType == "RaspberryPi":
            link_send(interfaces_report().encode())
        else:
            run("ipconfig")

    return RC_SUCCESS


def ver(parms: Optional[str] = None) -> CommandResult:
    """Send server version information to MSX."""
    version_string = f"MSXPi Server Version {VERSION} Build {BUILD_ID}\n"
    logger.info(f"Sending version info: {version_string.strip()}")
    return link_send(version_string.encode())


def link2_pattern(n: int, seed: int = 0) -> bytes:
    """The test pattern of l2test; L2TEST.BIN generates the same bytes on the MSX."""
    return bytes((i * 13 + (i >> 8) * 7 + seed) & 0xFF for i in range(n))


def l2test(parms: Optional[str] = None) -> CommandResult:
    """LINK2 test command (documents/LINK2-TEST-PLAN.md, T4).

    l2test pat N SEED   send N pattern bytes (CALL MSXPI("2,addr,l2test pat 8192 7"))
    l2test sink N SEED  take N bytes from the MSX (L2TEST.BIN), check them against the
                        pattern and answer "L2TEST OK/BAD ..." with their CRC-16
    l2test bin          send L2TEST.BIN, the Z80 test program, from MSXPI_HOME
    """
    from msxpi_link2 import link_crc

    a = (parms or "").split()
    op = a[0] if a else ""
    if op == "pat" and len(a) == 3:
        return link_send(link2_pattern(int(a[1]), int(a[2])))
    if op == "sink" and len(a) == 3:
        n, seed = int(a[1]), int(a[2])
        rc, data = link_recv(n + 4096)
        if rc != RC_SUCCESS:
            logger.info(f"l2test sink: receive failed rc={rc:#04x}")
            # Answer anyway: the MSX waits for the summary line, and without one its
            # next receive would be read by the command loop.
            link_send(f"L2TEST BAD receive failed rc {rc:#04x}\n".encode())
            return rc
        want = link2_pattern(n, seed)
        bad = next((i for i in range(min(len(data), n)) if data[i] != want[i]), None)
        if len(data) == n and bad is None:
            msg = f"L2TEST OK {n} crc {link_crc(data):04X}\n"
        else:
            msg = f"L2TEST BAD got {len(data)} want {n} first diff {bad}\n"
        logger.info(msg.strip())
        return link_send(msg.encode())
    if op == "bin":
        with open(os.path.join(settings.MSXPIHOME, "l2test.bin"), "rb") as f:
            return link_send(f.read())
    return link_send(b"usage: l2test pat|sink N SEED | bin\n")


def q(parm: Optional[str] = None) -> CommandResult:
    """Client-side quit notification (see sendQuit() in msxarch.c/p.c). The
    client sends this and, on most paths, exits back to DOS immediately
    afterward without waiting for/completing a reply - so this must return
    None (no link_send reply attempted). Previously there was no "q"
    handler at all, so this hit the KeyError/"Unknown command" path, which
    tried to link_send() an error string to a client that had already
    gone away - leaving the server mid-handshake with nobody listening,
    corrupting the next session's protocol state (surfaced as garbage
    checksums, a forced reconnect, and a "Disk error reading drive A" on
    whatever ran next)."""
    print("q(): client quit")


LINK2_PROBE = "https://raw.githubusercontent.com/costarc/MSXPi/{branch}/software/Server/Python/src/msxpi_link2.py"


def _speaks_link2(folder: str) -> bool:
    """Whether the server files in folder speak LINK2: their msxpi_blocks.py uses
    msxpi_link2 (a server without LINK2 has neither). True when it cannot tell."""
    try:
        with open(os.path.join(folder, "msxpi_blocks.py"), encoding="utf-8", errors="replace") as f:
            return "msxpi_link2" in f.read()
    except OSError:
        return True


def _branch_speaks_link2(branch: str) -> Optional[bool]:
    """Whether the branch's server has LINK2 (None: GitHub cannot be asked)."""
    import requests

    try:
        return requests.head(LINK2_PROBE.format(branch=branch), timeout=15).status_code == 200
    except Exception as e:
        print(f"update: cannot check {branch} for LINK2: {e}", flush=True)
        return None


def _restart_keeps_link2() -> Optional[str]:
    """Why "p restart" must not happen now, or None.

    Once the MSX has used LINK2, its ROM (the DOS half's disk driver, CALL MSXPI)
    needs a LINK2 server: a server without it cannot read the disk, and the MSX
    cannot even load P.COM to put things right. That is what msxpiupd.bat from
    master does, as it brings the server up to date from master before the
    branch it was given: on Windows "p update" stages master's files and
    "p restart" puts them in place; on a Pi update.sh writes them directly.
    So the restart is refused while the files it would start lack LINK2 (a
    staged set is dropped too, or the next start-openmsx.bat would apply it),
    and this server keeps running; the "p update <branch>" that follows in
    msxpiupd.bat brings LINK2 files again.
    """
    if not msxpi_link2.used:
        return None
    home = os.path.abspath(settings.MSXPIHOME)
    staged = os.path.join(home, "staged")
    if transport.hostType == "Windows" and os.path.isfile(os.path.join(staged, "READY")):
        if _speaks_link2(staged):
            return None
        try:
            os.replace(staged, f"{staged}.nolink2-{int(time.time())}")
        except OSError:
            try:
                os.remove(os.path.join(staged, "READY"))
            except OSError:
                pass
        return "Pi:Error - not restarted: the staged server has no LINK2, which this MSX's ROM needs (staged update dropped)"
    if not _speaks_link2(home):
        return "Pi:Error - not restarted: the server files have no LINK2, which this MSX's ROM needs. p update <a LINK2 branch> first"
    return None


def restart(parm: Optional[str] = None) -> CommandResult:
    why = _restart_keeps_link2()
    if why:
        print(why)
        link_send(why.encode())
        return
    if transport.hostType == "RaspberryPi":
        print("Restarting MSXPi Server")
        link_send(b"Pi:Ok")
        exitDueToSyncError()
    elif transport.hostType == "Windows":
        print("Restarting MSXPi Server")
        link_send(b"Pi:Ok")
        _restart_windows()
    else:
        print("Command not supported by this platform")
        link_send(b"Command not supported by this platform")


def _restart_windows() -> None:
    """Start this server again, in a new console, once this process is gone.

    Windows has no msxpi-monitor to bring the server back, so a detached
    PowerShell does it: it waits for this process to end, puts a staged
    update in place (msxpi-apply-staged.ps1, see update()) and starts the
    same Python with the same arguments in the same folder. The environment
    (MSXPI_PORT, MSXPI_INI, ...) is inherited. Then this process exits.
    """
    home = os.path.abspath(settings.MSXPIHOME)
    apply = os.path.join(home, "msxpi-apply-staged.ps1")

    def q(x: str) -> str:
        return "'" + x.replace("'", "''") + "'"

    ps = f"Wait-Process -Id {os.getpid()} -Timeout 30 -ErrorAction SilentlyContinue; "
    if os.path.isfile(apply):
        ps += f"& {q(apply)} -MsxPiHome {q(home)}; "
    args = ", ".join(q(a) for a in [os.path.abspath(sys.argv[0]), *sys.argv[1:]])
    ps += (f"Start-Process -FilePath {q(sys.executable)} -ArgumentList @({args}) "
           f"-WorkingDirectory {q(os.getcwd())}")
    # Not DETACHED_PROCESS: PowerShell without a console does nothing at all.
    flags = subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP
    subprocess.Popen(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps],
                     creationflags=flags, close_fds=True)
    for image in (getattr(disk, "drive0Data", None), getattr(disk, "drive1Data", None)):
        try:
            disk.unmount_drive(image)
        except Exception:
            pass
    sys.stdout.flush()
    os._exit(0)


UPDATE_SETUP_URL = "https://raw.githubusercontent.com/costarc/MSXPi/{branch}/software/Server/Setup"
# A git branch name as the MSX may send it ("feature/x"); keeps URLs and the
# command line safe.
_BRANCH_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$")
# update.sh touches this when it finishes; see update().
UPDATE_STAMP = ".last-update"


# The branch the MSX asked for with "p update <branch>"; later "p update" use it.
# Not persisted: a restarted server is back on master.
_update_branch = "master"
MASTER_DRIVE_M = "https://github.com/costarc/MSXPi/raw/master/software/target"


GITHUB_BRANCHES_API = "https://api.github.com/repos/costarc/MSXPi/branches"
RAW_BRANCH_PROBE = "https://raw.githubusercontent.com/costarc/MSXPi/{branch}/software/Server/Setup/update.sh"


def _branch_name(parm: Optional[str]) -> Optional[str]:
    """The branch in a command parameter: master when none was given, None
    when it is not a plain name.

    MSX-DOS 2 splits a batch parameter at "/", so msxpiupd.bat sends
    "%1%2%3..." to glue "feature" and "/x" back together; any blank left
    between the pieces is dropped, and so is an unexpanded "%n".
    """
    branch = re.sub(r"%\d|\s+", "", parm or "")
    if branch == "":
        return "master"
    if _BRANCH_RE.match(branch) and ".." not in branch:
        return branch
    return None


def _remote_branches() -> List[str]:
    """Every branch of the repository on GitHub (empty when it cannot tell)."""
    import requests

    names: List[str] = []
    for page in range(1, 6):
        resp = requests.get(GITHUB_BRANCHES_API, params={"per_page": 100, "page": page}, timeout=15)
        resp.raise_for_status()
        batch = [b["name"] for b in resp.json()]
        names += batch
        if len(batch) < 100:
            break
    return names


def _resolve_branch(branch: str) -> Tuple[Optional[str], str]:
    """(the branch as GitHub spells it, "") or (None, why not).

    A branch that does not exist would point every "pcopy m:" and the server
    update at 404s, so it is checked first. Branch names are case sensitive
    and an MSX user may well type them in capitals, so a name that differs
    only in case is taken too. When GitHub cannot be asked, the name is used
    as given: the update itself then reports what failed.
    """
    if branch == "master":
        return branch, ""
    import requests

    try:
        if requests.head(RAW_BRANCH_PROBE.format(branch=branch), timeout=15).status_code == 200:
            return branch, ""
        names = _remote_branches()
    except Exception as e:
        print(f"update: cannot check {branch}: {e}", flush=True)
        return branch, ""
    for name in names:
        if name.lower() == branch.lower():
            return name, ""
    # An older msxpiupd.bat sends only %1, which MSX-DOS 2 cut at the "/".
    near = [n for n in names if n.lower().startswith(branch.lower().rstrip("/") + "/")]
    if not near:
        near = [n for n in names if branch.lower() in n.lower()]
    why = f"no branch {branch}"
    if near:
        why += "\nDid you mean: " + " ".join(near[:4])
    return None, why


def _disk_build_id(home: str) -> str:
    """BUILD_ID of the server files on disk (not the running server's)."""
    try:
        with open(os.path.join(home, "msxpi_const.py"), encoding="utf-8") as f:
            m = re.search(r'^BUILD_ID\s*=\s*"([^"]+)"', f.read(), re.M)
        return m.group(1) if m else "unknown"
    except (OSError, TypeError):
        return "unknown"


def _current_branch() -> str:
    """The branch "p update" works on: the one "p update <branch>" chose.

    That also saves DriveM (msxpi.ini) pointing at the branch, and DriveM
    survives a server restart where the variable above does not: on a Pi
    "p restart" is asynchronous, so a restart can land after the branch was
    chosen and leave the MSX files coming from the branch and the server from
    master.
    """
    if _update_branch != "master":
        return _update_branch
    try:
        m = re.match(r"https://github\.com/costarc/MSXPi/raw/(.+)/software/target$", getMSXPiVar("DriveM") or "")
    except Exception:
        m = None
    return m.group(1) if m and _branch_name(m.group(1)) else "master"


def update(parm: Optional[str] = None) -> CommandResult:
    """Bring the server files up to date, on any host. Sent by msxpiupd.bat
    and msxpirfh.bat.

    Raspberry Pi and other Unix hosts run update.sh. Windows has no sh: it
    runs msxpi-windows-setup.ps1 for the server files and Python packages,
    leaving openMSX alone (it is the program the MSX is running in) and asking
    for no administrator rights.

    "p update <branch>" chooses the git branch (master for "master") for this
    and the following updates: it points DriveM, where "pcopy m:" reads, at
    the branch's target folder, so the MSX files come from the same branch.
    Without a name the branch chosen before is used. A branch that does not
    exist changes nothing. MSX-DOS batch files cannot test for an empty
    parameter, so msxpiupd.bat always sends "p update %1%2..." and an empty
    one means "the branch in use" (master, as msxpiupd.bat resets DriveM).

    An update of the same branch that finished in the last ten minutes is not
    repeated: msxpiupd.bat and msxpirfh.bat both ask for one.

    On Windows the setup only stages the server files (the running server's
    files are not replaced under it); "p restart" or the next start-openmsx.bat
    puts them in place.

    The server is not restarted here: msxpiupd.bat / msxpirfh.bat send
    "p restart" next (a Pi's msxpi-monitor, or _restart_windows(), brings it
    back); anywhere else the user restarts it.
    """
    global _update_branch
    current = _current_branch()
    explicit = bool((parm or "").strip())
    branch = _branch_name(parm) if explicit else current
    if branch is None:
        return "Pi:Error - bad branch name"
    if branch != current:
        branch, why = _resolve_branch(branch)
        if branch is None:
            return f"Pi:Error - {why}\nUpdating from {current}"
    # An MSX that uses LINK2 cannot work with a server without it (see
    # _restart_keeps_link2): msxpiupd.bat from master asks for master first.
    if msxpi_link2.used and _branch_speaks_link2(branch) is False:
        return (f"Pi:Error - the {branch} server has no LINK2, which this MSX's ROM needs."
                f"\nKept this server. Use: msxpiupd <a LINK2 branch>")
    if explicit:
        _update_branch = branch
        setMSXPiVar("DriveM", f"https://github.com/costarc/MSXPi/raw/{branch}/software/target")
    windows = transport.hostType == "Windows"
    home = os.path.abspath(settings.MSXPIHOME)
    stamp = os.path.join(home, UPDATE_STAMP)
    # The stamp holds the branch of the last update (empty: master, as written
    # by update.sh itself when msxpiupd.bat runs it first).
    # update.sh only touches the file, so a master update.sh run on top of a
    # branch's files leaves the old branch name in it with a fresh time: the
    # name counts only with the build it was written for, which must still be
    # the one on disk.
    try:
        if time.time() - os.path.getmtime(stamp) < 600:
            with open(stamp) as f:
                words = f.read().split()
            if not words and branch == "master":
                return f"Pi:Ok - server already updated from {branch}"
            if len(words) == 2 and words[0] == branch and words[1] == _disk_build_id(home):
                return f"Pi:Ok - server already updated from {branch}"
    except OSError:
        pass

    name = "msxpi-windows-setup.ps1" if windows else "update.sh"
    script = os.path.join(home, name)
    try:
        import requests  # only needed here; the server imports it elsewhere anyway

        resp = requests.get(f"{UPDATE_SETUP_URL.format(branch=branch)}/{name}", timeout=30)
        resp.raise_for_status()
        with open(script + ".new", "wb") as f:
            f.write(resp.content)
        os.replace(script + ".new", script)
    except Exception as e:
        return f"Pi:Error - cannot get {name}: {e}"

    if windows:
        cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script,
               "-MsxPiHome", home, "-SkipMpv", "-SkipOpenMsx", "-NoPause", "-Stage"]
        if branch != "master":
            cmd += ["-Branch", branch]
    else:
        cmd = ["sh", script]
    print(f"update: running {' '.join(cmd)}", flush=True)
    try:
        env = dict(os.environ)
        if branch != "master":
            env["MSXPI_UPDATE_BASE"] = (
                f"https://raw.githubusercontent.com/costarc/MSXPi/{branch}/software/Server/Python/src")
        done = subprocess.run(cmd, cwd=home, stdout=PIPE, stderr=STDOUT, env=env,
                              stdin=subprocess.DEVNULL, timeout=1800)
    except Exception as e:
        return f"Pi:Error - update: {e}"
    out = done.stdout.decode("utf-8", "replace")
    print(out, flush=True)
    if done.returncode == 0:
        try:
            with open(stamp, "w") as f:
                f.write(f"{branch} {_disk_build_id(home)}")
        except OSError:
            pass

    if not windows:
        # update.sh keeps its lines short for the MSX screen.
        return f"Server from {branch}\n" + (out.strip() or f"Pi:update exit {done.returncode}")
    # The Windows setup is chatty: send the count of what went well and every
    # line that did not.
    lines = [l.strip() for l in out.splitlines() if l.strip()]
    ok = sum(1 for l in lines if l.startswith("ok "))
    bad = [l[:78] for l in lines if l.lower().startswith(("warn", "fail", "msxpi-windows-setup:"))]
    status = "Pi:Ok" if done.returncode == 0 else f"Pi:Error - exit {done.returncode}"
    return "\n".join([f"{status} - server from {branch}, {ok} items", *bad,
                      "p restart (or the next start) applies it."])


def netreset(parm: Optional[str] = None) -> CommandResult:
    """Rebuild the Pi's MSX networking from scratch, on demand from the MSX.

    For the case this cannot be designed away: the Pi boots, msxpi-monitor
    starts msxpi-tcpip-setup.sh in the background, and the Pi has no default
    route yet - so there is no uplink to NAT to, the script gives up, and the
    MSX has no network until somebody logs into the Pi. Now "p netreset" does
    the whole sequence: tear down the TAP and the iptables rules, run the setup
    again (new uplink, new TAP owned by the server's user, fresh NAT), and
    reopen the link so the running server picks up the new device.

    An optional parameter is how many seconds to wait for a default route
    (default 15, bounded because the MSX is sitting waiting for the reply).
    """
    if transport.hostType != "RaspberryPi":
        return "Command not supported by this platform"
    tcpip_setup = settings.MSXPIHOME + "/msxpi-tcpip-setup.sh"
    if not os.path.isfile(tcpip_setup):
        return f"Pi:{tcpip_setup} missing"

    wait = 15
    if parm:
        try:
            wait = max(1, min(60, int(parm.split()[0])))
        except ValueError:
            pass

    # Before the script runs, not after: see _eth_release().
    _eth_release()

    # A MINIMAL environment, not os.environ: the script takes TAP, TAP_IP,
    # MSX_IP, PREFIX, MTU, TAP_USER and UPLINK from the environment, so
    # anything that happened to be set for the server - by the unit file, the
    # monitor, or whoever started it by hand - would silently reconfigure the
    # network differently here than at boot. Only WAIT_SECS is ours to pass.
    env = {
        "PATH": os.environ.get("PATH", "/usr/sbin:/usr/bin:/sbin:/bin"),
        "WAIT_SECS": str(wait),
    }
    report = []
    for phase in ("down", "up"):
        try:
            done = subprocess.run(
                ["sudo", tcpip_setup, phase],
                env=env,
                stdout=PIPE,
                stderr=STDOUT,
                text=True,
                timeout=wait + 60,
            )
        except Exception as exc:
            return f"Pi:netreset {phase} failed: {exc}"
        out = done.stdout or ""
        print(f"netreset {phase}: rc={done.returncode}\n{out}", flush=True)
        if done.returncode != 0:
            if phase == "down":
                # Teardown failing is not a reason to stop: it exits non-zero
                # when there is no default route yet, which is precisely the
                # situation this command exists for. Let "up" report the
                # real problem.
                continue
            # The script says why on its first line or two - pass that on
            # rather than a bare exit code, since "no default route" is the
            # expected answer when this is run too early.
            ethglue._eth_tap_retry_at = 0.0  # stale TAP: let the opcode path retry
            why = " ".join(out.split())[:70] or f"exit {done.returncode}"
            return f"Pi:netreset {phase}: {why}"
        if phase == "up":
            # Only the lines worth 40 columns on an MSX screen.
            for line in out.splitlines():
                if (
                    line.startswith(
                        ("uplink:", "created ", "msxpi0 up:", "NAT:", "dns:", "WARN")
                    )
                    or "recreating" in line
                ):
                    report.append(line.strip())

    state = _eth_relink()
    if state is None:
        report.append("link: idle, attaches on first use")
    elif state:
        report.append("link: TAP reattached")
    else:
        report.append("link: TAP unavailable - check owner")
    return "\r\n".join(report) if report else "Pi:netreset done"


def tcpip(parm: Optional[str] = None) -> CommandResult:
    """Alias for netreset - the script is msxpi-tcpip-setup.sh."""
    return netreset(parm)


# Run as one "sudo sh -c" so a single sudoers rule covers it. Works with
# NetworkManager (Bookworm) and with dhcpcd/wpa_supplicant (older images);
# each tool is skipped if absent. Every step is "|| true": a wlan0 in a bad
# state is exactly when individual steps fail, and the next step may still
# recover it.
_WLANRESET_SCRIPT = r"""
IF=wlan0
has() { command -v "$1" >/dev/null 2>&1; }
svc_active() { has systemctl && systemctl is-active --quiet "$1" 2>/dev/null; }
svc_enabled() { has systemctl && systemctl is-enabled --quiet "$1" 2>/dev/null; }

# Decide once who owns wlan0, so the teardown never pokes a manager that is
# not in charge (e.g. a leftover dhcpcd binary on a NetworkManager image).
#   nm       - NetworkManager (Bookworm and newer, or installed by hand)
#   dhcpcd   - dhcpcd + wpa_supplicant hook (Bullseye and older)
#   dhclient - ifupdown/dhclient
#   none     - nothing recognised: link and radio cycle only
if has nmcli && svc_active NetworkManager; then MGR=nm
elif has dhcpcd && { svc_active dhcpcd || svc_enabled dhcpcd; }; then MGR=dhcpcd
elif has dhclient; then MGR=dhclient
else MGR=none
fi
echo "wlanreset: manager=$MGR"

# --- tear down ---
case $MGR in
    nm)       nmcli device disconnect $IF || true ;;
    dhcpcd)   dhcpcd -k $IF >/dev/null 2>&1 || true ;;
    dhclient) dhclient -r $IF || true ;;
esac
ip addr flush dev $IF || true
ip link set $IF down || true

# --- radio off/on: forces the driver to drop the association completely ---
[ $MGR = nm ] && { nmcli radio wifi off || true; }
has rfkill && { rfkill block wifi || true; }
sleep 2
has rfkill && { rfkill unblock wifi || true; }
[ $MGR = nm ] && { nmcli radio wifi on || true; }

ip link set $IF up || true
sleep 2

# --- bring back and request a lease ---
case $MGR in
    nm)
        nmcli device set $IF managed yes || true
        # Connect can race the radio coming back; retry a few times.
        for i in 1 2 3; do
            nmcli device connect $IF && break
            sleep 3
        done
        ;;
    dhcpcd)
        # dhcpcd starts wpa_supplicant from its 10-wpa_supplicant hook;
        # "dhcpcd -k" may have stopped it and a plain rebind does not
        # restart it - a full service restart does.
        if svc_enabled dhcpcd || svc_active dhcpcd; then
            systemctl restart dhcpcd || true
        else
            dhcpcd $IF || true
        fi
        sleep 3
        has wpa_cli && { wpa_cli -i $IF reconfigure || true; }
        ;;
    dhclient)
        has wpa_cli && { wpa_cli -i $IF reconfigure || true; }
        dhclient $IF || true
        ;;
esac
exit 0
"""


def _wlan0_ipv4():
    try:
        out = (
            subprocess.run(
                ["ip", "-4", "-o", "addr", "show", "dev", "wlan0"],
                stdout=PIPE,
                stderr=STDOUT,
                text=True,
                timeout=5,
            ).stdout
            or ""
        )
    except Exception:
        return None
    for line in out.split("\n"):
        parts = line.split()
        if "inet" in parts:
            return parts[parts.index("inet") + 1]
    return None


def wlanreset(parm: Optional[str] = None) -> CommandResult:
    """Completely reset wlan0 so it gets a fresh DHCP lease from the router.

    Drops the lease, flushes addresses, takes the link down, cycles the WiFi
    radio (rfkill / nmcli), brings the link up and asks NetworkManager, dhcpcd
    or dhclient - whichever the image uses - to reconnect. Then waits for an
    IPv4 address.

    Does not touch msxpi0 or NAT: if the uplink address changed, run
    "p netreset" afterwards.

    Optional parameter: seconds to wait for an address (default 30, max 90).
    """
    if transport.hostType != "RaspberryPi":
        return "Command not supported by this platform"

    wait = 30
    if parm:
        try:
            wait = max(5, min(90, int(parm.split()[0])))
        except ValueError:
            pass

    try:
        done = subprocess.run(
            ["sudo", "sh", "-c", _WLANRESET_SCRIPT],
            stdout=PIPE,
            stderr=STDOUT,
            text=True,
            timeout=60,
        )
        print(f"wlanreset: rc={done.returncode}\n{done.stdout or ''}", flush=True)
    except Exception as exc:
        return f"Pi:wlanreset failed: {exc}"

    deadline = time.time() + wait
    addr = _wlan0_ipv4()
    while not addr and time.time() < deadline:
        time.sleep(1)
        addr = _wlan0_ipv4()

    if addr:
        return f"wlan0: {addr}"
    return f"Pi:wlanreset: no IPv4 on wlan0 after {wait}s"


def reboot(parm: Optional[str] = None) -> CommandResult:
    if transport.hostType == "RaspberryPi":
        print("Rebooting Raspberry Pi")
        os.system("sudo reboot")
    else:
        print("Command not supported by this platform")
        link_send(b"Command not supported by this platform")


def shut(parm: Optional[str] = None) -> CommandResult:
    """Shut the Raspberry Pi down. Sent by "p shut", and by msxarch once a game
    is fully loaded, right before it starts the game, when msxarch.ini has
    shutdownAfterRomLoad=yes.

    For interactive "p shut" the reply goes out FIRST and the MSX waits for it,
    so the exchange is complete before anything else happens.  msxarch uses
    "shut nowait" because the game is already staged and the launch path should
    not perform another receive/print before jumping into the ROM. Raspberry Pi
    ONLY: on any other host, the no-reply form is a logged no-op and the
    interactive form returns an unsupported-platform message."""
    no_reply = (parm or "").strip().lower() in ("nowait", "noack", "quiet")
    if transport.hostType == "RaspberryPi" and platform.system() == "Linux":
        if not no_reply:
            link_send(b"Pi:Ok")
        print("Shutting down Raspberry Pi in 2 seconds")
        subprocess.Popen(
            "sleep 2; sudo shutdown -h now",
            shell=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    else:
        print("Command not supported by this platform")
        if not no_reply:
            link_send(b"Command not supported by this platform")


def button_handler(channel):
    # Called by the transport's button monitor once the line has been held low
    # for 200 ms.  Released before 3 s: reboot.  Still held at 3 s: shut down
    # then, without waiting for the release.
    start = time.time()
    while transport.GPIO.input(transport.RPI_SHUTDOWN) == transport.GPIO.LOW:
        if time.time() - start >= 3:
            print("Shutdown triggered")
            os.system("sudo shutdown -h now")
            return
        time.sleep(0.01)
    print("Reboot triggered")
    os.system("sudo reboot")


def exitDueToSyncError():
    print("Sync error. Recycling MSXPi-Server")
    release_gpio()
    os.system(settings.MSXPIHOME + "/kill.sh")
