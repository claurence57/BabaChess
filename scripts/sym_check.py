#!/usr/bin/env python3
"""Check the evaluation's mirror symmetry on a large set of positions.

The golden invariant of BabaChess's evaluation is that the tempo-free core
`Static` is antisymmetric under mirroring (rank flip + colour swap + side
flip):

    Static(mirror(p)) == -Static(p)

`Evaluate` is NOT antisymmetric (it adds a tempo bonus), so this tool reads
`Static` through `--eval-fens`, which prints exactly that integer.

Usage:
  scripts/sym_check.py [FEN_FILE] [--binary PATH] [--count N] [--seed S]

FEN_FILE defaults to openings/openings.epd, extended with positions played
out from random openings (so quiet middle-game and endgame positions are
covered, not just the first moves). At least --count positions are checked
(default 3000). ZERO discrepancy is tolerated: the script exits non-zero if
any position violates the invariant, and prints the offending FENs.

Requires `python-chess` (already used by the book generator / datasets).
"""
from __future__ import annotations

import argparse
import random
import subprocess
import sys
from pathlib import Path

import chess

ROOT = Path(__file__).resolve().parent.parent


def read_fens(path: Path) -> list[str]:
    out = []
    for line in path.read_text(errors="replace").splitlines():
        line = line.split(";")[0].strip()
        if line:
            out.append(line)
    return out


def extend(fens: list[str], count: int, seed: int) -> list[str]:
    """Add random playout positions so mid/endgame material is represented."""
    rng = random.Random(seed)
    out = list(fens)
    attempts = 0
    while len(out) < count and attempts < count * 20:
        attempts += 1
        base = rng.choice(fens)
        try:
            board = chess.Board(base)
        except ValueError:
            continue
        if not board.is_valid():
            continue
        # Random legal play for a while, then keep the position (quiet only:
        # skip checks, which --eval-fens still evaluates but which are less
        # representative of the invariant's normal use).
        for _ in range(rng.randint(2, 40)):
            if board.is_game_over():
                break
            board.push(rng.choice(list(board.legal_moves)))
        if board.is_game_over():
            continue
        out.append(board.fen())
    return out


def read_evals(binary: Path, fens: list[str]) -> list[int]:
    fen_file = ROOT / "obj" / "sym_check_input.fen"
    fen_file.parent.mkdir(parents=True, exist_ok=True)
    fen_file.write_text("\n".join(fens) + "\n")
    proc = subprocess.run(
        [str(binary), "--eval-fens", str(fen_file)],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(f"--eval-fens failed ({proc.returncode})")
    vals = [int(x) for x in proc.stdout.split() if x.lstrip("-").isdigit()]
    if len(vals) != len(fens):
        raise SystemExit(f"expected {len(fens)} evals, got {len(vals)}")
    return vals


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("fen_file", nargs="?", default=str(ROOT / "openings" / "openings.epd"))
    ap.add_argument("--binary", default=str(ROOT / "bin" / "babachess"))
    ap.add_argument("--count", type=int, default=3000)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    binary = Path(args.binary)
    if not binary.exists():
        raise SystemExit(f"binary not found: {binary}")

    fens = read_fens(Path(args.fen_file))
    if not fens:
        raise SystemExit("no FENs to check")
    total = max(args.count, len(fens))
    fens = extend(fens, total, args.seed)
    mirrors = []
    for fen in fens:
        board = chess.Board(fen)
        mirrors.append(board.mirror().fen())

    evals = read_evals(binary, fens)
    mevals = read_evals(binary, mirrors)

    bad = 0
    for fen, mir, e, me in zip(fens, mirrors, evals, mevals):
        if e != -me:
            bad += 1
            if bad <= 20:
                print(f"ASYMMETRY: {e} vs {-me}\n  {fen}\n  {mir}")
    print(f"sym_check: {len(fens)} positions, {bad} discrepancies")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
