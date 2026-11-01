"""Watch a live F1 Spirit netplay game inside a running openMSX (no control socket needed): ReadProcessMemory.

    python f1spirit_live_watch.py <stub.bin> <stub.sym> <PLAYNET.OVL> <log> [port]

stub.bin is profiles/f1spirit/assets/stub.bin and stub.sym its symbols (in profiles/f1spirit/src:
sjasmplus --raw=NUL --sym=stub.sym glue.asm). The openMSX is the one with "msxpiserver_port <port>" (default 5000)
in its command line. The stub is found by its code in the 4 MB + 4 KB RAM regions; openMSX keeps stale copies
(reverse snapshots, an ended game), so the copy whose counters move is followed, and found again when it moves.
One heartbeat line a second, a line on each change of the inputs, and a dump of the counters, the bank tables and
both input rings when the frame counter has stood still for 2 s. On the MSXPi link there is no overlay (netcore=None).
"""
import ctypes, ctypes.wintypes as w, re, subprocess, sys, time

k = ctypes.WinDLL("kernel32", use_last_error=True)
port = sys.argv[5] if len(sys.argv) > 5 else '5000'
pid = int(subprocess.check_output(['powershell', '-NoProfile', '-c',
    "(Get-CimInstance Win32_Process -Filter \"name='openmsx.exe'\" | ? { $_.CommandLine -like '*msxpiserver_port %s*' } "
    "| select -First 1).ProcessId" % port]).split()[0])
h = k.OpenProcess(0x0410, False, pid)
S = {m[0]: int(m[1], 16) for m in re.findall(r'^(\w+):\s+EQU\s+0x([0-9A-Fa-f]+)', open(sys.argv[2]).read(), re.M)}
ORG = 0xD200                                           # the stub's load address (profile: STUB_LOAD)
class MBI(ctypes.Structure):
    _fields_ = [("Base", ctypes.c_void_p), ("AllocBase", ctypes.c_void_p), ("AllocProt", w.DWORD), ("pad", w.DWORD),
                ("Size", ctypes.c_size_t), ("State", w.DWORD), ("Prot", w.DWORD), ("Type", w.DWORD), ("pad2", w.DWORD)]
def rd(a, n):
    b = ctypes.create_string_buffer(n); m = ctypes.c_size_t()
    k.ReadProcessMemory(h, ctypes.c_void_p(a), b, n, ctypes.byref(m)); return b.raw[:m.value]
def regions():
    a = 0; m = MBI(); out = []
    while k.VirtualQueryEx(h, ctypes.c_void_p(a), ctypes.byref(m), ctypes.sizeof(m)):
        b = m.Base or 0
        if m.State == 0x1000 and m.Prot == 4 and m.Size == 0x401000: out.append(b)
        a = b + m.Size
    return out
SIG = open(sys.argv[1], 'rb').read()[0x240:0x260]
OVL = open(sys.argv[3], 'rb').read()[0x40:0x80]
def counters(reg, seg):
    d = rd(reg + seg + S['nf'] - 0xC000, 4)
    return d if len(d) == 4 else None
def find():
    """(region, segment offset, overlay offset or None) of a started stub, the live copy first"""
    cands = []
    for b in regions():
        d = rd(b, 0x401000); i = d.find(SIG)
        while i >= 0:
            base = i - 0x240; seg = base - (ORG - 0xC000)
            if (seg - 0x40) % 0x4000 == 0 and d[base + S['started'] - ORG] == 1:
                j = d.find(OVL)
                if j < 0: cands.append((b, seg, None))
                elif d[j - 0x40 + 0x169A] == 3: cands.append((b, seg, j - 0x40))
            i = d.find(SIG, i + 1)
    if not cands: return None
    before = [counters(b, s) for b, s, _ in cands]
    time.sleep(0.3)
    for c, v in zip(cands, before):
        if counters(c[0], c[1]) != v: return c
    return cands[0]
log = open(sys.argv[4], 'a', buffering=1)
def P(*a):
    s = time.strftime('%H:%M:%S ') + ' '.join(str(x) for x in a); print(s); log.write(s + '\n')
B = S['MK_BLOCK']; NB = S['mkTab1'] - B + 4 * 34       # the bank block with both tables (MK_P1_MAX + MK_P2_MAX = 34)
P('waiting for a READY game, openmsx pid', pid)
while True:
    while True:
        f = find()
        if f: break
        time.sleep(1)
    reg, seg, ovl = f
    P('attached: segment', hex(reg + seg), 'overlay', ovl)
    last = None; hb = 0; lastnf = -1; still = time.time(); dumped = False
    while True:
        d = rd(reg, 0x401000)
        if not d: P('region gone, re-finding'); break
        g = lambda a, n=1: d[seg + a - 0xC000:seg + a - 0xC000 + n]
        nf = g(S['nf'])[0]; stall = g(S['stallCnt'])[0]; des = g(S['desync'])[0]; desF = g(S['desyncF'])[0]
        started = g(S['started'])[0]; rx = g(S['rxSeen'])[0]
        own = g(S['ownVal'], 48); rem = g(S['remRing'], 64)
        ownpad = ownfk = rempad = remfk = 0
        for i in range(16):
            ownpad |= own[i * 3]; ownfk |= own[i * 3 + 1]; rempad |= rem[i * 4 + 1]; remfk |= rem[i * 4 + 2]
        st = d[ovl + 0x169A] if ovl is not None else None
        cur = (ownpad, ownfk, rempad, remfk, des, st, started)
        now = int(time.time())
        if now != hb:
            hb = now; P('HB nf=%3d stall=%3d rxSeq=%3d remTag=%02X pg1=%s segs=%d blk=%s' % (nf, stall, rx, g(S['remT'])[0],
                g(S['mkPg1'], 3).hex(), g(S['mkPg2'])[0], g(B, 10).hex()))
        if cur != last:
            P('nf=%3d stall=%3d desync=%d(f%d) started=%d netcore=%s  own pad=%02X fk=%02X | remote pad=%02X fk=%02X'
              % (nf, stall, des, desF, started, st, ownpad, ownfk, rempad, remfk))
            last = cur
        if nf != lastnf: lastnf = nf; still = time.time(); dumped = False
        elif not dumped and time.time() - still > 2:
            b = g(B, NB); dumped = True; t1 = S['mkTab1'] - B
            P('FROZEN nf=%d stall=%d rxSeq=%d desync=%d pg1=%s pg2=%s cur=%s seg=%s' % (nf, stall, rx, des,
              g(S['mkPg1'], 3).hex(), g(S['mkPg2'], 3).hex(), b[4:8].hex(), b[8:10].hex()))
            P('  tab1', b[t1:t1 + 28].hex()); P('  tab2', b[t1 + 28:].hex())
            P('  own', own.hex()); P('  rem', rem.hex())
        if st is not None and st not in (1, 2, 3):
            P('game ended, netcore state', st, '- waiting for the next one'); time.sleep(3); break
        time.sleep(0.03)
