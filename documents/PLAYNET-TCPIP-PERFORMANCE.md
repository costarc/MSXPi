# PLAYNET over TCP/IP: why it is slow, and how to make it as fast as the MSXPi link

Handover, written 2026-10-22 on `feature/tcpip-games` (HEAD `894fac7e`). Nothing in this document is implemented yet.

| | |
|---|---|
| Problem | Games over the TCP/IP UNAPI path (`PLAYNET /T`) run too slowly to be playable. Over the MSXPi link (`PLAYNET`) the same game runs at full speed. The branch was put on hold for this reason. |
| Goal | The same frame rate over TCP/IP as over the MSXPi link, with no change to the lockstep model, the GPF format or the integration guide. |
| Reads first | `documents/PLAYNET-DESIGN.md` (rationale, 8a measurements), `documents/PLAYNET-PROTOCOLS.md` (MSXNP, transport vector, stub). This document refers to their section numbers. |
| Main files | `software/Client/src/playnet/engine/playnet_engine.asm`, `transport_unapi.asm`, `playnet_tcp.asm`, `netcore/netcore.c`, `netcore/ovl_main.c`, `software/Server/Python/src/msxpi_netplay.py`, `software/UNAPI/src/ethops.asm` |

---

## 1. Summary

The lockstep design is not the problem. It sends one 22-byte packet each way per frame, and it is equally sound on both paths. The
problem is what one exchange costs on the TCP/IP path, and that the TCP/IP stack runs only by chance during a game.

What one game frame costs in network work (estimates for a 3.58 MHz Z80 and a link byte at about 67 µs, see 3.2):

| | MSXPi link | TCP/IP today (InterNestor Lite on the MSXPi Ethernet driver) |
|---|---|---|
| Link bytes per frame | 49 (one C9 transaction) | about 150: send 69, receive 71, plus a 6-byte status poll per serviced interrupt |
| Z80 work outside the link | about 0.2 ms | about 10 ms: 8 ms of it is netcore's clock (C1), the rest INL's IP/UDP work and the page switches |
| Who services the network | the Pi, all the time, in its own thread | InterNestor Lite, only when an interrupt happens to fall inside an `XCHG` call (C3) |
| Total per frame | about 3.5 ms | about 20 ms, plus waits of up to one interrupt for the stack to run |

Soccer's game frame takes about two interrupts (33 ms) and its own logic uses most of that time. Another 20 ms pushes most
frames to three interrupts or more, and the stalls described in C3 add to that.

Six causes, in order of weight:

| # | Cause | Evidence | Fix (section 5) |
|---|---|---|---|
| C1 | netcore's clock does a 32-bit multiply, divide and modulo on every read, and the overlay reads it twice per `XCHG` | Measured in the SDCC simulator: `nc_xchg` takes 2082 Z80 instructions with this clock and 177 with a plain tick counter | 5.1 |
| C2 | A software stack over the MSXPi link carries about 3x the bytes of a C9 transaction, plus IP/UDP processing on the Z80 | Byte counts from `ethops.asm`. Ping to INL on real hardware: 40-60 ms (UNAPI `PHASE1_DESIGN.md`). INL's timer: 38-44 % of a frame in emulation (design 8.4) | 5.3, 5.4, 5.5 |
| C3 | InterNestor Lite receives only on interrupts that fall inside an `XCHG` call. In a frame with no stall, that happens about half the time, so the opponent's packets queue up and the next frames stall | Follows from `transport_unapi.asm` and the game's interrupt path (design G6, 8.4) | 5.2 |
| C4 | Interrupts taken in MSX-DOS's page 3 during an `XCHG` are lost to the game's counters: the music slows down and netcore's in-game clock runs slow | `transport_unapi.asm`: `tTicks` counts only interrupts in the game's page 3 | 5.2 |
| C5 | The protocol sends a packet every frame whatever the transport costs. Resends are counted in polls, not time, and the input delay ignores the transport's service latency | `playnet_engine.asm` (`stallCnt & 15`), `choose_delay` in netcore and in Python | 5.3 |
| C6 | The IRC connection stays open through the game, and INL must receive and acknowledge its channel traffic over the same link | PROTOCOLS 14 | 5.6 (measure first) |

The proposal, in implementation order (the step numbers of section 7):
- **Step 0, measure** with the rig before changing anything, so each step has a number to beat.
- **Step 1, netcore's clock in ticks**: no division on the hot path. This removes about 8 ms per exchange, and it helps every TCP/IP
  stack, GR8NET included.
- **Step 2, service the stack deterministically**: the transport runs the stack's timer itself, at most once per interrupt period, when it
  needs a packet. Count the interrupts taken in MSX-DOS's page 3.
- **Step 3, MSXNP 2**: a send interval of K frames (K = 2 for software stacks), each side announces its transport's latency, the delay
  rule accounts for both, and resends are timed.
- **Step 4, driver and Pi**: the MSXPi Ethernet driver's burst mode and the pending-frame cache, plus a filter on the Pi's TAP.
- **Step 5, for TCP/IP players who have an MSXPi**: the game packets go over the C9 transaction, the chat stays on TCP/IP. That gives
  parity by construction.

Steps 1-3 are generic. On a hardware stack such as GR8NET they should be enough on their own. On InterNestor Lite over the MSXPi
Ethernet driver, steps 1-3 bring the cost to roughly 1.5x the MSXPi path's, and step 4 or 5 closes the rest (5.7).

