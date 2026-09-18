# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

"""MegaROM mapper detection and bank-switch patching, server side.

Both halves of this file exist because the MSX cannot do them well: detection
wants to look at the whole ROM at once, and patching a 128KB ROM on a 3.58MHz
Z80 means scanning 16KB per storage segment before the game even starts.

------------------------------------------------------------------------------
Bank-select addresses (from EXECROM.MAC's own MegaROM table, git 173f41c2)
------------------------------------------------------------------------------
    Konami4 : 6000h, 8000h, A000h                      (single addresses)
    Konami5 : 5000-57FF, 7000-77FF, 9000-97FF, B000-B7FF
    ASCII8  : 6000-67FF, 6800-6FFF, 7000-77FF, 7800-7FFF
    ASCII16 : 6000-6FFF, 7000-7FFF

Note ASCII8's four 2KB windows nest exactly inside ASCII16's two 4KB windows.

------------------------------------------------------------------------------
Why detection uses EXACT addresses but patching uses RANGES
------------------------------------------------------------------------------
This asymmetry is not an oversight; it was measured against all 51 ROMs in the
test set, and every attempt to make both sides consistent made things worse:

  * Widening the FIRST test of the detection chain to 2KB ranges reclassified
    23 of 33 megaROMs as ASCII8. At that granularity essentially every large
    ROM contains some unrelated store that lands in the window, so a widened
    test swallows everything.
  * Requiring a preceding "load A" instruction, to reject data that merely
    looks like LD (nn),A, removed REAL bank switches - XEVIOUS.ROM lost all of
    its sites and became unrecognizable.
  * Range-scoring with per-mapper hit counts misclassified ROMs that have been
    verified by actually running them (BILLIARD as Konami5, ZANACEX as Konami4).

The reason is that the two jobs have opposite error costs. In detection a
single false hit changes the answer for the entire ROM, so specificity wins. In
patching the mapper type is already known and a missed switch is fatal while a
stray patch costs a few bytes, so coverage wins.

ASCII16 also has no address of its own - it shares 6000h/7000h with the others
- so it can only be identified by ELIMINATION. That is why the chain below is
ordered, and why the order matters more than it looks.
------------------------------------------------------------------------------
"""

MAPPER_KONAMI  = 1      # 8K banks, Konami4
MAPPER_ASCII8  = 2      # 8K banks
MAPPER_ASCII16 = 3      # 16K banks
# Konami SCC: same four 8K windows as ASCII8/Konami on the MSX side, but the
# cartridge decodes 5000h/7000h/9000h/B000h. Server-internal only - the MSX
# is told MAPPER_KONAMI, since its loading path for 8K banks is identical.
MAPPER_KONAMI_SCC = 4

# Windows used for PATCHING, once the type is known.
PATCH_WINDOWS = {
    MAPPER_ASCII8:  [(0x6000, 0x67FF), (0x6800, 0x6FFF),
                     (0x7000, 0x77FF), (0x7800, 0x7FFF)],
    MAPPER_ASCII16: [(0x6000, 0x6FFF), (0x7000, 0x7FFF)],
    # A Konami cartridge decodes an address RANGE, exactly like ASCII8/ASCII16 -
    # matching only 6000h/8000h/A000h left most switches unpatched, and an
    # unpatched switch means the game keeps running the bank it already had.
    # CONTRA.ROM had 2 of its 46 sites patched, ANDROGYN.ROM 0 of 133.
    # Three windows, not four: the Konami-SCC decode (7000-77FF, 9000-97FF,
    # B000-B7FF) is a subset of these and picks the same window each time. Its
    # fourth window, 5000-57FF (the bank at 4000h), is NOT covered - in a
    # Konami4 ROM that range is ordinary ROM, and the handful of stores that
    # land in it are data coincidences (LODERUN.ROM has 10, and it is Konami4),
    # so patching them would corrupt the image. SCC needs its own mapper type.
    MAPPER_KONAMI:  [(0x6000, 0x7FFF), (0x8000, 0x9FFF), (0xA000, 0xBFFF)],
    # One window per 8K page: 5000h->4000h, 7000h->6000h, 9000h->8000h,
    # B000h->A000h. Patching these as Konami4 left CONTRA, PENNANT, MANBOW,
    # KINGS VALLEY 2 and METAL GEAR 2 switching the wrong windows.
    MAPPER_KONAMI_SCC: [(0x5000, 0x57FF), (0x7000, 0x77FF),
                        (0x9000, 0x97FF), (0xB000, 0xB7FF)],
}

