"""PPOKER soak: seeded random-bot tournaments with chip and flow invariants.

Every tournament is driven by bots making random legal and illegal moves
through msxpi_poker.Tournament with an injected clock (no sleeping): bets and
raises of valid and out-of-range sizes, action-clock timeouts, players who stop
polling and come back inside POKERGRACE, one leave, and late joins while
registration is open.  After every step the invariants below are checked.

Run from software/Server/Python:
    python -m unittest tests.test_poker_soak -v

Chip accounting: a player who leaves (or loses the seat after POKERGRACE)
takes no chips with them - the engine drops the seat's stack - so the
conserved total is the chips bought in (POKERSTACK for every seat taken)
minus the stacks of the seats that were given up.
"""
import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_poker as p

SEEDS = range(300)          # one tournament per seed
MAX_HANDS = 150             # every tournament must end within this many hands
                            # (the longest of the 300 took 39 when written)
MAX_STEPS = 40000           # safety net on bot steps per tournament

CONFIG = {'POKERSTACK': '300', 'POKERACTIONSECS': '30', 'POKERLEVELSECS': '120',
          'POKERDROP': '20', 'POKERGRACE': '600', 'POKERHANDDELAY': '3', 'POKERLATE': '2'}

BETTING = (p.STAGE_PREFLOP, p.STAGE_FLOP, p.STAGE_TURN, p.STAGE_RIVER)


class Clock:
    def __init__(self, start=1000.0):
        self.t = start

    def __call__(self):
        return self.t


