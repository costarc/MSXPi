"""PPOKER: a nine-seat no-limit Texas Hold'em tournament for MSXPi.

The Pi is the dealer: the MSX client (software/Client/src/ppoker.c) draws the
table and sends the player's actions; every rule lives here, so a client
cannot deal itself a card or move chips it does not have.  One MSXPi hosts a
table (its `poker host ROOM` starts the relay and the first join creates the
tournament); the other eight players point POKERRELAY at the host's
POKERLISTEN:POKERPORT and join the same room.

A tournament, not a cash game: everyone starts with the same stack, blinds
rise on a clock, and a player with no chips is out.  What it implements:

* blinds, the dealer button, and a full betting round on each street, with
  the big blind's option, minimum bets and raises, and all-in for less;
* no-limit bets and raises, and side pots when all-ins are unequal;
* showdown with a best-five-of-seven evaluator, split pots and odd chips;
* elimination, blind levels, and the end of the tournament;
* late registration (`POKERLATE` levels), joining between hands, and a
  seat that is held while a player is disconnected: they are blinded off
  and auto-folded, and get their seat back by polling again with the same
  nickname, until `POKERGRACE` seconds have passed.

The table state the MSX reads is one fixed 256-byte packet (packet layout
below), which is the size the MSXPi link already carries for PCHESS.  The
relay holds one tournament per room for a day, keyed by room name.
"""
import collections
import json
import os
import random
import re
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen

MAX_SEATS = 9
PACKET = 256

# One card is one byte: (rank-2)*4 + suit.  Rank 0..12 is 2..A, suit 0..3 is
# clubs, diamonds, hearts, spades - the order PPOKER's card tiles use.
CARD_NONE = 0xFF
RANK_NAMES = ('2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A')
SUIT_NAMES = ('C', 'D', 'H', 'S')

ACTION_NONE, ACTION_FOLD, ACTION_CHECK, ACTION_CALL, ACTION_BET, ACTION_RAISE, ACTION_ALLIN = range(7)
ACTION_TEXT = ('', 'FOLD', 'CHECK', 'CALL', 'BET', 'RAISE', 'ALLIN')

STAGE_NONE, STAGE_PREFLOP, STAGE_FLOP, STAGE_TURN, STAGE_RIVER, STAGE_SHOWDOWN, STAGE_OVER, STAGE_DONE = range(8)
STAGE_TEXT = ('WAIT', 'PREFLOP', 'FLOP', 'TURN', 'RIVER', 'SHOWDOWN', 'HAND OVER', 'TOURNAMENT OVER')

HAND_NAMES = ('HIGH CARD', 'PAIR', 'TWO PAIR', 'TRIPS', 'STRAIGHT', 'FLUSH',
              'FULL HOUSE', 'QUADS', 'STR FLUSH')


# What the client's 5x7 font can draw, so what a chat line may contain.
CHAT_CHARS = frozenset('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -:+#=().?!,/' + chr(39))


def card_name(card):
    if card == CARD_NONE:
        return '--'
    return RANK_NAMES[card >> 2] + SUIT_NAMES[card & 3]


# ---------------------------------------------------------------- the hands

def _straight_high(ranks):
    """Highest straight top rank in a set, ace low allowed, or None."""
    unique = sorted(set(ranks), reverse=True)
    if 12 in unique:                 # the ace also plays low
        unique.append(-1)
    for i in range(len(unique) - 4):
        if unique[i] - unique[i + 4] == 4:
            return unique[i]
    return None


def best_hand(cards):
    """Score the best five of five to seven cards; bigger tuples win."""
    ranks = [c >> 2 for c in cards]
    suits = [c & 3 for c in cards]
    counts = collections.Counter(ranks)
    by_count = sorted(counts.items(), key=lambda item: (item[1], item[0]), reverse=True)

    flush_suit = next((s for s in set(suits) if suits.count(s) >= 5), None)
    if flush_suit is not None:
        flush_ranks = sorted((c >> 2 for c in cards if (c & 3) == flush_suit), reverse=True)
        high = _straight_high(flush_ranks)
        if high is not None:
            return (8, high)
        return (5,) + tuple(flush_ranks[:5])

    high = _straight_high(ranks)
    if by_count[0][1] == 4:
        quad = by_count[0][0]
        kicker = max(r for r in ranks if r != quad)
        return (7, quad, kicker)
    if by_count[0][1] == 3 and by_count[1][1] >= 2:
        trips = max(r for r, n in counts.items() if n >= 3)
        pair = max(r for r, n in counts.items() if n >= 2 and r != trips)
        return (6, trips, pair)
    if high is not None:
        return (4, high)
    if by_count[0][1] == 3:
        trips = by_count[0][0]
        kickers = [r for r in ranks if r != trips]
        kickers.sort(reverse=True)
        return (3, trips) + tuple(kickers[:2])
    pairs = sorted((r for r, n in counts.items() if n >= 2), reverse=True)
    if len(pairs) >= 2:
        kicker = max((r for r in ranks if r not in pairs[:2]), default=-1)
        return (2, pairs[0], pairs[1], kicker)
    if pairs:
        kickers = sorted((r for r in ranks if r != pairs[0]), reverse=True)
        return (1, pairs[0]) + tuple(kickers[:3])
    return (0,) + tuple(sorted(ranks, reverse=True)[:5])