# A genuine bank-select address is written over and over; a data coincidence
# appears once or twice. BUBBLE.ROM writes 7FF8h 133 times and 77F8h 31 times;
# ISHTAR.ROM writes 77FFh 97 times and 67FFh 68 times. Neither touches 6800h or
# 7800h exactly, so the strict chain rejected both as unrecognized.
REPEAT_MIN = 8


def write_targets(rom):
    """Every LD (nn),A target in the ROM, with a count per address."""
    hits = {}
    for i in range(len(rom) - 2):
        if rom[i] == 0x32:
            a = rom[i + 1] | (rom[i + 2] << 8)
            hits[a] = hits.get(a, 0) + 1
    return hits


def _strict(hits):
    """Exact addresses, most specific first. Validated against the mapper
    types in openMSX's softwaredb.xml for all 33 megaROMs in the test set
    (32 match; SUPERLOA uses the unsupported SuperLodeRunner mapper and is
    correctly left unrecognised).

    The previous order sent any ROM with a stray 5000h store to Konami
    (ALESTE, FANZONE2 are ASCII16), any single 7800h to ASCII8 (METAL GEAR is
    Konami4) and every Konami SCC ROM to Konami4. 9000h is written only by
    SCC games - 12 to 26 times each - so it goes first; Konami4 needs BOTH
    8000h and A000h; ASCII16 still comes last, owning no address of its own."""
    if 0x9000 in hits:                                    return MAPPER_KONAMI_SCC, 8
    if 0x8000 in hits and 0xA000 in hits:                 return MAPPER_KONAMI, 8
    if any(a in hits for a in (0x6800, 0x7800)):          return MAPPER_ASCII8, 8
    if any(a in hits for a in (0x5000, 0x6000, 0x7000)):  return MAPPER_ASCII16, 16
    return None, None


# ------------------------------------------------------------------------------
# ROM database lookup (openMSX share/softwaredb.xml)
# ------------------------------------------------------------------------------
# The database is the authority; detect_mapper() below is only the fallback
# for ROMs it does not know. Types are openMSX's names, matched without regard
# to case (the file has both "Konami" and "konami").
ROMDB_PLAIN_TYPES = {"mirrored", "normal", "page12", "mirrored4000",
                     "0x4000", "8kb", "16kb"}
ROMDB_MAPPER_TYPES = {
    "ascii8":       (MAPPER_ASCII8, 8),
    "ascii8sram2":  (MAPPER_ASCII8, 8),
    "ascii8sram8":  (MAPPER_ASCII8, 8),
    "ascii16":      (MAPPER_ASCII16, 16),
    "ascii16sram2": (MAPPER_ASCII16, 16),
    "ascii16sram8": (MAPPER_ASCII16, 16),
    "konami":       (MAPPER_KONAMI, 8),
    "konamiscc":    (MAPPER_KONAMI_SCC, 8),
}


def load_romdb(xml_text):
    """Index openMSX's softwaredb.xml by SHA-1: {sha1: (type, title)}.
    A regex scan rather than an XML parser - the file is 1.4MB and this runs
    on a Raspberry Pi."""
    import re
    db = {}
    for sw in re.finditer(r'<software title="([^"]*)"(.*?)</software>', xml_text, re.S):
        title = sw.group(1)
        for rom in re.finditer(r'<rom\b([^>]*)/?>', sw.group(2)):
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', rom.group(1)))
            sha1 = attrs.get("sha1", "").lower()
            if len(sha1) == 40:
                db[sha1] = (attrs.get("type", ""), title)
    return db


