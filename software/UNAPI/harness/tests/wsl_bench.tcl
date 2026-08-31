# =============================================================================
# wsl_bench - sanity-check ETHBENCH before it is run on real hardware.
#
# In emulation the polled pass is FORCED to MODE_POLL_HW, which is the wrong
# backend for openMSX (it needs MODE_POLL_OMSX), so that pass must report
# ok=0000 and be discarded.  That is the point: it demonstrates the OK-count
# guard catching a pass whose timing is meaningless.  The /WAIT pass must
# report ok=0800.
# =============================================================================

harness::init "wsl_bench"

harness::at_dos_prompt {
    harness::run_cmd "RAMHELPR I" 60 {
        harness::run_cmd "ETHUNAPI" 60 {
            harness::run_cmd "ETHBENCH" 300 {
                set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                foreach l [harness::screen_lines] { puts $fh "|$l" }
                close $fh
                harness::assert_screen_contains "ran-all" "poll-om:"
                harness::assert_screen_contains "wait-pass-valid" "ok=0800"
                harness::done
            }
        }
    }
}
