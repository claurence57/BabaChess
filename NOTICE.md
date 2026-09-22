# NOTICE — provenance and licences

## Origin

**BabaChess** is a **fork of [AdaChess](https://github.com/adachess/AdaChess)**.

It is derived from AdaChess's **bitboard** engine (referred to as **BB** in the
AdaChess sources and journals): the Ada 2012 sources under `src/` (packages
`BBChess.*`), the C shim `src/bbchess-bits.c`, the vendored Fathom probe
`src/fathom/`, the measurement scripts under `scripts/`, the opening suite
`openings/openings.epd`, the diagnostic bench `bench/diag.tsv`, and the
engineering documentation (`DEVELOPMENT.md`, `CHANGELOG.md`,
`CHANGELOG_TECHNIQUE.md`, `NOTES_TUNING.md`, `src/doc/`). In the AdaChess
repository these sources lived under `src_bb/`; the fork renamed that directory
to `src/`.

The fork point is the AdaChess commit that established the "no further meaningful
improvement" threshold for the engine (AdaChess `DEVELOPMENT.md` §49). The full
development history is preserved in this repository's git history, including the
AdaChess commits it was forked from.

The original **mailbox** engine of AdaChess (packages `Chess.*`) has been
**removed** from this repository; it remains available upstream in AdaChess. Its
perft values are still used as the fork's validation reference.

## Licence

BabaChess is distributed under the **GNU General Public License, version 3 or
later** (GPL-3.0-or-later) — see [`LICENSE`](LICENSE). This is inherited from
AdaChess, which is GPL-licensed.

### Third-party components under MIT

The following components are reused from third parties under the **MIT**
licence and are **not** covered by the GPL:

| Component | Path | Licence |
|---|---|---|
| Fathom — Syzygy tablebase probe | `src/fathom/` | MIT — see `src/fathom/LICENSE` |
| `stdendian.h` (bundled in Fathom) | `src/fathom/stdendian.h` | MIT |

The MIT licence text is included at `src/fathom/LICENSE`. The MIT terms apply
to those files only; distributing BabaChess as a whole is governed by the GPL for
everything else.

### First-party C code

`src/bbchess-bits.c` (the portable software-PEXT fallback) was written for
this project (originally within AdaChess) and carries **no** MIT notice, so it
falls under the project's GPL licence.