def romdb_lookup(rom, db):
    """('plain', None, type, title), ('mapper', (mapper, bank_kb), type, title),
    ('unsupported', None, type, title), or None when the ROM is not listed."""
    import hashlib
    if not db:
        return None
    entry = db.get(hashlib.sha1(rom).hexdigest())
    if entry is None:
        return None
    dbtype, title = entry
    key = dbtype.strip().lower()
    if key in ROMDB_PLAIN_TYPES:
        return ("plain", None, dbtype, title)
    if key in ROMDB_MAPPER_TYPES:
        return ("mapper", ROMDB_MAPPER_TYPES[key], dbtype, title)
    return ("unsupported", None, dbtype, title)


def _repeated(hits, lo, hi):
    return [a for a, c in hits.items() if lo <= a <= hi and c >= REPEAT_MIN]


def detect_mapper(rom):
    """(mapper_type, bank_size_kb), or (None, None) if unrecognizable.

    Runs the strict exact-address chain first and only falls back to the
    repetition heuristic when that rejects the ROM, so a ROM that already
    classified keeps classifying exactly as before.
    """
    hits = write_targets(rom)
    mt, bs = _strict(hits)
    if mt is not None:
        return mt, bs

    if _repeated(hits, 0x5000, 0x57FF) and _repeated(hits, 0x9000, 0x97FF):
        return MAPPER_KONAMI, 8

    w = [_repeated(hits, lo, hi) for lo, hi in PATCH_WINDOWS[MAPPER_ASCII8]]
    used = sum(1 for g in w if g)
    # both halves of a 4KB group in use means the game tells them apart, so the
    # windows are 8K, not 16K
    if used >= 3 or (w[0] and w[1]) or (w[2] and w[3]):
        return MAPPER_ASCII8, 8
    # A single repeated window lies inside ASCII16's decode range too:
    # ANDROGYN.ROM writes only 77FFh (23 times) and is ASCII16.
    if used in (1, 2):
        return MAPPER_ASCII16, 16
    return None, None


# The bank-select register of each window, exactly. A real bank switch writes
# one of these; data that merely looks like LD (nn),A lands somewhere inside a
# window instead - see the inc/dec rule in _plausible_bank_store.
EXACT_BANK_ADDRS = {
    MAPPER_KONAMI:     (0x6000, 0x8000, 0xA000),
    MAPPER_KONAMI_SCC: (0x5000, 0x7000, 0x9000, 0xB000),
    MAPPER_ASCII8:     (0x6000, 0x6800, 0x7000, 0x7800),
    MAPPER_ASCII16:    (0x6000, 0x7000),
}


