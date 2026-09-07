# =============================================================================
# dos_dir - proves the harness can drive the machine and read what came back.
#
# Types a command at the DOS prompt and asserts on its output.  This is the
# mechanism every later test uses to run a .COM and check its result, so it is
# worth testing on its own with something that cannot fail for its own reasons.
# =============================================================================

harness::init "dos_dir"

harness::at_dos_prompt {
    # DIR of one named file, not the whole disk.  A bare DIR used to work,
    # but the served image has grown past a screenful and MSXPIBIO.ROM - one
    # of the first entries - now scrolls off the top of the 24-row display
    # before the command finishes.  Naming the file tests the same thing and
    # cannot scroll.
    harness::run_cmd "DIR MSXPIBIO.ROM" 60 {
        harness::assert_screen_contains "sees-msxpi-rom" "MSXPIBIO ROM"
        harness::assert_screen_contains "reports-total"  "bytes free"
        harness::assert_screen_lacks    "no-dos-error"   "Bad command"
        harness::done
    }
}
