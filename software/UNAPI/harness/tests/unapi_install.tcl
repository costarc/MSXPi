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
# unapi_install - the RAM installer must refuse when the ROM driver is present.
#
# Once the driver ships in msxpibios.rom there is already an ETHERNET
# implementation registered before anything runs, so ETHUNAPI.COM has to say
# so and stop.  Installing anyway would chain the EXTBIO hook to a second
# implementation of the same API, and the discovery procedure would report two
# where the machine has one.
#
# So this test pins the refusal, not the installation.  ETHUNAPI.COM is still
# built and still works - it is the option for people who cannot reflash - but
# it cannot be exercised on a machine whose ROM already carries the driver,
# which is every machine this harness models.
#
# RAMHELPR is deliberately NOT run first.  The installer checks "is one already
# installed" BEFORE it looks for the RAM helper, so that a user on a flashed
# machine gets the reason that actually applies instead of being sent off to
# install RAMHELPR for a problem they do not have.  Running with no helper
# present is what pins that ordering.
# =============================================================================

harness::init "unapi_install"

harness::at_dos_prompt {
    harness::run_cmd "ETHUNAPI" 60 {
        set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
        foreach l [harness::screen_lines] { puts $fh "|$l" }
        close $fh
        # The screen is 32 columns and the message wraps mid-word, so match a
        # fragment that cannot straddle the wrap.
        harness::assert_screen_contains "already-installed" \
            "ETHERNET UNAPI is"
        harness::assert_screen_lacks "did-not-install" "Transport:"
        # The point of the reordering: this must NOT be what it complains about.
        harness::assert_screen_lacks "not-the-helper" "No UNAPI RAM helper"
        harness::done
    }
}
