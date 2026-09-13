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
# wsl_linkclaim - a P command must survive InterNestor Lite polling underneath.
#
# The MSXPi link carries the disk, the P commands AND the Ethernet UNAPI.  Once
# INL is resident it calls ETH_IN_STATUS from the 50/60 Hz timer interrupt, and
# that ISR used to transmit in the middle of a P exchange: on real hardware
# `p cd` printed its answer and then hung, with the server reporting a stray
# 0xC5 - OP_IN_STATUS - discarded while it waited for READY.
#
# The window is the whole EXCHANGE, not a block: the failure landed in the
# turnaround, after the command was sent and while the server was executing it,
# where the MSX is idle but the link is NOT free.  P.COM now claims the link
# through UNAPI routine 129 for that whole region.
#
# INL must be installed BEFORE the P command or there is no ISR to collide
# with and the test proves nothing.  MSR first: INL needs the mapper support
# routines under MSX-DOS 1.
#
# Timing in emulation is not hardware timing, so a pass here is weaker evidence
# than a pass on the Canon V-25 - the ISR may simply not land in the vulnerable
# window.  A FAILURE, though, is real: it means the guard is not working.
# =============================================================================

harness::init "wsl_linkclaim"

harness::at_dos_prompt {
    harness::run_cmd "MSR I" 60 {
        harness::run_cmd "INL I" 90 {
            harness::run_cmd "P VER" 60 {
                set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                foreach l [harness::screen_lines] { puts $fh "|$l" }
                close $fh
                # The command must have ANSWERED - the server's version string
                # comes back through the same exchange that used to hang.
                harness::assert_screen_contains "p-ver-answered" "MSXPi Server"
                # And it must not have died on the way.
                harness::assert_screen_lacks "no-conn-error" "Connection error"
                harness::done
            }
        }
    }
}