---

## 2. State of the branch

- `feature/tcpip-games` holds the TCP/IP work up to `894fac7e`: PLAYNET steps 1-9 (design section 7), `PLAYNET /T`,
  `PLAYNET.OVL`, the MCHAT `/T` game agent (`games_local.c`) and the Soccer quick start over TCP/IP.
- `master` reverted the MCHAT side in `0c4ac631`. With `games_local.c`, `mchat.com` grew from 48922 to 49757 bytes, and **the chat
  hung after an invitation on real and emulated machines**. That is a separate bug, not the speed problem. It still has to be fixed
  before the chat-to-game scenario over TCP/IP (`SCENARIO=tcp`) is a release path. Until then, `PLAYNET /T game role lport
  ip:port` (the manual start) is the way to test speed.
- Tested: the rig only (openMSX, Canon V-25, InterNestor Lite on the MSXPi Ethernet driver through `msxpi_ethnat.py`). `SCENARIO=mixed`,
  `BOTH=1` and `SCENARIO=tcp` give identical frames and no desync. The traces carry no timing, so nothing records the speed.
- Not tested: real hardware over TCP/IP, and any stack other than InterNestor Lite.

---

## 3. One frame on each path

### 3.1 What happens

```
MSXPi link (transport_msxpi.asm)               TCP/IP (transport_unapi.asm + PLAYNET.OVL)
-------------------------------                ------------------------------------------
PN_TICK                                        PN_TICK
 XCHG: DI                                       XCHG: DI, packet -> overlay I/O block (page 2)
   C9 FLAGS L P[22] SUM  ->  Pi                       page 3 := MSX-DOS's segment (D3), private stack
   <- L P[22] SUM  (oldest queued packet)             PUT_P2(overlay), EI
   EI                                                 ovl_xchg:  irc_keep  -> nc_now (32-bit mul/div/mod)
                                                                 nc_xchg -> nc_poll -> nc_now (again)
 The Pi's thread meanwhile receives UDP,                                    UDP_RCV until "no data"  (CALL_MAP into INL)
 keeps time, answers PINGs, queues packets.                                 UDP_SEND (INL builds IP/UDP, ETH_SEND_FRAME: 69 link bytes)
                                                      [only if an interrupt falls in this window:
                                                       BIOS -> D3 H.TIMI -> INL timer -> ETH_IN_STATUS (6 bytes)
                                                       -> ETH_GET_FRAME (71 bytes) -> IP/UDP into INL's buffer]
                                                      DI, page 3 := the game's (G3), packet back, EI
```

The difference that matters: on the MSXPi path the session engine runs on the Pi, all the time, and the MSX only collects the
result. On the TCP/IP path the session engine and the TCP/IP stack run on the MSX, and only inside the game's calls to `XCHG`.

### 3.2 Costs

| Item | Cost | Source |
|---|---|---|
| Link byte, polled (`PIREADBYTE` path) | about 240 T-states on the Z80 (67 µs), plus the Pi. The Ethernet README gives about 18 KB/s (55 µs a byte) | UNAPI `PHASE1_DESIGN.md` 1.3, `UNAPI/README.md` |
| C9 game transaction, W = 1 | 25 bytes out, 24 back: about 3.3 ms | PROTOCOLS 10.1 |
| C9 poll with nothing to send | 4 bytes out, 2 back: about 0.4 ms | same |
| `ETH_SEND_FRAME` of a game packet | 14 + 20 + 8 + 22 = 64-byte frame, plus 4 header bytes and 1 reply byte: about 4.6 ms | `ethops.asm` |
| `ETH_IN_STATUS` | 1 out, 5 back: about 0.4 ms, **once every time INL's timer runs**, frame or not | `ethops.asm` |
| `ETH_GET_FRAME` of a game packet | 3 out, 3 + 64 + 1 back: about 4.8 ms | `ethops.asm` |
| `nc_now()` in `ovl_main.c` | about 1900 instructions (`__mullong`, `__divulong`, `__modulong`), roughly 13-17k T-states, 4 ms. Called twice per `XCHG` | measured, 4 C1 |
| INL timer routine per interrupt | mean 6-7 ms, up to 120 ms (emulated, pessimistic: the emulated MSXPi device waits for a real-time server) | design 8.4 |
| Ping Pi to INL, real Canon V-25 | 40-60 ms for one round trip | UNAPI `PHASE1_DESIGN.md`, "It works" |
| Page-3 switch, `PUT_P2`, packet copies | a few hundred T-states | `transport_unapi.asm` |

---

## 4. The causes in detail

### C1. netcore's clock

`ovl_main.c` keeps netcore's time in centiseconds:

```c
uint32_t x = (uint32_t)(uint16_t)(t - last_ticks) * 100 + rem;
cs += (uint16_t)(x / ovl_io.hz);
rem = (uint16_t)(x % ovl_io.hz);
```

SDCC turns that into calls to `__mullong`, `__divulong` and `__modulong` (see `build/ovl/ovl_main.asm`). `ovl_xchg` reads the clock
twice: once in `irc_keep`, before it even checks whether the IRC connection is in use, and once in `nc_poll`.

Measured with SDCC 4.0.0's own simulator (`sz80`), netcore built as `build.py` builds it (`-mz80 --opt-code-size`), the
UNAPI calls replaced by stubs, state READY:

