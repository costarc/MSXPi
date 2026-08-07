#!/usr/bin/env python3
"""Binary-patches LOADROM.COM v1.97 (by Trunks & Victor, 6016 bytes) to add
MSXPi network-loading, the same way patch_loadrom.py does for v1.0 - see
LDRPATCH197.MAC for the appended routines and full design notes on how
v1.97's internals differ from v1.0 (dual search mechanism collapsing to a
single authoritative pair, dynamic search-result buffer address, no
surviving command-line option scanner).

Usage: python patch_loadrom197.py <src LOADROM.COM v1.97> <appended .bin> <dest .COM> <zmac .lst>

Target addresses are read automatically from the zmac listing's symbol
table, so LDRPATCH197.MAC can be edited and reassembled freely without
having to hand-sync addresses here.
"""
import re
import sys

LOAD_ADDR = 0x100

# (address, expected original 3 bytes, symbol name, new opcode) - addresses
# are LOADROM.COM v1.97's own in-memory addresses (see loadrom197_full.asm
# in the session scratchpad for the disassembly these were confirmed
# against).
PATCHES = [
    # LOADROM's own first BDOS call (opens ROM-SORT.DSC): CALL $13B7 ->
    # CALL netinit (scans the raw command tail for "/N", then falls
    # through to the original call unchanged)
    (0x0676, bytes([0xCD, 0xB7, 0x13]), "netinit", 0xCD),
    # old-style F_SFIRST (C=$11, the authoritative search - see this
    # file's own module docstring): CALL $13B4 -> CALL searchpatch
    (0x079B, bytes([0xCD, 0xB4, 0x13]), "searchpatch", 0xCD),
    # old-style F_SNEXT (C=$12, same search): CALL $13B4 -> CALL searchpatch
    (0x07AF, bytes([0xCD, 0xB4, 0x13]), "searchpatch", 0xCD),
    # F_OPEN (plain-ROM path): CALL $13B4 -> CALL openpatch
    (0x0A7D, bytes([0xCD, 0xB4, 0x13]), "openpatch", 0xCD),
    # block read #1 (plain-ROM path): CALL $13A7 -> CALL readpatch
    (0x0A92, bytes([0xCD, 0xA7, 0x13]), "readpatch", 0xCD),
    # block read #2 (plain-ROM path): CALL $13A7 -> CALL readpatch
    (0x0AA0, bytes([0xCD, 0xA7, 0x13]), "readpatch", 0xCD),
    # F_OPEN (mapped-ROM path's own): CALL $13B4 -> CALL openpatch_mapped
    (0x0E4F, bytes([0xCD, 0xB4, 0x13]), "openpatch_mapped", 0xCD),
    # block read (mapped-ROM path's own loop): CALL $13A7 -> CALL readpatch
    (0x0E83, bytes([0xCD, 0xA7, 0x13]), "readpatch", 0xCD),
    # F_CLOSE (mapped-ROM path's own loop-exit): CALL $13B4 ->
    # CALL closepatch
    (0x0EC7, bytes([0xCD, 0xB4, 0x13]), "closepatch", 0xCD),
]

# Raw text replacements, applied after PATCHES: (expected original bytes,
# new bytes, address - for error messages only). Both are found by content
# rather than a hardcoded offset (the exact position was confirmed via
# disassembly, but searching is more robust to reordering elsewhere in the
# file) and replaced in place, padded with trailing spaces to the exact
# original byte length so nothing downstream shifts.
#   - the help-text banner (0105h) is free-flowing text (CR/LF separated,
#     no column dependency), so padding is just a safety habit here, not a
#     requirement.
#   - the status-line banner (152Dh) is NOT free-flowing: it's one single
#     $-terminated string whose later fields ("<- VDP freq", "-> CPU
#     Speed", "TAB:SCC slot", ...) are positioned purely by how many
#     characters precede them in this same string - same length is
#     mandatory here, not just tidy.
TEXT_PATCHES = [
    (b"LoadROM v1.97 by Trunks & Victor 2015",
     b"loadrom 2.0P by Trunks & Victor 2015"),
    (b"LoadROM.com v1.97 by Trunks & Vic",
     b"loadrom 2.0P by Trunks & Vic"),
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

    ORIGINAL_LEN = 0x1780  # LOADROM.COM v1.97's own real length (6016 bytes)
    if len(data) != ORIGINAL_LEN:
        print(f"WARNING: source is {len(data)} bytes, expected exactly "
              f"{ORIGINAL_LEN} (0x{ORIGINAL_LEN:04X}) - this doesn't look "
              f"like the LOADROM.COM v1.97 this patch was built against. "
              f"Refusing to patch.")
        sys.exit(1)

    # Pad with zeros up to LDRPATCH197.MAC's own org.
    gap_end = symbols["netinit"] - LOAD_ADDR
    if gap_end < len(data):
        print(f"WARNING: LDRPATCH197.MAC's org (0x{symbols['netinit']:04X}) "
              f"is before the original file's own end - refusing to patch.")
        sys.exit(1)
    data.extend(b"\x00" * (gap_end - len(data)))

    for old, new in TEXT_PATCHES:
        if len(new) > len(old):
            print(f"WARNING: replacement text {new!r} is longer than the "
                  f"original {old!r} - refusing to patch.")
            sys.exit(1)
        off = data.find(old)
        if off < 0:
            print(f"WARNING: expected banner text {old!r} not found - "
                  f"refusing to patch (source file may not be the exact "
                  f"6016-byte LOADROM.COM v1.97 this patch was built "
                  f"against).")
            sys.exit(1)
        padded = new + b" " * (len(old) - len(new))
        data[off:off+len(old)] = padded
        print(f"Patched banner at 0x{LOAD_ADDR+off:04X}: {old!r} -> "
              f"{padded!r}")

    for addr, expect, name, opcode in PATCHES:
        target = symbols[name]
        off = addr - LOAD_ADDR
        actual = bytes(data[off:off+3])
        if actual != expect:
            print(f"WARNING: at 0x{addr:04X} (file offset 0x{off:04X}), "
                  f"expected {expect.hex(' ')} but found {actual.hex(' ')} "
                  f"- refusing to patch (source file may not be the exact "
                  f"6016-byte LOADROM.COM v1.97 this patch was built "
                  f"against).")
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
