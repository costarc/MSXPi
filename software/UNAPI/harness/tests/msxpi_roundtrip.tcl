# =============================================================================
# msxpi_roundtrip - proves the MSX <-> server transport works.
#
# This is the path the whole UNAPI driver is built on: a command goes out over
# ports $56/$57/$5A, the server answers with a checksummed block, and the MSX
# accepts it.  The assertions that matter are on the SERVER side (see
# msxpi_roundtrip.expect) - P VER scrolls its output away, so checking the
# screen alone would pass even if nothing had been transferred.
# =============================================================================

harness::init "msxpi_roundtrip"

harness::at_dos_prompt {
    harness::run_cmd "P VER" 60 {
        # The command must at least have returned to a prompt rather than hung
        # or dropped into an error.
        harness::assert_screen_contains "returned-to-prompt" "A:"
        harness::assert_screen_lacks    "no-comms-error"     "Communication Error"
        harness::done
    }
}
