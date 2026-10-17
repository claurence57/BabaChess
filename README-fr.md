# BabaChess

[![CI](https://github.com/claurence57/BabaChess/actions/workflows/ci.yml/badge.svg)](https://github.com/claurence57/BabaChess/actions/workflows/ci.yml)

**English: [README-fr.md](README-fr.md).** Guide bilingue *Construire un moteur d'échecs* : [docs/README-fr.md](docs/README-fr.md).

> **BabaChess est un fork d'[AdaChess](https://github.com/adachess/AdaChess).**
> Il est né du fork du projet AdaChess, puis de la conversion de la
> représentation de l'échiquier de **mailbox** en **bitboard**. Après de
> nombreuses optimisations, il est devenu un projet à part entière. BabaChess
> est désormais l'unique cible de développement ; le moteur **mailbox** d'origine
> d'AdaChess a été **supprimé** de ce dépôt.
>
> Voir `NOTICE.md` pour la provenance complète et les détails de licence.

BabaChess est un moteur d'échecs écrit en **Ada 2012**, utilisant une
représentation d'échiquier par **bitboards**. Il se compile avec `gprbuild` et
parle à la fois **XBoard/Winboard** et **UCI**.

> **Note sur le nom.** BabaChess n'a aucun lien avec les autres projets d'échecs
> au nom similaire : **BabChess** (un moteur UCI en C++) et **BabasChess** (le
> client graphique FICS). Ce projet est un moteur bitboard écrit en Ada, issu du
> fork d'AdaChess.

## Fonctionnalités

- Génération de coups par bitboards (attaques glissantes PEXT/BMI2, avec un
  repli logiciel PEXT portable pour les processeurs sans BMI2).
- Recherche à variation principale (PVS) avec fenêtres d'aspiration ; table de
  transposition ; ordonnancement des coups (hash, MVV-LVA, killers, history,
  contre-coup et historique de continuation sur 1 demi-coup) ; réductions de
  coups tardifs et élagage (null-move adaptatif, futility, razoring, LMP),
  extensions d'échec, élagage par distance de mat.
- Recherche de quiescence bornée avec évaluation statique des échanges (SEE) et
  élagage delta.
- Évaluation artisanale à interpolation (milieu de partie/finale).
- Multithreading **Lazy SMP** (table de transposition partagée, heuristiques par
  thread), jusqu'à 16 threads.
- Livre d'ouvertures **Polyglot** et tables de finales **Syzygy** (via une sonde
  Fathom intégrée).
- Gestion du temps souple/stricte avec prise en charge de `movestogo`.
- Suite d'autotests intégrale (146 vérifications, compteur réussite/échec avec
  code de sortie non nul en cas d'échec) : perft 1-5, Zobrist, coups empaquetés,
  validation FEN, recherche, répétition, SEE, clés Polyglot, durcissement du
  fichier de livre et analyse du protocole.

## Compilation

Nécessite **GNAT** (Ada 2012) et **gprbuild**.

```bash
gprbuild -P babachess.gpr -XMode=release    # -> bin/babachess  (POPCNT/BMI2/PEXT)
gprbuild -P babachess.gpr -XMode=checked    # -> bin/babachess  (release + runtime checks)
gprbuild -P babachess.gpr -XMode=portable   # -> bin/babachess  (any x86-64)
gprbuild -P babachess.gpr -XMode=debug      # -> bin/babachess  (assertions + warnings)
```

- `release` compile avec `-mpopcnt -mbmi -mbmi2` et inline l'intrinsèque PEXT
  (`_pext_u64`) pour les attaques glissantes ; il **nécessite** un processeur
  avec BMI2/POPCNT.
- `checked` est aussi rapide que `release` (`-O3 -gnatN -flto`) mais **conserve
  les vérifications à l'exécution** (`-gnata`, pas de `-gnatp`) : les assertions,
  les contrôles d'indice et d'intervalle sont actifs. Il est environ 11 % plus
  lent, et c'est le mode à utiliser pour les **longues campagnes SPRT**
  (comportement défini plutôt que comportement indéfini silencieux).
- `portable` abandonne ces commutateurs et utilise le repli logiciel PEXT dans
  `bbchess-bits.c`, il tourne donc sur n'importe quel processeur x86-64 (~25 %
  plus lent).
- `debug` active les assertions Ada et tous les avertissements, et c'est le seul
  mode qui les porte.

`release` est le mode à distribuer ; `checked` est le mode avec lequel valider.

Voir `src/doc/build-and-cpu-fr.md` pour les commutateurs de compilation exacts et
l'historique d'optimisation CPU.

## Tests

```bash
./bin/babachess --selftest    # 146 checks: perft 1-5, Zobrist, FEN, search,
                              # SEE, Polyglot (+ book hardening, protocol)
./bin/babachess --bench 9     # 8 fixed positions at depth 9 -> nodes/time/knps
```

La **règle d'or** pour toute modification : `--selftest` doit rester vert (les
comptes de perft ne doivent pas changer) et l'évaluation doit rester symétrique.

## Téléchargements

Les archives de version sont nommées `babachess-<version>-<os>-x86_64-<build>`,
avec `os` = `linux` ou `windows` et `build` = `bmi2` (nécessite BMI2+POPCNT, soit
Intel Haswell 2013 / AMD Zen 2017 ou plus récent) ou `portable` (tout processeur
x86-64, PEXT logiciel, ~25 % plus lent). Choisir **une** :

