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
# at28_tag - AT28C256 /i flags the MSXPi ROM by the MSXPI tag in its header.
#
# The tag is the reserved header bytes 400Ah-400Eh of both EEPROM halves.
# The harness puts MSXPi in slot 2 (see run.sh), so "/s 2 /i" dumps its header
# and has to print the tag note.
# =============================================================================

harness::init "at28_tag"

harness::at_dos_prompt {
    harness::run_cmd "AT28C256 /s 2 /i" 60 {
        harness::assert_screen_contains "header-ab"      "41 42"
        harness::assert_screen_contains "tag-flagged"    "MSXPI tag found"
        harness::assert_screen_lacks    "no-dos-error"   "Bad command"
        harness::done
    }
}
