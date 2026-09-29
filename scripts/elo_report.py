#!/usr/bin/env python3
"""Compute Elo differences (and 95% intervals) from cutechess-cli PGNs/logs.

This is a small, self-contained alternative to `ordo`/`bayeselo` (neither is
available here). It uses the standard logistic relation between the expected
score S and the rating difference:

    S = 1 / (1 + 10^(-D/400))   <=>   D = -400 * log10(1/S - 1)

and a delta-method 95% interval: with the per-game results x_i in {1, 0.5, 0}
(win/draw/loss), the sample standard error of the mean score is
SE_S = sd(x)/sqrt(N), and SE_D = |dD/dS| * SE_S.

This is honest but approximate; it does NOT fit a joint model like ordo. The
report says so. Draws are counted as 0.5 and included in the variance.

Usage:
  scripts/elo_report.py --pgn match.pgn [--engine BB] [--opponent NAME]
  scripts/elo_report.py --log match.log
"""
from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

Z95 = 1.959963984540054


def log10(x: float) -> float:
    return math.log10(x)


def elo_from_score(s: float) -> float | None:
    if s <= 0.0 or s >= 1.0:
        return None
    return -400.0 * log10(1.0 / s - 1.0)


def dscore_delo(s: float) -> float:
    # dS/dD = ln(10)/400 * S * (1-S); invert for dD/dS.
    return 400.0 / (math.log(10.0) * s * (1.0 - s))


def stats(results: list[float]) -> dict:
    n = len(results)
    if n == 0:
        return {"n": 0}
    mean = sum(results) / n
    var = sum((x - mean) ** 2 for x in results) / (n - 1) if n > 1 else 0.0
    se_s = math.sqrt(var / n)
    elo = elo_from_score(mean)
    if elo is None:
        se_elo = float("inf") if mean in (0.0, 1.0) else 0.0
    else:
        se_elo = dscore_delo(mean) * se_s
    w = sum(1 for x in results if x == 1.0)
    d = sum(1 for x in results if x == 0.5)
    l = sum(1 for x in results if x == 0.0)
    return {
        "n": n, "w": w, "d": d, "l": l, "score": mean,
        "elo": elo, "se_elo": se_elo,
        "lo": (elo - Z95 * se_elo) if elo is not None else None,
        "hi": (elo + Z95 * se_elo) if elo is not None else None,
    }


def parse_pgn(path: Path, engine: str, opponent: str | None):
    """Return (vs_engine_results, {opponent: results}) from a PGN file."""
    import chess.pgn

    all_res = []
    per_opp: dict[str, list[float]] = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        while True:
            game = chess.pgn.read_game(fh)
            if game is None:
                break
            res = game.headers.get("Result", "*")
            if res not in ("1-0", "0-1", "1/2-1/2"):
                continue
            white = game.headers.get("White", "")
            black = game.headers.get("Black", "")
            if engine not in (white, black):
                continue
            engine_white = white == engine
            if res == "1/2-1/2":
                x = 0.5
            else:
                x = 1.0 if (res == "1-0") == engine_white else 0.0
            opp = black if engine_white else white
            all_res.append(x)
            per_opp.setdefault(opp, []).append(x)
    if opponent:
        per_opp = {k: v for k, v in per_opp.items() if k == opponent}
    return all_res, per_opp


def parse_log(path: Path):
    """Fallback: read 'Score of A vs B: w - l - d [..]' lines, last one wins."""
    pat = re.compile(r"Score of (.+?) vs (.+?): (\d+) - (\d+) - (\d+)")
    rows = []
    for line in path.read_text(errors="replace").splitlines():
        m = pat.search(line)
        if m:
            rows.append((m.group(1), m.group(2), int(m.group(3)),
                         int(m.group(4)), int(m.group(5))))
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pgn", type=Path)
    ap.add_argument("--log", type=Path)
    ap.add_argument("--engine", default="BB1")
    ap.add_argument("--opponent")
    args = ap.parse_args()

    if args.pgn:
        all_res, per_opp = parse_pgn(args.pgn, args.engine, args.opponent)
        s = stats(all_res)
        print(f"engine      : {args.engine}")
        print(f"games       : {s.get('n')}  "
              f"(W {s.get('w')} D {s.get('d')} L {s.get('l')})")
        if s.get("elo") is None:
            print("score       : 0 or 1 -> Elo not defined")
        else:
            print(f"score       : {100*s['score']:.1f}%")
            print(f"Elo diff    : {s['elo']:+.1f}  "
                  f"(95% CI {s['lo']:+.1f} .. {s['hi']:+.1f}, "
                  f"SE {s['se_elo']:.1f})")
        print()
        for opp, res in sorted(per_opp.items()):
            o = stats(res)
            if o.get("elo") is None:
                print(f"  vs {opp:20s} n={o['n']:4d} score=0/1")
                continue
            print(f"  vs {opp:20s} n={o['n']:4d} "
                  f"({o['w']}-{o['d']}-{o['l']}) score={100*o['score']:5.1f}% "
                  f"Elo {o['elo']:+7.1f} +/- {Z95*o['se_elo']:.1f}")
        return 0

    if args.log:
        rows = parse_log(args.log)
        if not rows:
            print("no score lines found", file=sys.stderr)
            return 1
        a, b, w, l, d = rows[-1]
        results = [1.0] * w + [0.0] * l + [0.5] * d
        s = stats(results)
        print(f"{a} vs {b}: {w}-{l}-{d}")
        if s.get("elo") is not None:
            print(f"Score of {a}: {100*s['score']:.1f}%  "
                  f"Elo {s['elo']:+.1f} +/- {Z95*s['se_elo']:.1f} "
                  f"(95% CI {s['lo']:+.1f} .. {s['hi']:+.1f})")
        return 0

    ap.error("give --pgn or --log")
    return 2


if __name__ == "__main__":
    sys.exit(main())
