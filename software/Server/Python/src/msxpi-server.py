#!/usr/bin/python3
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
# Start-up and the command loop. The work is done in the msxpi_* modules next
# to this file; msxpi_transport owns the link state (conn, hostType, pins).

import logging
import os
import signal
import socket
import sys
from os.path import exists

SERVER_MODULES = (
    "msxpi_const.py",
    "msxpi_settings.py",
    "msxpi_transport.py",
    "msxpi_ethglue.py",
    "msxpi_blocks.py",
    "msxpi_cmd_disk.py",
    "msxpi_cmd_files.py",
    "msxpi_cmd_media.py",
    "msxpi_cmd_rom.py",
    "msxpi_cmd_stock.py",
    "msxpi_cmd_system.py",
    "msxpi_cmd_web.py",
)


def _fetch_missing_modules() -> None:
    """Download server modules missing beside this file.

    Before v1.6.x the server was one file, and the update.sh already on a Pi
    only knows that file list: it brings a new msxpi-server.py without the
    modules it now imports, and the server would die at every start - with the
    MSX unable to reach the Pi to run the update again. Fetch from the same
    place update.sh does (MSXPI_UPDATE_BASE, a URL or a directory).
    """
    here = os.path.dirname(os.path.abspath(__file__))
    missing = [m for m in SERVER_MODULES if not os.path.exists(os.path.join(here, m))]
    if not missing:
        return
    import shutil
    import urllib.request

    base = os.environ.get(
        "MSXPI_UPDATE_BASE",
        "https://raw.githubusercontent.com/costarc/MSXPi/master/software/Server/Python/src",
    )
    for name in missing:
        target = os.path.join(here, name)
        try:
            if base.startswith(("http://", "https://")):
                with urllib.request.urlopen(f"{base}/{name}", timeout=30) as r:
                    data = r.read()
                if not data:
                    raise OSError("empty download")
                with open(target + ".new", "wb") as f:
                    f.write(data)
            else:
                shutil.copyfile(os.path.join(base, name), target + ".new")
            os.replace(target + ".new", target)
            print(f"MSXPi Server: fetched missing module {name}")
        except Exception as e:
            print(f"MSXPi Server: cannot fetch {name} from {base}: {e}")


_fetch_missing_modules()

import msxpi_cmd_disk as disk
import msxpi_cmd_media as media
import msxpi_settings as settings
import msxpi_transport as transport
from msxpi_blocks import recvdata2, sendmultiblock
from msxpi_cmd_disk import (
    dosinit,
    dskioini,
    dskior,
    dskiords,
    dskios,
    dskiosct,
    dskiow,
    dskiowrs,
    reload,
    unmount_drive,
)
from msxpi_cmd_files import cd, date, dir, pcopy, run
from msxpi_cmd_media import music, play, vol
from msxpi_cmd_rom import execrom, msxarchive, ploadr
from msxpi_cmd_stock import stock
from msxpi_cmd_system import (
    button_handler,
    netreset,
    pset,
    q,
    reboot,
    restart,
    shut,
    tcpip,
    ver,
    wifi,
    wlanreset,
)
from msxpi_cmd_web import chatgpt, irc, pchess, renderpage, showpage, template
from msxpi_const import BUILD_ID, RC_CONNERR, RC_SUCCESS, VERSION
from msxpi_settings import MSXPiConfig, getMSXPiVar

sys.stdout.reconfigure(line_buffering=True)
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger("msxpi")

MSXPIHOME = "/home/pi/msxpi"
# MSXPI_HOME overrides it. The line above stays literal: test harnesses patch
# it in the source text, as they do PORT below.
MSXPIHOME = os.environ.get("MSXPI_HOME", MSXPIHOME)
settings.MSXPIHOME = MSXPIHOME

HOST = "0.0.0.0"  # Listen on all interfaces
PORT = 5000  # Match this with serverPort in your C++ code
# MSXPI_PORT overrides it, so a second server can run beside the first.
PORT = int(os.environ.get("MSXPI_PORT", PORT))

