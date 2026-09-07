# =============================================================================
# unapi_discovery - the ROM implementation, discovered and called with nothing
# installed first.
#
# ETHTEST.COM runs the standard UNAPI discovery procedure and then calls
# routines through the implementation.  Passing proves the disk ROM's INIENV
# hooked EXTBIO, that the hook chains correctly, that the implementation
# reports slot/segment/entry point, and that routine dispatch works - all
# straight from a cold boot, with no RAMHELPR and no ETHUNAPI.
#
# The segment being FFh is the whole point of the ROM build: it is what puts
# stock clients, InterNestor Lite included, on their CALSLT path.
# =============================================================================

harness::init "unapi_discovery"

harness::at_dos_prompt {
    harness::run_cmd "ETHTEST" 60 {
        set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
        foreach l [harness::screen_lines] { puts $fh "|$l" }
        close $fh
        harness::assert_screen_contains "found-one"   "Found: 01"
        harness::assert_screen_contains "seg-is-rom"  "Seg: FF"
        harness::assert_screen_contains "api-is-1.1"  "API:   0101"
        harness::assert_screen_contains "impl-is-0.1" "Impl:  0001"
        # No helper was installed, so this must not have been needed.
        harness::assert_screen_lacks "no-helper-needed" "No RAM helper"
        # These three cross the wire to msxpi_eth.py, so they validate
        # whichever transport backend the driver detected on its first call -
        # polled on the stock Windows openmsx.exe, hardware /WAIT under WSL.
        # The MAC is msxpi_eth.BaseLink's default and exists nowhere on the MSX
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
