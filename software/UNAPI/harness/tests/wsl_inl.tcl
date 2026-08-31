# =============================================================================
# wsl_inl - install InterNestor Lite on top of our Ethernet UNAPI.
#
# The first real client of the driver: INL is a TCP/IP stack that calls
# ETH_IN_STATUS and ETH_GET_FRAME from the 50/60 Hz timer interrupt, which is
# the workload the whole ISR-safe transport core was written for.
#
# Expected to be informative either way - INL 2.x wants MSX-DOS 2 compatible
# mapper support routines and this harness boots MSX-DOS 1.8, so a refusal here
# is a real finding about what Phase 6 needs, not a driver bug.
# =============================================================================

harness::init "wsl_inl"

harness::at_dos_prompt {
    harness::run_cmd "MSR I" 60 {
        harness::run_cmd "ETHUNAPI" 60 {
            harness::run_cmd "INL I" 90 {
              harness::run_cmd "INL S" 90 {
                set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                foreach l [harness::screen_lines] { puts $fh "|$l" }
                close $fh
                harness::pass "ran"
                harness::done
              }
            }
        }
    }
}
