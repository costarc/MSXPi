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
# wsl_client - run a stock Konamiman TCP/IP UNAPI client against the stack.
#
# This is the Phase 6 acceptance test: not our own test program, but software
# written years before this driver existed, reaching it through two layers of
# UNAPI. It also exercises the CALSLT interrupt question from PHASE1_DESIGN 9 -
# a foreground client that fails to re-enable interrupts would stop INL's timer
# ISR and hang.
# =============================================================================

harness::init "wsl_client"

harness::at_dos_prompt {
    harness::run_cmd "MSR I" 60 {
        harness::run_cmd "ETHUNAPI" 60 {
            harness::run_cmd "INL I" 90 {
                harness::run_cmd "TCPCON" 90 {
                    set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                    foreach l [harness::screen_lines] { puts $fh "|$l" }
                    close $fh
                    harness::pass ran; harness::done
                }
            }
        }
    }
}
