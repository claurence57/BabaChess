#!/usr/bin/env python3
"""Generate a diverse, roughly balanced opening suite for tuning.

Why this exists: `openings/openings.epd` is a curated 65-line suite, and the
engine is deterministic at fixed nodes, so self-play started from it collapses
to ~130 distinct games. Deduplicated position extraction then yields a few
thousand positions -- far too correlated to tune an evaluation on. This builds
positions from random play-outs instead (the recipe of DEVELOPMENT.md 72.1,
minus the depth-5 score filter, which would need one protocol round-trip per
position):

  * random 6-10 half-move games from the start position;
  * material balance within one pawn (python-chess values);
  * |Static| <= 60, read in one batch through `--eval-fens`.

Usage:
  python3 scripts/gen_balanced_openings.py out.epd [--count N] [--candidates M]
                                                  [--engine PATH] [--seed S]

Requires python-chess (the tuning venv has it).
"""
from __future__ import annotations

import argparse
import random
import subprocess
import sys
from pathlib import Path

import chess

ROOT = Path(__file__).resolve().parents[1]

# Classical values, centipawns: only used to require a balanced material.
VALUES = {chess.PAWN: 100, chess.KNIGHT: 320, chess.BISHOP: 330,
          chess.ROOK: 500, chess.QUEEN: 900}


def material(board: chess.Board) -> int:
    """Material balance in centipawns, from White's point of view."""
    total = 0
    for _square, piece in board.piece_map().items():
        if piece.piece_type == chess.KING:
            continue
        value = VALUES[piece.piece_type]
        total += value if piece.color == chess.WHITE else -value
    return total


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--count", type=int, default=2500,
                    help="openings kept (default 2500)")
    ap.add_argument("--candidates", type=int, default=9000,
                    help="random positions generated before filtering")
    ap.add_argument("--engine", default=str(ROOT / "bin" / "babachess"))
    ap.add_argument("--seed", type=int, default=11)
    args = ap.parse_args()

    engine = Path(args.engine)
    if not engine.exists():
        raise SystemExit(f"engine not found: {engine}")

    rng = random.Random(args.seed)
    candidates: list[str] = []
    seen: set[str] = set()
    while len(candidates) < args.candidates:
        board = chess.Board()
        ok = True
        for _ in range(rng.randint(6, 10)):
            moves = list(board.legal_moves)
            if not moves:
                ok = False
                break
            board.push(rng.choice(moves))
        if not ok or board.is_game_over() or board.is_check():
            continue
        if abs(material(board)) > 100:
            continue
        fen = " ".join(board.fen().split()[:4])
        if fen in seen:
            continue
        seen.add(fen)
        candidates.append(fen)

    # One --eval-fens call evaluates the whole batch (a few seconds).
    cand_path = Path(args.out + ".cand")
    cand_path.write_text("\n".join(candidates) + "\n")
    proc = subprocess.run([str(engine), "--eval-fens", str(cand_path)],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"--eval-fens failed ({proc.returncode})")
    evals = [int(x) for x in proc.stdout.split()]

    kept = [f for f, e in zip(candidates, evals) if abs(e) <= 60]
    rng.shuffle(kept)
    kept = kept[: args.count]
    Path(args.out).write_text("\n".join(kept) + "\n")
    print(f"{len(candidates)} candidates, {len(kept)} balanced openings -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
