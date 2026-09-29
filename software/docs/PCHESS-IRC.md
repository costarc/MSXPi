# PChess IRC protocol v1

`#msxpi` is a shared chat channel. PChess ignores ordinary conversation.
Only availability is public: `PRIVMSG #msxpi :PCH1 SEEK`, sent by explicit
user action and limited to once per minute. No positions, moves or ACKs
are sent to the channel. Seeing SEEK displays the available nickname.

After selecting a nickname, all negotiation and game messages use IRC
`PRIVMSG <opponent-nick>`. Nothing requires users to leave the public channel.

1. Challenger sends `PCH1 OFFER <match>` privately. `match` is a random
   64-bit identifier encoded as 16 lowercase hexadecimal characters.
2. Invitee explicitly accepts with `PCH1 ACCEPT <match>`.
3. Challenger sends `PCH1 READY <match>`. Challenger is white; invitee black.
4. Sender sends `PCH1 MOVE <match> <ply> <uci> <before> <after>` privately.
   Ply is one-based; UCI includes the promotion piece when applicable.
   Position hashes are the first 16 hex characters of SHA-256 over
   `python-chess Board.fen()` encoded as ASCII (default en-passant policy).
5. Receiver verifies IRC sender, private target, match ID, turn, expected
   ply, pre-move hash, legal move and post-move hash before accepting.
   It replies `PCH1 ACK <match> <ply> <after>` privately.

Until ACK the sender cannot move again. A pending move is retransmitted
after five seconds, at most three times. An identical repeated MOVE is
acknowledged without applying it again. Unexpected senders, versions and
match IDs are ignored. State mismatches suspend the game; reconnect/resume
and clocks are not part of v1. Both sides independently derive mate/draw.
TCP disconnect is shown as an error, never as a fabricated opponent move.

IRC nickname identity is only as trustworthy as the network; match IDs are
correlation values, not authentication. Use registered nicknames and TLS
for public play. TLS is on by default and certificate verification enabled.

Configuration in each server's local `msxpi.ini` (never commit real passwords):

```text
var IRCADDR=irc.libera.chat
var IRCPORT=6697
var IRCTLS=1
var IRCNICK=pchAlice
var IRCACCOUNT=your_registered_account
var IRCPASSWORD=your_account_password
```

Leave both IRCACCOUNT and IRCPASSWORD absent/empty for unauthenticated joining.
The default network is Libera.Chat, which lets unregistered users exchange
private messages, so no account is needed to play. Libera can temporarily
require login during spam waves or from some cloud/VPN addresses; PChess then
shows `IRC ACCOUNT LOGIN REQUIRED (477)` and a free Libera account fixes it.
freenode (the previous default) requires every player to be logged in.
An account is distinct from a nickname: use a different IRCNICK if another
session already owns the account's usual nick. Credentials must belong to the
IRC network's account service, not necessarily a web or bouncer login.
SASL PLAIN requires certificate-verified TLS; authentication failure stops the
connection, without silently falling back to an unauthenticated session.
Login completes before JOIN. AUTHENTICATE payloads are never traced.
Passwords are stored in plaintext locally: restrict file access to the server
user. IRCPASSWORD is hidden in PSET output and command logging.

MSXPI_INI optionally selects a separate configuration file per server process;
otherwise the existing /home/pi/msxpi/msxpi.ini path is used. Restart the server
after editing the INI. Host/port/nick/TLS PCHESS_IRC environment overrides remain
available for isolated tests, but passwords come from the INI only. For two
authenticated harness clients, set PCHESS_TEST_INI_1 and PCHESS_TEST_INI_2 to their
respective Windows INI paths, then run pchess_dual.py --real-irc.

Host is configurable; availability of the default public endpoint is not
assumed. For an isolated local IRC test only, `PCHESS_IRC_TLS=0` is supported.

