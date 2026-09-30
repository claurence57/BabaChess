#!/usr/bin/env bash
#
# Strength gauge (gauntlet) for BabaChess.
#
# Plays BabaChess against one or more opponents (Stockfish with
# UCI_LimitStrength/UCI_Elo and/or classic engines) over the repository
# opening suite, book OFF on both sides, and reports the score and the Elo
# DIFFERENCE with a 95% interval.
#
# IMPORTANT: this reports a RELATIVE Elo only. The opponents' absolute ratings
# are NOT verified against the CCRL list by this script; do not quote an
# absolute Elo from here. See the final report for the wording.
#
# Usage:
#   scripts/gauntlet.sh --games 250 --tc 10+0.1 --opponent stockfish:1900
#   scripts/gauntlet.sh --games 100 --tc 10+0.1 --opponent "/usr/games/crafty:xb"
#
# Opponent spec: NAME:ELO (Stockfish limited) or PATH:uci|xb (raw engine).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/babachess"
GAMES=250; TC="10+0.1"; CONC=6; OUT=/tmp/opencode/gauntlet
OPPONENTS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --games) GAMES="$2"; shift 2 ;;
    --tc) TC="$2"; shift 2 ;;
    --concurrency) CONC="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --opponent) OPPONENTS+=( "$2" ); shift 2 ;;
    --binary) BIN="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ ${#OPPONENTS[@]} -gt 0 ] || { echo "give at least one --opponent" >&2; exit 2; }
[ -x "$BIN" ] || { echo "binary not found: $BIN" >&2; exit 2; }
mkdir -p "$OUT"

for spec in "${OPPONENTS[@]}"; do
  name="${spec%%:*}"; arg="${spec#*:}"
  case "$arg" in
    uci|xb) cmd="$name"; proto="$arg" ;;
    *)      cmd="stockfish"; proto="uci" ;;
  esac
  tag="$(basename "$name")_${arg}"
  pgn="$OUT/${tag}.pgn"; log="$OUT/${tag}.log"

  opp_args=( "name=$tag" )
  if [ "$cmd" = "stockfish" ]; then
    opp_args+=( "cmd=/usr/local/bin/stockfish" "proto=uci"
                "option.UCI_LimitStrength=true" "option.UCI_Elo=$arg"
                "option.Threads=1" )
  else
    opp_args+=( "cmd=$cmd" "proto=$proto" )
  fi

  echo "=== gauntlet vs $tag ($GAMES games, tc=$TC) ==="
  { set -x
    cutechess-cli \
      -engine "name=BB1" "cmd=$BIN" proto=uci option.OwnBook=false option.Threads=1 \
      -engine "${opp_args[@]}" \
      -each "tc=$TC" \
      -openings "file=$ROOT/openings/openings.epd" format=epd order=random \
      -games "$GAMES" -rounds 1 -concurrency "$CONC" -pgnout "$pgn" -repeat
    set +x
  } > "$log" 2>&1
  grep 'Score of' "$log" | tail -1
  python3 "$ROOT/scripts/elo_report.py" --pgn "$pgn" --engine BB1
  echo
done
