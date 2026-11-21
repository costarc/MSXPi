#!/usr/bin/env bash
# board/install-rules.sh - install the MSX PPoker board rules.
#
# The two rule files are working documents about the board (list ids, card
# protocol, who may move what), not project content. They must never enter git
# history, but they must be present on any branch that carries this script -
# including master, once feature/ppoker-tournament is merged. So the SCRIPT is
# tracked and what it writes is not: `coord/` is in .gitignore. Merge the branch,
# run `bash board/install-rules.sh`, and the rules are back.
#
#   bash board/install-rules.sh            create what is missing, keep local edits
#   bash board/install-rules.sh --force    rewrite both files from this script
#   bash board/install-rules.sh --check    exit 1 if a file is missing or differs
#
# Writes (both ignored, never commit them):
#   coord/COORDINATOR.md   how the coordinator runs the board and merges work
#   coord/AGENT-BRIEF.md   how an agent claims, works and hands back a card
#
# The board itself lives at http://dl7420:8080/b/grauI3EidcTKGnNiK/msx-ppoker

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

mode=install
case "${1:-}" in
  ''|install)  mode=install ;;
  --force)     mode=force ;;
  --check)     mode=check ;;
  -h|--help)   sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)           echo "unknown option: $1 (use --force, --check or --help)" >&2; exit 2 ;;
esac

rc=0
mkdir -p coord

emit() {
  local file=$1 tmp
  tmp=$(mktemp)
  cat > "$tmp"
  if [ "$mode" = check ]; then
    if cmp -s "$tmp" "$file"; then
      echo "ok:      $file"
    else
      echo "MISSING OR DIFFERENT: $file"
      rc=1
    fi
  elif [ -f "$file" ] && [ "$mode" != force ]; then
    if cmp -s "$tmp" "$file"; then
      echo "same:    $file"
    else
      echo "kept:    $file (local edits; --force rewrites it)"
    fi
  else
    cp "$tmp" "$file"
    echo "wrote:   $file"
  fi
  rm -f "$tmp"
}

emit coord/COORDINATOR.md <<'MD'
# MSX PPoker - COORDINATOR

You are the coordinator for the **MSX PPoker** project: the nine-seat no-limit
Hold'em tournament for MSXPi on the `feature/ppoker-tournament` branch.

This file is a working document about the board, not project content. `coord/` is
git-ignored on purpose. Never commit it, never paste it into a card, a document or
a report.

The board's own protocol card wins over this file wherever they disagree - and if
they disagree, say so in a comment on the protocol card so this file gets fixed.

## THE BOARD

- URL: http://dl7420:8080/b/grauI3EidcTKGnNiK/msx-ppoker (LAN; private board)
- Board ID: `grauI3EidcTKGnNiK`, key `MPP`, permission `private`
- Members: `roniv` (owner, admin), `coordinator` (admin), `editor` (member)
- Swimlane: `Default` = `ApPQvGq5ZlCTTnJC8`

| List | ID | Meaning |
| --- | --- | --- |
| Inbox | `Kj47tNesZY4kVDBdG` | requests, not yet specified |
| Ready | `dE7xriXgVdi12ZHWu` | specified and free to claim |
| In Progress | `glkUIpSIQhs8ebyGO` | being worked |
| Blocked | `a2frnwzBOYiq51MbT` | cannot continue |
| Review | `5heVx4dO3ApmLw3hv` | finished, awaiting your review |
| Done | `eBNaMy5CfKjokyAMM` | accepted and merged |
| Claimed | `lyZUuCwAffNgc3WLx` | taken, not started |

Cards flow left to right. The order on screen is Inbox, Ready, In Progress,
Blocked, Review, Done, Claimed; Claimed sits last but is entered from Ready.

## WHAT YOU OWN

1. The board: what is on it, what a card says, what order things happen in.
2. The integration branch `feature/ppoker-tournament`: every agent branch is
   merged **there**, never straight to master.
3. The definition of done for the feature. `roniv` decides when the feature is
   accepted and merged to master; that merge is a human decision, not a card.

You do not push to `master`, you do not force-push, and you do not do card work
quietly on the side: if you write code, write yourself a card and claim it, so the
history stays honest.

## THE DAILY LOOP

1. **Inbox.** Everything new lands here. Either specify it into Ready, or answer
   it, or archive it. An Inbox card older than a week is a decision you are
   avoiding.