Client controls: `4` connects and joins `#msxpi`; `5` advertises availability;
`6`, nickname, Return challenges; `7` accepts the displayed invitation.
Moves use the same notation/arrows/joystick controls as local play.

Wait for `IRC LOBBY <nick>` before advertising or challenging. PChess waits
for registration and its own JOIN confirmation, answers PING independently
of MSX polling, and uses the nickname confirmed by the IRC server. Prefer
nicknames of nine characters or fewer for older networks. Join/registration
failure is reported rather than displaying a false lobby.

PChess uses a separate connection from `IRC.BAS` and the server's `IRC READ`
command, so it cannot consume chat messages intended for BASIC. PChess now
honors IRCADDR/IRCPORT/IRCNICK from the shared configuration. Legacy port 6667
remains plaintext unless IRCTLS is explicitly set; credentials require TLS.
The legacy READ implementation can discard additional lines from a single
TCP read and does not preserve partial lines; it is not suitable as the
reliable transport for chess messages without further changes.

Run the Windows harness with `--irc` for a local fixture or `--real-irc` for
the configured public network. Both modes launch two owned servers on TCP
5041/5042 and two Panasonic_FS-A1WSX emulators with MSXPi and ram4mb, explicitly
switching to DOS C: before launching PCHESS. Real mode uses unique short
nicknames, sends only one public SEEK, and verifies private moves in both
directions plus both graphical boards. PCHESS_IRC_TRACE=1 enables protocol-only
diagnostics (not ordinary channel conversation). Test artifacts are retained
under work/pchess-dual-*; cleanup terminates only processes the harness started.

Live test, 2026-09-28: two Panasonic emulator/server pairs connected over TLS
to chat.freenode.net, joined #msxpi, and received public discovery. The network
rejected the private OFFER with numeric 477: "You need to be identified to a
registered account to message this user". Live moves are therefore NOT verified.
That test preceded account authentication support; completing it needs
working network account credentials, or an
explicitly chosen network permitting unauthenticated private messages. Changing
nicknames does not resolve this policy restriction. No accounts were created.

Post-change local validation: 19 automated tests passed, including two actual
TCP IRC clients. Two OpenMSX clients passed e2-e4/e7-e5 graphical board checks,
private game traffic/public discovery checks, and new-game history clearing.
Artifacts: work/pchess-dual-t2vctd9v. These local results do not imply the live
network's account requirement has been resolved.

Authentication update: SASL support and 22 tests pass. Both supplied test
accounts were rejected by the direct IRC.com/Freenode endpoint; the corrected
SASL exchange reports 904 (authentication failure). Authenticated live moves
remain unverified pending confirmation of account type/credentials.

Successful authenticated live test, 2026-09-28: newly registered accounts
msxpichess1 and msxpichess2 both authenticated over verified TLS and joined
#msxpi. Separate test nicknames pchtest1/pchtest2 avoided disrupting browser
sessions. Two Panasonic_FS-A1WSX + MSXPi + ram4mb emulators, each using its own
server/INI on ports 5041/5042, launched PCHESS from DOS C:. Public SEEK, private
OFFER/ACCEPT/READY, e2-e4/e7-e5 and ACKs all passed. Both VRAM board assertions
and new-game history clearing passed. Channel traffic contained discovery
only. Artifacts: work/pchess-dual-zshbp63t. All 23 automated tests pass.
Credentials remain in local INI files outside the repository, not in this guide.

Libera.Chat live test, 2026-09-29: two Panasonic_FS-A1WSX + MSXPi + ram4mb
emulators, each with its own server/INI on ports 5041/5042, connected over
TLS to irc.libera.chat:6697 as msxpichess1/msxpichess2 with no account or
password. Public SEEK, private OFFER/ACCEPT/READY, e2-e4/e7-e5 and ACKs all
passed, both VRAM board checks and new-game history clearing passed, and the
channel carried discovery only. Artifacts: work/pchess-dual-1yngqsw6.
