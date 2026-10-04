#!/usr/bin/env python3
"""Expand openings/openings.epd into a larger, balanced suite for long SPRTs.

Each of the 65 base positions is extended by two random legal half-moves; the
resulting positions are deduplicated, scored by the engine at a fixed depth and
kept only when |score| <= --max-cp. A larger suite means fewer repeated game
pairs over a 1000-game match. Deterministic for a given --seed and binary.

Usage: python3 scripts/expand_openings.py [--engine bin/babachess]
           [--per-base 24] [--depth 7] [--max-cp 70] [--seed 1]
           [--out openings/ops.epd]
"""
from __future__ import annotations

import argparse
import random
from pathlib import Path

import chess
import chess.engine


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", default="bin/babachess")
    ap.add_argument("--base", default="openings/openings.epd")
    ap.add_argument("--per-base", type=int, default=24)
    ap.add_argument("--depth", type=int, default=7)
    ap.add_argument("--max-cp", type=int, default=70)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default="openings/ops.epd")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    bases = [l.strip() for l in Path(args.base).read_text().splitlines()
             if l.strip()]
    candidates: list[str] = []
    seen: set[str] = set()
    for epd in bases:
        board, _ = chess.Board.from_epd(epd)
        for _ in range(args.per_base):
            b = board.copy()
            for _ in range(2):
                moves = list(b.legal_moves)
                if not moves:
                    break
                b.push(rng.choice(moves))
            key = b.epd()
            if b.is_game_over() or key in seen:
                continue
            seen.add(key)
            candidates.append(key)

    kept: list[str] = []
    with chess.engine.SimpleEngine.popen_uci(args.engine) as eng:
        for epd in candidates:
            board, _ = chess.Board.from_epd(epd)
            info = eng.analyse(board, chess.engine.Limit(depth=args.depth))
            cp = info["score"].white().score(mate_score=100_000)
            if cp is not None and abs(cp) <= args.max_cp:
                kept.append(epd)

    Path(args.out).write_text("\n".join(kept) + "\n")
    print(f"{len(bases)} bases, {len(candidates)} candidates, "
          f"{len(kept)} kept -> {args.out}")


if __name__ == "__main__":
    main()
