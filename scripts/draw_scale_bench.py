#!/usr/bin/env python3
"""Drawish-scaling benchmark: does the evaluation know which low-material
endgames are unwinnable?

Motivation (DEVELOPMENT.md, the Kieseritzky-Jaenisch endgame): a lone bishop
(and even a bishop vs two pawns) is scored as a clean pawn up, so a dead-drawn
position looks winning.  The engine has a drawish-endgame scale factor
(`Scale_Factor` in bbchess-eval.adb) that can damp those scores, but its
no-pawn branch is off by default (`P_SCALE_NOPAWN 0`).

This script measures that on a tablebase-verified position set: it probes each
FEN with Syzygy and compares the engine's static evaluation (`--eval-fens`)
against the truth.

  * DRAWN positions  -> a good scaler damps |eval| to ~0.
  * DECISIVE positions -> a scaler must NOT zero a win (that is a regression).

Usage:
  python3 scripts/draw_scale_bench.py [--binary bin/babachess]
                                      [--params FILE] [--fen FILE]
                                      [--syzygy DIR] [--verbose]
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import chess
import chess.syzygy

ROOT = Path(__file__).resolve().parent.parent

# A drawn position whose |eval| is above this is still "thought winning".
DRAW_THRESHOLD = 40
# A decisive position whose |eval| is at or below this is effectively zeroed.
ZERO_THRESHOLD = 10


def load_fens(path: Path) -> list[str]:
    fens = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            fens.append(line)
    return fens


def engine_evals(binary: Path, fens: list[str], params: Path | None) -> list[int]:
    """Static evaluation of each FEN (White's point of view), one engine call."""
    tmp = Path("/tmp/opencode/_draw_scale.fen")
    tmp.parent.mkdir(parents=True, exist_ok=True)
    tmp.write_text("\n".join(fens) + "\n")
    cmd = [str(binary), "--eval-fens", str(tmp)]
    if params is not None:
        cmd += ["--params", str(params)]
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    vals = [int(x) for x in out.split()]
    if len(vals) != len(fens):
        raise RuntimeError(f"eval count mismatch: {len(vals)} != {len(fens)}")
    return vals


def syzygy_class(tb, fen: str):
    """(wdl, winner) with wdl from the side to move; winner in {White, Black,
    None}.  Returns (None, None) when the position is not probeable."""
    try:
        board = chess.Board(fen)
        wdl = tb.probe_wdl(board)
    except (ValueError, KeyError, chess.syzygy.MissingTableError):
        return None, None
    if wdl > 0:
        return wdl, board.turn
    if wdl < 0:
        return wdl, not board.turn
    return 0, None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--binary", default=str(ROOT / "bin" / "babachess"))
    ap.add_argument("--params", default=None, help="engine --params file")
    ap.add_argument("--fen", default=str(ROOT / "bench" / "endgames_scale.fen"))
    ap.add_argument("--syzygy", default=str(Path.home() / "syzygy" / "3-4-5-all"))
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    fens = load_fens(Path(args.fen))
    if not fens:
        print(f"no FENs in {args.fen}", file=sys.stderr)
        return 1

    tb = chess.syzygy.open_tablebase(args.syzygy)
    evals = engine_evals(Path(args.binary), fens, Path(args.params)
                         if args.params else None)

    drawn, decisive, unknown = [], [], []
    for fen, ev in zip(fens, evals):
        wdl, winner = syzygy_class(tb, fen)
        if wdl is None:
            unknown.append((fen, ev))
        elif wdl == 0:
            drawn.append((fen, ev))
        else:
            decisive.append((fen, ev, winner))
    tb.close()

    label = "default" if not args.params else f"params={args.params}"

    if args.verbose:
        print(f"# config={label}")
        for fen, ev in drawn:
            print(f"DRAW  {ev:+6d}  {fen}")
        for fen, ev, winner in decisive:
            tag = "WHITE" if winner == chess.WHITE else "BLACK"
            print(f"WIN-{tag} {ev:+4d}  {fen}")
        for fen, ev in unknown:
            print(f"UNKN  {ev:+6d}  {fen}  (not tablebase-probeable)")
        print()

    # --- metrics ----------------------------------------------------------
    draw_within = sum(1 for _, ev in drawn if abs(ev) <= DRAW_THRESHOLD)
    draw_abs = [abs(ev) for _, ev in drawn]
    decisive_zeroed = sum(1 for _, ev, _ in decisive if abs(ev) <= ZERO_THRESHOLD)
    decisive_wrong = sum(1 for _, ev, w in decisive
                         if (ev > 0) != (w == chess.WHITE))
    mean_draw = sum(draw_abs) / len(draw_abs) if draw_abs else 0.0

    print(f"config={label}")
    print(f"  DRAWN    {len(drawn):2d}: |eval| mean {mean_draw:6.1f} cp, "
          f"{draw_within}/{len(drawn)} within +-{DRAW_THRESHOLD}")
    print(f"  DECISIVE {len(decisive):2d}: {decisive_zeroed} zeroed "
          f"(<= {ZERO_THRESHOLD} cp, regression), {decisive_wrong} on the "
          f"wrong side")
    if unknown:
        print(f"  UNKNOWN  {len(unknown):2d}: not tablebase-probeable")
    print(f"SUMMARY config={label} drawn={len(drawn)} "
          f"draw_within={draw_within} draw_mean_abs={mean_draw:.1f} "
          f"decisive={len(decisive)} decisive_zeroed={decisive_zeroed} "
          f"decisive_wrong_side={decisive_wrong} unknown={len(unknown)}")

    # A correct configuration: drawn positions damped, no decisive position
    # zeroed, no wrong-side sign.  Report, but do not fail the shell here.
    ok = (len(drawn) == 0 or draw_within == len(drawn)) and decisive_zeroed == 0 \
        and decisive_wrong == 0
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
