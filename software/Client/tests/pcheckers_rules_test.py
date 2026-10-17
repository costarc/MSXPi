"""Builds pcheckers_rules_host.c for the Z80 with sdcc and runs it in the sz80
simulator, then compares result[] with the expected rule outcomes (the perft
counts of the Brazilian/Russian opening: 7, 49, 302, 1469)."""
import os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
EXPECTED = [7, 49, 302, 1469, 1, 2, 3, 4, 1, 1, 1, 1, 2, 1, 2, 2]

def main():
    with tempfile.TemporaryDirectory() as tmp:
        src = os.path.join(HERE, "pcheckers_rules_host.c")
        subprocess.run(["sdcc", "-mz80", "--code-loc", "0x200", "--data-loc", "0x8000",
                        "-o", os.path.join(tmp, "t.ihx"), src], check=True, cwd=tmp)
        mp = open(os.path.join(tmp, "t.map")).read()
        addr = int(re.search(r"([0-9A-F]{8})\s+_result\b", mp).group(1), 16)
        cmds = f"run\ndump rom 0x{addr:x} 0x{addr+31:x}\nquit\n"
        out = subprocess.run(["sz80", "t.ihx"],
                             input=cmds, capture_output=True, text=True, cwd=tmp, timeout=600).stdout
        words = []
        for line in out.splitlines():
            m = re.match(r"0x[0-9a-f]{4}((?: [0-9a-f]{2}){8})", line)
            if m:
                bs = [int(x, 16) for x in m.group(1).split()]
                words += bs
        vals = [words[i] | (words[i + 1] << 8) for i in range(0, 32, 2)]
        print("got     ", vals)
        print("expected", EXPECTED)
        return 0 if vals == EXPECTED else 1

sys.exit(main())
