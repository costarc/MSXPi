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

from typing import Union

# Standard library imports
import logging

# Third-party imports

logger = logging.getLogger("msxpi")


# =============================================================================
# VERSION & BUILD INFORMATION
# =============================================================================
# What an MSX command handler returns: a status code, a reply the dispatcher
# sends for it (str or bytes), or None when the handler replied itself.
CommandResult = Union[int, str, bytes, None]

VERSION = "1.6"
BUILD_ID = "20260926.061"

# =============================================================================
# PROTOCOL CONSTANTS - SPI and Block Transfer
# =============================================================================
CMDSIZE = 9  # Command size in bytes
MSGSIZE = 128  # Message size in bytes
BLKSIZE = 512  # Block size in bytes
SECTORSIZE = 512  # Disk sector size in bytes
BULKBLKSIZE = 3 + 4096  # Bulk block size (header + data)
MAXBUFSIZE = 48 * 1024  # 48 KB buffer in MSX side

# SPI Bit-Bang Timing
SPI_SCLK_LOW_TIME = 0.001  # Clock low period (seconds)
SPI_SCLK_HIGH_TIME = 0.001  # Clock high period (seconds)

# Control Byte Values (MSX-Pi Protocol)
READY_ACK = 0xA0  # Acknowledge READY signal
SENDNEXT = 0xA1  # Send next block
ENDTRANSFER = 0xA2  # End of transfer
READY = 0xAA  # Ready signal
RC_CHKSUM_ERR = 0xAD  # Checksum error
WAIT = 0xAE  # Wait signal

# =============================================================================
# RETURN CODES (RC_*)
# =============================================================================
RC_SUCCESS = 0xE0  # Successful operation
RC_INVALIDCOMMAND = 0xE1  # Invalid command
RC_ESCPRESSED = 0xE2  # Escape key pressed
RC_BUFOVFLW = 0xE3  # Buffer overflow
RC_INVALIDDATASIZE = 0xE4  # Invalid data size
RC_HANDSHAKEERR = 0xE5  # Handshake error
RC_FILENOTFOUND = 0xE6  # File not found
RC_FAILED = 0xE7  # Operation failed
RC_CONNERR = 0xE8  # Connection error
RC_WAIT = 0xE9  # Wait status
RC_READY = 0xEA  # Ready status
RC_SUCCNOSTD = 0xEB  # Success, no standard
RC_FAILNOSTD = 0xEC  # Failed, no standard
RC_TERMINATE = 0xED  # Terminate connection
RC_UNEXPECTEDDATA = 0xEE  # Unexpected data
RC_UNDEFINED = 0xEF  # Undefined error

# =============================================================================
# RETRY & TIMEOUT CONFIGURATION
# =============================================================================
GLOBALRETRIES = 10  # Global retry limit
MAX_BLOCK_RETRIES = 3  # Block-level retry limit
SPI_INT_TIME = 3000  # SPI interrupt time (milliseconds)

# Timeout values (in seconds)
PIWAITTIMEOUTOTHER = 120  # Standard timeout for most operations
PIWAITTIMEOUTBIOS = 60  # Timeout for BIOS operations
SYNCTIMEOUT = 30  # Synchronization timeout
BYTETRANSFTIMEOUT = 180  # Byte transfer timeout (MSX drains blocks slowly)
SYNCTRANSFTIMEOUT = 180  # Sync transfer timeout
HTTP_TIMEOUT = 15  # HTTP request timeout (web fetches)

# =============================================================================
# ROM HEADER & MAPPER CONFIGURATION
# =============================================================================
ROM_HEADER_MAGIC = 0x52  # ROM header magic ('R')
ROM_HEADER_VERSION = 1  # ROM header version
ROM_HEADER_SIZE = 16  # ROM header size in bytes

# Mapper Types
MAPPER_PLAIN = 0  # Linear ROM (no mapper)
MAPPER_KONAMI = 1  # Konami mapper (8K banks)
MAPPER_ASCII8 = 2  # ASCII8 mapper (8K banks)
MAPPER_ASCII16 = 3  # ASCII16 mapper (16K banks)
MAPPER_REJECTED = 0xFF  # Mapper rejected (unsupported)

# ROM Size Limits
PLAIN_ROM_MAX_SIZE = 32768  # Client's fixed load window (32KB)
ROM_MAX_SIZE = 1048576  # Maximum ROM size cap (1MB)

# Block-size / length bit that marks a /WAIT burst payload (see sendmultiblock).
BURST_FLAG = 0x8000

st_init = 0  # waiting loop, waiting for a command
st_cmd = 1  # transfering data for a command
st_recvdata = 2
st_senddata = 4
st_synch = 5  # running a command received from MSX
st_runcmd = 6
st_shutdown = 99

NoTimeOutCheck = False
TimeOutCheck = True
