# How to build a chess engine — guide

This guide explains, in a **general and pedagogical** way, how a chess engine is
developed: the concepts, the components and the trade-offs. It uses
**BabaChess** (a bitboard engine in Ada 2012) as a concrete example, with
pointers to the code (`src/`) and to the technical documentation (`src/doc/`).

It does **not** describe the project's history or development steps: those are
internal logs (`DEVELOPMENT.md`, `CHANGELOG.md`).

Every chapter exists in **English** (`*-en.md`) and in **French** (`*-fr.md`).

## Table of contents

1. [Introduction](01-introduction-en.md) — what an engine is, its components, the protocols.
2. [Board representation and move generation](02-board-and-movegen-en.md) — representations, bitboards, legality, perft.
3. [Evaluation](03-evaluation-en.md) — material, piece-square tables, phase, positional terms, tuning.
4. [Search](04-search-en.md) — negamax/alpha-beta, move ordering, pruning, quiescence.
5. [Opening book](05-opening-book-en.md) — Polyglot format, probing, free sources.
6. [Endgame tablebases](06-endgame-tablebases-en.md) — Syzygy WDL/DTZ, the 50-move rule.
7. [Testing and tuning](07-testing-en.md) — perft, self-tests, symmetry, SPRT, Texel/SPSA.
8. [Roadmap and limits](08-roadmap-and-limits-en.md) — from a naive engine to a strong one, the classic ceiling, NNUE.

## In French

1. [Introduction](01-introduction-fr.md)
2. [Plateau et génération de coups](02-board-and-movegen-fr.md)
3. [Évaluation](03-evaluation-fr.md)
4. [Recherche](04-search-fr.md)
5. [Livre d'ouvertures](05-opening-book-fr.md)
6. [Tables de finales](06-endgame-tablebases-fr.md)
7. [Tests et réglage](07-testing-fr.md)
8. [Feuille de route et limites](08-roadmap-and-limits-fr.md)

Index français : [README-fr.md](README-fr.md).

## Technical documentation

The details of **this engine** (data structures, evaluation terms, search
thresholds, implementation choices) live in `src/doc/` (in French): `README.md`,
`bitboards.md`, `evaluation.md`, `recherche.md`, `finales.md`, `ouvertures.md`,
`outils-et-tests.md`, `build-and-cpu.md`.
