#!/bin/sh
# One runner for every PLAYNET game on every link (plan B6). The per-game facts are in the profile's rig.json
# (software/ROM-Patcher/profiles/<id>/rig.json): which rig script drives it, its ROM, the environment of each link, how its
# script takes <lag> <loss> <frames> <jitter>. No per-game code here and no per-link code in a profile.
#
#   PROFILE=<id> LINK=0|1|2|mixed|mixed2 [CHAT=1] [LAG=ms] [LOSS=pct] [FRAMES=n] [JITTER=ms] [EXITKEY=n] sh run_game.sh
#
#   LINK 0       both nodes over the MSXPi
#   LINK 1       both nodes over the TCP/IP UNAPI (UDP game packets)
#   LINK 2       both nodes: chat/stack on TCP/IP, the game's packets through the MSXPi (hybrid transport)
#   LINK mixed   P1 over the MSXPi, P2 over TCP/IP (link 1)   mixed2: the same with P2 on link 2
#   CHAT=1       start from MCHAT (/play, /accept) and, with EXITKEY, check both come back to it: LINK 0 over the MSXPi chat,
#                1 and 2 over MCHAT /T (LINK 1 plays over TCP/IP, LINK 2 through the MSXPi)
# Anything else in the environment (MODE, WORK, EXTRA_TCL, PNOPTS, PERF=1 for the cmp_perf table ...) goes through to the rig script.
# GAMEROMS = the folder with your own dumps (default C:/Users/roniv/Dev/MSX/gameroms; never committed).
# Prints the rig script's result: "compared n common frames: IDENTICAL" or the first differing frame.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
[ -n "$PROFILE" ] || { echo "set PROFILE=<id> (a folder of software/ROM-Patcher/profiles with a rig.json)"; exit 1; }
RIG="$ROOT/software/ROM-Patcher/profiles/$PROFILE/rig.json"
[ -f "$RIG" ] || { echo "no $RIG"; exit 1; }
LINK=${LINK:-0}
GAMEROMS=${GAMEROMS:-C:/Users/roniv/Dev/MSX/gameroms}
# the rig script, its arguments and the environment, from rig.json (python writes shell assignments)
PLAN=$(PROFILE_RIG="$RIG" LINK="$LINK" CHAT="$CHAT" GAMEROMS="$GAMEROMS" LAG="${LAG:-0}" LOSS="${LOSS:-0}" FRAMES="$FRAMES" JITTER="${JITTER:-0}" python - <<'PY'
import json, os, shlex, sys
rig = json.load(open(os.environ['PROFILE_RIG']))
link, chat = os.environ['LINK'], bool(os.environ['CHAT'])
table = rig['chat'] if chat else rig['links']
if link not in table:
    sys.exit('echo "%s has no %s run on LINK=%s"; exit 2' % (rig.get('script'), 'chat' if chat else 'game', link))
env = dict(rig.get('env', {}))
env.update(table[link])
env.setdefault(rig['rom_env'], os.environ['GAMEROMS'] + '/' + rig['rom'])
values = {'lag': os.environ['LAG'], 'loss': os.environ['LOSS'], 'frames': os.environ['FRAMES'] or str(rig['frames']),
          'jitter': os.environ['JITTER']}
print('SCRIPT=%s' % shlex.quote(rig['script']))
print('ARGS=%s' % shlex.quote(' '.join(values[a] for a in rig['argv'])))
for k, v in env.items():
    # an explicit environment setting wins over rig.json's default (MODE=1 sh run_game.sh ...)
    print('export %s=%s' % (k, shlex.quote(os.environ.get(k) or v)))
PY
)
[ $? = 0 ] || { echo "$PLAN"; exit 2; }
eval "$PLAN" || exit 2
[ -z "$PLAN_ONLY" ] || { echo "sh $SCRIPT $ARGS"; echo "$PLAN"; exit 0; }
export WORK=${WORK:-${TMP:-/tmp}/rungame-$PROFILE-$LINK${CHAT:+-chat}}
cd "$HERE" && exec sh "$SCRIPT" $ARGS