# The MSX may call exactly these. Before this table the dispatcher looked the
# name up in globals(), so any helper in the server (a downloader, a GPIO
# setter) was also reachable from the MSX by name.
COMMANDS = {
    f.__name__: f
    for f in (
        cd,
        chatgpt,
        date,
        dir,
        dosinit,
        dskioini,
        dskior,
        dskios,
        dskiow,
        irc,
        pchess,
        msxarchive,
        music,
        netreset,
        pcopy,
        play,
        ploadr,
        pset,
        q,
        reboot,
        reload,
        renderpage,
        restart,
        run,
        shut,
        stock,
        tcpip,
        template,
        ver,
        vol,
        wifi,
        wlanreset,
    )
}
COMMANDS.update(
    {
        "set": pset,  # "set" cannot be a function: it would shadow set()
        "dskiords": dskiords,  # pre-v1.6 ROM names, see msxpi_cmd_disk
        "dskiowrs": dskiowrs,
        "dskiosct": dskiosct,
        "execrom": execrom,  # EXECROM.MAC /W and msxarch.c
        "showpage": showpage,
    }
)


def resolve_command(cmd: str):
    """The handler for an MSX command; KeyError if there is none."""
    return COMMANDS[cmd.lower()]


def _reply(payload: bytes) -> None:
    try:
        sendmultiblock(payload)
    except Exception:
        pass


def handle_command(buf: bytes) -> None:
    """Run one command received from the MSX and send back any reply."""
    # errors='replace' rather than raising: a byte of line noise then becomes
    # an unrecognised command, which the loop already handles by resyncing,
    # instead of an exception that tears down the connection.
    cmd, *rest = buf.decode("utf-8", "replace").split()
    parms = " ".join(rest)
    # "p set IRCPASSWORD secret" must not land in the log.
    shown = (
        "[hidden]" if parms.upper().startswith(tuple(settings.SECRET_VARS)) else parms
    )
    print(f" -> {cmd} {shown}")
    try:
        result = resolve_command(cmd)(parms)
    except KeyError:
        err = f"MSXPi Server Error: Unknown command {cmd}"
        print(err)
        _reply(err.encode())
        return
    except Exception as e:
        print(f"MSXPi Server Command error: {str(e)}")
        _reply(("Pi:Error - " + str(e)).encode())
        return
    # Handlers usually reply themselves; a returned string or bytes is sent here.
    if isinstance(result, str):
        _reply(result.encode())
    elif isinstance(result, bytes):
        _reply(result)
    print("MSXPi Server waiting command:", end="", flush=True)


def ShowSecurityDisclaimer():
    print(
        "\n====================================================================================="
    )
    print("This server process is meant to handle communication with a MSX computer.")
    print("It allows the MSX to:\n")
    print(
        " * List/read (any) file from this computer or network (via the the PDIR/PCOPY commands).\n"
    )
    print(" * Execute arbitrary(!) shell commands (via the PRUN command).\n")
    if transport.hostType == "RaspberryPi":
        print(" * Configure the WiFi settings (via the PSET/PWIFI commands).\n")
    print(
        "Some very few commands designed specifically for Raspberry Pi requires elevation of"
    )
    print(
        "privileges using sudo - these commands will not be executed in the PC platforms and"
    )
    print(
        "when possible, a message will be returned to the MSX informing that the command is"
    )
    print("not supported.")
    print(
        "However notice that using PRUN, the MSX user can execute any commands in the host,"
    )
    print("bypassing the controls in the native MSXPi commands.")
    print(
        "=======================================================================================\n"
    )


