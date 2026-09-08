# wsl_pcopy - round trip Pi -> MSX B: -> Pi, and the drive-prefix default.
#
# The second upload omits the target on purpose: the Pi has no drive letters,
# and "pcopy B:SMALL.TXT" used to ask it to create a file literally named
# "B:SMALL.TXT".
harness::init "wsl_pcopy"

harness::at_dos_prompt {
    harness::run_command "PCOPY SMALL.TXT B:" 60 {
        harness::assert_screen_contains "downloaded" "copied successfully"
        harness::run_command "PCOPY B:SMALL.TXT" 90 {
            set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
            foreach l [harness::screen_lines] { puts $fh "|$l" }
            close $fh
            harness::assert_screen_contains "uploaded" "copied to MSXPi"
            harness::assert_screen_lacks "no-drive-in-name" "Pi:B:"
            harness::done
        }
    }
}
