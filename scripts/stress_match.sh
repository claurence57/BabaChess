#!/usr/bin/env bash
#
# Stress / legality match runner for BabaChess.
#
# Plays a cutechess-cli match between two BabaChess processes (or BabaChess
# vs an external engine), then reports the outcome categories that matter for
# robustness: illegal moves, losses on time, disconnections/crashes, and
# whether cutechess-cli itself exited cleanly.
#
# Usage:
#   scripts/stress_match.sh --games N --tc TC --threads K [--proto uci|xboard]
#                           [--book on|off] [--pgn FILE] [--concurrency C]
#                           [--opponent CMD] [--opp-proto P]
#
# Examples:
#   scripts/stress_match.sh --games 500 --tc 10+0.1 --threads 1 --proto uci
#   scripts/stress_match.sh --games 500 --tc 60+0.6 --threads 4 --proto xboard
#
# The exact cutechess-cli command line is printed (and kept in the log) so a
# run can be reproduced verbatim.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAMES=100; TC="10+0.1"; THREADS=1; PROTO="uci"; BOOK="off"
PGN="/tmp/opencode/stress.pgn"; CONC=4; OPPONENT=""; OPP_PROTO="uci"
BIN="$ROOT/bin/babachess"

while [ $# -gt 0 ]; do
  case "$1" in
    --games) GAMES="$2"; shift 2 ;;
    --tc) TC="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --proto) PROTO="$2"; shift 2 ;;
    --book) BOOK="$2"; shift 2 ;;
    --pgn) PGN="$2"; shift 2 ;;
    --concurrency) CONC="$2"; shift 2 ;;
    --opponent) OPPONENT="$2"; shift 2 ;;
    --opp-proto) OPP_PROTO="$2"; shift 2 ;;
    --binary) BIN="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v cutechess-cli >/dev/null || { echo "cutechess-cli not found" >&2; exit 2; }
[ -x "$BIN" ] || { echo "binary not found: $BIN" >&2; exit 2; }
mkdir -p "$(dirname "$PGN")"

OWNBOOK=true; [ "$BOOK" = off ] && OWNBOOK=false

ENGINE_OPTS="option.Threads=$THREADS option.OwnBook=$OWNBOOK"
if [ -n "$OPPONENT" ]; then
  OPP_ENGINE=( -engine "name=Opponent" "cmd=$OPPONENT" "proto=$OPP_PROTO" )
else
  OPP_ENGINE=( -engine "name=BB2" "cmd=$BIN" "proto=$PROTO" "$ENGINE_OPTS" )
fi

LOG="${PGN%.pgn}.log"
set -x
cutechess-cli \
  -engine "name=BB1" "cmd=$BIN" "proto=$PROTO" $ENGINE_OPTS \
  "${OPP_ENGINE[@]}" \
  -each "tc=$TC" \
  -openings "file=$ROOT/openings/openings.epd" format=epd order=random \
  -games "$GAMES" -rounds 1 -concurrency "$CONC" \
  -pgnout "$PGN" -repeat 2>&1 | tee "$LOG"
set +x

echo "----- summary -----"
echo "games requested : $GAMES"
echo "illegal moves   : $(grep -c 'illegal move' "$LOG" || true)"
echo "losses on time  : $(grep -c 'loses on time' "$LOG" || true)"
echo "disconnects     : $(grep -ciE 'disconnect|terminated|crash|segmentation' "$LOG" || true)"
echo "cutechess errors: $(grep -c 'Error' "$LOG" || true)"
echo "pgn             : $PGN"
echo "log             : $LOG"
