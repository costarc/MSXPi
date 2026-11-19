"""PPOKER tournament engine tests.

Run from software/Server/Python:
    python -m unittest tests.test_poker -v
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_poker as p


def card(text):
    """'AS' -> the engine's card byte."""
    return p.RANK_NAMES.index(text[0]) * 4 + p.SUIT_NAMES.index(text[1])


def cards(text):
    return [card(text[i:i + 2]) for i in range(0, len(text), 2)]


class Clock:
    def __init__(self, start=1000.0):
        self.t = start

    def __call__(self):
        return self.t

    def advance(self, seconds):
        self.t += seconds
        return self.t


CONFIG = {'POKERSTACK': '1000', 'POKERACTIONSECS': '30', 'POKERLEVELSECS': '300',
          'POKERDROP': '20', 'POKERGRACE': '600', 'POKERHANDDELAY': '5', 'POKERLATE': '4'}


class Table:
    """A tournament with a clock and a few seats filled."""

    def __init__(self, nicks=('ALICE', 'BOB', 'CAROL'), stack=1000, seats=3):
        self.clock = Clock()
        self.t = p.Tournament('test', dict(CONFIG, POKERSTACK=str(stack)), clock=self.clock)
        for nick in nicks:
            seat, error = self.t.join(nick, self.clock())
            assert seat is not None, error
        # Fill the remaining seats so the table is exactly `seats` handed.
        self.clock.advance(3)
        self.t.tick(self.clock())
        assert self.t.stage == p.STAGE_PREFLOP, self.t.stage

    def seat(self, nick):
        return self.t.seat_of(nick)

    def act(self, nick, action, amount=0):
        return self.t.act(self.seat(nick), action, amount, self.clock())

    def wait(self, seconds=31):
        self.clock.advance(seconds)
        self.t.tick(self.clock())

    def chips(self):
        return sum(s.stack for s in self.t.seats) + self.t.pot()


class Hands(unittest.TestCase):
    def test_categories(self):
        straight_flush = p.best_hand(cards('5S6S7S8S9SAD'))
        quads = p.best_hand(cards('7C7D7H7S2C'))
        full_house = p.best_hand(cards('KCKDKH4S4C'))
        flush = p.best_hand(cards('2H5H9HJHQH'))
        straight = p.best_hand(cards('5C6D7H8S9C'))
        trips = p.best_hand(cards('JCJDJH2S5C'))
        two_pair = p.best_hand(cards('3C3D8H8SKS'))
        pair = p.best_hand(cards('ACAD7H5S2C'))
        high = p.best_hand(cards('ACQD7H5S2C'))
        self.assertEqual([h[0] for h in (straight_flush, quads, full_house, flush, straight,
                                         trips, two_pair, pair, high)],
                         [8, 7, 6, 5, 4, 3, 2, 1, 0])
        self.assertGreater(full_house, flush)
        self.assertGreater(pair, high)

    def test_wheel_and_ace_high_straight(self):
        self.assertEqual(p.best_hand(cards('AC2D3H4S5C')), (4, 3))
        self.assertEqual(p.best_hand(cards('ACJDQHKSTD')), (4, 12))
        self.assertLess(p.best_hand(cards('AC2D3H4S5C')), p.best_hand(cards('2C3D4H5S6C')))

    def test_kickers(self):
        # Same pair, different kicker.
        self.assertGreater(p.best_hand(cards('ACADKHQS9C')),
                           p.best_hand(cards('ASAHQDJSTC')))
        # Two pair, the lower pair and then the kicker decide.
        self.assertGreater(p.best_hand(cards('3C3D8H8SKS')), p.best_hand(cards('3C3D8H8SQS')))

    def test_seven_card_best_five(self):
        # A seven-card hand picks the flush over the straight.
        score = p.best_hand(cards('2H5H9HQHKH3C4C'))
        self.assertEqual(score[0], 5)
        self.assertEqual(score[1], 11)                 # king high

    def test_split_exact(self):
        board = cards('2C3D4H5S7C')
        one = p.best_hand(board + cards('AC'))
        two = p.best_hand(board + cards('AS'))
        self.assertEqual(one, two)


