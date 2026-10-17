# Construire un moteur d'échecs — guide

Ce guide explique, de façon **générale et pédagogique**, comment on développe un
moteur d'échecs : les concepts, les composants et les compromis. Il prend
**BabaChess** (moteur bitboard en Ada 2012) comme exemple concret, avec des
renvois vers le code (`src/`) et vers la documentation technique (`src/doc/`).

Il ne décrit **pas** l'historique ni les étapes de développement du projet : ce
sont des journaux internes (`DEVELOPMENT.md`, `CHANGELOG.md`).

Chaque chapitre existe en **français** (`*-fr.md`) et en **anglais** (`*-en.md`).

## Sommaire

1. [Introduction](01-introduction-fr.md) — ce qu'est un moteur, ses composants, les protocoles.
2. [Plateau et génération de coups](02-board-and-movegen-fr.md) — représentations, bitboards, légalité, perft.
3. [Évaluation](03-evaluation-fr.md) — matériel, tables pièce-case, phase, termes positionnels, réglage.
4. [Recherche](04-search-fr.md) — négamax/alpha-bêta, ordonnancement, élagages, quiescence.
5. [Livre d'ouvertures](05-opening-book-fr.md) — format Polyglot, sondage, sources libres.
6. [Tables de finales](06-endgame-tablebases-fr.md) — Syzygy WDL/DTZ, règle des 50 coups.
7. [Tests et réglage](07-testing-fr.md) — perft, self-tests, symétrie, SPRT, Texel/SPSA.
8. [Feuille de route et limites](08-roadmap-and-limits-fr.md) — du moteur naïf au moteur fort, plafond classique, NNUE.

## En anglais

1. [Introduction](01-introduction-en.md)
2. [Board representation and move generation](02-board-and-movegen-en.md)
3. [Evaluation](03-evaluation-en.md)
4. [Search](04-search-en.md)
5. [Opening book](05-opening-book-en.md)
6. [Endgame tablebases](06-endgame-tablebases-en.md)
7. [Testing and tuning](07-testing-en.md)
8. [Roadmap and limits](08-roadmap-and-limits-en.md)

English index: [README-en.md](README-en.md).

## Documentation technique

Les détails de **ce moteur** (structures, termes, seuils, choix d'implémentation)
sont dans `src/doc/` (en français) : `README-fr.md`, `bitboards-fr.md`, `evaluation-fr.md`,
`recherche-fr.md`, `finales-fr.md`, `ouvertures-fr.md`, `outils-et-tests-fr.md`,
`build-and-cpu-fr.md`.
