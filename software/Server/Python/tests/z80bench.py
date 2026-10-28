"""T-states per byte of the LINK2 loops against today's (documents/LINK2-TEST-PLAN.md, T0 and T3).

    python z80bench.py

Runs routines of link2_z80_test.asm in the Z80 interpreter with every port answering at
once, so what is counted is the Z80's own work; the wait for the Pi is the same in both
protocols (and LINK2 does its CRC work inside it).  A burst's INIR/OTIR costs 21 T-states a
byte in either protocol (the CRC pass that follows it is what differs).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import z80_msx  # noqa: E402
import z80emu  # noqa: E402

N = 4096


def machine():
    code, sym = z80_msx.image()
    cpu = z80emu.Z80()
    cpu.mem[0x0100:0x0100 + len(code)] = code
    cpu.io_in = lambda port: 0 if (port & 0xFF) in (0x56,) else (0x5A if (port & 0xFF) == 0x5A else 0xFF)
    cpu.io_out = lambda port, v: None
    return cpu, sym


def t_per_byte(name, **regs):
    cpu, sym = machine()
    cpu.sp = 0xF000
    # CRC state for the routines that use it
    if name.startswith(("LINK_CRC", "LINK_GET")):
        cpu.run_call(sym["L2_CRC_INIT"])
    t, _ = cpu.run_call(sym[name], **regs)
    return t / N


def main():
    rows = [
        ("legacy PRB_SUM (burst checksum pass)", "BENCH_SUM", dict(de=0x8000, bc=N, hl=0)),
        ("legacy PAYLOAD_RX (polled receive, sum)", "PAYLOAD_RX", dict(de=0x8000, bc=N, hl=0)),
        ("legacy PAYLOAD_TX (polled send, sum)", "PAYLOAD_TX", dict(hl=0, de=0x8000, bc=N)),
        ("LINK2 LINK_CRC (burst CRC pass, header, polled send)", "LINK_CRC", dict(hl=0x8000, bc=N)),
        ("LINK2 LINK_GET (polled receive, CRC, STORE)", "LINK_GET", dict(de=0x8000, bc=N)),
        ("LINK2 LINK_PUT (polled send; the CRC is the pass above)", "LINK_PUT", dict(hl=0x8000, bc=N)),
    ]
    for label, name, regs in rows:
        print(f"{t_per_byte(name, **regs):7.1f}  {label}")


if __name__ == "__main__":
    main()
