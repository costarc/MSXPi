# =============================================================================
# wsl_waitmode - proves the hardware /WAIT transport is selected.
#
# Only meaningful against an openMSX built from Dev/github/openMSX/openMSX with
# the MSXPiDevice wait-mode support, i.e. /opt/openMSX in WSL.  The stock
# Windows binary reports $FE on port $57, so the driver correctly falls back to
# the polled backend and this test would fail for the right reason.
#
# The assertion used to be ETHUNAPI's install banner.  With the driver in the
# ROM there is no installer to print one: the driver probes the transport
# itself, on the first UNAPI call, and ETHTEST reports what it settled on
# through implementation-specific routine 128.  Mode 01 is MODE_WAIT, and it
# can only be reached by writing $01 to $57, reading back an exact $8E, AND
# then completing a real probe transaction over the /WAIT path - so this still
# proves the device implemented the mode register and that the mode works.
# =============================================================================

harness::init "wsl_waitmode"

harness::at_dos_prompt {
    harness::run_cmd "ETHTEST" 90 {
        set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
        foreach l [harness::screen_lines] { puts $fh "|$l" }
        close $fh
        harness::assert_screen_contains "found"     "Found: 01"
        harness::assert_screen_contains "wait-mode"  "Mode:  01"
        # A completed round trip on that transport, not just the mode byte.
        harness::assert_screen_contains "mac"        "024D53585069"
        harness::assert_screen_contains "netstat"    "Net:   01"
        # Wait mode is per-transaction and must be off again by now: while it
        # is on $57 reads $8E on hardware and $FF under openMSX, and
        # msxpi_bios.asm:97 stops recognising the emulator.
        harness::assert_screen_lacks "no-leaked-waitmode-hw"   "P57:   8E"
        harness::assert_screen_lacks "no-leaked-waitmode-omsx" "P57:   FF"
        harness::done
    }
}
