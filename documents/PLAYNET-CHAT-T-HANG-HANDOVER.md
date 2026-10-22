# Handover: the `MCHAT /T` hang after an invitation

Written 2026-10-22 on `feature/tcpip-games`. This is a bug to find, not a feature to build. Nothing in this document was reproduced by the
writer: it collects what is recorded, says what is not known, and proposes how to look. Facts are marked **known**, guesses **guess**.

## 1. What it blocks

- `MCHAT /T` (the chat over TCP/IP) with its game agent: `/play`, `/accept`, the hand-over to `PLAYNET /T` through `PLAYNET.SES`, and the way back.
- PLAYNET step 5 (the game packets of a TCP/IP chat player through its MSXPi, link 2): the loader, the transport and the Pi's `playnet open` /
  `playnet peers` are done and measured (27.49 fps on the rig, `fbcb26cd`), but the part that makes a chat player *use* link 2 lives in the
  game agent, which is not in the tree. See `PLAYNET-TCPIP-PERFORMANCE.md` 5.5 and section 7 (step 5).
- Not blocked: `PLAYNET /T game role lport ip:port` and `PLAYNET /T /H game role` (manual starts) and everything measured so far.

## 2. What is recorded

**Known** (commit message of `0c4ac631`, on `master` and on this branch): with `games_local.c` the `mchat.com` grew from 48922 to 49757 bytes,
and "the chat hung on real and emulated machines after the invitation". `0c4ac631` removed `games_local.c`, `games_local.h` and the game
code in `mchat_local.c`, and put `target/mchat.com` back to the 48922-byte build (`mchat.c`, `mchat_local.c` as of `0f8004a0`).

**Known**: the rig passed with the agent present. At `894fac7e`, `SCENARIO=tcp` (two openMSX, both chatting over TCP/IP against the IRC fixture,
`/play`, `/accept`, the game, the way back) gave identical frames and no desync, and the IRC keep-alive held (63 PONG in 30 s, no drop). So
the bug does not show in the rig as it is configured, and it did show on the writer's real machine (Canon V-25 with an MSXPi) and on an
emulated one that is not the rig. What differs between those machines and the rig is the first thing to find out.

**Not known**: where it hangs (which side, inviting or invited; on `/play`, on `/accept`, or at the hand-over), whether the screen still
updates, whether the keyboard answers, whether MSX-DOS is alive. None of this was written down. Ask the user first, or reproduce.

## 3. Where the code is

It is not in the tree. Recover it from history:

```
git show 0c4ac631^:software/Client/src/games_local.c   > software/Client/src/games_local.c      (397 lines)
git show 0c4ac631^:software/Client/src/games_local.h   > software/Client/src/games_local.h      (57 lines)
git show 0c4ac631^:software/Client/src/mchat_local.c   > software/Client/src/mchat_local.c      (the version with the agent)
git show 0c4ac631^:software/Client/src/mchat.c         > software/Client/src/mchat.c            (one line differs)
```

Do it in a worktree of its own (the parallel-session rule), on a branch cut from `feature/tcpip-games`. The agent was added by `8a081a00`
(PLAYNET step 8) and `8072c88e`.

- `games_local.c` is portable C, the twin of the Pi's `msxpi_games.Invites`; `test_games_local.py` (in `software/Server/Python/tests`, still in
  the tree) builds it with gcc and plays it against `Invites`. Run it first: if it fails, the protocol logic is at fault, not the MSX.
- The MSX glue is the "games (PLAYNET)" section of `mchat_local.c`: `gl_seconds`, `gl_random`, `gl_open` (the game's UDP port and
  candidates), the `PLAYNET.SES` write, `gl_restore` after the game, and the launch in the main loop (`gl_take_launch`).
- The chat's own memory check is in `tcp_link_start()`: `top = word at 0006h`; it refuses when `top - heap_top < STACK_ROOM` (768).

Build with `python software/Client/tests/soccernet/build_client.py mchat OUTDIR` (SDCC and fusion-c; the same options as `make.bat`, from any
checkout; it writes only `OUTDIR/MCHAT.COM`). Do not run `make.bat` for this: it copies into `target/` and into the emulator folder.

## 4. Guesses, in the order worth testing