def hand_name(score):
    return HAND_NAMES[score[0]]


# ---------------------------------------------------------------- the table

class Seat:
    def __init__(self, number):
        self.number = number
        self.nick = ''
        self.stack = 0
        self.occupied = False
        self.connected = True
        self.last_seen = 0.0
        self.in_hand = False
        self.folded = False
        self.all_in = False
        self.leaving = False
        self.waiting = False          # seated, waiting for the next hand
        self.cards = []
        self.bet = 0                  # chips put in this betting round
        self.contrib = 0              # chips put in this hand (side pots)
        self.acted = False
        self.last_action = ACTION_NONE
        self.last_amount = 0
        self.showing = False
        self.best = None

    def pack_hand(self):
        """After a hand: the betting state goes, the shown cards stay for
        the result screen until the next hand is dealt."""
        self.in_hand = False
        self.folded = False
        self.all_in = False
        self.bet = 0
        self.contrib = 0
        self.acted = False

    def clear_hand(self):
        self.in_hand = False
        self.folded = False
        self.all_in = False
        self.cards = []
        self.bet = 0
        self.contrib = 0
        self.acted = False
        self.last_action = ACTION_NONE
        self.last_amount = 0
        self.showing = False
        self.best = None


class Tournament:
    """One table.  Every public method takes the caller's clock (`now`)."""

    def __init__(self, room, config=None, clock=time.monotonic):
        config = config or {}
        self.room = room
        self.lock = threading.RLock()
        self.clock = clock
        self.start_stack = int(config.get('POKERSTACK') or 1500)
        self.level_seconds = int(config.get('POKERLEVELSECS') or 300)
        self.late_levels = int(config.get('POKERLATE') or 4)
        self.action_seconds = int(config.get('POKERACTIONSECS') or 45)
        self.drop_seconds = int(config.get('POKERDROP') or 20)
        self.grace_seconds = int(config.get('POKERGRACE') or 600)
        self.hand_delay = int(config.get('POKERHANDDELAY') or 6)
        self.blinds = [(10, 20), (15, 30), (25, 50), (50, 100), (75, 150),
                       (100, 200), (150, 300), (200, 400), (300, 600)]
        self.rng = random.Random(secrets.randbits(32))
        self.seats = [Seat(n) for n in range(MAX_SEATS)]
        self.button = MAX_SEATS - 1
        self.level = 0
        self.level_started = clock()
        self.hand_no = 0
        self.stage = STAGE_NONE
        self.board = []
        self.deck = []
        self.current_bet = 0
        self.min_raise = self.blinds[0][1]
        self.actor = -1
        self.action_deadline = 0.0
        self.next_hand_at = 0.0
        self.reopened = True
        self.action_seq = 0
        self.chat = {}                 # nick -> deque of (private, row)
        self.status = 'WAIT FOR PLAYERS'
        self.results = []              # this hand's winners, for the status
        self.started = False
        self.over = False
        self.champion = ''
        self.last_status = ''

    # -- helpers ---------------------------------------------------------
    @property
    def sb(self):
        return self.blinds[min(self.level, len(self.blinds) - 1)][0]

    @property
    def bb(self):
        return self.blinds[min(self.level, len(self.blinds) - 1)][1]

    def seat_of(self, nick):
        for seat in self.seats:
            if seat.occupied and seat.nick.upper() == nick.upper():
                return seat
        return None

    def in_tournament(self):
        return [s for s in self.seats if s.occupied and s.stack > 0 and not s.leaving]

    def contenders(self):
        return [s for s in self.seats if s.in_hand and not s.folded]

    def live(self):
        return [s for s in self.contenders() if not s.all_in]

    def pot(self):
        return sum(s.contrib for s in self.seats)

    def next_seat(self, start, predicate):
        """The first seat after `start` whose predicate passes, and its index."""
        for step in range(1, MAX_SEATS + 1):
            index = (start + step) % MAX_SEATS
            if predicate(self.seats[index]):
                return self.seats[index]
        return None

    def still_playing(self, seat):
        return seat.in_hand and not seat.folded and not seat.all_in

    def registration_open(self):
        return not self.over and self.level < self.late_levels

    def free_seat(self):
        for seat in self.seats:
            if not seat.occupied:
                return seat
        return None

    # -- joining and leaving --------------------------------------------
    def join(self, nick, now):
        """Sit down, rejoin a held seat, or come back to the table."""
        nick = (nick or '').strip()[:12].upper()
        if not nick:
            return None, 'Choose a nickname first (POKERNICK)'
        seat = self.seat_of(nick)
        if seat is not None:
            seat.connected = True
            seat.last_seen = now
            seat.leaving = False
            if self.over and seat.stack > 0:
                self.status = 'TOURNAMENT OVER - %s WON' % self.champion
            elif seat.waiting:
                self.status = 'SEATED - HAND STARTS SOON'
            else:
                self.status = 'WELCOME BACK %s' % nick
            return seat, 'WELCOME BACK'
        if self.over:
            return None, 'TOURNAMENT OVER - HOST NEW'
        if not self.registration_open():
            return None, 'LATE ENTRY CLOSED'
        seat = self.free_seat()
        if seat is None:
            # A busted player still holds their seat so they can watch the
            # rest of the tournament; a late entrant may take it instead.
            seat = next((s for s in self.seats if s.occupied and s.stack <= 0 and
                         not s.in_hand and not s.leaving), None)
        if seat is None:
            return None, 'TABLE FULL'
        seat.clear_hand()
        seat.occupied = True
        seat.nick = nick
        seat.stack = self.start_stack
        seat.connected = True
        seat.last_seen = now
        seat.waiting = True
        seat.leaving = False
        self.started = True
        self.status = '%s SEATED - HAND STARTS SOON' % nick
        if self.stage in (STAGE_NONE, STAGE_OVER, STAGE_DONE) and self.next_hand_at == 0:
            self.next_hand_at = now + 2
        return seat, 'SEATED'

    def leave(self, nick, now):
        seat = self.seat_of(nick)
        if seat is None:
            return 'NOT SEATED'
        # A player who leaves mid-hand is folded now and their chips stay in
        # the pot; the seat is freed when the hand ends.
        if seat.in_hand:
            seat.leaving = True
            if not seat.folded:
                self.fold(seat, now)
            return 'LEFT AFTER THIS HAND'
        seat.clear_hand()
        seat.occupied = False
        seat.nick = ''
        seat.stack = 0
        seat.waiting = False
        self.status = 'PLAYER LEFT'
        return 'LEFT'

    def drop_seat(self, seat):
        seat.clear_hand()
        seat.occupied = False
        seat.nick = ''
        seat.stack = 0
        seat.waiting = False
        seat.connected = False

    # -- the hand --------------------------------------------------------
    def start_hand(self, now):
        players = self.in_tournament()
        if len(players) < 2:
            if self.hand_no == 0:
                # A host opens a table before the others arrive: wait for a
                # second player instead of crowning the host.  Only a
                # tournament that has dealt a hand ends down to one player.
                self.status = 'WAITING FOR PLAYERS'
                self.next_hand_at = now + 2 if players else 0.0
                return
            self.end_tournament()
            return
        self.hand_no += 1
        self.board = []
        self.deck = list(range(52))
        self.rng.shuffle(self.deck)
        for seat in self.seats:
            seat.clear_hand()
        for seat in players:
            seat.in_hand = True
            seat.waiting = False
        self.stage = STAGE_PREFLOP
        # Deal in seat order from the button, two cards each.
        order = []
        seat = self.next_seat(self.button, lambda s: s.in_hand)
        while seat is not None and seat not in order:
            order.append(seat)
            seat = self.next_seat(seat.number, lambda s: s.in_hand)
        for _ in range(2):
            for seat in order:
                seat.cards.append(self.deck.pop())
        # The button moves to the next seat that is playing.
        button = self.next_seat(self.button, lambda s: s.in_hand)
        if button is not None:
            self.button = button.number
        if len(order) == 2:
            # Heads-up: the button posts the small blind and acts first.
            sb_seat = self.seat_at(self.button)
            bb_seat = self.next_seat(self.button, lambda s: s.in_hand)
        else:
            sb_seat = self.next_seat(self.button, lambda s: s.in_hand)
            bb_seat = self.next_seat(sb_seat.number, lambda s: s.in_hand)
        self.post_blind(sb_seat, self.sb)
        self.post_blind(bb_seat, self.bb)
        self.current_bet = self.bb
        self.min_raise = self.bb
        self.reopened = True
        for seat in self.seats:
            seat.acted = False
        first = self.next_seat(bb_seat.number, self.still_playing)
        self.actor = first.number if first is not None else -1
        self.action_deadline = now + self.action_seconds
        self.next_hand_at = 0.0
        self.status = 'HAND %d - PREFLOP' % self.hand_no
        self.results = []
        self.touch()
        self.check_round_end(now)

    def seat_at(self, number):
        return self.seats[number]

    def post_blind(self, seat, amount):
        if seat is None:
            return
        paid = min(amount, seat.stack)
        seat.stack -= paid
        seat.bet += paid
        seat.contrib += paid
        if seat.stack == 0:
            seat.all_in = True

    def touch(self):
        self.action_seq = (self.action_seq + 1) % 250

    def check_round_end(self, now):
        """Settle a betting round that is already complete (all-ins, calls)."""
        while True:
            contenders = self.contenders()
            if len(contenders) <= 1:
                self.settle_hand(now)
                return
            live = self.live()
            complete = all(s.acted and s.bet == self.current_bet for s in live)
            if live and not complete:
                # Move to the next player who still owes something.
                if self.actor < 0 or not self.needs_to_act(self.seats[self.actor]):
                    nxt = self.next_seat(self.actor if self.actor >= 0 else self.button,
                                         self.needs_to_act)
                    self.actor = nxt.number if nxt is not None else -1
                    self.action_deadline = now + self.action_seconds
                if self.actor >= 0:
                    return
                continue
            # The street is over.
            if self.stage == STAGE_RIVER:
                self.showdown(now)
                return
            self.begin_street(now)
            # Everyone all in: the loop deals the flop, turn and river before
            # the showdown, with nobody left to act.

    def needs_to_act(self, seat):
        return (seat.in_hand and not seat.folded and not seat.all_in and
                (not seat.acted or seat.bet < self.current_bet))

    def begin_street(self, now):
        for seat in self.seats:
            seat.bet = 0
            seat.acted = False
        self.current_bet = 0
        self.min_raise = self.bb
        self.reopened = True
        self.stage += 1
        self.deal_board()
        first = self.next_seat(self.button, self.still_playing)
        self.actor = first.number if first is not None else -1
        self.action_deadline = now + self.action_seconds
        self.status = 'HAND %d - %s' % (self.hand_no, STAGE_TEXT[self.stage])
        if self.actor >= 0:
            self.seats[self.actor].acted = False

    def deal_board(self):
        if self.stage == STAGE_FLOP:
            self.deck.pop()                 # burn
            self.board += [self.deck.pop() for _ in range(3)]
        elif self.stage in (STAGE_TURN, STAGE_RIVER):
            self.deck.pop()
            self.board.append(self.deck.pop())

    def showdown(self, now):
        self.stage = STAGE_SHOWDOWN
        board = self.board
        contenders = self.contenders()
        for seat in contenders:
            seat.best = best_hand(seat.cards + board) if len(seat.cards) == 2 else None
            seat.showing = True
        self.award(now)

    def award(self, now):
        """Split the pot (and side pots) among the best hands."""
        contenders = [s for s in self.contenders() if s.best is not None]
        self.results = []
        if not contenders:
            self.settle_hand(now)
            return
        # A walkover: everyone else folded, so nobody has to show.
        if len(contenders) == 1:
            winner = contenders[0]
            amount = self.pot()
            winner.stack += amount
            winner.showing = False
            self.results = [(winner.nick, amount, '', [])]
            self.finish_hand(now, '%s WINS %d' % (winner.nick, amount))
            return
        # Side pots: every distinct contribution level is one pot, and only
        # players who put in at least that much can win it.
        levels = sorted({s.contrib for s in self.seats if s.contrib > 0})
        previous = 0
        for level in levels:
            amount = sum(max(0, min(s.contrib, level) - min(s.contrib, previous))
                         for s in self.seats)
            eligible = [s for s in contenders if s.contrib >= level]
            previous = level
            if amount <= 0 or not eligible:
                continue
            best = max(s.best for s in eligible)
            winners = [s for s in eligible if s.best == best]
            share, odd = divmod(amount, len(winners))
            # Loose chips go to the first winner left of the button.
            ordered = self.from_button(winners)
            for index, winner in enumerate(ordered):
                won = share + (1 if index < odd else 0)
                winner.stack += won
                self.results.append((winner.nick, won, hand_name(winner.best),
                                     [card_name(c) for c in winner.cards]))
        parts = []
        for nick, amount, name, _cards in self.results:
            parts.append('%s WINS %d %s' % (nick, amount, name))
        self.finish_hand(now, ' / '.join(parts)[:39])

    def from_button(self, seats):
        """Sort seats clockwise from the button (odd-chip order)."""
        return sorted(seats, key=lambda s: (s.number - self.button - 1) % MAX_SEATS)

    def finish_hand(self, now, status):
        self.stage = STAGE_OVER
        self.actor = -1
        self.action_deadline = 0.0
        self.status = status.upper()
        self.touch()
        for seat in self.seats:
            if not seat.occupied:
                continue
            if seat.leaving:
                # A player who left mid-hand gives up their seat now.
                self.drop_seat(seat)
                continue
            # Busted players keep the seat (and the result on screen) with a
            # zero stack: they are out of the tournament but can watch, and a
            # late entrant may take the seat.  The cards of the players who
            # showed stay visible until the next hand is dealt.
            seat.pack_hand()
            seat.waiting = False
        if len(self.in_tournament()) < 2:
            self.next_hand_at = now + self.hand_delay
            self.end_tournament()
            return
        self.next_hand_at = now + self.hand_delay

    def end_tournament(self):
        players = [s for s in self.seats if s.occupied and s.stack > 0]
        self.over = True
        self.stage = STAGE_DONE
        self.actor = -1
        if players:
            self.champion = max(players, key=lambda s: s.stack).nick
            self.status = '%s WINS THE TOURNAMENT' % self.champion
        else:
            self.champion = ''
            self.status = 'TOURNAMENT OVER'
        self.next_hand_at = 0.0
        self.touch()

    def settle_hand(self, now):
        """Only one player is left in the hand: they take it without showing."""
        self.showdown(now)

    # -- actions ---------------------------------------------------------
    def act(self, seat, action, amount, now):
        """Apply one action from a seated player.  Returns an error or None."""
        if self.over or self.stage in (STAGE_DONE,):
            return 'TOURNAMENT OVER'
        if not seat.in_hand or seat.folded or seat.all_in:
            return 'NOT IN THIS HAND'
        if self.actor != seat.number:
            return 'NOT YOUR TURN'
        to_call = max(0, self.current_bet - seat.bet)
        try:
            amount = int(amount or 0)
        except (TypeError, ValueError):
            return 'BAD AMOUNT'
        if action == 'fold':
            self.fold(seat, now)
            return None
        if action == 'check':
            if to_call > 0:
                return 'CANNOT CHECK - CALL %d' % to_call
            seat.last_action = ACTION_CHECK
            seat.last_amount = 0
        elif action == 'call':
            if to_call <= 0:
                return 'NOTHING TO CALL - CHECK'
            paid = min(to_call, seat.stack)
            self.pay(seat, paid)
            seat.last_action = ACTION_ALLIN if seat.all_in else ACTION_CALL
            seat.last_amount = paid
        elif action in ('bet', 'raise', 'allin') and seat.acted and not self.reopened:
            return 'BET NOT REOPENED'
        elif action in ('bet', 'raise'):
            if action == 'bet' and self.current_bet > 0:
                return 'THERE IS A BET - RAISE'
            if action == 'raise' and self.current_bet == 0:
                return 'NO BET TO RAISE - BET'
            target = amount
            if target <= 0:
                return 'BAD AMOUNT'
            if action == 'bet':
                minimum = min(self.bb, seat.stack + seat.bet)
                if target < minimum and target < seat.stack + seat.bet:
                    return 'MIN BET %d' % minimum
            else:
                minimum = self.current_bet + self.min_raise
                if target < minimum and target < seat.stack + seat.bet:
                    return 'MIN RAISE %d' % minimum
            total = seat.bet + seat.stack
            if target > total:
                return 'NOT ENOUGH CHIPS'
            paid = min(target - seat.bet, seat.stack)
            raise_size = target - self.current_bet
            self.pay(seat, paid)
            if raise_size >= self.min_raise:
                # A full raise reopens the betting for everyone.
                self.min_raise = raise_size
                self.reopened = True
                for other in self.seats:
                    if other is not seat:
                        other.acted = False
            else:
                # An all-in for less: players who already acted may call the
                # difference but may not raise again.
                self.reopened = False
            self.current_bet = max(self.current_bet, seat.bet)
            seat.last_action = (ACTION_ALLIN if seat.all_in else
                                ACTION_RAISE if action == 'raise' else ACTION_BET)
            seat.last_amount = seat.bet
        elif action == 'allin':
            if seat.stack <= 0:
                return 'NO CHIPS'
            paid = seat.stack
            target = seat.bet + paid
            raise_size = target - self.current_bet
            self.pay(seat, paid)
            if target > self.current_bet:
                if raise_size >= self.min_raise:
                    self.min_raise = raise_size
                    self.reopened = True
                    for other in self.seats:
                        if other is not seat:
                            other.acted = False
                else:
                    self.reopened = False
                self.current_bet = target
            seat.last_action = ACTION_ALLIN
            seat.last_amount = target
        else:
            return 'UNKNOWN ACTION'
        seat.acted = True
        self.touch()
        self.status = ('%s %s %d' % (seat.nick, ACTION_TEXT[seat.last_action],
                                     seat.last_amount) if seat.last_amount else
                       '%s %s' % (seat.nick, ACTION_TEXT[seat.last_action]))
        if len(self.contenders()) <= 1:
            self.showdown(now)
            return None
        nxt = self.next_seat(seat.number, self.needs_to_act)
        if nxt is not None:
            self.actor = nxt.number
            self.action_deadline = now + self.action_seconds
            return None
        # Nobody else can act.  With everyone all in, check_round_end deals
        # the rest of the board before the showdown.
        self.check_round_end(now)
        return None

    def pay(self, seat, amount):
        paid = max(0, min(amount, seat.stack))
        seat.stack -= paid
        seat.bet += paid
        seat.contrib += paid
        if seat.stack == 0:
            seat.all_in = True
        return paid

    def fold(self, seat, now):
        seat.folded = True
        seat.acted = True
        seat.last_action = ACTION_FOLD
        seat.last_amount = 0
        seat.showing = False
        self.touch()
        self.status = '%s FOLDS' % seat.nick
        if len(self.contenders()) <= 1:
            self.showdown(now)
            return
        if self.actor == seat.number:
            nxt = self.next_seat(seat.number, self.needs_to_act)
            if nxt is not None:
                self.actor = nxt.number
                self.action_deadline = now + self.action_seconds
                return
            self.check_round_end(now)

    # -- the clock -------------------------------------------------------
    def tick(self, now):
        """Advance timers: blind level, disconnects, action timeouts, hands."""
        with self.lock:
            if self.stage == STAGE_DONE:
                return
            if now - self.level_started >= self.level_seconds:
                while now - self.level_started >= self.level_seconds:
                    self.level_started += self.level_seconds
                    if self.level < len(self.blinds) - 1:
                        self.level += 1
                if self.stage == STAGE_NONE:
                    self.status = 'BLINDS %d/%d' % (self.sb, self.bb)
            for seat in self.seats:
                if not seat.occupied:
                    continue
                if seat.connected and now - seat.last_seen > self.drop_seconds:
                    seat.connected = False
                    if seat.in_hand and self.actor == seat.number:
                        self.auto_act(seat, now)
                        continue
                if not seat.connected and now - seat.last_seen > self.grace_seconds:
                    # Out of the tournament, but a hand in progress keeps the
                    # chips the seat already put in the pot: fold and give the
                    # seat up when the hand ends.
                    seat.leaving = True
                    if seat.in_hand and not seat.folded:
                        self.fold(seat, now)
                    elif not seat.in_hand:
                        self.drop_seat(seat)
            if self.stage in (STAGE_PREFLOP, STAGE_FLOP, STAGE_TURN, STAGE_RIVER) \
                    and self.actor >= 0 and now >= self.action_deadline:
                self.auto_act(self.seats[self.actor], now)
            elif self.stage in (STAGE_NONE, STAGE_OVER) and self.next_hand_at and now >= self.next_hand_at:
                self.start_hand(now)

    def auto_act(self, seat, now):
        seat.connected = False
        to_call = max(0, self.current_bet - seat.bet)
        if to_call > 0:
            self.fold(seat, now)
        else:
            error = self.act(seat, 'check', 0, now)
            if error:
                self.fold(seat, now)

    # -- the packet ------------------------------------------------------
    def snapshot(self, nick):
        seat = self.seat_of(nick)
        data = bytearray(PACKET)
        data[0:4] = b'POKR'
        data[4] = 1
        data[5] = 1
        data[6] = self.stage
        data[7] = self.player_flags(seat)
        data[8] = self.hand_no & 0xFF
        data[9] = (self.hand_no >> 8) & 0xFF
        pot = min(self.pot(), 0xFFFF)
        data[10] = pot & 0xFF
        data[11] = pot >> 8
        data[12] = seat.number if seat is not None else 0xFF
        data[13] = self.action_seq
        to_call = max(0, self.current_bet - seat.bet) if seat is not None else 0
        self.put16(data, 14, min(to_call, 0xFFFF))
        minimum = (self.current_bet + self.min_raise) if self.current_bet else self.bb
        if seat is not None:
            minimum = min(minimum, seat.stack + seat.bet)
        self.put16(data, 16, min(max(1, minimum), 0xFFFF))
        self.put16(data, 18, seat.stack if seat is not None else 0)
        self.put16(data, 20, seat.bet if seat is not None else 0)
        left = 0
        if self.actor >= 0 and self.action_deadline:
            left = max(0, min(255, int(self.action_deadline - self.clock() + 0.999)))
        data[22] = left
        # Players left: a player all in this hand has no stack but is not
        # out yet, so in_tournament() (stack > 0) would undercount.
        players_left = sum(1 for s in self.seats if s.occupied and not s.leaving and
                           (s.stack > 0 or (s.in_hand and not s.folded)))
        data[23] = min(255, players_left)
        data[24] = self.level + 1
        data[25] = sum(1 for s in self.seats if s.occupied)
        self.put16(data, 26, self.sb)
        self.put16(data, 28, self.bb)
        data[30] = (1 if self.registration_open() else 0) | (2 if self.stage == STAGE_OVER else 0) | \
                   (4 if self.stage == STAGE_SHOWDOWN else 0)
        for i in range(5):
            data[32 + i] = self.board[i] if i < len(self.board) else CARD_NONE
        if seat is not None:
            data[37] = seat.cards[0] if len(seat.cards) > 0 else CARD_NONE
            data[38] = seat.cards[1] if len(seat.cards) > 1 else CARD_NONE
        else:
            data[37] = CARD_NONE
            data[38] = CARD_NONE
        # The player's current best hand, so the Z80 never has to evaluate:
        # nothing before the flop, when five cards do not exist yet.
        if seat is not None and len(seat.cards) == 2 and len(self.board) >= 3:
            name = hand_name(best_hand(list(seat.cards) + list(self.board)))[:10]
            data[44:44 + len(name)] = name.encode('ascii', 'replace')
        data[39] = data[23]
        data[40] = 0
        data[41] = min(255, max(0, int(self.next_hand_at - self.clock()))) if self.next_hand_at else 0
        data[42] = min(255, self.grace_seconds)
        for index, s in enumerate(self.seats):
            base = 64 + index * 16
            flags = 0
            if s.occupied:
                flags |= 1
            if s.in_hand:
                flags |= 2
            if s.folded:
                flags |= 4
            if s.all_in:
                flags |= 8
            if s.occupied and s.stack <= 0:
                flags |= 16
            if s.number == self.button and s.in_hand:
                flags |= 32
            if s.number == self.actor:
                flags |= 64
            if s.occupied and not s.connected:
                flags |= 128
            data[base] = flags
            data[base + 1] = s.last_action if s.occupied else ACTION_NONE
            self.put16(data, base + 2, max(0, s.stack))
            self.put16(data, base + 4, s.bet)
            show = s.cards if (seat is not None and s.number == seat.number) or \
                             (s.showing and len(s.cards) == 2) else []
            data[base + 6] = show[0] if len(show) > 0 else CARD_NONE
            data[base + 7] = show[1] if len(show) > 1 else CARD_NONE
            nick_bytes = s.nick.encode('ascii', 'replace')[:6] if s.occupied else b''
            data[base + 8:base + 8 + len(nick_bytes)] = nick_bytes
            self.put16(data, base + 14, min(0xFFFF, s.last_amount))
        status = self.status.encode('ascii', 'replace')[:39]
        data[208:208 + len(status)] = status
        queued = self.chat.get(nick.upper(), ()) if nick else ()
        data[248] = min(255, len(queued))       # unread chat rows
        data[249] = 1 if self.over else 0
        data[250] = self.level + 1              # blind level, 1-based
        data[251] = min(255, max(0, int(self.level_started + self.level_seconds - self.clock())))
        data[252] = MAX_SEATS
        data[253] = 1                           # packet layout version
        data[254] = 0
        data[255] = sum(data[0:255]) & 0xFF
        return bytes(data)

    def player_flags(self, seat):
        flags = 0
        if seat is None:
            return flags
        if seat.number == self.actor:
            flags |= 1
        if seat.in_hand:
            flags |= 2
        if seat.folded:
            flags |= 4
        if seat.all_in:
            flags |= 8
        if seat.stack <= 0:
            flags |= 16
        if seat.number == self.button and seat.in_hand:
            flags |= 32
        if seat.waiting:
            flags |= 64
        if not seat.connected:
            flags |= 128
        return flags

    @staticmethod
    def put16(data, offset, value):
        data[offset] = value & 0xFF
        data[offset + 1] = (value >> 8) & 0xFF

    # -- chat ------------------------------------------------------------
    def say(self, nick, text):
        text = ' '.join((text or '').split()).upper()
        text = ''.join(c if c in CHAT_CHARS else '?' for c in text)[:100]
        if not text:
            return 'NOTHING TO SAY'
        for other in self.seats:
            if other.occupied and other.nick.upper() != nick.upper():
                queue = self.chat.setdefault(other.nick.upper(), collections.deque(maxlen=40))
                for row in wrap_rows(nick.upper() + ': ', text):
                    queue.append((0, row))
        return None

    def take_chat(self, nick, limit=5):
        queue = self.chat.setdefault((nick or '').upper(), collections.deque(maxlen=40))
        rows = [queue.popleft() for _ in range(min(limit, len(queue)))]
        return rows, len(queue)


