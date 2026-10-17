# 7. Tests et réglage

Un moteur d'échecs se casse facilement sans qu'on s'en aperçoive : un patch peut
être rapide, élégant et faux, et un réglage d'évaluation peut sembler meilleur et
quand même faire perdre des Elo. Les tests sont la discipline qui garde un projet
honnête, et l'ordre est figé : la correction d'abord, le coût ensuite, la force en
dernier. Ce chapitre parcourt les instruments qui l'imposent, les deux tuners, et
les règles qui empêchent de se raconter des histoires. BabaChess sert d'exemple.

## 7.1 La correction d'abord : perft et autotests

La première ligne de défense est le **perft** : un compte de nœuds obtenu en
parcourant tous les coups légaux jusqu'à une profondeur fixée, généralement cinq
ou six depuis la position initiale. Ses valeurs publiées (20, 400, 8 902, 197 281
et 4 865 609 aux profondeurs 1 à 5) font office d'oracle externe, et un compte
faux est un bug de règles (légalité, roque, prise en passant, promotion), jamais
une amélioration de force.

Autour du perft se trouve une batterie interne : primitives bitboard, hachage
Zobrist, allers-retours de coups empaquetés, validation FEN, cohérence de la
recherche, répétition et SEE. Un seul échec doit tout arrêter. BabaChess la lance
avec `./bin/babachess --selftest` (146 vérifications, code de sortie non nul en
cas d'échec), pilotée par `BBChess.Self_Tests` (`src/bbchess-self_tests.adb`) et
comptée par `BBChess.Test_Harness` ; `scripts/perft_suite.sh` compare le perft, et
`--perft <FEN> <profondeur>` l'expose en usage manuel.

## 7.2 La symétrie de l'évaluation

On miroite le plateau, on échange les couleurs et on inverse le camp au trait, et
le score doit changer de signe ; une erreur de signe ou un facteur blanc/noir
oublié se voit aussitôt. La subtilité est le bonus de tempo : un noyau symétrique
comme `Static` de BabaChess est antisymétrique, mais `Evaluate` ajoute un bonus
pour le camp au trait et ne l'est **pas**. La symétrie se vérifie donc sur
`Static`, jamais sur le score final. `scripts/sym_check.py` teste des milliers de
positions via `--eval-fens` sans tolérer le moindre écart ; `--selftest` couvre la
position initiale et des FEN miroir.

## 7.3 Régression déterministe : les comptes de nœuds du banc

Un **banc** est bon marché et corrélé à la correction et à la vitesse : des
positions fixes cherchées à profondeur fixe avec la table de transposition
réinitialisée, rapportant nœuds, temps et nœuds par seconde. Le travail est
déterministe, donc deux binaires produisent des nombres exactement comparables,
et un compte qui bouge est une empreinte d'arbre de recherche modifié. Le banc est
un **garde de non-régression**, pas une cible. `Run_Bench` de BabaChess cherche
huit FEN fixes avec `--bench [profondeur]` (défaut 8) ; `release` et `portable`
partagent `obj/`, donc changez de build avec `rm -rf obj` avant de comparer.

## 7.4 Mesurer la force : les parties en auto-jeu

Rien de ce qui précède ne dit si le moteur joue mieux ; seules les parties le
disent. On ne peut pas faire confiance à un moteur pour juger ses propres coups,
donc le test oppose deux moteurs dans des conditions identiques (même temps et
incrément, ou même budget de nœuds), la construction précédente comme référence et
la construction patchée comme candidate. Un A/B à taille fixe de quelques dizaines
de parties donne des écarts contradictoires (environ plus ou moins 65 à 80 Elo),
assez pour tromper et jamais assez pour trancher ; la réponse est un test
séquentiel (7.6).

## 7.5 Ouvertures, couleurs, livre et temps fixé

Une partie depuis la position initiale est biaisée (les Blancs marquent environ 70
pour cent), donc utilisez une suite d'ouvertures : une liste de positions
(BabaChess lit `openings/openings.epd`) qui place les deux moteurs dans des
milieux de partie variés, chaque ouverture jouée **deux fois, couleurs inversées**,
pour qu'aucun moteur ne profite du choix. Neutralisez le livre des deux côtés,
sinon un binaire trouve silencieusement `books/book.bin` et l'autre non, et fixez
les conditions : même cadence, ou un nombre de nœuds fixe par coup (ce qui supprime
la dépendance à la vitesse du processeur et au mode de build). BabaChess n'honore
un plafond de nœuds par coup que sur son chemin UCI (`go nodes`).

## 7.6 Le SPRT et pourquoi les matchs courts ne veulent rien dire

Le SPRT (*Sequential Probability Ratio Test*) est l'outil de décision. Au lieu
d'un nombre fixe de parties, il surveille les preuves partie après partie et
s'arrête dès qu'une hypothèse est acceptée : **H0**, la candidate n'est pas plus
forte de `elo0` (un rejet, FAIL) ; ou **H1**, la candidate est plus forte d'au
moins `elo1` (une acceptation, PASS). Après chaque partie, un rapport de
vraisemblance logarithmique (LLR) est comparé à deux bornes,
`ln((1-beta)/alpha)` et `ln(beta/(1-alpha))`, valant environ plus ou moins 2,944
quand `alpha = beta = 0,05`. Franchissez la borne haute et H1 est acceptée, la
borne basse et H0 est acceptée, sinon le test est **INCONCLUSIVE** au plafond, si
bien qu'un verdict est une conclusion à un niveau de confiance connu.

Les matchs courts ne veulent rien dire à cause de la résolution. Un match de 40
parties a une barre d'erreur d'environ plus ou moins 87 Elo ; 300 parties donnent
environ plus ou moins 33 à 36 Elo ; seules plusieurs centaines à un millier de
parties résolvent les petits effets. Un match HEAD contre HEAD de binaires
identiques peut même afficher un faux écart dû au seul bruit, donc ne concluez
**jamais** « neutre » ou « négatif » à partir de quelques parties.

BabaChess pilote cela via `scripts/sprt.sh`, qui enveloppe `cutechess-cli -sprt`,
joue la suite d'ouvertures dans les deux couleurs, neutralise le livre pour le
match et le restaure à la sortie, et imprime un verdict avec des codes de sortie
PASS (0), FAIL (1), INCONCLUSIVE (2). Pour valider un patch, passez le binaire
précédent comme référence ; se comparer à une référence lointaine passe
instantanément.

## 7.7 Le réglage Texel sur positions calmes

Étant donné des positions au résultat connu, quels paramètres font que
l'évaluation s'accorde le plus souvent avec elles ? Le **réglage Texel** en fait
une régression : passer chaque évaluation statique par une courbe logistique,
minimiser l'erreur quadratique moyenne contre le résultat de la partie (1, 0,5 ou
0 du point de vue des Blancs), puis ajuster les paramètres par descente de
coordonnées, en ne gardant un changement que s'il abaisse l'erreur. Le piège est
le jeu de données : des positions tirées d'une partie en cours corrèlent
l'évaluation avec le résultat de toute la partie, donc ne gardez que des positions
**calmes** (ni capture, ni échec), où l'évaluation veut dire quelque chose, et
réservez un ensemble de validation pour éviter le surapprentissage.

