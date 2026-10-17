# 7. Testing and tuning

A chess engine is easy to break without noticing: a patch can be fast,
elegant and wrong, and an evaluation tweak can look better and still lose
Elo. Testing is the discipline that keeps a project honest, and the order is
fixed: correctness first, cost second, strength last. This chapter covers the
instruments that enforce it, the two tuners, and the rules that stop you
fooling yourself. BabaChess is the example.

## 7.1 Correctness first: perft and self-tests

The first line of defence is **perft**: a node count from walking every legal
move to a fixed depth, usually five or six from the start. Its published counts
(20, 400, 8 902, 197 281 and 4 865 609 at depths 1 to 5) act as an external
oracle, and a wrong count is a rules bug (legality, castling, en passant,
promotion), never a strength improvement.

Around perft sits an internal battery: bitboard primitives, Zobrist hashing,
packed move round-trips, FEN validation, search sanity, repetition and SEE.
One failure must stop everything. BabaChess runs it with `./bin/babachess
--selftest` (146 checks, non-zero exit on failure), driven by
`BBChess.Self_Tests` (`src/bbchess-self_tests.adb`) and counted by
`BBChess.Test_Harness`; `scripts/perft_suite.sh` cross-checks perft, and
`--perft <FEN> <depth>` exposes it manually.

## 7.2 Evaluation symmetry

Mirror the board, swap the colours and flip the side to move, and the score
must negate; a sign error or a missing white/black factor shows up at once.
The subtlety is the tempo bonus: a symmetric core such as BabaChess's `Static`
is antisymmetric, but `Evaluate` adds a bonus for the side to move and is
**not**. Symmetry is checked on `Static`, never on the final score.
`scripts/sym_check.py` tests thousands of positions through `--eval-fens` with
zero discrepancy tolerated; `--selftest` covers the start position and
mirrored FENs.

## 7.3 Deterministic regression: bench node counts

A **bench** is cheap and correlates with correctness and speed: fixed positions
searched to a fixed depth with the transposition table reset, reporting nodes,
time and nodes per second. The work is deterministic, so two binaries produce
exactly comparable numbers, and a count that moves is a fingerprint of a
changed search tree. The bench is a **non-regression guard**, not a target.
BabaChess's `Run_Bench` searches eight fixed FENs with `--bench [depth]`
(default 8); `release` and `portable` share `obj/`, so switch builds with
`rm -rf obj` before comparing.

## 7.4 Measuring strength: self-play matches

Nothing above says whether the engine plays better; only games do. An engine
cannot judge its own moves, so the test pits engine against engine under
identical conditions (same time and increment, or same node budget), the
previous build as baseline and the patched build as candidate. A fixed-length
A/B of a few dozen games produces contradictory gaps (about plus or minus 65 to
80 Elo), enough to mislead and never enough to decide; the answer is a
sequential test (7.6).

## 7.5 Openings, colours, book and fixed time

A game from the start position is biased (White scores around 70 percent), so
use an opening suite: a list of positions (BabaChess reads
`openings/openings.epd`) that drops both engines into varied middlegames, each
opening played **twice, with colours swapped**, so no engine benefits from the
choice. Neutralise the book on both sides, otherwise one binary silently finds
`books/book.bin` and the other does not, and fix the conditions: the same time
control, or a fixed node count per move (which removes the dependence on CPU
speed and build mode). BabaChess honours a per-move node cap only on its UCI
path (`go nodes`).

## 7.6 SPRT and why short matches are meaningless

SPRT (Sequential Probability Ratio Test) is the decision tool. Instead of a
fixed number of games, it watches the evidence game after game and stops as
soon as one hypothesis is accepted: **H0**, the candidate is not stronger by
`elo0` (a reject, FAIL); or **H1**, the candidate is at least `elo1` stronger
(an accept, PASS). After every game a log-likelihood ratio (LLR) is compared
with two bounds, `ln((1-beta)/alpha)` and `ln(beta/(1-alpha))`, about plus or
minus 2.944 when `alpha = beta = 0.05`. Cross the upper bound and H1 is
accepted, cross the lower bound and H0 is accepted, otherwise the test is
**INCONCLUSIVE** at the game cap, so a verdict is a conclusion at a known
confidence.