def wrap_rows(prefix, text, width=42):
    rows, first = [], True
    while first or text:
        row = prefix if first else '  '
        while text and len(row) < width:
            row += text[0]
            text = text[1:]
        rows.append(row)
        first = False
    return rows


def chat_packet(rows, unread):
    data = bytearray(PACKET)
    data[0:4] = b'POKR'
    data[5] = ord('C')
    for i, (private, row) in enumerate(rows[:5]):
        text = row[:42].encode('ascii', 'replace')
        data[8 + i * 44:8 + i * 44 + len(text)] = text
        data[8 + i * 44 + 43] = 1 if private else 0
    data[240] = min(len(rows), 5)
    data[241] = min(unread, 255)
    data[255] = sum(data[0:255]) & 0xFF
    return bytes(data)


def error_packet(message):
    data = bytearray(PACKET)
    data[0:4] = b'POKR'
    data[5] = ord('E')
    text = message.upper().encode('ascii', 'replace')[:39]
    data[208:208 + len(text)] = text
    data[255] = sum(data[0:255]) & 0xFF
    return bytes(data)


# ---------------------------------------------------------------- the host

class Rooms:
    """Every tournament this server hosts, keyed by room name."""

    def __init__(self):
        self.rooms = {}
        self.lock = threading.RLock()

    def valid(self, room):
        return bool(room) and len(room) <= 16 and re.fullmatch(r'[A-Za-z0-9]+', room) is not None

    def get(self, room, config, create=True):
        with self.lock:
            key = room.lower()
            if key not in self.rooms:
                if not create:
                    return None
                self.rooms[key] = Tournament(key, config)
            return self.rooms[key]

    def reset(self, room):
        with self.lock:
            self.rooms.pop(room.lower(), None)

    def sweep(self):
        with self.lock:
            for key in list(self.rooms):
                tournament = self.rooms[key]
                if tournament.over and tournament.clock() - tournament.level_started > 86400:
                    del self.rooms[key]


