# =============================================================================
# wsl_waitmode - proves the hardware /WAIT transport is selected.
#
# Only meaningful against an openMSX built from Dev/github/openMSX/openMSX with
# the MSXPiDevice wait-mode support, i.e. /opt/openMSX in WSL.  The stock
# Windows binary reports $FE on port $57, so the driver correctly falls back to
# the polled backend and this test would fail for the right reason.
#
# The install banner is the assertion: ETHUNAPI probes by writing $01 to $57 and
# requiring an exact $8E read-back, so "hardware /WAIT" can only be printed if
# the device really implemented the mode register.
# =============================================================================

harness::init "wsl_waitmode"

harness::at_dos_prompt {
    harness::run_cmd "RAMHELPR I" 60 {
        harness::run_cmd "ETHUNAPI" 60 {
            set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
            foreach l [harness::screen_lines] { puts $fh "|$l" }
            close $fh
            harness::assert_screen_contains "installed"  "Installed."
            harness::assert_screen_contains "wait-mode"  "hardware /WAIT"
            harness::assert_screen_lacks    "not-polled" "Transport: polled"
            harness::done
        }
    }
}
