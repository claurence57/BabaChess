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
- Integral self-test suite (145 checks, pass/fail counter with a non-zero exit
  on failure): perft 1-5, Zobrist, packed moves, FEN validation, search,
  repetition, SEE, Polyglot keys, book-file hardening and protocol parsing.

## Building

Requires **GNAT** (Ada 2012) and **gprbuild**.

```bash
gprbuild -P babachess.gpr -XMode=release    # -> bin/babachess  (POPCNT/BMI2/PEXT)
gprbuild -P babachess.gpr -XMode=checked    # -> bin/babachess  (release + runtime checks)
gprbuild -P babachess.gpr -XMode=portable   # -> bin/babachess  (any x86-64)
gprbuild -P babachess.gpr -XMode=debug      # -> bin/babachess  (assertions + warnings)
```

- `release` compiles with `-mpopcnt -mbmi -mbmi2` and inlines the PEXT intrinsic
  (`_pext_u64`) for sliding attacks; it **requires** a CPU with BMI2/POPCNT.
- `checked` is `release` speed (`-O3 -gnatN -flto`) but **keeps the run-time
  checks on** (`-gnata`, no `-gnatp`): assertions, range and index checks are
  active. It is ~11% slower, and is the mode to use for **long SPRT
  campaigns** (defined behaviour instead of silent undefined behaviour).
- `portable` drops those switches and uses the software PEXT fallback in
  `bbchess-bits.c`, so it runs on any x86-64 CPU (~25% slower).
- `debug` enables the Ada assertions and all warnings, and is the only mode that
  carries them.

`release` is the mode to distribute; `checked` is the mode to validate with.

See `src/doc/build-and-cpu.md` for the exact compiler switches and the CPU
optimization history.

## Testing

```bash
./bin/babachess --selftest    # 145 checks: perft 1-5, Zobrist, FEN, search,
                              # SEE, Polyglot (+ book hardening, protocol)
./bin/babachess --bench 9     # 8 fixed positions at depth 9 -> nodes/time/knps
```

The **golden rule** for any change: `--selftest` must stay green (perft counts
must not move) and evaluation must stay symmetric.

## Downloads

Release archives are named `babachess-<version>-<os>-x86_64-<build>`, with
`os` = `linux` or `windows` and `build` = `bmi2` (requires BMI2+POPCNT, i.e.
Intel Haswell 2013 / AMD Zen 2017 or newer) or `portable` (any x86-64 CPU,
software PEXT, ~25% slower). Pick **one**:

| Your CPU | Choose |
|---|---|
| Modern Intel/AMD (BMI2 + POPCNT) | `…-bmi2` |
| Older x86-64, or you see an illegal-instruction crash | `…-portable` |
| AMD Zen 1 / Zen 2 (microcoded PEXT) | try both; `portable` is often faster |

Verify integrity against the published `SHA256SUMS`. Each archive contains the
binary, `LICENSE`, `NOTICE.md`, `src/fathom/LICENSE`, `README.md`,
`RELEASE_NOTES_<version>.md` and the bundled book at `books/book.bin`.

> **Note.** The historical `bb-1.0` / `bb-2.0` tags belong to AdaChess-BB
> **before** the fork and are not part of BabaChess's numbering; BabaChess
> starts at `1.0.0`.

## Quick start with a GUI

BabaChess is a command-line UCI/XBoard engine; configure it as an external
engine in a GUI.

- **Arena (Windows):** `Engines → Install New Engine…`, pick `babachess.exe`,
  choose **UCI**.
- **Cute Chess / cutechess-cli:** GUI: add an engine (protocol UCI). CLI:
  `cutechess-cli -engine cmd=./babachess -engine cmd=<opponent> -each proto=uci tc=60+0.6 -games 2`
- **Lucas Chess (Windows):** `Competition → Engines… → New engine`, protocol
  **UCI**.
- **WinBoard / XBoard:** add an engine and select protocol **UCI** (or let it
  negotiate XBoard), e.g.
  `xboard -fcp ./babachess -fd . -scp ./babachess -sd . -tc 5 -inc 0.1`.

The engine **locates `books/book.bin` by itself** (next to the executable, one
directory up, `./books/`, `~/ .babachess/book.bin`); override with `--book
<file>` or the UCI option `BookFile`.

Sanity check:

```bash
printf 'uci\nquit\n' | ./babachess    # -> id name BabaChess <version> ... uciok
./bin/babachess --version             # -> BabaChess <version>
./bin/babachess --selftest            # -> 145 checks passed, 0 failed
```

## Using the engine

Set it up in any GUI that supports the XBoard or UCI protocol. Command-line
options include `--threads N` (also `-TN` / `--thread=N`), `--book <file>`,
`--syzygy <dir>`, `--params <file>`, `--dump-params`, `--eval-fens <file>`,
`--bench [depth]`, `--perft <FEN> <depth>`, `--selftest` and `--version`.

UCI options: `Hash` (inert — the size is compile-time; the option advertises
the real size and warns on a different request), `Threads`, `OwnBook`,
`BookFile`, `SyzygyPath`.

## Known limitations

- **DTZ at the root is opt-in.** By default Syzygy probing is WDL-only, so the
  engine knows a position is won but not the distance-to-zero; in the 50-move
  zone it may take a longer route and miss wins a DTZ-aware engine would
  convert. Since 1.2.0 a DTZ root probe exists behind `S_SYZYGY_ROOT 1`
  (`--params`), off by default (see `DEVELOPMENT.md` §78).
- **Transposition table assumes the x86-64 memory model.** The lock-free shared
  TT relies on x86-64 total-store-order semantics (three `pragma Atomic`, no
  explicit barriers) and is **not portable** to ARM or POWER. Releases are
  x86-64 only.
- **The `release` build requires BMI2/POPCNT**; use `portable` otherwise. PEXT
  is microcoded and slow on **AMD Zen 1/Zen 2**, where `portable` is often
  faster.
- **Lazy SMP scaling flattens around 8 threads**; extra helpers beyond that
  bring little strength.
- **Handcrafted evaluation, no NNUE.** King safety is a **known weak point**
  (improvement attempts measured negative, `DEVELOPMENT.md` §17).
- **No engine-strength limiter** (`UCI_LimitStrength`/`UCI_Elo`); use a time
  handicap or fewer `Threads` to weaken it.

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