def load_config(ini_path: str) -> MSXPiConfig:
    """msxpi.ini, or the defaults when there is none."""
    if exists(ini_path):
        config = MSXPiConfig.load(ini_path)
        if not config.has("SPI_CS"):
            for name, value in (
                ("SPI_HW", "False"),
                ("SPI_CS", "21"),
                ("SPI_SCLK", "20"),
                ("SPI_MOSI", "16"),
                ("SPI_MISO", "12"),
                ("RPI_READY", "25"),
            ):
                config.setdefault(name, value)
        return config
    return MSXPiConfig(
        ini_path,
        [
            ["PATH", MSXPIHOME],
            ["DriveA", MSXPIHOME + "/disks/msxpiboot.dsk"],
            ["DriveB", MSXPIHOME + "/disks/tools.dsk"],
            ["DriveM", "https://github.com/costarc/MSXPi/raw/master/software/target"],
            ["DriveR1", "https://www.msxarchive.nl/pub/msx/games/roms/msx1"],
            ["DriveR2", "https://www.msxarchive.nl/pub/msx/games/roms/msx2"],
            ["WIDTH", "80"],
            ["WIFISSID", "MYWIFI"],
            ["WIFIPWD", "MYWFIPASSWORD"],
            ["WIFICOUNTRY", "GB"],
            ["DSKTMPL", MSXPIHOME + "/disks/blank.dsk"],
            [
                "ROMDB",
                "https://raw.githubusercontent.com/costarc/openMSX/master/share/softwaredb.xml",
            ],
            ["IRCNICK", "msxpi"],
            ["IRCADDR", "chat.freenode.net"],
            ["IRCPORT", "6667"],
            ["PCHESSRELAY", ""],
            ["PCHESSLISTEN", "0.0.0.0"],
            ["PCHESSPORT", "5080"],
            ["SPI_HW", "False"],
            ["SPI_CS", "21"],
            ["SPI_SCLK", "20"],
            ["SPI_MOSI", "16"],
            ["SPI_MISO", "12"],
            ["RPI_READY", "25"],
            ["OPENAIKEY", ""],
            ["OPENAIMODEL", "gpt-4o-mini"],
            ["RAPIDAPIKEY", ""],
            ["RAPIDAPIHOST", ""],
            ["FINNHUBKEY", ""],
            ["TWELVEDATAKEY", ""],
            ["ALPHAVANTAGEKEY", ""],
        ],
    )


def configure_pins() -> None:
    """Hand the msxpi.ini pin numbers to the transport."""
    transport.SPI_CS = int(getMSXPiVar("SPI_CS"))
    transport.SPI_SCLK = int(getMSXPiVar("SPI_SCLK"))
    transport.SPI_MOSI = int(getMSXPiVar("SPI_MOSI"))
    transport.SPI_MISO = int(getMSXPiVar("SPI_MISO"))
    transport.RPI_READY = int(getMSXPiVar("RPI_READY"))
    # Shutdown/reboot button, GPIO 26 on PCB v1.2 Rev.1 and later.  No
    # RPI_SHUTDOWN line in msxpi.ini means GPIO 26, as it always was: making
    # the button opt-in left it dead on every existing install, whose msxpi.ini
    # never had the line.  Boards without a button set "var RPI_SHUTDOWN=none"
    # (or empty, or anything that is not a usable GPIO number), and the
    # interrupt is never set up: there the unconnected pin picked up noise that
    # read as a press and rebooted the Pi in a loop.  Never crash over a bad
    # value - the monitor would just restart the server for ever.
    shut_pin = (
        getMSXPiVar("RPI_SHUTDOWN").strip()
        if settings._config.has("RPI_SHUTDOWN")
        else "26"
    )
    transport.RPI_SHUTDOWN = (
        int(shut_pin) if shut_pin.isdigit() and 2 <= int(shut_pin) <= 27 else None
    )

    # Settling time between CS low and the first SPI clock edge, in ns, for
    # the native GPIO engine: "var GPIO_CS_SETUP_NS=1000" in msxpi.ini.  Unset
    # or invalid means 0, the original timing.  The v0.8.2 board (PCB v0.7
    # Rev.7) needs it; see msxpi_gpio_set_cs_setup() in native/gpio_transfer.c.
    # An MSXPI_GPIO_CS_SETUP_NS already in the environment wins, and the engine
    # itself reads that variable, so hand it over through the environment.
    cs_setup = getMSXPiVar("GPIO_CS_SETUP_NS").strip()
    if cs_setup.isdigit() and int(cs_setup) <= 100000:
        os.environ.setdefault("MSXPI_GPIO_CS_SETUP_NS", cs_setup)


def _on_sigterm(signum, frame):
    # SIGTERM (sudo shutdown, "p shut", a service stop) takes the same clean
    # exit as Ctrl-C, so the CPLD is told the server is going offline and the
    # pins are released.  kill -9 still cannot be caught.
    transport._stopping = True  # before any finally: block can relight it
    raise KeyboardInterrupt


