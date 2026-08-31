#!/usr/bin/env python3
"""Unit tests for msxpi_eth - protocol logic only, no MSX and no network.

    python test_msxpi_eth.py

These run anywhere and take milliseconds, so they are the first thing to run
after touching the shuttle.  The openMSX harness covers the other half: that
the MSX side of the same protocol agrees with this one.
"""

import sys
import msxpi_eth as E


class FakeTransport(object):
    """Stands in for the MSXPi byte transport.

    `inbox` is what the MSX is about to send; `outbox` collects what the Pi
    sent back.  Burst writes are recorded separately so a test can assert that
    the burst path was actually taken.
    """

    def __init__(self, inbox=b""):
        self.inbox = bytearray(inbox)
        self.outbox = bytearray()
        self.bursts = []

    def read_byte(self):
        if not self.inbox:
            return (0, None)
        return (0, self.inbox.pop(0))

    def write_byte(self, v):
        self.outbox.append(v)
        return 0

    def write_burst(self, data):
        self.bursts.append(bytes(data))
        self.outbox.extend(data)
        return 0


def shuttle(inbox=b"", link=None, burst=False):
    t = FakeTransport(inbox)
    lk = link or E.MockLink()
    s = E.EthShuttle(lk, t.read_byte, t.write_byte,
                     t.write_burst if burst else None)
    return s, t, lk


def frame(dst=b"\xff" * 6, src=b"\x02\x4d\x53\x58\x50\x69",
          ethertype=0x0800, payload=b"hello world"):
    import struct
    return dst + src + struct.pack(">H", ethertype) + payload


results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))


# --- probe ------------------------------------------------------------------

s, t, lk = shuttle()
check("probe-claims-opcode", s.handle(E.OP_PROBE))
check("probe-reply", bytes(t.outbox) == bytes([E.ETH_RC_OK]) + b"ETH" +
      bytes([E.PROTO_VERSION]), repr(bytes(t.outbox)))

# --- unknown opcode is not ours --------------------------------------------

s, t, lk = shuttle()
check("foreign-opcode-ignored", s.handle(0xAA) is False)
check("foreign-opcode-silent", len(t.outbox) == 0)

# --- MAC --------------------------------------------------------------------

s, t, lk = shuttle()
s.handle(E.OP_GET_HWADD)
check("hwadd-len", len(t.outbox) == 1 + 6, len(t.outbox))
check("hwadd-value", bytes(t.outbox[1:]) == lk.mac)
check("hwadd-locally-administered", (lk.mac[0] & 0x02) != 0)

# --- IN_STATUS with nothing queued -----------------------------------------

s, t, lk = shuttle()
s.handle(E.OP_IN_STATUS)
check("instatus-empty", bytes(t.outbox) == b"\x00\x00\x00\x00\x00",
      repr(bytes(t.outbox)))

# --- IN_STATUS with a frame queued -----------------------------------------

s, t, lk = shuttle()
f = frame()
lk.inject(f)
s.handle(E.OP_IN_STATUS)
out = bytes(t.outbox)
check("instatus-flag", out[0] == 1)
check("instatus-length", (out[1] | (out[2] << 8)) == len(f), len(f))
check("instatus-ethertype", (out[3] << 8 | out[4]) == 0x0800, hex(out[3] << 8 | out[4]))

# --- GET_FRAME --------------------------------------------------------------

s, t, lk = shuttle(inbox=b"\x00\x06")        # maxlen = 1536
lk.inject(f)
s.handle(E.OP_GET_FRAME)
out = bytes(t.outbox)
ln = out[0] | (out[1] << 8)
check("getframe-length", ln == len(f), ln)
check("getframe-noflags", out[2] == 0, out[2])
check("getframe-body", out[3:3 + ln] == f)
check("getframe-checksum", out[3 + ln] == (sum(f) & 0xFF))
check("getframe-consumed", lk.pending() == 0)

# --- GET_FRAME sets the more-pending flag ----------------------------------

