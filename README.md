# BabaChess

[![CI](https://github.com/claurence57/BabaChess/actions/workflows/ci.yml/badge.svg)](https://github.com/claurence57/BabaChess/actions/workflows/ci.yml)

> **BabaChess is a fork of [AdaChess](https://github.com/adachess/AdaChess).**
> It was born from the fork of the AdaChess project, then from the conversion of
> the board representation from **mailbox** to **bitboard**. After many
> optimizations it became a project in its own right. BabaChess is now the sole
> development target; AdaChess's original **mailbox** engine has been **removed**
> from this repository.
>
> See `NOTICE.md` for the full provenance and licence details.

BabaChess is a chess engine written in **Ada 2012**, using a **bitboard** board
representation. It builds with `gprbuild` and speaks both **XBoard/Winboard** and
**UCI**.

> **Name disambiguation.** BabaChess is unrelated to the other chess projects
> with a similar name: **BabChess** (a C++ UCI engine) and **BabasChess** (the
> FICS graphical client). This project is a bitboard engine written in Ada,
> forked from AdaChess.

## Features

- Bitboard move generation (PEXT/BMI2 sliding attacks, with a portable
  software-PEXT fallback for CPUs without BMI2).
- Principal-variation search (PVS) with aspiration windows; transposition table;
  move ordering (hash, MVV-LVA, killers, history, counter-move and 1-ply
  continuation history); late-move reductions and pruning (adaptive null-move,
  futility, razoring, LMP), check extensions, mate-distance pruning.
- Bounded quiescence search with static exchange evaluation (SEE) and delta
  pruning.
- Tapered (middlegame/endgame) handcrafted evaluation.
- **Lazy SMP** multi-threading (shared transposition table, per-thread
  heuristics), up to 16 threads.
- **Polyglot** opening book and **Syzygy** endgame tablebases (via a vendored
  Fathom probe).
- Soft/hard time management with `movestogo` support.
- Integral self-test suite: perft 1-5, Zobrist, packed moves, FEN validation,
  search, repetition, SEE, Polyglot keys.

## Building

Requires **GNAT** (Ada 2012) and **gprbuild**.

```bash
gprbuild -P babachess.gpr -XMode=release    # -> bin/babachess  (POPCNT/BMI2/PEXT)
gprbuild -P babachess.gpr -XMode=portable   # -> bin/babachess  (any x86-64)
gprbuild -P babachess.gpr -XMode=debug      # -> bin/babachess  (assertions + warnings)
```

- `release` compiles with `-mpopcnt -mbmi -mbmi2` and inlines the PEXT intrinsic
  (`_pext_u64`) for sliding attacks; it **requires** a CPU with BMI2/POPCNT.
- `portable` drops those switches and uses the software PEXT fallback in
  `bbchess-bits.c`, so it runs on any x86-64 CPU (~25% slower).
- `debug` enables the Ada assertions and all warnings, and is the only mode that
  carries them.

See `src/doc/build-and-cpu.md` for the exact compiler switches and the CPU
optimization history.

## Testing

```bash
./bin/babachess --selftest    # perft 1-5, Zobrist, FEN, search, SEE, Polyglot
./bin/babachess --bench 9     # 8 fixed positions at depth 9 -> nodes/time/knps
```

The **golden rule** for any change: `--selftest` must stay green (perft counts
must not move) and evaluation must stay symmetric.

## Using the engine

Set it up in any GUI that supports the XBoard or UCI protocol. Command-line
options include `--threads N` (also `-TN` / `--thread=N`), `--book <file>`,
`--syzygy <dir>`, `--params <file>`, `--dump-params`, `--eval-fens <file>`,
`--bench [depth]` and `--selftest`.

## Licence

**GPL-3.0-or-later** (see `LICENSE`), inherited from AdaChess.

Exception: the **C** components reused from Fathom (`src/fathom/`, the Syzygy
tablebase probe, and its bundled `stdendian.h`) are under the **MIT** licence —
see `src/fathom/LICENSE`. Details in `NOTICE.md`.

## Credits

- BabaChess is a fork of **AdaChess** by the AdaChess project
  (https://github.com/adachess/AdaChess).
- Syzygy tablebase probing uses the vendored **Fathom** library (MIT).
- Development has been AI-assisted; see `DEVELOPMENT.md` and `CHANGELOG.md`.