def connect():
    return transport.initialize_connection(HOST, PORT, button_handler)


def serve_gpio() -> None:
    """SPI mode: keep trying forever."""
    # Set the GPIO link up first: without this the first recvdata2() ran on
    # unconfigured pins, failed with "Please set pin numbering mode", and only
    # the error path below set the link up - a false error on every start.
    connect()
    print("MSXPi Server waiting command:", end="")
    while True:
        try:
            transport.DISABLETIMEOUT = True
            rc, buf = recvdata2()
            if rc == RC_SUCCESS:
                transport.DISABLETIMEOUT = False
                handle_command(buf)
            elif rc == RC_CONNERR:
                print("MSXPi Server: Connection error, reinitializing...")
                connect()
        except Exception as e:
            print(f"MSXPi Server Command error: {str(e)}")
            _reply(("Pi:Error - " + str(e)).encode())
            connect()


def serve_tcp(server_socket: socket.socket) -> None:
    """openMSX mode: accept loop with reconnection."""
    # One listening socket for the life of the server.  Opening a new one on
    # every pass bound port 5000 a second time while the first listener was
    # still open, which SO_REUSEADDR does not permit, so the first reconnect
    # killed the server with EADDRINUSE.
    while True:
        print("MSXPi Server: Waiting for MSX connection...")
        conn, addr = server_socket.accept()
        print(f" ** MSX Connected to {addr} **\n")
        # openMSX sends one byte per OUT. With Nagle on its side and delayed
        # ACK here, a /WAIT burst write (512 back-to-back bytes with no reply
        # between them) costs tens of milliseconds PER BYTE, which looks
        # exactly like a hung transfer. Ask for immediate ACKs and keep our own
        # one-byte replies prompt. openMSX should also set TCP_NODELAY (see
        # openMSX/src/MSXPiDevice.cc); this helps until such a build is
        # deployed. The Pi's GPIO link is unaffected.
        try:
            conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            if hasattr(socket, "TCP_QUICKACK"):
                conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_QUICKACK, 1)
        except OSError as exc:
            print(f"socket tuning not applied: {exc}")
        transport.conn = conn
        transport.tcp_handshake(conn)

        print("MSXPi Server waiting command:", end="")
        try:
            while True:
                transport.DISABLETIMEOUT = True
                rc, buf = recvdata2()
                if rc == RC_SUCCESS and buf is not None:
                    transport.DISABLETIMEOUT = False
                    handle_command(buf)
                elif rc == RC_CONNERR:
                    print("MSXPi Server: Protocol error, forcing reconnect")
                    break
        except (ConnectionResetError, BrokenPipeError, OSError) as e:
            print(f"MSXPi Server: connection lost: {e}")
        except Exception as e:
            print(f"MSXPi Server Error: {str(e)}")
            _reply(("Pi:Error - " + str(e)).encode())
        finally:
            try:
                conn.close()
            except Exception:
                pass
            print("MSXPi Server: Client disconnected, waiting for new connection...")


def main() -> None:
    # MSXPI_INI points at another msxpi.ini (a test's own configuration).
    settings._config = load_config(
        os.environ.get("MSXPI_INI", MSXPIHOME + "/msxpi.ini")
    )
    media.init_player()
    logger.info(f"Starting MSXPi Server Version {VERSION} Build {BUILD_ID}")

    transport.hostType = transport.detect_host()
    ShowSecurityDisclaimer()
    if transport.hostType == "RaspberryPi":
        import RPi.GPIO as GPIO

        transport.GPIO = GPIO
    configure_pins()
    signal.signal(signal.SIGTERM, _on_sigterm)

    server_socket = None
    try:
        if transport.hostType == "RaspberryPi":
            serve_gpio()
        else:
            server_socket = connect()
            serve_tcp(server_socket)
    except KeyboardInterrupt:
        if transport.hostType == "RaspberryPi":
            transport.release_gpio()
        if server_socket:
            try:
                server_socket.close()
            except Exception:
                pass
        for image in (disk.drive0Data, disk.drive1Data):
            unmount_drive(image)
        print("MSXPi Server: Terminating")


if __name__ == "__main__":
    main()
