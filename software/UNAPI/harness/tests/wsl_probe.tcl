harness::init "wsl_probe"
after time 30 {
    set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
    foreach l [harness::screen_lines] { puts $fh "|$l" }
    close $fh
    harness::pass p; harness::done
}