s, t, lk = shuttle(inbox=b"\x00\x06")
lk.inject(f)
lk.inject(f)
s.handle(E.OP_GET_FRAME)
check("getframe-more-pending", bytes(t.outbox)[2] & E.FLAG_MORE_PENDING)

# --- GET_FRAME with nothing queued -----------------------------------------

s, t, lk = shuttle(inbox=b"\x00\x06")
s.handle(E.OP_GET_FRAME)
check("getframe-empty", bytes(t.outbox) == b"\x00\x00\x00", repr(bytes(t.outbox)))

# --- GET_FRAME when the frame does not fit ---------------------------------

# maxlen = 16; f is 25 bytes, so it genuinely does not fit.
s, t, lk = shuttle(inbox=b"\x10\x00")
lk.inject(f)
s.handle(E.OP_GET_FRAME)
check("getframe-toobig-reports-zero", bytes(t.outbox)[:2] == b"\x00\x00")
check("getframe-toobig-dropped", lk.pending() == 0)

# --- SEND_FRAME -------------------------------------------------------------

payload = frame(payload=b"x" * 40)
chk = sum(payload) & 0xFF
s, t, lk = shuttle(inbox=bytes([len(payload) & 0xFF, len(payload) >> 8]) +
                          payload + bytes([chk]))
s.handle(E.OP_SEND_FRAME)
check("sendframe-ok", bytes(t.outbox) == bytes([E.ETH_RC_OK]), repr(bytes(t.outbox)))
check("sendframe-transmitted", len(lk.sent) == 1)
sent = lk.sent[0]
check("sendframe-padded", len(sent) == max(len(payload), E.PAD_TO) + 4, len(sent))
check("sendframe-body-intact", sent[:len(payload)] == payload)

# --- SEND_FRAME checksum mismatch ------------------------------------------

s, t, lk = shuttle(inbox=bytes([len(payload) & 0xFF, len(payload) >> 8]) +
                          payload + bytes([(chk + 1) & 0xFF]))
s.handle(E.OP_SEND_FRAME)
check("sendframe-badchecksum", bytes(t.outbox) == bytes([E.ETH_RC_CHKSUM]))
check("sendframe-not-transmitted", len(lk.sent) == 0)

# --- SEND_FRAME length validation ------------------------------------------

s, t, lk = shuttle(inbox=b"\x05\x00")        # 5 bytes, below the 16 minimum
s.handle(E.OP_SEND_FRAME)
check("sendframe-badlen", bytes(t.outbox) == bytes([E.ETH_RC_BADLEN]))

# --- queue policy: full buffer discards NEW, keeps OLD ---------------------

s, t, lk = shuttle()
first = frame(payload=b"FIRST")
for i in range(E.RX_QUEUE_MAX):
    lk.inject(first if i == 0 else frame(payload=bytes([i % 256]) * 20))
lk.inject(frame(payload=b"LAST"))
check("queue-capped", lk.pending() == E.RX_QUEUE_MAX, lk.pending())
check("queue-dropped-counted", lk.dropped == 1, lk.dropped)
got, _ = lk.pop()
check("queue-keeps-oldest", b"FIRST" in got)

# --- oversized frames never enter the queue --------------------------------

s, t, lk = shuttle()
lk.inject(frame(payload=b"z" * (E.MAX_FRAME + 100)))
check("oversize-rejected", lk.pending() == 0)

# --- NET_ONOFF and FILTERS --------------------------------------------------

# UNAPI encoding, passed through untranslated: B = 0 query / 1 enable /
# 2 disable, and A = 1 enabled / 2 disabled.  Note 2 means "disabled" on the way
# in AND on the way out - they are different meanings of the same number.
s, t, lk = shuttle(inbox=b"\x02")
s.handle(E.OP_NET_ONOFF)
check("netoff", bytes(t.outbox) == bytes([E.ETH_RC_OK, 2]) and not lk.enabled)

s, t, lk = shuttle(inbox=b"\x01")
s.handle(E.OP_NET_ONOFF)
check("neton", bytes(t.outbox) == bytes([E.ETH_RC_OK, 1]) and lk.enabled)

