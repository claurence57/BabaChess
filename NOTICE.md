# NOTICE — provenance and licences

## Origin

**BabaChess** is a **fork of [AdaChess](https://github.com/adachess/AdaChess)**.

It is derived from AdaChess's **bitboard** engine (referred to as **BB** in the
AdaChess sources and journals): the Ada 2012 sources under `src_bb/` (packages
`BBChess.*`), the C shim `src_bb/bbchess-bits.c`, the vendored Fathom probe
`src_bb/fathom/`, the measurement scripts under `scripts/`, the opening suite
`openings/openings.epd`, the diagnostic bench `bench/diag.tsv`, and the
engineering documentation (`DEVELOPMENT.md`, `CHANGELOG.md`,
`CHANGELOG_TECHNIQUE.md`, `NOTES_TUNING.md`, `src_bb/doc/`).

The fork point is the AdaChess commit that established the "no further meaningful
improvement" threshold for the engine (AdaChess `DEVELOPMENT.md` §49). The full
development history is preserved in this repository's git history, including the
AdaChess commits it was forked from.

The original **mailbox** engine of AdaChess (sources `src/`, project
`adachess.gpr`) is still **present in this tree as a legacy perft oracle and
reference opponent**, but it is **not a development target** (see `AGENTS.md`). It
is left untouched and is a candidate for removal if a BB-only tree is wanted.

## Licence

BabaChess is distributed under the **GNU General Public License, version 3 or
later** (GPL-3.0-or-later) — see [`LICENSE`](LICENSE). This is inherited from
AdaChess, which is GPL-licensed.

### Third-party components under MIT

The following components are reused from third parties under the **MIT**
licence and are **not** covered by the GPL:

| Component | Path | Licence |
|---|---|---|
| Fathom — Syzygy tablebase probe | `src_bb/fathom/` | MIT — see `src_bb/fathom/LICENSE` |
| `stdendian.h` (bundled in Fathom) | `src_bb/fathom/stdendian.h` | MIT |

The MIT licence text is included at `src_bb/fathom/LICENSE`. The MIT terms apply
to those files only; distributing BabaChess as a whole is governed by the GPL for
everything else.

### First-party C code

`src_bb/bbchess-bits.c` (the portable software-PEXT fallback) was written for
this project (originally within AdaChess) and carries **no** MIT notice, so it
falls under the project's GPL licence.