| `nc_xchg` call | Instructions per call |
|---|---|
| 32-bit clock, nothing to send | 2082 |
| 32-bit clock, sending a 22-byte packet | 2167 |
| 16-bit tick clock, nothing to send | 177 |
| 16-bit tick clock, sending | 262 |

The simulator counts instructions, not T-states (calibrated: 100 x `nop`/`djnz` gives 211). At 7-9 T-states per instruction for
this code, one clock read is about 4 ms, and **an `XCHG` spends about 8 ms reading the clock**. That is more than two whole C9
transactions, it applies to every stack (GR8NET included), and in a stall it is paid on every poll. The bench is a small C host
(stub `nc_send`/`nc_recv` that feed one SETUP, then nothing; 40 calls of `nc_xchg`, minus a run with 0 calls). Step 1 turns it into a
test (8.1).

### C2. The software stack on the MSXPi link

On the user's hardware, the TCP/IP stack is InterNestor Lite on the MSXPi Ethernet UNAPI driver in `msxpibios.rom`. Every Ethernet
frame crosses the same MSXPi link that the C9 transaction uses, and carries Ethernet, IP and UDP headers around the same 22 bytes:

- one game frame: about 150 link bytes against 49 (table in 3.2),
- the IP and UDP headers, checksums and ARP are built and checked by INL on the Z80,
- INL's timer polls the driver with `ETH_IN_STATUS` every time it runs, even when nothing is waiting.

On real hardware this shows as a 40-60 ms ping to INL from the Pi, for a path where the C9 transaction takes about 3 ms. That RTT feeds
the input delay (C5), so the game also feels laggier than on the MSXPi link.

### C3. The stack runs only by chance

InterNestor Lite does all its receiving from its timer hook (H.TIMI in MSX-DOS's page 3). `TCPIP_WAIT` just waits for the next interrupt
(`SOCCERNET-NETPLAY.md`). During the game:

- Interrupts that come while the game's page 3 (G3) is mapped go to `XIRQ` and then to the game's handler. The game reads the VDP status
  itself, so the BIOS never reaches H.TIMI. INL's code is not even in that page (design G6).
- INL's timer therefore runs only when an interrupt falls **inside** an `XCHG` call, the only time MSX-DOS's page 3 (D3) is mapped with
  interrupts on.

So, in a frame with no stall, `PN_TICK` calls `XCHG` once (about 13 ms today: the clock plus the send). There is roughly a one-in-two
chance that INL gets to fetch a frame from the driver during that call. The opponent sends one packet a frame, so INL falls behind, and the
packets pile up in the Pi's queue for the TAP. As the queue grows, the remote input for frame F arrives later and later, until `PN_TICK` stalls.
While it stalls, the engine calls `XCHG` back to back, INL gets interrupts and drains the queue, and the cycle starts again.
The game runs at the speed at which INL happens to be serviced, not at the speed of the network.

The input delay does not help. It is chosen in the connect phase, in MSX-DOS, where INL's timer runs on every interrupt. The delay the RTT
suggests is therefore one that the game's service pattern cannot meet.

### C4. Lost interrupts

An interrupt taken inside `XCHG` runs MSX-DOS's handler in D3: `JIFFY` (D3's) advances, and the VDP status is read and cleared. The game
does not see that interrupt at all:
- `tTicks` (netcore's clock in the game) misses it, so the 15 s dead-peer timer and the IRC keep-alive run slow;
- `PN_IRQ` misses it, so player 1's interrupt count in the frame records is too low and the music plays slower than the original.

The game itself loses nothing, because it is inside `PN_TICK` with its busy flag set and would only have counted the interrupt. That is why this
ranks low. The fix is small anyway (5.2).

### C5. The protocol's assumptions

MSXNP and the stub engine were tuned on the MSXPi path, where an exchange is cheap and the session engine runs independently of the game:

- **One packet each way per frame, always.** Each packet repeats the last 8 frames of input. On a transport where a packet costs
  10 ms, half of that redundancy would be enough. Sending every second frame halves the cost and still survives 3 lost packets in a
  row.
- **Resend every 16th poll** (`stallCnt & 15`). On the MSXPi path a poll is about 0.4 ms, so that resends every 6 ms or so. On TCP/IP
  today a poll is 9 ms or more, so a lost packet is repaired only after 150 ms or more, which is a visible hitch. The rule should be in time, not in polls.
- **The delay rule** `ceil(rtt90 / 2 / 20 ms) + 2` has no term for the time a transport takes to deliver a packet that has already arrived
  (C3), or for a send interval.

Nothing in the wire format needs to change for any of this (5.3): only the sender's schedule and the leader's delay rule.

### C6. Background traffic

`MCHAT /T` keeps the IRC TCP connection open through the game, and `PLAYNET.OVL` answers its PINGs (PROTOCOLS 14). Every message in
the player's channels still arrives as TCP segments. INL must take each one off the link (about 100-500 bytes a line) and acknowledge it, in the same
scarce service windows as the game packets. In a quiet channel this costs nothing. In a busy one it competes with the game. The keep-alive itself
(`irc_keep` twice a second) is cheap once C1 is fixed.

### What is not a cause

- The lockstep model, the 22-byte packet and the 8-frame redundancy.
- The page-3 segment design (G3 and D3): a switch costs a few dozen T-states.
- `XIRQ`, the trampoline and the return to MSX-DOS.
- The C code apart from the clock: with a tick clock, `nc_xchg` is 177-262 instructions.

---

## 5. Proposed changes

### 5.1 netcore keeps time in ticks (fixes C1)

- netcore's time unit becomes the host's tick: 1/50 or 1/60 s on the MSX, `JIFFY` in MSX-DOS and `tTicks` in the game.
  `nc_now()` in `ovl_main.c` becomes a plain 16-bit read of the counter.
- `nc_init()` gets the tick rate: `nc_init(profile, version, force_delay, hz)`. It converts the timeouts into ticks once:
  connect 120 s, start 60 s, dead 15 s, HELLO 200 ms, PING 100 ms, SETUP 200 ms, BYE 100 ms, PING_QUIET 1 s. `since()` stays a
  signed 16-bit difference, so a timeout must stay under 32767 ticks: limit `hz` to 250 at most.
- `choose_delay()` converts the 90th-percentile RTT from ticks to milliseconds once, when the delay is decided: one division per
  session.
- `netcore_host.c` (the gcc host of the conformance tests) passes `hz = 100` and keeps reporting centiseconds, so `test_netcore.py`
  does not change.
- `ovl_xchg` reads the clock once and passes the value to `irc_keep` (`irc_keep(now)`), which returns before any work when there
  is no IRC connection.

Expected gain: about 8 ms per `XCHG`, on every TCP/IP stack.

### 5.2 The stack is serviced on purpose (fixes C3, C4)

**Service.** A timer-driven stack such as InterNestor Lite gets its timer routine called by PLAYNET, at a known point and a known rate,
instead of by chance:

- `ovl_main.c` gets a `service()` step, run in `ovl_xchg` **before** `nc_xchg`, so that a frame INL fetches is read by `UDP_RCV` in the
  same call. With interrupts off, it calls MSX-DOS's H.TIMI hook (`call 0FD9Fh`, which is D3's, since D3 is mapped during the call),
  with `A = 80h` (a VDP status with the frame bit set), as the BIOS would.
