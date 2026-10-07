#!/usr/bin/env python3
"""Texel tuner for the BabaChess evaluation (self-play dataset).

Minimises the mean squared error between the game result and
sigmoid(K * Static / 400) over a "FEN;result" dataset (see
texel_extract.py), by coordinate descent over the evaluation parameters that
"--dump-params" lists (scalar P_* values, the piece-square tables and the
passed-pawn tables). The engine itself evaluates every candidate through
"--eval-fens --params", so the tuned evaluation is exactly the one that plays.

Per parameter, the candidates value +/- step and +/- 2*step are evaluated in
parallel and the best one is kept when it lowers the training error. A
held-out validation set (10%) is reported after every round; tuning stops
when it no longer improves (over-fitting guard).

Requires numpy.

Usage: texel.py DATASET [--engine BIN] [--start FILE] [--out FILE]
                [--rounds N] [--jobs N] [--only REGEX]
"""

import argparse
import os
import re
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Switches, gates and the features measured as losing (DEVELOPMENT.md §70):
# not tuned. P_PAWN anchors the scale (K absorbs the rest).
EXCLUDE = re.compile(
    r"^P_(PAWN|PASSED_REAR|SCALE_.*|MOB_AREA|HANGING_.*|THREAT_RQ|CONNECTED"
    r"|BACKWARD_.*|KS_LO|KS_HI)$")


def read_params(engine, start):
    if start:
        lines = open(start).read().splitlines()
    else:
        lines = subprocess.run([engine, "--dump-params"], capture_output=True,
                               text=True, check=True).stdout.splitlines()
    params = {}
    for line in lines:
        parts = line.split()
        if len(parts) == 2 and parts[0].startswith("P_"):
            params[parts[0]] = int(parts[1])
    return params


def step_of(name):
    if name in ("P_KNIGHT", "P_BISHOP", "P_ROOK", "P_QUEEN"):
        return 8
    if name.startswith("P_PST_") or name.startswith("P_PASSED_"):
        return 4
    return 2


class Evaluator:
    def __init__(self, engine, fens_path, results, train, val, k=None):
        self.engine = engine
        self.fens = fens_path
        self.results = results
        self.train = train
        self.val = val
        self.k = k
        self.tmpdir = tempfile.mkdtemp(prefix="texel_")
        self.counter = 0

    def evals(self, params):
        self.counter += 1
        path = os.path.join(self.tmpdir, f"p{self.counter}.params")
        with open(path, "w") as f:
            for n, v in params.items():
                f.write(f"{n} {v}\n")
        out = subprocess.run([self.engine, "--eval-fens", self.fens,
                              "--params", path],
                             capture_output=True, text=True, check=True)
        os.remove(path)
        e = np.array(out.stdout.split(), dtype=np.float64)
        if e.shape[0] != self.results.shape[0]:
            raise RuntimeError("eval count mismatch")
        return e

    def mse(self, e, idx, k=None):
        k = self.k if k is None else k
        p = 1.0 / (1.0 + np.power(10.0, -k * e[idx] / 400.0))
        return float(np.mean((self.results[idx] - p) ** 2))

    def fit_k(self, e):
        lo, hi = 0.2, 3.0
        for _ in range(40):
            a = lo + (hi - lo) / 3
            b = hi - (hi - lo) / 3
            if self.mse(e, self.train, a) < self.mse(e, self.train, b):
                hi = b
            else:
                lo = a
        self.k = (lo + hi) / 2
        return self.k


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dataset")
    ap.add_argument("--engine", default=os.path.join(ROOT, "bin", "babachess"))
    ap.add_argument("--start", default=None,
                    help="initial params file (default: engine defaults)")
    ap.add_argument("--out", default="texel_tuned.params")
    ap.add_argument("--rounds", type=int, default=8)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--only", default=None,
                    help="regex: tune only the matching parameters "
                         "(overrides the default exclusion list)")
    args = ap.parse_args()

    results = []
    fens_path = args.dataset + ".fens"
    with open(args.dataset) as f, open(fens_path, "w") as g:
        for line in f:
            fen, _, r = line.strip().rpartition(";")
            if fen:
                g.write(fen + "\n")
                results.append(float(r))
    results = np.array(results)
    rng = np.random.default_rng(7)
    perm = rng.permutation(len(results))
    n_val = len(results) // 10
    val, train = perm[:n_val], perm[n_val:]

    params = read_params(args.engine, args.start)
    if args.only:
        only = re.compile(args.only)
        names = [n for n in params if only.fullmatch(n)]
    else:
        names = [n for n in params if not EXCLUDE.match(n)]
    ev = Evaluator(args.engine, fens_path, results, train, val)
    e0 = ev.evals(params)
    k = ev.fit_k(e0)
    best = ev.mse(e0, train)
    best_val = ev.mse(e0, val)
    print(f"{len(results)} positions, {len(names)} tuned parameters, K={k:.4f}")
    print(f"start: train {best:.6f}  val {best_val:.6f}", flush=True)

    steps = {n: step_of(n) for n in names}
    pool = ThreadPoolExecutor(max_workers=args.jobs)
    for rnd in range(1, args.rounds + 1):
        changed = 0
        for n in names:
            cands = []
            for d in (steps[n], -steps[n], 2 * steps[n], -2 * steps[n]):
                c = dict(params)
                c[n] = params[n] + d
                cands.append(c)
            evs = list(pool.map(ev.evals, cands))
            scores = [ev.mse(e, train) for e in evs]
            i = int(np.argmin(scores))
            if scores[i] < best:
                best = scores[i]
                params = cands[i]
                changed += 1
        e = ev.evals(params)
        v = ev.mse(e, val)
        print(f"round {rnd}: train {best:.6f}  val {v:.6f}  changed {changed}",
              flush=True)
        if v >= best_val:
            # Keep the last parameters that improved the validation error.
            print("validation error stopped improving", flush=True)
            break
        best_val = v
        with open(args.out, "w") as f:
            for n, value in params.items():
                f.write(f"{n} {value}\n")
        if changed == 0:
            break


if __name__ == "__main__":
    main()
