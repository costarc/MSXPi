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

MAPPER_KONAMI  = 1      # 8K banks (both Konami4 and Konami SCC)
MAPPER_ASCII8  = 2      # 8K banks
MAPPER_ASCII16 = 3      # 16K banks

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
    """The original chain: exact addresses, most specific first. ASCII16 is
    last because it owns no address of its own."""
    if any(a in hits for a in (0x6800, 0x7800)):          return MAPPER_ASCII8, 8
    if any(a in hits for a in (0x5000, 0x9000, 0xB000)):  return MAPPER_KONAMI, 8
    if any(a in hits for a in (0x8000, 0xA000)):          return MAPPER_KONAMI, 8
    if any(a in hits for a in (0x6000, 0x7000)):          return MAPPER_ASCII16, 16
    return None, None


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
    if used == 2:
        return MAPPER_ASCII16, 16
    return None, None


def patch_bank_switches(rom, mapper_type, handlers):
    """Rewrite every LD (nn),A that targets a bank-select window into
    CALL <handler>, so the MSX only has to store blocks and run.

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
    while i < end:
        if out[i] == 0x32:
            a = out[i + 1] | (out[i + 2] << 8)
            for k, (lo, hi) in enumerate(windows):
                if lo <= a <= hi:
                    out[i] = 0xCD                       # CALL nn
                    out[i + 1] = handlers[k] & 0xFF
                    out[i + 2] = (handlers[k] >> 8) & 0xFF
                    n += 1
                    i += 2
                    break
        i += 1
    return bytes(out), n
