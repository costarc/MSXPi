# =============================================================================
# dos_dir - proves the harness can drive the machine and read what came back.
#
# Types a command at the DOS prompt and asserts on its output.  This is the
# mechanism every later test uses to run a .COM and check its result, so it is
# worth testing on its own with something that cannot fail for its own reasons.
# =============================================================================

harness::init "dos_dir"

harness::at_dos_prompt {
    harness::run_cmd "DIR" 60 {
        harness::assert_screen_contains "dir-ran"        "DIR"
        harness::assert_screen_contains "sees-msxpi-rom" "MSXPIBIO ROM"
        harness::assert_screen_contains "reports-total"  "files"
        harness::assert_screen_lacks    "no-dos-error"   "Bad command"
        harness::done
    }
}