def _plausible_bank_store(rom, i, depth=4, exact=False):
    """Is the 32 lo hi at rom[i] plausibly a real LD (nn),A instruction?

    The byte pattern alone also matches data and the middle of other
    instructions. NEMESIS.ROM's PLAY SELECT text contains 32 FF 6D ("R" then
    two layout bytes), which was patched into CALL F9C5h and drawn as
    "1PLAYE" plus garbage; XEVIOUS.ROM's "add a,32h / ld (ix+10h),a" read as
    LD (DD77h),A. A genuine bank switch follows an instruction that loads A,
    or one that leaves A alone. Checked against every megaROM in the test set:
    ARCTIC's "di / ld (7000h),a" and XEVIOUS/ZANACEX's chained
    "ld (nn),a / ld (7000h),a" are kept, the text and operand hits dropped."""
    if i >= 2 and rom[i - 2] == 0x3E:                              # ld a,n
        return True
    if i >= 3 and rom[i - 3] == 0x3A:                              # ld a,(nn)
        return True
    if i >= 1 and 0x78 <= rom[i - 1] <= 0xBF:                      # ld a,r / a op r
        return True
    if i >= 1 and rom[i - 1] in (0x3C, 0x3D, 0xAF, 0x87, 0x2F, 0x1A, 0x0A,
                                 0x07, 0x0F, 0x17, 0x1F, 0xF1, 0xB7):
        return True                                                # inc/dec/rotate/pop af...
    if i >= 3 and rom[i - 3] in (0xDD, 0xFD) and rom[i - 2] == 0x7E:
        return True                                                # ld a,(ix/iy+d)
    if i >= 2 and rom[i - 2] in (0xE6, 0xF6, 0xC6, 0xD6, 0xEE, 0xCE, 0xDE):
        return True                                                # and/or/add/sub... n
    if i >= 2 and rom[i - 2] == 0xCB:                              # CB-prefixed op
        return True
    # Instructions that leave A as it was and are distinctive enough to trust
    # on their own.
    if i >= 1 and rom[i - 1] in (0xF3, 0xFB, 0xF5, 0xC5, 0xD5, 0xE5):
        return True                                                # di / ei / push
    if i >= 3 and rom[i - 3] == 0x32:                              # chained ld (nn),a
        return True
    if i >= 2 and rom[i - 2] == 0x18 and rom[i - 1] == 0x00:       # jr +0
        return True
    # Weaker ones - also leave A alone, but common as data too - count only if
    # the instruction before them is plausible in turn. The Konami boot code
    # sets all three windows in a row - METAL GEAR, MGEAR and USAS do
    #     ld a,04h / push hl / ld hl,0F0F1h / ld (6000h),a / ld (hl),a /
    #     inc a / inc hl / ld (8000h),a ...
    # and without these the switch after ld hl,nn / inc hl was left unpatched,
    # so the game ran from the wrong banks and fell back to DOS. Accepted on
    # their own, NEMESIS's text "...21 39 25 32 FF 6D" read as ld hl,2539h
    # before the store and was patched again; the byte before that 21h is 2Ch,
    # which is not plausible, so the chain rejects it.
    if depth <= 0:
        return False
    # 8-bit inc/dec of B-L are weak too, but only for a store to an exact
    # bank-select register. PENNANT.ROM sets all four SCC windows in a row -
    # ld (7000h),a / ld (hl),a / inc a / inc l / ld (9000h),a / ld (hl),a /
    # inc a / inc l / ld (0B000h),a - and rejecting inc l left the 9000h and
    # B000h switches unpatched, so the banks never changed and the game ran
    # into data. Allowed for any window address, the same bytes are so common
    # in data that it also patched TETRIS's "15 32 15 70" tables, METAL GEAR's
    # bank-10 graphics (32 6E 7C) and METAL GEAR 2's 32 61 71 - all targets
    # somewhere inside a window, none of them a bank register. NEMESIS's
    # "39 25 32" stays rejected either way: 39h before the dec h is not
    # plausible.
    if exact and i >= 1 and rom[i - 1] in (0x04, 0x05, 0x0C, 0x0D, 0x14, 0x15,
                                           0x1C, 0x1D, 0x24, 0x25, 0x2C, 0x2D):
        return _plausible_bank_store(rom, i - 1, depth - 1, exact)  # inc/dec r
    if i >= 3 and rom[i - 3] in (0x01, 0x11, 0x21, 0x31):          # ld rr,nn
        return _plausible_bank_store(rom, i - 3, depth - 1, exact)
    if i >= 1 and rom[i - 1] in (0x03, 0x13, 0x23, 0x0B, 0x1B, 0x2B):
        return _plausible_bank_store(rom, i - 1, depth - 1, exact)  # inc/dec rr
    if i >= 1 and 0x70 <= rom[i - 1] <= 0x77 and rom[i - 1] != 0x76:
        return _plausible_bank_store(rom, i - 1, depth - 1, exact)  # ld (hl),r
    return False


def patch_bank_switches(rom, mapper_type, handlers):
    """Rewrite every LD (nn),A that targets a bank-select window into
    CALL <handler>, so the MSX only has to store blocks and run. Sites that do
    not look like real instructions are left alone - see _plausible_bank_store.

    handlers: one address per window of that mapper, in window order.
    Returns (patched_rom, count).
    """
    windows = PATCH_WINDOWS.get(mapper_type)
    if not windows:
        return rom, 0
    if len(handlers) < len(windows):
        raise ValueError(f"need {len(windows)} handler addresses, got {len(handlers)}")

    out = bytearray(rom)
    n = 0
    i = 0
    end = len(out) - 2
    exact_addrs = EXACT_BANK_ADDRS.get(mapper_type, ())
    while i < end:
        target = out[i + 1] | (out[i + 2] << 8) if out[i] == 0x32 else None
        exact = target in exact_addrs
        if out[i] == 0x32 and _plausible_bank_store(rom, i, exact=exact):
            a = out[i + 1] | (out[i + 2] << 8)
            for k, (lo, hi) in enumerate(windows):
                if lo <= a <= hi:
                    # SCC cartridges also expose sound-chip controls in the
                    # mapper register area.  Treating every ranged store as a
                    # bank switch corrupts MANBOW tables. Exact SCC register
                    # writes are still bank switches, even for high values
                    # like 3Fh: the resident handler masks them like hardware.
                    if mapper_type == MAPPER_KONAMI_SCC and not exact:
                        break
                    out[i] = 0xCD                       # CALL nn
                    out[i + 1] = handlers[k] & 0xFF
                    out[i + 2] = (handlers[k] >> 8) & 0xFF
                    n += 1
                    break
            # Step over the whole instruction even when it is not a bank
            # switch. METAL.ROM has ld a,(0C602h) / ld (0C632h),a / xor a at
            # 55F3h: the store to RAM was skipped one byte at a time, so its
            # operand "32 C6" plus the xor a (AFh) read as ld (0AFC6h),a, got
            # patched into CALL F9CFh, and the game crashed with SP=1010h.
            i += 3
            continue
        i += 1
    return bytes(out), n


