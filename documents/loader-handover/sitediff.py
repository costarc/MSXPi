import sys, glob, os, importlib.util
SRC = r"C:\Users\roniv\Dev\github\MSXPi\software\Server\Python\src\mapper_detect.py"
HEAD = os.path.join(os.path.dirname(__file__), "mapper_detect_head.py")

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

new, old = load("md_new", SRC), load("md_old", HEAD)
db = new.load_romdb(open(r"C:\Users\roniv\Dev\github\openMSX\openMSX\share\softwaredb.xml",
                         encoding="utf-8", errors="ignore").read())
H = [0xA100, 0xA200, 0xA300, 0xA400]
tot_add = tot_rm = 0
for f in sorted(glob.glob(r"C:\Users\roniv\Dev\MSX\gameroms\**\*.rom", recursive=True)
                + glob.glob(r"C:\Users\roniv\Dev\MSX\gameroms\**\*.ROM", recursive=True)):
    rom = open(f, "rb").read()
    if len(rom) < 0x10000:
        continue
    info = new.romdb_lookup(rom, db)
    if info and info[0] in ("plain", "unsupported"):
        continue
    mt = info[1][0] if info else new.detect_mapper(rom)[0]
    if mt not in new.PATCH_WINDOWS:
        continue
    a, na = new.patch_bank_switches(rom, mt, H)
    b, nb = old.patch_bank_switches(rom, mt, H)
    diff = [i for i in range(len(rom)) if a[i] != b[i] and a[i] == 0xCD or (b[i] == 0xCD and a[i] != b[i])]
    sites = sorted({i for i in diff if rom[i] == 0x32})
    added = [i for i in sites if a[i] == 0xCD and b[i] != 0xCD]
    removed = [i for i in sites if b[i] == 0xCD and a[i] != 0xCD]
    tot_add += len(added); tot_rm += len(removed)
    if added or removed:
        print(f"{os.path.basename(f):14} type={mt} old={nb} new={na}")
        for i in added:
            print(f"   + {i:05X} -> {rom[i+1] | rom[i+2] << 8:04X}  ctx {rom[max(0,i-4):i+3].hex(' ')}")
        for i in removed:
            print(f"   - {i:05X} -> {rom[i+1] | rom[i+2] << 8:04X}")
print(f"TOTAL added={tot_add} removed={tot_rm}")
