# Contribuer à BabaChess

Merci de votre intérêt pour BabaChess, un moteur d'échecs bitboard écrit en
**Ada 2012**. Ce fichier explique comment le compiler, comment le tester, et
les règles que toute modification doit respecter.

## Règles de base

BabaChess est développé avec une discipline de preuve stricte :

- **La correction avant tout.** Toute modification de la génération des coups,
  de make/unmake ou de la recherche doit garder `--selftest` au vert. Les
  comptes de perft (20 / 400 / 8 902 / 197 281 / 4 865 609) ne doivent pas
  changer.
- **L'évaluation doit rester symétrique.** `Static(mirror) = -Static` et
  `Static(startpos) = 0`. C'est vérifié par `--selftest` et par
  `scripts/sym_check.py`.
- **Aucune affirmation de force sans mesure.** Une modification censée rendre le
  moteur plus fort doit être validée par SPRT (voir plus bas). « Ça a l'air
  correct » n'est pas une preuve.
- **Les résultats négatifs mesurés sont documentés, pas cachés.** Si une idée
  n'apporte rien, on l'inscrit (le projet tient un journal de ce qui a été
  essayé puis rejeté).

## Compilation

Requiert **GNAT** (Ada 2012) et **gprbuild**.

```bash
make                       # release, ISA auto-detected from the host CPU
make portable              # generic x86-64 (software PEXT, no BMI2)
make debug                 # assertions + all warnings (the mode that warns)
make checked               # release speed with run-time checks (SPRT campaigns)
```

Ou directement :

```bash
gprbuild -P babachess.gpr -XMode=release    # -> bin/babachess
```

Tous les modes partagent `obj/` : lancez `rm -rf obj` avant de recompiler après
avoir changé de mode, sinon les chiffres de `--bench` n'ont aucun sens.

## Tests

```bash
./bin/babachess --selftest    # perft 1-5, Zobrist, FEN, search, SEE, protocol
./bin/babachess --bench 9     # 8 fixed positions at depth 9 -> nodes/time/knps
python3 scripts/sym_check.py  # evaluation symmetry, >=3000 positions
```

La CI compile `debug` avec les avertissements traités comme des erreurs
(`-gnatwe`), puis `release`, `portable` et `checked`, et lance `--selftest` sur
chacun.

## Mesurer la force (SPRT)

`scripts/sprt.sh` lance un test séquentiel entre deux binaires sur une suite
d'ouvertures équilibrée, dans les deux couleurs, avec le livre neutralisé :

```bash
scripts/sprt.sh 1+0.1 0 5 1000 7 <previous_binary> bin/babachess
```

Un match court ne prouve rien : 300 parties ne résolvent qu'environ ±30 Elo.
Utilisez au moins 1 000 parties (deux graines indépendantes pour un petit
effet). Voir `src/doc/outils-et-tests-fr.md` et `docs/07-testing-en.md` pour la
méthode.

## Régler les paramètres

- **Texel** (`scripts/texel_extract.py`, `scripts/texel.py`) règle l'évaluation
  sur des positions calmes issues de l'auto-jeu ; le jeu de données doit venir
  des propres parties du moteur, jamais de parties humaines.
- **SPSA** (`scripts/spsa.py`) règle des marges de recherche ou un sous-ensemble
  de paramètres à partir des résultats de parties, avec le même binaire via des
  fichiers `--params`.

Tout jeu de paramètres réglé doit être confirmé par un long SPRT avant d'être
adopté.

## Documentation

- **`docs/`** — le guide général, pédagogique et bilingue *How to build a chess
  engine*, un chapitre par sujet en `-en.md` et `-fr.md`.
- **`src/doc/`** — la référence technique de ce moteur (en français).
- Gardez `README-fr.md` (anglais) et `README-fr.md` synchronisés.

## Style

- Ada 2012 ; respectez le nommage existant et la convention fichier/unité
  (`BBChess.Search.PV` -> `bbchess-search-pv.adb`).
- Ne masquez jamais une erreur de type, ne laissez jamais un gestionnaire
  d'exception vide.
- Gardez le chemin chaud exempt d'allocation par nœud et de tout travail qui
  modifierait involontairement l'arbre de recherche.
- Ne commitez pas les fichiers générés (`obj/`, `bin/`, `*.o`, `*.ali`, `*.pgn`,
  le livre `.bin`).

## Licence

En contribuant, vous acceptez que votre contribution soit publiée sous la
licence du projet : **GPL-3.0-or-later** (voir `LICENSE`).
