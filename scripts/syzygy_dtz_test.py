#!/usr/bin/env python3
"""DTZ-root conversion test.

Measures whether the Syzygy DTZ root probe (S_Syzygy_Root) converts critical
winning endgames inside the 50-move zone, where the *path* to mate matters and
a plain search can drift into a draw. Each position is played out by the engine
against the same engine (the winning side is given a short movetime), with the
feature OFF and ON, and the outcomes are compared.

Outcome per game: mate (converted) / draw (50-move rule, repetition, or
insufficient material) / still-running at the move cap.

Usage:
  scripts/syzygy_dtz_test.py --syzygy DIR [--binary BIN] [--movetime MS]
                             [--halfmove N] [--moves CAP]
Writes a one-line JSON summary per run to stdout.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import chess
import chess.engine

ROOT = Path(__file__).resolve().parent.parent

# Winning endgames whose conversion depends on the shortest path (the ones the
# project's own notes flag as unreliable: KBNvK, KQvKR, KRPvKR), plus two easy
# controls (KQvK, KRvK) that must convert regardless.
POSITIONS = [
    ("KQvK",   "8/8/8/3k4/8/8/8/KQ6 w - - {hm} 1"),
    ("KRvK",   "8/8/8/3k4/8/8/8/KR6 w - - {hm} 1"),
    ("KBNvK",  "8/8/8/3k4/8/8/8/KBN5 w - - {hm} 1"),
    ("KBBvK",  "8/8/8/3k4/8/8/8/KBB5 w - - {hm} 1"),
    ("KQvKR",  "8/8/8/8/3rk3/8/8/KQ6 w - - {hm} 1"),
    ("KRPvKR", "8/8/8/8/3pk3/8/5K2/R7 w - - {hm} 1"),
]


def play(fen: str, binary: Path, syzygy: str, movetime: float, cap: int,
         params_file: str | None) -> str:
    """Play the position out, winning side = the engine, both sides the engine.

    Returns "mate", "draw", or "cap". The defending side also has the tables
    loaded, so the test isolates the ROOT probe (both can probe WDL in search).
    """
    board = chess.Board(fen)
    eng_w = chess.engine.SimpleEngine.popen_uci(
        [str(binary)] + (["--params", params_file] if params_file else [])
        + ["--syzygy", syzygy])
    eng_b = chess.engine.SimpleEngine.popen_uci([str(binary), "--syzygy", syzygy])
    try:
        for _ in range(cap):
            if board.is_game_over(claim_draw=True):
                break
            engine = eng_w if board.turn == chess.WHITE else eng_b
            res = engine.play(board, chess.engine.Limit(time=movetime))
            if res.move is None:
                break
            board.push(res.move)
        if board.is_checkmate():
            return "mate"
        if board.is_game_over(claim_draw=True) or board.is_fifty_moves() \
           or board.is_repetition(3) or board.is_insufficient_material():
            return "draw"
        return "cap"
    finally:
        eng_w.quit()
        eng_b.quit()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--syzygy", required=True)
    ap.add_argument("--binary", default=str(ROOT / "bin" / "babachess"))
    ap.add_argument("--movetime", type=float, default=0.1)
    ap.add_argument("--halfmove", type=int, default=80)
    ap.add_argument("--moves", type=int, default=120)
    args = ap.parse_args()

    binary = Path(args.binary)
    if not binary.exists():
        raise SystemExit(f"binary not found: {binary}")

    on_params = tempfile.NamedTemporaryFile("w", suffix=".params", delete=False)
    on_params.write("S_SYZYGY_ROOT 1\nS_SYZYGY_ROOT_MIN_HM 0\n")
    on_params.close()

    report = {"halfmove": args.halfmove, "movetime": args.movetime, "results": {}}
    try:
        for name, tmpl in POSITIONS:
            fen = tmpl.format(hm=args.halfmove)
            if not chess.Board(fen).is_valid():
                continue
            off = play(fen, binary, args.syzygy, args.movetime, args.moves, None)
            on = play(fen, binary, args.syzygy, args.movetime, args.moves, on_params.name)
            report["results"][name] = {"off": off, "on": on}
            print(f"{name:8s} off={off:5s} on={on:5s}", file=sys.stderr)
    finally:
        import os
        os.unlink(on_params.name)

    print(json.dumps(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
