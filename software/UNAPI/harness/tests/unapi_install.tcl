# =============================================================================
# unapi_install - install the RAM helper, then ETHUNAPI.COM, and confirm the
# UNAPI discovery procedure can find the implementation afterwards.
# =============================================================================

harness::init "unapi_install"

harness::at_dos_prompt {
    harness::run_cmd "RAMHELPR I" 60 {
        harness::run_cmd "ETHUNAPI" 60 {
            set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
            foreach l [harness::screen_lines] { puts $fh "|$l" }
            close $fh
            harness::assert_screen_contains "installed"   "Installed."
            harness::assert_screen_contains "transport"   "Transport:"
            harness::assert_screen_lacks    "no-helper-err" "No UNAPI RAM helper"
            harness::assert_screen_lacks    "no-alloc-err"  "Could not allocate"
            harness::done
        }
    }
}
