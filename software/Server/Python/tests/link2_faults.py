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


def run_slip(direction, data, k, size=8192, has_wait=True, tries=3):
    """One MSX transfer, number k, slips (the Pi never sees it).  Then the MSX
    repeats a clean follow-up command up to `tries` times, as a user would, while
    the server keeps serving.  Verdicts: OK, ABORT (first reported, follow-up
    fine at once), RETRIED (the follow-up needed more than one try), STUCK (no
    try worked), CORRUPT (wrong data accepted anywhere), HUNG, CRASH (the server
    raised something other than a wire wait)."""
    w = S.Wire(timeout=1.0)
    w.slip(k)
    follow = pattern(300, 99)
    results = []

    def forever(step):
        # The real server goes back to waiting after every transfer, failed or
        # not, for as long as it runs; a fixed list of steps would run out after
        # a few failed attempts and leave the MSX talking to nobody.
        def loop():
            while True:
                results.append(step())
        return loop

    if direction == "msx2pi":
        steps = [forever(lambda: B.link_recv(65536))]
    else:
        steps = [lambda: results.append(B.link_send(data)),
                 forever(lambda: B.link_send(follow))]
    srv = S.Server(w, steps).start()
    m = S.Msx(w, size, has_wait)
    first_err = None
    got_first = None
    attempts = 0
    follow_ok = False
    try:
        try:
            if direction == "msx2pi":
                m.send(data)
            else:
                got_first = m.recv()
        except S.MsxAborted as e:
            first_err = str(e)
        for attempts in range(1, tries + 1):
            try:
                if direction == "msx2pi":
                    m.send(follow)
                    follow_ok = True  # the server's results confirm it below
                else:
                    got = m.recv()
                    if got != follow:
                        w.close()
                        srv.join(2)
                        return "CORRUPT", "follow-up data"
                    follow_ok = True
                break
            except S.MsxAborted:
                continue
    except S.Hung as e:
        w.close()
        srv.join(2)
        return "HUNG", str(e)
    w.close()
    srv.join(2)
    if srv.error is not None and not isinstance(srv.error, S.Hung):
        return "CRASH", repr(srv.error)
    if direction == "msx2pi":
        accepted = [r[1] for r in results if r and r[0] == C.RC_SUCCESS]
        if any(x not in (data, follow) for x in accepted):
            return "CORRUPT", ""
        follow_ok = follow_ok and follow in accepted
    elif got_first is not None and got_first != data:
        return "CORRUPT", ""
    if not follow_ok:
        return "STUCK", first_err or ""
    if attempts > 1:
        return "RETRIED", first_err or ""
    return ("OK" if first_err is None else "ABORT"), first_err or ""


def sweep_slip(direction, data, size=8192, has_wait=True):
    """A slip at every MSX transfer of the first transfer (and a few beyond)."""
    tally = collections.Counter()
    bad = []
    for k in range(len(data) + 40):
        v, info = run_slip(direction, data, k, size, has_wait)
        tally[v] += 1
        if v in ("CORRUPT", "HUNG", "CRASH", "STUCK"):
            bad.append((k, v, info))
    return tally, bad


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