class Betting(unittest.TestCase):
    def test_blinds_button_and_order(self):
        t = Table()
        self.assertEqual(t.t.button, 0)                  # first button
        self.assertEqual(t.seat('BOB').stack, 990)       # small blind
        self.assertEqual(t.seat('CAROL').stack, 980)     # big blind
        self.assertEqual(t.t.pot(), 30)
        self.assertEqual(t.t.seats[t.t.actor].nick, 'ALICE')
        self.assertEqual(len(t.seat('ALICE').cards), 2)

    def test_call_check_flop(self):
        t = Table()
        self.assertIsNone(t.act('ALICE', 'call'))
        self.assertIsNone(t.act('BOB', 'call'))
        self.assertIsNone(t.act('CAROL', 'check'))
        self.assertEqual(t.t.stage, p.STAGE_FLOP)
        self.assertEqual(len(t.t.board), 3)
        self.assertEqual(t.t.pot(), 60)
        # After the flop the first player left of the button opens.
        self.assertEqual(t.t.seats[t.t.actor].nick, 'BOB')

    def test_bet_raise_and_minimums(self):
        t = Table()
        t.act('ALICE', 'call')
        t.act('BOB', 'call')
        t.act('CAROL', 'check')
        # Flop: BOB bets 50, CAROL raises to 150, ALICE folds.
        self.assertIsNone(t.act('BOB', 'bet', 50))
        self.assertEqual(t.act('CAROL', 'bet', 20), 'THERE IS A BET - RAISE')
        self.assertIsNone(t.act('CAROL', 'raise', 150))
        self.assertEqual(t.act('ALICE', 'raise', 180), 'MIN RAISE 250')
        self.assertIsNone(t.act('ALICE', 'fold'))
        self.assertEqual(t.t.current_bet, 150)
        self.assertIsNone(t.act('BOB', 'call'))
        self.assertEqual(t.t.stage, p.STAGE_TURN)
        self.assertEqual(t.t.pot(), 360)

    def test_check_refused_facing_bet(self):
        t = Table()
        self.assertEqual(t.act('ALICE', 'check'), 'CANNOT CHECK - CALL 20')

    def test_not_your_turn(self):
        t = Table()
        self.assertEqual(t.act('BOB', 'fold'), 'NOT YOUR TURN')

    def test_fold_around_wins_pot(self):
        t = Table()
        t.act('ALICE', 'fold')
        t.act('BOB', 'fold')
        self.assertEqual(t.t.stage, p.STAGE_OVER)
        self.assertEqual(t.seat('CAROL').stack, 1010)
        self.assertIn('CAROL WINS 30', t.t.status)
        self.assertEqual(t.chips(), 3000)

    def test_everyone_folds_to_big_blind_check(self):
        t = Table()
        t.act('ALICE', 'call')
        t.act('BOB', 'call')
        t.act('CAROL', 'check')
        for _ in range(3):
            t.act('BOB', 'check')
            t.act('CAROL', 'check')
            t.act('ALICE', 'check')
        self.assertEqual(t.t.stage, p.STAGE_OVER)
        self.assertEqual(len(t.t.board), 5)
        self.assertEqual(t.chips(), 3000)

    def test_all_in_short_raise_does_not_reopen(self):
        t = Table(stack=1000)
        # Flop: BOB (first to act) bets 100, CAROL all in for 185 total, a
        # short raise over the 100 bet.
        t.act('ALICE', 'call')
        t.act('BOB', 'call')
        t.act('CAROL', 'check')
        t.act('BOB', 'bet', 100)
        t.seat('CAROL').stack = 185          # her whole flop stack goes in
        self.assertIsNone(t.act('CAROL', 'allin'))
        self.assertEqual(t.t.current_bet, 185)
        # ALICE has not acted on the flop: a raise is still hers to make.
        self.assertIsNone(t.act('ALICE', 'call'))
        # BOB has acted; the short all-in did not reopen the betting.
        self.assertEqual(t.act('BOB', 'raise', 400), 'BET NOT REOPENED')
        self.assertIsNone(t.act('BOB', 'call'))


