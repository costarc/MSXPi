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
# dos_dir - proves the harness can drive the machine and read what came back.
#
# Types a command at the DOS prompt and asserts on its output.  This is the
# mechanism every later test uses to run a .COM and check its result, so it is
# worth testing on its own with something that cannot fail for its own reasons.
# =============================================================================

harness::init "dos_dir"

harness::at_dos_prompt {
    # DIR of one named file, not the whole disk.  A bare DIR used to work,
    # but the served image has grown past a screenful and MSXPIBIO.ROM - one
    # of the first entries - now scrolls off the top of the 24-row display
    # before the command finishes.  Naming the file tests the same thing and
    # cannot scroll.
    harness::run_cmd "DIR MSXPIBIO.ROM" 60 {
        harness::assert_screen_contains "sees-msxpi-rom" "MSXPIBIO ROM"
        harness::assert_screen_contains "reports-total"  "bytes free"
        harness::assert_screen_lacks    "no-dos-error"   "Bad command"
        harness::done
    }
}
