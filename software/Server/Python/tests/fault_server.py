r"""msxpi-server.py with link-byte corruption, for fault-injection tests.

Wraps msxpi_transport.tcp_exchange - every byte of the openMSX virtual-SPI
link goes through it, in both directions - and flips one random bit of a byte
with probability FAULT_RATE. Pi->MSX bytes are corrupted before they are
offered (the MSX reads a bad byte), MSX->Pi bytes after they arrive (the
server reads a bad byte); the sender's own copy is untouched, as with line
noise. Every injected fault is logged as "FAULT #n ..." with its direction
and byte position.

    FAULT_RATE=0.0005 FAULT_SEED=1 [FAULT_SKIP=bytes] [FAULT_DIR=rx|tx|both]
    [FAULT_SERVER_RETRIES=n] [FAULT_SRC=dir of another msxpi-server.py]
    python -u fault_server.py        (from any directory; same env as the server)

Test-only: nothing in the server imports this.
"""
import os
import random
import runpy
import sys
from pathlib import Path

# FAULT_SRC: another copy of the server sources (e.g. the released version)
SRC = Path(os.environ.get('FAULT_SRC') or Path(__file__).resolve().parents[1] / 'src')
sys.path.insert(0, str(SRC))
os.chdir(SRC)

import msxpi_transport  # noqa: E402

RATE = float(os.environ.get('FAULT_RATE', '0'))
SKIP = int(os.environ.get('FAULT_SKIP', '0'))
DIRS = os.environ.get('FAULT_DIR', 'both')
rng = random.Random(int(os.environ.get('FAULT_SEED', '1')))
state = {'bytes': 0, 'faults': 0}
_exchange = msxpi_transport.tcp_exchange


def _maybe(direction, value):
    state['bytes'] += 1
    if state['bytes'] <= SKIP or DIRS not in ('both', direction) or rng.random() >= RATE:
        return value
    bad = value ^ (1 << rng.randrange(8))
    state['faults'] += 1
    print(f"FAULT #{state['faults']} {direction} byte {state['bytes']}: "
          f"{value:#04x} -> {bad:#04x}", flush=True)
    return bad


def faulty_exchange(misos, timeout, hold=True):
    if len(misos) >= 64:
        print(f"BURST {len(misos)}", flush=True)  # one READY-held run (the harness counts them)
    misos = [_maybe('tx', b & 0xFF) for b in misos]
    rc, got = _exchange(misos, timeout, hold)
    if got is not None:
        got = bytearray(_maybe('rx', b) for b in got)
    return rc, got


msxpi_transport.tcp_exchange = faulty_exchange
if os.environ.get('FAULT_SERVER_RETRIES'):
    # the server's per-block retry limit, to pair it with a ROM built with
    # another GLOBALRETRIES (old server + new ROM and the reverse)
    import msxpi_blocks
    msxpi_blocks.MAX_BLOCK_RETRIES = int(os.environ['FAULT_SERVER_RETRIES'])
    print(f'fault_server: MAX_BLOCK_RETRIES={msxpi_blocks.MAX_BLOCK_RETRIES}', flush=True)
print(f'fault_server: rate={RATE} skip={SKIP} dir={DIRS} seed={os.environ.get("FAULT_SEED", "1")}', flush=True)
sys.argv = [str(SRC / 'msxpi-server.py')]
runpy.run_path(str(SRC / 'msxpi-server.py'), run_name='__main__')