# ASCII8 window select with the register computed at run time, D = window 0-3,
# E = bank. HYDLIDE3.ROM does all its ordinary bank switching through this
# routine at 414Dh (called from 12 places):
#     ld a,d / add a,a / add a,a / add a,a / add a,60h / ld h,a / di / ld (hl),e
# There is no LD (nn),A, so patch_bank_switches never saw it; in RAM the
# ld (hl),e overwrote the game's own code instead of switching, and the game
# sat on a blue screen with the wrong bank in 8000h.
_ASCII8_INDEXED_SELECT = bytes([0x7A, 0x87, 0x87, 0x87, 0xC6, 0x60, 0x67, 0xF3, 0x73])


def patch_indexed_switches(rom, mapper_type, dispatch):
    """Replace each ASCII8 computed window select with di / CALL <dispatch>
    (the MSX's window dispatcher, D = window, E = bank) padded with NOPs to the
    same nine bytes. Returns (patched_rom, count)."""
    if mapper_type != MAPPER_ASCII8 or not dispatch:
        return rom, 0
    pat = _ASCII8_INDEXED_SELECT
    repl = bytes([0xF3, 0xCD, dispatch & 0xFF, (dispatch >> 8) & 0xFF]) + \
        bytes(len(pat) - 4)
    out = bytearray(rom)
    n = 0
    i = out.find(pat)
    while i >= 0:
        out[i:i + len(pat)] = repl
        n += 1
        i = out.find(pat, i + len(pat))
    return bytes(out), n


def neutralise_scc_writes(rom):
    """NOP writes to Konami SCC sound registers.

    A Konami SCC cartridge exposes sound registers at 9800h-98FFh after the SCC
    is enabled.  msxarch runs from RAM, so those writes would overwrite the ROM
    image instead of reaching hardware; Space Manbow does this continuously
    during play.  The loader cannot emulate SCC sound, but it can preserve the
    ROM image by making those writes no-ops.
    """
    out = bytearray(rom)
    n = 0

    def in_scc(a):
        return 0x9800 <= a <= 0x98FF

    def patch_span(i, size):
        nonlocal n
        if any(out[i + k] for k in range(size)):
            for k in range(size):
                out[i + k] = 0
            n += 1

    def same_bank_target(origin, target):
        # MANBOW's SCC mixer code calls helpers in the same 8K ROM bank that is
        # currently visible at 6000h-7FFFh.
        if not 0x4000 <= target <= 0xBFFF:
            return None
        off = (origin & ~0x1FFF) + (target & 0x1FFF)
        return off if 0 <= off < len(rom) else None

    scc_roots = []

    for i in range(len(rom) - 3):
        # Common SCC helper setup: ld de,98xxh / call helper.  The helper only
        # writes sound registers; in RAM that is destructive, so skip it.  Some
        # MANBOW paths jump through the helper instead of calling it directly, and
        # some put flag tests between the LD DE and CALL. Remember those roots so
        # the helper's own store opcodes can be neutralised below.
        if rom[i] == 0x11:
            a = rom[i + 1] | (rom[i + 2] << 8)
            if in_scc(a):
                for j in range(i + 3, min(i + 40, len(rom) - 2)):
                    if rom[j] in (0xC3, 0xCD):
                        target = rom[j + 1] | (rom[j + 2] << 8)
                        off = same_bank_target(i, target)
                        if off is not None:
                            scc_roots.append(off)
                        if j == i + 3 and rom[j] == 0xCD:
                            patch_span(j, 3)

    seen = set()

    def neutralise_helper(root, depth=0):
        if root in seen or depth > 2:
            return
        seen.add(root)
        pc = root
        end = min(root + 96, len(rom))
        while pc < end:
            op = rom[pc]
            if op == 0xC9:
                return
            if op == 0xCD and pc + 2 < len(rom):
                target = rom[pc + 1] | (rom[pc + 2] << 8)
                off = same_bank_target(root, target)
                if off is not None:
                    neutralise_helper(off, depth + 1)
                pc += 3
                continue
            if op == 0xC3:
                target = rom[pc + 1] | (rom[pc + 2] << 8)
                off = same_bank_target(root, target)
                if off is not None:
                    neutralise_helper(off, depth + 1)
                return
            if op == 0x12 and pc > root and rom[pc - 1] == 0x7E:
                patch_span(pc, 1)     # ld (de),a after ld a,(hl)
            elif op == 0x77 and pc > root and rom[pc - 1] == 0x1A:
                patch_span(pc, 1)     # ld (hl),a after ld a,(de)
            pc += 1

    for root in scc_roots:
        neutralise_helper(root)

    return bytes(out), n


