"""One fault at every byte position of a LINK2 transfer (test plan T1.2).

Each run: a faulted transfer, then a clean one in the same direction.  Verdicts:
OK (data intact), ABORT (reported, and the clean one still works = both idle),
STUCK (reported but the follow-up failed = ends out of step), CORRUPT, HUNG.
"""
import os, sys, collections
sys.path.insert(0, os.path.dirname(__file__))
import link2_sim as S
import msxpi_const as C
import msxpi_blocks as B
from test_link2 import pattern


def run(direction, data, d, idx, mask, size=8192, has_wait=True):
    """direction 'msx2pi' or 'pi2msx'; fault in wire direction d at index idx."""
    w = S.Wire(timeout=1.0)
    w.flip(d, idx, mask)
    follow = pattern(300, 99)
    if direction == "msx2pi":
        steps = [lambda: B.link_recv(65536), lambda: B.link_recv(65536)]
    else:
        steps = [lambda: B.link_send(data), lambda: B.link_send(follow)]
    srv = S.Server(w, steps).start()
    m = S.Msx(w, size, has_wait)
    first = second = None
    err = None
    try:
        try:
            if direction == "msx2pi":
                m.send(data)
            else:
                first = m.recv()
        except S.MsxAborted as e:
            err = str(e)
        # the clean follow-up (fault already consumed or past)
        try:
            if direction == "msx2pi":
                m.send(follow)
            else:
                second = m.recv()
        except S.MsxAborted as e:
            second = ("fail", str(e))
    except S.Hung as e:
        w.close()
        srv.join(2)
        return "HUNG", str(e)
    srv.join(2)
    w.close()
    if direction == "msx2pi":
        r = srv.results
        got = r[0][1] if r and r[0][0] == C.RC_SUCCESS else None
        got2 = r[1][1] if len(r) > 1 and r[1][0] == C.RC_SUCCESS else None
        if got is not None and got != data:
            return "CORRUPT", ""
        ok2 = got2 == follow
        if err is None and got == data:
            return ("OK" if ok2 else "STUCK"), ""
        return ("ABORT" if ok2 else "STUCK"), err or ""
    else:
        if first is not None and first != data:
            return "CORRUPT", ""
        ok2 = second == follow
        if err is None and first == data:
            return ("OK" if ok2 else "STUCK"), ""
        return ("ABORT" if ok2 else "STUCK"), err or ""


def sweep(direction, data, size=8192, has_wait=True, masks=(0x01,)):
    n = len(data) + 40
    tally = collections.Counter()
    bad = []
    for d in ("p2m", "m2p"):
        for idx in range(n):
            for mask in masks:
                v, info = run(direction, data, d, idx, mask, size, has_wait)
                tally[v] += 1
                if v not in ("OK", "ABORT"):
                    bad.append((d, idx, mask, v, info))
    return tally, bad


if __name__ == "__main__":
    for direction in ("msx2pi", "pi2msx"):
        for n, size in ((512, 8192), (600, 256)):
            t, bad = sweep(direction, pattern(n, n), size)
            print(direction, n, size, dict(t), bad[:6], flush=True)
