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

from typing import Optional

# Standard library imports
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
import msxpi_cmd_disk as disk
import msxpi_settings as settings
import msxpi_transport as transport
from msxpi_blocks import sendmultiblock
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
        return sendmultiblock(out.encode())

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
        return sendmultiblock(helptext.encode())

    # Now treat first token as variable name
    varname = parts[0]
    varname_upper = varname.upper()

    # ---------------------------------------------------------
    # 2. Single variable display:  set wifi
    # ---------------------------------------------------------
    if len(parts) == 1:
        for name, value in settings._config.items():
            if name.upper() == varname_upper:
                return sendmultiblock(f"{name}={shown_value(name, value)}".encode())
        return sendmultiblock(f"{varname} not found".encode())

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
        return sendmultiblock(helptext.encode())

    # ---------------------------------------------------------
    # 4. Delete variable:  set wifi /d
    # ---------------------------------------------------------
    if parts[1].lower() in ("/d", "/delete"):
        print(f"Deleting variable {varname}")
        rc = setMSXPiVar(varname, "")  # empty value = delete
        return sendmultiblock("Pi:Ok".encode())

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

        return sendmultiblock("Pi:Ok".encode())

    return sendmultiblock("Pi:Error".encode())


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
        sendmultiblock("Pi:Usage:\npwifi display | set".encode())
        return RC_SUCCESS

    if cmd[:1] == "s" or cmd[:1] == "S":
        if transport.hostType == "RaspberryPi":
            wifisetcmd = (
                'sudo nmcli device wifi connect "'
                + wifissid
                + '" password "'
                + wifipass
                + '"'
            )
            run(wifisetcmd)
        else:
            sendmultiblock(b"Parameter not supported in this platform")
    else:
        if transport.hostType == "RaspberryPi":
            sendmultiblock(interfaces_report().encode())
        else:
            run("ipconfig")

    return RC_SUCCESS


def ver(parms: Optional[str] = None) -> CommandResult:
    """Send server version information to MSX."""
    version_string = f"MSXPi Server Version {VERSION} Build {BUILD_ID}\n"
    logger.info(f"Sending version info: {version_string.strip()}")
    return sendmultiblock(version_string.encode())


def q(parm: Optional[str] = None) -> CommandResult:
    """Client-side quit notification (see sendQuit() in msxarch.c/p.c). The
    client sends this and, on most paths, exits back to DOS immediately
    afterward without waiting for/completing a reply - so this must return
    None (no sendmultiblock reply attempted). Previously there was no "q"
    handler at all, so this hit the KeyError/"Unknown command" path, which
    tried to sendmultiblock() an error string to a client that had already
    gone away - leaving the server mid-handshake with nobody listening,
    corrupting the next session's protocol state (surfaced as garbage
    checksums, a forced reconnect, and a "Disk error reading drive A" on
    whatever ran next)."""
    print("q(): client quit")


def restart(parm: Optional[str] = None) -> CommandResult:
    if transport.hostType == "RaspberryPi":
        print("Restarting MSXPi Server")
        sendmultiblock(b"Pi:Ok")
        exitDueToSyncError()
    else:
        print("Command not supported by this platform")
        sendmultiblock(b"Command not supported by this platform")


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
        sendmultiblock(b"Command not supported by this platform")


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
            sendmultiblock(b"Pi:Ok")
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
            sendmultiblock(b"Command not supported by this platform")


def button_handler(channel):
    # A press must hold the line low WITHOUT A BREAK for 200 ms.  Noise coupled
    # from SCLK/CS (header pins 38/40, next to transport.GPIO 26 on pin 37) is continuous
    # during a transfer, so a single sample could land low and reboot the Pi;
    # sampling every 5 ms cannot be fooled that way.
    for _ in range(40):
        time.sleep(0.005)
        if transport.GPIO.input(transport.RPI_SHUTDOWN) != transport.GPIO.LOW:
            return
    start = time.time()
    # Wait for release
    while transport.GPIO.input(transport.RPI_SHUTDOWN) == transport.GPIO.LOW:
        time.sleep(0.01)
    duration = time.time() - start

    if duration >= 3:
        print("Shutdown triggered")
        os.system("sudo shutdown -h now")
    else:
        print("Reboot triggered")
        os.system("sudo reboot")


def exitDueToSyncError():
    print("Sync error. Recycling MSXPi-Server")
    release_gpio()
    os.system(settings.MSXPIHOME + "/kill.sh")