_rooms = Rooms()


def room_config(config):
    return {key: config.get(key) for key in (
        'POKERSTACK', 'POKERLEVELSECS', 'POKERLATE', 'POKERACTIONSECS',
        'POKERDROP', 'POKERGRACE', 'POKERHANDDELAY')}


def relay_url(config):
    url = os.environ.get('POKER_RELAY_URL') or config.get('POKERRELAY') or ''
    return url.rstrip('/')


def default_nick(config):
    return (os.environ.get('POKER_NICK') or config.get('POKERNICK') or
            config.get('IRCNICK') or 'PLAYER').upper()[:12]


def forward(url, payload):
    request = Request(url + '/poker', json.dumps(payload).encode(),
                      {'Content-Type': 'application/json'})
    with urlopen(request, timeout=6) as response:
        result = json.loads(response.read(16384))
    if 'error' in result:
        raise ValueError(result['error'])
    return bytes.fromhex(result['packet'])


def handle_command(command, config=None, now=None):
    """Run one PPOKER command and return the MSX's 256-byte reply.

    Called by the MSXPi server's `poker` command.  With POKERRELAY set the
    command is forwarded to the hosting server, which owns the table; without
    it this server hosts (the first `join ROOM` creates the tournament).
    """
    config = config or {}
    now = time.monotonic() if now is None else now
    args = (command or '').split()
    nick = default_nick(config)
    if not args:
        return error_packet('poker join ROOM')
    say_text = command.partition(' ')[2] if args[0] == 'say' else ''
    if args[0] == 'nick' and len(args) == 2:
        nick = args[1][:12].upper()
        args = ['poll'] if len(args) < 3 else args[2:]
    url = relay_url(config)
    # A forwarded command carries the nickname and the room the host needs.
    if url:
        room = args[1] if len(args) > 1 and args[0] in ('join', 'host', 'new') else \
            config.get('POKERROOM') or ''
        if args[0] in ('join', 'new') and not room:
            return error_packet('JOIN ROOM FIRST')
        payload = {'cmd': ' '.join(args), 'nick': nick, 'room': room}
        try:
            return forward(url, payload)
        except Exception as exc:
            return error_packet('RELAY ERROR: %s' % exc)
    return local_command(args, nick, say_text, config, now)