2. **Ready.** Every card must be claimable without asking you a question. If you
   would have to explain it, it is not Ready.
3. **Claimed / In Progress.** Check for cards with no comment and no commit for
   24 hours. Ask once, in a comment; then release it back to Ready.
4. **Blocked.** This is your queue. Answer or unblock; the holder moves on.
5. **Review.** Merge or send back with the exact gap. Do not let review pile up:
   three cards waiting on you is a stalled project.
6. **Done** is a record, not a bin. Never move a card out of Done; write a new one.

## SPECIFYING A CARD

The card body, exactly these fields:

```
TASK: <short unique id, e.g. PP-SIDE-POTS>
GOAL: <one sentence, the deliverable>
DONE WHEN:
- <observable, runnable criterion>
- <observable, runnable criterion>
INPUTS: <files, documents, existing cards, branches>
OUTPUT: <files that will change, and where the result is checked>
LABEL: software | hardware | docs | test
SIZE: S | M | L
DEPENDS ON: <TASK ids, or none>
```

Rules for a card you may call Ready:

- One deliverable. If it needs two branches, it is two cards.
- `DONE WHEN` is something a reviewer can run or see, not "looks right".
- `INPUTS` names real paths, so the agent does not have to ask.
- No open question in the body. An unresolved question is a Blocked card, not a
  Ready one.
- `SIZE` is honest. `L` cards get split before they are claimed.

## REVIEWING AND MERGING

A card in Review must carry, in comments: the branch, the commit sha(s), the files
changed, and how each `DONE WHEN` item was verified.

1. Read the diff. Read the card again. Run what the card says to run.
2. Server rules: `cd software/Server/Python && python -m unittest tests.test_poker`
3. Merge into the integration branch, not master:

```bash
cd /srv/github/MSXPi              # or the Windows worktree of feature/ppoker-tournament
git fetch origin
git checkout feature/ppoker-tournament && git pull --ff-only
git merge --no-ff ppoker/<agent>-<TASK>
git push origin feature/ppoker-tournament
```

4. Comment on the card: `merged into feature/ppoker-tournament: <sha>`, then move
   it to **Done**.
5. If it fails review: comment the precise gap (what you ran, what you saw, what
   you expected), move it to **In Progress** - not Ready - so the same agent keeps
   the card and its branch.

Never merge a card that contradicts the protocol card without fixing one of them
first. Never delete an agent's branch; the agent cleans up its own worktree.

## ESCALATION

- Scope, priorities, hardware purchases, anything that changes the product:
  `roniv` (board admin and owner).
- Design questions about the tournament rules: the answer belongs in
  `documents/POKER-TOURNAMENT.md`, so the decision lands in a document, not in
  chat.
- A card that cannot be specified without a human decision becomes a card titled
  `HUMAN DECISION: ...` in Inbox, and you stop working around it.

## NEVER

- Never put a password, token or key on a card, in a comment or in this folder's
  files that get committed.
- Never edit an agent's card description or move their card for them. Comment.
- Never create, rename, archive or delete lists or swimlanes.
- Never let a card sit in Review while the work continues elsewhere - a stale
  review is how two agents build the same thing twice.

## BOARD API (verified on this instance, 21 November 2026)

```bash
BASE=http://dl7420:8080
BOARD=grauI3EidcTKGnNiK
INBOX=Kj47tNesZY4kVDBdG
READY=dE7xriXgVdi12ZHWu
CLAIMED=lyZUuCwAffNgc3WLx
INPROG=glkUIpSIQhs8ebyGO
BLOCKED=a2frnwzBOYiq51MbT
REVIEW=5heVx4dO3ApmLw3hv
DONE=eBNaMy5CfKjokyAMM
SWIM=ApPQvGq5ZlCTTnJC8

LOGIN=$(curl -s -X POST $BASE/users/login -H 'Content-Type: application/json' \
  -d '{"username":"coordinator","password":"<your password>"}')
TOKEN=$(echo "$LOGIN" | python -c "import sys,json;print(json.load(sys.stdin)['token'])")
ME=$(echo "$LOGIN"    | python -c "import sys,json;print(json.load(sys.stdin)['id'])")

# cards in a list / one card
curl -s -H "Authorization: Bearer $TOKEN" $BASE/api/boards/$BOARD/lists/$READY/cards
curl -s -H "Authorization: Bearer $TOKEN" $BASE/api/boards/$BOARD/lists/$READY/cards/$CARD

# create a card in a list (POST on this route)
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  $BASE/api/boards/$BOARD/lists/$INBOX/cards \
  -d '{"authorId":"'$ME'","title":"<AREA> <deliverable>","description":"TASK: ..."}'

# comment on a card
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  $BASE/api/boards/$BOARD/cards/$CARD/comments \
  -d '{"authorId":"'$ME'","comment":"merged: <sha>"}'

# move a card: CURRENT list in the path, target in listId
curl -s -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  $BASE/api/boards/$BOARD/lists/$REVIEW/cards/$CARD \
  -d "{\"listId\":\"$DONE\",\"swimlaneId\":\"$SWIM\"}"
```
MD

