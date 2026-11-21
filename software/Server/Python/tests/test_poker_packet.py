"""PPOKER packet layout: documents/POKER-TOURNAMENT.md, the server and the client.

Builds one mid-hand table (button, blinds posted, a fold, an all-in, a bet to
call, the flop out) and checks every row of the doc's packet table and seat
record by offset, then the chat and error packets.  The last test reads the
offsets software/Client/src/ppoker.c parses, so a change on either side that
moves a field shows up here.

Run from software/Server/Python:
    python -m unittest tests.test_poker_packet -v
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_poker as p

CONFIG = {'POKERSTACK': '1000', 'POKERACTIONSECS': '30', 'POKERLEVELSECS': '300',
          'POKERDROP': '20', 'POKERGRACE': '600', 'POKERHANDDELAY': '5', 'POKERLATE': '4'}


def card(text):
    return p.RANK_NAMES.index(text[0]) * 4 + p.SUIT_NAMES.index(text[1])


def w(data, offset):
    return data[offset] | (data[offset + 1] << 8)


class Clock:
    def __init__(self, start=1000.0):
        self.t = start

    def __call__(self):
        return self.t


def mid_hand():
    """Four players; seat 0 ALICE is on the button and faces a flop bet.

    Preflop: DAVIDSON (UTG) folds, ALICE calls, BOB (small blind) calls, CAROL
    (big blind, 80 chips) checks.  Flop: BOB bets 100, CAROL calls all in for
    60, and it is ALICE's turn with 100 to call.
    """
    clock = Clock()
    t = p.Tournament('packet', CONFIG, clock=clock)
    for nick in ('ALICE', 'BOB', 'CAROL', 'DAVIDSON'):
        seat, message = t.join(nick, clock())
        assert seat is not None, message
    t.seat_of('CAROL').stack = 80
    clock.t += 3
    t.tick(clock())
    assert t.button == 0 and t.actor == 3, (t.button, t.actor)

    def act(nick, action, amount=0):
        error = t.act(t.seat_of(nick), action, amount, clock())
        assert error is None, (nick, action, error)

    act('DAVIDSON', 'fold')
    act('ALICE', 'call')
    act('BOB', 'call')
    act('CAROL', 'check')
    assert t.stage == p.STAGE_FLOP
    clock.t += 7
    act('BOB', 'bet', 100)
    act('CAROL', 'call')
    assert t.actor == 0
    # Known cards, so the hand name is fixed: ALICE has trip aces.
    t.board = [card('AS'), card('KD'), card('7H')]
    t.seat_of('ALICE').cards = [card('AH'), card('AD')]
    t.say('BOB', 'nice flop')
    return t, clock


class TablePacket(unittest.TestCase):
    def setUp(self):
        self.t, self.clock = mid_hand()
        self.data = self.t.snapshot('ALICE')

    def test_size_magic_kind_checksum(self):
        d = self.data
        self.assertEqual(len(d), 256)
        self.assertEqual(d[0:4], b'POKR')                     # 0-3 magic
        self.assertEqual(d[4], 1)                             # 4 table packet
        self.assertEqual(d[5], 1)                             # 5 table packet
        self.assertEqual(d[255], sum(d[0:255]) & 0xFF)        # 255 checksum

    def test_header(self):
        d, t = self.data, self.t
        self.assertEqual(d[6], p.STAGE_FLOP)                  # 6 stage
        self.assertEqual(d[7], 1 | 2 | 32)                    # 7 my turn, in hand, button
        self.assertEqual(w(d, 8), 1)                          # 8 hand number
        self.assertEqual(w(d, 10), 60 + 100 + 60)             # 10 pot
        self.assertEqual(d[12], 0)                            # 12 my seat
        self.assertEqual(d[13], t.action_seq)                 # 13 action sequence
        self.assertEqual(w(d, 14), 100)                       # 14 to call
        self.assertEqual(w(d, 16), 200)                       # 16 minimum raise to
        self.assertEqual(w(d, 18), 980)                       # 18 my stack
        self.assertEqual(w(d, 20), 0)                         # 20 my bet this street
        self.assertEqual(d[22], 30)                           # 22 action clock
        self.assertEqual(d[23], 4)                            # 23 players left
        self.assertEqual(d[24], 1)                            # 24 blind level
        self.assertEqual(d[25], 4)                            # 25 seats in use
        self.assertEqual(w(d, 26), 10)                        # 26 small blind
        self.assertEqual(w(d, 28), 20)                        # 28 big blind
        self.assertEqual(d[30], 1)                            # 30 registration open
        self.assertEqual(d[31], 0)                            # 31 unused
        self.assertEqual(list(d[32:37]), [card('AS'), card('KD'), card('7H'), 0xFF, 0xFF])
        self.assertEqual(list(d[37:39]), [card('AH'), card('AD')])
        self.assertEqual(d[39], 4)                            # 39 players left, as 23
        self.assertEqual(d[40], 0)                            # 40 unused
        self.assertEqual(d[41], 0)                            # 41 no next hand yet
        self.assertEqual(d[42], 255)                          # 42 grace 600, capped
        self.assertEqual(d[43], 0)                            # 43 unused
        self.assertEqual(d[44:54], b'TRIPS'.ljust(10, b'\0'))  # 44-53 hand name
        self.assertEqual(d[54:64], bytes(10))                 # 54-63 unused

    def test_seat_records(self):
        d = self.data

        def seat(i):
            base = 64 + 16 * i
            return (d[base], d[base + 1], w(d, base + 2), w(d, base + 4),
                    d[base + 6], d[base + 7], d[base + 8:base + 14], w(d, base + 14))

        self.assertEqual(seat(0), (1 | 2 | 32 | 64, p.ACTION_CALL, 980, 0,
                                   card('AH'), card('AD'), b'ALICE\0', 20))
        self.assertEqual(seat(1), (1 | 2, p.ACTION_BET, 880, 100, 0xFF, 0xFF, b'BOB\0\0\0', 100))
        # All in: stack 0, so the "no chips" bit is set as well.
        self.assertEqual(seat(2), (1 | 2 | 8 | 16, p.ACTION_ALLIN, 0, 60, 0xFF, 0xFF,
                                   b'CAROL\0', 60))
        self.assertEqual(seat(3), (1 | 2 | 4, p.ACTION_FOLD, 1000, 0, 0xFF, 0xFF, b'DAVIDS', 0))
        for i in range(4, 9):
            self.assertEqual(seat(i), (0, 0, 0, 0, 0xFF, 0xFF, bytes(6), 0))

    def test_trailer(self):
        d, t = self.data, self.t
        status = d[208:248]
        self.assertEqual(status, b'CAROL ALLIN 60'.ljust(40, b'\0'))   # 208-247
        self.assertEqual(d[247], 0)                           # always terminated
        self.assertEqual(d[248], len(t.chat['ALICE']))        # 248 unread chat rows
        self.assertGreater(d[248], 0)
        self.assertEqual(d[249], 0)                           # 249 not over
        self.assertEqual(d[250], 1)                           # 250 level again
        self.assertEqual(d[251], 255)                         # 251 290 s left, capped
        self.clock.t += 100
        self.assertEqual(self.t.snapshot('ALICE')[251], 300 - 110)
        self.assertEqual(d[252], 9)                           # 252 seats at a table
        self.assertEqual(d[253], 1)                           # 253 layout version
        self.assertEqual(d[254], 0)                           # 254 unused

    def test_hand_over_and_tournament_over(self):
        t, clock = self.t, self.clock
        # ALICE folds; BOB and CAROL (all in) see the board out and a showdown.
        t.act(t.seat_of('ALICE'), 'fold', 0, clock())
        while t.stage in (p.STAGE_TURN, p.STAGE_RIVER):
            # BOB is the only one left who can bet, and checks it down.
            self.assertIsNone(t.act(t.seat_of('BOB'), 'check', 0, clock()))
        self.assertEqual(t.stage, p.STAGE_OVER)
        d = t.snapshot('ALICE')
        self.assertEqual(d[6], p.STAGE_OVER)
        self.assertEqual(d[30], 1 | 2)                        # registration open, hand over
        self.assertEqual(d[249], 0)
        self.assertEqual(d[41], 5)                            # POKERHANDDELAY
        self.assertEqual(d[22], 0)                            # nobody's clock runs
        shown = [i for i in range(9) if d[64 + 16 * i + 6] != 0xFF and i != 0]
        self.assertEqual(shown, [1, 2])                       # both showed down
        # Everyone else busts: the tournament ends.
        for seat in t.seats:
            if seat.nick != 'BOB':
                seat.stack = 0
        t.finish_hand(clock(), 'BOB WINS')
        d = t.snapshot('BOB')
        self.assertEqual(d[6], p.STAGE_DONE)
        self.assertEqual(d[30] & 2, 0)
        self.assertEqual(d[249], 1)                           # 249 tournament over
        self.assertEqual(d[23], 1)

    def test_not_seated(self):
        d = self.t.snapshot('NOBODY')
        self.assertEqual(d[12], 0xFF)
        self.assertEqual(d[7], 0)
        self.assertEqual(list(d[37:39]), [0xFF, 0xFF])
        for i in range(9):
            self.assertEqual(d[64 + 16 * i + 6:64 + 16 * i + 8], b'\xff\xff')

    def test_others_see_their_own_cards_only(self):
        d = self.t.snapshot('BOB')
        self.assertEqual(d[12], 1)
        self.assertEqual(d[64 + 6:64 + 8], b'\xff\xff')        # ALICE hidden from BOB
        self.assertEqual(list(d[64 + 16 + 6:64 + 16 + 8]), self.t.seat_of('BOB').cards)


class OtherPackets(unittest.TestCase):
    def test_chat_packet(self):
        rows = [(0, 'BOB: NICE FLOP'), (1, 'X' * 50)]
        d = p.chat_packet(rows, 7)
        self.assertEqual(d[0:4], b'POKR')
        self.assertEqual(d[4], 0)
        self.assertEqual(d[5], ord('C'))
        self.assertEqual(d[8:8 + 44], b'BOB: NICE FLOP'.ljust(44, b'\0'))
        self.assertEqual(d[8 + 44:8 + 44 + 42], b'X' * 42)    # 42 characters a row
        self.assertEqual(d[8 + 44 + 42], 0)
        self.assertEqual(d[8 + 43], 0)                         # +43 private flag
        self.assertEqual(d[8 + 44 + 43], 1)
        self.assertEqual(d[8 + 88:240], bytes(240 - 96))       # rows 3-5 empty
        self.assertEqual(d[240], 2)                            # 240 rows
        self.assertEqual(d[241], 7)                            # 241 still queued
        self.assertEqual(d[255], sum(d[0:255]) & 0xFF)

    def test_chat_packet_five_rows(self):
        d = p.chat_packet([(0, 'ROW%d' % i) for i in range(7)], 0)
        self.assertEqual(d[240], 5)
        self.assertEqual(d[8 + 4 * 44:8 + 4 * 44 + 4], b'ROW4')

    def test_error_packet(self):
        d = p.error_packet('not your turn ' + 'x' * 40)
        self.assertEqual(d[0:4], b'POKR')
        self.assertEqual(d[4], 0)
        self.assertEqual(d[5], ord('E'))
        self.assertEqual(d[208:208 + 13], b'NOT YOUR TURN')
        self.assertEqual(d[247], 0)                            # 39 characters at most
        self.assertEqual(d[6:208], bytes(202))
        self.assertEqual(d[255], sum(d[0:255]) & 0xFF)


class ClientOffsets(unittest.TestCase):
    """The offsets ppoker.c reads are the ones the doc and the server use."""

    def source(self, name):
        text = (ROOT / 'software/Client/src/ppoker.c').read_text(encoding='latin-1')
        match = re.search(r'static void %s\(void\) \{(.*?)\n\}' % name, text, re.S)
        self.assertIsNotNone(match, name)
        return match.group(1)

    def test_parse_table(self):
        body = self.source('parse_table')
        header = {int(n) for n in re.findall(r'reply\[(\d+)', body)} | \
                 {int(n) for n in re.findall(r'reply\+(\d+)\)', body)}
        self.assertEqual(header, {6, 7, 8, 10, 12, 14, 16, 18, 20, 22, 23, 24, 26, 28,
                                  32, 37, 38, 44, 248, 249, 251})
        self.assertIn('64+i*16', body)
        seat = {int(n) for n in re.findall(r'base\+(\d+)', body)}
        self.assertEqual(seat, {2, 4, 6, 7, 8})
        self.assertIn('reply[base]', body)

    def test_status_and_chat(self):
        self.assertIn('reply[208+i]', self.source('parse_status'))
        self.assertIn('i<40', self.source('parse_status'))
        text = (ROOT / 'software/Client/src/ppoker.c').read_text(encoding='latin-1')
        self.assertIn('#define CHAT_COLS 42', text)
        self.assertIn('reply+8+i*44', text)
        self.assertIn('reply[8+i*44+CHAT_COLS+1]', text)       # +43 private flag
        self.assertIn('reply[240]', text)
        self.assertIn('reply[241]', text)


if __name__ == '__main__':
    unittest.main()
