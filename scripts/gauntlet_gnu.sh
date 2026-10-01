#!/usr/bin/env bash
#
# Gauntlet judge: BabaChess vs GNU Chess 6.2.7 (Fruit 2.1), the primary
# instrument for the "knowledge" lots (steps 1 and 2).
#
# Why a dedicated gauntlet: the self-play SPRT (scripts/sprt.sh) is blind to
# the failure modes the external audit found -- a slow positional drift and
# missed quiet checks -- because both sides share them. GNU Chess does not,
# so it is the reference judge for evaluation/search knowledge.
#
# Book OFF on both sides, both colours per opening (-repeat), GNU started
# through its UCI wrapper. `-recover` is MANDATORY: GNU Chess 6.2.7 aborts on
# its own assertion ("nread < BUF_SIZE-1" in engine.cc) every so often; without
# -recover a single abort would end the whole match.
#
# Games that end by a GNU-side disconnect/crash are counted SEPARATELY and
# EXCLUDED from the score (they are GNU's fault, not the engine's), but their
# number is reported so a suspicious rate is visible.
#
# Reports the RELATIVE Elo difference versus a fixed reference binary (the
# point-zero build) on the same seeds/openings, via scripts/elo_report.py.
# It never quotes an absolute Elo.
#
# Usage:
#   scripts/gauntlet_gnu.sh [binary] [games] [tc] [seed] [outdir]
#
# Defaults: binary=bin/babachess, games=400, tc=10+0.1, seed=7,
#           outdir=/tmp/opencode/gauntlet_gnu
#
# Env overrides: GNU_WRAP (default ~/bin/gnuchess_uci.sh),
#                OPENINGS (default openings/openings.epd),
#                CONCURRENCY (default nproc-1), REFERENCE (an optional
#                point-zero binary used to print the delta explicitly).
set -euo pipefail

BIN="${1:-$(cd "$(dirname "$0")/.." && pwd)/bin/babachess}"
GAMES="${2:-400}"
TC="${3:-10+0.1}"
SEED="${4:-7}"
OUTDIR="${5:-/tmp/opencode/gauntlet_gnu}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GNU_WRAP="${GNU_WRAP:-${HOME}/bin/gnuchess_uci.sh}"
OPENINGS="${OPENINGS:-${ROOT}/openings/openings.epd}"
CONCURRENCY="${CONCURRENCY:-$(( $(nproc) - 1 ))}"
REFERENCE="${REFERENCE:-}"

# Even number of games: -games 2 -repeat plays each opening with both colours.
GAMES=$(( (GAMES + 1) / 2 * 2 ))
[ "$CONCURRENCY" -lt 1 ] && CONCURRENCY=1

[ -x "$BIN" ] || { echo "binary not executable: $BIN" >&2; exit 2; }
[ -x "$GNU_WRAP" ] || { echo "GNU wrapper missing: $GNU_WRAP" >&2; exit 2; }
[ -f "$OPENINGS" ] || { echo "openings missing: $OPENINGS" >&2; exit 2; }
BIN="$(realpath "$BIN")"

# A fair, bookless match: hide the repository book for the whole run (the
# engine probes books/book.bin automatically; OwnBook=false is also set).
ROOT_BOOK="$ROOT/books/book.bin"
BOOK_HIDDEN=""
cleanup() { [ -n "$BOOK_HIDDEN" ] && mv -f "$BOOK_HIDDEN" "$ROOT_BOOK" || true; }
trap cleanup EXIT
if [ -f "$ROOT_BOOK" ]; then
  BOOK_HIDDEN="$ROOT_BOOK.hidden.$$"
  mv -f "$ROOT_BOOK" "$BOOK_HIDDEN"
fi

mkdir -p "$OUTDIR"
STAMP="$(date +%s)"
PGN="$OUTDIR/gnu_${STAMP}.pgn"
LOG="$OUTDIR/gnu_${STAMP}.log"

echo "engine      = $BIN"
echo "GNU         = $GNU_WRAP"
echo "games       = $GAMES (tc=$TC, seed=$SEED, concurrency=$CONCURRENCY)"
echo "openings    = $OPENINGS"
echo "pgn         = $PGN"

set -x
cutechess-cli \
  -engine name=Baba cmd="$BIN" proto=uci option.OwnBook=false option.Threads=1 \
  -engine name=GNU cmd="$GNU_WRAP" proto=uci option.OwnBook=false \
  -each tc="$TC" timemargin=200 \
  -openings file="$OPENINGS" format=epd order=random policy=default \
  -games 2 -rounds "$(( GAMES / 2 ))" -repeat -recover \
  -concurrency "$CONCURRENCY" -ratinginterval 20 -srand "$SEED" \
  -pgnout "$PGN"
set +x

# --- Score, excluding GNU-side aborts -------------------------------------
python3 - "$PGN" "$LOG" "$REFERENCE" <<'PY'
import re, sys, math
from pathlib import Path

pgn, log, reference = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]

# Parse the PGN: per-game result + Termination, from Baba's perspective.
import chess.pgn
results = []          # 1 / 0.5 / 0 for Baba
crash = 0             # games voided by a GNU-side abort/disconnect
total = 0
with open(pgn, encoding="utf-8", errors="replace") as fh:
    while True:
        g = chess.pgn.read_game(fh)
        if g is None:
            break
        res = g.headers.get("Result", "*")
        term = g.headers.get("Termination", "")
        if res not in ("1-0", "0-1", "1/2-1/2"):
            continue
        total += 1
        white = g.headers.get("White", "")
        baba_white = white == "Baba"
        # A GNU crash/disconnect leaves no normal mate/resignation/adjudication.
        if re.search(r"disconnect|stall|crash|abort|illegal", term, re.I) and \
           not re.search(r"mates|resign|50 moves|repetition|insufficient|stalemate|adjudicat|time", term, re.I):
            crash += 1
            continue
        if res == "1/2-1/2":
            results.append(0.5)
        else:
            results.append(1.0 if (res == "1-0") == baba_white else 0.0)

n = len(results)
score = sum(results) / n if n else 0.0
def elo(s):
    if s <= 0 or s >= 1:
        return None
    return -400.0 * math.log10(1.0 / s - 1.0)
def se_elo(s, sd, n):
    if s <= 0 or s >= 1 or n < 2:
        return None
    return (400.0 / (math.log(10.0) * s * (1 - s))) * (sd / math.sqrt(n))

mean = score
sd = math.sqrt(sum((x - mean) ** 2 for x in results) / (n - 1)) if n > 1 else 0.0
e = elo(score)
se = se_elo(score, sd, n)
w = sum(1 for x in results if x == 1.0)
d = sum(1 for x in results if x == 0.5)
l = sum(1 for x in results if x == 0.0)

print()
print(f"games        : {total}  usable {n}  (crash/void {crash})")
print(f"Baba score   : {w}-{d}-{l}  = {100*score:.1f}%")
if e is None:
    print("Elo diff     : undefined (0% or 100%)")
else:
    lo, hi = e - 1.96 * se, e + 1.96 * se
    print(f"Elo diff     : {e:+.1f}  (95% CI {lo:+.1f} .. {hi:+.1f}, SE {se:.1f})")
    # Write a machine-readable line for later stacking/regression tables.
    (pgn.with_suffix(".summary")).write_text(
        f"n={n} w={w} d={d} l={l} score={score:.4f} elo={e:.2f} "
        f"se={se:.2f} lo={lo:.2f} hi={hi:.2f} crash={crash}\n")
if reference:
    print(f"reference    : {reference} (compare per-opening on the same seed)")
PY

echo "summary      : ${PGN%.pgn}.summary"