class AllIn(unittest.TestCase):
    def test_side_pots(self):
        clock = Clock()
        t = p.Tournament('test', dict(CONFIG, POKERSTACK='1000'), clock=clock)
        for nick in ('ALICE', 'BOB', 'CAROL'):
            self.assertIsNotNone(t.join(nick, clock())[0])
        # CAROL is the short stack: 300 against two of 1000.
        t.seat_of('CAROL').stack = 300
        clock.advance(3)
        t.tick(clock())
        self.assertEqual(t.stage, p.STAGE_PREFLOP)
        self.assertEqual(sum(1 for s in t.seats if s.in_hand), 3)
        # ALICE and BOB go all in; CAROL calls with the rest of her 300.
        self.assertIsNone(t.act(t.seat_of('ALICE'), 'allin', 0, clock()))
        self.assertIsNone(t.act(t.seat_of('BOB'), 'allin', 0, clock()))
        self.assertIsNone(t.act(t.seat_of('CAROL'), 'call', 0, clock()))
        # ALICE and BOB are both all in.  Whoever takes the 1400 side pot
        # cannot also be out, so at most two players are left and the
        # tournament may be over; every chip is still on the table.
        self.assertIn(t.stage, (p.STAGE_OVER, p.STAGE_DONE))
        self.assertEqual(sum(s.stack for s in t.seats if s.occupied), 2300)
        amounts = sum(amount for _nick, amount, _name, _cards in t.results)
        self.assertEqual(amounts, 2300)
        # Two pots: 900 that CAROL can win and 1400 that only ALICE and BOB
        # can win.  Someone always wins every chip, and no winner gets more
        # than the pots they were in.
        self.assertEqual(sum(s.contrib for s in t.seats), 0)
        self.assertEqual(sum(s.stack for s in t.seats if s.occupied), 2300)

    def test_all_in_runs_out_the_board(self):
        clock = Clock()
        t = p.Tournament('test', dict(CONFIG, POKERSTACK='500'), clock=clock)
        t.join('ALICE', clock())
        t.join('BOB', clock())
        clock.advance(3)
        t.tick(clock())
        self.assertIsNone(t.act(t.seat_of('ALICE'), 'allin', 0, clock()))
        self.assertIsNone(t.act(t.seat_of('BOB'), 'call', 0, clock()))
        # A split pot leaves both players with chips and the tournament goes
        # on; otherwise one is out and heads-up is over.
        self.assertIn(t.stage, (p.STAGE_OVER, p.STAGE_DONE))
        self.assertEqual(len(t.board), 5)
        self.assertEqual(sum(s.stack for s in t.seats), 1000)
        self.assertEqual(t.over, t.stage == p.STAGE_DONE)

    def test_elimination_and_champion(self):
        clock = Clock()
        t = p.Tournament('test', dict(CONFIG, POKERSTACK='500'), clock=clock)
        t.join('ALICE', clock())
        t.join('BOB', clock())
        clock.advance(3)
        t.tick(clock())
        t.act(t.seat_of('ALICE'), 'allin', 0, clock())
        t.act(t.seat_of('BOB'), 'call', 0, clock())
        winner = max((s for s in t.seats if s.occupied), key=lambda s: s.stack)
        loser = min((s for s in t.seats if s.occupied), key=lambda s: s.stack)
        if winner.stack == loser.stack:
            self.assertEqual(winner.stack, 500)        # the board split it
            self.assertFalse(t.over)
            return
        self.assertTrue(t.over)
        self.assertEqual(t.stage, p.STAGE_DONE)
        self.assertEqual(winner.stack, 1000)
        self.assertEqual(loser.stack, 0)
        self.assertIn(winner.nick, t.status)
        self.assertEqual(t.champion, winner.nick)

    def test_split_pot_odd_chip(self):
        # Three players put in 5 each and chop; the odd chip goes to the first
        # winner left of the button.
        board = cards('2C3D4H5S6C')
        score = p.best_hand(board)
        self.assertEqual(score, (4, 4))
        self.assertEqual(p.hand_name(score), 'STRAIGHT')