- **At most once per interrupt period**: `service()` runs only if `tTicks` has advanced since the last service, and no interrupt was
  taken in D3 since then (D3's `JIFFY` did not move). INL's own timers (TCP retransmission, ARP) then never run faster than real time.
- Only for stacks that need it. `PLAYNET /T` finds the TCP/IP implementation's name with UNAPI function 0 (read through `RD_MAP`
  for a RAM implementation) and turns the service on for "InterNestor". A new switch, `/S0` or `/S1`, forces it off or on for tests and
  for other software stacks. GR8NET and other hardware stacks have no timer to run. GR8NET's manual (12.4) confirms it: its TCP/IP is in
  the W5100 chip, and its `TCPIP_WAIT` "does nothing, and always returns ERR_OK".
- `XCHG` keeps `EI` around the stack calls: a RAM implementation enables interrupts inside its calls anyway (design 8.5).

**Interrupt accounting** (C4). `XCHG` reads D3's `JIFFY` when it switches to D3 and again before it switches back:

- the difference is added to `tTicks`,
- it is returned in a register (`E`, free in the contract). `PN_TICK` adds it to `irqCnt` after the call (a new 6-byte step in the
  engine, `PN_IRQ`'s count by hand), so that player 1's interrupt count, and the music, stay right.

This is a stub ABI change (5.3 bumps it anyway).

**What it costs.** INL's timer then runs once per frame (2 interrupts in Soccer) in steady state, and once per interrupt in a stall.
Design 8.4 rejected running it on **every** interrupt from `XIRQ`, at 38-44 % of a frame. This runs it about half as often, and only
inside `PN_TICK`, where the game is waiting anyway. Most of the cost is the frame fetch, which the game needs. The `ETH_IN_STATUS`
round trip that finds nothing waiting is what 5.4 removes.

### 5.3 MSXNP 2 and stub ABI 2 (fixes C5)

All three changes keep the game packet and control datagram layouts (PROTOCOLS 11.1). The control datagram's `version` becomes 2.
Both implementations (`msxpi_netplay.py`, `netcore.c`) change together, and version 1 peers get "incompatible" as today. The
branch is alpha, so there is nothing to stay compatible with.

**(a) Transport profile in HELLO.** HELLO's `b`, now always 0, carries what this side's transport costs:

| Bits of `b` | Field | MSXPi (Pi) | INL | hardware stack |
|---|---|---|---|---|
| 0-7 | K: the send interval this side wants, 1-3 frames | 1 | 2 | 1 |
| 8-15 | S: this side's service latency, in frames (the time between a packet's arrival and the game seeing it) | 0 | 1 | 0 |
| 16-31 | reserved, 0 | | | |

The values in the table are the defaults to start from. Step 0 measures them, and `PLAYNET /T` takes `/K` and `/L` switches to override them in
tests.

**(b) SETUP carries K.** The leader chooses `K = max(K_leader, K_follower)` and sends it in SETUP's `b`. ACK echoes it. Both sides
use the same K.

**(c) Delay rule.**

```
D = ceil(rtt90 / 2 / 20 ms) + 2 + (K - 1) + max(S_leader, S_follower),   clamped to 2..7
```

`MAX_DELAY` goes from 6 to 7. The engine's rings hold 16 frames, and records can be up to 2D frames ahead of the frame being played, so D
must stay at or below 7 (`2D < 16`). Check `recv`'s `cp 16` bound when making the change.

