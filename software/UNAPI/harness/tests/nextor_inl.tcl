# =============================================================================
# nextor_inl - the DOS2 target, end to end.
#
# Canon V-25, MegaFlashROM SCC+SD in slot 1 running Nextor, MSXPi in slot 2 for
# the network.  This is the configuration the driver is actually deployed in,
# and until now nothing modelled it: the harness only ever ran MSX-DOS 1 with
# the disk served over MSXPi.
#
# Needs HW=nextor and the image from ./mknextorhd.sh, which bakes the host's
# "Boot Nextor" folder into a hard disk.  The tools live in its tcpip
# subdirectory, which AUTOEXEC.BAT does NOT put on the PATH - hence the CD.
#
# No RAMHELPR and no ETHUNAPI: the driver is in the ROM.  No MSR either - Nextor
# already provides the DOS 2 mapper support routines and MSR is built to refuse
# when they are present.
# =============================================================================

harness::init "nextor_inl"

harness::at_nextor_prompt {
    harness::run_cmd "CD TCPIP" 30 {
        harness::run_cmd "ETHTEST" 60 {
            harness::assert_screen_contains "seg-is-rom"   "Seg: FF"
            harness::assert_screen_contains "reset-ok"     "Rst:   ok"
            harness::assert_screen_contains "mac-over-wire" "024D53585069"
            harness::run_cmd "INL I" 90 {
                set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                foreach l [harness::screen_lines] { puts $fh "|$l" }
                close $fh
                harness::assert_screen_contains "install-completed" \
                    "has been ins"
                harness::assert_screen_lacks "no-config-error" \
                    "from a configuration file"
                harness::done
            }
        }
    }
}
