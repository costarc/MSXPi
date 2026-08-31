# =============================================================================
# smoke - proves the harness loop itself works end to end.
#
# Boots the machine and waits for the MSX-DOS prompt.  If this fails, nothing
# else in the suite is trustworthy: either openMSX did not start, the MSXPi
# device could not reach the server, or the boot disk is not being served.
# =============================================================================

harness::init "smoke"

harness::at_dos_prompt {
    harness::assert_screen_contains "msxdos-booted" "MSX-DOS version"
    harness::assert_screen_contains "command-loaded" "COMMAND version"
    harness::assert_screen_contains "prompt-present" "A:"
    harness::done
}
