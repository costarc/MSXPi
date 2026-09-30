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

# Standard library imports
import time
import logging

# Third-party imports

logger = logging.getLogger("msxpi")

from msxpi_const import (
    RC_SUCCESS,
)
from msxpi_transport import SPI_BurstOut, SPI_ByteTransfer

# IRC client integration (currently disabled - awaiting complete implementation)
# TODO: Integrate IRC client when msxpi_irc module is ready
# Intended usage: from irc_client import * to enable irc_* commands
# IRC_ENABLED = False

# ---------------------------------------------------------------------------
# Ethernet UNAPI shuttle (msxpi_eth.py).
#
# Guarded like the IRC import: the server must still run if the module is
# missing.  eth_handle_opcode() is called from recvdata2()'s wait-for-READY
# loop, i.e. from the byte that loop was about to discard, so it must be cheap
# and must report False for anything that is not one of its opcodes.
#
# The shuttle is built lazily on the first opcode rather than at import: the
# transport functions it closes over (SPI_ByteTransfer / SPI_BurstOut) are
# defined further down this file, and on a Pi the GPIO setup has not run yet at
# import time.
# ---------------------------------------------------------------------------
try:
    import msxpi_eth as _eth_mod
except Exception as _e:
    _eth_mod = None
    print(f"Warning: failed to import msxpi_eth module: {_e}")

_eth_shuttle = None


# Module-level rather than lambdas built per shuttle: one less Python frame on
# every reply. The shuttle's contract is 0 = success (see msxpi_eth.EthShuttle);
# RC_SUCCESS is 0xE0 - truthy - so it must be mapped, not passed through, or
# every write would look like a failure.
def _eth_write_byte(v):
    return 0 if SPI_ByteTransfer(v)[0] == RC_SUCCESS else 1


def _eth_write_burst(data):
    return 0 if SPI_BurstOut(data) == RC_SUCCESS else 1


def eth_get_shuttle():
    """The EthShuttle, created on first use.  None if the module is absent."""
    global _eth_shuttle
    if _eth_mod is None:
        return None
    if _eth_shuttle is None:
        link = _eth_mod.make_link(log=print)
        _eth_shuttle = _eth_mod.EthShuttle(
            link,
            read_byte=SPI_ByteTransfer,
            # The shuttle's contract is 0 = success (see msxpi_eth.EthShuttle).
            # It deliberately does not know about this file's RC_* values, and
            # RC_SUCCESS is 0xE0 - truthy - so it must be mapped, not passed
            # through, or every write would look like a failure.
            write_byte=_eth_write_byte,
            write_burst=_eth_write_burst,
            log=print,
        )
        print("eth: Ethernet UNAPI shuttle ready (%s)" % type(link).__name__)
        _eth_note_link(link)
    return _eth_shuttle


# Seconds between attempts to replace a MockLink with the real TAP.
ETH_TAP_RETRY = 5.0
_eth_link_is_mock = False  # checked on the opcode path, so keep it a bool
_eth_tap_retry_at = 0.0


def _eth_note_link(link):
    """Remember whether the shuttle ended up on MockLink."""
    global _eth_link_is_mock
    _eth_link_is_mock = _eth_mod is not None and isinstance(link, _eth_mod.MockLink)


def _eth_retry_tap():
    """Swap a MockLink for the real TAP once msxpi0 becomes openable.

    make_link() runs once, lazily, on the first Ethernet opcode, and its result
    used to be kept for the life of the process.  msxpi-monitor starts
    msxpi-tcpip-setup.sh in the BACKGROUND and the server immediately after, so
    whether msxpi0 exists and is owned by the server's user when that first
    opcode lands is a race.  Losing it pinned MockLink, which answers every
    opcode correctly and carries no traffic whatsoever - the MSX installs INL,
    reports the link up, and nothing reaches the network - until somebody
    restarted the server by hand.

    The MSX-visible MAC is the same fixed address on every link (BaseLink's
    default), so a swap is invisible to the stack on the other side; the two
    pieces of state the MSX can change, ETH_ENABLE and ETH_FILTERS, are carried
    across.  Retries are silent: on a host that will never have a TAP (the
    openMSX harness) this runs for the life of the process.
    """
    global _eth_tap_retry_at
    now = time.monotonic()
    if now < _eth_tap_retry_at:
        return
    _eth_tap_retry_at = now + ETH_TAP_RETRY
    try:
        # TapLink directly, not make_link: its fallback would build a throwaway
        # MockLink (threads and all) and log a line on every failed retry.
        link = _eth_mod.TapLink()
    except Exception:
        return
    old = _eth_shuttle.link
    link.enabled = old.enabled
    link.filters = old.filters
    _eth_shuttle.link = link
    old.close()
    _eth_note_link(link)
    print("eth: msxpi0 is up now - MockLink replaced by the TAP", flush=True)


