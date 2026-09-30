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
# basic_call - the BIOS-only ROM bank (msxpibas.rom) on a machine with no disk
# system at all.  Run with HW=basic.
#
# No disk kernel ran, so the ROM allocated no work area and its GETWRK hands
# msxpi_bios.asm PROCNM as the stash.  CALL MSXPIVER receives through
# PRINTPISTDOUT, and the "2,<buffer>,<cmd>" form through PerformHandshake and
# RECVDATA_ONEBLOCK - both use the stash, so a broken stash shows up here as a
# hang or a bad header instead of passing quietly.
# =============================================================================

harness::init "basic_call"

proc basic_call_dump {} {
    set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
    foreach l [harness::screen_lines] { puts $fh "|$l" }
    puts $fh "PC=[format %04X [reg pc]] SP=[format %04X [reg sp]]"
    set w {}
    foreach b [split [debug read_block memory 0xFD09 128] ""] { lappend w [format %02X [scan $b %c]] }
    puts $fh "SLTWRK=$w"
    close $fh
}

harness::wait_for "Ok" 40 {
    harness::type_line "CALL MSXPIVER"
    harness::wait_for "Server Version" 40 {
        harness::assert_screen_contains "bios-only-banner" "(no DOS)"
        harness::type_line {CALL MSXPI("2,C000,ver")}
        harness::wait 10 {
            harness::type_line {PRINT "RC=";PEEK(&HC000);"LEN=";PEEK(&HC001)+256*PEEK(&HC002)}
            harness::wait_for "LEN=" 20 {
                harness::wait 2 {
                    basic_call_dump
                    # RC_SUCCESS is E0h = 224.
                    harness::assert_screen_contains "buffered-rc-success" "RC= 224"
                    harness::assert_screen_lacks "no-basic-error" "error"
                    harness::done
                }
            }
        }
    } {
        basic_call_dump
        harness::fail "msxpiver" "no server version on screen"
        harness::done
    }
}