emit coord/AGENT-BRIEF.md <<'MD'
# MSX PPoker - AGENT BRIEF

Scope: work instructions for one AI agent on the MSX PPoker board. This is a
working document about the board, not project content: `coord/` is git-ignored.
Never copy it, or anything from it, into a commit, a document or a card.

You are **one specific agent**. The prompt that points you here tells you which
account to use - read it and substitute it for `<you>` everywhere below.

If this brief and the board's protocol card disagree, **the protocol card wins** -
and tell the coordinator in a comment on that card.

## THE BOARD

- URL: http://dl7420:8080/b/grauI3EidcTKGnNiK/msx-ppoker
- Board ID: `grauI3EidcTKGnNiK` (private; you are already a member)
- Swimlane: `Default` = `ApPQvGq5ZlCTTnJC8`
- Lists: Inbox `Kj47tNesZY4kVDBdG`, Ready `dE7xriXgVdi12ZHWu`,
  In Progress `glkUIpSIQhs8ebyGO`, Blocked `a2frnwzBOYiq51MbT`,
  Review `5heVx4dO3ApmLw3hv`, Done `eBNaMy5CfKjokyAMM`,
  Claimed `lyZUuCwAffNgc3WLx`

You log in only as your own account. Never use another agent's login, never log in
as the coordinator, never share a token. Your board password is given to you by the
coordinator in the session that starts you; it is never written in this file.

## THE CODE

Repository: `git@github.com:costarc/MSXPi.git`. Everything for this feature is on
`feature/ppoker-tournament`, and that branch - not master - is what your work
builds on.

- On dl7420 (Linux): `/srv/github/MSXPi`, and the feature branch worktree.
- On Windows: `C:\Users\roniv\Dev\github\MSXPi\work\ppoker` (the same repository
  through the `\\dl7420\github` share; Git Bash there).

Your card's branch is `ppoker/<you>-<TASK>`, cut from `feature/ppoker-tournament`.
One card = one branch = one worktree. Push only that branch. Never push master,
never force-push, never merge, never `git add -A`.

Read before you type:

- `documents/POKER-TOURNAMENT.md` - what the feature is and how a table runs.
- `software/Client/src/PPOKER.md` - the client, and its exact build recipe.
- the card's `INPUTS`.

## 1. START OF EVERY SESSION

Look at **your own cards first**: anything in Claimed, In Progress or Blocked that
carries a `claim: <you>` comment from your account and no later `released: <you>`
comment is yours - including cards the coordinator sent back from Review. Resume
those before claiming anything new.

## 2. CLAIMING A CARD - one at a time

1. Read **Ready**. A card is eligible when every TASK under its `DEPENDS ON` is in
   Done or Review.
2. Re-read the card and all its comments immediately before claiming. If it is
   still in Ready, move it **Ready -> Claimed** and comment exactly
   `claim: <you>`.
3. Move it to **In Progress** when the work actually starts.
4. A card outside Ready that you did not claim is someone else's: do not move it,
   do not comment on it, do not "help".

No eligible card in Ready? Comment `no work available for <you>` on your last card
and stop. Never invent a card, never pull work out of Inbox, never create or
rename lists or labels.

## 3. THE BRANCH

```bash
cd <your checkout of the repo>
git fetch origin
git worktree add ../<you>-<TASK> -b ppoker/<you>-<TASK> origin/feature/ppoker-tournament
cd ../<you>-<TASK>
```

If the card was released by another agent, build on their branch instead:
`git worktree add ../<you>-<TASK> ppoker/<them>-<TASK>`.

## 4. DOING THE WORK

- Follow `GOAL`, `DONE WHEN`, `INPUTS`, `OUTPUT`. Do not widen scope; if the card
  is wrong, say so in a comment before working around it.
- Verify with the project's own tools. Rules and relay:

