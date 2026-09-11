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
# msxpi_roundtrip - proves the MSX <-> server transport works.
#
# This is the path the whole UNAPI driver is built on: a command goes out over
# ports $56/$57/$5A, the server answers with a checksummed block, and the MSX
# accepts it.  The assertions that matter are on the SERVER side (see
# msxpi_roundtrip.expect) - P VER scrolls its output away, so checking the
# screen alone would pass even if nothing had been transferred.
# =============================================================================

harness::init "msxpi_roundtrip"

harness::at_dos_prompt {
    harness::run_cmd "P VER" 60 {
        # The command must at least have returned to a prompt rather than hung
        # or dropped into an error.
        harness::assert_screen_contains "returned-to-prompt" "A:"
        harness::assert_screen_lacks    "no-comms-error"     "Communication Error"
        harness::done
    }
}
