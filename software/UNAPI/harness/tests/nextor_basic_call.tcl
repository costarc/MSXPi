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
# nextor_basic_call - CALL MSXPI from Disk BASIC with Nextor as the disk system
# and MSXPi in the higher slot.  Run with HW=nextor, once per ROM bank:
#
#   HW=nextor ./run.sh nextor_basic_call                        (MSX-DOS bank)
#   HW=nextor MSXPIEXT=MSXPiBasic ./run.sh nextor_basic_call    (BIOS-only bank)
#
# The .screen file records the drive count (F347h) and FRE(0): the BIOS-only
# bank must add no drives and leave more memory than the MSX-DOS bank.
# =============================================================================

harness::init "nextor_basic_call"

proc nextor_basic_call_dump {} {
    set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
    foreach l [harness::screen_lines] { puts $fh "|$l" }
    close $fh
}

harness::at_nextor_prompt {
    harness::type_line "BASIC"
    harness::wait_for "Ok" 30 {
        harness::type_line "CALL MSXPIVER"
        harness::wait_for "Server Version" 40 {
            harness::type_line {PRINT "DRV=";PEEK(&HF347);"FRE=";FRE(0)}
            harness::wait_for "FRE=" 20 {
                harness::wait 2 {
                    nextor_basic_call_dump
                    harness::assert_screen_contains "msxpiver" "MSXPi BIOS v1.6"
                    harness::assert_screen_lacks "no-basic-error" "error"
                    harness::done
                }
            }
        }
    }
}