| Votre processeur | Choisir |
|---|---|
| Intel/AMD moderne (BMI2 + POPCNT) | `…-bmi2` |
| x86-64 plus ancien, ou en cas de plantage pour instruction illégale | `…-portable` |
| AMD Zen 1 / Zen 2 (PEXT microcodé) | essayez les deux ; `portable` est souvent plus rapide |

Vérifiez l'intégrité par rapport au fichier `SHA256SUMS` publié. Chaque archive
contient le binaire, `LICENSE`, `NOTICE.md`, `src/fathom/LICENSE`, `README-fr.md`,
`RELEASE_NOTES_<version>.md` et le livre intégré à `books/book.bin`.

> **Remarque.** Les étiquettes historiques `bb-1.0` / `bb-2.0` appartiennent à
> AdaChess-BB **avant** le fork et ne font pas partie de la numérotation de
> BabaChess ; BabaChess commence à `1.0.0`.

## Démarrage rapide avec une interface graphique

BabaChess est un moteur en ligne de commande UCI/XBoard ; configurez-le comme
moteur externe dans une interface graphique.

- **Arena (Windows) :** `Engines → Install New Engine…`, choisir `babachess.exe`,
  puis **UCI**.
- **Cute Chess / cutechess-cli :** interface graphique : ajoutez un moteur
  (protocole UCI). Ligne de commande :
  `cutechess-cli -engine cmd=./babachess -engine cmd=<opponent> -each proto=uci tc=60+0.6 -games 2`
- **Lucas Chess (Windows) :** `Competition → Engines… → New engine`, protocole
  **UCI**.
- **WinBoard / XBoard :** ajoutez un moteur et sélectionnez le protocole **UCI**
  (ou laissez-le négocier XBoard), par exemple
  `xboard -fcp ./babachess -fd . -scp ./babachess -sd . -tc 5 -inc 0.1`.

Le moteur **trouve `books/book.bin` tout seul** (à côté de l'exécutable, un
répertoire au-dessus, `./books/`, `~/ .babachess/book.bin`) ; remplacez-le par
`--book <file>` ou l'option UCI `BookFile`.

Vérification de bon fonctionnement :

```bash
printf 'uci\nquit\n' | ./babachess    # -> id name BabaChess <version> ... uciok
./bin/babachess --version             # -> BabaChess <version>
./bin/babachess --selftest            # -> 146 checks passed, 0 failed
```

## Utilisation du moteur

Configurez-le dans n'importe quelle interface graphique prenant en charge le
protocole XBoard ou UCI. Les options en ligne de commande incluent
`--threads N` (aussi `-TN` / `--thread=N`), `--book <file>`,
`--syzygy <dir>`, `--params <file>`, `--dump-params`, `--eval-fens <file>`,
`--bench [depth]`, `--perft <FEN> <depth>`, `--selftest` et `--version`.

Options UCI : `Hash` (inerte, la taille est fixée à la compilation ; l'option
annonce la taille réelle et avertit en cas de demande différente), `Threads`,
`OwnBook`, `BookFile`, `SyzygyPath`.

## Limitations connues

- **Le DTZ à la racine est optionnel.** Par défaut, la sonde Syzygy est WDL
  uniquement, le moteur sait donc qu'une position est gagnée mais pas la
  distance jusqu'à zéro ; dans la zone des 50 coups, il peut prendre un chemin
  plus long et manquer des gains qu'un moteur conscient du DTZ convertirait.
  Depuis 1.2.0, une sonde DTZ à la racine existe derrière `S_SYZYGY_ROOT 1`
  (`--params`), désactivée par défaut (voir `DEVELOPMENT.md` §78).
- **La table de transposition suppose le modèle mémoire x86-64.** La TT partagée
  sans verrou repose sur la sémantique total-store-order de x86-64 (trois
  `pragma Atomic`, aucune barrière explicite) et n'est **pas portable** vers ARM
  ou POWER. Les versions publiées sont x86-64 uniquement.
- **La compilation `release` nécessite BMI2/POPCNT** ; utilisez `portable` sinon.
  PEXT est microcodé et lent sur **AMD Zen 1/Zen 2**, où `portable` est souvent
  plus rapide.
- **Le passage à l'échelle de Lazy SMP plafonne autour de 8 threads** ; des
  auxiliaires supplémentaires au-delà n'apportent que peu de force.
- **Évaluation artisanale, pas de NNUE.** La sécurité du roi est un **point
  faible connu** (les tentatives d'amélioration se sont révélées négatives,
  `DEVELOPMENT.md` §17).
- **Pas de limiteur de force** (`UCI_LimitStrength`/`UCI_Elo`) ; utilisez un
  handicap de temps ou moins de `Threads` pour l'affaiblir.

## Licence

**GPL-3.0-or-later** (voir `LICENSE`), hérité d'AdaChess.

Exception : les composants **C** réutilisés de Fathom (`src/fathom/`, la sonde de
tables de finales Syzygy et son `stdendian.h` intégré) sont sous licence **MIT**,
voir `src/fathom/LICENSE`. Détails dans `NOTICE.md`.

## Crédits

- BabaChess est un fork d'**AdaChess** par le projet AdaChess
  (https://github.com/adachess/AdaChess).
- La sonde de tables de finales Syzygy utilise la bibliothèque **Fathom**
  intégrée (MIT).
- Le développement a été assisté par IA ; voir `DEVELOPMENT.md` et
  `CHANGELOG.md`.
