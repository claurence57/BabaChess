# Contributing to BabaChess

Thanks for your interest in BabaChess, a bitboard chess engine written in
**Ada 2012**. This file explains how to build it, how to test it, and the rules
that any change must follow.

## Ground rules

BabaChess is developed with a strict evidence discipline:

- **Correctness first.** Any change to move generation, make/unmake or the
  search must keep `--selftest` green. The perft counts (20 / 400 / 8 902 /
  197 281 / 4 865 609) must not change.
- **The evaluation must stay symmetric.** `Static(mirror) = -Static` and
  `Static(startpos) = 0`. This is checked by `--selftest` and by
  `scripts/sym_check.py`.
- **No strength claim without a measurement.** A change that is meant to make
  the engine stronger must be validated by SPRT (see below). "Looks correct"
  is not evidence.
- **Measured negatives are documented, not hidden.** If an idea does not gain,
  record it (the project keeps a log of what was tried and rejected).

## Build

Requires **GNAT** (Ada 2012) and **gprbuild**.

```bash
make                       # release, ISA auto-detected from the host CPU
make portable              # generic x86-64 (software PEXT, no BMI2)
make debug                 # assertions + all warnings (the mode that warns)
make checked               # release speed with run-time checks (SPRT campaigns)
```

Or directly:

```bash
gprbuild -P babachess.gpr -XMode=release    # -> bin/babachess
```

All modes share `obj/`: run `rm -rf obj` before rebuilding after switching
modes, or `--bench` numbers are meaningless.

## Test

```bash
./bin/babachess --selftest    # perft 1-5, Zobrist, FEN, search, SEE, protocol
./bin/babachess --bench 9     # 8 fixed positions at depth 9 -> nodes/time/knps
python3 scripts/sym_check.py  # evaluation symmetry, >=3000 positions
```

CI builds `debug` with warnings as errors (`-gnatwe`), then `release`,
`portable` and `checked`, and runs `--selftest` on each.

## Measure strength (SPRT)

`scripts/sprt.sh` runs a sequential test between two binaries over a balanced
opening suite, in both colours, with the book neutralised:

```bash
scripts/sprt.sh 1+0.1 0 5 1000 7 <previous_binary> bin/babachess
```

A short match proves nothing: 300 games only resolve about ±30 Elo. Use at
least 1 000 games (two independent seeds for a small effect). See
`src/doc/outils-et-tests-en.md` and `docs/07-testing-en.md` for the method.

## Tune parameters

- **Texel** (`scripts/texel_extract.py`, `scripts/texel.py`) tunes the
  evaluation on quiet self-play positions; the dataset must come from the
  engine's own games, never from human games.
- **SPSA** (`scripts/spsa.py`) tunes search margins or a parameter subset on
  game results, with the same binary through `--params` files.

Any tuned set must be confirmed by a long SPRT before adoption.

## Documentation

- **`docs/`** — the general, pedagogical, bilingual guide *How to build a
  chess engine*, one chapter per topic in `-en.md` and `-fr.md`.
- **`src/doc/`** — the technical reference for this engine (French).
- Keep `README-en.md` (English) and `README-fr.md` in sync.

## Style

- Ada 2012; match the existing naming and the file/unit convention
  (`BBChess.Search.PV` -> `bbchess-search-pv.adb`).
- Never suppress type errors, never leave an empty exception handler.
- Keep the hot path free of per-node allocation and of work that changes the
  search tree unintentionally.
- Do not commit generated files (`obj/`, `bin/`, `*.o`, `*.ali`, `*.pgn`, the
  book `.bin`).

## Licence

By contributing you agree that your contribution is released under the
project's licence: **GPL-3.0-or-later** (see `LICENSE`).
