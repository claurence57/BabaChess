#!/usr/bin/env bash
# Search campaign runner: each test = one params file (campaign/params/<id>.params)
# vs the same binary with its compiled defaults. fastchess, 4+0.04, SPRT [0,5]
# capped at 1000 games, each opening played in both colours.
# After each test the raw result is appended to CAMPAGNE_RECHERCHE.md and
# committed + pushed, so a container restart never loses a finished match.
#
# Usage: campaign/run.sh <seed> <id> [<id> ...]
# An id written new:old plays new.params against old.params instead of the
# compiled defaults (incremental tests).
set -u
cd "$(dirname "$0")/.."
SEED=$1; shift
BRANCH=$(git rev-parse --abbrev-ref HEAD)
BIN=campaign/bin/babachess
mkdir -p campaign/bin campaign/logs
cp bin/babachess "$BIN"          # frozen copy: a rebuild cannot disturb a match

for ID in "$@"; do
  NEW_ID=${ID%%:*}
  OLD_ID=; [[ $ID == *:* ]] && OLD_ID=${ID#*:}
  P=campaign/params/$NEW_ID.params
  OLD_ARGS=; OLD_DESC="défauts compilés"
  if [[ -n $OLD_ID ]]; then
    OLD_ARGS="args=--params campaign/params/$OLD_ID.params"
    OLD_DESC="\`$OLD_ID.params\` : \`$(tr '\n' ' ' < campaign/params/$OLD_ID.params)\`"
  fi
  LOG=campaign/logs/${NEW_ID}${OLD_ID:+_vs_$OLD_ID}_s${SEED}.log
  fastchess \
    -engine cmd="$BIN" args="--params $P" name=new \
    -engine cmd="$BIN" ${OLD_ARGS:+"$OLD_ARGS"} name=old \
    -each proto=uci tc=4+0.04 \
    -openings file=openings/ops.epd format=epd order=random \
    -repeat -rounds 500 -games 2 -concurrency 4 \
    -sprt elo0=0 elo1=5 alpha=0.05 beta=0.05 \
    -srand "$SEED" -recover > "$LOG" 2>&1
  {
    echo
    echo "### $ID — graine $SEED — $(git rev-parse --short HEAD) — $(date -u '+%F %T') UTC"
    echo
    echo "Paramètres (\`$P\`) : \`$(tr '\n' ' ' < "$P")\` — référence : $OLD_DESC"
    echo
    echo '```'
    grep -A6 '^Results of' "$LOG" | tail -7
    echo '```'
  } >> CAMPAGNE_RECHERCHE.md
  git add CAMPAGNE_RECHERCHE.md
  git commit -q -m "Search campaign: $ID (seed $SEED) result

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_016q2YbVQjbosUupL8kaqu1C"
  for d in 0 2 4 8 16; do sleep $d; git push -q -u origin "$BRANCH" && break; done
done