**(d) Stub ABI 2.** The stub header grows from 4 bytes to 5. Byte 4 is K, written by the loader from the handshake, like the delay in byte 2.
The engine changes as follows:
- `send` and an `XCHG` with a packet happen when `nf mod K == 0`. In other frames `XCHG` is called with `HL = 0` (poll only) when the
  remote input for F is missing, and not at all when it is there.
- **Timed resend.** In a stall, resend when 3 or more interrupts (about 50 ms) have passed since the last send, measured with `irqCnt`,
  which now also includes the interrupts counted in 5.2. This replaces `stallCnt & 15`. On the MSXPi path it resends less often than now, which
  the Pi does not need anyway.
- With K = 2, each frame's record is in 4 packets instead of 8, so 3 consecutive losses are repaired instead of 7. That is still above what the
  acceptance test asks for (8 % random loss).

GPF, profile hashes and `min_playnet`: the stub is an asset inside the GPF, so `SOCCER.GPF` gets a new hash. `build_games.py`
rebuilds it, and `min_playnet` goes to 2.

**Effect.** With K = 2 the per-frame link cost on INL halves, from about 150 bytes to about 75. The delay grows by one frame for K and one for S.
D counts game frames, and Soccer's frame is about two interrupts, so that is up to about 67 ms more input lag against an INL machine. The lag is fixed and
the same for both players. With the service of 5.2 in place S may turn out to be 0: step 0 and step 3 decide it, and check that the result stays playable.

### 5.4 The MSXPi Ethernet driver and the Pi (C2)

These help InterNestor Lite on the MSXPi, and most of them also help the MSXPi link itself.

1. **Burst transfers** (hardware `/WAIT`, `INIR`/`OTIR`): 21 T-states a byte plus the Pi's stall, against about 240 polled (UNAPI
   `PHASE1_DESIGN.md` 1.2-1.3, 3.4). This is the biggest lever for C2, because frames are mostly payload bytes. It needs the
   Pi-side burst requirement of `PHASE1_DESIGN.md` 3.4 first, and the CPLD support on the board in use. Apply it to the C9
   transaction too: then both paths get faster and parity is about the bytes again.
2. **The pending-frame cache** (the TODO in `FN_IN_STATUS`). The Pi already answers `ETH_GET_FRAME` with a "another frame is queued" flag.
   Extend that reply with the next frame's length and ethertype (5 bytes), so that `ETH_IN_STATUS` answers from the cache with no round
   trip when a frame is known to be waiting. Keep the round trip when the cache says "none", because a frame may have arrived since.
3. **Fetch with the status.** When `ETH_IN_STATUS` does go to the Pi and a frame is waiting, the Pi sends the frame in the same
   transaction into the driver's segment buffer. `ETH_GET_FRAME` then copies it locally. That is one transaction per frame instead of two.
4. **A filter on the Pi's TAP** (`msxpi_eth.py`): pass only frames for the MSX's MAC, broadcast ARP for its IP, and the multicasts INL
   uses (none, by default). Count what is dropped. On a LAN, broadcast noise otherwise reaches the MSX at link speed.

### 5.5 TCP/IP players who have an MSXPi: game packets over the C9 transaction

This is the user's own configuration: a Canon V-25 with InterNestor Lite on the MSXPi. The chat runs over TCP/IP (`MCHAT /T`), and the
same MSXPi could carry the game packets the way the MSXPi path does. Mixed matches already prove that a Pi session plays an INL session.

- **Session on the Pi.** New MSXPi commands:
  - `playnet open <game_id>`: the Pi opens its `Netplay` socket and returns its candidates (`ip:port,...`, LAN and STUN), and the profile hash it serves.
  - `playnet peers <token> <seat> <game_id> <candidates>`: the Pi builds the session record (PROTOCOLS 13) that `playnet session` serves.
- **`MCHAT /T`.** When it finds an MSXPi with these commands, it sends the Pi's candidates in ACCEPT/GO instead of INL's, passes the
  opponent's candidates to `playnet peers`, and writes `PLAYNET.SES` with a new link value 2, "TCP/IP chat, MSXPi game".
- **`PLAYNET /T`** with link 2 connects through the Pi (flags 40h/80h, as on the MSXPi path) and installs a third transport,
  `transport_hybrid.asm`:
  - `XCHG` is the C9 transaction, run in the game's page 3 with no page switch at all (it is only I/O ports);
  - every 30th call it also maps D3 and the overlay, for `irc_keep` and one stack service (5.2), so the IRC connection lives through the game;
  - the return to MSX-DOS is the TCP/IP path's (page 3 of its own, nothing saved).
- The opponent sees an ordinary MSXNP peer. MSXG does not change.

The cost per frame is the MSXPi path's. The PLAYNET-DESIGN.md requirement (TCP/IP without a host) is not affected: without an MSXPi,
`MCHAT /T` and `PLAYNET /T` behave as in 5.1-5.3.

### 5.6 IRC traffic during a game (C6, measure first)

If step 0 shows channel traffic costing frames: before typing `PLAYNET /T`, `MCHAT /T` sends `AWAY :in a game`, and `PLAYNET.OVL`
reads the IRC connection only every 2 s instead of every 0.5 s. A server's ping timeout is minutes, so that is safe. Leaving the channels during the game
would be the stronger fix, but other players would see the player leave. Decide only on numbers.