# Hoisted out of eth_handle_opcode: the membership test below runs on EVERY
# byte recvdata2() reads while waiting for READY, so it is on the path for all
# traffic and not just for opcodes. A module-global frozenset lookup avoids an
# attribute lookup on _eth_mod each time.
_eth_opcodes = _eth_mod.OPCODES if _eth_mod is not None else frozenset()
_eth_handle = None  # the shuttle's bound handle(), cached on first use


def eth_handle_opcode(opcode):
    """True if `opcode` was an Ethernet UNAPI op and has been served."""
    if opcode not in _eth_opcodes:
        return False
    global _eth_handle
    if _eth_handle is None:
        shuttle = eth_get_shuttle()
        if shuttle is None:
            return False
        # Cache the bound method: saves a function call plus an attribute
        # lookup per opcode, on a path where the per-transaction fixed cost is
        # what dominates short transactions.
        _eth_handle = shuttle.handle
    if _eth_link_is_mock:
        # Degraded: look for the TAP again (rate limited inside). Only ever on
        # this path while the link is Mock, so it costs a bool test otherwise.
        _eth_retry_tap()
    try:
        return _eth_handle(opcode)
    except Exception as e:
        print(f"eth: error serving opcode {hex(opcode)}: {e}")
        return True  # consumed; do not fall through to the garbage branch


def _eth_relink():
    """Re-attach the Ethernet link after the TAP device has been replaced.

    msxpi-tcpip-setup.sh deletes and recreates msxpi0, which leaves the
    shuttle holding a file descriptor to a device that no longer exists - it
    reads and writes without error and carries nothing. Nothing short of
    reopening recovers from that, so netreset() does it here rather than
    telling the user to restart the server.
    """
    global _eth_handle, _eth_tap_retry_at
    if _eth_mod is None or _eth_shuttle is None:
        return None  # nothing attached yet: first opcode will
    old = _eth_shuttle.link
    try:
        link = _eth_mod.TapLink()
    except Exception as exc:
        print(f"eth: TAP still unavailable after netreset ({exc})")
        _eth_tap_retry_at = 0.0  # let the opcode path keep trying
        return False
    link.enabled = old.enabled
    link.filters = old.filters
    _eth_shuttle.link = link
    old.close()
    _eth_note_link(link)
    _eth_handle = _eth_shuttle.handle
    print("eth: TAP device reattached after netreset", flush=True)
    return True


def _eth_release():
    """Let go of msxpi0 so the setup script can actually delete it.

    `ip tuntap del` does NOT remove a device that a process still has open: it
    clears the persist flag and the device survives, with its original owner,
    until that descriptor is closed. The server is exactly such a process, so
    a netreset that ran the script first would ask the kernel to delete a
    device it was itself holding - the delete "succeeded", the old device
    stayed, and the rebuild reconfigured the very device the server could not
    open. Drop to MockLink first: opcodes keep being answered while the
    network is being rebuilt, and netreset reattaches afterwards.
    """
    global _eth_handle
    if _eth_mod is None or _eth_shuttle is None:
        return
    old = _eth_shuttle.link
    if isinstance(old, _eth_mod.MockLink):
        return
    mock = _eth_mod.MockLink()
    mock.enabled = old.enabled
    mock.filters = old.filters
    _eth_shuttle.link = mock
    old.close()
    _eth_note_link(mock)
    _eth_handle = _eth_shuttle.handle
    print("eth: released msxpi0 for netreset", flush=True)
