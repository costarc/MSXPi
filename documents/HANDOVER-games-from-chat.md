# Handover: online games from MSX Free Chat (Konami's Soccer first)

Written 2026-10-19 at the end of a long session. Read this first, then `documents/MSXCHAT-GAMES.md` (the contract),
`documents/SOCCERNET-NETPLAY.md` (design notes and test history of the game engine) and the file headers named below.

## 1. Goal

MSX Free Chat (`MCHAT.COM`) becomes a general chat. From it a player invites another to an **online game**; the chat
starts the game program on both MSX machines. The chat, the launcher contract and the server side must be **generic**
(any game, not just soccer). Konami's Soccer (RC-732, 32 KB MSX1 ROM) is the first game: lockstep over the internet, each
MSX runs the whole game and only the two joystick bytes cross the network, through the MSXPi (Pi/PC server does the UDP).
The user's own `SOCCER.ROM` is never distributed or modified on disk: a loader patches a RAM copy.

## 2. Where everything is (three places, two branches that matter)

| What | Where | Branch / state |
|---|---|---|
| Chat branch (this document lives here) | worktree `C:\Users\roniv\Dev\github\MSXPi\.claude\worktrees\msx-freechat` (was locked by an old, idle "MSX Free Chat" session; taken over on request) | `worktree-msx-freechat`, pushed to `origin` (costarc/MSXPi). HEAD `0f8004a0`. Rebased onto `origin/master` (7d0bddaa) and merged with `netplay`. |
| Game engine branch | worktree `C:\Users\roniv\Dev\github\MSXPi-netplay` | `netplay`, pushed. HEAD `067ac034`. Already merged into the chat branch. |
| Reference only | `C:\Users\roniv\Dev\github\Konami-Soccer` (clone of `antxiko/KonamisSoccer-disassembly`) | **Read-only reference.** Local branch `netplay-wip` has two commits of the old prototype; push is refused (403, not ours). Do not push there, do not add work there. Contains `soccer.rom` (the user's dump, SHA-256 `b9536809...dcd4`), `HANDOVER.md`, `ARCHITECTURE-REVIEW.md`, `NETPLAY.md` and the prototype rigs (TAP adapters, file mailbox) that were deliberately not brought over. |

Rule the user set: **our work lives in worktrees of MSXPi, never in the Konami clone.** Other Claude sessions share the main
checkout (`C:\Users\roniv\Dev\github\MSXPi`, currently on another branch): never switch branches there, never use bare
`git stash` (shared stack; one stash of mine was popped by mistake once, harmlessly). Commit/push only when asked; the user did
ask for commits and pushes of both branches.

Keep the two branches in step: engine files (`software/Client/src/soccernet/`, `msxpi_netplay.py`, its tests, the `run_native.sh`
rig) are developed on `netplay` and merged into the chat branch with `git merge origin/netplay`; chat files
(`msxpi_chat.py`, `msxpi_games.py`, `mchat.c`, `chat_node.tcl`, `documents/MSXCHAT-GAMES.md`) belong to the chat branch.
Eventually both go to master together (no PR opened yet).

## 3. What exists and works (all verified in openMSX, **scripted input only, nothing on real hardware**)

**Engine (`netplay` branch)**
- `software/Client/src/soccernet/`: `soccernet.asm` (DOS-phase loader + patch table, hard-coded for one ROM dump), `stub.tmpl.asm`
  (resident lockstep stub at F000h; native MSXPi transport, handshake, negotiated input delay, desync check, dead-peer reset),
  `gen_stub.py`/`gen_inc.py`, `rom_check.py`, `build.sh`, `udptest.asm` (UNAPI UDP test, uses the standard dispatch), `unapi.tmpl.inc`
  (**not yet ported** to the standard dispatch), `README.md`.
- `software/Server/Python/src/msxpi_netplay.py`: MSXPi opcode `0xC9` transaction (header documents the wire format), session API
  `instance()`, `open()`, `candidates()` (LAN + STUN), `set_peers()`, `close()`, `describe()`; HELLO/version handshake, RTT-based
  delay (2..6 frames), keep-alive/dead detection (15 s), delay/loss/jitter injection for tests. Hooked in `msxpi_ethglue.py`
  (`eth_handle_opcode`), listed in `SERVER_MODULES` of `msxpi-server.py`.
- Tests: `software/Server/Python/tests/test_netplay.py` (24 tests). Rig: `software/Client/tests/soccernet/run_native.sh`.

**Chat (`worktree-msx-freechat` branch)**
- `software/Server/Python/src/msxpi_games.py`: game registry (`Game`, `load_registry`; built-in `soccer`; extra games from
  `msxpi.ini` `MSXGAME_*` — **to be removed, see section 6**) and the invitation state machine `Invites` (private IRC messages
  `MSXG1 INVITE/ACCEPT/GO/DECLINE/CANCEL`, expiry 120 s/180 s, one game at a time, results reported on resume).
- `msxpi_chat.py`: `/play NICK [GAME]`, `/accept`, `/decline`, `/cancel`, `/games`; header byte 22 flags (1 = game ready,
  2 = invitation waiting); command `mchat launch` returns an `L` packet with the MSX-DOS command line.
- `software/Client/src/mchat.c`: on the launch flag it fetches the line, stuffs it into the BIOS keyboard buffer
  (FBF0h, pointers F3F8h/F3FAh), restores the screen and returns to MSX-DOS **without** `mchat quit` (the chat survives on the
  server, `MCHAT` resumes it). **Ctrl-U** = pick a player from the user list (Up/Down/Enter puts `/play NICK ` on the input line).
  `software/target/mchat.com` is rebuilt (48,922 bytes, image ends near 0xC020: not tested with the TCP/IP driver loaded, where the
  TPA top can be only 0xC806 — open item).
- Tests: `test_games.py` (23 with `test_chat`; includes two real chats on the IRC fixture + real netplay sessions);
  98 tests pass across `test_chat test_games test_netplay test_pchess_irc test_pcheckers_irc`.
- **End-to-end rig**: `SCENARIO=chat` (add `PICK=1` to invite through the user list): two emulated MSX meet in MCHAT, one invites,
  the other accepts, the chat types `SOCCERNET H`/`SOCCERNET C`, the game starts, sessions connect (leader election, delay 3 on
  localhost) and the two machines are compared frame by frame: 901 frames identical (typed `/play`), 506 overlapping frames
  identical (Ctrl-U pick; machine C's trace started at frame 95, a tracing artifact).
- Not covered end to end: the return to the chat after a game (unit-tested only).

Soccer-specific results kept in `documents/SOCCERNET-NETPLAY.md`: lag 50 ms + 20 ms jitter + 8 % loss, 3001 frames identical;
version mismatch, injected desync and a vanished opponent all behave as designed.

## 4. How to build and run

Build environment is Windows (Git Bash for `sh` scripts, PowerShell for the MSX C build). Python 3 (Windows), sjasmplus
(`C:\Users\roniv\Dev\bin\sjasmplus.exe`), openMSX Windows build with the MSXPi device
(`C:/Users/roniv/Dev/MSX/MSXPi/openmsx-MSXPi_v1.7.0/openmsx.exe`). Memory notes: run openMSX freely unless the user says it is
busy; the test machine is the Canon V-25 (an MSX2) with ram2mb + MSXPi.

- Loader and stub: `SJASMPLUS=/c/Users/roniv/Dev/bin/sjasmplus.exe sh software/Client/src/soccernet/build.sh` ->
  `build/prod/SOCCERNET.COM` (real joystick, built, **never run**) and `build/test/SOCCERNET.COM` (scripted input, used by the rigs).
  The stub budget is tight: the game's stack reaches F30Ch, the test stub ends at F300h (assert in `stub.tmpl.asm`), production
  is ~39 bytes shorter. There is no free space in the ROM to move code into.
- `mchat.com`: needs the MSX C toolchain and a **junction** `C:\Users\roniv\Dev\github\MSXPi\.claude\MSX` ->
  `C:\Users\roniv\Dev\MSX` (the sources include Fusion-C headers through a relative path five levels up; the junction exists now,
  it is outside both repos). Run a copy of `software/make.bat` with absolute paths from PowerShell (see section 7) —
  `make.bat <name>` itself resolves `..\..\..\MSX` relative to `software\`, which breaks inside `.claude\worktrees\...`.
- Unit tests: `cd software/Server/Python/tests && python -m unittest test_chat test_games test_netplay`.
- Rig (about 12 minutes, runs two emulators and two servers; ports 8115/8116 and IRC 6671 — **8015/8016 belong to other sessions**):
  `cd software/Client/tests/soccernet && SOCCER_ROM=C:/.../soccer.rom [SCENARIO=chat] [PICK=1] TMAX=900 NODETMO=1000 sh run_native.sh <lag_ms> <loss_pct> <frames> [jitter_ms]`.
  Work files go to `%TEMP%\soccernet-work` (`np/H.trace`, `C.trace`, `.screen`, server logs). Other env switches are in the script header
  (`ONLY=H`, `FORCE_DELAY`, `VER2`, `POKEF`, `EXITF`). `cmp_pair.py` compares the two traces; the script's last lines sometimes
  print nothing, run `cmp_pair.py` by hand on the traces if so.

## 5. Pitfalls that cost time (do not repeat)

- Tcl `type "...\r"`: the file must contain backslash + `r`, not a CR byte. Writing it through shell here-documents turned it into a
  real CR twice; use the Edit tool or `chr(92)` in a script file, and check with `grep -c $'\r' file` (must be 0).
- File names on the MSX disk are 8.3 (`SOCCERNAT.COM` made DOS hang).
- The 8-bit frame counter wraps every 256 frames: "frame 0" logic must be guarded by state, not by the counter (this restarted the
  handshake at frame 256 once).
- `ld bc,16` where B must be 16 made a 256-iteration loop that overwrote the stub; check register pairs.
- On Windows a UDP send to a closed port makes the next `recvfrom` raise `ConnectionResetError`; the receive loop must continue.
- Session nonces must not come from a seeded generator (both servers had the same seed and never elected a leader).
- Another session's openMSX/server may use ports 8015/8016; the process `C:\home\pi\msxpi\msxpi-server.py` is not ours.
- Shell here-documents mangle backslashes and some bytes (a STUN magic-cookie literal got corrupted): write files with the Write/Edit
  tools or put the escape in a named constant.
- After the game resets the MSX, the BIOS would boot the RAM copy as a cartridge (it has the `AB` header): `fatal` wipes 4000h/4001h first.
- `git` here converts line endings (autocrlf): files in the repo are mixed; shell scripts have `.gitattributes` `eol=lf` in the soccernet folders.

## 6. The design decision taken last (NOT yet implemented — start here)

Design review with the user (see the discussion end of the session). Agreed direction:

1. **Game profiles live on the server**, one file per game, in a separate folder under the MSXPi home (`/home/pi/msxpi/games/`),
   not in `msxpi.ini`. They hold the registry data (id, title, launch command, roles, transport) **and** the per-game patch
   information. Remove `MSXGAME_*` handling from `msxpi_games.py` and `DEFAULT_GAMES`; the chat lists games by reading the profiles.
2. **Adding a game = adding a profile file.** The loader must know how to patch it from the profile alone.
3. **Profiles are updated by `msxpiupd.bat`.** That batch only runs `msxpirfh.bat`, which runs `update.sh` on the Pi
   (`software/Server/Setup/update.sh`, downloads named files from GitHub raw, atomic replace). Raw GitHub cannot list a folder, so
   add an **index file** with each profile's hash; `update.sh` fetches and verifies them. User-added profiles go in a second
   folder (suggested `games.local/`), never touched by the updater; a local id wins on a clash.
4. **Recommended refinements agreed in principle (the user has to confirm the three questions below):**
   - Make the loader **generic** (suggested name `PLAYNET.COM <game> <role>`): it asks the Pi for the profile (compact binary,
     validated server side; bounds: patches only inside the ROM or stub area, size limits) and applies it. Both players then
     always run identical patches, which lockstep needs. Include a **hash of the profile in the invitation** so players with
     different revisions are warned or declined (replaces the hand-kept `version` number).
   - A profile is data, not code: it can describe ROM recognition (size + hash, several revisions), byte patches, NOP ranges, call
     redirections to stub entries, value patches (the shortened RAM-clear lengths) and **stub parameters** (frame counter address,
     sound-tick address, state-check region E100-E2FF, RNG replacement, pad-read hook sites). A game needing a new hook kind or a
     different determinism fix still needs new stub code; the profile chooses among hook kinds the stub has. Validate the schema by
     sketching a **second game on paper** before freezing it; give it `format=1`.
   - Version 1 supports plain 16/32 KB ROMs only (mapper ROMs cannot be copied into a 32 KB RAM image).
   - Games that bring their own program (e.g. PChess) can still be profiles with no patch section.
5. **Open questions for the user** (ask first): (a) profile format: plain `key = value` text with comments (recommended, no
   dependency) or TOML (needs Python 3.11 on the Pi — which Pi OS baseline is supported?); (b) names `games/`, `games.local/`,
   `PLAYNET`; (c) scope = plain 16/32 KB ROMs for version 1.
6. Suggested order: write the schema as a short design document -> parser/validator/binary encoder in Python -> convert Soccer to
   the first profile and **prove equivalence** (build the patched RAM image the old way and the new way, compare byte for byte; the
   current patch table is in `soccernet.asm` near line 250, ROM check values in `rom_check.py`) -> generic loader fetching the
   profile through an MSXPi command or an extra flag of opcode C9 -> chat reads the folder -> `update.sh` + index -> "how to add a game".

## 7. Other open items (in rough priority)

1. Everything above in section 6 (the user's latest direction).
2. Real-joystick production stub (`build/prod`) has never run; the first real test of `readLocal -> LEEMANDO1`.
3. Port `unapi.tmpl.inc` to the standard UNAPI dispatch (RAM helper `CALL_MAP` / `CALSLT`, `ei` after each call, buffers outside
   page 1) as the second transport backend for GR8NET/ObsoNET etc. `udptest.asm` already shows the working pattern; known risks:
   the game bypasses H.TIMI so a RAM-based stack (InterNestor Lite) needs its timer routine called per frame and JIFFY advanced.
4. Real hardware: nothing has run on a real MSX or a real Pi; the cost of the two ~15-byte polled transactions per frame is unmeasured.
   STUN has only been tested against a local fake server; hole punching only on one machine (candidate 127.0.0.1).
5. `mchat.com` free-memory check with the TCP/IP driver loaded (image ends near 0xC020).
6. A connect screen: while the opponent is slow the title is blank (the stub waits in `connect`).
7. Return to chat after a game on the emulators (only unit-tested), and a game picker when several games are registered
   (Ctrl-U inserts `/play NICK `; the user types the game name).
8. In `/t` mode (chat over TCP/IP without the Pi) games cannot start; documented.
9. Clean up: mailbox-transport variant of the stub (no `-DNATIVE`) is dead code kept for the old rig; the old
   `Konami-Soccer/netplay-wip` branch is local only.
10. No PR yet. When the user asks: master <- `netplay` and `worktree-msx-freechat` (they overlap; merging the chat branch carries the engine).

## 8. Reading list for the next session

`documents/MSXCHAT-GAMES.md`, `documents/SOCCERNET-NETPLAY.md`, `software/Client/src/soccernet/README.md`, the header of
`software/Server/Python/src/msxpi_netplay.py` and `msxpi_games.py`, `software/Client/tests/soccernet/run_native.sh` (usage),
`C:\Users\roniv\Dev\github\Konami-Soccer\ARCHITECTURE-REVIEW.md` (why the transport is MSXPi-native), and the earlier prototype
`HANDOVER.md` there for the Soccer ROM details (patch table meaning, determinism fixes: sound tick once per frame, Z80 R register,
three anti-copy self-modifying writes, RAM clears shortened so the stub at F000h survives).