# ------------------------------------------------------------------------------
# Plain ROMs: neutralise stores into the ROM's own address window
# ------------------------------------------------------------------------------
# A cartridge ROM is read-only, so a store into it is silently discarded by the
# hardware. msxarch runs the image from RAM, where the same store SUCCEEDS and
# overwrites the game's own code. GOONIES.ROM does, at 401Fh:
#     ld   hl,0C9E1h
#     ld   (0411Ch),hl      ; a no-op on a real cartridge
# which in RAM turns the DJNZ at 411Ch into POP HL / RET and hangs the game.
#
# This used to be a linear byte scan on the MSX, which also matched DATA that
# merely looked like LD (nn),A / LD (nn),HL: GALAGA.ROM lost 22 bytes of its
# tables that way and hung on a black screen, CASTLE.ROM 17, AVALANCH.ROM 76.
# Only instructions reached by following the code from the header entry points
# are considered now. Code reached only through computed jumps (JP (HL), jump
# tables) is not traced; a store there is left alone, which is the old
# unpatched behaviour, never a corruption.

_LEN3 = {0x01, 0x11, 0x21, 0x31, 0x22, 0x2A, 0x32, 0x3A,
         0xC2, 0xC3, 0xC4, 0xCA, 0xCC, 0xCD, 0xD2, 0xD4, 0xDA, 0xDC,
         0xE2, 0xE4, 0xEA, 0xEC, 0xF2, 0xF4, 0xFA, 0xFC}
_LEN2 = {0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E,
         0x10, 0x18, 0x20, 0x28, 0x30, 0x38,
         0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE,
         0xD3, 0xDB, 0xCB}
# IX/IY-prefixed opcodes that take a (IX+d) displacement byte
_DISP = ({0x34, 0x35, 0x36, 0x46, 0x4E, 0x56, 0x5E, 0x66, 0x6E, 0x7E, 0x77,
          0x86, 0x8E, 0x96, 0x9E, 0xA6, 0xAE, 0xB6, 0xBE} | set(range(0x70, 0x76)))


def _base_len(op):
    return 3 if op in _LEN3 else 2 if op in _LEN2 else 1


def _insn_len(rom, i):
    op = rom[i]
    if op == 0xED:
        return 4 if (i + 1 < len(rom) and rom[i + 1] in
                     (0x43, 0x4B, 0x53, 0x5B, 0x63, 0x6B, 0x73, 0x7B)) else 2
    if op in (0xDD, 0xFD):
        if i + 1 >= len(rom):
            return 1
        sub = rom[i + 1]
        if sub == 0xCB:
            return 4
        if sub in (0xDD, 0xFD, 0xED):
            return 1                        # redundant prefix, acts as a NOP
        return 1 + _base_len(sub) + (1 if sub in _DISP else 0)
    return _base_len(op)