### 5.7 Expected result

Estimates per game frame, network work only, to be replaced by step 0's measurements:

| Configuration | INL on the MSXPi Ethernet driver | Hardware stack (GR8NET class), not measured |
|---|---|---|
| Today | about 20 ms plus waits for service | about 9 ms (the clock, C1) plus the stack's own cost |
| + 5.1 tick clock | about 12 ms plus waits | about 1 ms plus the stack's cost |
| + 5.2 service | about 12 ms, no waits | no change |
| + 5.3 K = 2 | about 6-7 ms on average | K stays 1 |
| + 5.4 burst | about 2-3 ms | no change |
| 5.5 C9 for game packets | about 3.5 ms (the MSXPi path's cost) | does not apply |
| MSXPi path, for reference | about 3.5 ms | |

### 5.8 Alternatives considered and rejected

| Alternative | Why not |
|---|---|
| Chain INL's timer from `XIRQ` on every interrupt | Design 8.4: 38-44 % of every frame, including frames that do not need the network. 5.2 runs it only inside `PN_TICK`, and at most once per interrupt period. |
| Only raise the input delay | It hides latency, not cost. Each frame would still pay about 20 ms, and C3's backlog would come back whenever INL falls behind. |
| Send raw Ethernet frames for game packets, bypassing INL | INL owns the driver's receive queue, and the result would only work on Ethernet UNAPI stacks. It is fragile, and 5.5 gets the same result cleanly. |
| TCP for game packets | Head-of-line blocking and retransmission timers are the opposite of what lockstep with redundancy needs. |
| Rewrite netcore in assembler | With the tick clock, netcore is 177-262 instructions per call. The remaining cost is in the stack and the link. |
| GR8NET's hardware multiplier and divider (MathPack, manual 11.5.9) for netcore's clock | It is real: 32-bit signed multiply and divide in 200-320 ns, memory-mapped at offsets 5Fh-7Fh of GR8NET's logical page C9h. But a program only sees that page through GR8NET's bank-1 window (6000h-7FFFh), with GR8NET's slot in page 1, and in the game page 1 is the game. Each use would cost a page-1 slot switch, a bank select, 8 bytes written, 4-8 bytes read and the switch back: roughly 1000 T-states. After step 1 the clock is a 16-bit read of about 50 T-states, with nothing left to divide per frame. It would also be a code path for one card, outside the conformance tests. |

---

## 6. Risks and open questions

| # | Risk or question | How to settle it |
|---|---|---|
| Q1 | Is it safe to call InterNestor Lite's H.TIMI routine outside an interrupt, with interrupts off and with `A = 80h`? (INL's source is not in this repository: only `inl-2.3-ram-implementation.patch` is.) | Step 2 on the rig, then on real hardware. Fallback: a `TCPIP_WAIT`-like call made with the game's page 3 mapped out, which is the current behaviour but forced once per interrupt period. |
| Q2 | Does INL send a UDP datagram during `UDP_SEND`, or queue it for its timer? If it queues, 5.2's service also drives sending, and the order in `ovl_xchg` becomes send, service, receive. | A breakpoint on `ETH_SEND_FRAME` in step 0. |
| Q3 | Does INL process more than one received frame per timer run? If not, a backlog drains at one frame per service. | Step 0: count `ETH_GET_FRAME` per H.TIMI. |
| Q4 | The values of K and S for INL (5.3 table) | Step 0 and step 3 measurements. |
| Q5 | GR8NET and other ROM stacks: `unapi()` in `ovl_main.c` uses `CALSLT` for a ROM implementation. If its entry were in page 2, `CALSLT` would map it over the running overlay at 8000h. | **Settled for GR8NET** by its manual (12.4): its UNAPI is in bank 1 (4000h-7FFFh), and data passed to it must not be in bank 1. The overlay at 8000h and `io.buf` in page 3 both satisfy that. Other ROM stacks: check when available. |
| Q9 | GR8NET's manual (12.4) forbids UNAPI calls "within the interrupt service routines" and any concurrent calls. In Soccer, `PN_TICK`, and so `XCHG`, runs inside the game's H.KEYI handler, with interrupts on. No other UNAPI caller exists during the game, so nothing is concurrent, but whether the firmware minds the interrupt context is not stated. | First GR8NET run (step 6). If it fails, the glue can move the exchange out of the handler: the handler sets a flag, and the game's main loop calls `PN_TICK`, which is what the manual recommends. That is a per-game patch, not an engine change. |
| Q6 | The MCHAT `/T` hang after an invitation (reverted on master in `0c4ac631`) | A separate task. It blocks `SCENARIO=tcp` and 5.5, not steps 0-4. |
| Q7 | Emulated timing: the MSXPi device in openMSX waits for a real-time server, so link costs in emulated time depend on the host's speed and on throttle | Compare paths in the same run conditions. Take absolute numbers from real hardware only. |
| Q8 | `MAX_DELAY` 7 and the rings | Check `recv`'s window and the ring size with D = 7 in the lockstep model (`lockstep_model.py`) before the stub changes. |

---

## 7. Implementation plan

Each step ends with something measured. The MSXPi path's results (plain, chat, mixed) must not change at any step.

