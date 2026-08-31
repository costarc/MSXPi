harness::init "wsl_ucount"
harness::at_dos_prompt {
    harness::run_cmd "MSR I" 60 {
        harness::run_cmd "ETHUNAPI" 60 {
            harness::run_cmd "UCOUNT" 60 {
                harness::run_cmd "INL I" 90 {
                    harness::run_cmd "UCOUNT" 60 {
                        set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                        foreach l [harness::screen_lines] { puts $fh "|$l" }
                        close $fh
                        harness::pass ran; harness::done
                    }
                }
            }
        }
    }
}
