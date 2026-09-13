#!/usr/bin/env python3
"""A closed TCP connection must end a READY wait, not spin it.

When openMSX exits, recv() on its socket returns b'' immediately and forever,
so SPI_ByteTransfer() answers RC_CONNERR on every call.  The READY-wait loops
treated every non-success as "keep waiting", which turned one closed socket
into a full-speed loop printing "connection closed by peer" and never let the
accept loop reconnect.  These tests pin both halves of the fix: RC_CONNERR
returns at once, and a timeout (RC_FAILED) still means keep waiting - on the
Pi's GPIO link and for an idle MSX, waiting is the right answer.

No server startup: the functions are lifted out of msxpi-server.py with ast
and run against a scripted SPI_ByteTransfer.
"""
import ast
import unittest
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / 'Server/Python/src/msxpi-server.py'
TREE = ast.parse(SRC.read_text(encoding='utf-8-sig'))

# Every top-level function that waits for READY, found by shape rather than by
# name, so a sixth loop added later is covered without editing this list.
def _waits_for_ready(fn):
    return any(isinstance(n, ast.While) and 'READY' in ast.unparse(n)
               and 'SPI_ByteTransfer' in ast.unparse(n) for n in ast.walk(fn))

FUNCS = [n for n in TREE.body if isinstance(n, ast.FunctionDef) and _waits_for_ready(n)]
CONSTS = [n for n in TREE.body if isinstance(n, ast.Assign)
          and all(isinstance(t, ast.Name) and t.id.isupper() for t in n.targets)
          and isinstance(n.value, ast.Constant)]
CODE = compile(ast.Module(body=CONSTS + FUNCS, type_ignores=[]), 'server', 'exec')

# How each one is called, and what it should hand back on a dead connection.
CALLS = {
    'recvdata2':          lambda f: f(),
    'recvdata2_oneblock': lambda f: f(8192),
    # never spun - it already returns on any error - but it waits for READY too
    'pcopy_handshake':    lambda f: f(),
    'senddata':           lambda f: f(0, b'x'),
    'PerformHandshake':   lambda f: f(),
}


class Link:
    """SPI_ByteTransfer stand-in playing a fixed script of receive results."""
    def __init__(self, script, then):
        self.script, self.then, self.calls = list(script), then, 0

    def __call__(self, byte_out=None):
        self.calls += 1
        if self.calls > 1000:
            raise AssertionError('READY wait is spinning')
        if byte_out is not None:
            return self.ns['RC_SUCCESS'], None
        return self.script.pop(0) if self.script else self.then


def run(name, link):
    ns = {'print': lambda *a, **k: None, 'eth_handle_opcode': lambda b: False}
    exec(CODE, ns)
    link.ns = ns
    ns['SPI_ByteTransfer'] = link
    return ns, CALLS[name](ns[name])


class ConnErrSpin(unittest.TestCase):
    def test_all_ready_waits_are_covered(self):
        self.assertEqual(sorted(f.name for f in FUNCS), sorted(CALLS),
                         'a READY-wait loop was added or renamed - add it to CALLS')

    def test_closed_peer_returns_immediately(self):
        for name in CALLS:
            with self.subTest(name):
                ns = {}; exec(CODE, ns)
                link = Link([], (ns['RC_CONNERR'], None))
                _, result = run(name, link)
                rc = result[0] if isinstance(result, tuple) else result
                self.assertNotEqual(rc, ns['RC_SUCCESS'])
                self.assertEqual(link.calls, 1, f'{name} read {link.calls} times')

    def test_timeout_still_waits_for_ready(self):
        # pcopy_handshake has always returned on its first failed read; that is
        # its own policy and not what this fix is about, so it is only held to
        # the closed-peer test above.
        for name in (n for n in CALLS if n != 'pcopy_handshake'):
            with self.subTest(name):
                ns = {}; exec(CODE, ns)
                failed = (ns['RC_FAILED'], None)
                # three timeouts, then READY, then the connection drops
                link = Link([failed] * 3 + [(ns['RC_SUCCESS'], ns['READY'])],
                            (ns['RC_CONNERR'], None))
                run(name, link)
                self.assertGreater(link.calls, 4, f'{name} gave up on a timeout')


if __name__ == '__main__':
    unittest.main()
