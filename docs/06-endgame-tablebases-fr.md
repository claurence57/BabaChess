# 6. Les tables de finales

Les finales révèlent les limites des heuristiques : une KQvK gagnée passe à la
trappe, une forteresse est mal jugée, la règle des 50 coups glisse hors du champ.
Les tables de finales y répondent directement : au lieu d'estimer une position,
elles en renvoient le résultat exact, gain, nulle ou perte. Ce chapitre couvre la
notion de table, ses mesures (WDL, DTZ, DTM), le format Syzygy, le sondage en
recherche et à la racine, et la subtilité des 50 coups. BabaChess sert d'exemple.

## 6.1 Ce que sont les tables de finales

Une table de finales est un ensemble de résultats **précalculés** : pour chaque
position légale à peu de pièces, elle stocke l'issue théorique, résolue à rebours
depuis le mat. Là, la réponse est une preuve, pas une évaluation.

Le gain est important : au lieu de parcourir un sous-arbre et de faire confiance
à une heuristique, le moteur pose une question et obtient la vérité, là où
l'évaluation est justement la plus faible. Le coût, c'est l'espace : une table ne
va que jusqu'à N pièces et stocke la valeur de chaque position, pas un plan.

## 6.2 WDL, DTZ, DTM

Trois mesures répondent à des questions différentes ; les confondre provoque de
vrais bogues.

- **WDL** (*Win / Draw / Loss*) : résultat théorique vu du camp au trait, en
  ignorant la règle des 50 coups. Elle dit *si* une position est gagnée, pas en
  combien de temps.
- **DTZ** (*Distance To Zero*) : demi-coups jusqu'au prochain **coup remettant le
  compteur à zéro** (coup de pion ou capture) en conservant le résultat WDL ; la
  mesure liée à la règle des 50 coups.
- **DTM** (*Distance To Mate*) : demi-coups jusqu'au mat. Les anciens formats
  (Nalimov, Edwards) l'exposaient ; Syzygy non.

Le WDL suffit à élaguer, car il donne le score exact d'un sous-arbre ; le DTZ
convertit un gain une fois le compteur lancé. Un schéma courant, et celui de
BabaChess, sonde le WDL partout et garde le DTZ pour la racine.

Une nuance : Fathom renvoie cinq codes, `0` perte, `1` blessed loss, `2` nulle,
`3` cursed win, `4` gain. Un **cursed win** n'est gagné qu'en ignorant la règle
des 50 coups, un **blessed loss** en est le miroir ; tous deux sont des nulles en
pratique.

## 6.3 Le format Syzygy et le nombre de pièces

**Syzygy** est le standard moderne : deux fichiers par configuration, `.rtbw`
pour le WDL et `.rtbz` pour le DTZ, compressés via les symétries de l'échiquier et
une indexation compacte. Le jeu 3-4-5 pièces tient dans environ un gigaoctet.

Les nombres montent en flèche : 3-4-5 pièces environ 1 Go, six environ 150 Go,
sept environ 18 To. Les fichiers WDL sont bien plus petits que les DTZ, car le WDL
n'a besoin que de trois valeurs et le DTZ d'une distance.

## 6.4 Sonder pendant la recherche

Sonder, c'est interroger le chargeur sur la valeur d'une position. La sonde se
place près du haut de la fonction récursive, après le test de répétition : une
position résolue renvoie un score exact sans développer d'enfant. Trois gardes
l'encadrent : tables chargées et activées ; pas plus de pièces que le plus grand
jeu chargé ; **aucun droit de roque**, que le WDL ne décrit pas.

En cas de succès, l'issue remplace le score, encodée juste sous le mat et ajustée
par le pli courant, si bien que le moteur préfère le gain le plus proche et
retarde la perte ; la recherche s'arrête dès qu'un tel score revient. En cas
d'échec, elle continue comme si aucune table n'existait.

## 6.5 Sonder à la racine

Le WDL dit qu'une position est gagnée, pas comment la gagner en cinquante coups.
Le remède est une **sonde à la racine** : le moteur demande un coup qui conserve
le résultat WDL tout en minimisant la distance à zéro. Rare par construction
(plus lourde que le WDL, exigeant des données DTZ, non sûre en multithread), elle
s'exécute une fois, avant la recherche, uniquement dans la zone de finale.

## 6.6 La règle des 50 coups et pourquoi le DTZ compte

Le WDL est calculé avec le compteur de demi-coups à zéro : un « gain » signifie
donc gagné si la règle des 50 coups ne mord jamais, ce qui n'est pas la même chose
que gagné selon les règles. Un moteur à WDL seul peut savoir une position
gagnante, avancer vers elle, ne jamais jouer de coup de pion ni de capture, et
être nul à cinquante : la valeur juste, le gain perdu.

