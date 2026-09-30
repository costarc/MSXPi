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

# =============================================================================
# sltsl_off - the SLTSL jumper open: the EEPROM is cut off, the machine boots
# plain BASIC and CALL MSXPI does not exist.  Needs the whole-board extension:
#
#   HW=basic MSXPIEXT=MSXPi MSXPISLTSL=OFF ./run.sh sltsl_off
# =============================================================================

harness::init "sltsl_off"

harness::wait_for "Ok" 40 {
    harness::assert_screen_lacks "no-msxpi-banner" "MSXPi BIOS"
    harness::type_line "CALL MSXPIVER"
    harness::wait_for "Syntax error" 20 {
        harness::assert_screen_lacks "no-msxpi-banner-after-call" "MSXPi BIOS"
        harness::done
    }
}