class Soak:
    """One seeded tournament and its bots."""

    def __init__(self, test, seed):
        self.test = test
        self.seed = seed
        self.rng = random.Random(seed)
        self.clock = Clock()
        self.t = p.Tournament('soak', CONFIG, clock=self.clock)
        self.t.rng = random.Random(seed ^ 0x5A5A)
        self.stack = int(CONFIG['POKERSTACK'])
        self.grace = int(CONFIG['POKERGRACE'])
        players = self.rng.randint(2, 9)
        self.nicks = ['P%d' % i for i in range(players)]
        first = self.rng.randint(1, players)
        self.waiting = self.nicks[first:]     # late entrants, not yet joined
        self.away = {}                         # nick -> time they stopped polling
        self.left = set()
        self.leaves = 1 if self.rng.random() < 0.6 else 0
        self.bought = 0
        self.forfeited = 0
        self.max_hands = 0
        self.step_no = 0
        for nick in self.nicks[:first]:
            self.join(nick)
        self.check('start')

    # -- bookkeeping ------------------------------------------------------
    def owners(self):
        return {s.number: (s.nick, s.stack) for s in self.t.seats if s.occupied}

    def run_op(self, what, op):
        """Run one engine call, account for seats given up, check invariants."""
        before = self.owners()
        result = op()
        after = self.owners()
        for number, (nick, stack) in before.items():
            if after.get(number, (None,))[0] != nick:
                self.forfeited += stack
        self.check(what)
        return result

    def join(self, nick):
        def op():
            seat, message = self.t.join(nick, self.clock())
            if message == 'SEATED':
                self.bought += self.stack
            return seat, message
        return self.run_op('join %s' % nick, op)

    # -- invariants --------------------------------------------------------
    def fail(self, what, text):
        self.test.fail('seed %d step %d (%s), stage %d hand %d: %s'
                       % (self.seed, self.step_no, what, self.t.stage, self.t.hand_no, text))

    def check(self, what):
        t = self.t
        chips = sum(s.stack for s in t.seats) + t.pot()
        if chips != self.bought - self.forfeited:
            self.fail(what, 'chips %d != bought %d - forfeited %d'
                      % (chips, self.bought, self.forfeited))
        for s in t.seats:
            if s.stack < 0 or s.bet < 0 or s.contrib < 0:
                self.fail(what, 'seat %d stack %d bet %d contrib %d'
                          % (s.number, s.stack, s.bet, s.contrib))
            if not s.occupied and s.stack:
                self.fail(what, 'empty seat %d holds %d chips' % (s.number, s.stack))
        betting = t.stage in BETTING
        if betting:
            if not 0 <= t.actor < p.MAX_SEATS:
                self.fail(what, 'street open with no actor (%d)' % t.actor)
            actor = t.seats[t.actor]
            if not t.still_playing(actor):
                self.fail(what, 'actor seat %d cannot act' % t.actor)
            if not t.needs_to_act(actor):
                self.fail(what, 'actor seat %d owes nothing' % t.actor)
        elif t.actor != -1:
            self.fail(what, 'actor %d outside a betting street' % t.actor)
        for viewer in [s for s in t.seats if s.occupied]:
            data = t.snapshot(viewer.nick)
            if len(data) != p.PACKET:
                self.fail(what, 'packet is %d bytes' % len(data))
            if data[0:4] != b'POKR':
                self.fail(what, 'bad magic %r' % data[0:4])
            if data[255] != sum(data[0:255]) & 0xFF:
                self.fail(what, 'bad checksum for %s' % viewer.nick)
            if data[12] != viewer.number:
                self.fail(what, 'packet seat %d for seat %d' % (data[12], viewer.number))
            acting = [i for i in range(p.MAX_SEATS) if data[64 + 16 * i] & 64]
            if betting and acting != [t.actor]:
                self.fail(what, 'acting seats in packet %r, actor %d' % (acting, t.actor))
            if not betting and acting:
                self.fail(what, 'acting seats %r outside a betting street' % acting)
            for s in t.seats:
                if s.number == viewer.number:
                    continue
                shown = data[64 + 16 * s.number + 6:64 + 16 * s.number + 8]
                if shown == b'\xff\xff':
                    continue
                # Cards of others only after a showdown (they stay on the
                # result screen until the next deal), and only if shown.
                if betting or not s.showing:
                    self.fail(what, 'seat %d cards %r visible to %s'
                              % (s.number, bytes(shown), viewer.nick))

    # -- the bots ----------------------------------------------------------
    def present(self):
        """Seated players whose bot is still polling."""
        return [s for s in self.t.seats
                if s.occupied and s.nick not in self.away and s.nick not in self.left]

    def amount(self, seat):
        t = self.t
        top = seat.stack + seat.bet
        minimum = t.current_bet + t.min_raise if t.current_bet else t.bb
        choice = self.rng.random()
        if choice < 0.55 and top >= 1:
            low = min(minimum, top)
            return self.rng.randint(low, top)           # valid
        if choice < 0.65:
            return self.rng.choice((0, -5, -1))           # nonsense
        if choice < 0.8:
            return top + self.rng.randint(1, 5000)        # more than the stack
        if choice < 0.9 and minimum > 1:
            return self.rng.randint(1, minimum - 1)       # under the minimum
        return self.rng.choice(('x', None, '12', 3.7))    # not a number

    def move(self, seat):
        action = self.rng.choices(('fold', 'check', 'call', 'bet', 'raise', 'allin', 'dance'),
                                  (8, 25, 30, 12, 12, 4, 1))[0]
        amount = self.amount(seat) if action in ('bet', 'raise') else 0
        self.run_op('%s %s %r' % (seat.nick, action, amount),
                    lambda: self.t.act(seat, action, amount, self.clock()))

    def advance(self, seconds):
        self.clock.t += seconds
        self.run_op('tick +%s' % seconds, lambda: self.t.tick(self.clock()))

    def poll_all(self):
        now = self.clock()
        for seat in self.present():
            seat.last_seen = now
            seat.connected = True

    def step(self):
        self.step_no += 1
        t, rng = self.t, self.rng
        roll = rng.random()
        now = self.clock()
        # Players who walked away come back inside the grace period.
        for nick, since in list(self.away.items()):
            if now - since > self.grace - 60 or rng.random() < 0.02:
                del self.away[nick]
                if t.seat_of(nick) is not None:
                    self.join(nick)
        if t.hand_no == 0 and len(self.present()) < 2 and self.waiting:
            # A host alone waits for the others; the next player arrives.
            self.join(self.waiting.pop(0))
        elif t.stage in BETTING and roll < 0.75:
            actor = t.seats[t.actor]
            if actor.nick in self.away:
                self.advance(rng.choice((5, 31)))              # their clock runs
            else:
                self.move(actor)
        elif roll < 0.80 and t.stage in BETTING:
            # Somebody acts out of turn, or a folded player tries again.
            seat = rng.choice([s for s in t.seats if s.occupied])
            self.run_op('out of turn %s' % seat.nick,
                        lambda: t.act(seat, rng.choice(('call', 'check', 'raise')),
                                      rng.randint(-10, 5000), self.clock()))
        elif roll < 0.84:
            self.advance(int(t.action_seconds) + 1)            # an action-clock timeout
        elif roll < 0.86:
            present = [s for s in self.present()]
            if present:
                self.away[rng.choice(present).nick] = now       # stops polling
        elif roll < 0.87 and self.leaves and t.hand_no > 0:
            present = self.present()
            if present:
                nick = rng.choice(present).nick
                self.leaves -= 1
                self.left.add(nick)
                self.run_op('leave %s' % nick, lambda: t.leave(nick, self.clock()))
        elif roll < 0.90 and self.waiting:
            nick = self.waiting.pop(0)
            seat, message = self.join(nick)
            if not t.registration_open() and message != 'LATE ENTRY CLOSED':
                self.fail('late join', 'join after registration closed: %s' % message)
        else:
            self.advance(rng.choice((1, 2, 3)))
        self.poll_all()

    def run(self):
        while not self.t.over:
            if self.step_no >= MAX_STEPS:
                self.fail('run', 'no champion after %d steps' % MAX_STEPS)
            if self.t.hand_no > MAX_HANDS:
                self.fail('run', 'no champion after %d hands' % MAX_HANDS)
            self.step()
        t = self.t
        self.test.assertEqual(t.stage, p.STAGE_DONE, 'seed %d' % self.seed)
        holders = [s for s in t.seats if s.stack > 0]
        self.test.assertEqual(len(holders), 1, 'seed %d: holders %r'
                              % (self.seed, [(s.nick, s.stack) for s in holders]))
        self.test.assertEqual(holders[0].stack, self.bought - self.forfeited, 'seed %d' % self.seed)
        self.test.assertEqual(t.champion, holders[0].nick, 'seed %d' % self.seed)
        self.test.assertEqual(t.pot(), 0, 'seed %d' % self.seed)
        return t.hand_no


# Seeds that fail on a known server bug, skipped until it is fixed (add
# @unittest.skip by listing the seed here, with the bug's card in KNOWN_BUG).
# The dead-money loss in Tournament.award was fixed by PP-UNCALLED-BET.
KNOWN_BUG = 'PP-SOAK known server bug, seed %d'
DEAD_MONEY_SEEDS = set()


class SoakTest(unittest.TestCase):
    """One test per seed, so a failure names its seed."""


def _make(seed):
    def test(self):
        hands = Soak(self, seed).run()
        self.assertLessEqual(hands, MAX_HANDS)
    if seed in DEAD_MONEY_SEEDS:
        test = unittest.skip(KNOWN_BUG % seed)(test)
    return test


for _seed in SEEDS:
    setattr(SoakTest, 'test_seed_%03d' % _seed, _make(_seed))
del _seed

if __name__ == '__main__':
    unittest.main()
