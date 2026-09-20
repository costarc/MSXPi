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
# pver - PVER.COM prints the board/CPLD build read from port $57, then the
# server version ("p ver").  openMSX emulates the main v1.6 CPLD, so the board
# part must decode build ID $0E, and /WAIT is only reported where the emulator
# really implements it (the WSL build).
# =============================================================================

harness::init "pver"

harness::at_dos_prompt {
    harness::run_cmd "PVER" 60 {
        harness::assert_screen_contains "port-57"        "Port \$57: \$0E"
        harness::assert_screen_contains "build-id"       "Build ID: \$0E"
        harness::assert_screen_contains "board-name"     "Board   : v1.3 to v1.6"
        harness::assert_screen_contains "firmware-name"  "v1.6 /WAIT build"
        harness::assert_screen_contains "wait-probe"     "/WAIT   : yes (burst)"
        harness::assert_screen_contains "server-version" "MSXPi Server Version"
        harness::assert_screen_lacks    "no-comms-error" "connection error"
        harness::done
    }
}