def _store_target(rom, i):
    """Address of an absolute 16-bit store at rom[i], else None."""
    op = rom[i]
    if op in (0x32, 0x22):
        return rom[i + 1] | (rom[i + 2] << 8)
    if op == 0xED and rom[i + 1] in (0x43, 0x53, 0x63, 0x73):
        return rom[i + 2] | (rom[i + 3] << 8)
    if op in (0xDD, 0xFD) and rom[i + 1] == 0x22:
        return rom[i + 2] | (rom[i + 3] << 8)
    return None


def trace_code(rom, base=0x4000):
    """Offsets of every instruction reachable from the ROM header's INIT,
    STATEMENT and DEVICE entries, following jumps, calls and fallthrough."""
    size = len(rom)
    todo = []
    for h in (2, 4, 6):                      # TEXT (8) points at BASIC, not code
        a = rom[h] | (rom[h + 1] << 8)
        # LODERUN.ROM's INIT is 4004h: its code starts inside the header.
        if base + 4 <= a < base + size:
            todo.append(a - base)
    seen = set()
    while todo:
        i = todo.pop()
        while 0 <= i < size and i not in seen:
            n = _insn_len(rom, i)
            if i + n > size:
                break
            seen.add(i)
            op = rom[i]
            nxt = i + n
            target = None
            stop = False
            if op in (0xC3, 0xCD) or (op & 0xC7) in (0xC2, 0xC4):
                target = (rom[i + 1] | (rom[i + 2] << 8)) - base
                stop = (op == 0xC3)
            elif op in (0x18, 0x10, 0x20, 0x28, 0x30, 0x38):
                d = rom[i + 1]
                target = nxt + (d - 256 if d > 127 else d)
                stop = (op == 0x18)
            elif op in (0xC9, 0xE9) or (op == 0xED and rom[i + 1] in (0x45, 0x4D)) \
                    or (op in (0xDD, 0xFD) and rom[i + 1] == 0xE9):
                stop = True
            # Interrupt hooks: GOONIES reaches most of its code through
            # ld hl,4028h / ld (0FD9Bh),hl - a timer hook, never a CALL.
            # Only a literal that is stored into the BIOS hook area is
            # followed; following every address literal traced data tables as
            # code and brought the false positives straight back.
            if op == 0x21 and nxt + 3 <= size and rom[nxt] == 0x22:
                lit = rom[i + 1] | (rom[i + 2] << 8)
                dest = rom[nxt + 1] | (rom[nxt + 2] << 8)
                if 0xFD9A <= dest <= 0xFFC9 and base + 4 <= lit < base + size \
                        and lit - base not in seen:
                    todo.append(lit - base)
            # Pushed return addresses: VALLEY.ROM does ld hl,4644h / push hl
            # before dispatching, so 4644h runs when the handler returns.
            if op in (0x01, 0x11, 0x21) and nxt < size and \
                    rom[nxt] == {0x01: 0xC5, 0x11: 0xD5, 0x21: 0xE5}[op]:
                lit = rom[i + 1] | (rom[i + 2] << 8)
                if base + 4 <= lit < base + size and lit - base not in seen:
                    todo.append(lit - base)
            if target is not None and 0 <= target < size and target not in seen:
                todo.append(target)
            if stop:
                break
            i = nxt
    return seen


# Single-byte writes through HL: ld (hl),r / ld (hl),n / inc (hl) / dec (hl)
_HL_WRITES = {0x34, 0x35, 0x36, 0x77} | set(range(0x70, 0x76))


def _hl_write_len(rom, j):
    """Length of a write through (HL) at rom[j], else 0. Includes the CB
    prefixed RES b,(HL) / SET b,(HL)."""
    if j >= len(rom):
        return 0
    if rom[j] in _HL_WRITES:
        return 2 if rom[j] == 0x36 else 1
    if rom[j] == 0xCB and j + 1 < len(rom) and rom[j + 1] >= 0x80 \
            and (rom[j + 1] & 7) == 6:
        return 2
    return 0


