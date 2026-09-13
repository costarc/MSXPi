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

# =============================================================================
# wsl_waitmode - proves the hardware /WAIT transport is selected.
#
# Only meaningful against an openMSX built from Dev/github/openMSX/openMSX with
# the MSXPiDevice wait-mode support, i.e. /opt/openMSX in WSL.  The stock
# Windows binary reports $FE on port $57, so the driver correctly falls back to
# the polled backend and this test would fail for the right reason.
#
# The assertion used to be ETHUNAPI's install banner.  With the driver in the
# ROM there is no installer to print one: the driver probes the transport
# itself, on the first UNAPI call, and ETHTEST reports what it settled on
# through implementation-specific routine 128.  Mode 01 is MODE_WAIT, and it
# can only be reached by writing $01 to $57, reading back an exact $8E, AND
# then completing a real probe transaction over the /WAIT path - so this still
# proves the device implemented the mode register and that the mode works.
# =============================================================================

harness::init "wsl_waitmode"

harness::at_dos_prompt {
    harness::run_cmd "ETHTEST" 90 {
        set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
        foreach l [harness::screen_lines] { puts $fh "|$l" }
        close $fh
        harness::assert_screen_contains "found"     "Found: 01"
        harness::assert_screen_contains "wait-mode"  "Mode:  01"
        # A completed round trip on that transport, not just the mode byte.
        harness::assert_screen_contains "mac"        "024D53585069"
        harness::assert_screen_contains "netstat"    "Net:   01"
        # Wait mode is per-transaction and must be off again by now.
        harness::assert_screen_contains "no-leaked-waitmode" "P57:   0E"
        harness::done
    }
}