**Step 0: instrument and measure (no product change).**
- New `software/Client/tests/soccernet/perf_node.tcl`, loaded with `EXTRA_TCL` and `EXTRA_TCL_C`. It writes `$WORK/np/<role>.perf`:
  - emulated time every 100 frames (from `machine_info time` at `PN_TICK`), which gives game frames per second;
  - `XCHG` calls per frame (stall polls), and emulated time spent inside `XCHG`;
  - interrupts per frame (player 1's record byte, already in the trace);
  - InterNestor Lite timer runs (a breakpoint on the address in D3's H.TIMI hook, which PLAYNET can print at start-up);
  - `ETH_SEND_FRAME`, `ETH_IN_STATUS` and `ETH_GET_FRAME` calls (breakpoints on the driver's function table entries);
  - the time from a packet's `UDP_SEND` on one node to its `UDP_RCV` on the other (needs both traces; optional).
- Follow the known openMSX Tcl pitfalls: no proc named `step` or `arm`, prefer plain address breakpoints to conditions, keep
  breakpoints gated to the game phase, and set throttle the same way in every run.
- Runs, 3000 frames each: native pair (`run_native.sh 0 0 3000`), `SCENARIO=mixed`, `SCENARIO=mixed BOTH=1`, then the same
  three with `50 8 3000 20`.
- `cmp_perf.py` prints one table: fps, polls per frame, ms in `XCHG` per frame, INL timer runs per frame, link operations per frame.
- **Deliverable**: section 5.7 rewritten with measured numbers, and Q2, Q3 and Q4 answered.

**Step 1: tick clock (5.1).** Files: `netcore.c`, `netcore.h`, `ovl_main.c`, `host/netcore_host.c`, `playnet_tcp.asm` (it passes `hz`
already, in the I/O block). Tests: `test_netcore.py` unchanged and passing. New cost test (8.1): `nc_xchg` at or below 400 instructions in
`sz80`. The rig in step 0's six runs. **Accept**: identical frames, and lower ms in `XCHG` per frame by about the predicted amount.

**Step 2: stack service and interrupt accounting (5.2).** Files: `ovl_main.c` (`service()`, the implementation name check), `transport_unapi.asm`
(D3 `JIFFY` before and after, `E` out), `playnet_engine.asm` (add `E` to `irqCnt`), `playnet_tcp.asm` (`/S`), `PLAYNET-PROTOCOLS.md` 10.
**Accept**: INL timer runs per frame between 1 and the frame's interrupt count, polls per frame down, music at 60 ticks a second on a TCP/IP node
(as measured on the MSXPi path in design step 4), and the dead-peer and IRC keep-alive timers in real time.

**Step 3: MSXNP 2 and stub ABI 2 (5.3).** Files: `msxpi_netplay.py`, `netcore.c` (HELLO `b`, SETUP `b`, the delay rule, `MAX_DELAY`),
`playnet_engine.asm` (header byte 4, the K schedule, the timed resend), `playnet.asm` and `playnet_tcp.asm` (write K, `/K` and `/L`), the Soccer
package rebuilt (`rebuild.py`, `build_games.py`), `PLAYNET-PROTOCOLS.md` 9.1, 11.1, 11.3 and 16, and `lockstep_model.py` with K. Tests:
`test_netplay.py` and `test_netcore.py` extended (K and S both ways, leader either side, delay rule vectors), the GPF tests, and the rig.
**Accept**: 3000 identical frames with `50 8 3000 20` on the native, mixed and both-TCP/IP pairs, and fps at or above step 2's.

**Step 4: driver and Pi (5.4).** Burst transfers first, if the board and the Pi-side requirement allow it. Then the pending-frame cache and the
fetch with the status in `ethops.asm` and `msxpi_eth.py`, then the TAP filter. Tests: the UNAPI harness (`software/UNAPI/harness`), `ETHBENCH` and
`ETHTEST` on real hardware, ping from the Pi (40-60 ms today), and step 0's runs. **Accept**: link operations per frame and the ping RTT down, with no
regression in telnet, `HGET` or the chat.

**Step 5: C9 game packets for TCP/IP players with an MSXPi (5.5).** Depends on Q6 (the MCHAT `/T` hang) for the chat part. Files: `msxpi_chat.py`
(`playnet open` and `playnet peers`), `mchat_local.c` and `games_local.c` (the Pi's candidates, link 2), `transport_hybrid.asm`, `playnet_tcp.asm`,
PROTOCOLS 13 and 15. Tests: a Python test for the two new commands, the rig scenario `SCENARIO=tcp HYBRID=1`, and the IRC keep-alive check of
`SCENARIO=tcp` (63 PONG in 30 s, no drop). **Accept**: fps equal to the native pair's within 2 %.

**Step 6: real hardware.** Canon V-25 with MSXPi and InterNestor Lite against a native peer, and two such machines; GR8NET if one can be borrowed.
Take the numbers into PLAYNET-DESIGN.md 8a.

---

## 8. Test plan

### 8.1 Without an emulator

| Test | What it checks | When |
|---|---|---|
| `test_netcore.py` (gcc under WSL) | netcore against `Netplay` over real UDP: leadership, delay, W 1 and 4, mismatch, BYE. Extended in step 3: K and S announced both ways, K = max, the new delay rule, version 1 against 2 = incompatible | steps 1, 3 |
| `test_netplay.py` | the Pi's side of MSXNP 2 | step 3 |
| **new** `software/Client/tests/netcore_cost.py` | builds netcore with SDCC as `build.py` does, runs it in `sz80` with stubbed UNAPI calls, and fails if `nc_xchg` takes more than 400 instructions (sending) or `nc_now` more than 20 | step 1, and after every netcore change |
| `lockstep_model.py` | the engine's schedule with K = 1, 2, 3 and D up to 7, with loss and jitter: no frame waits forever, and K = 2 repairs 3 consecutive losses | step 3, before the stub changes |
| `test_gpf.py`, `build_games.py --check` | the rebuilt Soccer package and its new hash | step 3 |
| new Python test for `playnet open`/`peers` | the session record built from the commands | step 5 |

### 8.2 The two-emulator rig

The scenarios are `run_native.sh` as it is, plus `EXTRA_TCL=perf_node.tcl`. Every run compares the two traces (`cmp_pair.py`) and prints the perf table.

| Run | Arguments | Pass |
|---|---|---|
| native pair | `0 0 3000`, `50 8 3000 20` | identical frames, no desync, fps = the baseline (must not regress) |
| mixed | `SCENARIO=mixed`, same two | identical frames; the TCP/IP node's fps at or above 95 % of the native pair's (step 3 onwards) |
| both TCP/IP | `SCENARIO=mixed BOTH=1`, same two | identical frames; fps at or above 95 % of the native pair's after step 4 (or after step 5 for hybrid runs) |
| exit key | `BOTH=1 EXITF=600` | both back at the MSX-DOS prompt, results 1 and 2 |
| desync | `POKEF=900` on a TCP/IP pair | both end with result 4 and the frame number |
| version | `VER2=1` against MSXNP 2 | "incompatible" on both, no game |
| IRC | `SCENARIO=tcp EXITKEY=...` (after Q6) | as today: PONGs during the game, no drop, back on the same connection |
| hybrid | `SCENARIO=tcp HYBRID=1` (step 5) | fps within 2 % of the native pair's, IRC as above |

Measured for every run, in the perf table:
- game frames per emulated second, over frames 500-3000 (after the set-up screens);
- polls per frame, and the share of frames that stalled at least once;
- ms in `XCHG` per frame;
- InterNestor Lite timer runs and link operations per frame;
- sound ticks per second on each node.

**"As fast as the MSXPi link"** means: on the same rig and in the same run conditions, the TCP/IP node's fps is at least 95 % of the native
pair's (98 % for hybrid). Its stall share is at most 2 points above the native pair's, and its music runs at the same ticks per second.

### 8.3 Real hardware

- Canon V-25 + MSXPi + InterNestor Lite (`MSR I`, `INL I`) against an MSXPi peer: `PLAYNET /T soccer C ...` against `PLAYNET` through the chat on the Pi
  (mixed), then two TCP/IP machines if a second one is available.
- Before and after each step: `ETHBENCH` (link cost), ping from the Pi, and a 3000-frame match timed with a stopwatch against a match on
  the MSXPi path. The game's frame counter (E003h in Soccer) read at the start and end gives the frame count.
- GR8NET or another hardware stack when available, to settle Q9 and the right K and S for hardware stacks (expected: K = 1, S = 0, service
  off). GR8NET specifics from its manual (12.4) to keep in mind:
  - it has 3 sockets in all, shared with its BASIC network I/O. A game needs 2 (the IRC TCP connection kept by `MCHAT /T`, and the game's
    UDP port), so nothing else may hold one;
  - `UDP_RCV` returns one datagram per call, and the chip drops datagrams when its receive buffer overflows. netcore already drains it on every
    `XCHG`.

---

## 9. Files reference

| File | Role here |
|---|---|
| `software/Client/src/playnet/netcore/netcore.c`, `netcore.h` | MSXNP engine (portable C): clock units, HELLO/SETUP fields, delay rule |
| `software/Client/src/playnet/netcore/ovl_main.c` | `PLAYNET.OVL`: UNAPI calls, the clock, `irc_keep`, the new `service()` |
| `software/Client/src/playnet/netcore/host/netcore_host.c` | the gcc host for the conformance test |
| `software/Client/src/playnet/transport_unapi.asm` | the TCP/IP transport: page-3 switch, interrupt accounting |
| `software/Client/src/playnet/transport_msxpi.asm` | the C9 transport, the basis for `transport_hybrid.asm` |
| `software/Client/src/playnet/engine/playnet_engine.asm` | the stub engine: K schedule, timed resend, header byte 4 |
| `software/Client/src/playnet/playnet_tcp.asm`, `playnet.asm` | `PLAYNET /T`: switches, stack detection, writing K |
| `software/Server/Python/src/msxpi_netplay.py` | the Pi's MSXNP: version 2, K and S, delay rule |
| `software/Server/Python/src/msxpi_chat.py` | `playnet` commands (step 5) |
| `software/UNAPI/src/ethops.asm`, `software/Server/Python/src/msxpi_eth.py` | the Ethernet driver and its Pi side (step 4) |
| `software/Client/tests/soccernet/run_native.sh`, `cmp_pair.py`, `lockstep_model.py` | the rig, extended with `perf_node.tcl` and `cmp_perf.py` |
| `documents/PLAYNET-PROTOCOLS.md` | to update in steps 2, 3 and 5 (sections 9.1, 10, 11, 13, 15, 16) |
| `documents/PLAYNET-DESIGN.md` | 8a gets the measurements of steps 0 and 6 |