# Opcodes after which HL no longer holds a value we can follow statically.
_HL_CHANGERS = ({0x21, 0x2A, 0xE1, 0x09, 0x19, 0x29, 0x39, 0xEB, 0xE3, 0xF9,
                 0x24, 0x25, 0x2C, 0x2D, 0x26, 0x2E} | set(range(0x60, 0x70)))
# Anything that leaves the current straight-line block.
_FLOW = ({0xC3, 0xCD, 0x18, 0x10, 0x20, 0x28, 0x30, 0x38, 0xC9, 0xE9, 0x76}
         | {x for x in range(0xC0, 0x100) if (x & 0xC7) in (0xC0, 0xC2, 0xC4, 0xC7)})


def _hl_run_writes(rom, i, code, lo, hi):
    """Follow HL from the traced ld hl,nn at rom[i] through the straight-line
    code after it. Returns (offset, length) of every write through (HL) made
    while HL points into [lo, hi). VALLEY.ROM does
        ld hl,40E4h / ld a,(404Ch) / ld (hl),a / inc hl / ld (hl),0C9h
    rewriting its own dispatcher, which a cartridge silently ignores."""
    hl = rom[i + 1] | (rom[i + 2] << 8)
    j = i + 3
    writes = []
    for _ in range(16):
        if j not in code or j >= len(rom):
            break
        op = rom[j]
        n = _insn_len(rom, j)
        if op == 0xED:
            sub = rom[j + 1]
            if sub in (0x67, 0x6F):                    # rrd / rld write (hl)
                if lo <= hl < hi:
                    writes.append((j, 2))
                j += n
                continue
            if sub in (0x42, 0x4A, 0x52, 0x5A, 0x62, 0x6A, 0x72, 0x7A, 0x6B,
                       0x45, 0x4D, 0xA0, 0xA8, 0xB0, 0xB8, 0xA1, 0xA9, 0xB1, 0xB9):
                break                                   # HL changed or block ends
            j += n
            continue
        if op in (0xDD, 0xFD):
            if rom[j + 1] in (0x66, 0x6E, 0xE9, 0xE3):
                break
            j += n
            continue
        if op == 0xCB:
            sub = rom[j + 1]
            if sub < 0x40 and (sub & 7) in (4, 5):     # shifts/rotates of H or L
                break
            if sub >= 0x80 and (sub & 7) in (4, 5):    # res/set on H or L
                break
            wl = _hl_write_len(rom, j)
            if wl and lo <= hl < hi:
                writes.append((j, wl))
            j += n
            continue
        if op == 0x23:
            hl = (hl + 1) & 0xFFFF
            j += 1
            continue
        if op == 0x2B:
            hl = (hl - 1) & 0xFFFF
            j += 1
            continue
        wl = _hl_write_len(rom, j)
        if wl:
            if lo <= hl < hi:
                writes.append((j, wl))
            j += n
            continue
        if op in _HL_CHANGERS or op in _FLOW:
            break
        j += n
    return writes


def neutralise_rom_writes(rom, base=0x4000):
    """NOP out traced stores whose target lies inside the ROM image.
    Returns (rom, count).

    Every such store is a no-op on the cartridge - verified by running
    GOONIES, AVALANCH and FROGGER in openMSX's own cartridge slot, where all
    three run although AVALANCH makes 76 stores into its own window. Because
    only TRACED instructions are considered, data that merely looks like a
    store is never touched.

    Besides absolute stores this covers the common indirect form
        ld hl,nn / <write through (hl)>
    GOONIES.ROM does ld hl,4721h / res 6,(hl) at 40B7h; in RAM that clears a
    bit of its own data table and the game stays on a black screen."""
    code = trace_code(rom, base)
    lo, hi = base, base + len(rom)
    out = bytearray(rom)
    n = 0
    for i in sorted(code):
        if rom[i] == 0x21 and i + 3 <= len(rom):
            for j, wl in _hl_run_writes(rom, i, code, lo, hi):
                if any(out[j + k] for k in range(wl)):
                    for k in range(wl):
                        out[j + k] = 0x00
                    n += 1
            continue
        length = _insn_len(out, i)
        if length < 3 or i + length > len(out):
            continue
        a = _store_target(out, i)
        if a is not None and lo <= a < hi:
            for k in range(length):
                out[i + k] = 0x00
            n += 1
    return bytes(out), n
