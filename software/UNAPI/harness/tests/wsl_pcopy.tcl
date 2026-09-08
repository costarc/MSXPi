# =============================================================================
# wsl_pcopy - round trip a file Pi -> MSX drive B: -> Pi.
#
# Covers both pcopy directions and, in particular, the post-block status
# handshake: the receiver sends READY and the status and the sender answers
# READY_ACK.  recvdata2_oneblock() used to have that backwards, so both ends
# read and every upload died at the last step with RC_HANDSHAKEERR - after the
# payload had already arrived intact.  Nothing sent bulk data from the MSX to
# the Pi before pcopy learned to upload, which is why it went unnoticed.
#
# Both directions in ONE run on purpose: the server mounts its disk images from
# a private staging copy refreshed on every mount, so a file the MSX writes to
# B: does not survive a server restart.
#
# Needs SMALL.TXT in the server's PATH directory.  A small file keeps this
# inside the default 300s TIMEOUT; the same test against a 256 KB ROM takes
# about twenty minutes of emulated time and needs TIMEOUT=2400.  That larger
# run is what proved the transfer byte-exact - sha1 12f6f31f... both ways on
# ALESTE.ROM - and is worth repeating by hand after touching the block
# protocol.
# =============================================================================
harness::init "wsl_pcopy"

harness::at_dos_prompt {
    harness::run_command "PCOPY SMALL.TXT B:" 60 {
        harness::assert_screen_contains "downloaded" "copied successfully"
        harness::run_command "PCOPY B:SMALL.TXT SMALLUP.TXT" 90 {
            set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
            foreach l [harness::screen_lines] { puts $fh "|$l" }
            close $fh
            harness::assert_screen_contains "uploaded" "copied to MSXPi"
            harness::done
        }
    }
}
