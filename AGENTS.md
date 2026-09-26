# AGENTS.md — BabaChess

**BabaChess** is a bitboard chess engine written in **Ada 2012**. It is a **fork
of [AdaChess](https://github.com/adachess/AdaChess)**, derived from AdaChess's
bitboard engine. BabaChess is now the **sole development target**.

| | BabaChess |
|---|---|
| Sources | `src/` (packages `BBChess.*` + C shim `bbchess-bits.c`) |
| Project file | `babachess.gpr` |
| Binary | `bin/babachess` |
| Role | **Active development target** |

`DEVELOPMENT.md` is the authoritative engineering log (in French). It covers the
current era (§48 onward: the solidity/cleanliness/performance work, P0-P7 and
after) and uses the BabaChess names (`babachess.gpr` / `bin/babachess`); the
pre-fork history (§1-§47, which still refers to the old `adachess_bb.gpr` /
`bin_bb/adachess_bb`) is archived in `DEVELOPMENT_HISTORY.md`. `CHANGELOG.md`
and `CHANGELOG_TECHNIQUE.md` cover the engine. `README.md` describes BabaChess;
`NOTICE.md` records provenance and licensing.

## Build

```bash
make                                          # release, ISA auto-detected
make portable                                 # generic x86-64
make debug                                    # assertions + warnings
# or directly with gprbuild:
gprbuild -P babachess.gpr -XMode=release      # -> ./bin/babachess
gprbuild -P babachess.gpr -XMode=portable     # -> ./bin/babachess
gprbuild -P babachess.gpr -XMode=debug        # -> ./bin/babachess
```

- Toolchain: GNAT Ada 2012 + `gprbuild`. Modes: `release` (default), `checked`,
  `debug`, `portable`.
- `release` compiles with `-mpopcnt -mbmi -mbmi2` and inlines `_pext_u64` (PEXT)
  for sliding attacks — it requires a CPU with BMI2/POPCNT. `portable` drops
  those switches and uses the software PEXT fallback (`bbchess-bits.c`), so it
  runs on any x86-64 CPU at ~25% lower speed; both modes are otherwise identical.
- `checked` is `release` speed with the run-time checks kept on (`-gnata`, no
  `-gnatp`); it is the mode for long SPRT campaigns (`release` is the mode to
  distribute).
- `debug` turns on the Ada assertions and all warnings (`-gnatwa -gnatVa`); it is
  the only mode that carries warnings.
- `release` and `portable` share `obj/`: after switching, `rm -rf obj`
  before rebuilding, or `--bench` comparisons are meaningless.
- The root `Makefile` (RubiChess-style) detects the host CPU and passes
  `-march=x86-64-vN` (or `ARCH=...`) through the `BABA_ARCH_FLAGS` project
  external; it does not use `-march=native` by default (measured slower). See
  `src/doc/build-and-cpu.md`.

## Test & verify (no test framework; CI runs in GitHub Actions)

```bash
./bin/babachess --selftest    # 136 checks: perft 1-5, Zobrist, packed moves,
                                 # FEN validation, search, repetition, SEE,
                                 # Polyglot key, book hardening, protocol.
                                 # Pass/fail counter; exit non-zero on failure.
./bin/babachess --bench 9     # 8 fixed positions at depth 9 -> nodes/time/knps
```

- CI (`.github/workflows/ci.yml`): builds `debug` with warnings as errors
  (`-cargs:ada -gnatwe`), then `release`/`portable`/`checked` and `--selftest`.

- **Golden rule**: any movegen/search/eval change must keep `--selftest` green
  (perft counts must not change) and keep evaluation symmetric.
- Symmetry is tested on `Static`: startpos = 0 and mirror ⇒ `-Static`.
  `Evaluate` itself is not antisymmetric because it adds a tempo bonus.
- The engine's perft is validated against known perft values and was cross-checked
  against AdaChess's mailbox engine before the fork.

## Benchmarking / matches (needs `cutechess-cli`)

```bash
scripts/sprt.sh 1+0.1 0 5 1000 7 <previous_binary> bin/babachess
scripts/ab.sh 1+0.1 20 7          # reference vs current HEAD
scripts/vs_gnuchess.sh 30+1 12 7  # vs GNU Chess (UCI)
```

- `scripts/sprt.sh [tc] [elo0] [elo1] [max_games] [seed] [old] [new]` is the
  **decision tool**: a sequential test (verdict PASS/FAIL/INCONCLUSIVE, exit
  0/1/2) between two builds over `openings/openings.epd` in both colours. Validate
  a patch by passing the *previous* binary as `old`.
- `ab.sh` compares against `~/bin/adachess_bb` (the frozen AdaChess `bb-1.0`
  reference); rebuild first. `vs_gnuchess.sh` needs the machine-local wrapper
  `~/bin/gnuchess_uci.sh`.
- **A 300-game SPRT only resolves ~±30 Elo**: never conclude "neutral/negative"
  from a short match; use ≥ 600-1000 games for small effects.
- Match fairness: use the opening suite and neutralise the book on both sides;
  a match from the start position is biased (~70% White).
- `scripts/diag_bench.py build|score` measures a global success rate on a
  40-position bench (`bench/diag.tsv`); never optimize a single position.
- `scripts/spsa.py` tunes parameters via SPSA over `--params` (same binary, book
  neutralised); validate any result with a long SPRT.

## Command-line modes

`--selftest`, `--bench [depth]` (default 8), `--threads N` (Lazy SMP, max 16;
also `-TN` / `--thread=N`), `--book <file>`, `--syzygy <dir>`, `--dump-params`,
`--eval-fens <file>`, `--params <file>`. `--params`/`--threads` apply to every
mode; `--book`/`--syzygy` only to the playing modes (not probed by
`--selftest`/`--bench`/`--eval-fens`).

The engine speaks **both** XBoard and UCI (protocol selected by the `uci`
command). The UCI search is **asynchronous** (runs in a task): `isready` answers
`readyok` during a search, `stop` interrupts it, `quit` stops and exits. `go`
supports `wtime`/`btime`/`winc`/`binc`/`movetime`/`depth`/`nodes`/`infinite`.
The XBoard search path is synchronous.

## Conventions & gotchas

- Ada unit ↔ file name: `BBChess.Search.PV` → `bbchess-search-pv.adb`;
  `BBChess.See` → `bbchess-see.adb`.
- Generated/ignored (never commit): `obj/`, `bin/`, `babachess`,
  `adachess`, `*.o`, `*.ali`, `*.pgn`, `*.txt`.
- `scripts/tune.py` (Texel tuner) requires `python-chess`; `scripts/gen_dataset.py`
  builds `FEN;result` datasets from PGN. Eval tuning was a **negative result** —
  default parameters were kept on purpose (see `DEVELOPMENT_HISTORY.md` §21).
- Opening book: Polyglot `.bin` (`BBChess.Polyglot`), probed before the search
  (16-ply limit, legal-move checked). Fetch a CC0 book with
  `scripts/fetch_book.sh` → `books/book.bin` (gitignored). Override with
  `--book <file>` or UCI `setoption name BookFile value <path>`. Polyglot keys
  are cross-checked in `--selftest`.
- Endgame tablebases: Syzygy via **vendored Fathom** (`src/fathom/`, **MIT** —
  see `NOTICE.md`). Enable with `--syzygy <dir>` or UCI `SyzygyPath`; inert
  without `.rtbw`/`.rtbz` files. WDL is probed in the search (no castling
  rights); no DTZ yet.
- The UCI `Hash` option is **inert** (the table size is compile-time); the option
  advertises the real size and warns when a different value is requested.
- Log notable engine changes in `DEVELOPMENT.md` (French, sectioned) and
  `CHANGELOG.md`, matching the existing style. Licence: GPL-3.0-or-later, except
  the MIT C components (see `NOTICE.md`).
