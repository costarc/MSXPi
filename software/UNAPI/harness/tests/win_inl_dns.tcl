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
# win_inl_dns - the emulated MSX resolves a name through the WINDOWS TAP.
#
# The end of the Windows road: openMSX -> msxpi-server.py -> WinTapLink ->
# TAP-Windows adapter -> WinNAT -> the real internet, and an answer back.
#
# This is wsl_inl's install flow (MSR I, INL I) followed by the one thing that
# proves the link carries traffic rather than merely coming up: a DNS lookup.
# INL reports "installed" quite happily with no network underneath it - that is
# exactly what MockLink does, answering every opcode correctly and carrying
# nothing - so the install alone asserts very little.
#
# Requires, on Windows:
#   - the OpenVPN TAP driver (tap-windows6)
#   - msxpi-tcpip-setup.ps1 run once, as Administrator
#   - nothing else holding the adapter (an OpenVPN session will)
#
# software/Tests/test_wintap_nat.py proves that same path with no MSX in it,
# and is the thing to run first when this fails: if it passes and this does
# not, the fault is on the MSX side of the shuttle, not in Windows.
#
# HOST is InterNestor Lite's resolver client. It prints the address on success
# and an error code on failure ("8: DNS not found" when the query goes nowhere,
# which is what a MockLink or a broken NAT looks like from here).
# =============================================================================

harness::init "win_inl_dns"

harness::at_dos_prompt {
    harness::run_cmd "MSR I" 60 {
        harness::run_cmd "INL I" 90 {
            harness::run_cmd "HOST GOOGLE.COM" 120 {
                set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                foreach l [harness::screen_lines] { puts $fh "|$l" }
                close $fh

                # A PUBLIC address, not merely "an IPv4 address on screen":
                # INL echoes its own configuration as it installs, so the
                # local address, the mask, the gateway and the resolver are
                # all sitting there already and any bare dotted-quad match
                # would pass with no network underneath at all.
                set found ""
                foreach ip [regexp -all -inline \
                        {[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+} [harness::screen_text]] {
                    if {![string match "192.168.*" $ip]
                        && ![string match "255.*" $ip]
                        && ![string match "0.*" $ip]
                        && ![string match "10.*" $ip]} {
                        set found $ip
                        break
                    }
                }
                if {$found ne ""} {
                    harness::pass "resolved" $found
                } else {
                    harness::fail "resolved" \
                        "no public address on screen - the lookup did not return one"
                }
                harness::assert_screen_lacks "no-dns-error" "DNS not found"
                harness::done
            }
        }
    }
}
