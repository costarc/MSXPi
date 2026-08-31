# =============================================================================
# unapi_discovery - the full Phase 4 chain.
#
# Installs the RAM helper and the driver, then runs ETHTEST.COM, which performs
# the standard UNAPI discovery procedure and calls ETH_GETINFO through the RAM
# helper.  Passing proves the EXTBIO hook chains correctly, the implementation
# reports its slot/segment/entry point, and routine dispatch works.
# =============================================================================

harness::init "unapi_discovery"

harness::at_dos_prompt {
    harness::run_cmd "RAMHELPR I" 60 {
        harness::run_cmd "ETHUNAPI" 60 {
            harness::run_cmd "ETHTEST" 60 {
                set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                foreach l [harness::screen_lines] { puts $fh "|$l" }
                close $fh
                harness::assert_screen_contains "found-one"   "Found: 01"
                harness::assert_screen_contains "api-is-1.1"  "API:   0101"
                harness::assert_screen_contains "impl-is-0.1" "Impl:  0001"
                # These three cross the wire to msxpi_eth.py, so they validate
                # whichever transport backend this host selected - polled on the
                # stock Windows openmsx.exe, hardware /WAIT under WSL.  The MAC
                # is msxpi_eth.BaseLink's default and exists nowhere on the MSX
                # side, so seeing it proves the round trip really happened.
                harness::assert_screen_contains "mac-over-wire" "024D53585069"
                harness::assert_screen_contains "netstat"       "Net:   01"
                harness::assert_screen_contains "instatus"      "InSt:  00"
                # Wait mode must never be left on: while it is, $57 reads 8E and
                # msxpi_bios.asm:97 stops recognising openMSX.
                # Both values that mean "wait mode is still on": $8E on real
                # hardware, $FF on openMSX.
                harness::assert_screen_lacks "no-leaked-waitmode-hw"   "P57:   8E"
                harness::assert_screen_lacks "no-leaked-waitmode-omsx" "P57:   FF"
                harness::done
            }
        }
    }
}
