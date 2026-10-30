#!/usr/bin/env python3
"""Anchored Elo estimate for one engine from a gauntlet.

`elo_report.py` reports the Elo *difference* against one opponent. This tool
goes one step further: it places the engine on a reference scale by fitting a
single rating R to all the games, with each opponent's rating held at its
nominal value (`--anchor NAME=ELO`):

    p(game) = 1 / (1 + 10 ** ((R - R_opp) / 400))

R maximises the Bernoulli log-likelihood; the 95% interval comes from the
observed Fisher information. Pooling several opponents gives a tighter,
more robust estimate than averaging per-opponent differences.

The absolute number is only as sound as the anchors: Stockfish's UCI_Elo is a
self-consistent ladder, not an official CCRL rating. Compare ratings produced
with the same anchors, not across scales.

Usage:
  scripts/elo_rate.py --pgn out/*.pgn --engine Baba \\
      --anchor SF2000=2000 --anchor SF2400=2400 --anchor SF2800=2800
  scripts/elo_rate.py --pgn out/*.pgn --anchors scripts/elo_pool.conf --json
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

LN10_400 = math.log(10.0) / 400.0
Z95 = 1.959963984540054


def load_anchors(pairs: list[str] | None,
                 files: list[str] | None) -> dict[str, float]:
    anchors: dict[str, float] = {}
    for path in files or []:
        for line in Path(path).read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "|" in line:
                parts = line.split("|")
                name, value = parts[0], parts[4]
            elif "=" in line:
                name, value = line.split("=", 1)
            else:
                name, value = line.rsplit(None, 1)
            anchors[name.strip()] = float(value)
    for item in pairs or []:
        if "=" not in item:
            raise SystemExit(f"--anchor expects NAME=ELO, got {item!r}")
        name, value = item.split("=", 1)
        anchors[name.strip()] = float(value)
    return anchors


def read_games(paths: list[str], engine: str) -> list[tuple[str, float]]:
    import chess.pgn

    games: list[tuple[str, float]] = []
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as fh:
            while True:
                game = chess.pgn.read_game(fh)
                if game is None:
                    break
                result = game.headers.get("Result", "*")
                if result not in ("1-0", "0-1", "1/2-1/2"):
                    continue
                white = game.headers.get("White", "")
                black = game.headers.get("Black", "")
                if engine == white:
                    opponent, engine_white = black, True
                elif engine == black:
                    opponent, engine_white = white, False
                else:
                    continue
                if result == "1/2-1/2":
                    score = 0.5
                else:
                    score = 1.0 if (result == "1-0") == engine_white else 0.0
                games.append((opponent, score))
    return games


def expected(rating: float, opponent: float) -> float:
    return 1.0 / (1.0 + 10.0 ** ((opponent - rating) / 400.0))


def fit(games: list[tuple[str, float]], anchors: dict[str, float]):
    def slope(rating: float) -> float:
        return LN10_400 * sum(score - expected(rating, anchors[opp])
                              for opp, score in games)

    lo, hi = -4000.0, 4000.0
    flo, fhi = slope(lo), slope(hi)
    while flo < 0.0 and lo > -20000.0:
        lo *= 2.0
        flo = slope(lo)
    while fhi > 0.0 and hi < 20000.0:
        hi *= 2.0
        fhi = slope(hi)
    if flo < 0.0:
        return None, "all games lost: rating is below the anchor range"
    if fhi > 0.0:
        return None, "all games won: rating is above the anchor range"
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        if slope(mid) > 0.0:
            lo = mid
        else:
            hi = mid
    rating = 0.5 * (lo + hi)
    info = LN10_400 ** 2 * sum(
        expected(rating, anchors[opp]) * (1.0 - expected(rating, anchors[opp]))
        for opp, _ in games)
    se = 1.0 / math.sqrt(info) if info > 0.0 else float("inf")
    return rating, se


def elo_from_score(score: float) -> float | None:
    if score <= 0.0 or score >= 1.0:
        return None
    return -400.0 * math.log10(1.0 / score - 1.0)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pgn", nargs="+", required=True)
    ap.add_argument("--engine", default="Baba")
    ap.add_argument("--anchor", action="append", default=[],
                    help="NAME=ELO (repeatable)")
    ap.add_argument("--anchors", action="append", default=[],
                    help="file with NAME=ELO lines (repeatable)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    anchors = load_anchors(args.anchor, args.anchors)
    games = read_games(args.pgn, args.engine)
    if not games:
        print(f"no games for engine {args.engine!r} in {args.pgn}", file=sys.stderr)
        return 1

    missing = sorted({opp for opp, _ in games if opp not in anchors})
    if missing:
        print(f"missing anchor for: {', '.join(missing)} "
              f"(use --anchor NAME=ELO)", file=sys.stderr)
        return 2

    rating, err = fit(games, anchors)
    per: dict[str, list[float]] = {}
    for opp, score in games:
        per.setdefault(opp, []).append(score)

    n = len(games)
    wins = sum(1 for _, x in games if x == 1.0)
    draws = sum(1 for _, x in games if x == 0.5)
    losses = sum(1 for _, x in games if x == 0.0)
    mean = sum(x for _, x in games) / n

    per_rows = []
    for opp, res in sorted(per.items()):
        m = len(res)
        s = sum(res) / m
        diff = elo_from_score(s)
        per_rows.append({
            "opponent": opp, "anchor": anchors[opp], "games": m,
            "wins": sum(1 for x in res if x == 1.0),
            "draws": sum(1 for x in res if x == 0.5),
            "losses": sum(1 for x in res if x == 0.0),
            "score": s,
            "implied_elo": (anchors[opp] + diff) if diff is not None else None,
        })

    result = {
        "engine": args.engine,
        "games": n, "wins": wins, "draws": draws, "losses": losses,
        "score": mean,
        "rating": rating,
        "se": err if rating is not None else None,
        "ci95": ([rating - Z95 * err, rating + Z95 * err]
                 if rating is not None else None),
        "anchors": anchors,
        "per_opponent": per_rows,
    }

    if args.json:
        print(json.dumps(result, indent=2))
        return 0

    print(f"engine      : {args.engine}")
    print(f"games       : {n}  (W {wins} D {draws} L {losses}, "
          f"score {100 * mean:.1f}%)")
    if rating is None:
        print(f"rating      : undefined ({err})")
    else:
        lo, hi = rating - Z95 * err, rating + Z95 * err
        print(f"rating      : {rating:.0f}  "
              f"(95% CI {lo:.0f} .. {hi:.0f}, SE {err:.1f})")
    print("per opponent:")
    for row in per_rows:
        implied = (f"{row['implied_elo']:.0f}" if row["implied_elo"] is not None
                   else "n/a")
        print(f"  {row['opponent']:16s} anchor {row['anchor']:6.0f}  "
              f"n={row['games']:4d} ({row['wins']}-{row['draws']}-"
              f"{row['losses']}) score {100 * row['score']:5.1f}%  "
              f"implied {implied}")
    print("note        : the absolute value follows the anchor scale "
          "(e.g. Stockfish UCI_Elo), not an official rating list.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