Short matches are meaningless because of resolution. A 40-game match has an
error bar of about plus or minus 87 Elo; 300 games give about plus or minus 33
to 36 Elo; only several hundred to a thousand games resolve small effects. A
HEAD-versus-HEAD match of identical binaries can show a false gap from noise
alone, so never conclude "neutral" or "negative" from a handful of games.

BabaChess drives this through `scripts/sprt.sh`, which wraps `cutechess-cli
-sprt`, plays the opening suite in both colours, neutralises the book for the
match and restores it on exit, and prints a verdict with exit codes PASS (0),
FAIL (1), INCONCLUSIVE (2). To validate a patch, pass the previous binary as
the baseline; comparing to a distant reference passes instantly.

## 7.7 Texel tuning on quiet positions

Given positions with a known result, which parameters make the evaluation agree
with them most often? **Texel tuning** turns this into regression: map each
static evaluation through a logistic curve, minimise the mean squared error
against the game result (1, 0.5 or 0 from White's view), then adjust the
parameters by coordinate descent, keeping a change only if it lowers the error.
The catch is the dataset: positions from a live game correlate the evaluation
with the result of the whole game, so keep **quiet** positions only (no
captures, no checks), where the evaluation means something, and hold out a
validation set to avoid over-fitting.

The warning is that a lower error is not a stronger engine: the tuned set must
be re-validated in real games. BabaChess tunes through `--eval-fens` (static
evaluations), `--dump-params` (scalars) and `--params` (loads a set without a
rebuild); `scripts/texel.py` runs the descent and `scripts/texel_extract.py`
builds a quiet self-play dataset.

## 7.8 SPSA tuning on parameters

Texel optimises a proxy; **SPSA** (Simultaneous Perturbation Stochastic
Approximation) optimises the real thing, the result of games. It wraps the same
binary with different parameter files, so no rebuild is needed: each iteration
perturbs all tunable parameters at once in a random direction, plays a match
between the two perturbed engines, and nudges them along the measured gradient
(`c_k = c0 / (k+1)^0.101`, `a_k = a0 / (k+1+A)^0.602`). It is slower and noisier
than Texel, because every estimate costs a match, and a useful run lasts hours.
It proposes and the SPRT disposes: the final set goes through the same ~300-game
SPRT at a real time control. BabaChess's `scripts/spsa.py` perturbs a curated
list of evaluation parameters (material excluded), with the book neutralised
and restored.

## 7.9 Golden rules

1. `--selftest` green and perft unchanged: mandatory before any match.
2. Any new evaluation stays symmetric (`Static` at the start = 0).
3. Never decide below about 300 games; at short lengths the error bar dwarfs
   the effect.
4. `scripts/sprt.sh` is the decision tool; other matches are noisy thermometers.
5. `--bench` and the multi-position diagnostic are non-regression guards, not
   targets; never optimize a single position.
6. A tuner that lowers its error earns adoption only through an SPRT.

## 7.10 BabaChess as the example

The workflow is a loop: change the code, build `release`, run `./bin/babachess
--selftest`, compare `--bench 9`, then decide with `scripts/sprt.sh` passing the
previous binary as the baseline. The supporting files are `BBChess.Self_Tests`
(`src/bbchess-self_tests.adb`), `scripts/perft_suite.sh`, `scripts/sym_check.py`,
`scripts/sprt.sh`, `scripts/texel.py` and `scripts/spsa.py`. Each instrument is
described in `src/doc/outils-et-tests.md`.

## See also

- `src/doc/outils-et-tests.md`: reference documentation of the test and
  measurement tools (`--selftest`, perft, `--bench`, `--eval-fens`, `--params`,
  SPRT, tuners).
- `src/bbchess-self_tests.adb`: the internal battery (`BBChess.Self_Tests`), run
  by `--selftest` and counted by `BBChess.Test_Harness`.
- `AGENTS.md`: build modes, the golden rule, and how to run the bench and
  matches.
- `scripts/`: `perft_suite.sh`, `sym_check.py`, `sprt.sh`, `texel.py` and
  `spsa.py`.
- Neighbouring chapters: `06-endgame-tablebases-en.md` and
  `08-roadmap-and-limits-en.md`.
- Perft: <https://www.chessprogramming.org/Perft>; SPSA:
  <https://www.chessprogramming.org/SPSA>; Automated Tuning (Texel):
  <https://www.chessprogramming.org/Automated_Tuning>; Testing:
  <https://www.chessprogramming.org/Testing>.