def local_command(args, nick, say_text, config, now, room=None):
    """Apply a command to a tournament hosted by this server."""
    action = args[0]
    if action in ('join', 'host'):
        room = args[1] if len(args) > 1 else (room or config.get('POKERROOM') or '')
        if not _rooms.valid(room):
            return error_packet('ROOM: 1-16 LETTERS OR DIGITS')
        tournament = _rooms.get(room, room_config(config))
        with tournament.lock:
            tournament.tick(now)
            seat, message = tournament.join(nick, now)
            if seat is None:
                return error_packet(message)
            tournament.touch()
            return tournament.snapshot(nick)
    if action == 'new':
        room = args[1] if len(args) > 1 else (room or config.get('POKERROOM') or '')
        if not _rooms.valid(room):
            return error_packet('ROOM: 1-16 LETTERS OR DIGITS')
        _rooms.reset(room)
        tournament = _rooms.get(room, room_config(config))
        with tournament.lock:
            seat, message = tournament.join(nick, now)
            if seat is None:
                return error_packet(message)
            return tournament.snapshot(nick)
    room = room or config.get('POKERROOM') or ''
    if action in ('rooms',):
        return error_packet('ROOMS: %s' % ','.join(sorted(_rooms.rooms))[:30] or 'NONE')
    tournament = _rooms.get(room, room_config(config), create=False) if room else None
    if tournament is None:
        # Without a configured room, a single table per server is the norm:
        # find the table this nick is seated at.
        tournament = next((t for t in _rooms.rooms.values() if t.seat_of(nick)), None)
    if tournament is None:
        return error_packet('NOT AT A TABLE - JOIN ROOM')
    with tournament.lock:
        tournament.tick(now)
        seat = tournament.seat_of(nick)
        if action in ('fold', 'check', 'call', 'bet', 'raise', 'allin'):
            if seat is None:
                return error_packet('NOT SEATED')
            amount = 0
            if action in ('bet', 'raise'):
                if len(args) < 2 or not args[1].isdigit():
                    return error_packet('AMOUNT NEEDED')
                amount = int(args[1])
            error = tournament.act(seat, action, amount, now)
            if error:
                return error_packet(error)
            return tournament.snapshot(nick)
        if action == 'leave':
            message = tournament.leave(nick, now)
            if seat is None:
                return error_packet(message)
            return tournament.snapshot(nick)
        if action == 'say':
            error = tournament.say(nick, say_text)
            return error_packet(error) if error else tournament.snapshot(nick)
        if action == 'chat':
            rows, unread = tournament.take_chat(nick)
            return chat_packet(rows, unread)
        if action in ('poll', 'peek'):
            if seat is None:
                return tournament.snapshot(nick)
            seat.last_seen = now
            seat.connected = True
            return tournament.snapshot(nick)
        return error_packet('UNKNOWN ACTION')


