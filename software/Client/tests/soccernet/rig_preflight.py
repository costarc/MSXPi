"""Rig preflight: does openMSX load this branch's msxpibios.rom?

The rig loads msxpibios.rom from <Documents>/openMSX/share/systemroms/extensions/ (MSXPi.xml names it), which is whatever any
session installed last. A ROM and a server that disagree on the Ethernet protocol leave INL with no network.

  python rig_preflight.py        exit 0: the installed ROM is the branch's; 1: it is not (the install command is printed)
  ALLOW_ROM=1                    only report (sha1 and protocol byte), never fail

The Ethernet protocol byte is the operand of the `cp ETH_PROTO` that follows the probe's `cp "H"` (ethops.asm).
"""
import hashlib, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
# openMSX loads the whole 32 KB EEPROM image, target/msxpi32k.rom, under the name msxpibios.rom (MSXPi.xml; build)
BRANCH_ROM = os.path.join(ROOT, "software", "target", "msxpi32k.rom")
INSTALLED = os.environ.get("MSXPI_INSTALLED_ROM") or os.path.join(
    os.path.expanduser("~"), "Documents", "openMSX", "share", "systemroms", "extensions", "msxpibios.rom")
ETH_PY = os.path.join(ROOT, "software", "Server", "Python", "src", "msxpi_eth.py")


def sha1(path):
    with open(path, "rb") as f:
        return hashlib.sha1(f.read()).hexdigest()


def rom_proto(path):
    with open(path, "rb") as f:
        d = f.read()
    m = re.search(rb"\xfe\x48\x20.\xdd\x7e.\xfe(.)\xc8", d, re.S)   # cp "H" / jr nz / ld a,(ix+n) / cp PROTO / ret z
    return m.group(1)[0] if m else None


def server_proto():
    with open(ETH_PY) as f:
        return int(re.search(r"^PROTO_VERSION\s*=\s*(\d+)", f.read(), re.M).group(1))


def main():
    problems = []
    for p in (BRANCH_ROM, INSTALLED):
        if not os.path.isfile(p):
            problems.append("missing: %s" % p)
    if problems:
        print("rig preflight: " + "; ".join(problems))
        return 0 if os.environ.get("ALLOW_ROM") else 1
    b, i = sha1(BRANCH_ROM), sha1(INSTALLED)
    pb, pi, ps = rom_proto(BRANCH_ROM), rom_proto(INSTALLED), server_proto()
    print("rig preflight: installed ROM sha1 %s (Ethernet protocol %s); branch ROM sha1 %s (%s); server PROTO_VERSION %s"
          % (i[:8], pi, b[:8], pb, ps))
    if pi != ps:
        problems.append("the installed ROM speaks Ethernet protocol %s, the server %s: INL gets no network" % (pi, ps))
    if i != b:
        problems.append("the installed ROM is not this branch's software/target/msxpi32k.rom")
    if not problems:
        return 0
    for p in problems:
        print("rig preflight: " + p)
    print('rig preflight: install the branch ROM with:  cp "%s" "%s"' % (BRANCH_ROM, INSTALLED))
    print("rig preflight: (ALLOW_ROM=1 runs anyway; the other sessions' rigs read the same file, so check they are idle)")
    return 0 if os.environ.get("ALLOW_ROM") else 1


if __name__ == "__main__":
    sys.exit(main())
