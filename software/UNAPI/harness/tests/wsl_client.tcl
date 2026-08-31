# =============================================================================
# wsl_client - run a stock Konamiman TCP/IP UNAPI client against the stack.
#
# This is the Phase 6 acceptance test: not our own test program, but software
# written years before this driver existed, reaching it through two layers of
# UNAPI. It also exercises the CALSLT interrupt question from PHASE1_DESIGN 9 -
# a foreground client that fails to re-enable interrupts would stop INL's timer
# ISR and hang.
# =============================================================================

harness::init "wsl_client"

harness::at_dos_prompt {
    harness::run_cmd "MSR I" 60 {
        harness::run_cmd "ETHUNAPI" 60 {
            harness::run_cmd "INL I" 90 {
                harness::run_cmd "TCPCON" 90 {
                    set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                    foreach l [harness::screen_lines] { puts $fh "|$l" }
                    close $fh
                    harness::pass ran; harness::done
                }
            }
        }
    }
}