# ---------------------------------------------------------------- the relay

class RelayServer(ThreadingHTTPServer):
    allow_reuse_address = os.name != 'nt'
    daemon_threads = True


class RelayHandler(BaseHTTPRequestHandler):
    config = {}

    def do_POST(self):
        try:
            if self.path != '/poker':
                raise ValueError('Unknown endpoint')
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 4096:
                raise ValueError('Invalid request size')
            request = json.loads(self.rfile.read(size))
            room = request.get('room') or 'main'
            command = (request.get('cmd') or 'poll').strip()
            args = command.split()
            say_text = command.partition(' ')[2] if args and args[0] == 'say' else \
                (request.get('text') or '')
            tournament = _rooms.get(room, room_config(self.config))
            with tournament.lock:
                now = time.monotonic()
                tournament.tick(now)
                reply = local_command(args, (request.get('nick') or 'PLAYER')[:12].upper(),
                                      say_text, self.config, now, room)
        except Exception as exc:
            reply = error_packet(str(exc))
        body = json.dumps({'packet': reply.hex()}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


_relay = None


def start_relay(config):
    global _relay
    if _relay is not None:
        return
    listen = config.get('POKERLISTEN') or '0.0.0.0'
    port = int(config.get('POKERPORT') or 5090)
    try:
        _relay = RelayServer((listen, port), RelayHandler)
    except OSError as exc:
        print('poker: relay not started on %s:%d: %s' % (listen, port, exc))
        return
    RelayHandler.config = config
    threading.Thread(target=_relay.serve_forever, daemon=True).start()
    print('poker: relay listening on %s:%d' % (listen, port))


def stop_relay():
    global _relay
    if _relay is not None:
        _relay.shutdown()
        _relay.server_close()
        _relay = None


# ---------------------------------------------------------------- testing

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--listen', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=5090)
    options = parser.parse_args()
    RelayHandler.config = {}
    print('PPOKER relay on %s:%d' % (options.listen, options.port))
    RelayServer((options.listen, options.port), RelayHandler).serve_forever()
