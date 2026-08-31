# =============================================================================
# wsl_ethops - first real traffic on the $C0-$CF opcode protocol.
#
# ETHTEST calls ETH_GET_HWADD, ETH_GET_NETSTAT and ETH_IN_STATUS, all of which
# cross the wire to msxpi_eth.py.  Passing means the MSX driver and the Python
# shuttle agree on the framing, and that the transport core works in hardware
# /WAIT mode with INIR/OTIR.
#
# The MAC is msxpi_eth.BaseLink's default 02:4D:53:58:50:69 ("MSXPi", locally
# administered).  Net=01 because MockLink reports the link up.  P57 must read
# back 8E/FE-free - see the assertion comment below.
# =============================================================================

harness::init "wsl_ethops"

harness::at_dos_prompt {
    harness::run_cmd "RAMHELPR I" 60 {
        harness::run_cmd "ETHUNAPI" 60 {
            harness::run_cmd "ETHTEST" 90 {
                set fh [open "$::env(MSXPI_HARNESS_OUT).screen" w]
                foreach l [harness::screen_lines] { puts $fh "|$l" }
                close $fh
                harness::assert_screen_contains "found"    "Found: 01"
                harness::assert_screen_contains "mac"      "024D53585069"
                harness::assert_screen_contains "netstat"  "Net:   01"
                harness::assert_screen_contains "instatus" "InSt:  00"
                # Wait mode must NOT still be on when the driver returns: while
                # it is, $57 reads 8E and msxpi_bios.asm:97 would stop
                # recognising openMSX, breaking all other MSXPi software.
                # Both values that mean "wait mode is still on": $8E on real
                # hardware, $FF on openMSX.
                harness::assert_screen_lacks "no-leaked-waitmode-hw"   "P57:   8E"
                harness::assert_screen_lacks "no-leaked-waitmode-omsx" "P57:   FF"
                harness::done
            }
        }
    }
}