1. **The program is too big for the machine's TPA, or collides with its own stack/heap (guess).** The agent added 835 bytes. The image of the
   small build already ends at `C019h`; the large one at about `C2DEh`, plus the BSS, the 768 bytes of stack room and `net_area`. MSX-DOS 1
   does not refuse a `.COM` that overruns the word at `0006h`; it overwrites the BDOS area, which fails later, in a BDOS call, far from the
   cause. The tests that matter: print `*(uint16_t*)6`, the image end and `heap_top` on the failing machine (a debug line in `tcp_link_start`),
   and compare with the rig (`SCENARIO=tcp` can print them too). The TPA top depends on the disk ROMs and drivers present, INL, `MSR`, the
   disk drive count: exactly what differs between a real machine and the rig. A real machine without a floppy (Canon V-25, MSXPi boot)
   and one with a built-in drive have different tops. This also explains "hung after the invitation": the first BDOS-heavy step after
   start-up is writing `PLAYNET.SES`.
2. **The BDOS write of `PLAYNET.SES` with the IRC connection resident (guess).** `MCHAT /t` opens the TCP connection with the resident flag and
   leaves it open; the file write goes through MSX-DOS and the MSXPi/disk ROM with interrupts and the stack's timer (H.TIMI) running. A
   write that never returns would look like a hang right after the hand-over. Test: stop the agent right before the write and write a
   file of the same size without the chat connection; then with it.
3. **`gl_open` (guess).** The agent opens a UDP port to learn the candidates and `PLAYNET /T` opens the same local port later. If the chat does
   not close its port before launching, `UDP_OPEN` can fail or block in PLAYNET (it reports "no port", which is not a hang) or the stack can
   misbehave. Check `gl_open`'s port handling at the launch.
4. **A loop without a bound in the agent (guess).** `games_local.c` has few loops (see `grep -n while`); `gl_seconds` reads the time:
   check what it reads and that it keeps counting with the interrupt hooks in the state the chat leaves them. A deadline that never
   expires, or one that expires at once, would change what the user sees.
5. **The Pi side (guess, least likely).** `Invites` and the chat commands are unchanged by this; the Python tests pass.

## 5. Reproducing

Rig (known to pass; the first job is to make it fail):
- `SCENARIO=tcp` in `software/Client/tests/soccernet/run_native.sh` (needs `SOCCER_ROM`, an openMSX with the MSXPi device, `sjasmplus`; see the
  header of the script; use a **copy** of the openMSX install). It builds `MCHAT.COM` with `build_client.py`, starts the IRC fixture and two
  servers, and drives both nodes with `chat_node.tcl`.
- Vary what the rig fixes: the machine (`-machine`), the RAM extension, the boot (`BOOT=nextor` for MSX-DOS 2), whether `MSR I` / `INL I` run
  first, the number of drives. The aim is one configuration where `mchat /T`, `/play` then `/accept` stops.
- The rig's trace and `$WORK/np/*.log` show the last screen text; `EXITKEY=1` makes the game end by the exit key and checks the way back.

On the failing machine: run the build with debug prints (the three numbers of guess 1, and one line before and after each step of the
launch: the `PLAYNET.SES` open, write, close, then the command typed into the keyboard buffer). Note the last line printed.

Python side: `python -m unittest test_games_local test_games` in `software/Server/Python/tests` (the C agent against the Pi's `Invites`).

## 6. What "fixed" looks like

- `SCENARIO=tcp EXITKEY=1`: both chat, invite, play, leave by the exit key and land back in `MCHAT /T` with the connection alive (the checks the
  script already makes), with the agent's `mchat.com` **and** on the configuration that used to hang.
- The size of `mchat.com` and the TPA top of the supported machines are written down; if guess 1 is right, either the agent gets smaller,
  or the chat moves its buffers out of the TPA (it already puts `net_area` in page 2 or 3, see the comment above `NetMem`), or `MCHAT /T`
  refuses to start with a clear message when `0006h` is too low (the existing "Not enough memory for TCP/IP" check measures only the heap).
- Then the link-2 change of step 5: in the agent, when the Pi answers `playnet open <game>`, announce the Pi's candidates instead of INL's,
  pass the opponent's to `playnet peers`, and write `PLAYNET.SES` with link 2. The loader accepts that record already
  (`tcpSession`, link 2 sets `hyb`); the Pi commands are in `msxpi_chat.playnet_command` with a test in `test_games.py`. Rig:
  `SCENARIO=tcp HYBRID=1` does not exist yet (`HYBRID=1 SCENARIO=mixed` does).

## 7. Related, already done on this branch

`fbcb26cd` step 5 (link 2: `transport_hybrid.asm`, `PLAYNET /T /H`, `playnet open|peers`); `ceeec205` LDIR `memcpy`; the K/S sweep; the
Ethernet driver protocol 2 (`feature/eth-tx-otir`, rebased in). Results are in `PLAYNET-TCPIP-PERFORMANCE.md` 5.7a.
