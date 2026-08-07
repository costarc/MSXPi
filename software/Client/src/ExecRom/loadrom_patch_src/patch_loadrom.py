#!/usr/bin/env python3
"""Binary-patches LOADROM.COM (third-party, no source available) to add
MSXPi network-loading for plain (<=32KB) ROMs via a new "/N" option,
leaving disk-mode behavior (and all MegaROM mapper/relocation logic)
byte-for-byte identical to the original. See LDRPATCH.MAC for the
appended routines and full design notes.

Usage: python patch_loadrom.py <src LOADROM.COM> <appended .bin> <dest .COM> <zmac .lst>

Target addresses (optpatch/openpatch/readpatch) are read automatically
from the zmac listing's symbol table, so LDRPATCH.MAC can be edited and
reassembled freely without having to hand-sync addresses here.
"""
import re
import sys

LOAD_ADDR = 0x100

# (address, expected original 3 bytes, symbol name, new opcode) - addresses
# are the original LOADROM.COM's own in-memory addresses (see
# loadrom_full.asm); symbol name is resolved against the .lst file.
PATCHES = [
    # option-scanner tail: INC HL / INC HL / <1st byte of LD ($0815),HL>
    # -> JP optpatch
    (0x062B, bytes([0x23, 0x23, 0x22]), "optpatch", 0xC3),
    # F_OPEN (plain-ROM path only): CALL $115A -> CALL openpatch
    (0x09FD, bytes([0xCD, 0x5A, 0x11]), "openpatch", 0xCD),
    # block read #1: CALL $114D -> CALL readpatch
    (0x0A12, bytes([0xCD, 0x4D, 0x11]), "readpatch", 0xCD),
    # block read #2: CALL $114D -> CALL readpatch
    (0x0A20, bytes([0xCD, 0x4D, 0x11]), "readpatch", 0xCD),
    # F_SFIRST (plain-ROM path's own preliminary local search): CALL
    # $115A -> CALL searchpatch
    (0x0754, bytes([0xCD, 0x5A, 0x11]), "searchpatch", 0xCD),
    # F_SNEXT (same search loop): CALL $115A -> CALL searchpatch
    (0x0768, bytes([0xCD, 0x5A, 0x11]), "searchpatch", 0xCD),
]


def load_symbols(lst_path):
    symbols = {}
    pat = re.compile(r"^(\w+)\s+([0-9a-fA-F]+)\s*$")
    for line in open(lst_path, encoding="utf-8", errors="replace"):
        m = pat.match(line)
        if m:
            symbols[m.group(1)] = int(m.group(2), 16)
    return symbols


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)

    src_path, appended_path, dest_path, lst_path = sys.argv[1:5]

    symbols = load_symbols(lst_path)
    for _, _, name, _ in PATCHES:
        if name not in symbols:
            print(f"WARNING: symbol '{name}' not found in {lst_path} - "
                  f"refusing to patch.")
            sys.exit(1)

    data = bytearray(open(src_path, "rb").read())
    appended = open(appended_path, "rb").read()

    ORIGINAL_LEN = 0x139F  # LOADROM.COM's own real length (5023 bytes)
    if len(data) != ORIGINAL_LEN:
        print(f"WARNING: source is {len(data)} bytes, expected exactly "
              f"{ORIGINAL_LEN} (0x{ORIGINAL_LEN:04X}) - this doesn't look "
              f"like the LOADROM.COM this patch was built against. "
              f"Refusing to patch.")
        sys.exit(1)

    # Pad with zeros up to LDRPATCH.MAC's own org - matches the original
    # file's own tail (a run of zero bytes, likely a runtime scratch
    # buffer - see LDRPATCH.MAC's org comment) rather than introducing a
    # different fill pattern at the boundary.
    gap_end = symbols["optpatch"] - LOAD_ADDR
    if gap_end < len(data):
        print(f"WARNING: LDRPATCH.MAC's org (0x{symbols['optpatch']:04X}) "
              f"is before the original file's own end - refusing to patch.")
        sys.exit(1)
    data.extend(b"\x00" * (gap_end - len(data)))

    for addr, expect, name, opcode in PATCHES:
        target = symbols[name]
        off = addr - LOAD_ADDR
        actual = bytes(data[off:off+3])
        if actual != expect:
            print(f"WARNING: at 0x{addr:04X} (file offset 0x{off:04X}), "
                  f"expected {expect.hex(' ')} but found {actual.hex(' ')} "
                  f"- refusing to patch (source file may not be the exact "
                  f"5023-byte LOADROM.COM this patch was built against).")
            sys.exit(1)
        lo = target & 0xFF
        hi = (target >> 8) & 0xFF
        data[off]   = opcode
        data[off+1] = lo
        data[off+2] = hi
        print(f"Patched 0x{addr:04X}: {actual.hex(' ')} -> "
              f"{data[off]:02X} {data[off+1]:02X} {data[off+2]:02X} "
              f"({name}=0x{target:04X})")

    result = bytes(data) + appended
    open(dest_path, "wb").write(result)
    print(f"Wrote {dest_path}: {len(result)} bytes "
          f"({len(data)} original + {len(appended)} appended)")


if __name__ == "__main__":
    main()