Le **DTZ** comble l'écart : un coup remettant le compteur à zéro le réinitialise
et un moteur conscient du DTZ préfère la ligne qui le réinitialise à temps. Le
compteur faisant partie de l'état du jeu, la sonde reçoit sa valeur courante, et
un résultat cursed ou blessed en tient compte. Un jeu parfait sous la règle exige
plus fin qu'une seule valeur DTZ, mais minimiser la distance à zéro et traiter
cursed et blessed comme des nulles est l'approximation saine.

## 6.7 Utiliser une bibliothèque de sondage, taille et disponibilité

Personne ne réimplémente Syzygy pour livrer un moteur ; le décodage est délicat
et propice aux erreurs. **Fathom** (MIT) est le choix courant, un petit lecteur C
avec quelques points d'entrée pour le WDL et le DTZ à la racine (python-chess
offre un équivalent pour l'outillage). BabaChess vendore Fathom derrière une
liaison mince, ce qui garde le moteur portable et la licence nette (`NOTICE.md`).

La disponibilité compte : 3-4-5 pièces est facile à stocker, six pièces un
engagement disque sérieux, sept une affaire de plusieurs téraoctets. Beaucoup de
moteurs restent inertes par défaut : sans fichiers, la sonde n'est jamais tentée,
et comme les fichiers sont mappés en mémoire et lus à la demande, sonder coûte
aussi de la latence disque.

## 6.8 Limites

- **Pas de roque.** Les tables WDL et DTZ ne décrivent que les positions sans
  droit de roque.
- **Plafond de pièces.** Au-delà du plus grand jeu chargé, la sonde est muette.
- **Subtilité des 50 coups.** Sans DTZ, un « gain » peut encore être nul.
- **Valeur, pas plan.** Ni plan lisible, ni distance au mat.
- **Lié au disque.** Les grands jeux demandent de l'espace et un stockage rapide.

## 6.9 BabaChess comme exemple

BabaChess sonde Syzygy via `BBChess.Syzygy` (`src/bbchess-syzygy.ads` / `.adb`),
une liaison mince au-dessus du wrapper C `src/fathom/bbchess-tbwrap.c`, lui-même
au-dessus de **Fathom** vendoré (MIT, `src/fathom/` ; voir `NOTICE.md`). L'API
offre `Init (Path, Ok)`, `Free`, `Largest`, `Enabled`, `Probe_WDL (Position)`.

Le **WDL est sondé dans la recherche**, en haut de `Negamax` après le test de
répétition, gardé par `Enabled` et un nombre de pièces inférieur ou égal à
`Largest`. Les positions avec roque sont refusées et le compteur de demi-coups est
envoyé à zéro, comme le suppose le WDL. Un gain devient `TB_Win - Ply`
(`TB_Win = 20_000`, sous le mat), une perte sa négation, et les codes blessed,
cursed et nulle se replient sur `0`, une lecture prudente. Avec les tables
3 pièces, une KQvK blanche renvoie 19999 dès la profondeur 2.

Le **DTZ est optionnel à la racine.** `Has_DTZ` et `Probe_Root_Move` encapsulent
`tb_probe_root` de Fathom ; activé par `S_Syzygy_Root` (`--params` avec
`S_SYZYGY_ROOT 1`), désactivé par défaut, il ne se déclenche que dans la zone des
50 coups (demi-coups au moins `S_Syzygy_Root_Min_Hm`, 80 par défaut) avec au plus
`S_Syzygy_Root_Max_Pieces` pièces. Non sûr en multithread, il s'exécute une fois à
la racine, le compteur de demi-coups passé comme contexte des 50 coups.

La configuration est tolérante. `--syzygy <dossier>`, ou UCI `setoption name
SyzygyPath value <dossier>`, désigne les tables, le chemin pouvant lister
plusieurs répertoires séparés par le séparateur de la plateforme (`:` sous Unix,
`;` sous Windows). Un chemin invalide n'est pas fatal : `Init` renvoie
`Ok = False`, `Largest` reste 0, `Enabled` est faux, et le moteur joue sans
tables. `--selftest` et `--bench` ne les sondent jamais.

## Voir aussi

- `src/doc/finales.md` : la documentation de référence de la couche tablebases.
- `src/bbchess-syzygy.adb`, `src/bbchess-syzygy.ads` : la liaison Ada.
- `src/fathom/` : la sonde Fathom vendorée (MIT) ; voir `src/fathom/LICENSE`.
- Syzygy Bases : <https://www.chessprogramming.org/Syzygy_Bases>.
- `src/doc/README.md` : l'index de la documentation technique.
- Chapitre voisin : `05-opening-book-fr.md` ; les autres sont dans `docs/`.