s, t, lk = shuttle(inbox=b"\x00")
lk.enabled = False
s.handle(E.OP_NET_ONOFF)
check("net-query-does-not-change",
      bytes(t.outbox) == bytes([E.ETH_RC_OK, 2]) and not lk.enabled)

# ETH_FILTERS: bit 7 of the argument means "report only".
s, t, lk = shuttle(inbox=b"\x06")
s.handle(E.OP_FILTERS)
check("filters-set", bytes(t.outbox) == bytes([E.ETH_RC_OK, 0x06]))

s, t, lk = shuttle(inbox=b"\x86")
lk.filters = 0x02
s.handle(E.OP_FILTERS)
check("filters-query-does-not-change", bytes(t.outbox) == bytes([E.ETH_RC_OK, 0x02]))

check("filters-default-is-bcast-and-small", E.MockLink().filters == 0x06)

# --- disabled link drops incoming ------------------------------------------

s, t, lk = shuttle()
lk.enabled = False
lk._push(frame())
check("disabled-drops", lk.pending() == 0)

# --- RESET clears the queue -------------------------------------------------

s, t, lk = shuttle()
lk.inject(frame())
s.handle(E.OP_RESET)
check("reset-clears", lk.pending() == 0)
check("reset-reply", bytes(t.outbox) == bytes([E.ETH_RC_OK, 0]))

# --- burst path is used when available -------------------------------------

s, t, lk = shuttle(inbox=b"\x00\x06", burst=True)
lk.inject(f)
s.handle(E.OP_GET_FRAME)
check("burst-used", len(t.bursts) == 1, t.bursts and len(t.bursts[0]))
check("burst-carries-whole-reply", len(t.bursts[0]) == 3 + len(f) + 1)

# --- CRC32 matches the known Ethernet FCS check value ----------------------
# The CRC of the ASCII string "123456789" under this polynomial and bit order
# is the standard CRC-32 check constant.
check("crc32-check-vector", E.eth_crc32(b"123456789") == 0xCBF43926,
      hex(E.eth_crc32(b"123456789")))


# --- the success-code mapping the server has to apply ----------------------
# msxpi-server.py's RC_SUCCESS is 0xE0, which is TRUTHY.  If it were handed to
# the shuttle unmapped, _write_many()'s `if rc: return rc` would treat the very
# first successful byte as an error and abandon the rest of the reply.  This
# reproduces the server's wiring exactly so the mapping cannot regress.

RC_SUCCESS_SERVER = 0xE0


class ServerLikeTransport(object):
    def __init__(self):
        self.outbox = bytearray()

    def raw_write(self, v):
        self.outbox.append(v)
        return (RC_SUCCESS_SERVER, v)

    def raw_read(self):
        return (RC_SUCCESS_SERVER, 0)


st = ServerLikeTransport()
s = E.EthShuttle(E.MockLink(),
                 read_byte=st.raw_read,
                 write_byte=lambda v: 0 if st.raw_write(v)[0] == RC_SUCCESS_SERVER else 1)
s.handle(E.OP_GET_HWADD)
check("server-rc-mapping-writes-whole-reply", len(st.outbox) == 7, len(st.outbox))

# And the failure mode it guards against, to prove the test has teeth.
st2 = ServerLikeTransport()
s2 = E.EthShuttle(E.MockLink(),
                  read_byte=st2.raw_read,
                  write_byte=lambda v: st2.raw_write(v)[0])   # unmapped - wrong
s2.handle(E.OP_GET_HWADD)
check("unmapped-rc-would-truncate", len(st2.outbox) == 1, len(st2.outbox))


# --- report -----------------------------------------------------------------

failed = [r for r in results if not r[1]]
for name, ok, detail in results:
    if not ok:
        print("FAIL %-34s %s" % (name, detail))
print("-" * 50)
print("%d passed, %d failed, %d total" %
      (len(results) - len(failed), len(failed), len(results)))
sys.exit(1 if failed else 0)