```bash
cd software/Server/Python && python -m unittest tests.test_poker
```

- Client under emulation (Windows, openMSX with the MSXPi extension):

```bash
cd software/Client/tests && python poker_smoke_openmsx.py    # PPOKER.COM boots and draws
cd software/Client/tests && python poker_table_openmsx.py    # host + clients, a whole table
```

- Rebuild the client as `software/Client/src/PPOKER.md` describes; the built
  `PPOKER.COM` is a card artefact, so say in the card where you checked it.
- Commit in small steps with a real message. Comment when something changes: a
  push, a decision, an obstacle. A card with no comment or commit for 24 hours may
  be released by the coordinator.
- **Missing something?** Commit and push what you have, move the card to
  **Blocked**, comment exactly what is missing and who can unblock it, and claim
  another card.

## 5. FINISHING

1. Verify every `DONE WHEN` criterion yourself - run it, do not assume it.
2. Commit and push your branch:
   `git push -u origin ppoker/<you>-<TASK>`
3. Move the card to **Review** and comment:
   - branch `ppoker/<you>-<TASK>`
   - commit sha(s)
   - files changed
   - how each `DONE WHEN` criterion was verified (command and result)
4. Claim another card. You do not wait for the merge; the coordinator merges into
   `feature/ppoker-tournament`.

## 6. ENDING A SESSION WITH A CARD UNFINISHED

Never leave silently. Commit and push the branch, then either:

- comment `paused: <you>, branch ppoker/<you>-<TASK> @<sha>, next step: ...` and
  leave the card where it is, if you will be back soon; or
- comment `released: <you>, branch ppoker/<you>-<TASK> @<sha>, done so far: ...,
  next step: ...` and move the card back to **Ready** so any agent can finish it.

## 7. RULES

- Never merge, never close, never delete a branch, never push anything but your
  card's branch.
- Never rewrite another agent's card, and never rewrite your own description -
  comment instead.
- Never put credentials, tokens, passwords or keys in a commit, a card, a comment
  or an attachment.
- Cards titled `HUMAN ...`, `REVIEWER ...` or `EDITOR ...` are for people: never
  claim, move, edit or comment on them.
- If the code contradicts the card, the card loses - comment the evidence.

## 8. BOARD API

```bash
BASE=http://dl7420:8080
BOARD=grauI3EidcTKGnNiK
READY=dE7xriXgVdi12ZHWu
CLAIMED=lyZUuCwAffNgc3WLx
INPROG=glkUIpSIQhs8ebyGO
BLOCKED=a2frnwzBOYiq51MbT
REVIEW=5heVx4dO3ApmLw3hv
SWIM=ApPQvGq5ZlCTTnJC8

LOGIN=$(curl -s -X POST $BASE/users/login -H 'Content-Type: application/json' \
  -d '{"username":"<you>","password":"<your password>"}')
TOKEN=$(echo "$LOGIN" | python -c "import sys,json;print(json.load(sys.stdin)['token'])")
ME=$(echo "$LOGIN"    | python -c "import sys,json;print(json.load(sys.stdin)['id'])")

# claim
curl -s -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  $BASE/api/boards/$BOARD/lists/$READY/cards/$CARD \
  -d "{\"listId\":\"$CLAIMED\",\"swimlaneId\":\"$SWIM\"}"

# comment (not /api/cards/{id}/comments - that returns 405)
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  $BASE/api/boards/$BOARD/cards/$CARD/comments \
  -d '{"authorId":"'$ME'","comment":"claim: <you>"}'

# every other move is the same PUT: the card's CURRENT list in the path,
# the target list in listId.
```

In the UI instead: log in as your account, open the board, drag the card from Ready
to Claimed, then add the comment `claim: <you>`.
MD

# `coord/` must never be tracked. This is checked, never silently rewritten: the
# file is tracked, and a script that edits tracked files on every run is a trap.
if ! grep -qxF 'coord/' .gitignore 2>/dev/null; then
  echo "WARNING: 'coord/' is not in .gitignore - add it before committing anything" >&2
  rc=1
fi

if [ "$mode" = check ]; then
  echo
  echo "check complete (exit $rc)"
else
  echo
  echo "Board: http://dl7420:8080/b/grauI3EidcTKGnNiK/msx-ppoker"
  echo "These files are ignored by git; they are installed by this tracked script"
  echo "on every branch that has it, master included after the feature is merged."
fi
exit "$rc"
