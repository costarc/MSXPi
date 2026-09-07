# =============================================================================
# unapi_install - the RAM installer must refuse when the ROM driver is present.
#
# Once the driver ships in msxpibios.rom there is already an ETHERNET
# implementation registered before anything runs, so ETHUNAPI.COM has to say
# so and stop.  Installing anyway would chain the EXTBIO hook to a second
# implementation of the same API, and the discovery procedure would report two
# where the machine has one.
#
# So this test pins the refusal, not the installation.  ETHUNAPI.COM is still
# built and still works - it is the option for people who cannot reflash - but
# it cannot be exercised on a machine whose ROM already carries the driver,
# which is every machine this harness models.
#
# RAMHELPR is deliberately NOT run first.  The installer checks "is one already
# installed" BEFORE it looks for the RAM helper, so that a user on a flashed
# machine gets the reason that actually applies instead of being sent off to
# install RAMHELPR for a problem they do not have.  Running with no helper
# present is what pins that ordering.
# =============================================================================

harness::init "unapi_install"

harness::at_dos_prompt {
    harness::run_cmd "ETHUNAPI" 60 {
        set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
        foreach l [harness::screen_lines] { puts $fh "|$l" }
        close $fh
        # The screen is 32 columns and the message wraps mid-word, so match a
        # fragment that cannot straddle the wrap.
        harness::assert_screen_contains "already-installed" \
            "ETHERNET UNAPI is"
        harness::assert_screen_lacks "did-not-install" "Transport:"
        # The point of the reordering: this must NOT be what it complains about.
        harness::assert_screen_lacks "not-the-helper" "No UNAPI RAM helper"
        harness::done
    }
}