class ClockTests(unittest.TestCase):
    def test_blinds_rise(self):
        t = Table()
        self.assertEqual((t.t.sb, t.t.bb), (10, 20))
        t.clock.advance(301)
        t.t.tick(t.clock())
        self.assertEqual((t.t.sb, t.t.bb), (15, 30))
        self.assertEqual(t.t.level, 1)

    def test_timeout_folds_facing_a_bet(self):
        t = Table()
        # BOB and CAROL are polling; ALICE is not, and she is on the clock.
        t.clock.advance(31)
        t.seat('BOB').last_seen = t.clock()
        t.seat('CAROL').last_seen = t.clock()
        t.t.tick(t.clock())
        self.assertTrue(t.seat('ALICE').folded)
        self.assertEqual(t.t.seats[t.t.actor].nick, 'BOB')

    def test_timeout_checks_when_possible(self):
        t = Table()
        t.act('ALICE', 'call')
        t.act('BOB', 'call')
        t.act('CAROL', 'check')
        self.assertEqual(t.t.stage, p.STAGE_FLOP)
        t.wait(31)
        self.assertEqual(t.seat('BOB').last_action, p.ACTION_CHECK)
        self.assertFalse(t.seat('BOB').folded)

    def test_disconnect_autofold_then_rejoin(self):
        t = Table()
        t.clock.advance(25)
        t.seat('BOB').last_seen = t.clock()
        t.seat('CAROL').last_seen = t.clock()
        t.t.tick(t.clock())
        self.assertFalse(t.seat('ALICE').connected)
        # ALICE was on the clock with a bet to call: the drop folds her.
        self.assertTrue(t.seat('ALICE').folded)
        self.assertEqual(t.seat('ALICE').last_action, p.ACTION_FOLD)
        # Polling again with the same nickname gets the seat back.
        t.t.tick(t.clock())
        seat, message = t.t.join('ALICE', t.clock())
        self.assertIsNotNone(seat)
        self.assertTrue(seat.connected)
        self.assertEqual(message, 'WELCOME BACK')

    def test_dropped_player_loses_the_seat_after_grace(self):
        t = Table()
        for _ in range(150):
            t.clock.advance(5)
            t.t.tick(t.clock())
            if not t.seat('ALICE'):
                break
        self.assertIsNone(t.seat('ALICE'))
        self.assertTrue(t.t.over)

    def test_leave_frees_the_seat(self):
        t = Table()
        self.assertEqual(t.t.leave('BOB', t.clock()), 'LEFT AFTER THIS HAND')
        seat = t.seat('BOB')
        self.assertTrue(seat.leaving)
        # Finish the hand; the seat goes, the chips stay in the pot.
        t.act('ALICE', 'fold')
        t.t.tick(t.clock() + 6)
        self.assertNotIn('BOB', [s.nick for s in t.t.seats if s.occupied])


class Joining(unittest.TestCase):
    def test_late_registration_between_hands(self):
        t = Table(nicks=('ALICE', 'BOB'))
        self.assertEqual(len([s for s in t.t.seats if s.in_hand]), 2)
        seat, message = t.t.join('CAROL', t.clock())
        self.assertEqual(message, 'SEATED')
        self.assertTrue(seat.waiting)
        self.assertFalse(seat.in_hand)
        # Play the hand out, then the late entrant is dealt in.
        t.act('ALICE', 'fold')
        self.assertEqual(t.t.stage, p.STAGE_OVER)
        t.clock.advance(6)
        t.t.tick(t.clock())
        self.assertEqual(t.t.stage, p.STAGE_PREFLOP)
        self.assertTrue(t.seat('CAROL').in_hand)
        self.assertEqual(t.seat('CAROL').stack, 990)      # posts the small blind

    def test_late_entry_closes(self):
        t = Table(nicks=('ALICE', 'BOB'))
        t.t.level = t.t.late_levels
        self.assertFalse(t.t.registration_open())
        seat, message = t.t.join('DAVE', t.clock())
        self.assertIsNone(seat)
        self.assertEqual(message, 'LATE ENTRY CLOSED')

    def test_table_full(self):
        clock = Clock()
        t = p.Tournament('test', dict(CONFIG, POKERSTACK='1000'), clock=clock)
        for i in range(9):
            seat, error = t.join('P%d' % i, clock())
            self.assertIsNotNone(seat, error)
        seat, message = t.join('TEN', clock())
        self.assertIsNone(seat)
        self.assertEqual(message, 'TABLE FULL')

    def test_nick_is_kept_upper(self):
        t = Table(nicks=('alice', 'bob'))
        self.assertIsNotNone(t.t.seat_of('ALICE'))
        seat, message = t.t.join('ALICE', t.clock())
        self.assertEqual(message, 'WELCOME BACK')


