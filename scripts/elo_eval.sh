#!/usr/bin/env bash
#
# Elo evaluation of BabaChess on a reference scale.
#
# Plays a bookless gauntlet over the repository opening suite (each opening
# with both colours, -repeat) against a pool of anchored opponents, then fits
# BabaChess's rating with scripts/elo_rate.py (opponents fixed at their
# nominal Elo). This complements scripts/sprt.sh (self-play, relative Elo) and
# scripts/elo_report.py (difference vs one opponent): here the result is an
# absolute-ish rating on the pool's scale.
#
# The pool is a small pipe-separated file:  name|proto|cmd|options|elo
# The default (scripts/elo_pool.conf) is Stockfish's UCI_Elo ladder, which is
# a self-consistent scale, NOT an official CCRL rating.
#
# Usage:
#   scripts/elo_eval.sh                         # defaults: 100 games/opponent, 10+0.1
#   scripts/elo_eval.sh --games 200 --tc 5+0.05 --concurrency 7
#   scripts/elo_eval.sh --pool my_pool.conf --out /tmp/opencode/my_elo
#
# Options: --pool FILE --games N --tc TC --concurrency C --seed S
#          --out DIR --binary PATH --engine-name NAME
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/babachess"
POOL="$ROOT/scripts/elo_pool.conf"
GAMES=100
TC="10+0.1"
CONC="$(( $(nproc) - 1 ))"
[ "$CONC" -lt 1 ] && CONC=1
SEED=7
OUT="/tmp/opencode/elo_eval"
ENGINE_NAME="Baba"

while [ $# -gt 0 ]; do
  case "$1" in
    --pool) POOL="$2"; shift 2 ;;
    --games) GAMES="$2"; shift 2 ;;
    --tc) TC="$2"; shift 2 ;;
    --concurrency) CONC="$2"; shift 2 ;;
    --seed) SEED="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --binary) BIN="$2"; shift 2 ;;
    --engine-name) ENGINE_NAME="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

command -v cutechess-cli >/dev/null || { echo "cutechess-cli not found" >&2; exit 2; }
[ -x "$BIN" ] || { echo "binary not executable: $BIN" >&2; exit 2; }
[ -f "$POOL" ] || { echo "pool file not found: $POOL" >&2; exit 2; }
BIN="$(realpath "$BIN")"
mkdir -p "$OUT"

# Fair, bookless match: hide the repository book (the engine probes it
# automatically) and disable OwnBook explicitly on both sides.
ROOT_BOOK="$ROOT/books/book.bin"
BOOK_HIDDEN=""
cleanup() { [ -n "$BOOK_HIDDEN" ] && mv -f "$BOOK_HIDDEN" "$ROOT_BOOK" || true; }
trap cleanup EXIT
if [ -f "$ROOT_BOOK" ]; then
  BOOK_HIDDEN="$ROOT_BOOK.hidden.$$"
  mv -f "$ROOT_BOOK" "$BOOK_HIDDEN"
fi

PGNS=()
ANCHORS=()
while IFS='|' read -r name proto cmd opts elo; do
  case "$name" in ''|'#'*) continue ;; esac
  pgn="$OUT/${name}.pgn"
  log="$OUT/${name}.log"
  echo "=== ${ENGINE_NAME} vs ${name} (anchor ${elo}, ${GAMES} games, tc=${TC}) ==="
  set -x
  cutechess-cli \
    -engine "name=${ENGINE_NAME}" "cmd=${BIN}" proto=uci \
            option.OwnBook=false option.Threads=1 \
    -engine "name=${name}" "cmd=${cmd}" "proto=${proto}" ${opts} \
    -each "tc=${TC}" \
    -openings "file=$ROOT/openings/openings.epd" format=epd order=random policy=default \
    -games 2 -rounds "$(( (GAMES + 1) / 2 ))" -repeat -recover \
    -concurrency "$CONC" -srand "$SEED" -pgnout "$pgn" 2>&1 \
    | tee "$log" | grep -E "Score of|Elo|Finished match" || true
  set +x
  PGNS+=( "$pgn" )
  ANCHORS+=( --anchor "${name}=${elo}" )
done < "$POOL"

echo
echo "=== anchored rating ==="
python3 "$ROOT/scripts/elo_rate.py" --pgn "${PGNS[@]}" \
        --engine "$ENGINE_NAME" "${ANCHORS[@]}"
echo "PGNs: $OUT"