L'avertissement est qu'une erreur plus basse n'est pas un moteur plus fort : le
jeu réglé doit être re-validé en vraies parties. BabaChess se règle via
`--eval-fens` (évaluations statiques), `--dump-params` (scalaires) et `--params`
(charge un jeu sans rebuild) ; `scripts/texel.py` exécute la descente et
`scripts/texel_extract.py` construit un jeu de positions calmes en auto-jeu.

## 7.8 Le réglage SPSA sur les paramètres

Texel optimise un proxy ; le **SPSA** (*Simultaneous Perturbation Stochastic
Approximation*) optimise la vraie chose, le résultat des parties. Il enveloppe le
même binaire avec différents fichiers de paramètres, donc aucun rebuild n'est
nécessaire : chaque itération perturbe tous les paramètres réglables à la fois
dans une direction aléatoire, joue un match entre les deux moteurs perturbés, et
les pousse le long du gradient mesuré (`c_k = c0 / (k+1)^0,101`,
`a_k = a0 / (k+1+A)^0,602`). Il est plus lent et plus bruité que Texel, car chaque
estimation coûte un match, et un run utile dure des heures. Il propose et le SPRT
dispose : le jeu final repasse par le même SPRT de ~300 parties à cadence réelle.
`scripts/spsa.py` de BabaChess perturbe une liste choisie de paramètres
d'évaluation (matériel exclu), avec le livre neutralisé et restauré.

## 7.9 Les règles d'or

1. `--selftest` vert et perft inchangé : obligatoire avant tout match.
2. Toute évaluation nouvelle reste symétrique (`Static` au départ = 0).
3. Ne rien trancher sous environ 300 parties ; sur des durées courtes, la barre
   d'erreur écrase l'effet.
4. `scripts/sprt.sh` est l'outil de décision ; les autres matchs sont des
   thermomètres bruités.
5. `--bench` et le diagnostic multi-positions sont des gardes de non-régression,
   pas des cibles ; on n'optimise jamais une position isolée.
6. Un tuner qui abaisse son erreur ne mérite l'adoption que par un SPRT.

## 7.10 BabaChess comme exemple

Le flux de travail est une boucle : changer le code, construire `release`, lancer
`./bin/babachess --selftest`, comparer `--bench 9`, puis décider avec
`scripts/sprt.sh` en passant le binaire précédent comme référence. Les fichiers
qui soutiennent tout cela sont `BBChess.Self_Tests`
(`src/bbchess-self_tests.adb`), `scripts/perft_suite.sh`, `scripts/sym_check.py`,
`scripts/sprt.sh`, `scripts/texel.py` et `scripts/spsa.py`. Chaque instrument est
décrit dans `src/doc/outils-et-tests.md`.

## Voir aussi

- `src/doc/outils-et-tests.md` : la documentation de référence des outils de test
  et de mesure (`--selftest`, perft, `--bench`, `--eval-fens`, `--params`, SPRT,
  tuners).
- `src/bbchess-self_tests.adb` : la batterie interne (`BBChess.Self_Tests`),
  lancée par `--selftest` et comptée par `BBChess.Test_Harness`.
- `AGENTS.md` : les modes de construction, la règle d'or, et la façon de lancer
  le banc et les matchs.
- `scripts/` : `perft_suite.sh`, `sym_check.py`, `sprt.sh`, `texel.py` et
  `spsa.py`.
- Chapitres voisins : `06-endgame-tablebases-fr.md` et
  `08-roadmap-and-limits-fr.md`.
- Perft : <https://www.chessprogramming.org/Perft> ; SPSA :
  <https://www.chessprogramming.org/SPSA> ; Réglage automatique (dont Texel) :
  <https://www.chessprogramming.org/Automated_Tuning> ; Tests de moteurs :
  <https://www.chessprogramming.org/Testing>.
