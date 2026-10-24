#!/usr/bin/env python3
r"""Byte-compare C client builds at a base commit and in the working tree.

Used by the SDCC 4.6 port (documents/SDCC46-PORT-HANDOVER.md) for the stages that must
leave today's binaries unchanged: build each program with the same make.bat in both trees,
then compare the .com and the .map.

    python software/tools/abi_bytecmp.py [--base REV] [--keep] prog [prog...]

Builds go to scratch directories (MAKE_OUTDIR), never to target\ or the shared FloppyA.
The base commit is checked out as a git worktree next to this one (make.bat reaches the
fusion-c tree with ..\..\..\, so the depth must match). The working tree's make.bat is
copied over the base's, with ABI1_PROGRAMS emptied, so both sides use the same flags and
only the sources differ. SDCC_ALLOW_ABI_MIX=1 is set: these builds are the old,
mixed-convention ones.
Windows only (make.bat).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SOFTWARE = Path(__file__).resolve().parent.parent
REPO = SOFTWARE.parent


def run(cmd, cwd, env=None, check=True):
    return subprocess.run(cmd, cwd=cwd, env=env, check=check, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def build(software, prog, outdir, env_extra):
    env = dict(os.environ, MAKE_OUTDIR=str(outdir), KEEPMAP="1", SDCC_ALLOW_ABI_MIX="1", **env_extra)
    r = run(["cmd", "/c", r".\make.bat", prog], software, env, check=False)
    com = outdir / f"{prog}.com"
    if not com.exists():
        sys.exit(f"{prog}: build failed in {software}\n{r.stdout[-3000:]}")
    return com, outdir / f"{prog}.map"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("programs", nargs="+")
    ap.add_argument("--base", default="e59728e0", help="commit to compare against")
    ap.add_argument("--keep", action="store_true", help="keep the base worktree and outputs")
    a = ap.parse_args()

    base_wt = REPO.parent / "_abicmp_base"
    if base_wt.exists():
        sys.exit(f"{base_wt} exists; remove it (git worktree remove --force) first")
    scratch = Path(tempfile.mkdtemp(prefix="abicmp_"))
    run(["git", "worktree", "add", "--detach", str(base_wt), a.base], REPO)
    try:
        mk = (SOFTWARE / "make.bat").read_text()
        mk = re.sub(r"(?im)^SET ABI1_PROGRAMS=.*$", "SET ABI1_PROGRAMS=", mk)
        (base_wt / "software" / "make.bat").write_text(mk)
        # The working tree side must also be built with the old flags.
        wmk_path = SOFTWARE / "make.bat"
        wmk = wmk_path.read_text()
        same = []
        for prog in a.programs:
            bo, wo = scratch / "base", scratch / "work"
            bo.mkdir(exist_ok=True)
            wo.mkdir(exist_ok=True)
            bc, bm = build(base_wt / "software", prog, bo, {})
            if re.search(r"(?im)^SET ABI1_PROGRAMS=.*\b%s\b" % re.escape(prog), wmk):
                sys.exit(f"{prog} is in ABI1_PROGRAMS: not comparable with a mixed-convention base")
            wc, wm = build(SOFTWARE, prog, wo, {})
            com_ok = bc.read_bytes() == wc.read_bytes()
            map_ok = bm.read_bytes() == wm.read_bytes() if bm.exists() and wm.exists() else None
            print(f"{prog}: .com {'IDENTICAL' if com_ok else 'DIFFERENT'} "
                  f"({bc.stat().st_size} vs {wc.stat().st_size} bytes), "
                  f".map {'identical' if map_ok else 'different' if map_ok is False else 'n/a'}")
            same.append(com_ok)
        sys.exit(0 if all(same) else 1)
    finally:
        if a.keep:
            print(f"kept: {base_wt}, {scratch}")
        else:
            run(["git", "worktree", "remove", "--force", str(base_wt)], REPO, check=False)
            shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()
