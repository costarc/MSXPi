# =============================================================================
# wsl_inl - install InterNestor Lite on top of our Ethernet UNAPI.
#
# The first real client of the driver: INL is a TCP/IP stack that calls
# ETH_IN_STATUS and ETH_GET_FRAME from the 50/60 Hz timer interrupt, which is
# the workload the whole ISR-safe transport core was written for.
#
# This is the test the ROM port exists for.  Against the RAM implementation
# `INL I` HUNG, right after printing "Found MSXPi Ethernet UNAPI" - INL's
# RAM-segment path is code no field implementation exercises.  A ROM
# implementation reports segment $FF, so INL takes the CALSLT path ObsoNET
# uses, and the install completes.
#
# It also covers INL.CFG, which INL reads back through its own command parser
# after installing - one line at a time, as if each were typed at the prompt.
# That file has to have CRLF line endings; with LF only, INL never finds a line
# boundary, prints "Cannot execute this command from a configuration file", and
# then loops printing its banner for ever.  It looks exactly like a hang in
# whatever UNAPI driver is underneath, which is why it is pinned here.
#
# ETHUNAPI is deliberately NOT run first: the driver is in the ROM, and the
# installer would only refuse.  MSR still is - INL needs mapper support
# routines for its own buffers under MSX-DOS 1, whoever supplies the UNAPI.
#
# `INL S` is run for the record but not asserted.  It still reports "not
# installed" here, and that is a separate defect the ROM path did NOT fix.  It
# is not the mapper-in-another-slot theory either: it reproduces on
# MACHINE=Philips_NMS_8245 HW=msxpi128, where mapper and page-1 RAM share a
# slot.  UCOUNT proves the TCP/IP UNAPI registers, so INL works and only its
# own status command is confused.  See PHASE1_DESIGN.md.
# =============================================================================

harness::init "wsl_inl"

harness::at_dos_prompt {
    harness::run_cmd "MSR I" 60 {
        harness::run_cmd "INL I" 90 {
            harness::run_cmd "INL S" 90 {
                set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                foreach l [harness::screen_lines] { puts $fh "|$l" }
                close $fh
                # Not asserting on the "Found MSXPi Ethernet UNAPI" line: with
                # INL.CFG present INL echoes one line per config entry after
                # it, which scrolls that message off the 24-row screen.
                # unapi_discovery covers discovery; this test is about the
                # install COMPLETING.
                harness::assert_screen_contains "install-completed" \
                    "has been ins"
                # Every INL.CFG line must be accepted.  "has been installed"
                # on its own would not catch a config file that was silently
                # skipped, which is the failure this test exists to prevent.
                harness::assert_screen_contains "config-applied" \
                    "has been modified"
                harness::assert_screen_lacks "no-unapi-error" \
                    "No Ethernet UNAPI"
                harness::assert_screen_lacks "no-config-error" \
                    "from a configuration file"
                harness::done
            }
        }
    }
}
