# BabaChess 1.6.0 — Release Notes

**BabaChess** is a chess engine written in **Ada 2012**, using a **bitboard**
board representation. It speaks **UCI** and runs on 64-bit **Windows** and
**Linux**. BMI2/POPCNT and portable x86-64 builds are provided.

BabaChess is a fork of [AdaChess](https://github.com/adachess/AdaChess); see
`NOTICE.md` for provenance and licensing.

---

## What's in 1.6.0

This release concentrates on **protocol completeness, correctness and code
architecture**. No Elo gain over 1.5.0 is claimed: no 1.5.0 versus 1.6.0 match
has been run, and the final cleanup deliberately preserves search trees and
default evaluation scores.

### Breaking change: UCI only

The native XBoard/WinBoard protocol has been removed. GUIs must select UCI;
XBoard can still be used through its UCI adapter. The match scripts now use
`proto=uci` as well.

### Protocol and diagnostics

- `go searchmoves <moves…>` restricts the root move list.
- `go perft <n>` reports per-root and total leaf counts, without a `bestmove`.
- `go mate N` stops as soon as a mate within N moves is proven.
- `MultiPV` (1–8) reports exact full-window scores and a PV for each line.
- `currmove`, `currmovenumber`, `seldepth` and `tbhits` enrich UCI `info` lines.
- `UCI_LimitStrength` and `UCI_Elo` provide a monotone, deliberately uncalibrated
  node cap from 1,000 to 10,000,000 nodes per move.
- The `d` command prints the board, FEN, side, castling rights and Zobrist key;
  `eval` breaks the static score down by term.
- `Clear Hash` is now advertised, `id author` is filled in, `Contempt` and
  `Syzygy50MoveRule` are configurable, and the handshake has 15 lines.

### Correctness fixes

- An en-passant square is now kept only when an opposing pawn can actually
  capture. FEN output, Zobrist/Polyglot identity and repetition detection agree.
- A position that is already drawn at the root (repetition, fifty moves or
  insufficient material) is scored as a draw instead of being searched normally.
- A soft clock limit and a node cap can now be supplied together without the
  node cap silently replacing the soft limit.

### Architecture and cleanup

- `Search_Request` carries depth, soft/hard time and node limits together.
- UCI `position`, `go`, book discovery and Syzygy discovery are separate
  subunits; obsolete protocol clock globals have been removed.
- The TT replacement policy is injected into `Search.TT`; `Store` reuses one
  snapshot per entry. Per-thread contexts remain private under Lazy SMP.
- Rejected dormant experiments and unused interfaces have been removed,
  including quiet checks in quiescence, IIR, stability-based time scaling and
  the disabled hanging/outpost/imbalance evaluation terms.
- Hot paths avoid redundant occupancy tests and skip king-danger collection
  when the current phase cannot consume it. Default scores and node counts are
  unchanged by these optimizations.

### Documentation

The archives include the bilingual general guide, the technical reference and
two 17-page architecture booklets: `docs/babachess-architecture-fr.pdf` and
`docs/babachess-architecture-en.pdf`. They cover packages, global state, core
data structures, main functions and execution order.

## Verification

- `--selftest`: **176/176** in release, portable, checked and debug (`-gnatwe`).
- `--bench 9/12/14`: **467,051 / 1,809,934 / 4,767,382** nodes.
- Evaluation output is identical to the pre-cleanup binary on the bench and
  endgame sets, including non-standard king-safety configurations.
- Both TT replacement policies and a four-thread SMP smoke test pass.
- Bilingual documentation and link checks pass.
- The release workflow builds and self-tests Linux and Windows artifacts in
  both BMI2 and portable variants, checks for GNAT runtime dependencies, and
  attaches the four archives plus `SHA256SUMS`.

## Compatibility notes

The 1.5.0 bench counters were **455,176 / 1,784,546 / 5,214,141**. They change
because of the en-passant normalization and root-draw fix; external benchmark
scripts must use the new 1.6.0 reference counts above.

Every rejected experiment and all verification details are recorded in
`DEVELOPMENT.md`, especially sections 99–108. No strength number is inferred
from these functional and architectural changes.
