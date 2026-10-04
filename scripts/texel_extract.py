#!/usr/bin/env python3
"""Build a Texel dataset ("FEN;result") from self-play PGN files.

Each game contributes a random sample of its *quiet* positions, labelled with
the game result from White's point of view (1, 0.5, 0). A position is kept
when:
  * it is at least MIN_PLY plies after the game's start position (the
    opening suite positions are skipped);
  * the side to move is not in check;
  * the move the engine actually played from it is quiet (no capture, no
    promotion, no check): the engine judged no tactic worth playing, so the
    static evaluation is a fair estimate of the position;
  * it is not in the last END_SKIP plies of the game (adjudication noise).

Requires python-chess.

Usage: texel_extract.py OUT.txt GAME.pgn [GAME2.pgn ...]
       [--per-game N] [--seed S]
"""

import argparse
import random

import chess
import chess.pgn

MIN_PLY = 8
END_SKIP = 6

RESULTS = {"1-0": 1.0, "0-1": 0.0, "1/2-1/2": 0.5}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("pgn", nargs="+")
    ap.add_argument("--per-game", type=int, default=12)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    rng = random.Random(args.seed)

    seen = set()
    n_games = n_pos = 0
    with open(args.out, "w") as out:
        for path in args.pgn:
            with open(path) as f:
                while True:
                    game = chess.pgn.read_game(f)
                    if game is None:
                        break
                    res = RESULTS.get(game.headers.get("Result", "*"))
                    if res is None:
                        continue
                    n_games += 1
                    board = game.board()
                    moves = list(game.mainline_moves())
                    cands = []
                    for ply, move in enumerate(moves):
                        if (MIN_PLY <= ply < len(moves) - END_SKIP
                                and not board.is_check()
                                and not board.is_capture(move)
                                and move.promotion is None
                                and not board.gives_check(move)):
                            cands.append(board.fen())
                        board.push(move)
                    rng.shuffle(cands)
                    for fen in cands[:args.per_game]:
                        key = " ".join(fen.split()[:4])
                        if key in seen:
                            continue
                        seen.add(key)
                        out.write(f"{fen};{res}\n")
                        n_pos += 1
    print(f"{n_games} games, {n_pos} positions -> {args.out}")


if __name__ == "__main__":
    main()