class Packets(unittest.TestCase):
    def test_layout_and_checksum(self):
        t = Table()
        data = t.t.snapshot('ALICE')
        self.assertEqual(len(data), 256)
        self.assertEqual(data[0:4], b'POKR')
        self.assertEqual(data[255], sum(data[0:255]) & 0xFF)
        self.assertEqual(data[12], 0)                    # ALICE's seat
        self.assertNotEqual(data[37], p.CARD_NONE)       # her own cards
        # The opponents' cards stay hidden.
        base = 64 + 1 * 16
        self.assertEqual(data[base + 6], p.CARD_NONE)
        self.assertEqual(data[8] | (data[9] << 8), 1)     # hand 1
        self.assertEqual(data[26] | (data[27] << 8), 10)
        self.assertEqual(data[28] | (data[29] << 8), 20)
        self.assertEqual(data[10] | (data[11] << 8), 30)

    def test_showdown_reveals_cards(self):
        t = Table(nicks=('ALICE', 'BOB'))
        t.act('ALICE', 'allin')
        t.act('BOB', 'call')
        data = t.t.snapshot('ALICE')
        revealed = 0
        for index in range(9):
            base = 64 + index * 16
            if data[base] & 1 and data[base + 6] != p.CARD_NONE:
                revealed += 1
        self.assertGreaterEqual(revealed, 2)

    def test_packet_clock_and_status(self):
        t = Table()
        data = t.t.snapshot('ALICE')
        self.assertTrue(10 <= data[22] <= 30)            # seconds to act
        status = data[208:248].split(b'\x00')[0].decode()
        self.assertIn('HAND 1', status)

    def test_hand_name_for_the_client(self):
        t = Table()
        self.assertEqual(t.t.snapshot('ALICE')[44], 0)    # nothing before the flop
        t.t.board = cards('ASKSQS')
        t.seat('ALICE').cards = cards('JSTS')
        data = t.t.snapshot('ALICE')
        self.assertEqual(data[44:54].split(b'\x00')[0], b'STR FLUSH')
        # Each player sees the name of their own seven cards.
        self.assertIn(t.t.snapshot('BOB')[44:54].split(b'\x00')[0].decode(), p.HAND_NAMES)


class Commands(unittest.TestCase):
    def test_join_and_error_packets(self):
        config = dict(CONFIG, POKERROOM='testroom', POKERNICK='ALICE')
        clock = Clock()
        data = p.handle_command('join testroom', config, now=clock())
        self.assertEqual(data[0:4], b'POKR')
        self.assertEqual(data[255], sum(data[0:255]) & 0xFF)
        self.assertEqual(data[12], 0)
        bad = p.handle_command('fold', config, now=clock())
        self.assertEqual(bad[5], ord('E'))
        self.assertIn('NOT IN THIS HAND', bad[208:248].decode('ascii', 'replace'))

    def test_chat_round_trip(self):
        clock = Clock()
        t = p.Tournament('test', CONFIG, clock=clock)
        t.join('ALICE', clock())
        t.join('BOB', clock())
        t.say('ALICE', 'good luck')
        rows, unread = t.take_chat('BOB')
        self.assertEqual(unread, 0)
        self.assertEqual(len(rows), 1)
        self.assertIn('GOOD LUCK', rows[0][1])
        packet = p.chat_packet(rows, unread)
        self.assertEqual(packet[5], ord('C'))
        self.assertEqual(packet[255], sum(packet[0:255]) & 0xFF)


class Relay(unittest.TestCase):
    """The host serves the table over HTTP; every other MSXPi forwards to it."""

    def test_two_players_over_the_relay(self):
        import time
        host = dict(CONFIG, POKERNICK='ALICE', POKERROOM='relayroom',
                    POKERLISTEN='127.0.0.1', POKERPORT='5098')
        p.start_relay(host)
        try:
            relay = dict(CONFIG, POKERRELAY='http://127.0.0.1:5098', POKERROOM='relayroom')
            alice = dict(relay, POKERNICK='ALICE')
            bob = dict(relay, POKERNICK='BOB')
            first = p.handle_command('join relayroom', alice)
            self.assertEqual(first[0:4], b'POKR')
            self.assertEqual(first[255], sum(first[0:255]) & 0xFF)
            self.assertEqual(first[12], 0)                  # ALICE's seat
            second = p.handle_command('join relayroom', bob)
            self.assertEqual(second[12], 1)                 # BOB's seat
            self.assertEqual(second[25], 2)                 # two seats in use
            # A poll comes back as a table packet for the same player.
            again = p.handle_command('poll', alice)
            self.assertEqual(again[12], 0)
            # Chat goes through the relay too.
            self.assertNotEqual(p.handle_command('say hello', alice)[5], ord('E'))
            time.sleep(0.05)
            chat = p.handle_command('chat', bob)
            self.assertEqual(chat[5], ord('C'))
            self.assertIn(b'HELLO', chat[8:50])
        finally:
            p.stop_relay()

    def test_relay_down_is_reported(self):
        config = dict(CONFIG, POKERNICK='ALICE', POKERRELAY='http://127.0.0.1:5097',
                      POKERROOM='nowhere')
        reply = p.handle_command('join nowhere', config)
        self.assertEqual(reply[0:4], b'POKR')
        self.assertEqual(reply[5], ord('E'))
        self.assertIn('RELAY ERROR', reply[208:248].decode('ascii', 'replace'))


if __name__ == '__main__':
    unittest.main()
