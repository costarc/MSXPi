# wsl_pcopy - download a file LARGE enough that the receive buffer crosses
# #4000 into page 1, which is where the driver banks its own ROM while DSKIO
# runs.  At 8 KB blocks the buffer stops just short of that boundary and the
# page-1 send path is never used; at 16 KB it is.  Reported on hardware as
# "Invalid drive writing drive B:" followed by a lost link.
harness::init "wsl_pcopy"

harness::at_dos_prompt {
    harness::run_command "PCOPY B64K.BIN B:" 900 {
        set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
        foreach l [harness::screen_lines] { puts $fh "|$l" }
        close $fh
        harness::assert_screen_contains "copied" "copied successfully"
        harness::done
    }
}
