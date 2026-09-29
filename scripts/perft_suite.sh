#!/usr/bin/env bash
#
# Perft suite: compare the engine's perft against the standard reference
# values (Chess Programming Wiki), for the initial position, Kiwipete and
# CPW positions 3-6. Any difference is a movegen / make-unmake bug and makes
# the script exit non-zero.
#
# Usage:
#   scripts/perft_suite.sh [--binary PATH] [--max-depth N] [--deep]
#
#   --max-depth N   cap the depth (default 5; use 6 for the full check)
#   --deep          shorthand for --max-depth 6
#
# The deeper runs are only launched when the depth is within the reference set
# of that position. Reference counts are exact and MUST NOT change.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/babachess"
MAX_DEPTH=5

while [ $# -gt 0 ]; do
  case "$1" in
    --binary) BIN="$2"; shift 2 ;;
    --max-depth) MAX_DEPTH="$2"; shift 2 ;;
    --deep) MAX_DEPTH=6; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -x "$BIN" ] || { echo "binary not found: $BIN (build first)" >&2; exit 2; }

pass=0
fail=0
check() {
  local name="$1" fen="$2" depth="$3" expect="$4"
  if [ "$depth" -gt "$MAX_DEPTH" ]; then
    return
  fi
  local got
  got="$("$BIN" --perft "$fen" "$depth" | sed 's/.*= //' | tr -d ' ')"
  if [ "$got" = "$expect" ]; then
    printf 'OK   %-12s d%d = %s\n' "$name" "$depth" "$got"
    pass=$((pass + 1))
  else
    printf 'FAIL %-12s d%d = %s (expected %s)\n' "$name" "$depth" "$got" "$expect"
    fail=$((fail + 1))
  fi
}

# Position 1 - initial
P1="rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
check startposition "$P1" 1 20
check startposition "$P1" 2 400
check startposition "$P1" 3 8902
check startposition "$P1" 4 197281
check startposition "$P1" 5 4865609
check startposition "$P1" 6 119060324

# Position 2 - Kiwipete
P2="r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
check kiwipete "$P2" 1 48
check kiwipete "$P2" 2 2039
check kiwipete "$P2" 3 97862
check kiwipete "$P2" 4 4085603
check kiwipete "$P2" 5 193690690

# Position 3 - en passant / promotions
P3="8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
check pos3 "$P3" 1 14
check pos3 "$P3" 2 191
check pos3 "$P3" 3 2812
check pos3 "$P3" 4 43238
check pos3 "$P3" 5 674624
check pos3 "$P3" 6 11030083

# Position 4 - castling / promotions (Black castles)
P4="r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
check pos4 "$P4" 1 6
check pos4 "$P4" 2 264
check pos4 "$P4" 3 9467
check pos4 "$P4" 4 422333
check pos4 "$P4" 5 15833292

# Position 5 - promotions / discovered check
P5="rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"
check pos5 "$P5" 1 44
check pos5 "$P5" 2 1486
check pos5 "$P5" 3 62379
check pos5 "$P5" 4 2103487
check pos5 "$P5" 5 89941194

# Position 6 - quiet middlegame
P6="r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10"
check pos6 "$P6" 1 46
check pos6 "$P6" 2 2079
check pos6 "$P6" 3 89890
check pos6 "$P6" 4 3894594
check pos6 "$P6" 5 164075551

echo
echo "perft suite: $pass passed, $fail failed (max depth $MAX_DEPTH)"
[ "$fail" -eq 0 ] || exit 1
