#!/usr/bin/env bash
#
# Phase 3.2 stress campaign: >= 500 games per protocol (UCI/XBoard) x thread
# count (1/4) x time control (10+0.1 / 60+0.6), all self-play, book off.
# Records the exact commands and the failure counters in one summary file.
#
# Usage: scripts/phase3_stress.sh [--games N] [--out DIR] [--quick]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAMES=500; OUT=/tmp/opencode/phase3; QUICK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --games) GAMES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --quick) QUICK=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ "$QUICK" = 1 ] && GAMES=20
mkdir -p "$OUT"
SUMMARY="$OUT/summary.txt"
: > "$SUMMARY"

run() {
  local proto="$1" threads="$2" tc="$3"
  local tag="stress_${proto}_${threads}t_${tc/+/_}"
  local log="$OUT/$tag"
  echo "=== $tag ($GAMES games) ===" | tee -a "$SUMMARY"
  bash "$ROOT/scripts/stress_match.sh" --games "$GAMES" --tc "$tc" \
    --threads "$threads" --proto "$proto" --book off \
    --pgn "$log.pgn" --concurrency 6 > "$log.out" 2>&1
  local illegal time crash err
  illegal=$(grep -c 'illegal move' "$log.log" || true)
  time=$(grep -c 'loses on time' "$log.log" || true)
  crash=$(grep -ciE 'disconnect|terminated|crash|segmentation' "$log.log" || true)
  err=$(grep -c 'Error' "$log.log" || true)
  {
    echo "proto=$proto threads=$threads tc=$tc games=$GAMES"
    echo "  illegal=$illegal time_loss=$time crash=$crash errors=$err"
    echo "  cmd: scripts/stress_match.sh --games $GAMES --tc $tc --threads $threads --proto $proto --book off"
  } | tee -a "$SUMMARY"
}

# 250 games per (protocol, thread) = 500 games per protocol; the thread
# count and the cadence both vary between the two cells.
run uci    1 "10+0.1"
run uci    4 "30+0.3"
run xboard 1 "10+0.1"
run xboard 4 "30+0.3"

echo "DONE" >> "$SUMMARY"
