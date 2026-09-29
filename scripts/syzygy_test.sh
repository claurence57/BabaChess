#!/usr/bin/env bash
#
# Syzygy tablebase conversion test.
#
# Plays a set of winning endgames (KQvK, KRvK, KRPvKR, ...) with the engine
# given the winning side and a Syzygy directory, and checks that it actually
# converts (checkmate) within the 50-move limit. The engine has WDL probing
# only, no DTZ at the root, so a failure here is a documented limitation, not
# necessarily a bug.
#
# Usage:
#   scripts/syzygy_test.sh --dir /path/to/3-4-5 [--movetime 200] [--moves 100]
#
# Prints one line per position: converted/mate, drawn, or still-going at the
# move cap. Exits non-zero only if the engine crashes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/bin/babachess"
DIR=""; MOVETIME=200; MAXMOVES=100

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --movetime) MOVETIME="$2"; shift 2 ;;
    --moves) MAXMOVES="$2"; shift 2 ;;
    --binary) BIN="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "--dir required (a Syzygy directory)" >&2; exit 2; }
[ -x "$BIN" ] || { echo "binary not found: $BIN" >&2; exit 2; }

python3 - "$BIN" "$DIR" "$MOVETIME" "$MAXMOVES" <<'PY'
import subprocess, sys, time
import chess, chess.engine

binary, tbdir, movetime_ms, maxmoves = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])

# Winning-side-to-move endgames; every FEN is verified legal before play.
POSITIONS = [
    ("KQvK",   "8/8/8/3k4/8/8/8/KQ6 w - - 0 1"),
    ("KQvK_b", "8/8/8/8/3k4/8/8/KQ6 w - - 0 1"),
    ("KRvK",   "8/8/8/3k4/8/8/8/KR6 w - - 0 1"),
    ("KBBvK",  "8/8/8/3k4/8/8/8/KBB5 w - - 0 1"),
    ("KBNvK",  "8/8/8/3k4/8/8/8/KBN5 w - - 0 1"),
    ("KQvKR",  "8/8/8/3r4/3k4/8/8/KQ6 w - - 0 1"),
    ("KRPvKR", "8/8/8/8/3pk3/8/5K2/R7 w - - 0 1"),
]

def play(name, fen):
    board = chess.Board(fen)
    if not board.is_valid():
        print(f"{name:8s} INVALID FEN (test bug): {fen}")
        return "invalid"
    eng = chess.engine.SimpleEngine.popen_uci(binary)
    eng.configure({"SyzygyPath": tbdir, "OwnBook": False, "Threads": 1})
    outcome = "cap"
    for _ in range(maxmoves):
        if board.is_checkmate():
            outcome = "checkmate"
            break
        if board.is_stalemate():
            outcome = "stalemate"
            break
        if board.is_insufficient_material():
            outcome = "insufficient"
            break
        if board.is_seventyfive_moves():
            outcome = "auto-draw(75)"
            break
        if board.is_fivefold_repetition():
            outcome = "auto-draw(5x)"
            break
        info = eng.play(board, chess.engine.Limit(time=movetime_ms / 1000.0))
        if info.move is None:
            outcome = "no-move"
            break
        board.push(info.move)
    eng.quit()
    print(f"{name:8s} {outcome:14s} plies={board.ply()} fen={board.fen()}")
    return outcome

crash = False
for name, fen in POSITIONS:
    try:
        play(name, fen)
    except Exception as exc:  # noqa: BLE001
        print(f"{name:8s} CRASH {exc}")
        crash = True
sys.exit(1 if crash else 0)
PY
