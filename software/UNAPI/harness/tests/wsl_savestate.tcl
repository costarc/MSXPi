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
# wsl_savestate - MSXPiDevice::serialize(): a savestate keeps the EEPROM where
# the running code expects it.
#
# Needs a fork build with the EEPROM support in MSXPiDevice and the whole-board
# extension (MSXPiDevice with a <rom> child, mapped over the whole slot).
#
# The jumper settings are read at reset, so changing one while the machine runs
# must NOT move the ROM.  A savestate must keep that: this is what the reverse
# sub-system does internally (PgUp, or step_back in the debugger), and it
# rebuilds the device from scratch.  Without serialize() the restored device
# picks up the CURRENT setting instead, the ROM disappears, and the Z80 reads
# FFh where its code used to be.
#
# Checked against both builds: with serialize() 4000h still reads the "AB"
# cartridge header (65 66); without it, 255 255.
# =============================================================================

harness::init "wsl_savestate"

# This test changes a setting; don't let that leak into the user's settings.xml.
set ::save_settings_on_exit false

harness::at_dos_prompt {
    harness::run_cmd "DIR MSXPIBIO.ROM" 300 {
        harness::assert_screen_contains "dir-before" "bytes free"
        harness::assert_eq "rom-before" "65 66" \
            "[debug read memory 0x4000] [debug read memory 0x4001]"

        # move the jumper, but no reset: the ROM must stay visible
        set ::msxpirom_sltsl OFF
        harness::assert_eq "rom-after-jumper-change" "65 66" \
            "[debug read memory 0x4000] [debug read memory 0x4001]"

        savestate msxpi_savestate_test
        loadstate msxpi_savestate_test

        # the restored machine must still see the ROM ...
        harness::assert_eq "rom-after-loadstate" "65 66" \
            "[debug read memory 0x4000] [debug read memory 0x4001]"

        # ... and keep running: DOS still works and the link still answers
        harness::run_cmd "DIR MSXPIBIO.ROM" 300 {
            harness::assert_screen_contains "dir-after" "bytes free"
            harness::assert_screen_lacks "no-error" "error"
            set ::msxpirom_sltsl ON
            harness::done
        }
    }
}
