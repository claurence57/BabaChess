#!/usr/bin/env bash
# Final check: the binary with the new compiled defaults (no --params) vs the
# main binary (79ac266), same protocol as run.sh. Result appended, committed
# and pushed. Usage: campaign/final.sh <seed>
set -u
cd "$(dirname "$0")/.."
SEED=$1
LOG=campaign/logs/final_vs_main_s${SEED}.log
fastchess \
  -engine cmd=campaign/bin/final name=new \
  -engine cmd=campaign/bin/main_79ac266 name=old \
  -each proto=uci tc=4+0.04 \
  -openings file=openings/ops.epd format=epd order=random \
  -repeat -rounds 500 -games 2 -concurrency 4 \
  -sprt elo0=0 elo1=5 alpha=0.05 beta=0.05 \
  -srand "$SEED" -recover > "$LOG" 2>&1
{
  echo
  echo "### final (défauts compilés de $(git rev-parse --short HEAD)) contre main 79ac266 — graine $SEED — $(date -u '+%F %T') UTC"
  echo
  echo '```'
  grep -A6 '^Results of' "$LOG" | tail -7
  echo '```'
} >> CAMPAGNE_RECHERCHE.md
git add CAMPAGNE_RECHERCHE.md
git commit -q -m "Search campaign: final binary vs main (seed $SEED)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_016q2YbVQjbosUupL8kaqu1C"
for d in 0 2 4 8 16; do sleep $d; git push -q origin "$(git rev-parse --abbrev-ref HEAD)" && break; done
